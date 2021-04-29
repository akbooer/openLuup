local ABOUT = {
  NAME          = "openLuup.api",
  VERSION       = "2021.04.29",
  DESCRIPTION   = "openLuup object-level API",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2021 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2021 AK Booer

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

--
-- openLuup API - the object-oriented interface
--
-- the intention is to deprecate the traditional luup.xxx API for new development
-- retaining the original for compatibility with legacy plugins and code
--

-- 2021.04.27  key parts extracted from luup.lua

-----
--
-- openLuup.cpu_table,   2020.06.28
-- openLuup.wall_table,  2020.06.29
--
-- returns an object with current plugin CPU / WALL-CLOCK times
-- allow pretty printing and the difference '-' operator


local tables        = require "openLuup.servertables" -- SID used in device variable virtualization
local chdev         = require "openLuup.chdev"
local devutil       = require "openLuup.devices"
local sceneutil     = require "openLuup.scenes"


local devices = devutil.device_list
local scenes = sceneutil.scene_list

local function time_table (what)
  local array
  local function sub(a,b)
    local s, b = array {}, b or {}
    for n,v in pairs(a) do s[n] = b[n] and v - b[n] or nil end
    return s
  end
  local function str(x)
    local con = table.concat
    local time, info = "%8.3f", "%12s %8s %s"
    local b = {info: format ("(s.ms)", "[#]", "device name")}
    local devs = {}
    for n in pairs(x) do devs[#devs+1] = n end
    table.sort (devs)
    for _,n in ipairs(devs) do 
      local v = x[n]
      local name = devices[n].description: match "%s*(.*)"
      b[#b+1] = info: format (time: format(v), con{'[', n, ']'}, name)
    end
    b[#b+1] = ''
    return con (b, '\n')
  end
  function array (x) setmetatable (x, {__sub = sub, __tostring = str}) return x end
  local t = array {}
  for i, d in pairs (devices) do t[i] = d.attributes[what] end
  return t
end

-- 2021.02.03  find device by attribute: name / id / altid / etc...
local function find_device (attribute)
  if type (attribute) ~= "table" then return end
  local name, value = next (attribute)
  for n, d in pairs (devices) do
    if d.attributes[name] == value then
      return n
    end
  end
end

-- 2021.03.05  find scene id by name - find_scene {name = xxx}
local function find_scene (attribute)
  local name = attribute.name       -- currently, only 'name' is supported
  for id, s in pairs (scenes) do
    if s.description == name then return id end
  end
end

-----
--
-- openLuup as an iterator for devices / scenes / ...
--
-- usage is:  for n, d in openLuup "devices" -- or "scenes"
--
local function api_iterator (self, what)
  local possible = {devices = devices, scenes = scenes}
  return next, possible[what]
end

-----
--
-- virtualization of device variables
-- 2021.04.25  functionality added to openLuup structure itself
--

local SID = tables.SID

local function readonly (_, x) error ("ERROR - READONLY: attempt to create index " .. x, 2) end

local api_meta = {__newindex = readonly, __call = api_iterator}

function api_meta:__index (dev)
  
  local svc_meta = {__newindex = readonly}
        
  function svc_meta:__index (sid)
    sid = SID[sid] or sid             -- handle possible serviceId aliases (see servertables.SID)
    
    local var_meta = {}
    
--    function var_meta:__call (action)
--      return function (args)
--        local d = devices[dev]
--        if d then 
--          return d: call_action (sid, action, args) 
--        else
--          return nil, "no such device #" .. tostring(dev)
--        end
--      end
--    end

    function var_meta:__index (var)
      local d = devices[dev]
      if not d then print("No dev", dev) return end
      local v = d: variable_get (sid, var) or {}
      return v.value, v.time
    end
    
    function var_meta:__newindex (var, new)
      local d = devices[dev]
      if not d then print("No dev", dev) return end
      new = tostring(new)
      local old = self[var]
      if old ~= new then
        d: variable_set (sid, var, new, true)   -- not logged, but 'true' enables variable watch
      end
    end

    return setmetatable({}, var_meta)
  end

  local d = setmetatable ({}, svc_meta)
  rawset (self, dev, d)
  return d
end

-----
--
-- export values and methods
--
local RESERVED = "RESERVED"     -- placeholder to be filled in elsewhere

local api = {
  
  devices = devices, 
  scenes  = scenes,
  -- TODO: find a way to access rooms = rooms,
  
  bridge = chdev.bridge,      -- 2020.02.12  Bridge utilities 
  find_device = find_device,  -- 2021.02.03  find device by attribute: name / id / altid / etc...
  find_scene = find_scene,    -- 2021.03.05  find scene by name

  cpu_table  = function() return time_table "cpu(s)"  end,
  wall_table = function() return time_table "wall(s)" end,

   -- reserved placeholders (table is otherwise READONLY)
  req_table = RESERVED, 
  mqtt      = RESERVED,
}

return setmetatable (api, api_meta)   -- enable virtualization of device variables and actions  

-----
