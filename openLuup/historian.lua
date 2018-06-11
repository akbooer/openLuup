local ABOUT = {
  NAME          = "openLuup.historian",
  VERSION       = "2018.06.10",
  DESCRIPTION   = "openLuup data historian",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-18 AK Booer

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

local logs    = require "openLuup.logs"
local json    = require "openLuup.json"                       -- for storage schema rules
local devutil = require "openLuup.devices"
local timers  = require "openLuup.timers"                     -- for performance statistics
local vfs     = require "openLuup.virtualfilesystem"          -- for configuration files
local whisper = require "openLuup.whisper"                    -- for the Whisper database

local lfs     = require "lfs"                                 -- for mkdir(), and Graphite

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

Pattern-matches for schemas, finders, and cacheVariables() ALL use the API paths and wildcards described 
here: http://graphite-api.readthedocs.io/en/latest/api.html#graphing-metrics

--]]
    
local Directory             -- location of history database

local CacheSize             -- in-memory cache size

local Rules                 -- schema and aggregation rules   

local NoSchema = {}         -- table of schema metrics which definitely don't match schema rules

local tally = {}
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
  
  local function match_all (self, item)
    -- TBD
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
  
  local query = pattern_parts (pattern)
  query.pattern = pattern
  query.match = match_all    -- add whole match
  return query
end


-- ITERATOR, walks through (unsorted) VWH variables
-- usage:  for v in VariableWithHistory () do ... end
local function VariablesWithHistory (pattern)
  return coroutine.wrap (function () 
    for _,d in pairs (luup.devices) do
      for _,v in ipairs (d.variables) do
        local history = v.history
        if history and #history > 0 then 
          -- TODO: match pattern
          coroutine.yield (v) 
        end
      end
    end
  end)
end


-- findVariable()  find the variable with the given metric path  *...*.dev[name].shortSid.variable
local function findVariable (metric)
  local d,s,v = metric: match "(%d+)[^%.]*%.([%w_]+)%.(.+)$"  -- ignore non-numeric device name and full path
  d = luup.devices[tonumber (d)]
  if d then
    for _, x in ipairs (d.variables) do
      if x.shortSid == s and x.name == v then return x end
    end
  end
end


---------------------------------------------------
--
-- Carbon Cache look-alike (cf. DataCache)
-- WRITES data to the disk-based archives
--
-- Storage Schemas and aggregation configuration rules
-- 
-- for whisper.create(path, archives, xFilesFactor, aggregationMethod)
-- are read from JSON-format file: storage-schemas.json
-- see: http://graphite.readthedocs.org/en/latest/config-carbon.html#storage-schemas-conf

local function match_rule (item, rules)
  -- return rule for which first rule.patterns element matches item
  for _,rule in ipairs (rules) do
    if type(rule) == "table" and rule.patterns and rule.archives then
      for pattern in rule.patterns: gmatch "[^%s,]+" do 
        if item: match (pattern) then 
          return rule 
        end
      end
    end
  end
end


-- create file with specified archives and aggregation
local function create (metric, filename) 
  local schema = match_rule (metric, Rules)
  if schema then          -- apply the matching rule
    local xff = schema.xFilesFactor or 0
    local aggr = schema.aggregation or "average"
    whisper.create (filename, schema.archives, xff, aggr)  
    
    local message = "created: %s, schema: %s, aggregation: %s, xff: %.0f"
    _log (message: format (metric or '?', schema.archives, aggr, xff))
  end
  return schema
end

----
--
-- write_thru() disc cache - callback for all updates of variables with history
--
-- 2018.06.06 use extra timestamp parameter
local function write_thru (dev, svc, var, _, value, timestamp)     -- 'old' value parameter not used
  local short_svc = (svc: match "[^:]+$") or "UnknownService"
  local metric = table.concat ({dev, short_svc, var}, '.')
  if NoSchema[metric] then return end                             -- not interested
  
  _debug (table.concat {"WRITE ", metric, " = ", value})
  
  local filename = table.concat {Directory, metric, ".wsp"}         -- add folder and extension 
  
  if not whisper.info (filename) then               -- it's not there, we need to create it
    local schema = create (metric, filename) 
    NoSchema[metric] = not schema 
    if not schema then return end                   -- still no file, so bail out here
  end
  
  local wall, cpu   -- for performance stats
  
  do
    wall = timers.timenow ()
    cpu = timers.cpu_clock ()
    -- use timestamp as time 'now' to avoid clock sync problem of writing at a future time
    whisper.update (filename, value, timestamp, timestamp)  
    cpu = timers.cpu_clock () - cpu
    wall = timers.timenow () - wall
  end
  
  -- TODO: send to external DB also?  Graphite / InfluxDB
  
  -- update stats
  stats.cpu_seconds = stats.cpu_seconds + cpu
  stats.elapsed_sec = stats.elapsed_sec + wall
  stats.total_updates = stats.total_updates + 1  
  tally[metric] = (tally[metric] or 0) + 1
end


local function initDB ()
  local err
  lfs.mkdir (Directory)             -- ensure it exists
  
  -- load the rule base
  local json_rules
  local rules_file = "storage-schemas.json"
  local f = io.open (Directory .. rules_file) or vfs.open (rules_file)   -- either here or there
  json_rules = f: read "*a"
  f: close()
  
  Rules, err = json.decode (json_rules)     
  if type(Rules) ~= "table" then
    Rules = {}
    _log (err or "Unknown error reading storage-schemas.json")
  else
    local rulesMessage = "#schema rules: %d"
    _log (rulesMessage: format (#Rules) ) 
  end

  -- start watching for history updates
  devutil.variable_watch (nil, write_thru, nil, "history")  -- (dev, callback, srv, var)

end

-- enable in-memory cache for all variables
-- TODO: add filter option to cacheVariables() ?
local function cacheVariables (pattern)
  for _,d in pairs (luup.devices) do
    for _,v in ipairs (d.variables) do
        v.history = v.history or {}   -- may be called more than once, so don't overwrite existing value
    end
  end
end

-- fetch() returns time/value data between the specified times.
-- the data is fetched in Whisper fashion, using the best resolution containing the entire interval.
-- Effectively, this means that if the data is in the cache, the it's taken from there,
-- otherwise, it comes (at lower resolution) from the database (agnostic as to exactly which one... HOW?)
local function fetch(var, startTime, endTime)
  local now = timers.timenow()
  startTime = startTime or now - 24*60*60                  -- default to 24 hours ago 
  endTime   = endTime   or now                             -- default to now
  
  local V, T
  local Ndisk, Ncache = 0,0
  if var then
    local metric_path = table.concat ({var.dev, var.shortSid, var.name}, '.')
    local _, Tcache = var: oldest ()                        -- get the oldest cached time
    if Directory and (startTime < Tcache) then              -- get older data from the disk archives
      
      -- get data from disk archives
      local fs_path = table.concat {Directory, metric_path, ".wsp"}
      local _, tv = pcall (whisper.fetch, fs_path, startTime, endTime)  -- catch file missing error
      if tv then
        -- reduce the data by removing nil values...
        --   ... no need to return uniformly spaced data
        local prev
        V, T = {}, {}    -- start new non-uniform t and v arrays
        
        for _, v, t in tv:ipairs () do
          Ndisk = Ndisk + 1
          if v and v ~= prev then                   -- skip nil and replicated values
            T[#T+1] = t
            V[#V+1] = v
            prev = v
          end
        end
      end
      
      -- add final point, if necessary
      local n = #T
      if n > 0 and T[n] < endTime then
        T[n+1] = endTime
        V[n+1] = V[n]
      end
        
    else
    
      -- get data from variable cache memory (already includes point at endTime)
      V, T = var:fetch(startTime, endTime)
      if V then Ncache = #V end
    end
     
    if ABOUT.DEBUG then
      local fetchline = "FETCH %s from: %s (%s) to: %s (%s), Ndisk: %s, Ncache: %s" 
      _debug (fetchline: format (metric_path,
        os.date("%H:%M:%S", startTime), startTime, os.date ("%H:%M:%S", endTime), endTime, Ndisk, Ncache))
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
  local function HRfetch (startTime, endTime)
    local var = findVariable (metric_path)
    local V, T
    if var then 
      V, T = fetch(var, startTime, endTime) 
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
  return {
      fetch = HRfetch,
      get_intervals = get_intervals,
    }
  
  end


local function HistoryFinder()    -- no config parameter required for this finder

  -- the Historian implementation of the Whisper database is a single directory 
  -- with metric path names, prefixed by the directory, as the filenames, 
  -- eg: device.shortServiceId.variable.wsp   ... 2.openLuup.Memory_Mb
  -- TODO: a virtual parallel tree using: devNo_deviceName.shortServiceId.variable?
  local function buildVWHtree ()
    local T = {}
    for v in VariablesWithHistory () do
        local d,s,n = v.dev, v.shortSid, v.name
--        d = tostring(d)
        local name = luup.devices[d].description: match "%s*(.*)"
        d = table.concat {d, ':', (name: gsub ('%W', '_'))}     -- devNo:deviceName.shortServiceId.variable
        local D = T[d] or {}
        local S = D[s] or {}
        S[n] = false          -- not a branch, but a leaf
        D[s] = S
        T[d] = D
    end
    return T
  end

  local function IntOrStr (x)
    local i = x: match "^(%d+)"
    return tonumber(i) or x
  end
  
  -- find_nodes() is the entry point when browsing the metrics tree.
  -- It is an iterator which yields leaf or branch nodes matching the query
  -- query is a FindQuery object = {pattern = pattern}
  local function find_nodes(query)
    local pattern_parts = FindQuery (query.pattern)   -- upgrade query to one with real functionality!

    local dir = {   -- TODO: consider lazy evaluation to build tree only if referenced
        history = buildVWHtree(),               -- add 'history' prefix to path
        whisper = {},                           -- placeholder for general Whisper directory
      }
    
    --  Recursively generates absolute paths whose components
    --  underneath current_dir match the corresponding pattern in patterns
    local function _find_paths (current_dir, patterns, i, metric_path_parts)
      local qi = patterns[i]
      if qi then
        for node, branch in sorted (current_dir, function(a,b) return IntOrStr(a) < IntOrStr(b) end) do
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
                reader = HistoryReader(metric_path)
              end
              coroutine.yield (Node(metric_path, reader))
            end
          end
        end
      end
    end

    _find_paths (dir, pattern_parts, 1, {}) 

  end

  -- HistoryFinder()
  return {
    find_nodes = function(query) 
      return coroutine.wrap (function () find_nodes (query) end)  -- a coroutine iterator
    end
  }
end


---------------------------------------------------
--
-- called with configuration at system startup
--  
local function start (config)
  
  CacheSize = config.CacheSize
  Directory = config.Directory
  
  if not CacheSize or CacheSize < 0 then 
    _debug "Historian CacheSize not defined, so not starting"
    return 
  end
  
  _log "starting data historian..."
  devutil.set_cache_size (CacheSize)
  cacheVariables ()                   -- turn on caching for existing variables
  
  if Directory then     -- we're using the write-thru on-disk archive as well as in-memory cache
    _log ("...using on-disk archive: " .. Directory .. "...")
    initDB ()
  end
  
  _log ("...using memory cache size (per-variable): " .. CacheSize)
end

return {
  
  ABOUT = ABOUT,
  
  -- variables
  stats = stats,
  tally = tally,

  -- methods
  cacheVariables        = cacheVariables,
  fetch                 = fetch,
  start                 = start,
  VariablesWithHistory  = VariablesWithHistory,   -- iterator
  
  -- Graphite modules
  finder = HistoryFinder,
  reader = HistoryReader,
  
}

-----
