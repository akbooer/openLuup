local ABOUT = {
  NAME          = "openLuup.api",
  VERSION       = "2021.05.09",
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
-- whilst retaining the original for compatibility with legacy plugins and code.
--
-- device variable and attributes, plus other system variables and attributes 
-- (like cpu and wall-clock times) are directly accessible as API variables.


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
local timers        = require "openLuup.timers"


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
--      local name = devices[n].description: match "%s*(.*)"
      local name = devices[n].attributes.name: match "%s*(.*)"
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

local function readonly (_, x) error ("ERROR - READONLY: attempt to create index " .. x, 2) end

-----
--
-- virtualization of device variables
-- 2021.04.25  functionality added to openLuup structure itself
--

local SID = tables.SID
local attr_alias = {attr = true, attributes = true}   -- pseudo serviceId for virtual devices


local api_meta = {__newindex = readonly, __call = api_iterator}

function api_meta:__index (dev)
  
  if not devices[dev] then return end   -- don't create anything for non-existent device
  
  local dev_meta = {__newindex = readonly}
        
  function dev_meta:__index (sid)
    sid = SID[sid] or sid             -- handle possible serviceId aliases (see servertables.SID)
    
    local svc_meta = {}
    
    function svc_meta:__call (action)
      return function (args)
        local d = devices[dev]
        if d then 
          return d: call_action (sid, action, args) 
        else
          return nil, "no such device #" .. tostring(dev)
        end
      end
    end

    function svc_meta:__index (var)
      local d = devices[dev]
      if attr_alias[sid] then return d.attributes[var] end
      local v = d: variable_get (sid, var) or {}
      return v.value, v.time
    end
    
    function svc_meta:__newindex (var, new)
      local d = devices[dev]
      if attr_alias[sid] then d.attributes[var] = new end
      new = tostring(new)
      local old = self[var]
      if old ~= new then
        d: variable_set (sid, var, new, true)   -- not logged, but 'true' enables variable watch
      end
    end

    return setmetatable({}, svc_meta)
  end

  local d = setmetatable ({}, dev_meta)
  rawset (self, dev, d)
  return d
end

-----
-- create module
-- creation of devices / scenes / rooms
--

local c_meta = {__newindex = readonly }

local c_what = {}

-- device create
-- named parameters are called after the attributes of a device
--
--[[
local function create_device (
      device_type, 
      altid = internal_id, 
      name = description, 
      device_file = upnp_file, 
      impl_file = upnp_impl, 
      ip, 
      mac, 
      hidden, 
      invisible, 
      id_parent = parent, 
      room, 
      plugin = pluginnum, s
      
      tatevariables,
      pnpid, nochildsync, aeskey, reload, nodupid  
  )
--]]

function c_what: device (x)
  luup.log "CREATE SOMETHING"
end

function c_meta:__call (what)
  local this = c_what[what: lower()]
  if not this then error ("undefined openLuup.create object: " .. what, 2) end
  return this
end

-----
--
-- servers module
--

local s_meta = {__newindex = readonly}

-----
--
-- timers module
--
 
local function pcheck (p)
  if type (p) ~= "table" then error ("parameter type should be table, but is: " .. type(p), 3) end
end

local t_meta = {__newindex = readonly}

local t_call = {}
--  delay = {"callback", "delay","parameter", "name"},
function t_call.delay (p)
  pcheck (p)
  return timers.call_delay (p.callback, p.delay, p.parameter, p.name)
end

--  timer = {"callback", "type", "time", "days", "parameter", "recurring"},
-- Type is 1=Interval timer, 2=Day of week timer, 3=Day of month timer, 4=Absolute timer. 
-- For a day of week timer, Days is a comma separated list with the days of the week where 1=Monday and 7=Sunday. 
-- Time is the time of day in hh:mm:ss format. 
function t_call.timer (p)
  local ttype = {interval = 1, day_of_week = 2, day_of_month = 3, absolute = 4}
  pcheck (p)
  local ptype = ttype[p.type] or p.type
  return timers.call_timer (p.callback, ptype, p.time, p.days, p.parameter, p.recurring)
end

function t_meta:__call (what)
  local this = t_call[what]
  if not this then error ("undefined openLuup.timer function: " .. what, 2) end
  return this
end

local t_var = {
  cpu         = "cpu_clock", 
  gmt_offset  = "gmt_offset",
--loadtime    = special case, since it's a constant  
  night       = "is_night",
  now         = "timenow", 
  sunrise     = "sunrise",
  sunset      = "sunset",
  wall        = "timenow", 
}

function t_meta:__index (what)
  if what == "loadtime" then return timers.loadtime end
  local this = t_var[what]
  if not this then error ("undefined openLuup.timer variable: " .. what, 2) end
  return timers[this] ()   -- convert timers module function call into variable value
end


-----
--
-- export values and methods
--
local RESERVED = "RESERVED"     -- placeholder to be filled in elsewhere

local api = {
  

  
  bridge = chdev.bridge,          -- 2020.02.12  Bridge utilities 
  
  create = setmetatable ({}, c_meta),
  
  find_device = devutil.find,     -- 2021.02.03  find device by attribute: name / id / altid / etc...
  find_scene = sceneutil.find,    -- 2021.03.05  find scene by name

  servers = setmetatable ({}, s_meta),
  timers = setmetatable ({}, t_meta),
  
  cpu_table  = function() return time_table "cpu(s)"  end,
  wall_table = function() return time_table "wall(s)" end,

   -- reserved placeholders (table is otherwise READONLY)
  mqtt      = RESERVED,
}

return setmetatable (api, 
--    {
--      __newindex = readonly, 
--      __call = api_iterator,
--    }
    api_meta
  )   -- enable virtualization of device variables and actions  

-----
