module(..., package.seeall)

ABOUT = {
  NAME          = "mqtt_shelly",
  VERSION       = "2021.04.02",
  DESCRIPTION   = "Shelly MQTT bridge",
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


-- 2021.02.01  original Shelly Bridge
-- 2021.02.17  add LastUpdate time to individual devices
-- 2021.03.01  don't start Shelly bridge until first "shellies/..." MQTT message
-- 2021.03.28  add Shelly 1/1PM
-- 2021.03.29  use "input_event" topic for scenes to denote long push, etc.
-- 2021.03.30  use DEV and SID definitions from openLuup.servertables
-- 2021.03.31  put button press processing into generic() function (works for ix3, sw1, sw2.5, ...) 
-- 2021.04.02  make separate L_ShellyBridge file


local json      = require "openLuup.json"
local luup      = require "openLuup.luup"
local chdev     = require "openLuup.chdev"            -- to create new bridge devices
local tables    = require "openLuup.servertables"     -- for standard DEV and SID definitions

local DEV = tables.DEV {
    shelly      = "D_GenericShellyDevice.xml",
  }

local SID = tables.SID {
    sBridge   = "urn:akbooer-com:serviceId:ShellyBridge1",
    shellies  = "shellies",
  }


--------------------------------------------------
--
-- Shelly MQTT Bridge - CONTROL
--
-- this part runs as a standard device
-- it is a control API only (ie. action requests)
--

local devNo             -- bridge device number (set on startup)

local function SetTarget (dno, args)
  local id = luup.attr_get ("altid", dno)
  local shelly, relay = id: match "^([^/]+)/(%d)$"    -- expecting "shellyxxxx/n"
  if relay then
    local val = tonumber (args.newTargetValue)
    luup.variable_set (SID.switch, "Target", val, dno)
    local on_off = val == 1 and "on" or "off"
    shelly = table.concat {"shellies/", shelly, '/relay/', relay, "/command"}
    luup.openLuup.mqtt.publish (shelly, on_off)
  else 
    return false
  end
end

local function ToggleState (dno)
  local val = luup.variable_get (SID.switch, "Status", dno)
  SetTarget (dno, {newTargetValue = val == '0' and '1' or '0'})
end

local function generic_action (serviceId, action)
  local function noop(lul_device)
    local message = "service/action not implemented: %d.%s.%s"
    luup.log (message: format (lul_device, serviceId, action))
    return false
  end

  local SRV = {
      [SID.switch]    = {SetTarget = SetTarget},
      [SID.hadevice]  = {ToggleState = ToggleState},
    }
  
  local service = SRV[serviceId] or {}
  local act = service [action] or noop
  if type(act) == "function" then act = {run = act} end
  return act
end

function init (lul_device)   -- Shelly Bridge device entry point
  devNo = tonumber (lul_device)
	luup.devices[devNo].action_callback (generic_action)    -- catch all undefined action calls
  luup.set_failure (0)
  return true, "OK", "ShellyBridge"
end

--
-- end of Luup device file
--
--------------------------------------------------


--------------------------------------------------
--
-- Shelly MQTT Bridge - MODEL and VIEW
--
-- this part runs as a system module and can create a bridge device
-- as well as subsequent child devices, and update their variables
--

local devices = {}      -- gets filled with device info on MQTT connection
local devNo             -- bridge device number (set on startup)

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

-- generic actions for all devices
local function generic (dno, var, value) 
  -- button pushes behave as scene controller
  -- look for change of value of input/n [n = 0,1,2]
  local button = var: match "^input_event/(%d)"
  if button then
    local input = json.decode (value)
    local push = input and push_event[input.event]
    if push then
      local scene = button + push
      variable_set (SID.scene, "sl_SceneActivated", scene, dno)
      variable_set (SID.scene, "LastSceneTime", os.time(), dno)
    end
  end
end

local function ix3 ()
  -- all the work done in generic actions above
  --  luup.log ("ix3 - update: " .. var)
end

local function sw2_5(dno, var, value) 
--  luup.log ("sw2.5 - update: " .. var)
  local action, child, attr = var: match "^%a+/(%d)/?(.*)"
  if child then
    local altid = luup.attr_get ("altid", dno)
    local cdno = luup.openLuup.find_device {altid = table.concat {altid, '/', child} }
    if cdno then
      if action == "relay" then
        if attr == '' then
          variable_set (SID.switch, "Status", value == "on" and '1' or '0', cdno)
        elseif attr == "power" then
          variable_set (SID.energy, "Watts", value, cdno, false)    -- don't log power updates
        elseif attr == "energy" then
          variable_set (SID.energy, "KWH", math.floor (value / 60) / 1000, cdno, false)  -- convert Wmin to kWh, don't log
        end
      elseif action == "input" then
          -- possibly set the input as a security/tamper switch
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
    generic (child, var, message)
    local model = luup.attr_get ("model", child)
    models[model].updater (child, var, message)
  end
end

luup.register_handler ("Shelly_MQTT_Handler", "mqtt:shellies/#")   -- * * * * MQTT wildcard subscription * * * *

-----
