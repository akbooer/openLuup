module(..., package.seeall)

ABOUT = {
  NAME          = "mqtt_tasmota",
  VERSION       = "2021.05.08",
  DESCRIPTION   = "Tasmota MQTT bridge",
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


-- 2021.04.02  new L_TasmotaBridge file
-- 2021.04.17  use openLuup device variable virtualizer, go one level deeper in table data (thanks @Buxton)
-- 2021.05.08  add /STATE and /RESULT topics (thanks @ArcherS)


local json      = require "openLuup.json"
local luup      = require "openLuup.luup"
local chdev     = require "openLuup.chdev"            -- to create new bridge devices
local tables    = require "openLuup.servertables"     -- for standard DEV and SID definitions

local DEV = tables.DEV {
    tasmota      = "D_GenericTasmotaDevice.xml",
  }

local SID = tables.SID {
    TasmotaBridge   = "urn:akbooer-com:serviceId:TasmotaBridge1",
  }

local openLuup = luup.openLuup
local VIRTUAL = openLuup

--------------------------------------------------
--
-- Tasmota MQTT Bridge - CONTROL
--
-- this part runs as a standard device
-- it is a control API only (ie. action requests)
--

function init ()   -- Tasmota Bridge device entry point
  luup.set_failure (0)
  return true, "OK", "TasmotaBridge"
end

--
-- end of Luup device file
--
--------------------------------------------------



--------------------------------------------------
--
-- Tasmota MQTT Bridge - MODEL and VIEW
--
-- this part runs as a system module and can create a bridge device
-- as well as subsequent child devices, and update their variables
--

local devices = {}      -- gets filled with device info on MQTT connection
local devNo             -- bridge device number (set on startup)


local function _log (msg)
  luup.log (msg, "luup.tasmota")
end

local function create_device(altid)
  _log ("New Tasmota detected: " .. altid)
  local room = luup.rooms.create "Tasmota"     -- create new device in Tasmota room

  local offset = VIRTUAL[devNo][SID.TasmotaBridge].Offset
  local dno = openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
  
  local name = altid
  
  
--  local upnp_file = models[info.model].upnp
  local upnp_file = DEV.tasmota
  
  local dev = chdev.create {
    devNo = dno,
    internal_id = altid,
    description = name,
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

local function init_device (altid)
  local dno = openLuup.find_device {altid = altid} 
                or 
                  create_device (altid)
                  
  luup.devices[dno].handle_children = true  -- ensure that it handles child requests
  devices[altid] = dno                      -- save the device number, indexed by id
  return dno
end

-- the bridge is a standard Luup plugin
local function create_TasmotaBridge()
  local internal_id, ip, mac, hidden, invisible, parent, room, pluginnum 

  local offset = openLuup.bridge.nextIdBlock()  
  local statevariables = table.concat {SID.TasmotaBridge, ",Offset=", offset} 
   
  return luup.create_device (
            "TasmotaBridge",         -- device_type
            internal_id,
            "Tasmota",               -- description
            "D_TasmotaBridge.xml",   -- upnp_file
            "I_TasmotaBridge.xml",   -- upnp_impl
            
            ip, mac, hidden, invisible, parent, room, pluginnum, 
            
            statevariables)  
end

-----
--
-- MQTT callbacks
--

function _G.Tasmota_MQTT_Handler (topic, message, prefix)
  
  local tasmotas = topic: match (table.concat {"^", prefix, "/(.+)"})
  if not tasmotas then return end
  
  devNo = devNo       -- ensure that TasmotaBridge device exists
            or
              openLuup.find_device {device_type = "TasmotaBridge"}
                or
                  create_TasmotaBridge ()

  -- device update: tele/tasmota_7FA953/SENSOR
  -- 2021.05.08  add /STATE and /RESULT
  local tasmota, mtype = tasmotas: match "^(.-)/(%u+)"
  local valid = {SENSOR = true, STATE = true, RESULT = true}
  if not (tasmota and valid[mtype]) then 
    _log (table.concat ({"Topic ignored", topic, message}, " : "))
    return 
  end
  
  local info, err = json.decode (message)
  if not info then 
    _log ("JSON error: " .. (err or '?')) 
    _log ("Received message ignored: " .. message)
    return 
  end
  
  local timenow = os.time()
  VIRTUAL[devNo].hadevice.LastUpdate = timenow
  
  local child = devices[tasmota] or init_device (tasmota)

  local DEV = VIRTUAL[child]
  DEV.hadevice.LastUpdate = timenow
  DEV[tasmota][prefix] = message
  
  for n,v in pairs (info) do
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
      DEV[tasmota][n] = v
    end
  end
end


-- startup on module load
-- standard prefixes are: {"cmnd", "stat", "tele"}
local prefixes = {"tele", "tasmota/tele"}             -- subscribed Tasmota prefixes

for _, prefix in ipairs (prefixes) do
  luup.register_handler ("Tasmota_MQTT_Handler", "mqtt:" .. prefix .. "/#", prefix)   -- * * * MQTT wildcard subscription * * *
end

-----
