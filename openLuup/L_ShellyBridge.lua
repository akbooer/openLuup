module(..., package.seeall)

ABOUT = {
  NAME          = "mqtt_shelly",
  VERSION       = "2024.02.11",
  DESCRIPTION   = "Shelly MQTT bridge",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2020-present AKBooer",
  DOCUMENTATION = "",
  LICENSE       = [[
  Copyright 2020-present AK Booer

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
-- 2021.04.17  use openLuup device variable virtualizer, fix SetTarget for Shelly-1 (thanks @Elcid)
-- 2021.04.25  add Shelly SHPLG2-1 (thanks @ArcherS)
-- 2021.05.02  check for non-existent device (pre-announcement)
-- 2021.05.10  add missing bridge_utilities.SID, "Remote_ID"
-- 2021.06.21  add child H&T devices for Shelly H&T
-- 2021.10.21  add Dimmer2 (thanks @ArcherS)
-- 2021.11.02  Dimmer2 improvements
-- 2021.11.08  Dimmer2 slider status and control

-- 2022.10.24  add Max/Min Temp for H&T child sensors (implemented through Historian database aggregation)
-- 2022.11.01  reduce Max/Min Temp cache size to under a day (hopefully)
-- 2022.11.07  add H & T variables to H&T parent device (for display)
-- 2022.11.15  remove hack for H & T cache size (now handled by servertables.cache_rules)
-- 2022.11.16  basic infrastructure for Shelly Plus (Shelly-NG) devices

-- 2023.01.20  create Shelly Gen2 devices
-- 2023.03.15  add support for Plus i4 events
-- 2023.03.21  Plus i4 improvements

-- 2024.02.05  add Plus H_T
-- 2024.02.11  handle devices which may not have assigned IP address (thanks @a-lurker)
-- 2024.02.14  handle battery level / voltage for Plus devices (thanks @a-lurker)


local json      = require "openLuup.json"
local luup      = require "openLuup.luup"
local chdev     = require "openLuup.chdev"            -- to create new bridge devices
local tables    = require "openLuup.servertables"     -- for standard DEV and SID definitions

--local pretty = require "openLuup.loader" .shared_environment.pretty


local DEV = tables.DEV {
    shelly      = "D_GenericShellyDevice.xml",
  }

local SID = tables.SID {
    sBridge   = "urn:akbooer-com:serviceId:ShellyBridge1",
    shellies  = "shellies",
  }

local openLuup = luup.openLuup
local API = require "openLuup.api"

--------------------------------------------------
--
-- Shelly MQTT Bridge - CONTROL
--
-- this part runs as a standard device
-- it is a control API only (ie. action requests)
--
do
  local devNo             -- bridge device number (set on startup)

  local function SetTarget (dno, args)
    local id = luup.attr_get ("altid", dno)
    local dfile = luup.attr_get ("device_file", dno)
    local dtype = dfile == DEV.dimmer and "light" or "relay"
    local shelly, relay = id: match "^([^/]+)/(%d)$"    -- expecting "shellyxxxx/n"
    if shelly then
      local val = tostring(tonumber (args.newTargetValue) or 0)
      API[dno].switch.Target = val
      local on_off = val == '1' and "on" or "off"
      shelly = table.concat {"shellies/", shelly, '/', dtype, '/', relay, "/command"}
      openLuup.mqtt.publish (shelly, on_off)
    else 
      return false
    end
  end

  local function ToggleState (dno)
    local val = API[dno].switch.Status
    SetTarget (dno, {newTargetValue = val == '0' and '1' or '0'})
  end

  local function SetLoadLevelTarget (dno, args)
    local id = luup.attr_get ("altid", dno)
    local shelly, relay = id: match "^([^/]+)/(%d)$"    -- expecting "shellyxxxx/n"
    if shelly then
      local val_n = tonumber (args.newLoadlevelTarget) or 0
      local val = tostring(val_n)
      API[dno].dimming.LoadLevelTarget = val
      -- shellies/shellydimmer-<deviceid>/light/0/set 	
      -- accepts a JSON payload in the format 
      -- {"brightness": 100, "turn": "on", "transition": 500}
      shelly = table.concat {"shellies/", shelly, '/light/', relay, "/set"}
      local command = json.encode {brightness = val_n}
      openLuup.mqtt.publish (shelly, command)
    else 
      return false
    end
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
        [SID.dimming]   = {SetLoadLevelTarget = SetLoadLevelTarget},
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

local shelly_devices = {}      -- gets filled with device info on MQTT connection
local devNo                    -- bridge device number (set on startup)

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

-- generic actions for all Gen 1 devices
local function generic (dno, var, value) 
  -- battery level
  if type(var) ~= "string" then return end
  if var == "sensor/battery" then
    API[dno].HaDevice1.BatteryLevel = value
    return
  end
  -- button pushes behave as scene controller
  -- look for change of value of input/n [n = 0,1,2]
  local button = var: match "^input_event/(%d)"
  if button then
    local input = json.decode (value)
    local push = input and push_event[input.event]
    if push then
      local scene = button + push
      local S = API[dno].scene
      S.sl_SceneActivated = scene
      S.LastSceneTime = os.time()
    end
  end
end

local function ix3 ()
  -- all the work done in generic actions above
  --  luup.log ("ix3 - update: " .. var)
end

local function sw2_5(dno, var, value) 
--  luup.log ("sw2.5 - update: " .. var)
  local action, child, attr = var: match "^(%a+)/(%d)/?(.*)"
  if child then
    local altid = luup.attr_get ("altid", dno)
    local cdno = openLuup.find_device {altid = table.concat {altid, '/', child} }
    if cdno then
      local D = API[cdno]
      if action == "relay" then
        if attr == '' then
          D.switch.Status = value == "on" and '1' or '0'
        elseif attr == "power" then
          D.energy.Watts = value
        elseif attr == "energy" then
          D.energy.KWH = math.floor (value / 60) / 1000   -- convert Wmin to kWh
        end
      elseif action == "input" then
          -- possibly set the input as a security/tamper switch
      end
    end
  end
end

-- H&T sensor
-- sensor/[temperature,humidity] - also [battery,error,act_reasons]
local function h_t (dno, var, value)
  local metric = var: match "^sensor/(.+)"
  if not metric then return end

  local mtype = metric: sub (1,1)     -- first character [t,h,b]
  local altid = luup.attr_get ("altid", dno)
  local children = {t = 0, h = 1}   -- altid suffixes for child device types
  local child = children[mtype]
  local cdno = openLuup.find_device {altid = table.concat {altid, '/', child} }
  if cdno then
    local D = API[cdno]
    local P = API[dno]                -- parent device
    if mtype == 't' then
      P.temp.CurrentTemperature = value
      D.temp.CurrentTemperature = value
      D.temp.MinTemp = value              -- implemented through Historian database aggregation
      D.temp.MaxTemp = value              -- ditto
    elseif mtype == 'h' then
      value = math.floor(value + 0.5)     -- humidity simply isn't this accurate
      P.humid.CurrentLevel = value
      D.humid.CurrentLevel = value
    end
  end

end

-- Dimmer 2
--
local function dm_2 (dno, var, value)
  local action, child, attr = var: match "^(%a+)/(%d)/?(.*)"
  if child then
    local altid = luup.attr_get ("altid", dno)
    local cdno = openLuup.find_device {altid = table.concat {altid, '/', child} }
    if cdno then
      local D = API[cdno]
      if action == "light" then
        if attr == '' then
          D.switch.Status = value == "on" and '1' or '0'
        elseif attr == "power" then
          D.energy.Watts = value
        elseif attr == "energy" then
          D.energy.KWH = math.floor (value / 60) / 1000   -- convert Wmin to kWh
        elseif attr == "status" then
          -- {"ison":false,"source":"input","has_timer":false,"timer_started":0,    
          --  "timer_duration":0,"timer_remaining":0,"mode":"white","brightness":48,"transition":0}
          local status = json.decode (value)
          if type (status) == "table" then
            if status.brightness then
              D.dimming.LoadLevelStatus = status.brightness
            end
          end
        end
      elseif action == "input" then
          -- possibly set the input as a security/tamper switch
      end
    end
  end
end


----------------------
--
-- Plus model updaters (use RPC syntax)
--

-- generic actions for all Gen Plus devices
local function generic_plus (dno, subtopic, info) 
  
  print(subtopic, json.encode(info))
  local D = API[dno]
  
   -- battery level
  if subtopic:match "status/devicepower" then
    local battery = info.battery
    local external = info.external
    local V, percent = '', ''
    if external and external.present then     -- as per @a-lurker's wishes
      V = 5
      percent = 100
    elseif battery then
      V = battery.V
      percent = battery.percent
    end
    local S = D.HaDevice1
    S.BatteryLevel = percent
    S.voltage = V
  end
 
end

--[[
{
  "src":"shellyplusi4-a8032ab0c018",
  "dst":"shellyplusi4-a8032ab0c018/events",
  "method":"NotifyEvent",
  "params":{"ts":1678882095.02,"events":[{"component":"input:2", "id":2, "event":"btn_up", "ts":1678882095.02}]}}
--]]

local function i4 (dno, info)    -- info is decoded JSON message body
  --[[
        {
        "component": "input:2",
        "id": 2,
        "event": "btn_up",  -- also "single_push", "long_push"
        "ts": 1678882095.02
      }
--]]
  if info.method == "NotifyEvent" then 
    local D = API[dno]
    local altid = D.attr.altid
    local watched = {single_push = true, long_push=true}
    for _, event in ipairs(info.params.events) do
      local j = json.encode(event): gsub('%c','')
      luup.log (j)
      local id = event.id
      local action = event.event
      if watched[action] then
        D[altid]["input_event/" .. id] = j
        local S = D.scene
        S.sl_SceneActivated = table.concat {action, '_', id}
        S.LastSceneTime = os.time()
      end
    end
  end
end

local function plus_h_t(dno, info)
--  print(pretty {PLUS_H_T = info})
  if info.tC then 
    h_t(dno, "sensor/temperature", info.tC)
  elseif info.rh then 
    h_t(dno, "sensor/humidity", info.rh)
  end
end

----------------------

local function model_info (upnp, updater, children)
  return {upnp = upnp, updater = updater, children = children}
end
--[[
  H&T device:

    shellies/shellyht-<deviceid>/sensor/temperature: in °C or °F depending on configuration
    shellies/shellyht-<deviceid>/sensor/humidity: RH in %
    shellies/shellyht-<deviceid>/sensor/battery: battery level in %
--]]

local unknown_model = model_info (DEV.shelly, generic)
local models = setmetatable (
  {
    ["SHSW-1"]    = model_info (DEV.shelly, sw2_5, {DEV.light}),
    ["SHSW-PM"]   = model_info (DEV.shelly, sw2_5, {DEV.light}),
    ["SHIX3-1"]   = model_info (DEV.controller, ix3),
    ["SHSW-25"]   = model_info (DEV.shelly, sw2_5, {DEV.light, DEV.light}),       -- two child devices
    ["SHPLG-S"]   = model_info (DEV.shelly, sw2_5, {DEV.light}),
    ["SHPLG2-1"]  = model_info (DEV.shelly, sw2_5, {DEV.light}),
    ["SHHT-1"]    = model_info (DEV.shelly, h_t,   {DEV.temperature, DEV.humidity}),
    ["SHDM-2"]    = model_info (DEV.shelly, dm_2,  {DEV.dimmer}),
    
    ["shellyplusi4"]    = model_info (DEV.controller, i4),    -- TODO: make new PLUS versions of these
    ["shellyplus2pm"]   = model_info (DEV.shelly, sw2_5, {DEV.light, DEV.light}),
    ["shellyplusht"]    = model_info (DEV.shelly, plus_h_t, {DEV.temperature, DEV.humidity}),
  },{
    __index = function () return unknown_model end
  })


local function _log (msg)
  luup.log (msg, "luup.shelly")
end

local function format_mac_address(mac)
  return (mac or ''):gsub("..", "%1:"):sub(1,-2)
end

local function create_device(info)
  local room = luup.rooms.create "Shellies"     -- create new device in Shellies room

  local offset = API[devNo][SID.sBridge].Offset
  if not offset then 
    offset = openLuup.bridge.nextIdBlock()  
    API[devNo][SID.sBridge].Offset = offset
  end
  local dno = openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
  
  local name, altid = info.id, info.id
  
  local upnp_file = models[info.model].upnp
  
  local dev = chdev.create {
    devNo = dno,
    internal_id = altid,
    description = name,
    upnp_file = upnp_file,
--    json_file = json_file,
    parent = devNo,
    room = room,
    ip = info.ip,                             -- include ip address of Shelly device
    mac = format_mac_address(info.mac),       -- ditto mac, adding ':' (thanks @a-lurker)
    manufacturer = "Allterco Robotics",
  }
  
  dev.handle_children = true                -- ensure that any child devices are handled
  luup.devices[dno] = dev                   -- add to Luup devices
  
  -- create extra child devices if required
  
  local children = models[info.model].children or {}
  local childID = "%s/%s"
  for i, upnp_file2 in ipairs (children) do
    local cdno = openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
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
  if shelly_devices[info.id] then return end       -- device already registered

  _log ("New Shelly announced: " .. altid)
  local dno = openLuup.find_device {altid = altid} 
                or 
                  create_device (info)
                  
  luup.devices[dno].handle_children = true  -- ensure that it handles child requests
  shelly_devices[altid] = dno                      -- save the device number, indexed by id
  
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

local function init_shelly_bridge ()
  devNo = devNo       -- ensure that ShellyBridge device exists
            or
              openLuup.find_device {device_type = "ShellyBridge"}
                or
                  create_ShellyBridge ()
  
  local bridge = API[devNo]
  bridge[chdev.bridge.SID].Remote_ID = 543779     -- 2021.0105.10  ensure ID for "ShellyBridge" exists  
  bridge.hadevice.LastUpdate = os.time()
  
  return devNo
end


-----
--
-- MQTT callbacks
--

--
-- on announcement, get status with, eg,
-- shellies/shellyplusi4-a8032ab0c018/rpc {"id":123,"method":"Mqtt.GetConfig"}
--

function _G.Shelly_Plus_Handler (topic, message)
  
  init_shelly_bridge ()
  
  if not devNo then return end      -- wait until bridge exists
  _log (table.concat ({"ShellyPlus:", topic, message}, ' '))
  
  local shelly, subtopic = topic: match "([^/]+)/(.+)"
  
  if subtopic == "online" and message == "true" then    -- get/update configuration
    local id = (tostring {}): match "%w+$"              -- create unique message id
    local msg = json.encode  {id = id, src = "shelly-gen2-cmd", method = "Shelly.GetConfig"}
    openLuup.mqtt.publish (shelly .. "/rpc", msg)
    
  elseif subtopic == "events/rpc" or subtopic: match "^status" then
    
    local child = shelly_devices[shelly]            -- look up device number
    if not child then return end
    
    local info, err = json.Lua.decode (message)
    if err then 
      _log (err) 
      return
    end
    
    local timenow = os.time()
    local D = API[child]
    D.hadevice.LastUpdate = timenow
    
    generic_plus (child, subtopic, info)            -- perform generic update actions
    local model = D.attr.model
    models[model].updater (child, info)             -- perform device specific update actions
    
  end
end

-- handler for Gen 2 responses when creating new device
function _G.Shelly_Gen2_Handler (topic, message)
 
--  init_shelly_bridge ()
  
  if not devNo then return end      -- wait until bridge exists
  _log (table.concat ({"ShellyGen2:", topic, message}, ' '))
  
  if topic ~= "shelly-gen2-cmd/rpc" then return end
  
  local info, err = json.decode (message)
  if err then 
    _log (err) 
    return
  end
    
  -- add old-style info fields...
  -- info = {"id":"xxx","model":"SHSW-25","mac":"hhh","ip":"...","new_fw":false,"fw_ver":"..."}
  local newinfo = {Gen2 = true}
  newinfo.id = info.src    -- id has different meaning in Gen 2
  info = info.result
  local sys = info.sys
  if sys and sys.device then
    newinfo.ip = info.wifi and info.wifi.sta and info.wifi.sta.ip or ''
    newinfo.model = info.mqtt.client_id: match "%w+"       -- can't see anywhere else which has this info
    newinfo.name = sys.device.name or info.id
    newinfo.mac = format_mac_address(sys.device.mac)
    newinfo.fw_ver = sys.device.fw_id
  end
--  _log (json.Lua.encode(newinfo))   -- **
  init_device (newinfo)
end


function _G.Shelly_MQTT_Handler (topic, message)
    
  local shellies = topic: match "^shellies/(.+)"
  if not shellies then return end
  
  init_shelly_bridge ()
  
  if shellies == "announce" then
    _log (message)
    local info, err = json.decode (message)
    if not info then _log ("Announce JSON error: " .. (err or '?')) return end
    init_device (info)
  end
  
  local  shelly, var = shellies: match "^(.-)/(.+)"
  local child = shelly_devices[shelly]
  if not child then return end
  
  local timenow = os.time()
  local D = API[child]
  D.hadevice.LastUpdate = timenow
  
  local S = D[shelly]
  local old = S[var]
  if message ~= old then
    S[var] = message                                  -- save the raw message
    generic (child, var, message)                     -- perform generic update actions
    local model = luup.attr_get ("model", child)
    models[model].updater (child, var, message)       -- perform device specific update actions
  end
end

luup.register_handler ("Shelly_MQTT_Handler", "mqtt:shellies/#")   -- * * * MQTT wildcard subscription * * *
luup.register_handler ("Shelly_Plus_Handler", "mqtt:shellyplus#")
luup.register_handler ("Shelly_Gen2_Handler", "mqtt:shelly-gen2#")  -- rpc response

-----
