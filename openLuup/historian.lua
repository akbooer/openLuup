local ABOUT = {
  NAME          = "openLuup.historian",
  VERSION       = "2018.05.31",
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

local lfs     = require "lfs"                                 -- for mkdir()

local isWhisper, whisper = pcall (require, "L_DataWhisper")   -- might not be installed

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

--[[

Data Historian manipulates the in-memory variable history cache and the on-disc archive.  
The industry-standard for a time-based metrics database, Whisper is used (as in DataYours.)
 
The code here handles all aspects of the in-memory cache and the on-disc archive with the exception of
updating the variable cache which is done in the device module itself.
 
Note that ONLY numeric variable values are supported by the historian.

--]]
    
local Directory             -- location of history database

local CacheSize             -- in-memory cache size

local Rules                 -- schema and aggregation rules   

local NoSchema = {}         -- table of schema metrics which definitely don't match schema rules

local tally = {}
local stats = {             -- interesting performance stats
    cpu_seconds = 0,
    total_updates = 0,
  }


----
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
  
  print (metric, value)   --TODO: TESTING only
  
  local filename = table.concat {Directory, metric, ".wsp"}         -- add folder and extension 
  
  if not whisper.info (filename) then               -- it's not there, we need to create it
    local schema = create (metric, filename) 
    NoSchema[metric] = not schema 
    if not schema then return end                   -- still no file, so bail out here
  end
  
  local cpu   -- for performance stats
  
  do
    cpu = timers.cpu_clock ()
    -- use timestamp as time 'now' to avoid clock sync problem of writing at a future time
    local timestamp = os.time()  -- TODO: find way to insert actual variable change time
    whisper.update (filename, value, timestamp, timestamp)  
    cpu = timers.cpu_clock () - cpu
    cpu = cpu - cpu % 0.000001        -- every microsecond counts!
  end

  -- update stats
  stats.cpu_seconds = stats.cpu_seconds + cpu
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
    local rulesMessage   = "#rules: %d"
    _log (rulesMessage: format (#Rules) ) 
  end

  -- start watching for history updates
  devutil.variable_watch (nil, write_thru, nil, "history")  -- (dev, callback, srv, var)

end

-- enable in-memory cache for all variables
-- TODO: add filter option to cacheVaraibles() ?
local function cacheVariables ()
  for _,d in pairs (luup.devices) do
    for _,v in ipairs (d.variables) do
        v.history = v.history or {}   -- may be called more than once, so don't overwrite existing value
    end
  end
end

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
  cacheVariables  = cacheVariables,
  start           = start,
}

-----
