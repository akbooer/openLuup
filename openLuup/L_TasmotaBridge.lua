module(..., package.seeall)

ABOUT = {
  NAME          = "mqtt_tasmota",
  VERSION       = "2021.04.14",
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


--------------------------------------------------
--
-- Tasmota MQTT Bridge - CONTROL
--
-- this part runs as a standard device
-- it is a control API only (ie. action requests)
--

local devNo             -- bridge device number (set on startup)

local function SetTarget (dno, args)
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

function init (lul_device)   -- Tasmota Bridge device entry point
  devNo = tonumber (lul_device)
	luup.devices[devNo].action_callback (generic_action)    -- catch all undefined action calls
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



----------------------


local function _log (msg)
  luup.log (msg, "luup.tasmota")
end

local function create_device(altid, info)
  _log ("New Tasmota detected: " .. altid)
  local room = luup.rooms.create "Tasmota"     -- create new device in Shellies room

  local offset = luup.variable_get (SID.TasmotaBridge, "Offset", devNo)
  local dno = luup.openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
  
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
  
  -- create extra child devices if required
  
--  local children = models[info.model].children or {}
--  local childID = "%s/%s"
--  for i, upnp_file2 in ipairs (children) do
--    local cdno = luup.openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
--    local cdev = chdev.create {
--      devNo = cdno,
--      internal_id = childID: format (altid, i-1),
--      description = childID: format (name, i-1),
--      upnp_file = upnp_file2,
--  --    json_file = json_file,
--      parent = dno,
--      room = room,
--    }
    
--    luup.devices[cdno] = cdev                   -- add to Luup devices
--  end
  
  return dno
end

local function init_device (altid, info)
  local dno = luup.openLuup.find_device {altid = altid} 
                or 
                  create_device (altid, info)
                  
  luup.devices[dno].handle_children = true  -- ensure that it handles child requests
  devices[altid] = dno                      -- save the device number, indexed by id
  return dno
end

-- the bridge is a standard Luup plugin
local function create_TasmotaBridge()
  local internal_id, ip, mac, hidden, invisible, parent, room, pluginnum 

  local offset = luup.openLuup.bridge.nextIdBlock()  
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

local prefixes = {cmnd = true, stat = true, tele = true}    -- default Tasmota prefixes

function _G.Tasmota_MQTT_Handler (topic, message)
  
  local prefix, tasmotas  = topic: match "^(%w+)/(.+)"
  if not prefixes[prefix] then return end
  
  devNo = devNo       -- ensure that TasmotaBridge device exists
            or
              luup.openLuup.find_device {device_type = "TasmotaBridge"}
                or
                  create_TasmotaBridge ()
  
  local info, err = json.decode (message)
  if not info then _log ("JSON error: " .. (err or '?')) return end
  
  local timenow = os.time()
  luup.devices[devNo]: variable_set (SID.hadevice, "LastUpdate", timenow, true)   -- not logged, but watchable

  -- device update: tele/tasmota_7FA953/SENSOR
  if prefix == "tele" then 
    local tasmota = tasmotas: match "^(.-)/SENSOR"

    local child = devices[tasmota] or init_device (tasmota, info)
  
    local dev = luup.devices[child]
    dev: variable_set (SID.hadevice, "LastUpdate", timenow, true)     -- not logged, but 'true' enables variable watch
    dev: variable_set (tasmota, "tele", message, true)  
    
    for n,v in pairs (info) do
      if type (v) == "table" then
        for a,b in pairs (v) do
          dev: variable_set (n, a, b, true)
        end
      else
        dev: variable_set (tasmota, n, v, true)
      end
    end
    
--    local model = luup.attr_get ("model", child)
--    models[model].updater (child, var, message)
  
  end
end

for prefix in pairs (prefixes) do
  luup.register_handler ("Tasmota_MQTT_Handler", "mqtt:" .. prefix .. "/#")   -- * * * * MQTT wildcard subscription * * * *
end

-----
