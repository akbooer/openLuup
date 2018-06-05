local ABOUT = {
  NAME          = "openLuup.historian",
  VERSION       = "2018.06.05",
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

local lfs     = require "lfs"                                 -- for mkdir(), and Graphite

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

local isWhisper, whisper  = pcall (require, "L_DataWhisper")    -- might not be installed?

---------------------------------------------------
--
-- Graphite Data Finder dependencies
--

local isGraphite, graphite_api  = pcall (require, "L_DataGraphiteAPI")    -- might not be installed?

graphite_api = graphite_api or {}
local node = graphite_api.node  or {}
local BranchNode, LeafNode = node.BranchNode, node.LeafNode

local utils = graphite_api.utils or {}
local sorted = utils.sorted
local expand_value_list = utils.expand_value_list

--local intervals = graphite_api.intervals or {}
--local Interval = intervals.Interval
--local IntervalSet = intervals.IntervalSet

--[[

Data Historian manipulates the in-memory variable history cache and the on-disc archive.  
The industry-standard for a time-based metrics database, Whisper, is used (as in DataYours.)
It also uses the Graphite API standard as an interface for Grafana plotting, implemented by 
a WSAPI interface to the openLuup CGI servlet.
 
The code here handles all aspects of the in-memory cache and the on-disc archive with the exception of
updating the variable cache which is done in the device module itself.

Note that ONLY numeric variable values are supported by the historian.

Pattern-matches for schemas, finders, and cacheVariables() ALL use the API paths and wildcards  
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

-- sort function for table.sort() of VWH info
local function sort_dsv (a,b) 
  return 
    (a.dev <  b.dev) or
    (a.dev == b.dev) and
      ( (a.shortSid < b.shortSid) or
        (a.shortSid == b.shortSid) and
          a.name < b.name )
  
--  if a[1] < b[1] then return true end
--  if a[1] == b[1] then
--    if a[2] < b[2] then return true end
--    if a[2] == b[2] then 
--      return a[3] < b[3] 
--    end
--  end
end

-- ITERATOR, returning sorted array element-by-element of all VWH info
-- usage:  for v = VariableWithHistory () do ... end
local function VariablesWithHistory ()
  local VWH = {}
  for _,d in pairs (luup.devices) do
    for _,v in ipairs (d.variables) do
      local history = v.history
      if history and #history > 0 then 
        VWH[#VWH+1] = v
      end
    end
  end
  table.sort (VWH, sort_dsv)
  local i = 0
  return function () i = i + 1; return VWH[i] end
end

-- findVariable()  find the variable with the given metric path  dev.shortSid.variable
local function findVariable (metric)
  local d,s,v = metric: match "(%d+)%.([%w_]+)%.(.+)"
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
local function write_thru (dev, svc, var, _, value)     -- 'old' value parameter not used
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
    local timestamp = os.time()  -- TODO: find way to insert actual variable change time
    whisper.update (filename, value, timestamp, timestamp)  
    cpu = timers.cpu_clock () - cpu
    wall = timers.timenow () - wall
  end

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
local function cacheVariables ()
  for _,d in pairs (luup.devices) do
    for _,v in ipairs (d.variables) do
        v.history = v.history or {}   -- may be called more than once, so don't overwrite existing value
    end
  end
end


---------------------------------------------------
--
-- Graphite API custom Storage Finder for Historian
-- see: http://graphite-api.readthedocs.io/en/latest/finders.html#custom-finders
--

-- Finder utilities


-- Reader is the class responsible for fetching the datapoints for the given path. 
-- It is a simple class with 2 methods: fetch() and get_intervals():

local function HistoryReader(fs_path, real_metric_path)

---- get_intervals() is a method that hints graphite-web about the time range available for this given metric in the database. 
---- It must return an IntervalSet of one or more Interval objects.
  local function get_intervals()
--    local start_end = whisperDB.__file_open(fs_path,'rb', earliest_latest)
--    return IntervalSet {start_end}    -- TODO: all of the archives separately?
  end

-- fetch() returns time/value data between the specified times.
-- the data is fetched in two parts:
--    1. disk archives, if start time is before that in the cache
--    2. memory cache 
  local function fetch(startTime, endTime)
    local now = timers.timenow()
    startTime = startTime or now - 24*60*60                  -- default to 24 hours ago 
    endTime   = endTime   or now                             -- default to now
    local var = findVariable (real_metric_path)
    
    local fetchline = "FETCH %s from: %s (%s) to: %s (%s)" 
    _debug (fetchline: format (real_metric_path,
        os.date("%H:%M:%S", startTime), startTime, os.date ("%H:%M:%S", endTime), endTime))
    
    local V, T
    local tv
    local Ndisk, Ntrim = 0,0
    if var and isWhisper then                 -- get some older data from the disk archives
      local Tcache = var: oldest ()           -- get the oldest cached time
      if startTime < Tcache then
        tv = whisper.fetch (fs_path, startTime, Tcache)
        -- reduce the data by removing nil values...
        --   ... no need, now, to return uniformly spaced data
        local prev
        V, T = {}, {}    -- start new non-uniform t and v arrays
        
        for _, v, t in tv:ipairs () do
          Ndisk = Ndisk + 1
          if v and v ~= prev then                   -- skip nil and replicated values
            T[#T+1] = t
            V[#T] = v
            prev = v
          end
        end
        V[#T+1] = nil     -- truncate any remaining data in V
        Ntrim = #T
        V.n = Ntrim
      end
      startTime = Tcache    --
    end
  
    local tv = var:fetch(startTime, endTime, V, T)   -- Whisper-like return structure (with iterator)
    
    local dataline = "... Ndisk: %s, Ntrim: %s, Ntotal: %s"
    _debug (dataline: format (Ndisk or '?', Ntrim or '?', tv.values.n or '?'))
    
    return tv
  end

  -- reader()
  return {
      fetch = fetch,
      get_intervals = get_intervals,
    }
  
  end


local function HistoryFinder()    -- no config parameter required for this finder

  -- the Historian implementation of the Whisper database is a single directory 
  -- with metric path names, prefixed by the directory, as the filenames, 
  -- eg: device.shortServiceId.variable.wsp
  -- TODO: a virtual parallel tree using: deviceName.shortServiceId.variable
  local function buildTree ()
    local T = {}
    for v in VariablesWithHistory () do
        local d,s,n = v.dev, v.shortSid, v.name
        d = tostring(d)
        local D = T[d] or {}
        local S = D[s] or {}
        S[n] = false          -- not a branch, but a leaf
        D[s] = S
        T[d] = D
    end
    return T
  end


  -- find_nodes() is the entry point when browsing the metrics tree.
  -- It is an iterator which yields leaf or branch nodes matching the query
  -- query is a FindQuery object. 

  --{
  --  pattern = pattern
  --  startTime = startTime
  --  endTime = endTime
  --  isExact = true     -- is_pattern(pattern)           -- no idea
  --  interval = {startTime or 0, endTime or os.time()}   -- Interval() object
  --  return self
  --}
  local function find_nodes(query)
    local clean_pattern = query.pattern: gsub ('\\', '')
    local pattern_parts = {}
    clean_pattern: gsub("[^%.]+", function(c) pattern_parts[#pattern_parts+1] = c end);

    local dir = buildTree() 
    
    -- construct and yield an appropriate Node object
    local function yield_node_object (metric_path, branch)
      local reader, absolute_path
      local Node = branch and BranchNode or LeafNode
      if not branch then
        if Directory then absolute_path = table.concat {Directory, metric_path, ".wsp"} end
        reader = HistoryReader(absolute_path, metric_path)
      end
      coroutine.yield (Node(metric_path, reader))
    end
    
    --  Recursively generates absolute paths whose components
    --  underneath current_dir match the corresponding pattern in patterns
    local function _find_paths (current_dir, patterns, i, metric_path_parts)
      local qi = patterns[i]
      if qi then
        for qy in expand_value_list (qi) do     -- do value list substitutions {a,b, ...} 
          qy = qy: gsub ("[%-]", "%%%1")        -- quote special characters
          qy = qy: gsub ("%*", "%.%1")          -- '*' -> '.*' (converting regex to Lua pattern)
          qy = qy: gsub ("%?", ".")             -- replace single character query '?' with dot '.'
          qy = '^'.. qy ..'$'                   -- ensure pattern matches the whole string
          for node, branch in sorted (current_dir) do
            local ok = node: match (qy)
            if ok then
              metric_path_parts[i] = ok
              if i < #patterns then
                if branch then
                  _find_paths (branch, patterns, i+1, metric_path_parts)
                end
              else
                local metric_path = table.concat (metric_path_parts, '.')
                -- Now construct and yield an appropriate Node object            
                yield_node_object (metric_path, branch)
              end
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
-- CGI for Historian Graphite API
--


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
  
  if Directory and isWhisper then     -- we're using the write-thru on-disk archive as well as in-memory cache
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
  start                 = start,
  VariablesWithHistory  = VariablesWithHistory,   -- iterator
  
  -- module
  finder = HistoryFinder,     -- for graphite_cgi interface

  -- CGI entry point
--  run = run,
  
}

-----
