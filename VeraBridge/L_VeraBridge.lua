_NAME = "VeraBridge"
_VERSION = "2016.04.19"
_DESCRIPTION = "VeraBridge plugin for openLuup!!"
_AUTHOR = "@akbooer"

-- bi-directional monitor/control link to remote Vera system
-- NB. this version ONLY works in openLuup
-- it plays with action calls and device creation in ways that you can't do in Vera,
-- in order to be able to implement ANY command action and 
-- also to logically group device numbers for remote machine device clones.

-- 2015-08-24   openLuup-specific code to action ANY serviceId/action request
-- 2015-11-01   change device numbering scheme
-- 2015-11-12   create links to remote scenes
-- 2016-02-15   use string altid (not number), thanks @cybrmage
-- 2016-03-19   prepare for major refactoring: 
--                retention of parent/child structure
--                mirroring of selected local openLuup devices on remote Vera
--                set LastUpdate variable to indicate active link, thanks @reneboer
-- 2016.03.27   fix for device 1 and 2 on non-primary bridges (clone all hidden devices)
-- 2016.04.14   fix for missing device #2
-- 2016.04.15   don't convert device states table into string (thanks @explorer)
-- 2016.04.17   chdev.create devices each time to ensure cloning of all attributes and variables
-- 2016.04.18   add username, password, ip, mac, json_file to attributes in chdev.create
-- 2016.04.19   fix action redirects for multiple controllers

local devNo                      -- our device number

local chdev     = require "openLuup.chdev"
local json      = require "openLuup.json"
local rooms     = require "openLuup.rooms"
local scenes    = require "openLuup.scenes"
local userdata  = require "openLuup.userdata"
local url       = require "socket.url"

--local pretty = require "pretty"   -- TODO: TESTING ONLY

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
local BLOCKSIZE = 10000           -- size of each block of device and scene IDs allocated
local Zwave = {}                  -- list of Zwave Controller IDs to map without device number translation

local function local_by_remote_id (id) 
  return Zwave[id] or id + OFFSET
end

local function remote_by_local_id (id)
  return Zwave[id] or id - OFFSET
end

-- change parent of given device, and ensure that it handles child actions
local function set_parent (devNo, newParent)
  local dev = luup.devices[devNo]
  if dev then
    local meta = getmetatable(dev).__index
    luup.log ("device[" .. devNo .. "] parent set to " .. newParent)
    meta.handle_children = true                   -- handle Zwave actions
    dev.device_num_parent = newParent             -- parent resides in two places under different names !!
    dev.attributes.id_parent = newParent
  end
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

-- make a list of our existing children, counting grand-children, etc.!!!
local function existing_children (parent)
  local c = {}
  local function children_of (d,index)
    for _, child in ipairs (index[d] or {}) do
      c[child] = luup.devices[child]
      children_of (child, index)
    end
  end
  
  local idx = {}
  for child, dev in pairs (luup.devices) do
    local num = dev.device_num_parent
    local children = idx[num] or {}
    children[#children+1] = child
    idx[num] = children
  end
  children_of (parent, idx)
  return c
end

-- create a new device, cloning the remote one
local function create_new (cloneId, dev, room)
--[[
          hidden          = nil, 
          pluginnum       = d.plugin,
          disabled        = d.disabled,

--]]
  local d = chdev.create {
    devNo = cloneId, 
    device_type = dev.device_type,
    internal_id = tostring(dev.altid),
    invisible   = dev.invisible == "1",   -- might be invisible, eg. Zwave and Scene controllers
    json_file   = dev.device_json,
    description = dev.name,
    upnp_file   = dev.device_file,
    upnp_impl   = 'X',              -- override device file's implementation definition... musn't run here!
    parent      = devNo,
    password    = dev.password,
    room        = room, 
    statevariables = dev.states,
    username    = dev.username,
    ip          = dev.ip, 
    mac         = dev.mac, 
  }  
  luup.devices[cloneId] = d   -- remember to put into the devices table! (chdev.create doesn't do that)
end

-- ensure that all the parent/child relationships are correct
local function build_families (devices)
  for _, dev in pairs (devices) do   -- once again, this 'devices' table is from the 'user_data' request
    local cloneId  = local_by_remote_id (dev.id)
    local parentId = local_by_remote_id (tonumber (dev.id_parent) or 0)
    if parentId == OFFSET then parentId = devNo end      -- the bridge is the "device 0" surrogate
    local clone  = luup.devices[cloneId]
    local parent = luup.devices[parentId]
    if clone and parent then
      set_parent (cloneId, parentId)
    end
  end
--  existing_children (devNo)     -- TODO: TESTING ONLY 
end

-- create the child devices managed by the bridge
local function create_children (devices, room)
  local N = 0
  local list = {}           -- list of created or deleted devices (for logging)
  local something_changed = false
  local current = existing_children (devNo)
  for _, dev in ipairs (devices) do   -- this 'devices' table is from the 'user_data' request
    dev.id = tonumber(dev.id)
      N = N + 1
      local cloneId = local_by_remote_id (dev.id)
      if not current[cloneId] then 
        something_changed = true
      end
      create_new (cloneId, dev, room) -- recreate the device anyway to set current attributes and variables
      list[#list+1] = cloneId
      current[cloneId] = nil
      -- TODO: update existing child device variables and attributes??
  end
  if #list > 0 then luup.log ("creating device numbers: " .. json.encode(list)) end
  
  list = {}
  for n in pairs (current) do
    luup.devices[n] = nil       -- remove entirely!
    something_changed = true
    list[#list+1] = n
  end
  if #list > 0 then luup.log ("deleting device numbers: " .. json.encode(list)) end
  
  build_families (devices)
  if something_changed then luup.reload() end
  return N
end

-- remove old scenes within our allocated block
local function remove_old_scenes ()
  local min, max = OFFSET, OFFSET + BLOCKSIZE
  for n in pairs (luup.scenes) do
    if (min < n) and (n < max) then
      luup.scenes[n] = nil            -- nuke it!
    end
  end
end

-- create a link to remote scenes
local function create_scenes (remote_scenes, room)
  local N,M = 0,0
--  remove_old_scenes ()
  luup.log "linking to remote scenes..."
  
  local action = "RunScene"
  local sid = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"
  local wget = 'luup.inet.wget "http://%s:3480/data_request?id=action&serviceId=%s&action=%s&SceneNum=%d"' 
  
  for _, s in pairs (remote_scenes) do
    local id = s.id + OFFSET             -- retain old number, but just offset it
    if not s.notification_only then
      if luup.scenes[id] then  -- don't overwrite existing
        M = M + 1
      else
        local new = {
          id = id,
          name = s.name,
          room = room,
          lua = wget:format (ip, sid, action, s.id)   -- trigger the remote scene
          }
        luup.scenes[new.id] = scenes.create (new)
        luup.log (("scene [%d] %s"): format (new.id, new.name))
        N = N + 1
      end
    end
  end
  
  local msg = "scenes: existing= %d, new= %d" 
  luup.log (msg:format (M,N))
  return N+M
end


local function GetUserData ()
  local Vera    -- (actually, 'remote' Vera!)
  local Ndev, Nscn = 0, 0
  local url = table.concat {"http://", ip, ":3480/data_request?id=user_data&output_format=json"}
  local atr = url:match "=(%a+)"
  local status, j = luup.inet.wget (url)
  if status == 0 then Vera = json.decode (j) end
  if Vera then 
    luup.log "Vera info received!"
    local t = ("%ss"): format (atr)
    if Vera.devices then
      local new_room_name = "MiOS-" .. (Vera.PK_AccessPoint: gsub ("%c",''))  -- stray control chars removed!!
      if Vera[t] then userdata.attributes [t] = Vera[t] end
      luup.log (new_room_name)
      rooms.create (new_room_name)
  
      remote_room_index = index_rooms (Vera.rooms or {})
      local_room_index  = index_rooms (luup.rooms or {})
      luup.log ("new room number: " .. (local_room_index[new_room_name] or '?'))
  
      Ndev = #Vera.devices
      luup.log ("number of remote devices = " .. Ndev)
      local roomNo = local_room_index[new_room_name] or 0
      Ndev = create_children (Vera.devices, roomNo)
      Nscn = create_scenes (Vera.scenes, roomNo)
    end
  end
  return Ndev, Nscn
end

-- MONITOR variables

-- updates existing device variables with new values
-- this devices table is from the "status" request
local function UpdateVariables(devices)
  for _, dev in pairs (devices) do
  dev.id = tonumber (dev.id)
    local i = local_by_remote_id(dev.id)
    if i and luup.devices[i] and (type (dev.states) == "table") then
      for _, v in ipairs (dev.states) do
        local value = luup.variable_get (v.service, v.variable, i)
        if v.value ~= value then
--          print ("update", dev.id, i, v.variable)    -- TODO: TEST ONLY
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
    luup.devices[devNo]:variable_set (SID.gateway, "LastUpdate", os.time(), true) -- 2016.03.20 set without log entry
  end 
  luup.call_delay ("VeraBridge_delay_callback", POLL_DELAY, DataVersion)
end

-- find other bridges in order to establish base device number for cloned devices
local function findOffset ()
  local offset
  local my_type = luup.devices[devNo].device_type
  local bridges = {}      -- devNos of ALL bridges
  for d, dev in pairs (luup.devices) do
    if dev.device_type == my_type then
      bridges[#bridges + 1] = d
    end
  end
  table.sort (bridges)      -- sort into ascending order by deviceNo
  for d, n in ipairs (bridges) do
    if n == devNo then offset = d end
  end
  return offset * BLOCKSIZE   -- every remote machine starts in a new block of devices
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
-- MIRROR CALLBACK HANDLER
--
function VeraBridge_Mirror_Callback (name, dev, srv, var, old, new)
  luup.log (("%s dev=%s, srv=%s, var=%s, old=%s, new=%s"): format (name, tostring(dev), 
      srv or '?', var or '?' , old or '?', new or '?'))
end

--
-- MIRROR ACTION HANDLERS
--

function CreateMirrorDevice (_, args)
  luup.log ("CreateMirrorDevice")
  local n = tonumber(args.LocalDeviceNum)
  if not (n and n < BLOCKSIZE and luup.devices[n]) then 
    luup.log ("CreateMirrorDevice: invalid local device number: " .. (n or '?'))
    return false end
  luup.log ("CreateMirrorDevice: mirroring local device number: " .. n)
  luup.log "NOT IMPLEMENTED"    -- TODO: create remote device, if necessary
  -- local device gets attribute: openLuup-mirror:123.45.67.89  (for IP of remote machine)
  -- remote device gets altid: openLuup-mirror:123.54.76.98 (for IP of this machine)
end

function DeleteMirrorDevice (_, args)
  luup.log ("DeleteMirrorDevice: not yet implemented")
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
        request[#request+1] = table.concat {a, '=', url.escape(b) or ''} 
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
  luup.log (_NAME)
  luup.log (_VERSION)
    
  devNo = lul_device
  OFFSET = findOffset ()
  luup.log ("device clone numbering starts at " .. OFFSET)

  -- map remote Zwave controller device if we are the primary VeraBridge 
  if OFFSET == BLOCKSIZE then 
    Zwave = {1}                   -- device IDs for mapping (same value on local and remote)
    set_parent (1, devNo)         -- ensure Zwave controller is an existing child 
    set_parent (2, 0)             -- unhook local scene controller (remote will have its own)
    luup.log "VeraBridge maps remote Zwave controller"
  end

  luup.devices[devNo].action_callback (generic_action)     -- catch all undefined action calls
  
  ip = luup.attr_get ("ip", devNo)
  luup.log (ip)
  
  local Ndev, Nscn = GetUserData ()
  luup.variable_set (SID.gateway, "Devices", Ndev, devNo)
  luup.variable_set (SID.gateway, "Scenes",  Nscn, devNo)
  luup.variable_set (SID.gateway, "Version", _VERSION, devNo)
  luup.variable_set (SID.altui, "DisplayLine1", Ndev.." devices, " .. Nscn .. " scenes", devNo)
  luup.variable_set (SID.altui, "DisplayLine2", ip, devNo)

  VeraBridge_delay_callback ()
  
  return true, "OK", _NAME
end

