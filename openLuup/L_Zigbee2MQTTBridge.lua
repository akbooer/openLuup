module(..., package.seeall)

ABOUT = {
  NAME          = "Zigbee2MQTT Bridge",
  VERSION       = "2021.06.14",
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
local chdev     = require "openLuup.chdev"            -- to create new bridge devices
local tables    = require "openLuup.servertables"     -- for standard DEV and SID definitions

local DEV = tables.DEV {
    zigbee      = "D_GenericZigbeeDevice.xml",
  }

local SID = tables.SID {
    Zigbee2MQTTBridge   = "urn:akbooer-com:serviceId:Zigbee2MQTTBridge1",
  }

local openLuup = luup.openLuup
local VIRTUAL = require "openLuup.api"

local VALID = {}      -- valid topics (set at startup)

--------------------------------------------------
--
-- Zigbee2MQTT Bridge - CONTROL
--
-- this part runs as a standard device
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

local function create_device(altid, name)
  _log ("New Zigbee detected: " .. altid)
  local room = luup.rooms.create "Zigbee"     -- create new device in Zigbee room

  local offset = VIRTUAL[devNo][SID.Zigbee2MQTTBridge].Offset
  local dno = openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
  
--  local upnp_file = models[info.model].upnp
  local upnp_file = DEV.zigbee
  
  local dev = chdev.create {
    devNo = dno,
    internal_id = altid,
    description = name or altid,
    upnp_file = upnp_file,
--    json_file = json_file,
    parent = devNo,
    room = room,
    manufacturer = "could be anyone",
  }
  
  dev.handle_children = true                -- ensure that any child devices are handled
  luup.devices[dno] = dev                   -- add to Luup devices
  
  return dno
end

local function init_device (dev)
  local friendly_name = dev.friendly_name
  local ieee_address = dev.ieee_address
  local dno = openLuup.find_device {altid = ieee_address} 
                or 
                  create_device (ieee_address, friendly_name)
                  
  luup.devices[dno].handle_children = true    -- ensure that it handles child requests
  devices[ieee_address] = dno                 -- save the device number, indexed by id
  return dno
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

local function create_devices(info)
  if type(info) ~= "table" then
    _log "bridge/devices payload is not valid JSON"
    return
  end

  for _, dev in ipairs(info) do
    if type(dev) == "table" then
      local friendly_name = dev.friendly_name
      local ieee_address = dev.ieee_address
      local zigbee = ieee_address
      if friendly_name and ieee_address then
        local child = devices[ieee_address] or init_device (dev)
      
        local DEV = VIRTUAL[child]
        DEV.hadevice.LastUpdate = os.time()
--        DEV[zigbee][prefix] = message
        
        for n,v in pairs (dev) do
          if type (v) == "table" then
            for a,b in pairs (v) do
              if type (b) == "table" then
                for c,d in pairs(b) do
                  DEV[n][a .. '/' .. c] = d
                end
              else
                DEV[n][a] = b
              end
            end
          else
            DEV[zigbee][n] = v
          end
        end
      
      end
    end
  end
end

-----
--
-- MQTT callbacks
--

function _G.Zigbee2MQTT_Handler (topic, message, prefix)
  
  local zigbees = topic: match (table.concat {"^", prefix, "/(.+)"})
  if not zigbees then return end
  
  devNo = devNo       -- ensure that Bridge device exists
            or
              openLuup.find_device {device_type = "Zigbee2MQTTBridge"}
                or
                  create_Zigbee2MQTTBridge ()

  VIRTUAL[devNo][chdev.bridge.SID].Remote_ID = 716833     -- ensure ID for "Zigbee2MQTTBridge" exists

  local zigbee, mtype = zigbees: match "^(.-)/(.+)"
  
  if not (zigbee and VALID[mtype]) then 
    _log (table.concat ({"Topic ignored", topic}, " : "))
--    _log (table.concat ({"Topic ignored", topic, message}, " : "))
    return 
  end
  
  local info = json.decode (message) or {[mtype] = message}   -- treat invalid JSON as plain text
  
  local timenow = os.time()
  VIRTUAL[devNo].hadevice.LastUpdate = timenow
  
  if zigbee == "bridge" and mtype == "devices" then
    create_devices (info)
    return
  end
  
--  local child = devices[zigbee] or init_device (zigbee)

--  local DEV = VIRTUAL[child]
--  DEV.hadevice.LastUpdate = timenow
--  DEV[zigbee][prefix] = message
  
--  for n,v in pairs (info) do
--    if type (v) == "table" then
--      for a,b in pairs (v) do
--        if type (b) == "table" then
--          for c,d in pairs(b) do
--            DEV[n][a .. '/' .. c] = d
--          end
--        else
--          DEV[n][a] = b
--        end
--      end
--    else
--      DEV[zigbee][n] = v
--    end
--  end
end


-- startup
function start (config)
  config = config or {}
  
  -- standard prefixes are: {"cmnd", "stat", "tele"}
  local prefixes = config.Prefix or "zigbee2mqtt"       -- subscribed prefixes
  
  for prefix in prefixes: gmatch "[^%s,]+" do
    luup.register_handler ("Zigbee2MQTT_Handler", "mqtt:" .. prefix .. "/#", prefix)   -- * * * MQTT wildcard subscription * * *
  end

  -- standard topics are: {"SENSOR", "STATE", "RESULT", "LWT"}
  local topics = config.Topic or "devices"
  for topic in topics: gmatch "[^%s,]+" do
    VALID[topic] = 1
  end

end

-----
