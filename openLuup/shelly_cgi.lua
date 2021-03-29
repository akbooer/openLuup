#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

local wsapi = require "openLuup.wsapi" 

local ABOUT = {
  NAME          = "shelly_cgi",
  VERSION       = "2021.03.29b",
  DESCRIPTION   = "Shelly-like API for relays and scenes, and Shelly MQTT bridge",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2020-2021 AKBooer",
  DOCUMENTATION = "",
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

-- shelly_cgi.lua
-- see: https://shelly-api-docs.shelly.cloud/#shelly-family-overview
-- see: http://keplerproject.github.io/wsapi/libraries.html

-- 2021.02.01  add Shelly Bridge
-- 2021.02.17  add LastUpdate time to individual devices
-- 2021.03.01  don't start Shelly bridge until first "shellies/..." MQTT message
-- 2021.03.05  allow /relay/xxx and /scene/xxx to have id OR name
-- 2021.03.28  add Shelly 1/1PM
-- 2021.03.29  use "input_event" topic for scenes to denote long push, etc.


--local socket    = require "socket"
local json      = require "openLuup.json"
local luup      = require "openLuup.luup"
local requests  = require "openLuup.requests"         -- for data_request?id=status response
local chdev     = require "openLuup.chdev"            -- to create new bridge devices

local SID = {
    hag       = "urn:micasaverde-com:serviceId:HomeAutomationGateway1",   -- run scene
    hadevice  = "urn:micasaverde-com:serviceId:HaDevice1",                -- LastUpdate, Toggle
    switch    = "urn:upnp-org:serviceId:SwitchPower1",                          
    scene     = "urn:micasaverde-com:serviceId:SceneController1",
    energy    = "urn:micasaverde-com:serviceId:EnergyMetering1",
    
    sBridge   = "urn:akbooer-com:serviceId:ShellyBridge1",
    shellies  = "shellies",
  }


local settings =       -- complete device settings
  {
    device = {
      name  = "openLuup_shelly_server",
      fw    = ABOUT.VERSION,
    },
    mqtt = {
      enable = true,
      port = 1883,
      keep_alive = 60,
    },
    lat = luup.latitude,
    lng = luup.longitude,
  }
 
-------------------------------------------
--
-- Shelly-like CGI API for all openLuup devices
--

-- perform generic luup action
local function call_action (info, ...)
  -- returns: error (number), error_msg (string), job (number), arguments (table)
  info.status, info.message, info.job = luup.call_action(...)
end

-- easy HTTP request to run a scene
local function scene (info) 
  if luup.scenes[info.id] then
    call_action(info, SID.hag, "RunScene", {SceneNum = info.id}, 0)
  end
  return info
end

-- easy HTTP request to switch a switch
local turn = {
    on      = function (info) call_action (info, SID.switch, "SetTarget", {newTargetValue = '1'}, info.id) end,
    off     = function (info) call_action (info, SID.switch, "SetTarget", {newTargetValue = '0'}, info.id) end,
    toggle  = function (info) call_action (info, SID.hadevice, "ToggleState", {}, info.id) end,
  }
  
local function simple()
  local d = settings.device
  return {
    type  = d.name,
    fw    = d.fw,
  }
end
  
local function relay (info)
  local op = info.parameters.turn
  local fct = turn[op]
  local d = luup.devices[info.id]
  if fct and d then fct(info) end
  return info
end

local function status (info)
  local result = requests.status (nil, {DeviceNum = info.id})   -- already JSON encoded
  return (result == "Bad Device") and info or result            -- info has default error message
end

local function update_dynamic_settings ()
  local t = os.time()
  settings.unixtime = t
  settings.time = os.date ("%H:%M", t)
end

local function config (info)
  update_dynamic_settings ()
  return settings
end

local function unknown (info)
  info.status = -1
  info.message = "invalid action request"
  return info
end


local dispatch = {
    shelly    = simple,
    relay     = relay,
    scene     = scene,
    status    = status,
    settings  = config,
  }
  
-- CGI entry point

function run(wsapi_env)
  
  local req = wsapi.request.new(wsapi_env)
  local res = wsapi.response.new ()
  res:content_type "text/plain" 
  
  local command = req.script_name
  local action, path = command: match "/(%w+)/?(.*)"
  local id = tonumber(path: match "^%d+")
  
  local ol = luup.openLuup
  local finders = { 
      relay = ol.find_device,
      scene = ol.find_scene,
    }
  local finder = finders[action]
    
  if not id and finder then         -- try device/scene by name
    local name = wsapi.util.url_decode (path: match "^[^/%?]+")
    id = finder {name = name}
    print ("name:", name, "id:", id, type(id))
  end
  
  local info = {command = command, id = id, parameters = req.GET}
  local fct = dispatch[action] or unknown
  
  unknown(info)   -- set default error message (to be over-written)
  
  local reply, err = fct(info)       -- input and output parameters also returned (unencoded) in info
  if type(reply) == "table" then
    reply, err = json.encode(reply)
  end
  res: write (reply or err)
  res:content_type "application/json"
  
  return res:finish()
end

--
-- END of Shelly CGI
--
--------------------------------------------------


--------------------------------------------------
--
-- Shelly MQTT Bridge
--

local devices = {}      -- gets filled with device info on MQTT connection
local devNo             -- bridge device number (set on startup)


local DEV = {
  light       = "D_BinaryLight1.xml",
  dimmer      = "D_DimmableLight1.xml",
  thermos     = "D_HVAC_ZoneThermostat1.xml",
  motion      = "D_MotionSensor1.xml",
  controller  = "D_SceneController1.xml",
  combo       = "D_ComboDevice1.xml",
  rgb         = "D_DimmableRGBLight1.xml",
  shelly      = "D_GenericShellyDevice.xml",

}

-- option for allowing variable to be set with or without logging
local function variable_set (sid, var, val, dno, log)
  local d = luup.devices[dno]
  if d then
    if log == false then                            -- note that nil will allow logging
      d: variable_set (sid, var, val, true)         -- not logged, but 'true' enables variable watch
    else
      luup.variable_set (sid, var, val, dno)
    end
  end
end

----------------------
--
-- device specific variable updaters
--
-- NB: only called if variable has CHANGED value
--

local function generic() end

--[[
  for switch in "momentary" mode: 
  input_event is {"event":"S","event_cnt":57}
  added to the switch number 0/1/2/...
--]]
local push_event = {
      S   = 10,  -- shortpush 	
      L   = 20,  -- longpush 	
      SS  = 30,  -- double shortpush 	
      SSS = 40,  -- triple shortpush 	
      SL  = 50,  -- shortpush + longpush 	
      LS  = 60,  -- longpush + shortpush 
    }	
    
--local function ix3 (dno, var) 
----  luup.log ("ix3 - update: " .. var)
--  -- look for change of value of input/n [n = 0,1,2]
--  local button = var: match "^input/(%d)"
--  if button then
--    variable_set (SID.scene, "sl_SceneActivated", button, dno)
--    variable_set (SID.scene, "LastSceneTime", os.time(), dno)
--  end
--end

local function ix3 (dno, var, value) 
--  luup.log ("ix3 - update: " .. var)
  -- look for change of value of input/n [n = 0,1,2]
  local button = var: match "^input_event/(%d)"
  if button then
    local event = json.decode (value)
    local push = push_event[event]
    if push then
      local scene = button + push
      variable_set (SID.scene, "sl_SceneActivated", scene, dno)
      variable_set (SID.scene, "LastSceneTime", os.time(), dno)
    end
  end
end

local function sw2_5(dno, var, value) 
--  luup.log ("sw2.5 - update: " .. var)
  local child, attr = var: match "^relay/(%d)/?(.*)"
  if child then
    local altid = luup.attr_get ("altid", dno)
    local cdno = luup.openLuup.find_device {altid = table.concat {altid, '/', child} }
    if cdno then
      if attr == '' then
        variable_set (SID.switch, "Status", value == "on" and '1' or '0', cdno)
      elseif attr == "power" then
        variable_set (SID.energy, "Watts", value, cdno, false)    -- don't log power updates
      elseif attr == "energy" then
        variable_set (SID.energy, "KWH", math.floor (value / 60) / 1000, cdno, false)  -- convert Wmin to kWh, don't log
      end
    end
  end
end



----------------------

local function model_info (upnp, updater, children)
  return {upnp = upnp, updater = updater, children = children}
end

local unknown_model = model_info (DEV.controller, generic)
local models = setmetatable (
  {
    ["SHSW-1"]  = model_info (DEV.light, sw2_5),
    ["SHSW-PM"] = model_info (DEV.light, sw2_5),
    ["SHIX3-1"] = model_info (DEV.controller, ix3),
    ["SHSW-25"] = model_info (DEV.shelly, sw2_5, {DEV.light, DEV.light})      -- two child devices
  },{
    __index = function () return unknown_model end
  })


local function _log (msg)
  luup.log (msg, "luup.shelly")
end

local function create_device(info)
  local room = luup.rooms.create "Shellies"     -- create new device in Shellies room

  local offset = luup.variable_get (SID.sBridge, "Offset", devNo)
  if not offset then 
    offset = luup.openLuup.bridge.nextIdBlock()  
    variable_set (SID.sBridge, "Offset", offset, devNo)
  end
  local dno = luup.openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
  
  local name, altid, ip = info.id, info.id, info.ip
  
  local _, s = luup.inet.wget ("http://" .. ip .. "/settings")
  if s then
    s = json.decode (s)
    if s then name = s.name or name end
  else 
    _log "no Shelly settings name found"
  end
  
  local upnp_file = models[info.model].upnp
  
  local dev = chdev.create {
    devNo = dno,
    internal_id = altid,
    description = name,
    upnp_file = upnp_file,
--    json_file = json_file,
    parent = devNo,
    room = room,
    ip = info.ip,                           -- include ip address of Shelly device
    mac = info.mac,                         -- ditto mac
    manufacturer = "Allterco Robotics",
  }
  
  dev.handle_children = true                -- ensure that any child devices are handled
  luup.devices[dno] = dev                   -- add to Luup devices
  
  -- create extra child devices if required
  
  local children = models[info.model].children or {}
  local childID = "%s/%s"
  for i, upnp_file2 in ipairs (children) do
    local cdno = luup.openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
    local cdev = chdev.create {
      devNo = cdno,
      internal_id = childID: format (altid, i-1),
      description = childID: format (name, i-1),
      upnp_file = upnp_file2,
  --    json_file = json_file,
      parent = dno,
      room = room,
    }
    
    luup.devices[cdno] = cdev                   -- add to Luup devices
  end
  
  return dno
end

local function init_device (info)
  
  local altid = info.id
  if devices[info.id] then return end       -- device already registered

  _log ("New Shelly announced: " .. altid)
  local dno = luup.openLuup.find_device {altid = altid} 
                or 
                  create_device (info)
                  
  luup.devices[dno].handle_children = true  -- ensure that it handles child requests
  devices[altid] = dno                      -- save the device number, indexed by id
  
  -- update info, it may have changed
  -- info = {"id":"xxx","model":"SHSW-25","mac":"hhh","ip":"...","new_fw":false,"fw_ver":"..."}
  luup.ip_set (info.ip, dno)
  luup.mac_set (info.mac, dno)
  luup.attr_set ("model", info.model, dno)
  luup.attr_set ("firmware", info.fw_ver, dno)
  
end

-- the bridge is a standard Luup plugin
local function create_ShellyBridge()
  local internal_id, ip, mac, hidden, invisible, parent, room, pluginnum 

  local statevariables
  
  return luup.create_device (
            "ShellyBridge",         -- device_type
            internal_id,
            "Shelly",               -- description
            "D_ShellyBridge.xml",   -- upnp_file
            "I_ShellyBridge.xml",   -- upnp_impl
            
            ip, mac, hidden, invisible, parent, room, pluginnum, 
            
            statevariables)  
end

-----
--
-- MQTT callbacks
--

function _G.Shelly_MQTT_Handler (topic, message)
  
  local shellies = topic: match "^shellies/(.+)"
  if not shellies then return end
  
  devNo = devNo       -- ensure that ShellyBridge device exists
            or
              luup.openLuup.find_device {device_type = "ShellyBridge"}
                or
                  create_ShellyBridge ()
  
  if shellies == "announce" then
    local info, err = json.decode (message)
    if not info then _log ("Announce JSON error: " .. (err or '?')) return end
    init_device (info)
  end
  
  local timenow = os.time()
  luup.devices[devNo]: variable_set (SID.hadevice, "LastUpdate", timenow, true)   -- not logged, but watchable

  local  shelly, var = shellies: match "^(.-)/(.+)"

  local child = devices[shelly]
  if not child then return end
  
  local dev = luup.devices[child]
  dev: variable_set (SID.hadevice, "LastUpdate", timenow, true)     -- not logged, but 'true' enables variable watch
  
  local old = luup.variable_get (shelly, var, child)
  if message ~= old then
    dev: variable_set (shelly, var, message, true)                  -- not logged, but 'true' enables variable watch
    local model = luup.attr_get ("model", child)
    models[model].updater (child, var, message)
  end
end

luup.register_handler ("Shelly_MQTT_Handler", "mqtt:shellies/#")   -- * * * * MQTT wildcard subscription * * * *

-----
