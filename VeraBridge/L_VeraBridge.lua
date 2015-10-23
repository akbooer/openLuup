-- VeraBridge
-- bi-directional monitor/control link to remote Vera system

local version =  "2015.10.08   @akbooer"


-- 2015-08-24   openLuup-specific code to action ANY serviceId/action request

local devNo                      -- our device number

local json = require "openLuup.json"

local ip                         -- remote machine ip address
local POLL_DELAY = 5              -- number of seconds between remote polls

local local_by_remote_id = {}    -- child device indices
local remote_by_local_id = {}

local local_room_index           -- bi-directional index of our rooms
local remote_room_index          -- bi-directional of remote rooms

local SID = {
  gateway  = "urn:akbooer-com:serviceId:VeraBridge1",
  altui    = "urn:upnp-org:serviceId:altui1"          -- Variables = 'DisplayLine1' and 'DisplayLine2'
}

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
-- this devices table is from the "user_data" request
local function create_children (devices, new_room)
  local family_tree = {}      -- list of remote dev.id_parent indexed by remote dev.id
  local remote_attr = {}      -- important attibutes, indexed by remote dev.id
  
  local childDevices = luup.chdev.start(devNo)
  local embedded = false
  local invisible = false
  
  for _, dev in ipairs (devices) do
    if not (dev.invisible == "1") then
      local remote_id = tonumber (dev.id) or 'missing'
      family_tree[remote_id] = tonumber (dev.id_parent)
      remote_attr[remote_id] = {manufacturer = dev.manufacturer, model = dev.model}
      local variables = create_variables (dev.states)
      local impl_file = 'X'  -- override device file's implementation definition... musn't run here!
      luup.chdev.append (devNo, childDevices, dev.id, dev.name, 
        dev.device_type, dev.device_file, impl_file, 
        variables, embedded, invisible, new_room)
    end
  end
  luup.chdev.sync(devNo, childDevices)
  -- now find their device numbers and index them...
  local n = 0
  for i, dev in pairs (luup.devices) do
    if dev.device_num_parent == devNo then       -- it's one of ours
      n = n + 1
      local id = tonumber (dev.id)              -- strangely inconsistent re. string vs. number
      local_by_remote_id[id] = i
      remote_by_local_id[i] = id
    end
  end
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
    local i = local_by_remote_id[dev.id]
    if i and (type (dev.states) == "table") then
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

-- logged request

local function wget (request)
  luup.log (request)
  local status, result = luup.inet.wget (request)
  if status ~= 0 then
    luup.log ("failed requests status: " .. 0)
  end
end

-- CONTROL actions

-- the implementation file calls p.<actionName> from a job

p = {}        -- GLOBAL (accessed by the <job> tags in the implementation file)

--    <action>
--  		<serviceId>urn:upnp-org:serviceId:SwitchPower1</serviceId>
--  		<name>SetTarget</name>
--  		<job>
--  			if (p ~= nil) then p.switchPower(lul_device, lul_settings.newTargetValue)  end
--  			return 4,0
--  		</job>
--    </action>

function p.switchPower(lul_device, newTargetValue)
  wget (table.concat {
      "http://", ip, ":3480/data_request?id=action", 
      "&action=SetTarget", 
      "&serviceId=urn:upnp-org:serviceId:SwitchPower1",
      "&DeviceNum=", remote_by_local_id[lul_device],
      "&newTargetValue=", newTargetValue})
end

--    <action>
--  		<serviceId>urn:upnp-org:serviceId:Dimming1</serviceId>
--  		<name>SetLoadLevelTarget</name>
--  		<job>
--  			if (p ~= nil) then p.setDimmerLevel(lul_device, lul_settings.newLoadlevelTarget) end
--			return 4,0
--		</job>
--    </action>

function p.setDimmerLevel(lul_device, newLoadlevelTarget)
  wget (table.concat {
      "http://", ip, ":3480/data_request?id=action", 
      "&action=SetLoadLevelTarget", 
      "&serviceId=urn:upnp-org:serviceId:Dimming1",
      "&DeviceNum=", remote_by_local_id[lul_device],
      "&newLoadlevelTarget=", newLoadlevelTarget})
end

--    <action>
--  		<serviceId>urn:micasaverde-com:serviceId:DoorLock1</serviceId>
--  		<name>SetTarget</name>
--  		<job>
--  			if (p ~= nil) then p.setLockStatus(lul_device, lul_settings.newTargetValue) end
--  			return 4,0
--  		</job>
--    </action> 

function p.setLockStatus(lul_device, newTargetValue)
  wget (table.concat {
      "http://", ip, ":3480/data_request?id=action", 
      "&action=SetTarget", 
      "&serviceId=urn:micasaverde-com:serviceId:DoorLock1",
      "&DeviceNum=", remote_by_local_id[lul_device],
      "&newTargetValue=", newTargetValue})
end

--    <action>
--      	<serviceId>urn:upnp-org:serviceId:TemperatureSetpoint1_Heat</serviceId>
--      	<name>SetCurrentSetpoint</name>
--      	<job>
--      		if (p ~= nil) then p.SetTheNewTemp(lul_device, lul_settings.NewCurrentSetpoint)  end
--  			return 4,0
--  		</job>
--    </action>

function p.SetTheNewTemp(lul_device, NewCurrentSetpoint)
  wget (table.concat {
      "http://", ip, ":3480/data_request?id=action", 
      "&action=SetCurrentSetpoint", 
      "&serviceId=urn:upnp-org:serviceId:TemperatureSetpoint1_Heat",
      "&DeviceNum=", remote_by_local_id[lul_device],
      "&NewCurrentSetpoint=", NewCurrentSetpoint})
end

--    <action>
--      	<serviceId>urn:upnp-org:serviceId:HVAC_UserOperatingMode1</serviceId>
--      	<name>SetModeTarget</name>
--      	<job>
--      		if (p ~= nil) then p.SetModeTarget(lul_device, lul_settings.NewModeTarget) end
--  			return 4,0
--  		</job>
--    </action>

function p.SetModeTarget(lul_device, NewModeTarget)
  wget (table.concat {
      "http://", ip, ":3480/data_request?id=action", 
      "&action=SetModeTarget", 
      "&serviceId=urn:upnp-org:serviceId:HVAC_UserOperatingMode1",
      "&DeviceNum=", remote_by_local_id[lul_device],
      "&NewModeTarget=", NewModeTarget})
end

--    <action>
--  		<serviceId>urn:upnp-org:serviceId:WindowCovering1</serviceId>
--  		<name>Up</name>
--  		<job>
--  			if (p ~= nil) then p.windowCovering(lul_device, "Up")  end
--  			return 4,0
--  		</job>
--    </action>
--    <action>
--  		<serviceId>urn:upnp-org:serviceId:WindowCovering1</serviceId>
--  		<name>Down</name>
--  		<job>
--  			if (p ~= nil) then p.windowCovering(lul_device, "Down") end
--  			return 4,0
--  		</job>
--    </action>
--    <action>
--  		<serviceId>urn:upnp-org:serviceId:WindowCovering1</serviceId>
--  		<name>Stop</name>
--  		<job>
--  			if (p ~= nil) then p.windowCovering(lul_device, "Stop") end
--  			return 4,0
--  		</job>
--    </action>

function p.windowCovering(lul_device, direction)
  wget (table.concat {
      "http://", ip, ":3480/data_request?id=action", 
      "&action=", direction,
      "&serviceId=urn:upnp-org:serviceId:WindowCovering1",
      "&DeviceNum=", remote_by_local_id[lul_device]})
end

--    <action>
--    	<serviceId>urn:micasaverde-com:serviceId:SecuritySensor1</serviceId>
--    	<name>SetArmed</name>
--    	<job>
--    		if (p ~= nil) then p.setArmed(lul_device, lul_settings.newArmedValue) end
--  			return 4,0
--  		</job>
--    </action>

function p.setArmed(lul_device, newArmedValue)
  wget (table.concat {
      "http://", ip, ":3480/data_request?id=action", 
      "&action=SetArmed", 
      "&serviceId=urn:micasaverde-com:serviceId:SecuritySensor1",
      "&DeviceNum=", remote_by_local_id[lul_device],
      "&newArmedValue=", newArmedValue})
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
    local devNo = remote_by_local_id[tonumber(lul_device) or ''] or ''
    local request = {basic_request, "DeviceNum=" .. devNo }
    for a,b in pairs (lul_settings) do
      request[#request+1] = table.concat {a, '=', b or ''}
    end
    local url = table.concat (request, '&')
    wget (url)
    return 4,0
  end
  return {job = job}
end


-- plugin startup
function init (lul_device)
  luup.log ("VeraBridge")
  luup.log (version)
  luup.log (_NAME)
  
  devNo = lul_device
  local catch = luup.devices[devNo].action_callback    -- only effective in openLuup
  if catch then catch (generic_action) end
  
  ip = luup.attr_get ("ip", devNo)
  luup.log (ip)
  
  local Ndev = GetUserData ()
  luup.variable_set (SID.gateway, "Devices", Ndev, devNo)
  luup.variable_set (SID.gateway, "Version", version, devNo)
  luup.variable_set (SID.altui, "DisplayLine1", Ndev.." devices", devNo)
  luup.variable_set (SID.altui, "DisplayLine2", ip, devNo)

  VeraBridge_delay_callback ()
  
  return true, "OK", _NAME
end

