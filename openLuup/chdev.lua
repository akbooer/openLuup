local _NAME = "openLuup.chdev"
local revisionDate = "2015.10.15"
local banner = "    version " .. revisionDate .. "  @akbooer"


-- Module: luup.chdev
--
-- Contains functions for a parent to synchronize its child devices. 
-- Whenever a device has multiple end-points, the devices are represented in a parent/child fashion where
-- the parent device is responsible for reporting what child devices it has and giving each one a unique id. 
-- The parent calls start, then enumerates each child device with append, and finally calls sync. 
-- You will need to pass the same value for device to append and sync that you passed to start.

local logs = require "openLuup.logs"

--  local log
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control



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
  return {}                 -- local database for new devices
  -- NB: this is essential to avoid changing luup.devices whilst it might be being traversed
end

-- function: append
-- parameters: 
--    device, ptr, id, description, device_type, device_filename, 
--    implementation_filename, parameters, embedded, invisible[, room]   
--    Note extra parameter "room" cf. luup 
-- returns: nothing
--
-- Adds one child to device.
-- Pass in the ptr which you received from the uup.chdev.start call. 
-- Give each child a unique id so you can keep track of which is which. 
-- You can optionally provide a description which the user sees in the user interface.
-- device_type is the UPnP device type, such as urn:schemas-upnp-org:device:BinaryLight:1.
-- NOTE: On UI7, the device_type MUST be either the empty string, 
-- or the same as the one in the device file, otherwise the Luup engine will restart continuously. 

local function append (device, ptr, id, descr, ...)
  _log (("[%s] %s"):format (id or '?', descr or ''), "luup.chdev.append")
  ptr[#ptr+1] = {
    id = id,                                      -- easy access for later
    parameters = {device, ptr, id, descr, ...}    -- save all the parameters for later
  }
end
  
-- function: sync
-- parameters: device (string or number), ptr (binary object),
-- returns: nothing
--
-- Pass in the ptr which you received from the start function. 
-- Tells the Luup engine you have finished enumerating the child devices. 

-- Note extra parameter "room" cf. luup 

-- new_child()
local function new_child (device, ptr, id, description, device_type, device_filename, 
  implementation_filename, parameters, embedded, invisible, room)    
  room = tonumber(room) or 0
  if embedded then room = luup.devices[device].room_num end
  -- create_device (device_type, internal_id, description, upnp_file, upnp_impl, 
  --                  ip, mac, hidden, invisible, parent, room, pluginnum, statevariables...)
  local childDevNo = luup.create_device (device_type, id, description, 
          device_filename, implementation_filename, 
          nil, nil, embedded, invisible, device, room, nil, parameters)
  return childDevNo
end

-- sync()
local function sync (device, ptr)
  local reload = false              -- may be needed later
  _log (table.concat{"syncing ", #ptr, " children"}, "luup.chdev.sync")
  -- build a table of device's current children, indexed by (alt)id
  local old = {}
  for devNo, dev in pairs (luup.devices) do
    if dev.device_num_parent == device then
      old[dev.id] = devNo
    end
  end
  -- compare sync list with existing children, creating any new ones
  for _,new in ipairs (ptr) do
    if not old[new.id] then
      new_child (unpack (new.parameters,1,12))      -- make call to luup.create_device
      reload = true
    end
    old[new.id] = nil   -- mark as done
  end
  -- check if any existing ones not now required
  for _, devNo in pairs(old) do
    local fmt = "deleting [%d] %s"
    _log (fmt:format (devNo, luup.devices[devNo].description or '?'))
    luup.devices[devNo] = nil     -- no finesse required here, ...
-- TODO: delete any grandchildren ??
    reload = true                 -- ...system will be reloaded
  end
  if reload then
    luup.reload() 
  end
end


-- return the methods

return {
  start   = start,
  append  = append,
  sync    = sync,
}

----
