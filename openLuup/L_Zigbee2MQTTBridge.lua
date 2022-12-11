module(..., package.seeall)

ABOUT = {
  NAME          = "Zigbee2MQTT Bridge",
  VERSION       = "2022.12.11",
  DESCRIPTION   = "Zigbee2MQTT bridge",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2020-2022 AKBooer",
  DOCUMENTATION = "",
  LICENSE       = [[
  Copyright 2013-2022 AK Booer

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


-- 2022.11.27  new bridge for @a-lurker (based on Tasmota bridge framework)
-- 2022.12.11  add variable initialisation for new scene controllers


local json      = require "openLuup.json"
local luup      = require "openLuup.luup"
local chdev     = require "openLuup.chdev"              -- to create new bridge devices
local tables    = require "openLuup.servertables"       -- for standard DEV and SID definitions

local DEV = tables.DEV {
    zigbee      = "D_GenericZigbeeDevice.xml",
  }

local SID = tables.SID {
    Zigbee2MQTTBridge   = "urn:akbooer-com:serviceId:Zigbee2MQTTBridge1",
  }

local openLuup = luup.openLuup
local API = require "openLuup.api"

local devNo             -- bridge device number (set on startup)

local PREFIX = "zigbee2mqtt"    -- default MQTT topic prefix

local devices = {}      -- gets filled with device info on MQTT bridge/devices PUBLISH and in init() below

-- save list of device names and addresses
local function register_device (dno)
  local S = API[dno].properties                 -- service containing key variables
  devices[S.ieee_address]  = dno                -- save the device number, indexed by id...
  devices[S.friendly_name] = dno                -- ..and friendly name
end

--------------------------------------------------
--
-- Zigbee2MQTT Bridge - CONTROL
--
-- this part runs as a standard openLuup device
-- it is a control API only (ie. action requests)
--

local function SetTarget (dno, args)
  local id = API[dno].attr.altid
  local val = tostring(tonumber (args.newTargetValue) or 0)
  API[dno].switch.Target = val
  local on_off = val == '1' and "ON" or "OFF"
  local zigbee = table.concat {PREFIX, '/', id, "/set/state"}
  openLuup.mqtt.publish (zigbee, on_off)
end

local function ToggleState (dno)
  local val = API[dno].switch.Status
  SetTarget (dno, {newTargetValue = val == '0' and '1' or '0'})
end

local function SetLoadLevelTarget (dno, args)
  local id = API[dno].attr.altid
  local val_n = tonumber (args.newLoadlevelTarget) or 0
  local val = tostring(val_n)
  API[dno].dimming.LoadLevelTarget = val
  local zigbee = table.concat {PREFIX, '/', id, "/set"}
  local command = json.encode {brightness = val_n}
  openLuup.mqtt.publish (zigbee, command)
end

local function SetArmed (dno, args)
  API[dno].security.Armed = args.newArmedValue or '0'
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
      [SID.security]  = {SetArmed = SetArmed},
    }
  
  local service = SRV[serviceId] or {}
  local act = service [action] or noop
  if type(act) == "function" then act = {run = act} end
  return act
end

function init (lul_device)   -- Zigbee2MQTT Bridge device entry point
  devNo = tonumber (lul_device)
  
  local y,m,d = ABOUT.VERSION:match "(%d+)%D+(%d+)%D+(%d+)"
  local version = ("v%d.%d.%d"): format (y%2000,m,d)
  local Vnumber = tonumber ((y%2000)..m..d)
  local D = API[devNo]
  local S = D[SID.Zigbee2MQTTBridge]
  S.Version = version                 -- version number in all possible places!
  S.Vnumber = Vnumber
  D.altui.DisplayLine1 = version
  D.attr.version = version
  
  D[chdev.bridge.SID].Remote_ID = 716833     -- ensure ID for "Zigbee2MQTTBridge" exists

  -- register existing child devices
  for dno in pairs (openLuup.bridge.all_descendants (devNo)) do
    register_device (dno)
  end
  
	luup.devices[devNo].action_callback (generic_action)    -- catch all undefined action calls
  luup.set_failure (0)
  return true, "OK", "Zigbee2MQTTBridge"
end

--
-- end of Luup device file
--
--------------------------------------------------



--------------------------------------------------
--
-- Zigbee2MQTT Bridge - MODEL and VIEW
--
-- this part runs as a system module and can create a bridge device
-- as well as subsequent child devices, and update their variables
--

local generic_variables = {
    battery = {s = SID.hadevice, v = "BatteryLevel"},
    voltage = {s = SID.energy, v = "Voltage"},
  }

-- generic updates for all devices
local function generic (D, topic, message) 
  if type (message) ~= "table" then 
    luup.log ("no JSON payload for " .. topic)
    return
  end
  
  -- update exposed values
  local S = D.exposes
  for n,v in pairs (message) do
    if type (v) == "table" then
      local S2 = D[n]
      for n2,v2 in pairs (v) do
        S2[n2] = tostring(v2)
      end
    else
      S[n] = tostring(v)
    end
  end
  
  -- update generic Luup device variables
  for var, gv in pairs (generic_variables) do
    local value = message[var]
    if value then
      D[gv.s][gv.v] = value
    end
  end
 
end

-- specific device updates

local function update_light (D, message)
  -- state: ON or OFF
  local state = message.state 
  if state then
    D.switch.Status = state == "ON" and '1' or '0'
  end
end

local function update_dimmer (D, message)
  -- brightness: 0 - 100 ?
  local brightness = message.brightness
  if brightness then
    D.dimming.LoadLevelStatus = brightness
  end
  update_light (D, message)       -- on/off
end

local function update_motion (D, message)
  -- occupancy: true or false
  local occupancy = message.occupancy
  -- openLuup simulate of full Tripped / ArmedTripped action would need to use luup.variable_set()
  -- for the time being, just update the basic variables...
  if occupancy ~= nil then    -- note that variable is boolean and false is a valid value!
    D.security.Tripped = occupancy and '1' or '0'
    D.security.LastTrip = tostring(os.time())
  end
end

-- several types of button / scene controller
--
-- Xiaomi WXKG11LM:
--    Triggered action (e.g. a button click). 
--    The possible values are: single, double, triple, quadruple, hold, release.
--
-- Philips 324131092621: (Hue Dimmer Switch)
--    Triggered action (e.g. a button click). 
--    The possible values are: on_press, on_hold, on_hold_release, up_press, up_hold, up_hold_release, 
--    down_press, down_hold, down_hold_release, off_press, off_hold, off_hold_release.
--
local function update_scene_controller (D, message)
  -- button pushes behave as scene controller
  local action = message.action
  if action then
    local S = D.scene
    S.sl_SceneActivated = action
    S.LastSceneTime = os.time()
  end
end

--
-- end of MODEL and VIEW
--
--------------------------------------------------


local function _log (msg)
  luup.log (msg, "luup.zigbee2mqtt")
end


-- the bridge is a standard Luup plugin
local function create_Zigbee2MQTTBridge()
  local internal_id, ip, mac, hidden, invisible, parent, room, pluginnum 

  local offset = openLuup.bridge.nextIdBlock()  
  local statevariables = table.concat {SID.Zigbee2MQTTBridge, ",Offset=", offset} 
   
  return luup.create_device (
            "Zigbee2MQTTBridge",         -- device_type
            internal_id,
            "Zigbee2MQTT",               -- description
            "D_Zigbee2MQTTBridge.xml",   -- upnp_file
            "I_Zigbee2MQTTBridge.xml",   -- upnp_impl
            
            ip, mac, hidden, invisible, parent, room, pluginnum, 
            
            statevariables)  
end

-----


-- adev = {properties=..., definition=..., exposes=...}
local function init_device_variables (child, adev)

  local DEV = API[child]
  DEV.hadevice.LastUpdate = os.time()
  
  for srv,vars in pairs (adev) do
    local S = DEV[srv]
    for name, value in pairs (vars) do
      S[name] = value
    end
  end
end

-----

local function configure_null () end

local function configure_scene_controller (dno)
  -- special variable initialisation for scene controllers
  local S = API[dno].scene
  S.LastSceneTime = ''
  S.sl_SceneActivated = ''
end

local function infer_device_type (adev)
  local upnp_file = DEV.zigbee
  local configure
  local exp = adev.exposes
  if exp then
    if exp.occupancy then
      upnp_file = DEV.motion
    elseif exp.switch then
     upnp_file = DEV.binary
    elseif exp.action then
      upnp_file = DEV.controller
      configure = configure_scene_controller
    elseif exp.type == "light" then
      upnp_file = DEV.dimmer    -- assuming ATM that most are, these days
    end
  end
  return upnp_file, configure or configure_null
end


local function create_device(adev)
  local props = adev.properties
  local friendly_name = props.friendly_name
  local ieee_address = props.ieee_address
  _log ("New Zigbee detected: " .. ieee_address)
  
  local room = luup.rooms.create "Zigbee"     -- create new Zigbee room, if necessary
  local offset = API[devNo][SID.Zigbee2MQTTBridge].Offset
  local dno = openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
  
  local upnp_file, configure = infer_device_type (adev)
  
  local dev = chdev.create {
    devNo = dno,
    internal_id = ieee_address,
    description = friendly_name or ieee_address,
    upnp_file = upnp_file,
    json_file = nil,      -- may need this one day
    parent = devNo,
    room = room,
    manufacturer = props.manufacturer or "could be anyone",
  }
  
  dev.handle_children = true                -- ensure that any child devices are handled
  luup.devices[dno] = dev                   -- add to Luup devices
  configure (dev)     
  
  return dno
end

local function init_device (adev)  
  local dno = openLuup.find_device {altid = adev.properties.ieee_address} 
                or 
                  create_device (adev)
                  
  luup.devices[dno].handle_children = true              -- ensure that it handles child requests
  return dno
end


local function extract_scalar_variables(Vs)
  local vars = {}
  if type(Vs) == "table" then 
    for name,value in pairs(Vs) do
      if type(value) ~= "table" then
        vars[name] = value
      end
    end
  end
  return vars
end

-- returns a table with serviceIds
-- {properties=..., definition=..., exposes=...}
-- along with their variables and values
local function analyze_device (dev)

  local adev = {}  
  adev.properties = extract_scalar_variables (dev)        -- top level properties

  local definition = dev.definition
  if type(definition) == "table" then
    adev.definition = extract_scalar_variables (definition)
    local exposes = definition.exposes
    if type(exposes) == "table" then
      local exposed = {}
      for _, item in ipairs(exposes) do
        exposed[item.name or "type"] = item.type
      end 
      adev.exposes = exposed
    end
  end
  return adev
end


local function create_devices(info)
  if type(info) ~= "table" then
    _log "bridge/devices payload is not valid JSON"
    return
  end
  for _, dev in ipairs(info) do
    if type(dev) == "table" then
      
      local friendly_name = dev.friendly_name
      local ieee_address = dev.ieee_address

      if friendly_name and ieee_address then
        local adev = analyze_device (dev)      -- all the services and variables
        local child = devices[ieee_address] or init_device (adev)
        init_device_variables (child, adev)
        register_device (child)    -- record its name
      end
    end
  end
end

-----

local function ignore_topic (topic)
  _log (table.concat ({"Topic ignored ", PREFIX, '/', topic}, " : "))
end


local function handle_bridge_topics (topic, message)
  local subtopic = topic: match "^bridge/(.+)"
  if subtopic: match "^devices" then
    create_devices (message)
  else
    ignore_topic (topic)
  end
end

local function update_unknown () end
  
local specific = setmetatable (
  {
    [DEV.light]       = update_light,
    [DEV.dimmer]      = update_dimmer,
    [DEV.motion]      = update_motion,
    [DEV.controller]  = update_scene_controller,
  },{
    __index = function () return update_unknown end   -- no action
  })
  
local function handle_friendly_names (topic, message)
  local dno = devices[topic]
  local D = API[dno]
  if D then
    local dfile = D.attr.device_file
    D.hadevice.LastUpdate = os.time()
    generic (D, topic, message)
    specific [dfile] (D, message)       -- perform device specific update actions
  else
    ignore_topic (topic)
  end
end


-----
--
-- MQTT callbacks
--

function _G.Zigbee2MQTT_Handler (topic, message, prefix)

  topic = topic: match (table.concat {"^", prefix, "/(.+)"})
  if not topic then return end

  devNo = devNo       -- ensure that Bridge device exists
    or
      openLuup.find_device {device_type = "Zigbee2MQTTBridge"}
        or
          create_Zigbee2MQTTBridge ()

  API[devNo].hadevice.LastUpdate = os.time()

  message = json.decode (message) or message          -- treat invalid JSON as plain text

  if topic: match "^bridge/(.+)" then 
    handle_bridge_topics (topic, message)
  else
    handle_friendly_names (topic, message)
  end

end

-- startup
function start (config)
  config = config or {}
  
  local prefixes = config.Prefix or PREFIX        -- a string containing subscribed prefixes
  
  for prefix in prefixes: gmatch "[^%s,]+" do
    luup.register_handler ("Zigbee2MQTT_Handler", "mqtt:" .. prefix .. "/#", prefix)   -- MQTT subscription
  end

end

-----
