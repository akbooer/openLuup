local ABOUT = {
  NAME          = "openLuup.historian",
  VERSION       = "2018.05.27",
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
local devutil = require "openLuup.devices"
local timers  = require "openLuup.timers"                     -- for performance statistics
local vfs     = require "openLuup.virtualfilesystem"          -- for configuration files

local lfs     = require "lfs"                                 -- for mkdir()

local isWhisper, whisper = pcall (require, "L_DataWhisper")   -- might not be installed

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

--[[

Data Historian uses several modules to manipulate the in-memory variable history cache and
the on-disc archive.  Industry-standard formats and APIs are used widely, and the implementation
builds on previous plugins and CGIs, most notably, DataYours (an implementation of Graphite and Whisper.) 

 - Whisper      the database
 - CarbonCache  the Whisper writer
 
The code here handles all aspects of the in-memory cache and the on-disc archive with the exception of
updating the variable cache which is done in the device module itself.
 
--]]
    


------------------------------------------------------------------------
--
-- DataCache: data archive back-end using Whisper
-- 
-- DataCache mimics a Carbon "cache" daemon, saving incoming data to a Whisper database.
-- reads the Graphite format "storage-schemas.conf" and "storage-aggregation.conf" files.
--
-- based on DataCache - Carbon Cache daemon   2016.10.04   @akbooer
-- without re-write rules (part of Carbon Aggregator)
-- uses configuration files from openLuup virtual file system

local function CarbonCache (ROOT)       -- ROOT for the whisper database

  local filePresent = {}          -- cache of existing file names

  local tally = {n = 0}
  local stats = {                 -- interesting performance stats
      cpu = 0,
      updates = 0,
    }

  local default = {
    schema  = {name = "[default]",  retentions = "1h:7d"},                                    -- default to once an hour for a week
    aggregation = {name = "[default]", xFilesFactor = 0.5, aggregationMethod = "average" },   -- these are the usual Whisper defaults anyway
  }

  ----
  --
  -- Storage Schemas and aggregation configuration rules
  -- 
  -- for whisper.create(path, archives, xFilesFactor, aggregationMethod)
  -- are read from two Graphite-format .conf files: storage-schemas.conf and storage-aggregation.conf
  -- see: http://graphite.readthedocs.org/en/latest/config-carbon.html#storage-schemas-conf
  -- and: http://graphite.readthedocs.org/en/latest/config-carbon.html#storage-aggregation-conf

  local function match_rule (item, rules)
    -- return rule for which first rule.pattern matches item
    for _,rule in ipairs (rules) do
      if rule.pattern and item: match (rule.pattern) then return rule end
    end
  end
  
  local function parse_conf_file (config)
    -- generic Graphite .conf file has parameters a=b separated by name field [name]
    -- returns ordered list of named items with parameters and values { {name=name, parameter=value, ...}, ...}
    -- if name = "pattern" then regular expression escape "\" is converted to Lua pattern escape "%"
    local ITEM                     -- sticky item
    local result, index = {}, {}
    local function comment (l) return l: match "^%s*%#" end
    local function section  (l)
      local n = l: match "^%s*%[([^%]]+)%]" 
      if n then ITEM = {name = n}; index[n] = ITEM; result[#result+1] = ITEM end
      return n
    end
    local function parameter (l)
      -- syntax:   param (number) = value, number is optional
      local p,n,v = l: match "^%s*([^=%(%s]+)%s*%(?(%d*)%)?%s*=%s*(.-)%s*$"
      if v then 
        v = v: gsub ("[\001-\031]",'')                      -- remove any control characters
        n = tonumber (n)                                    -- there may well not be a numeric parameter  
        if p: match "^%d+$" then p = tonumber (p) end
        if p == "pattern" then v = v: gsub ("\\","%%")      -- both their own escapes!
        elseif v:upper() == "TRUE"  then v = true           -- make true, if that's what it is
        elseif v:upper() == "FALSE" then v = false          -- or false
        else v = tonumber(v) or v end                       -- or number  
        if not ITEM then section "[_anon_]" end             -- create section if none exists
        local item = ITEM[p]
        if item then                                        -- repeated item, make multi-valued table 
          if type(item) ~= "table" then item = {item} end
          item [#item+1] = v
          v = item
        end
        ITEM[p] = v 
      end
    end
      
    for line in config: gmatch "%C+" do 
      local _ = comment(line) or section(line) or parameter(line)
    end
    
    return result, index
  end

  ----
  --
  -- cacheWrite()
  --
  -- Whisper file update - could make this much more complex 
  -- with queuing and caching like CarbonCache, but let's not yet.
  -- message is in Whisper plaintext format: "path value timestamp"
  -- 

  local function cacheWrite (path, value, timestamp) -- update whisper file, creating new file if necessary
    local filename
    
    local function create () 
      local logMessage1 = "created: %s"
      local logMessage2 = "schema %s = %s, aggregation %s = %s, xff = %.0f"
      local rulesMessage   = "rules: #schema: %d, #aggregation: %d"
      if not whisper.info (filename) then   -- it's not there
        -- load the rule base (do this every create to make sure we have the latest)
        local schemas     = parse_conf_file (vfs.read "storage-schemas.conf")
        local aggregation = parse_conf_file (vfs.read "storage-aggregation.conf")      
        _log (rulesMessage: format (#schemas, #aggregation) )   
        -- apply the matching rules
        local schema = match_rule (path, schemas)     or default.schema
        local aggr   = match_rule (path, aggregation) or default.aggregation
        whisper.create (filename, schema.retentions, aggr.xFilesFactor, aggr.aggregationMethod)  
        _log (logMessage1: format (path or '?') )
        _log (logMessage2: format (schema.name, schema.retentions, aggr.name,
                       aggr.aggregationMethod or default.aggregation.aggregationMethod, 
                       aggr.xFilesFactor or default.aggregation.xFilesFactor) )
      end
      filePresent[filename] = true
    end
    
    -- update ()
    if path and value then
      timestamp = timestamp or os.time()         -- add local time if sender has no timestamp
      filename = table.concat {ROOT, path:gsub(':', '^'), ".wsp"}    -- change ":" to "^" and add extension 
      timestamp = tonumber (timestamp)   
      value = tonumber (value)
      if not filePresent[filename] then create () end         -- we may need to create it
      local cpu = timers.cpu_clock ()
      -- use remote timestamp as time 'now' to avoid clock sync problem of writing at a future time
      whisper.update (filename, value, timestamp, timestamp)  
      cpu = stats.cpu + (timers.cpu_clock () - cpu)
      stats.cpu = cpu - cpu % 0.001
      stats.updates = stats.updates + 1
      if not tally[path] then
        tally[path] = 0
        tally.n = tally.n + 1
      end
      tally[path] = tally[path] + 1
    end
  end

  return {
    write = cacheWrite,
    info  = {stats = stats, tally = tally},
    }
  
end -- data_cache module


-------------------------
---
--- Historian
---


local CacheSize, Directory

local NoArchive = {}

local diskCache   

-- write_thru() disc cache - callback for all updates of variables with history
local function write_thru (dev, srv, var, old, new)
  if NoArchive[var] then return end    -- not interested
  local _ = old    -- unused
  local short_name = table.concat ({dev, (srv: match "[^:]+$") or "UnknownService", var}, '.')
  print (short_name, new)
  diskCache.write (short_name, new)
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
  
  for _,d in pairs (luup.devices) do
    for _,v in ipairs (d.variables) do
        v.history = v.history or {}   -- may be called more than once, so don't overwrite existing value
    end
  end

  if Directory and isWhisper then     -- we're using the write-thru on-disk archive as well as in-memory cache
    _log ("...using on-disk archive " .. Directory .. "...")
    lfs.mkdir (Directory)             -- ensure it exists
    diskCache = CarbonCache (Directory)
    
    if type(config.NoArchive) == "string" then
      for varname in config.NoArchive: gmatch "[%w_]+" do
        NoArchive[varname] = true
      end
    end
    
    devutil.variable_watch (nil, write_thru, nil, "history")  -- (dev, callback, srv, var)
  end
  
  _log ("...using memory cache size (per-variable) " .. CacheSize)
end

return {
  
  ABOUT = ABOUT,
  
  start     = start,
  
}

-----
