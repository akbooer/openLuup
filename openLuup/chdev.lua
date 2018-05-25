local ABOUT = {
  NAME          = "openLuup.chdev",
  VERSION       = "2018.04.05",
  DESCRIPTION   = "device creation and luup.chdev submodule",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2018 AK Booer

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

-- This file not only contains the luup.chdev submodule, 
-- but also the luup-level facility for creating a device
-- after all, in the end, every device is a child device.

-- 2016.01.28  added 'disabled' attribute for devices - thanks @cybrmage
-- 2016.02.15  ensure that altid is a string (thanks cybrmage)
-- 2016.04.03  add UUID (for Sonos, and perhaps other plugins)
-- 2016.04.15  change the way device variables are handled in chdev.create - thanks @explorer!
-- 2016.04.18  add username and password to attributes (for cameras)
-- 2016.04.29  add device status
-- 2016.05.12  use luup.attr_get and set, rather than a dependence on openLuup.userdata
-- 2016.05.24  fix 'nil' plugin attribute
-- 2016.06.02  undo @explorer string mods (interim solution not now needed) and revert to standard Vera syntax
-- 2016.07.10  add extra 'no_reload' parameter to luup.chdev.sync (for ZWay plugin)
-- 2016.07.12  add 'reload' return parameter to luup.chdev.sync (ditto)
-- 2016.11.02  add device name to device_startup code

-- 2017.05.10  add category_num and subcategory_num to create() table parameters (thanks @dklinkman)

-- 2018.03.18  create default device variables if they have a defaultValue in the service definition
-- 2018.04.03  add jobs table to device metadata (for status reporting to AltUI)
-- 2018.04.05  move get/set status from devices to here (more a luup thing, than a device thing)


local logs      = require "openLuup.logs"

local devutil   = require "openLuup.devices"
local loader    = require "openLuup.loader"
local scheduler = require "openLuup.scheduler"

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

-- utilities

-- generate a (fairly) unique UDN
-- see: https://en.wikipedia.org/wiki/Universally_unique_identifier
--
-- A UUID is simply a 128-bit value. The meaning of each bit is defined by any of several variants.
-- For human-readable display, many systems use a canonical format using hexadecimal text with inserted hyphen characters. -- For example:    de305d54-75b4-431b-adb2-eb6b9e546014 
--

local UUID = (function ()
  local seed = luup and tonumber (luup.pk_accesspoint)
  if seed then math.randomseed (seed) end
  local fmt = "%02x"
  local uuid = {"uuid:"}
  local dash = {[4]='-', [6]='-', [8]='-', [10]='-'}
  for i = 1,16 do
    uuid[#uuid+1] = fmt:format(math.random(0,255))
    uuid[#uuid+1] = dash[i]
  end
  return table.concat (uuid)
end) ()

-- convert string statevariable definition into Lua table of device variables
local function varlist_to_table (statevariables) 
  -- syntax is: "serviceId,variable=value" separated by new lines
  local vars = {}
  for srv, var, val in statevariables: gmatch "%s*([^,]+),([^=]+)=(%C*)" do
    vars[#vars+1] = {service = srv, variable = var, value = val}
  end
  return vars
end

-- 
-- function: create (x)
-- parameters: see below
--
-- This creates the device with the parameters given, and returns the device object 
-- 2016.04.15 note statevariables are now a Lua array of {service="...", variable="...", value="..."}
--
local function create (x)
  -- {devNo, device_type, internal_id, description, upnp_file, upnp_impl, 
  -- ip, mac, hidden, invisible, parent, room, pluginnum, statevariables, ...}
  
  _debug (x.description)
  local dev = devutil.new (x.devNo)   -- create the proto-device
  local services = dev.services
  
  local ok, d, err = pcall (loader.assemble_device, x.devNo, x.device_type, x.upnp_file, x.upnp_impl, x.json_file)

  if not ok then
    local fmt = "ERROR [%d] %s / %s / %s : %s"
    local msg = fmt: format (x.devNo, x.upnp_file or x.device_type or '', 
                                        x.upnp_impl or '', x.json_file or '', d or '?')
    _log (msg, "luup.create_device")
    return
  end
  if err then _log (err) end
  local fmt = "[%d] %s / %s / %s"
  local msg = fmt: format (x.devNo, x.upnp_file or d.device_type or '', d.impl_file or '', d.json_file or '')
  _log (msg, "luup.create_device")
  
  if d.action_list then
    -- create and set service actions (from implementation file)
    -- each action_list element is a structure with (possibly) run/job/timeout/incoming functions
    -- it also has 'name' and 'serviceId' fields
    -- and may have 'returns' added below using information (from service file)
    for _, a in ipairs (d.action_list) do
      dev:action_set (a.serviceId, a.name, a)
      -- add any return parameters from service_data
      local sdata = loader.service_data[a.serviceId] or {returns = {}}
      a.returns = sdata.returns[a.name]
    end
  end
  
  -- 2018.03.18  create default device variables if they have a defaultValue in the service definition
  -- this is so that newly created devices have, at least, a minimal set of variables with defaults
  -- these may well get overwritten in the following block when statevariables are enumerated
  for _,srv in ipairs(d.service_list or {}) do
    local sdata = loader.service_data         -- delve into the loader's cache of service info
    local sid = srv.serviceId
    _debug (sid)
    for _, var in ipairs ((sdata[sid] or {}).variables or {}) do
      if var.defaultValue then
        _debug (var.name, var.defaultValue)
        dev:variable_set (sid, var.name, var.defaultValue)
      end
    end
  end

  -- go through the variables and set them
  -- 2016.04.15 note statevariables are now a Lua array of {service="...", variable="...", value="..."}
  if type(x.statevariables) == "table" then
    for _,v in ipairs(x.statevariables) do
      dev:variable_set (v.service, v.variable, v.value)
    end
  end

  -- schedule device startup code
  local device_name = x.description or d.friendly_name or ('_' .. (x.device_type:match "(%w+):%d+$" or'?'))
  if d.entry_point then 
    if tonumber (x.disabled) ~= 1 then
      scheduler.device_start (d.entry_point, x.devNo, device_name)         -- schedule startup in device context
    else
      local fmt = "[%d] is DISABLED"
      _log (fmt: format (x.devNo), "luup.create_device")
    end
  end
  
  -- set known attributes
  dev:attr_set {
    id              = x.devNo,                                          -- device id
    altid           = x.internal_id and tostring(x.internal_id) or '',  -- altid (called id in luup.devices, confusing, yes?)
    category_num    = x.category_num or d.category_num,     -- 2017.05.10
    device_type     = d.device_type or '',
    device_file     = x.upnp_file,
    device_json     = d.json_file,
    disabled        = tonumber (x.disabled) or 0,
    id_parent       = tonumber (x.parent) or 0,
    impl_file       = d.impl_file,
    invisible       = x.invisible and "1" or "0",   -- convert true/false to "1"/"0"
    local_udn       = UUID,
    manufacturer    = d.manufacturer or '',
    model           = d.modelName or '',
    name            = device_name, 
    plugin          = tostring(x.pluginnum or ''),
    password        = x.password,
    room            = tostring(tonumber (x.room or 0)),   -- why it's a string, I have no idea
    subcategory_num = tonumber (x.subcategory_num or d.subcategory_num) or 0,     -- 2017.05.10
    time_created    = os.time(), 
    username        = x.username,
    ip              = x.ip or '',
    mac             = x.mac or '',
  }
  
  local a = dev.attributes
-- TODO: consider protecting device attributes...
--  setmetatable (dev.attributes, {__newindex = 
--          function (_,x) error ("ERROR: attempt to create new device attribute "..x,2) end})
  
  local luup_device =     -- this is the information that appears in the luup.devices table
    {
      category_num        = a.category_num,
      description         = a.name,
      device_num_parent   = a.id_parent,
      device_type         = a.device_type, 
      embedded            = false,                  -- if embedded, it doesn't have its own room
      hidden              = x.hidden or false,        -- if hidden, it's not shown on the dashboard
      id                  = a.altid,
      invisible           = x.invisible or false,     -- if invisible, it's 'for internal use only'
      ip                  = a.ip,
      mac                 = a.mac,
      pass                = a.password or '',
      room_num            = tonumber (a.room),
      subcategory_num     = tonumber (a.subcategory_num),
      udn                 = a.local_udn,
      user                = a.username or '',    
    }
  
  -- fill out extra data in the proto-device
  dev.category_name       = d.category_name
  dev.handle_children     = d.handle_children == "1"
  dev.serviceList         = d.service_list
  dev.environment         = d.environment               -- the global environment (_G) for this device
  dev.io                  = {                           -- area for io related data (see luup.io)
                              incoming = d.incoming,
                              protocol = d.protocol,
                              -- other fields created on open include socket and intercept
                            }
  dev.jobs                = {}              -- 2018.04.03
  -- note that all the following methods should be called with device:function() syntax...
  dev.is_ready            = function () return true end          -- TODO: wait on startup sequence 
  dev.status              = -1                                   -- 2016.04.29  add device status
  dev.supports_service    = function (self, service) return not not services[service] end

  function dev:status_get ()            -- 2016.04.29, 2018.04.05
    return dev.status
  end
  
  function dev:status_set (value)     -- 2016.04.29, 2018.04.05
    if dev.status ~= value then
      devutil.new_userdata_dataversion ()
      dev.status = value
    end
  end


  return setmetatable (luup_device, {__index = dev} )   --TODO:    __metatable = "access denied"
end

-- this create device function has the same parameter list as the luup.create_device call
-- but it does NOT place the created device into the luup.devices table.
-- function: create_device
-- parameters: see below
-- returns: the device number AND the device object
--
local function create_device (
      device_type, internal_id, description, upnp_file, upnp_impl, 
      ip, mac, hidden, invisible, parent, room, pluginnum, statevariables,
      pnpid, nochildsync, aeskey, reload, nodupid  
  )
  local devNo = tonumber (luup.attr_get "Device_Num_Next")
  luup.attr_set ("Device_Num_Next", devNo + 1)
  local dev = create {
    devNo = devNo,                      -- (number)   (req)  *** NB: extra parameter cf. luup.create ***
    device_type = device_type,          -- (string)
    internal_id = internal_id,          -- (string)
    description = description,          -- (string)
    upnp_file = upnp_file,              -- (string)
    upnp_impl = upnp_impl,              -- (string)
    ip = ip,                            -- (string)
    mac = mac,                          -- (string)
    hidden = hidden,                    -- (boolean)
    invisible = invisible,              -- (boolean)
    parent = parent,                    -- (number)
    room = room,                        -- (number)
    pluginnum = pluginnum,              -- (number)
    statevariables = varlist_to_table (statevariables or ''),    -- (string)   "service,variable=value\nservice..."
    pnpid = pnpid,                      -- (number)   no idea (perhaps uuid??)
    nochildsync = nochildsync,          -- (string)   no idea
    aeskey = aeskey,                    -- (string)   no idea
    reload = reload,                    -- (boolean)
    nodupid = nodupid,                  -- (boolean)  no idea
  }
  return devNo, dev
end

-- Module: luup.chdev
--
-- Contains functions for a parent to synchronize its child devices. 
-- Whenever a device has multiple end-points, the devices are represented in a parent/child fashion where
-- the parent device is responsible for reporting what child devices it has and giving each one a unique id. 
-- The parent calls start, then enumerates each child device with append, and finally calls sync. 
-- You will need to pass the same value for device to append and sync that you passed to start.



-- function: start
-- parameters: device (string or number)
-- returns: ptr (binary object)
--
-- Tells Luup you will start enumerating the children of device. 
-- If device is a string it is interpreted as a udn [NOT IMPLEMENTED], 
-- if it's a number, as a device id. 
-- The return value is a binary object which you cannot do anything with in Lua, 
-- but you do pass it to the append and sync functions.
  
local function start (device)
  -- build a table of device's current children, indexed by (alt)id
  -- NB: this is essential to avoid changing luup.devices whilst it might be being traversed
  local old = {}
  for devNo, dev in pairs (luup.devices) do
    if dev.device_num_parent == device then
      old[dev.id] = devNo
    end
  end
  return {old = old, new = {}, reload = false}      -- lists of existing and new child devices
end

-- function: append
-- parameters: 
--    device, ptr, altid, description, device_type, device_filename, 
--    implementation_filename, parameters, embedded, invisible[, room]   
--    Note extra parameter "room" cf. luup 
-- returns: nothing
--
-- Adds one child to device.
-- Pass in the ptr which you received from the luup.chdev.start call. 
-- Give each child a unique id so you can keep track of which is which. 
-- You can optionally provide a description which the user sees in the user interface.
-- device_type is the UPnP device type, such as urn:schemas-upnp-org:device:BinaryLight:1.
-- NOTE: On UI7, the device_type MUST be either the empty string, 
-- or the same as the one in the device file, otherwise the Luup engine will restart continuously. 

local function append (device, ptr, altid, description, device_type, device_filename, 
  implementation_filename, parameters, embedded, invisible, room) 
  _log (("[%s] %s"):format (altid or '?', description or ''), "luup.chdev.append")
  if ptr.old[altid] then 
    ptr.old[altid] = nil        -- it existed already
  else
    ptr.reload = true           -- we will need a reload 
    room = tonumber(room) or 0
    if embedded then room = luup.devices[device].room_num end
    -- create_device (device_type, internal_id, description, upnp_file, upnp_impl, 
    --                  ip, mac, hidden, invisible, parent, room, pluginnum, statevariables...)
    local devNo, dev = create_device (device_type, altid, description, 
            device_filename, implementation_filename, 
            nil, nil, embedded, invisible, device, room, nil, parameters)
    ptr.new[devNo] = dev        -- save in the new list
  end
end
  
-- function: sync
-- parameters: device (string or number), ptr (binary object),
--    Note extra parameter 'no_reload' cf. luup 
-- returns: nothing  [CHANGED to return true if a reload WOULD have occurred and no_reload is set]
--
-- Pass in the ptr which you received from the start function. 
-- Tells the Luup engine you have finished enumerating the child devices. 
-- 
local function sync (device, ptr, no_reload)
  local name = luup.devices[device].description or '?'
  _log (("[%d] %s, syncing children"): format (device, name), "luup.chdev.sync")
  -- check if any existing ones not now required
  for _, devNo in pairs(ptr.old) do
    local fmt = "deleting [%d] %s"
    _log (fmt:format (devNo, luup.devices[devNo].description or '?'))
    luup.devices[devNo] = nil             -- no finesse required here, ...
    ptr.reload = true                     -- ...system should be reloaded
  end
  -- now it's safe to link new ones into luup.devices
  for devNo, dev in pairs (ptr.new) do
    luup.devices[devNo] = dev  
  end
  if ptr.reload and not no_reload then
    luup.reload() 
  end
  return ptr.reload
end


-- return the methods

return {
  ABOUT = ABOUT,
  
  create = create,
  create_device = create_device,
  
  -- this is the actual child device module for luup
  chdev = {
    start   = start,
    append  = append,
    sync    = sync,
  }
}

----
