local ABOUT = {
  NAME          = "openLuup.chdev",
  VERSION       = "2020.12.23",
  DESCRIPTION   = "device creation and luup.chdev submodule",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2020 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2020 AK Booer

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
-- 2018.05.14  ensure (sub)category numeric (thanks @rafale77)
-- 2018.05.14  remove pcall from create() to propagate errors
-- 2018.05.25  tidy attribute coercions
-- 2018.06.11  don't use impl_file if parent handles actions (thanks @rigpapa)
-- 2018.06.16  check for duplicate altids in chdev.append()  (thanks @rigpapa)
-- 2018.07.02  fix room number/string type problem in create()
-- 2018.07.22  create only non-blank default device variables (blank was breaking AlTUI install)

-- 2019.02.02  override device file manufacturer and modelName with existing attributes (thanks @rigpapa)
-- 2019.05.04  add status_message field to device and status_set/get()
-- 2019.06.02  chdev.create() sets device category from device type, if necessary (thanks @reneboer)
--             ALSO, allow missing serviceId in variable definitions to set attribute (thanks @rigpapa)
-- 2019.06.19  add dev:get_icon() to return dynamic icon name (for console)
-- 2019.08.29  check non-empty device name in create(), thanks @cokeman
-- 2019.09.14  set specified attributes to AFTER the default settings - thanks @reneboer
-- 2019.10.28  do not run startup code for devices whose parent handles them
-- 2019.12.19  fix get_icons() - state_icon entries may incllude list of the icon names, so ignore non-table items

-- 2020.02.05  add dev:rename()
-- 2020.02.09  add newindex() to keep integrity of visible luup.device[] structure
-- 2020.02.12  add Bridge utilities (mapped to luup.openLuup.bridge.*)
-- 2020.03.07  add ZWay bridge to device startup priorities
-- 2020.12.19  allow luup.chdev.append() to change device name (thanks @rigpapa)
-- 2020.12.23  add Ezlo bridge to scheduler startup priorities (thanks @rigpapa)


local logs      = require "openLuup.logs"

local devutil   = require "openLuup.devices"
local loader    = require "openLuup.loader"
local scheduler = require "openLuup.scheduler"
local json      = require "openLuup.json"               -- for device.__tostring()

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

local BLOCKSIZE = 10000     -- size of device number blocks allocate to openLuup Bridge devices

-- utilities

local function newindex (self, ...) rawset (getmetatable(self).__index, ...) end      -- put non-visible variables into meta

local function jsonify (self) return (json.encode (self: state_table())) or '?' end   -- return JSON device representation

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
  for srv, var, val in statevariables: gmatch "%s*([^,]*),([^=]+)=(%C*)" do   -- 2019.06.02 allow missing serviceId
    if srv == '' then srv = nil end
    vars[#vars+1] = {service = srv, variable = var, value = val}
  end
  return vars
end

local function non_empty(x) return x and x:match "%S" and x end
  
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
  
  local parent = tonumber (x.parent) or 0
  local parent_device = luup.devices[parent] or {}
  local do_not_implement = parent_device.handle_children     -- ignore device implementation file if parent handles it

  local d, err = loader.assemble_device (x.devNo, x.device_type, x.upnp_file, x.upnp_impl, x.json_file,
                                              do_not_implement)

  d = d or {}
  local fmt = "[%d] %s / %s / %s   (%s)"
  local msg = fmt: format (x.devNo, x.upnp_file or '', d.impl_file or '', d.json_file or '', d.device_type or '')
  _log (msg, "luup.create_device")
  if err then _log (err) end
  
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
      if var.defaultValue and var.defaultValue ~= '' then   -- 2018.07.22 only non-blank defaults
        _debug (var.name, var.defaultValue)
        dev:variable_set (sid, var.name, var.defaultValue)
      end
    end
  end
  
  local device_type = d.device_type or ''
  local job_priority = {
    openLuup = 1, 
    ["urn:schemas-upnp-org:device:altui:1"] = 3, 
    ["urn:schemas-rboer-com:device:EzloBridge:1"] = 5,
    VeraBridge = 5,
    ZWay = 5}         -- 2020.03.07
  local cat_num = tonumber (x.category_num or d.category_num or loader.cat_by_dev[device_type])   -- 2019.06.02
  local priority = job_priority[device_type]
  
  -- schedule device startup code
  local device_name = non_empty (x.description) 
                        or d.friendly_name or "Device_" .. x.devNo  -- 2019.08.29 check non-empty name
  if d.entry_point then 
    if tonumber (x.disabled) ~= 1 then
      if not parent_device.handle_children then                                 -- 2019.10.28  
        scheduler.device_start (d.entry_point, x.devNo, device_name, priority)  -- schedule startup in device context
      end
    else
      local fmt = "[%d] is DISABLED"
      _log (fmt: format (x.devNo), "luup.create_device")
    end
  end
  
  -- set known attributes
  dev:attr_set {
    id              = x.devNo,                                          -- device id
    altid           = x.internal_id and tostring(x.internal_id) or '',  -- altid (called id in luup.devices, confusing, yes?)
    category_num    = cat_num or 0,                      -- 2017.05.10, 2018.05.12, 2019.06.02
    device_type     = device_type,
    device_file     = x.upnp_file,
    device_json     = d.json_file,
    disabled        = tonumber (x.disabled) or 0,
    id_parent       = parent,
    impl_file       = d.impl_file,
    invisible       = x.invisible and "1" or "0",   -- convert true/false to "1"/"0"
    local_udn       = UUID,
    manufacturer    = x.manufacturer or d.manufacturer or '',
    model           = x.model or d.modelName or '',
    name            = device_name, 
    plugin          = tostring(x.pluginnum or ''),
    password        = x.password,
    room            = tostring(tonumber (x.room) or 0),   -- why it's a string, I have no idea 2018.07.02
    subcategory_num = tonumber (x.subcategory_num or d.subcategory_num) or 0,     -- 2017.05.10
    time_created    = os.time(), 
    username        = x.username,
    ip              = x.ip or '',
    mac             = x.mac or '',
  }

  -- 2019.09.14 move to here from earlier in the code to avoid overwriting by defaults - thanks @reneboer
  -- go through the variables and set them
  -- 2016.04.15 note statevariables are now a Lua array of {service="...", variable="...", value="..."}
  if type(x.statevariables) == "table" then
    for _,v in ipairs(x.statevariables) do
      if v.service then                                   -- 2019.06.02
        dev:variable_set (v.service, v.variable, v.value)
      else
        dev:attr_set (v.variable, v.value)
      end
    end
  end

  local a = dev.attributes
-- TODO: consider protecting device attributes...
--  setmetatable (dev.attributes, {__newindex = 
--          function (_,x) error ("ERROR: attempt to create new device attribute "..x,2) end})
 
-- Note: that all the entries in dev.attributes already have the right type, so no need for coercions...
  local luup_device =     -- this is the information that appears in the luup.devices table
    {
      category_num        = a.category_num,
      description         = a.name or '???',
      device_num_parent   = a.id_parent,
      device_type         = a.device_type, 
      embedded            = false,                  -- if embedded, it doesn't have its own room
      hidden              = x.hidden or false,        -- if hidden, it's not shown on the dashboard
      id                  = a.altid,
      invisible           = x.invisible or false,     -- if invisible, it's 'for internal use only'
      ip                  = a.ip,
      mac                 = a.mac,
      pass                = a.password or '',
      room_num            = tonumber(a.room),         -- 2018.07.02
      subcategory_num     = a.subcategory_num,
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
  dev.status_message      = ''                                   -- 2019.05.04
  dev.supports_service    = function (self, service) return not not services[service] end

  function dev:status_get ()            -- 2016.04.29, 2018.04.05
    return dev.status, dev.status_message
  end
  
  function dev:status_set (value, message)     -- 2016.04.29, 2018.04.05, 2019.05.04
    message = message or ''
    if dev.status ~= value or dev.status_message ~= message then
      dev.status = value
      dev.status_message = message
--      devutil.new_userdata_dataversion ()
      dev: touch()                    -- 2019.05.04
    end
  end

  -- return the names asnd values of the variables with shortCode aliases (as appear in the status request)
  function dev:get_shortcodes ()      -- 2019.05.10
    local info = {}
    local sd = loader.service_data
    for svc, s in pairs (self.services) do
      local known_service = sd[svc]
      if known_service then
        for var, v in pairs (s.variables) do
          local short = known_service.short_codes[var]
          if short then info[short] = v.value end
        end
      end
    end
    return info 
  end
  
  -- this is the basic user_data for the device variables
  -- the id=user_data and id=status requests embellish this in different ways
  -- used by userdata.devices_table() and requests.status_devices_table()
  function dev:state_table ()      -- 2019.05.12
    local states = {}
    for i,item in ipairs(self.variables) do
      states[i] = {
        id = item.id, 
        service = item.srv,
        variable = item.name,
        value = item.value or '',
      }
    end
    return states
  end

  -- get list of child device numbers (not grand-children, etc...)
  function dev:get_children ()
    local children = {}
    local id = self.attributes.id
    for n,d in pairs (luup.devices) do
      if d.device_num_parent == id then
        children[#children + 1] = n
      end
    end
    return children
  end
  
  -----------------------------
  -- dynamic icons
  
  local op = {}
  op.noop  = function () end
  op["=="] = function (a,b) return a == b end
  op["!="] = function (a,b) return a ~= b end
  op["<="] = function (a,b) return a <= b end
  op[">="] = function (a,b) return a >= b end
  op["<"]  = function (a,b) return a <  b end
  op[">"]  = function (a,b) return a >  b end

  local function is_true (d, c)
    local srv = d.services[c.service]
    if not srv then return end
    local var = srv.variables[c.variable]
    if not var then return end
    local val = type(c.value) == "number" and tonumber (var.value) or var.value
    local fct = op[c.operator] or function() end
    return fct (val, c.value)
  end

  function dev: get_icon ()
    local icon = "zwave_default.png"
    local json_file = self.attributes.device_json
    local sd = loader.static_data[json_file]
    if not sd then return icon end        -- can't find static data

    icon = sd.default_icon or icon
    local si = sd.state_icons
    if not si then return icon end        -- use default device icon

    local cn, scn = self.category_num, self.subcategory_num
    for _, set in ipairs (si) do
      -- 2019.12.19 note that initial entries may include list of the icon names, so ignore non-table items
      -- each set is {conditions = {}...}, img = '...'} and all need to be met
      if type(set) == "table" then
        local met = true
        for _, c in ipairs (set.conditions or {}) do
          local cat = (not c.category_num or c.category_num == cn) and
                      (not c.subcategory_num or c.subcategory_num == scn) 
          met = met and cat and is_true (self, c)
        end
        if met then
          icon = set.img or icon
          break
        end
      end
    end
    return icon
  end

  -- rename and/or change room , 2020.02.05
  -- (can be room number or existing room name, see: http://wiki.micasaverde.com/index.php/Luup_Requests#device)
  function dev: rename (name, new_room)
    if name then
      self.description = name       -- change in both places!!
      self.attributes.name = name
    end
    if new_room then
      local idx = {}
      for i,room in pairs(luup.rooms) do idx[room] = i end        -- build index of room names
      self.room_num = tonumber(new_room) or idx[new_room] or 0    -- room number also appears in two places
      self.attributes.room = tostring(self.room_num)
    end
--    devutil.new_userdata_dataversion ()
    dev: touch()                    -- 2020.02.23
  end

  -- set parent of device
  function dev:set_parent (newParent)
    self.device_num_parent = newParent        -- parent resides in two places under different names !!
    self.attributes.id_parent = newParent
  end
  
  
  return setmetatable (luup_device, {
      __index = dev, 
      __newindex = newindex,          -- 2020.02.09
      __tostring = jsonify})
  
end

-- generate the next device number
local function next_device_number ()
  local devNo = tonumber (luup.attr_get "Device_Num_Next")
  if devNo < BLOCKSIZE then                             -- 2020.02.15
    luup.attr_set ("Device_Num_Next", devNo + 1)        -- increment as usual
  else
    devNo = #luup.devices + 1   -- else start reusing (very) old free device numbers
  end
  return devNo
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
  local devNo = next_device_number ()
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

----------------------------------------
--
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
  -- 2018.06.16  add list of seen altids
  return {old = old, new = {}, seen = {}, reload = false}      -- lists of existing and new child devices
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
  
  -- 2018.06.16  check for duplicate altids (thanks @rigpapa)
  assert (not ptr.seen[altid], "duplicate altid in chdev.append()")  -- no return status, so raise error
  ptr.seen[altid] = true
 
  local dno = ptr.old[altid]
  if dno then 
    ptr.old[altid] = nil        -- it existed already
    if non_empty(description) then      -- 2020.12.19
      local dev = luup.devices[dno]
      dev.description = description
      dev.attributes.name = description
    end
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


----------------------------------------
--
-- 2020.02.12
-- Bridge/Child utilities (mapped to luup.openLuup.bridge.*)
--

local SID = "urn:akbooer-com:serviceId:openLuupBridge1"

local bridge_utilities = {BLOCKSIZE = BLOCKSIZE, SID = SID}

-- establish next base device number for child devices
function bridge_utilities.nextIdBlock ()
  -- 2020.02.12 simply calculate the next higher free block
  local maxId = 0
  for i in pairs (luup.devices) do maxId = (i > maxId) and i or maxId end     -- max device id
  local maxBlock = math.floor (maxId / BLOCKSIZE)                             -- max block
  return (maxBlock + 1) * BLOCKSIZE                                           -- new block offset
end

-- get next available device number in block
function bridge_utilities.nextIdInBlock (offset, baseline)
  local bridgeNo = math.floor (offset / BLOCKSIZE)
  local maxId = offset + (baseline or 1000)  -- Ids below baseline reserved for whatever you like
  for n in pairs(luup.devices) do
    if math.floor (n / BLOCKSIZE) == bridgeNo then
      maxId = math.max (maxId, n)
    end
  end
  return maxId + 1
end

-- get vital information from installed openLuup Bridge devices
-- indexed by (integer) bridge#, and  .by_pk[], .by_name[]
-- 2020.02.12 recognise bridge by having high-numbered children, not by device type
function bridge_utilities.get_info ()
  local bridge = {[0] = {nodeName = "openLuup", PK = '0', offset = 0, devNo = 2}}   -- preload openLuup info
  -- which devices are bridges?
  for i,dev in pairs(luup.devices) do
    local p = dev.device_num_parent
    if  i > BLOCKSIZE       -- high-numbered device
    and p < BLOCKSIZE       -- low-numbered parent (ie. local device) 
    and p > 1               -- ignore the mapped Zwave controller #1
    and not bridge[p] then  -- not already recorded
      
      local bridgeNo = math.floor (i / BLOCKSIZE)
      local d = luup.devices[p]
      local name = d.description: gsub ("%W",'')      -- remove non-alphanumerics
      local PK = luup.variable_get (bridge_utilities.SID, "Remote_ID", p) -- generic Remote ID
      local offset = bridgeNo * BLOCKSIZE
      if offset and PK then
        local index = math.floor (offset / BLOCKSIZE)   -- should be a round number anyway
        bridge[index] = {nodeName = name, PK = PK, offset = offset, devNo = p}
      end
    end
  end
  
  local by_pk, by_name, by_devNo = {}, {}, {}  -- indexes
  for _,b in pairs (bridge) do    
    by_pk[b.PK] = b
    by_name[b.nodeName] = b
    by_devNo[b.devNo] = b
  end
  
  bridge.by_pk = by_pk          -- add indexes to bridge table
  bridge.by_name = by_name
  bridge.by_devNo = by_devNo
  return bridge
end

-- make a list of parent's existing children, counting grand-children, etc.!!!
function bridge_utilities.all_descendants (parent)
  
  local idx = {}
  for child, dev in pairs (luup.devices) do   -- index all devices by parent id
    local num = dev.device_num_parent
    local children = idx[num] or {}
    children[#children+1] = child
    idx[num] = children
  end

  local c = {}
  local function children_of (d)      -- recursively find all children
    for _, child in ipairs (idx[d] or {}) do
      c[child] = luup.devices[child]
      children_of (child)
    end
  end
  children_of (parent)
  return c
end


----------------------------------------


-- return the methods

return {
  ABOUT = ABOUT,
  
  create = create,
  create_device = create_device,
  
  -- openLuup Bridge utilities for child numbering
  bridge = bridge_utilities,
  
  -- this is the actual child device module for luup
  chdev = {
    start   = start,
    append  = append,
    sync    = sync,
  }
}

----
