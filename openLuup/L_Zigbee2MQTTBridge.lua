module(..., package.seeall)

ABOUT = {
  NAME          = "Zigbee2MQTT Bridge",
  VERSION       = "2022.11.28",
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


--------------------------------------------------
--
-- Zigbee2MQTT Bridge - CONTROL
--
-- this part runs as a standard openLuup device
-- it is a control API only (ie. action requests)
--

function init ()   -- Zigbee2MQTT Bridge device entry point
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

local devices = {}      -- gets filled with device info on MQTT connection
local devNo             -- bridge device number (set on startup)


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

local function add_variables_to_service(Vs, S)
  if type(Vs) == "table" then 
    for name,value in pairs(Vs) do
--      print (name, value)
      if type(value) ~= "table" then
        S[name] = value
      end
    end
  end
end

local function init_device_variables (child, dev)

  local DEV = API[child]
  DEV.hadevice.LastUpdate = os.time()
  add_variables_to_service(dev, DEV.properties)
  
  for srv,vars in pairs (dev) do
    local S = DEV[srv]
    add_variables_to_service (vars, S)
  end

  local definition = dev.definition
  if type(definition) == "table" then
    add_variables_to_service (definition, DEV.definition)
    local exposes = definition.exposes
    if type(exposes) == "table" then
      local exposed = {}
      for _, item in ipairs(exposes) do
        exposed[item.name or '?'] = item.type
      end 
      add_variables_to_service (exposed, DEV.exposes)
    end
  end
end

-----


local function infer_device_type (adev)
  local upnp_file = DEV.zigbee
  local exp = adev.exposes
  if exp then
    if exp.occupancy then
      upnp_file = DEV.motion
    elseif exp.light then
      upnp_file = DEV.switch
    elseif exp.switch then
      upnp_file = DEV.scene
    end
  end
  return upnp_file
end


local function create_device(adev)
  local props = adev.properties
  local friendly_name = props.friendly_name
  local ieee_address = props.ieee_address
  _log ("New Zigbee detected: " .. ieee_address)
  
  local room = luup.rooms.create "Zigbee"     -- create new Zigbee room, if necessary
  local offset = API[devNo][SID.Zigbee2MQTTBridge].Offset
  local dno = openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
  local upnp_file = infer_device_type (adev)
  
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
  
  return dno
end
local function init_device (adev)
  local dev = adev.properties
  local ieee_address = dev.ieee_address
  local dno = openLuup.find_device {altid = ieee_address} 
                or 
                  create_device (adev)
                  
  luup.devices[dno].handle_children = true    -- ensure that it handles child requests
  devices[ieee_address] = dno                 -- save the device number, indexed by id
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
        exposed[item.name or '?'] = item.type
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
        init_device_variables (child, dev)
      end
    end
  end
end

-----

local function ignore_topic (topic)
  _log (table.concat ({"Topic ignored", topic}, " : "))
end


local function handle_bridge_topics (subtopic, message)
  if subtopic: match "^devices" then
    create_devices (message)
  else
    ignore_topic ("bridge/" .. subtopic)
  end
end

local function handle_friendly_names (topic)
  
  ignore_topic (topic)
 
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

  API[devNo][chdev.bridge.SID].Remote_ID = 716833     -- ensure ID for "Zigbee2MQTTBridge" exists
  API[devNo].hadevice.LastUpdate = os.time()

  message = json.decode (message) or message          -- treat invalid JSON as plain text

  local subtopic = topic: match "^bridge/(.+)"
  if subtopic then 
    handle_bridge_topics (subtopic, message)
  else
    handle_friendly_names (topic, message)
  end

end

-- startup
function start (config)
  config = config or {}
  
  local prefixes = config.Prefix or "zigbee2mqtt"       -- subscribed prefixes
  
  for prefix in prefixes: gmatch "[^%s,]+" do
    luup.register_handler ("Zigbee2MQTT_Handler", "mqtt:" .. prefix .. "/#", prefix)   -- MQTT subscription
  end

end

-----
