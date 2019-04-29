local ABOUT = {
  NAME          = "openLuup.historian",
  VERSION       = "2019.04.18",
  DESCRIPTION   = "openLuup data historian",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-19 AK Booer

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
]]

}
    
-- 2018.07.21  ensure Directory ends with '/'
-- 2018.11.26  enable historian mirroring to external Graphite and InfluxDB databases via UDP

-- 2019.04.18  remove TidyCache daemon (now done implicitly at variable creation in devices module)


local logs    = require "openLuup.logs"
local devutil = require "openLuup.devices"
local timers  = require "openLuup.timers"             -- for performance statistics
local tables  = require "openLuup.servertables"       -- for storage schema and aggregation rules
local whisper = require "openLuup.whisper"            -- for the Whisper database
local ioutil  = require "openLuup.io"                 -- for UDP (NOT the same as luup.io or Lua's io.)
local vfs     = require "openLuup.virtualfilesystem"  -- for default Graphite schema files

local lfs     = require "lfs"                         -- for mkdir(), and Graphite

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

--[[

Data Historian manipulates the in-memory variable history cache and the on-disc archive.  
The industry-standard for a time-based metrics database, Whisper, is used (as in DataYours.)
It also uses the Graphite Finder standard as an interface to the WSAPI CGI graphite_cgi,
which may then be accessed by dashboard applications or servers like Grafana.
 
The code here handles all aspects of the in-memory cache and the on-disc archive with the exception of
updating the variable cache which is done in the device module itself.

Note that ONLY numeric variable values are supported by the historian.


There are three major parts:

 CarbonCache    - an implementation of the Graphite Carbon Cache which writes data to disk
 HistoryFinder  - called by the Graphite API (in openLuup, implemented as a CGI) to find metrics
 HistoryReader  - called by the Graphite API to return metric values (from both cache and disk archives)
 
TODO: Additionally, CarbonCache is able to write non-historian Whisper files, replacing DataYours)

TODO: consider recording some internal metrics
see: https://github.com/graphite-project/carbon/blob/master/lib/carbon/instrumentation.py

--]]


local BRIDGEBLOCK = 10000   -- hardcoded VeraBridge blocksize (sorry, but easy and quick)
local Bridges               -- VeraBridge info for nodeNames and device offsets

local Directory             -- location of history database
local DYdirectory           -- location of (optional) DataYours database (to include in Finder node tree)
local DYtree = "DataYours"  -- root name of the DataYours tree for Finder

local Hcarbon, DYcarbon     -- Carbon Cache (Whisper archives) for Historian and DataYours replacement

local Graphite_UDP          -- external Graphite UDP port to mirror historian disk cache
local InfluxDB_UDP          -- ditto InfluxDB

local CacheSize             -- in-memory cache size

local Rules                 -- schema and aggregation rules   

local NoSchema = {}         -- table of schema metrics which definitely don't match schema rules

local tally = {}            -- counter for each written metric
local stats = {             -- interesting performance stats
    cpu_seconds = 0,
    elapsed_sec = 0,
    total_updates = 0,
  }

----------------------------------------
--
-- Utility functions
--


-- Find Query class factory with extended methods
local function FindQuery (pattern)

  -- iterator to expand a series list string "preamble{A,B,C}postamble{X,Y,Z}" 
  -- into a list of individual series "preambleApostambleX", etc.
  local function expansions (x)
    local function option (x, z)
      z = z or ''
      local pre, braces, post = x: match "(.-)(%b{})(.*)"   
      if braces then
        for y in braces: gmatch "[^{},]+" do
          option (post, table.concat {z, pre, y})
        end
      else
        coroutine.yield (z..x)  
      end
    end
    return coroutine.wrap (function () option (x.pattern) end)
  end
  
  -- match a single part, returning the matching pattern
  local function match_part (self, item)
    for q in expansions(self) do
    local pattern = table.concat {'^', q, '$'}    -- match ALL of query
      if item: match (pattern) then
        return q
      end
    end
  end
  
  -- match the whole lot
  local function match_all (self, item)
    local n = 0
    local Nrules = #self
    for part in item: gmatch "[^%.]+" do
      n = n + 1
      if n > Nrules then return end       -- ran out of rule parts!
      local match = self[n]: matches (part)
      if not match then return end
    end
    if n ~= Nrules then return end        -- ran out of item parts!
    return true
  end
  
  -- convert into Lua search pattern, can't use ranges [a-z]
  local function pattern_parts (p)
    -- note that this may still contain options in braces which need expanding in individual parts
    local part = {}
    p: gsub("[^%.]+", function(c) part[#part+1] = c end);
    -- have to do these substitutions separately for each part
    for i, q in ipairs (part) do
      q = q: gsub ("[%-]", "%%%1")        -- quote special character(s) ... just '-' ATM
      q = q: gsub ("%*", "%.%1")          -- '*' -> '.*'
      q = q: gsub ("%?", ".")             -- replace single character query '?' with dot '.'
      part[i] = {pattern = q, expansions = expansions, matches = match_part}
    end
    return part
  end
  
  if not pattern then return end
  local query = pattern_parts (pattern)
  query.pattern = pattern
  query.matches = match_all    -- add whole match
  return query
end


-- maps all device variables, calling a user-defined function if pattern matches
-- Note that this can be made into an iterator using coroutines (see VariablesWithHistory)
local function mapVars (fct, pattern)
  local query = FindQuery (pattern) or {}
  
  if not pattern then     -- fast-track through device variables
    for _,d in pairs (luup.devices) do
      for _,v in ipairs (d.variables) do fct (v) end
    end  
  
  else                    -- go through device, service, variable, matching pattern
    for devNo,d in pairs (luup.devices) do
      if query[1]: matches (tostring(devNo)) then
        for _,s in pairs (d.services) do
          if query[2]: matches (s.shortSid) then
            for name,v in pairs (s.variables) do
              if query[3]: matches (name) then fct (v) end
            end
          end
        end
      end
    end  
  end
end

-- ITERATOR, walks through (unsorted) VWH variables
-- usage:  for v in VariablesWithHistory () do ... end
-- or, eg: for v in VariablesWithHistory "*.*Sensor*.Current*" do ... end
-- filters by a threshold on the number of points - default is 1 (or more)
local function VariablesWithHistory (pattern, length)
  length = 2*(length or 1)      -- recall that each point takes TWO history items, t and v
  local function isVWH (v)
    local history = v.history
    if history and #history >= length then coroutine.yield (v) end
  end
  return coroutine.wrap (function ()  mapVars (isVWH, pattern) end)
end

-- enable in-memory cache for some or all variables
-- may be called more than once, so don't overwrite existing value
local function cacheVariables (pattern)
  mapVars (function (v) v:enableCache() end, pattern)
end

-- disable in-memory cache for some or all variables
-- may be called more than once, so don't overwrite existing value
local function nocacheVariables (pattern)
  mapVars (function (v) v:disableCache() end, pattern)
end

-- add a new archive rule to existing or new schema
-- archiveRule ("every_10m", "*.*.*{Max,Min}*")
-- note that, unless run at startup, this may not be effective (see No_Schema)
local function archiveRule(schema, newrule)
  for _, rule in ipairs (Rules) do
    if rule.schema == schema then
      rule.patterns[#rule.patterns+1] = newrule
      return
    end
  end
  -- must be a new schema
  Rules[#Rules+1] = {
    schema = schema,
    patterns = {newrule},
  }  
end

-- get vital information from installed VeraBridge devices
-- indexed by (integer) bridge#, and  .by_pk[], .by_name[]
local function get_bridge_info ()
  local bridgeSID = "urn:akbooer-com:serviceId:VeraBridge1"
  local bridge = {[0] = {nodeName = "openLuup", PK = '0', offset = 0}}   -- preload with openLuup info

  for i,d in pairs(luup.devices) do
    if d.device_type == "VeraBridge" then
      local name = d.description: gsub ("%W",'')      -- remove non-alphanumerics
      local PK = luup.variable_get (bridgeSID, "PK_AccessPoint", i)
      local offset = luup.variable_get (bridgeSID, "Offset", i)
      offset = tonumber (offset)
      if offset and PK then
        local index = math.floor (offset / BRIDGEBLOCK)   -- should be a round number anyway
        bridge[index] = {nodeName = name, PK = PK, offset = offset}
      end
    end
  end
  
  local by_pk, by_name = {}, {}  -- indexes
  for _,b in pairs (bridge) do    
    by_pk[b.PK] = b
    by_name[b.nodeName] = b
  end
  
  bridge.by_pk = by_pk          -- add indexes to bridge table
  bridge.by_name = by_name
  return bridge
end

---------------------------------
---
--- Metrics, handling of various format conversions
--
--[[

Different APIs have different formats/requirements:

 - luup.variable_...(),   serviceId, name, deviceNo is used to access variable history, as usual.
 - disk cache filenames,  node.localDevNo.shortSid.variable.wsp  
 - finder metrics,        nodeName.localDevNo_shortDevName.shortSid.variable
 
where:

  node,         0 for openLuup otherwise PK_AccessPoint or remote Vera  
  nodeName,     the name of the associated VeraBridge, or "openLuup"
  shortSid,     final apha-numeric part of the full serviceId
  shortDevName, device name with all non-alphanumerics removed
  
This way, even if the order of the bridges is changed in openLuup, the files are the same.  If you have to swap out a Vera, then its PK_AccessCode will change and you'll have to rename files to continue using them, but the finder metrics names will not change (unless you rename the associated VeraBridge.)

Pattern-matches for schemas, finders, and cacheVariables() ALL use the API paths and wildcards described 
here: http://graphite-api.readthedocs.io/en/latest/api.html#graphing-metrics

--]]

local Metrics = {}

-- find the variable with the given metric path: nodeName.dev[_name].shortSid.variable
function Metrics.finder2var (metric)
  -- ignore non-numeric device name
  local n,d,s,v = metric: match "(%w+)%.(%d+)[^%.]*%.([%w_]+)%.(.+)$"
  local b = Bridges.by_name[n]
  if b then 
    local dev = luup.devices[d + b.offset]      -- add bridge offset to convert to openLuup device number
    if dev then
      for _, x in ipairs (dev.variables) do
        if x.shortSid == s and x.name == v then return x end
      end
    end
  end
end

-- find the file path and filename give openLuup device number, shortSid and variable name
function Metrics.dsv2filepath (dev,shortSid,var)
  local devNo = dev % BRIDGEBLOCK   -- local device number, possibly on remote Vera 
  local bridge = math.floor (dev / BRIDGEBLOCK)
  -- Bridges[bridge] = {nodeName = name, PK = PK, offset = offset}
  local b = Bridges[bridge]
  if b then
    local filename = table.concat ({b.PK, devNo, shortSid, var}, '.')
    local path = table.concat {Directory, filename, ".wsp"}
    return path, filename
  end
end

-- find the file path and filename give metrics finder name
function Metrics.finder2filepath (metric)
  -- ignore non-numeric device name
  local n,d,s,v = metric: match "(%w+)%.(%d+)[^%.]*%.([%w_]+)%.(.+)$"
  local b = Bridges.by_name[n]
  if b then 
    local filename = table.concat ({b.PK, d, s, v}, '.')
    local path = table.concat {Directory, filename, ".wsp"}
    return path, filename
  end
end

-- bsv2finder (b, d, shortSid, var)  -- INTERNAL routine
-- ALSO returns openLuup device number and full device name
local function bdsv2finder (b, d, shortSid, var)
  if b then
    -- Bridges[bridge] = {nodeName = name, PK = PK, offset = offset}
    d = d + b.offset              -- add bridge offset to convert to openLuup device number
    local dev = luup.devices[d]
    if dev then
      local n = b.nodeName
      local devname = dev.description: gsub ("%W", '')            -- remove non-alphanumerics
      local d2 = table.concat {d % BRIDGEBLOCK, '_', devname}     -- shortDevNo_shortDevName
      return table.concat ({n, d2, shortSid, var}, '.'), d, dev.description
    end
  end
end

-- find the metrics finder name given all the components of the filename, including pk
function Metrics.pkdsv2finder (pk, d, shortSid, var)
  local b = Bridges.by_pk [pk]
  return bdsv2finder (b, d,shortSid,var)
end

-- find the metrics finder name given components of the filename, without pk
function Metrics.dsv2finder (dev, shortSid, var)
  local d = dev % BRIDGEBLOCK   -- local device number, possibly on remote Vera 
  local bridge = math.floor (dev / BRIDGEBLOCK)
  local b = Bridges[bridge]
  return bdsv2finder (b, d,shortSid,var)
end

-- find the metrics finder name from the variable
function Metrics.var2finder (v)
  local bridge = math.floor (v.dev / BRIDGEBLOCK)
  local b = Bridges[bridge]
  return bdsv2finder (b, v.dev % BRIDGEBLOCK, v.shortSid, v.name)
end

---------------------------------------------------
--
-- Carbon Cache look-alike (cf. DataYours / DataCache)
-- see: http://graphite.readthedocs.io/en/latest/carbon-daemons.html#carbon-cache-py
--
-- WRITES data to the disk-based archives
-- CREATES files using Storage Schemas and aggregation configuration rules
-- 
-- for whisper.create(path, archives, xFilesFactor, aggregationMethod)
-- are read from two Graphite-format .conf files: storage-schemas.conf and storage-aggregation.conf
-- both STORED IN THE DATABASE DIRECTORY (because the files relate to storage capacity)
-- see: http://graphite.readthedocs.org/en/latest/config-carbon.html#storage-schemas-conf
-- and: http://graphite.readthedocs.org/en/latest/config-carbon.html#storage-aggregation-conf

local function CarbonCache (path)
  
  local filePresent = {}   -- index of known files
  
  -- the current set of rules
  local schemas = {}              -- with retentions field
  local aggregations = {}         -- with XFilesFactor and aggregationMethod     

  local default_rule = {            -- default to once an hour for a week
    schema      = {name = "[default]", retentions = "1h:7d"},
    aggregation = {name = "[default]", xFilesFactor = 0.5, aggregationMethod = "average" },
   }

  -- for whisper.create(path, archives, xFilesFactor, aggregationMethod)
  -- are read from JSON-format file: storage-schemas.json
  -- see: http://graphite.readthedocs.org/en/latest/config-carbon.html#storage-schemas-conf

  local function read_conf_file (filename)
    -- if file not found on path..filename, then try virtualfilestorage
    -- generic Graphite .conf file has parameters a=b separated by name field [name]
    -- returns ordered list of named items with parameters and values { {name=name, parameter=value, ...}, ...}
    -- if name = "pattern" then regular expression escape "\" is converted to Lua pattern escape "%"  
    local rules
    local function comment (l) return l: match"^%s*%#" end
    local function section (l) 
      local n = l: match "^%s*%[([^%]]+)%]" 
      if n then 
        local new = {name = n}
        rules[#rules+1] = new           -- add new rule with this name...
        rules[n] = new end              -- ...and index it by name
      return n
    end
    local function parameter (l)
      local k,v = l: match "^%s*([^=%s]+)%s*=%s*(%S+)"    -- syntax:  param = value
      if k == "pattern" then v = v: gsub ("\\","%%") end  -- both their own escapes!
      local r = #rules
      if v and r > 0 then rules[r][k] = tonumber(v) or v end
    end    
    local f = io.open (path .. filename) or vfs.open (filename)
    if f then
      
      rules = {match = function (self, item)  -- returns rule for which first rule.pattern matches item
          for _,rule in ipairs (self) do
            if rule.pattern and item: match (rule.pattern) then return rule end
          end
        end}
      
      for l in f:lines() do
        local _ = comment(l) or section(l) or parameter(l);
      end
      f: close ()
    end
    return rules
  end

  local function load_rule_base ()
    schemas      = read_conf_file "storage-schemas.conf"
    aggregations = read_conf_file "storage-aggregation.conf"      
  end
  
  local function create (filename) 
    if not whisper.info (filename) then   -- it's not there
      load_rule_base ()      -- do this every create to make sure we have the latest
      -- apply the matching rules
      local schema = schemas: match (path)      or default_rule.schema
      local aggr   = aggregations: match (path) or default_rule.aggregation
      whisper.create (filename, schema.retentions, aggr.xFilesFactor, aggr.aggregationMethod)  
    end
    filePresent[filename] = true
  end

  local function update (metric, value, timestamp)
    local filename = table.concat {path, metric:gsub(':', '^'), ".wsp"}   -- change ':' to '^'
    if not filePresent[filename] then create (filename) end 
    -- use  timestamp as time 'now' to avoid clock sync problem of writing at a future time
    whisper.update (filename, value, timestamp, timestamp)  
  end

  -- CarbonCache ()
  load_rule_base ()   -- intial load of storage schemas and aggregation rules
  
  return {
    aggregations = aggregations,
    schemas = schemas,
    update = update,
  }
  
end
-----------------------------------
--
-- Data Historian file writing
--
-- Rules for which metrics to archive on disk define the name of a Carbon schema rule which should be used
-- in file creation, not the schema and aggregation themselves.

local function match_historian_rules (item, rule_set)
  -- return schema name (and matching pattern) for which first rule_set.patterns element matches item
  for _,rule in ipairs (rule_set) do
    if type(rule) == "table" and type(rule.patterns) == "table" and type(rule.schema) == "string" then
      for _, pattern in ipairs (rule.patterns) do
        local query = FindQuery (pattern)         -- turn it into a sophisticated query object
        if query: matches (item) then 
          return rule.schema, pattern 
        end
      end
    end
  end
end

-- create historian file with specified archives and aggregation...
-- ... so that it's always there to be written (and won't be created with the wrong archives)
local function create_historian_file (metric, filename) 
  local schema
  local rule, pattern = match_historian_rules (metric, Rules)
  if rule then          -- find the matching rule name
    _debug (metric .. " matching rule: " .. rule)
    local schema = Hcarbon.schemas[rule]    -- find the named schema rule
    if schema then
      local archives = schema.retentions
      local aggregate = Hcarbon.aggregations: match (metric)       -- use actual metric name here
      local xff = aggregate.xFilesFactor or 0
      local aggr = aggregate.aggregationMethod or "average"
      whisper.create (filename, archives, xff, aggr)  
      
      local message = "CREATE %s %s(%s) archives: %s, aggregation: %s, xff: %.0f"
      _log (message: format (metric or '?', rule, pattern, archives, aggr, xff))
    end
  end
  return schema
end

-- write_thru() disc cache - callback for all updates of variables with history
-- this has to be VERY fast, so disk archives are local, and mirroring to remote databases uses UDP
-- 2018.06.06 use extra [openLuup-only] timestamp parameter for actual variable time change
local function write_thru (dev, svc, var, old, value, timestamp)
  local short_svc = (svc: match "[^:]+$") or "UnknownService"
  local short_metric = table.concat ({dev, short_svc, var}, '.')
  if NoSchema[short_metric] then return end                             -- not interested
  
  local path, filename = Metrics.dsv2filepath (dev, short_svc, var)
  if not whisper.info (path) then               -- it's not there, we need to create it
    local schema = create_historian_file (short_metric, path) 
    NoSchema[short_metric] = not schema 
    if not schema then return end                   -- still no file, so bail out here
  end
  
  _debug (table.concat {"WRITE ", path, " = ", value})
  
  local wall, cpu   -- for performance stats
  do
    wall = timers.timenow ()
    cpu = timers.cpu_clock ()
    -- use timestamp as time 'now' to avoid clock sync problem of writing at a future time
    whisper.update (path, value, timestamp, timestamp)  
    cpu = timers.cpu_clock () - cpu
    wall = timers.timenow () - wall
  end

  -- update stats
  stats.cpu_seconds = stats.cpu_seconds + cpu
  stats.elapsed_sec = stats.elapsed_sec + wall
  stats.total_updates = stats.total_updates + 1  
  tally[filename] = (tally[filename] or 0) + 1
  
  -- send to external DBs also:  Graphite / InfluxDB
  -- use finder metric name for compatibility with Grafana, etc.
  if Graphite_UDP or InfluxDB_UDP then
    local message = "%s value=%s"
    local findername = Metrics.dsv2finder (dev, short_svc, var)
    local datagram = message: format (findername, value)    -- TODO: add TIME stamp?
    
    -- see: http://graphite.readthedocs.io/en/latest/feeding-carbon.html#the-plaintext-protocol
    if Graphite_UDP then                    -- send all updates (even if same, to populate archives)
      Graphite_UDP: send (datagram)
    end

    -- see: https://docs.influxdata.com/influxdb/v1.7/write_protocols/line_protocol_reference/
    -- also: https://docs.influxdata.com/influxdb/v1.7/supported_protocols/udp/
    if InfluxDB_UDP and value ~= old then   -- only send changes
      InfluxDB_UDP: send (datagram)
    end
  end

end

-- Wfetch() returns data from a Whisper disk archive, ignoring missing files,
-- and removing nils and replicated values, adding a final end point if required
local function Wfetch (fs_path, startTime, endTime)
  local V, T
  local N = 0       -- original number of points retrieved from archive
  local _, tv = pcall (whisper.fetch, fs_path, startTime, endTime)  -- catch file missing error
  if type(tv) == "table" and tv.values then
    -- reduce the data by removing nil values...
    --   ... no need to return uniformly spaced data
    local prev
    V, T = {}, {}    -- start new non-uniform t and v arrays
    N = tv.values.n
    for _, v, t in tv:ipairs () do
      if v and v ~= prev then                   -- skip nil and replicated values
        T[#T+1] = t
        V[#V+1] = v
        prev = v
      end
    end
  
    -- add final point, if necessary
    local n = #T
    if n > 0 and T[n] < endTime then
      T[n+1] = endTime
      V[n+1] = V[n]
    end
  end

  return V, T, N
end

-- Hfetch() returns time/value history data between the specified times, from cache or disk archives.
-- Data is fetched in Whisper fashion, using the best resolution containing the entire interval.
-- Effectively, this means that if the data is in the cache, then it's taken from there,
-- otherwise, it comes (at lower resolution) from the local disk archives.
-- it's used by luup.variable_get() when called with fourth (non-standard) time parameter
local function Hfetch(var, startTime, endTime)
  local now = timers.timenow()
  startTime = startTime or now - 24*60*60                  -- default to 24 hours ago 
  endTime   = endTime   or now                             -- default to now
  
  local V, T
  local N = 0
  local Ndisk, Ncache = 0,0
  if var then
    local _, Tcache = var: oldest ()                        -- get the oldest cached time
    if Tcache and (startTime >= Tcache) then
      
      -- get data from variable cache memory (already includes point at endTime)
      V, T = var:fetch(startTime, endTime)
      if V then Ncache = #V end
      
    elseif Directory then
    
      -- get data from disk archives
      local fs_path = Metrics.dsv2filepath (var.dev, var.shortSid, var.name)
      V, T, N = Wfetch (fs_path, startTime, endTime)
      if V then Ndisk = #V end
      N = N or 0
    end
     
    if ABOUT.DEBUG then
      local metric_path = table.concat ({var.dev, var.shortSid, var.name}, '.')
      local fetchline = "FETCH %s from: %s (%s) to: %s (%s), Ndisk: %s/%s, Ncache: %s" 
      _debug (fetchline: format (metric_path,
        os.date("%H:%M:%S", startTime), startTime, os.date ("%H:%M:%S", endTime), endTime, Ndisk, N, Ncache))
    end
 
  end
  
  return V or {}, T or {}
end

---------------------------------------------------
--
-- Graphite API custom Storage Finder for Historian
-- see: http://graphite-api.readthedocs.io/en/latest/finders.html#custom-finders
--

-- Finder utilities

-- sorted version of the pairs iterator
-- use like this:  for a,b in sorted (x, fct) do ... end
-- optional second parameter is sort function cf. table.sort
local function sorted (x, fct)
  local y, i = {}, 0
  for z in pairs(x) do y[#y+1] = z end
  table.sort (y, fct) 
  return function ()
    i = i + 1
    local z = y[i]
    return z, x[z]  -- if z is nil, then x[z] is nil, and loop terminates
  end
end


---------------------------------------------------
--
-- Nodes: either leaf or branch.  Leaf nodes have a reader.
--

local function Node (path, reader)
  return {
      path = path,
      name = path: match "([^%.]+)%.?$" or '',
      is_leaf = reader and true,
      reader = reader,
      fetch = (reader or {}).fetch   -- fetch (startTime, endTime)
--      ["local"] = true,
--      intervals = reader.get_intervals(),     -- not implemented
  }
end


-- Reader is the class responsible for fetching the datapoints for the given path. 
-- It is a simple class with 2 methods: fetch() and get_intervals():

local function HistoryReader(metric_path)

  -- fetch() returns time/value data between the specified times.
  -- also a v.n attribute and an ipairs iterator for Whisper compatilibilty in the Graphite API
  -- NOTE: that the time structure does not have the same meaning as for Whisper, but ipairs works fine.
  local function fetch (startTime, endTime)
    local var = Metrics.finder2var (metric_path)
    local V, T
    if var then 
      V, T = Hfetch(var, startTime, endTime) 
    end
    V = V or {}
    T = T or {}
    V.n = #V                                    -- add the number of samples, as does Whisper
    return {values = V, times = T, ipairs =     -- Whisper-like return structure (with iterator)
      function (tv) 
        return 
          function (self, i)
            i = i + 1
            local v,t = self.values[i], self.times[i]
            if v then return i, v,t end
          end, 
        tv, 0
      end}    
  end
  
---- get_intervals() is a method that hints graphite-web about the time range available for this given metric in the database. 
---- It must return an IntervalSet of one or more Interval objects.
  local function get_intervals()
--    local start_end = whisperDB.__file_open(fs_path,'rb', earliest_latest)
--    return IntervalSet {start_end}    -- TODO: all of the archives separately?
  end

  -- HistoryReader()
  _debug ("READER " .. metric_path)
  return {
      fetch = fetch,
      get_intervals = get_intervals,
    }
end


local function WhisperReader(metric_path)
 
  local function fetch (startTime, endTime) 
    local fs_path = table.concat {DYdirectory, metric_path: match "%.(.*)", ".wsp"}  -- ignore tree root
    local _, tv = pcall (whisper.fetch, fs_path, startTime, endTime)  -- catch file missing error
    return tv
  end

---- get_intervals() is a method that hints graphite-web about the time range available for this given metric in the database. 
---- It must return an IntervalSet of one or more Interval objects.
  local function get_intervals()
--    local start_end = whisperDB.__file_open(fs_path,'rb', earliest_latest)
--    return IntervalSet {start_end}    -- TODO: all of the archives separately?
  end

  -- WhisperReader()
  return {
      fetch = fetch,
      get_intervals = get_intervals,
    }  
end


local function HistoryFinder(config)

  -- the Historian implementation of the Whisper database is a single directory 
  -- with metric path names, prefixed by the PK_AccessPoint, as the filenames, 
  -- eg: PK_AccessPoint.device.shortServiceId.variable.wsp   ... 0.2.openLuup.Memory_Mb
  local function buildVWHtree ()
    local T = {}
    
    local function buildTree (n,d,s,v)
      local dev = luup.devices[d]
      if dev then
        local devname = dev.description: gsub ("%W", '')    -- remove non-alphanumerics
        d = table.concat {d % BRIDGEBLOCK, '_', devname}    -- shortDevNo_shortDevName
        local N = T[n] or {}
        local D = N[d] or {}
        local S = D[s] or {}
        S[v] = false          -- not a branch, but a leaf
        D[s] = S
        N[d] = D
        T[n] = N
      end
    end
    
    -- search the variable cache
    for v in VariablesWithHistory (nil, 1) do
      local b = Bridges[math.floor (v.dev / BRIDGEBLOCK)]
      if b then
        buildTree (b.nodeName, v.dev, v.shortSid, v.name)
      end
    end
    
    -- search the on-disk archives for files matching: pk.dev:name.shortSid.var.wsp
    if Directory then
      for a in lfs.dir (Directory) do              -- scan the directory and build tree of metrics
        local pk,d,s,v = a: match "^([^%.]+)%.([^%.]+)%.([^%.]+)%.([^%.]+)%.wsp$"   -- node.dev.svc.var
        local b = Bridges.by_pk[pk]        -- eg. {nodeName = "openLuup", PK = '0', offset = 0}
        if b then
          buildTree (b.nodeName,b.offset+d,s,v)
        end
      end
    end
    
    return T
  end

  -- the DataYours (DY) implementation of the Whisper database is a single directory 
  -- with fully expanded metric path names as the filenames, eg: system.device.service.variable.wsp
  local function buildDYtree (root_dir)
    local function buildTree (name, dir)
      local a,b = name: match "^([^%.]+)%.(.*)$"      -- looking for a.b
      if a then 
        dir[a] = dir[a] or {}
        buildTree (b, dir[a])     -- branch
      else
        dir[name] = false         -- not a branch, but a leaf
      end
    end
    
    local dir = {}
    for a in lfs.dir (root_dir) do              -- scan the root directory and build tree of metrics
      local name = a: match "^(.-)%.wsp$" 
      if name then buildTree(name, dir) end
    end
    return dir
  end

  
  -- find_nodes() is the entry point when browsing the metrics tree.
  -- It is an iterator which yields leaf or branch nodes matching the query
  -- query is a FindQuery object = {pattern = pattern}
  local function find_nodes(query)
    local pattern_parts = FindQuery (query.pattern)   -- upgrade query to one with real functionality!

    local dir = buildVWHtree()
    dir[DYtree] = DYdirectory and buildDYtree(DYdirectory) or nil    -- add DataYours Whisper directory
    
    --  Recursively generates absolute paths whose components
    --  underneath current_dir match the corresponding pattern in patterns
    local function _find_paths (current_dir, patterns, i, metric_path_parts)
      local qi = patterns[i]
      if qi then
        for node, branch in sorted (current_dir) do
--        for node, branch in pairs (current_dir) do
          local ok = qi: matches (node)
          if ok then
            metric_path_parts[i] = node
            if i < #patterns then
              if branch then
                _find_paths (branch, patterns, i+1, metric_path_parts)
              end
            else
              local metric_path = table.concat (metric_path_parts, '.')
              -- Now construct and yield an appropriate Node object            
              local reader
              if not branch then
                if metric_path_parts[1] == DYtree then
                  reader = WhisperReader(metric_path)   -- plain Whisper reader
                else
                  reader = HistoryReader(metric_path)
                end
              end
              coroutine.yield (Node(metric_path, reader))
            end
          end
        end
      end
    end

    _find_paths (dir, pattern_parts, 1, {}) 

  end

  -- HistoryFinder(),  called with Graphite API configuration
  
  DYdirectory = ((config or {}).historian or {}).DataYours   -- explicit override of DY finder
  
  if DYdirectory then 
    DYcarbon = CarbonCache (DYdirectory) 
    -- TODO: check for DY receiver UDP and start listener
  end
  
  return {
    find_nodes = function(query) 
      return coroutine.wrap (function () find_nodes (query) end)  -- a coroutine iterator
    end
  }
end



---------------------------------------------------
--
-- start() called with openLuup.Historian configuration at system startup
--  
local function start (config)
  CacheSize   = config.CacheSize
  Directory   = config.Directory
  Bridges     = get_bridge_info ()
  
  local ip_port = "%d+%.%d+%.%d+%.%d+:%d+"
  local Graphite = (config.Graphite_UDP or ''): match (ip_port)
  local InfluxDB  = (config.InfluxDB_UDP or ''): match (ip_port)
  
  -- convert destination IPs to actual sockets
  if Graphite then Graphite_UDP = ioutil.udp.open (Graphite) end 
  if InfluxDB then InfluxDB_UDP = ioutil.udp.open (InfluxDB) end
  
  if not CacheSize or CacheSize < 0 then 
    _debug "Historian CacheSize not defined, so not starting"
    return 
  end
  
  _log "starting data historian"
  devutil.set_cache_size (CacheSize)
  
  if Directory then     -- we're using the write-thru on-disk archive as well as in-memory cache
    Directory = Directory: gsub ("[^/]$","%1/")   -- 2018.07.21  ensure Directory ends with '/'
    _log ("using on-disk archive: " .. Directory)
    lfs.mkdir (Directory)             -- ensure it exists
    Hcarbon = CarbonCache (Directory) 
    local cacheMessage = "Graphite schema/aggregation rule sets: %d/%d"
    _log (cacheMessage: format (#Hcarbon.schemas, #Hcarbon.aggregations) ) 
    
    -- load the disk storage rule base  
    Rules = tables.archive_rules
    local rulesMessage = "disk archive storage rule sets: %d"
    _log (rulesMessage: format (#Rules) ) 

    -- start watching for history updates
    devutil.variable_watch (nil, write_thru, nil, "history")  -- (dev, callback, srv, var)
  end
  
  if Graphite_UDP then _log ("mirroring archives to Graphite at " .. Graphite) end
  if InfluxDB_UDP then _log ("mirroring archives to InfluxDB at " .. InfluxDB) end
  
  _log ("using memory cache size (per-variable): " .. CacheSize)
end

return {
  
  ABOUT = ABOUT,
  
  -- variables
  stats = stats,
  tally = tally,

  -- methods
  archiveRule           = archiveRule,            -- add a new archive rule to existing schema
  cacheVariables        = cacheVariables,         -- turn caching on
  nocacheVariables      = nocacheVariables,       -- turn it off
  VariablesWithHistory  = VariablesWithHistory,   -- iterator
  
  fetch                 = Hfetch,
  start                 = start,
  
  -- Graphite modules
  finder  = HistoryFinder,
  reader  = HistoryReader,
  metrics = Metrics,          -- for name translations: .finder2var(), .dsv2filepath(), .dsv2nodename()
  
}

-----
