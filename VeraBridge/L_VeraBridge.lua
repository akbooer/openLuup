_NAME = "VeraBridge"
_VERSION = "2015.11.01"
_DESCRIPTION = "VeraBridge plugin for openLuup!!"
_AUTHOR = "@akbooer"

-- bi-directional monitor/control link to remote Vera system
-- NB. this version ONLY works in openLuup
-- it plays with action calls and device creation in ways that you can't do in Vera,
-- in order to be able to implement ANY command action and 
-- also to logically group device numbers for remote machine device clones.

-- 2015-08-24   openLuup-specific code to action ANY serviceId/action request
-- 2015-11-01   change device numbering scheme

local devNo                      -- our device number

local json    = require "openLuup.json"
local url     = require "socket.url"

local ip                          -- remote machine ip address
local POLL_DELAY = 5              -- number of seconds between remote polls

local local_room_index           -- bi-directional index of our rooms
local remote_room_index          -- bi-directional of remote rooms

local SID = {
  gateway  = "urn:akbooer-com:serviceId:VeraBridge1",
  altui    = "urn:upnp-org:serviceId:altui1"          -- Variables = 'DisplayLine1' and 'DisplayLine2'
}

-- mapping between remote and local device IDs

local OFFSET                      -- offset to base of new device numbering scheme

local function local_by_remote_id (id) 
  return id + OFFSET
end

local function remote_by_local_id (id)
  return id - OFFSET
end

--create a variable list for each remote device from given states table
local function create_variables (states)
  local v = {}
  for i, s in ipairs (states) do
      v[i] = table.concat {s.service, ',', s.variable, '=', s.value}
  end
  return table.concat (v, '\n')
end
 
-- create bi-directional indices of rooms: room name <--> room number
local function index_rooms (rooms)
  local room_index = {}
  for number, name in pairs (rooms) do
    local roomNo = tonumber (number)      -- user_data may return string, not number
    room_index[roomNo] = name
    room_index[name] = roomNo
  end
  return room_index
end

-- create rooms (strangely, there's no Luup command to do this directly)
local function create_room(n) 
  luup.inet.wget ("127.0.0.1:3480/data_request?id=room&action=create&name=" .. n) 
end

-- create a child device for each remote one
-- we cheat standard luup here by manipulating the top-level attribute Device_Num_Next
-- in advance of calling chdev.append so that we can force a specific device number.
-- this devices table is from the "user_data" request
local function create_children (devices, new_room)
  local remote_attr = {}      -- important attibutes, indexed by remote dev.id
  
  local Device_Num_Next = luup.attr_get "Device_Num_Next"    -- save the real one
  local childDevices = luup.chdev.start(devNo)
  local embedded = false
  local invisible = false
  
  local n = 0
  for _, dev in ipairs (devices) do
    if not (dev.invisible == "1") then
      n = n + 1
      local remote_id = tonumber (dev.id) 
      local cloneId = local_by_remote_id(remote_id)
      remote_attr[remote_id] = {manufacturer = dev.manufacturer, model = dev.model}
      local variables = create_variables (dev.states)
      local impl_file = 'X'  -- override device file's implementation definition... musn't run here!
      luup.attr_set ("Device_Num_Next", cloneId)    -- set this, in case next call creates new device
      luup.chdev.append (devNo, childDevices, dev.id, dev.name, 
        dev.device_type, dev.device_file, impl_file, 
        variables, embedded, invisible, new_room)
    end
  end
  
  luup.attr_set ("Device_Num_Next", Device_Num_Next)  -- restore original BEFORE possible reload
  luup.chdev.sync(devNo, childDevices)
  
  luup.log ("local children created = " .. n)
  return n
end

local function GetUserData ()
  local Vera    -- (actually, 'remote' Vera!)
  local Ndev = 0
  local url = table.concat {"http://", ip, ":3480/data_request?id=user_data&output_format=json"}
  local status, j = luup.inet.wget (url)
  if status == 0 then Vera = json.decode (j) end
  if Vera then 
    luup.log "Vera info received!"
    if Vera.devices then
      local new_room_name = "MiOS-" .. (Vera.PK_AccessPoint: gsub ("%c",''))  -- stray control chars removed!!
      luup.log (new_room_name)
      create_room (new_room_name)
  
      remote_room_index = index_rooms (Vera.rooms or {})
      local_room_index  = index_rooms (luup.rooms or {})
      luup.log ("new room number: " .. (local_room_index[new_room_name] or '?'))
  
      Ndev = #Vera.devices
      luup.log ("number of remote devices = " .. Ndev)
      Ndev = create_children (Vera.devices or {}, local_room_index[new_room_name] or 0)
    end
  end
  return Ndev
end

-- MONITOR variables

-- updates existing device variables with new values
-- this devices table is from the "status" request
local function UpdateVariables(devices)
  for _, dev in pairs (devices) do
    local i = local_by_remote_id(dev.id)
    if i and luup.devices[i] and (type (dev.states) == "table") then
      for _, v in ipairs (dev.states) do
        local value = luup.variable_get (v.service, v.variable, i)
        if v.value ~= value then
          luup.variable_set (v.service, v.variable, v.value, i)
        end
      end
    end
  end
end

-- poll remote Vera for changes
local poll_count = 0
function VeraBridge_delay_callback (DataVersion)
  local s
  poll_count = (poll_count + 1) % 10            -- wrap every 10
  if poll_count == 0 then DataVersion = '' end  -- .. and go for the complete list (in case we missed any)
  local url = table.concat {"http://", ip, 
    ":3480/data_request?id=status2&output_format=json&DataVersion=", DataVersion or ''}
  local status, j = luup.inet.wget (url)
  if status == 0 then s = json.decode (j) end
  if s and s.devices then
    UpdateVariables (s.devices)
    DataVersion = s.DataVersion
  end 
  luup.call_delay ("VeraBridge_delay_callback", POLL_DELAY, DataVersion)
end

-- find other bridges in order to establish base device number for cloned devices
local function findOffset ()
  local offset
  local bridges = {}      -- devNos of ALL bridges
  for d, dev in pairs (luup.devices) do
    if dev.device_type == "VeraBridge" then
      bridges[#bridges + 1] = d
    end
  end
  table.sort (bridges)      -- sort into ascending order by deviceNo
  for d, n in ipairs (bridges) do
    if n == devNo then offset = d end
  end
  return offset * 10000   -- every remote machine starts in a new block of 10,000 devices
end

-- logged request

local function wget (request)
  luup.log (request)
  local status, result = luup.inet.wget (request)
  if status ~= 0 then
    luup.log ("failed requests status: " .. (result or '?'))
  end
end

--
-- GENERIC ACTION HANDLER
--
-- called with serviceId and name of undefined action
-- returns action tag object with possible run/job/incoming/timeout functions
--
local function generic_action (serviceId, name)
  local basic_request = table.concat {
      "http://", ip, ":3480/data_request?id=action",
      "&serviceId=", serviceId,
      "&action=", name,
    }
  local function job (lul_device, lul_settings)
    local devNo = remote_by_local_id (lul_device)
    if not devNo then return end        -- not a device we have cloned
    local request = {basic_request, "DeviceNum=" .. devNo }
    for a,b in pairs (lul_settings) do
      if a ~= "DeviceNum" then        -- thanks to @CudaNet for finding this bug!
        request[#request+1] = table.concat {a, '=', url.escape(b) or ''}  -- TODO: check with @CudaNet
      end
    end
    local url = table.concat (request, '&')
    wget (url)
    return 4,0
  end
  return {run = job}    -- TODO: job or run ?
end


-- plugin startup
function init (lul_device)
  luup.log ("VeraBridge")
  luup.log (_VERSION)
  luup.log (_NAME)
    
  devNo = lul_device
  OFFSET = findOffset ()
  luup.log ("device clone numbering starts at " .. OFFSET)

  local catch = luup.devices[devNo].action_callback    -- catch all undefined action calls
  if catch then catch (generic_action) end
  
  ip = luup.attr_get ("ip", devNo)
  luup.log (ip)
  
  local Ndev = GetUserData ()
  luup.variable_set (SID.gateway, "Devices", Ndev, devNo)
  luup.variable_set (SID.gateway, "Version", _VERSION, devNo)
  luup.variable_set (SID.altui, "DisplayLine1", Ndev.." devices", devNo)
  luup.variable_set (SID.altui, "DisplayLine2", ip, devNo)

  VeraBridge_delay_callback ()
  
  return true, "OK", _NAME
end

