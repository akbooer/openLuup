module(..., package.seeall)

ABOUT = {
  NAME          = "mqtt_shelly",
  VERSION       = "2024.04.08",
  DESCRIPTION   = "Shelly MQTT bridge",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2020-present AKBooer",
  DOCUMENTATION = "",
  DEBUG         = false,
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
-- 2024.02.25  support for Plus UNI pulse counter (input 2)
-- 2024.03.15  change handling of Plus device initialisation and subscriptions
-- 2024.03.24  add 'firmware_update' device attribute
-- 2024.03.28  broaden Gen2+ handling of devices... not just "shellyplus..." (thanks @a-lurker)
-- 2024.04.04  override CJson or RapidJson... lost faith in them... producing functions in some decodes!
-- 2024.04.08  fully embrace Shelly component concept for Gen2+ 


local json      = require "openLuup.json"
local luup      = require "openLuup.luup"
local chdev     = require "openLuup.chdev"            -- to create new bridge devices
local tables    = require "openLuup.servertables"     -- for standard DEV and SID definitions

json = json.Lua  -- 2024.04.04  override CJson or RapidJson

local pretty = luup.openLuup.pretty

local DEV = tables.DEV {
    shelly      = "D_GenericShellyDevice.xml",
  }

local SID = tables.SID {
    sBridge   = "urn:akbooer-com:serviceId:ShellyBridge1",
    shellies  = "shellies",
  }

local openLuup = luup.openLuup
local API = require "openLuup.api"

-- the empty list - cannot be written to, but saves creating lots of empty lists.

local READONLY do
  local readonly_meta = {__newindex = function() error ("read-only empty list - detected attempted write!", 2) end}
  READONLY = function(x) return setmetatable (x, readonly_meta) end
end

local empty = READONLY {}

local function _debug(...) if ABOUT.DEBUG then print("Shelly", ...) end; end

--------------------------------------------------
--
-- utilities
--

-- convert openLuup device number into shelly id and unit number
-- expecting "shellyxxxx" or "shellyxxxx/n"  
local function shelly_unit(dno)
  local id = luup.attr_get ("altid", dno)
  local shelly, unit = id: match "^([^/]+)/?(%d*)$"    -- expecting "shellyxxxx" or "shellyxxxx/n"
  unit = tonumber(unit) or 0
  return shelly, unit
end

-- cache device number indexed by altid
local lookup_meta = {}
function lookup_meta:__index(altid)
  local dno = openLuup.find_device {altid = altid}
  self[altid] = dno
  return dno
end

local dev_lookup = setmetatable({}, lookup_meta)

-- use base altid (ie. without /0, etc.) to determine whether or not a Gen2+ device
local function is_gen1(shelly)
  local dno = dev_lookup[shelly]
  local model = API[dno].attr.model
  return model: match "^%u"       -- Gen2+ model is uooercase
end

-- generate a unique id for rpc messages
local unique_id do
  local id = 0
  unique_id = function()
    id = id + 1
    return id
  end
end

-- return Shelly device type relay/light/color given device number
local function shelly_type(dno)
  local dfile = luup.attr_get ("device_file", dno)
  return  (dfile == DEV.dimmer and "light") 
      or  (dfile == DEV.rgb and "color")
      or "relay"
end
  
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
    local dtype = shelly_type(dno)
    local shelly, unit = shelly_unit(dno)
    local on_off
    if shelly then
      local val = tostring(tonumber (args.newTargetValue) or 0)
      API[dno].switch.Target = val
      if is_gen1(shelly) then
        on_off = val == '1' and "on" or "off"
        shelly = table.concat {"shellies/", shelly, '/', dtype, '/', unit, "/command"}
      else
        shelly = shelly .. "/rpc"
        local state = (val == '1')      -- boolean parameter
        on_off = json.encode {
            id = unique_id(),
            src = "openLuup-response",
            method = "Switch.Set",
            params = {id = unit, on = state}}
      end
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
    --[[
          args = {
          DeviceNum = "30009",
          action = "SetLoadLevelTarget",
          newLoadlevelTarget = "100",
          serviceId = "urn:upnp-org:serviceId:Dimming1"}
    --]]
    local dtype = shelly_type(dno)
    local shelly, unit = shelly_unit(dno)
    if shelly then
      local val_n = tonumber (args.newLoadlevelTarget) or 0
      local val = tostring(val_n)
      API[dno].dimming.LoadLevelTarget = val
      local command
      if is_gen1(shelly) then
        -- shellies/shellydimmer-<deviceid>/light/0/set 	
        -- accepts a JSON payload in the format 
        -- {"brightness": 100, "turn": "on", "transition": 500}
--        shelly = table.concat {"shellies/", shelly, '/light/', unit, "/set"}
        shelly = table.concat {"shellies/", shelly, '/', dtype, '/', unit, "/set"}
--        command = json.encode {brightness = val_n}    -- possibly this for monochrome dimmer ???
        command = json.encode {gain = val_n}
      else
        -- TODO: Gen2+ dimming here
      end
      openLuup.mqtt.publish (shelly, command)
    else 
      return false
    end
  end
  
  -- {newColorRGBTarget = "144,198,95"}  all 0..255
  local function SetColorRGB (dno, args)
    local shelly, unit = shelly_unit(dno)
    if shelly then
      -- shellies/shellyrgbw2-<deviceid>/color/0/set
      shelly = table.concat {"shellies/", shelly, '/color/', unit, "/set"}
      local r,g,b,w = (args.newColorRGBTarget or ''):match "(%d+),(%d+),(%d+),?(%d*)"
      local command = json.encode {red = r, green = g, blue = b, white = w}
      openLuup.mqtt.publish (shelly,command)
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
        [SID.color]     = {SetColorRGB = SetColorRGB},
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


local function _log (msg)
  luup.log (msg, "luup.shelly")
end

local function noop() end

local function format_mac_address(mac)
  return (mac or ''):gsub("..", "%1:"):sub(1,-2)
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

-- generic actions for all Gen 1 devices
local function generic (dno, var, value) 
  -- battery level
  if type(var) ~= "string" then return end
  if var == "sensor/battery" then
    API[dno].hadevice.BatteryLevel = value
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
  --  _log ("ix3 - update: " .. var)
end

local function sw2_5(dno, var, value) 
--  _log ("sw2.5 - update: " .. var)
  local action, child, attr = var: match "^(%a+)/(%d)/?(.*)"
  if child then
    local altid = luup.attr_get ("altid", dno)
    local cdno = dev_lookup[table.concat{altid, '/', child}]
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
  local cdno = dev_lookup[table.concat{altid, '/', child}]
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
    local cdno = dev_lookup[table.concat{altid, '/', child}]
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

--
-- RGBW2
--
local function rgbw2_color (dno, var, value)
  local D = API[dno]
  if var == "color/0/status" then
    local status = json.decode(value)
    if type(status) == "table" then
      local r,g,b,w = status.red, status.green, status.blue, status.white
      local wrgb = "0=%d,1=%d,2=%d,3=%d"
      if r and g and b and w then
        D.color.CurrentColor = wrgb: format(w,r,g,b)
      end
    end
    if status.ison ~= nil then
      D.switch.Status = status.ison and '1' or '0'
    end
    if status.gain ~= nil then
      D.dimming.LoadLevelStatus = status.gain
    end
  elseif var == "color/0/power" then
    D.energy.Watts = value
  elseif var == "" then

  end
end

local function rgbw2_white (dno, var, value)
  local _ = dno, var, value
end

local function rgbw2 (dno, var, value)
  if var:match "^color" then
    rgbw2_color(dno, var, value)
  else
    rgbw2_white(dno, var, value)
  end
end


----------------------
--
-- Plus model updaters (use RPC syntax)
--

----------------------
--
-- Gen2+ components
--

local plus_component = {}

function plus_component.switch(dno, info)
  local D = API[dno]
  local shelly, unit = shelly_unit(dno)
  local sid = shelly: match "%w+"
  local name = table.concat {"switch/", unit, "/output"}
  local value = D[sid][name] == "true" and '1' or '0'
--  TODO: D.switch.Status = value  -- ...or something like that
end

function plus_component.temperature(D, info)
--  print("TEMPERATURE", pretty(info))
  local value = info.tC
  if value then 
    D.temp.CurrentTemperature = value
    local cdno = dev_lookup[D.attr.altid .. "/0"]
    if cdno then
      local S = API[cdno].temp
      S.CurrentTemperature = value
      S.MinTemp = value              -- implemented through Historian database aggregation
      S.MaxTemp = value              -- ditto
    end
  end
end

function plus_component.humidity(D, info)
--  print("HUMIDITY", pretty(info))
  local value = info.rh
  if value then 
    value = math.floor(value + 0.5)
    D.humid.CurrentLevel = value
    local cdno = dev_lookup[D.attr.altid .. "/1"]
    if cdno then
      local S = API[cdno].humid
      S.CurrentLevel = value
    end
  end
end

function plus_component.device(D, info)
--  print("DEVICE", pretty(info))
  local fw = info.fw_id 
  if fw then
    D.attr.firmware = fw
  end
  -- also mac and name are here
end

function plus_component.sys(D, info)
--  print("SYS", pretty(info))
  local mac = info.mac
  if mac then
    D.attr.mac = format_mac_address(mac)
  end
  
  local update = ''
  local available = info.available_updates
  if type(available) == "table" then
    local updates = {}
    for up in pairs(available) do 
      updates[#updates+1] = up
    end
    update = table.concat(updates, ' ')
  end
  D.attr.firmware_update = update
end

function plus_component.wifi(D, info)
  local ip = info.sta_ip 
  if ip then
    D.attr.ip = ip
  end
end

function plus_component.ethernet(D, info)
  local ip = info.sta_ip 
  if ip then
    D.attr.ip = ip
  end
end

-- inputs may be placed in child devices or the main parent, depending on configuration
-- single true/false switch states currently ignored
-- events are handled as scene inputs
function plus_component.input(D, info, cno)
--  print("INPUT", pretty(info))
  local altid = D.attr.altid
  local cdno = dev_lookup[altid .. "/" .. cno]      -- child device, or...
                or dev_lookup[altid]                -- ..parent
  if not cdno then return end
  
  local CD = API[cdno]
  local last_update = D.hadevice.LastUpdate
  CD.hadevice.LastUpdate = last_update
  
  -- on/off switch
--  local state = info.state        --TODO: generic update has already set variable... no equivalent MiOS variable?
  
  -- counter (assume it's an energy meter)
  local counts = info.counts
  if counts then
    local S = CD.energy
    local total = counts.total or 0
    local pulse = S.Pulse or 1000             -- default to 1000 pulses per kWh unit
    S.Count = total
    S.Pulse = pulse
    S.KWH = total / pulse
  end
end

function plus_component.voltmeter(D, info)
--  print("VOLTMETER", pretty(info))
  
end

function plus_component.switch(D, info, cno)
--  print("SWITCH", pretty(info))
  local id = tonumber(info.id)
  local output = info.output 
--  if id ~= cno then
--    _log "ERROR component id does not match component number"
--  end
  if id and output ~= nil then     -- state could be true or false
    local cdno = dev_lookup[D.attr.altid .. '/' .. id]
    if cdno then
      API[cdno].switch.Status = output and '1' or '0'
    else 
      _log "ERROR: no child device for switch component"
    end
  end
end

function plus_component.light(D, info, cno)
  print("LIGHT", pretty(info))
  
end

function plus_component.devicepower(D, info)
--  print("DEVICEPOWER", pretty(info))
  -- battery level
  local battery = info.battery
  local external = info.external
  if battery or external then
    local V, percent = '', ''
    if external and external.present then     -- as per @a-lurker's wishes
      V = 5
      percent = 100
    elseif battery then
      V = battery.V
      percent = battery.percent
    end
    D.hadevice.BatteryLevel = percent
    D.energy.Voltage = V
  end
end

-- not really a component, but an error return
function plus_component.error(D, event)
  _log ("ERROR: " .. (event.message or '?'))
end

-- not really a component, convert a button event into a scene activation

local watched_event = {single_push = true, long_push=true}    -- ignore button up/down

function plus_component.event(D, event)
  local j = json.encode(event): gsub('%c','')
  _log (j)
  local id = event.id
  local action = event.event
  if watched_event[action] then
    local S = D.scene
    S.sl_SceneActivated = table.concat {action, '_', id}
    S.LastSceneTime = os.time()
  end
end


function plus_component.XXX(_, info, _, component)
--  print (component:upper(), pretty(info))
end


-- return text version of value
local function convert(value)
  if (type(value) == "table") then
    local j,e = json.encode(value)
    value = j or e
    if e then _log("JSON convert ERROR: " .. e) end
  end
  return value
end 
  

----------------------
--
-- Plus model updaters 
--


-- generic parameter handling for all Gen Plus devices
local function generic_plus (dno, params) 
--  print("GENERIC PLUS", pretty(params))
-- rename and reformat values for device variables
  local D = API[dno]
  D.hadevice.LastUpdate = os.time()
  local sid = D.attributes.altid: match "%w+"
  local S = D[sid]
  
  -- component variables
  for a,b in pairs(params) do
    local component, cno = a: match "(%w+):?(%d*)"      -- treat numbered names as components to save
    cno = tonumber(cno) 
    -- component updates
    local dispatch = plus_component[component] or plus_component.XXX
    dispatch(D, b, cno, component)
    -- top-level device variables
    if cno and type(b) == "table" then
      local cname = component .. '/' .. cno
      for name, value in pairs(b) do
        local compound_name = cname .. '/' .. name
        S[compound_name] = convert(value)
      end
    else
      S[a] = convert(b)
    end
  end
  
  -- events
  for _, event in ipairs(params.events or empty) do
    local component, cno = event.component: match "(%w+):?(%d*)"      -- treat numbered names as components to save
    cno = tonumber(cno) 
    plus_component.event(D, event)
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
    ["SHRGBW2"]   = model_info (DEV.rgb,    rgbw2),
    
    ["shellyplusi4"]    = model_info (DEV.controller, noop),
    ["shellyplus2pm"]   = model_info (DEV.shelly, noop, {DEV.light, DEV.light}),
    ["shellyplusht"]    = model_info (DEV.shelly, noop, {DEV.temperature, DEV.humidity}),
    ["shellyplusuni"]   = model_info (DEV.shelly, noop, {DEV.light, DEV.light, DEV.power}),
  },{
    __index = function () return unknown_model end
  })

local function create_device(altid, model)
  local room = luup.rooms.create "Shellies"     -- create new device in Shellies room

  local offset = API[devNo][SID.sBridge].Offset
  if not offset then 
    offset = openLuup.bridge.nextIdBlock()  
    API[devNo][SID.sBridge].Offset = offset
  end
  local dno = openLuup.bridge.nextIdInBlock(offset, 0)  -- assign next device number in block
  
  local name = altid
  local upnp_file = models[model].upnp
  
  local dev = chdev.create {
    devNo = dno,
    internal_id = altid,
    description = name,
    upnp_file = upnp_file,
--    json_file = json_file,
    parent = devNo,
    room = room,
    manufacturer = "Allterco Robotics",
  }
  
  dev.attributes.model = model
  dev.handle_children = true                -- ensure that any child devices are handled
  luup.devices[dno] = dev                   -- add to Luup devices
  
  -- create extra child devices if required
  
  local children = models[model].children or empty
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

local function init_device (altid, model)
  local dno = shelly_devices[altid]
  if not dno then
    -- device not yet registered
    _log ("New Shelly announced: " .. altid)
    dno = dev_lookup[altid] 
                  or 
                    create_device (altid, model)
                    
    luup.devices[dno].handle_children = true      -- ensure that it handles child requests
    shelly_devices[altid] = dno                   -- save the device number, indexed by id
  end
  return dno
end

-- the bridge is a standard Luup plugin
local function init_shelly_bridge ()
  devNo = devNo       -- ensure that ShellyBridge device exists
            or
              openLuup.find_device {device_type = "ShellyBridge"}
                or
                  luup.create_device (
                    "ShellyBridge",         -- device_type
                    '',                     -- altid
                    "Shelly",               -- description
                    "D_ShellyBridge.xml",   -- upnp_file
                    "I_ShellyBridge.xml")   -- upnp_impl
  
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

-----

local rpc = "openLuup-ShellyBridge"             -- handler for Gen 2+ RPC responses
 
_G[rpc] = function(topic, message)  
  if not devNo then return end      -- wait until bridge exists
  _log (table.concat ({rpc, topic, message}, ' '))
  
  local info, err = json.decode (message)
  if err then 
    _log (err) 
    return
  end
  
--  local verify, err2 = json.encode {RPC_response = info}
--  _log (verify or err2) 
  
  local dno = shelly_devices[info.src]
--  _debug("RPC", json.encode(info))
  local result = info.result
  if dno and result then
    generic_plus(dno, result)
  end
end

luup.register_handler (rpc, "mqtt:" .. rpc .. "/rpc")  -- rpc response

-----

local gen2 = "Shelly_Gen_2_Plus"
--local valid = {NotifyFullStatus = true, NotifyStatus = true,  NotifyEvent = true}   -- valid methods

_G[gen2] = function(topic, message)
  
  local shelly = topic: match "^shelly[^/]+"  
  if not shelly then return end                 -- oops, not a Shelly Gen 2+ device
  init_shelly_bridge()                          -- make sure the bridge is up and running
  
  local dno = shelly_devices[shelly]            -- look up device number
  local model = shelly: match "%w+"             -- TODO: find ACTUAL model type?
  if not dno then                               -- create new device, if necessary
    dno = init_device(shelly, model)
  
    -- ask for config details
    local id = unique_id()                      -- create unique message id
    local msg = json.encode  {id = id, src = rpc, method = "Sys.GetConfig"}
    openLuup.mqtt.publish (shelly .. "/rpc", msg)
  end

  local info, err = json.decode (message)
  if err then 
    _log (err) 
    return
  end
  
  info = info.params or info.result or info       -- last option is a vanilla status message
  generic_plus (dno, info)                        -- perform generic update actions
  local updater = models[model].updater
  if updater then 
    updater(dno, info)               -- perform device specific update actions
  else
    _log("ERROR - no such model: " .. tostring(model))
  end
end

luup.register_handler (gen2, "mqtt:+/events/rpc", '')   -- Gen 2+ devices

-----

local gen1 = "Shelly_Gen_1"

_G[gen1] = function(topic, message)
    
  local shellies = topic: match "^shellies/(.+)"
  if not shellies then return end                 -- not a Shelly Gen 1 device
  
  init_shelly_bridge ()
  
  if shellies == "announce" then
    _log (message)
    local info, err = json.decode (message)
    if not info then _log ("Announce JSON error: " .. (err or '?')) return end
    local altid = info.id
    local dno = init_device (altid, info.model)
  -- update info, it may have changed
    local A = API[dno].attr
--    luup.ip_set (info.ip, dno)
--    luup.mac_set (format_mac_address(info.mac), dno)
--    luup.attr_set ("model", info.model, dno)
--    luup.attr_set ("firmware", info.fw_ver, dno)
--    luup.attr_set ("firmware_update", tostring(info.new_fw or ''), dno)
    A.ip  = info.ip
    A.mac = format_mac_address(info.mac)
    A.model = info.model
    A.firmware = info.fw_ver
    A.firmware_update = tostring(info.new_fw or '')
    
    luup.devices[dno]: delete_service(altid)      -- remove old-style service
    
  end
   
  local  shelly, var = shellies: match "^(.-)/(.+)"
  local child = shelly_devices[shelly]
  if not child then return end
  
  local timenow = os.time()
  local D = API[child]
  D.hadevice.LastUpdate = timenow
  
  local sid = shelly: match "%w+"
  local S = D[sid]
  local old = S[var]
  if message ~= old then
    S[var] = message                                  -- save the raw message
    generic (child, var, message)                     -- perform generic update actions
    local model = luup.attr_get ("model", child)
    models[model].updater (child, var, message)       -- perform device specific update actions
  end
end

luup.register_handler (gen1, "mqtt:shellies/#")            -- Gen 1 devices

-----

local test = "Shelly_Test"

_G[test] = function(topic, message)
    
--  local shellies = topic: match "^shell"
--  if not shellies then return end

  print(os.date "%X", test, topic, message)
end

--luup.register_handler (test, "mqtt:#") 

-----

local status = "Status"

_G[status] = function(topic, message)         -- reformat status messages
    
  local shelly, component = topic: match "^(shelly[^/]+)/status/(.+)"
  local dno = shelly_devices[shelly]
  if not shelly and component then return end

  local new_msg = ('{"%s": %s}'): format(component, message)
--  _G[gen2] (topic, new_msg)       -- pass it on to usual Gen2+ handler
  print(os.date "%X", status, component, topic, message)
  print('', "new_msg", pretty(json.decode(new_msg)))
end

luup.register_handler (status, "mqtt:+/status/#", '')   -- Gen 2+ devices

