ABOUT = {
  NAME          = "VeraBridge",
  VERSION       = "2018.03.24",
  DESCRIPTION   = "VeraBridge plugin for openLuup",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
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
-- 2016.04.22   fix old room allocations
-- 2016.04.29   update device status
-- 2016.04.30   initial implementation of mirror devices (thanks @logread for design discussions & prototyping)
-- 2016.05.08   @explorer options for bridged devices
-- 2016.05.14   settled on implementation of mirror devices using top-level openLuup.mirrors attribute
-- 2016.05.15   HouseMode variable to reflect status of bridged Vera (thanks @logread)
-- 2016.05.21   @explorer fix for missing Zwave device children when ZWaveOnly selected
-- 2016.05.23   HouseModeMirror for mirroring either way (thanks @konradwalsh)
-- 2016.06.01   Add GetVeraFiles action to replace openLuup_getfiles separate utility
-- 2016.06.20   Do not re-parent device #2 (now openLuup device) if not child of #1 (_SceneController)
-- 2016.08.12   Add CloneRooms option (set to 'true' to use same rooms as remote Vera)
-- 2016.11.12   only set LastUpdate when remote variable changes to avoid triggering a local status response
--              thanks @delle, see: http://forum.micasaverde.com/index.php/topic,40434.0.html
 
-- 2017.02.12   add BridgeScenes flag (thanks @DesT) 
-- 2017.02.22   add 'remote_ip' request using new extra_returns action parameter
-- 2017.03.07   add Mirror as AltUI Data Service Provider
-- 2017.03.09   add wildcard '*' in Mirror syntax to preserve existing serviceId or variable name
-- 2017.03.17   don't override existing user attibutes (thanks @explorer)
-- 2017.05.10   add category_num and subcategory_num to bridge devices (thanks @dklinkman)
-- 2017.07.19   add GetVeraScenes action call to copy (not just link) remote scenes
-- 2017.08.08   move unimplemented triggers warning in GetVeraScenes to generic openLuup scene handler

-- 2018.01.11   refactor remote requests in advance of Vera security changes closing HTTP ports
--              remove deprecated mirror functionality - instead use AltUI Data Storage Provider callbacks
-- 2018.01.29   ignore static_data content in user_Data request using the (new) &ns=1 option
-- 2018.02.05   use real action to trigger HouseMode change so that openLuup plugin triggers
--              thanks @RHCPNG, see: http://forum.micasaverde.com/index.php/topic,56664.0.html
-- 2018.02.09   continuing updates for Vera security changes (/port_3480)
-- 2018.02.11   fix recent SID error in RegisterDataProvider (thanks @Buxton)
--              and /port_3480/ separator
--              qdd TEMP COPY suffix to scenes by action call
-- 2018.02.17   Redirect any SID.hag action to the remote Vera, device 0
--              useful (perhaps) for things like SetHouseMode and SetGeoFence
--              thanks @RHCPNG, see: http://forum.micasaverde.com/index.php/topic,57834.0.html
-- 2018.02.20   include remote HouseMode in bridge panel DisplayLine2
-- 2018.02.21   don't try and display HouseMode if none (eg. UI5)
-- 2018.03.01   fix serviceId error for DisplayLine2 initialisation
-- 2018.03.02   if mirroring remote House Mode, then change local Mode with immediate effect
-- 2018.03.24   use luup.rooms.create metatable method


local devNo                      -- our device number

local chdev     = require "openLuup.chdev"
local json      = require "openLuup.json"
local scenes    = require "openLuup.scenes"
local userdata  = require "openLuup.userdata"
local url       = require "socket.url"
local lfs       = require "lfs"

local ip                          -- remote machine ip address
local POLL_DELAY = 5              -- number of seconds between remote polls

local local_room_index           -- bi-directional index of our rooms
local remote_room_index          -- bi-directional of remote rooms

local BuildVersion                -- ...of remote machine

local SID = {
  altui    = "urn:upnp-org:serviceId:altui1"  ,         -- Variables = 'DisplayLine1' and 'DisplayLine2'
  gateway  = "urn:akbooer-com:serviceId:VeraBridge1",
  hag      = "urn:micasaverde-com:serviceId:HomeAutomationGateway1",
}

--local Mirrored          -- mirrors is a set of device IDs for 'reverse bridging', not to be cloned
--local MirrorHash        -- reverse lookup: local hash to remote device ID
local HouseModeMirror   -- flag with one of the following options
local HouseModeTime = 0 -- last time we checked

local HouseModeOptions = {      -- 2016.05.23
  ['0'] = "0 : no mirroring",
  ['1'] = "1 : local mirrors remote",
  ['2'] = "2 : remote mirrors local",
}

-- 2017.0719  saved variables required for GetVeraScenes action
local VeraScenes, VeraRoom

-- @explorer options for device filtering

local BridgeScenes, CloneRooms, ZWaveOnly, Included, Excluded

-- LUUP utility functions 

local function getVar (name, service, device) 
  service = service or SID.gateway
  device = device or devNo
  local x = luup.variable_get (service, name, device)
  return x
end

local function setVar (name, value, service, device)
  service = service or SID.gateway
  device = device or devNo
  local old = luup.variable_get (service, name, device)
  if tostring(value) ~= old then 
   luup.variable_set (service, name, value, device)
  end
end

-- get and check UI variables
local function uiVar (name, default, lower, upper)
  local value = getVar (name) 
  local oldvalue = value
  if value and (value ~= "") then           -- bounds check if required
    if lower and (tonumber (value) < lower) then value = lower end
    if upper and (tonumber (value) > upper) then value = upper end
  else
    value = default
  end
  value = tostring (value)
  if value ~= oldvalue then setVar (name, value) end   -- default or limits may have modified value
  return value
end

-- given a string of numbers s = "n, m, ..." convert to a set (for easy indexing)
local function convert_to_set (s)
  local set = {}
  for a in s: gmatch "%d+" do
    local n = tonumber (a)
    if n then set[n] = true end
  end
  return set
end

-- remote request to port_3480
local function remote_request (request)    -- 2018.01.11
  return luup.inet.wget (table.concat {"http://", ip, "/port_3480", request})
end


-----------
-- mapping between remote and local device IDs

local OFFSET                      -- offset to base of new device numbering scheme
local BLOCKSIZE = 10000           -- size of each block of device and scene IDs allocated
local Zwave = {}                  -- list of Zwave Controller IDs to map without device number translation

local function local_by_remote_id (id) 
  return Zwave[id] or id + OFFSET
end

local function remote_by_local_id (id)
  if id == devNo then return 0 end  -- point to remote Vera device 0
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

-- create bi-directional indices of REMOTE rooms: room name <--> room number
local function index_remote_rooms (rooms)    --<-- different structure
  local room_index = {}
  for _, room in pairs (rooms) do
    local number, name = room.id, room.name
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
    category_num    = dev.category_num,      -- 2017.05.10
    devNo           = cloneId, 
    device_type     = dev.device_type,
    internal_id     = tostring(dev.altid or ''),
    invisible       = dev.invisible == "1",   -- might be invisible, eg. Zwave and Scene controllers
    json_file       = dev.device_json,
    description     = dev.name,
    upnp_file       = dev.device_file,
    upnp_impl       = 'X',              -- override device file's implementation definition... musn't run here!
    parent          = devNo,
    password        = dev.password,
    room            = room, 
    statevariables  = dev.states,
    subcategory_num = dev.subcategory_num,      -- 2017.05.10
    username        = dev.username,
    ip              = dev.ip, 
    mac             = dev.mac, 
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

-- return true if device is to be cloned
-- note: these are REMOTE devices from the Vera status request
-- consider: ZWaveOnly, Included, Excluded (...takes precedence over the first two)
-- and Mirrored, a sequence of "remote = local" device IDs for 'reverse bridging'

-- plus @explorer modification
-- see: http://forum.micasaverde.com/index.php/topic,37753.msg282098.html#msg282098

local function is_to_be_cloned (dev)
  local d = tonumber (dev.id)
  local p = tonumber (dev.id_parent)
  local zwave = p == 1 or d == 1
  if ZWaveOnly and p then -- see if it's a child of the remote zwave device
      local i = local_by_remote_id(p)
      if i and luup.devices[i] then zwave = true end
  end
--  return  not (Excluded[d] or Mirrored[d])
  return  not (Excluded[d])
          and (Included[d] or (not ZWaveOnly) or (ZWaveOnly and zwave) )
end

--[[
-- original
local function is_to_be_cloned (dev)
  local d = tonumber (dev.id)
  local p = tonumber (dev.id_parent)
  local zwave = p == 1
  return  not (Excluded[d] or Mirrored[d])
          and (Included[d] or (not ZWaveOnly) or (ZWaveOnly and zwave) )
end
--]]

-- create the child devices managed by the bridge
local function create_children (devices, room_0)
  local N = 0
  local list = {}           -- list of created or deleted devices (for logging)
  local something_changed = false
  local current = existing_children (devNo)
  for _, dev in ipairs (devices) do   -- this 'devices' table is from the 'user_data' request
    dev.id = tonumber(dev.id)
    if is_to_be_cloned (dev) then
      N = N + 1
      local room = room_0
      local cloneId = local_by_remote_id (dev.id)
      if not current[cloneId] then 
        something_changed = true
      else
        local new_room
        local remote_room = tonumber(dev.room)
        if CloneRooms then    -- force openLuup to use the same room as Vera
          new_room = local_room_index[remote_room_index[remote_room]] or 0
        else
          new_room = luup.devices[cloneId].room_num
        end
        room = (new_room ~= 0) and new_room or room_0   -- use room number
      end
      create_new (cloneId, dev, room) -- recreate the device anyway to set current attributes and variables
      list[#list+1] = cloneId
      current[cloneId] = nil
    end
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

  if not BridgeScenes then        -- 2017.02.12
    remove_old_scenes ()
    luup.log "remote scenes not linked"
    return 0
  end
  
  luup.log "linking to remote scenes..."
  
  local action = "RunScene"
  local wget = 'luup.inet.wget "http://%s/port_3480/data_request?id=action&serviceId=%s&action=%s&SceneNum=%d"' 
  
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
          lua = wget:format (ip, SID.hag, action, s.id)   -- trigger the remote scene
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
  local url = "/data_request?id=user_data2&output_format=json&ns=1"   -- 2018.01.29  ignore static_data content
  local status, j = remote_request (url)
  local version
  if status == 0 then Vera = json.decode (j) end
  if Vera then 
    luup.log "Vera info received!"
    local t = "users"
    if Vera.devices then
      local new_room_name = "MiOS-" .. (Vera.PK_AccessPoint: gsub ("%c",''))  -- stray control chars removed!!
      userdata.attributes [t] = userdata.attributes [t] or Vera[t]
      luup.log (new_room_name)
      luup.rooms.create (new_room_name)     -- 2018.03.24  use luup.rooms.create metatable method
  
      remote_room_index = index_remote_rooms (Vera.rooms or {})
      local_room_index  = index_rooms (luup.rooms or {})
      luup.log ("new room number: " .. (local_room_index[new_room_name] or '?'))
      
      if CloneRooms then    -- check individual rooms too...
        for room_name in pairs (remote_room_index) do
          if type(room_name) == "string" then
            if not local_room_index[room_name] then 
              luup.log ("creating room: " .. room_name)
              local new = luup.rooms.create (room_name)     -- 2018.03.24  use luup.rooms.create metatable method
              local_room_index[new] = room_name
              local_room_index[room_name] = new
            end
          end
        end
      end
  
      version = Vera.BuildVersion
      luup.log ("BuildVersion = " .. version)
      
      Ndev = #Vera.devices
      luup.log ("number of remote devices = " .. Ndev)
      local roomNo = local_room_index[new_room_name] or 0
      Ndev = create_children (Vera.devices, roomNo)
      Nscn = create_scenes (Vera.scenes, roomNo)
      do      -- 2017.07.19
        VeraScenes = Vera.scenes
        VeraRoom = roomNo
      end
    end
  end
  return Ndev, Nscn, version
end

-- MONITOR variables

-- updates existing device variables with new values
-- this devices table is from the "status" request
local function UpdateVariables(devices)
  local update = false
  for _, dev in pairs (devices) do
  dev.id = tonumber (dev.id)
    local i = local_by_remote_id(dev.id)
    local device = i and luup.devices[i] 
    if device and (type (dev.states) == "table") then
      device: status_set (dev.status)      -- 2016.04.29 set the overall device status
      for _, v in ipairs (dev.states) do
        local value = luup.variable_get (v.service, v.variable, i)
        if v.value ~= value then
          luup.variable_set (v.service, v.variable, v.value, i)
          update = true
        end
      end
    end
  end
  return update
end

-- update HouseMode variable and, possibly, the actual openLuup Mode
local modeName = {"Home", "Away", "Night", "Vacation"}
local displayLine = "%s [%s]"

local function UpdateHouseMode (Mode)
  Mode = tonumber(Mode)
  if not Mode then return end   -- 2018.02.21  bail out if no Mode (eg. UI5)
  local status = modeName[Mode] or '?'
  Mode = tostring(Mode)
  setVar ("HouseMode", Mode)                                            -- 2016.05.15, thanks @logread!
  setVar ("DisplayLine2", displayLine: format(ip, status), SID.altui)   -- 2018.02.20
  
  local current = userdata.attributes.Mode
  if current ~= Mode then 
    if HouseModeMirror == '1' then
      -- luup.attr_set ("Mode", Mode)                                     -- 2016.05.23, thanks @konradwalsh!
      -- 2018.02.05, use real action, thanks @RHCPNG
      luup.call_action (SID.hag, "SetHouseMode", {Mode = Mode, Now=1})    -- 2018.03.02  with immediate effect 

    elseif HouseModeMirror == '2' then
      local now = os.time()
      luup.log "remote HouseMode differs from that set..."
      if now > HouseModeTime + 60 then        -- ensure a long delay between retries (Vera is slow to change)
        local switch = "remote HouseMode update, was: %s, switching to: %s"
        luup.log (switch: format (Mode, current))
        HouseModeTime = now
        local request = "/data_request?id=action&serviceId=%s&DeviceNum=0&action=SetHouseMode&Mode=%s"
        remote_request (request: format(SID.hag, current))
      end
    end
  end
end

-- poll remote Vera for changes
-- TODO: make callback use asynchronous I/O
local poll_count = 0
function VeraBridge_delay_callback (DataVersion)
  local s
  poll_count = (poll_count + 1) % 10            -- wrap every 10
  if poll_count == 0 then DataVersion = '' end  -- .. and go for the complete list (in case we missed any)
  local url = "/data_request?id=status2&output_format=json&DataVersion=" .. (DataVersion or '')
  local status, j = remote_request (url)
  if status == 0 then s = json.decode (j) end
  if s and s.devices then
    UpdateHouseMode (s.Mode)
    DataVersion = s.DataVersion
    if UpdateVariables (s.devices) then -- 2016.11.20 only update if any variable changes
      luup.devices[devNo]:variable_set (SID.gateway, "LastUpdate", os.time(), true) -- 2016.03.20 set without log entry
    end 
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
-- MIRRORS
--

-- openLuup.mirrors syntax is:
-- <VeraIP>
-- <VeraDeviceId> = <openLuupDeviceId>.<serviceId>.<variableName>
-- ...
--[==[

luup.attr_set ("openLuup.mirrors", [[
192.168.99.99
82 = 15.urn:upnp-org:serviceId:TemperatureSensor1.CurrentTemperature 
83 = 16.urn:micasaverse-com:serviceId:HumiditySensor1.CurrentLevel
85 = 17.urn:cd-jackson-com:serviceId:SystemMonitor.memoryAvailable
85 = 17.urn:cd-jackson-com:serviceId:SystemMonitor.systemLuupRestartTime
]])

--]==]

-- set up variable watches for mirrored devices, 
-- returning set of devices to ignore in cloning
-- and hash table for variable watch
--local function set_of_mirrored_devices ()
--  local Minfo = luup.attr_get "openLuup.mirrors"      -- this attribute set at startup
--  local mirrored = {}
--  local hashes = {}                     -- hash table of all mirrored variables
--  local our_ip = false                  -- set to true when we're parsing our own data
--  luup.log "reading mirror info..."
--  for line in (Minfo or ''): gmatch "%C+" do
--    local ip_info = line:match "^%s*(%d+%.%d+%.%d+%.%d+)"      -- IP address format
--    if ip_info then 
--      our_ip = ip_info == ip
--    elseif our_ip then
--      local rem, lcl, srv, var  = line:match "^%s*(%d+)%s*=%s*(%d+)%.(%S+)%.(%S+)"
--      if var then
--        -- set up device watch
--        rem = tonumber (rem)
--        lcl = tonumber (lcl)
--        luup.log (("mirror: rem=%s, lcl=%d.%s.%s"): format (rem, lcl, srv, var))
--        local m = mirrored[rem] or {}                       -- flag remote device as a mirror, so don't clone locally
--        local hash = table.concat ({lcl, srv, var}, '.')    -- build hash key
--        hashes[hash] = rem
--        m[#m+1] = {lcl=lcl, srv=srv, var=var, hash=hash}    -- add to list of watched vars for this device
--        mirrored[rem] = m 
--      end
--    end
--  end
--  return mirrored, hashes
--end

-- Mirror watch callbacks

--function VeraBridge_Mirror_Callback (dev, srv, var, _, new)
--  local hash = table.concat ({dev, srv, var}, '.')
--  local request = "http://%s:3480/data_request?id=variableset&DeviceNum=%d&serviceId=%s&Variable=%s&Value=%s"
--  local rem = MirrorHash[hash]
--  if rem then   --  send to remote device
--    luup.inet.wget (request: format(ip, rem, srv, var, url.escape(new)))
--  end
--end

---- set up callbacks and initialise remote device variables
--local function watch_mirror_variables (mirrored)
--  for rem, mirror in pairs (mirrored) do
--    for _, v in ipairs (mirror) do
--      luup.variable_watch ("VeraBridge_Mirror_Callback", v.srv, v.var, v.lcl)   -- start watching 
--      local val = luup.variable_get (v.srv, v.var, v.lcl)
--      VeraBridge_Mirror_Callback (rem, v.srv, v.var, nil, val or '')  -- use the callback to set the values
--    end
--  end
--  return
--end

--
-- Bridge ACTION handler(s)
--

-- copy all device files and icons from remote vera
-- (previously performed by the openLuup_getfiles utility)
function GetVeraFiles ()
  
  local code = [[

  local lfs = require "lfs"
  local f = io.open ("/www/directory.txt", 'w')
  for fname in lfs.dir ("%s") do
    if fname:match "lzo$" or fname: match "png$" then
      f:write (fname)
      f:write '\n'
    end
  end
  f:close ()

  ]]

-- TODO: New Vera security measures will disable, by default, RunLua
-- could bypass this by defining and running a scene with Lua code attached
  local function get_directory (path)
    local template = "/data_request?id=action" ..
                      "&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1" ..
                      "&action=RunLua&Code="
    local request = template .. url.escape (code: format(path))

    local status, info = remote_request (request)
    if status ~= 0 then luup.log ("error creating remote directory listing: " .. status) return end

    status, info = luup.inet.wget ("http://" .. ip .. "/directory.txt")
    if status ~= 0 then luup.log ("error reading remote directory listing: " .. status) return end
    
    return info
  end

-- TODO: does this work with new port_3480 access?
  local function get_files_from (path, dest, url_prefix)
    dest = dest or '.'
    url_prefix = url_prefix or "/port_3480/"
    luup.log ("getting files from " .. path)
    local info = get_directory (path)
    for x in info: gmatch "%C+" do
      local fname = x:gsub ("%.lzo",'')   -- remove unwanted extension for compressed files
      local status, content = luup.inet.wget ("http://" .. ip .. url_prefix .. fname)
      if status == 0 then
        luup.log (table.concat {#content, ' ', fname})
        
        local f = io.open (dest .. '/' .. fname, 'wb')
        f:write (content)
        f:close ()
      else
        luup.log ("error: " .. fname)
      end
    end
  end

  -- device, service, lua, json, files...
  lfs.mkdir "files"
  get_files_from ("/etc/cmh-ludl/", "files", "/port_3480/")
  get_files_from ("/etc/cmh-lu/", "files", "/port_3480/")
  luup.log "...end of device files"
  
  -- icons
  lfs.mkdir "icons"
  local _,b,_ = BuildVersion: match "(%d+)%.(%d+)%.(%d+)"    -- branch, major minor
  local major = tonumber(b)

  local icon_directories = {
    [5] = "/www/cmh/skins/default/icons/",                        -- UI5 icons
    [6] = "/www/cmh_ui6/skins/default/icons/",                    -- UI6 icons, thanks to @reneboer for this information
    [7] = "/www/cmh/skins/default/img/devices/device_states/",    -- UI7 icons
  }
 
  if major then  
    if major > 5 then     -- UI7
      get_files_from (icon_directories[7], "icons", "/cmh/skins/default/img/devices/device_states/")
    else                  -- UI5
      get_files_from (icon_directories[5], "icons", "/cmh/skins/default/icons/")
    end
    luup.log "...end of icon files"  
  end
end


-- GetVeraScenes action (not to be confused with the usual scene linking.)
-- Makes new copies in the 100,000+ range to aid logic transfer to openLuup

function GetVeraScenes()
  luup.log "GetVeraScenes action called"
  
  if VeraScenes then
    for _,s in pairs (VeraScenes) do
      luup.log (s.name)
      s.name = s.name .. " TEMP COPY"
      -- embedded Lua code, and timers are unchanged
      s.paused = "1"                            -- don't want this to run by default
      s.room = VeraRoom                         -- default place for this Vera
      s.id = s.id + OFFSET + 1e5     -- BIG offset for these scenes
      
      -- convert triggers and actions to point to local devices
      s.triggers = s.triggers or {}
      for _,t in ipairs (s.triggers) do
        t.device = t.device + OFFSET
        t.enabled = 0             -- disable it
      end
      for _,g in ipairs (s.groups or {}) do
        for _,a in ipairs (g.actions or {}) do
          a.device = a.device + OFFSET
        end
      end
      
      -- now create new scene locally
      luup.scenes[s.id] = scenes.create (s)
    end
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
      "http://", ip, "/port_3480/data_request?id=action",
      "&serviceId=", serviceId,
      "&action=", name,
    }
  local function job (lul_device, lul_settings)
    local devNo = remote_by_local_id (lul_device)
    if not devNo then return end        -- not a device we have cloned

    if devNo == 0 and serviceId ~= SID.hag then  -- 2018.02.17  only pass on hag requests to device #0
      return 
    end
  
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
  
  -- This action call to ANY child device of this bridge:
  -- luup.call_action ("urn:akbooer-com:serviceId:VeraBridge1","remote_ip",{},10123)
  -- will return something like: 
  -- {IP = "172.16.42.14"}

  if serviceId == SID.gateway and name == "remote_ip" then     -- 2017.02.22  add remote_ip request
    return {serviceId = serviceId, name = name, extra_returns = {IP = ip} }
  end
    
  return {run = job}    -- TODO: job or run ?
end

-- make either "1" or "true" work the same way
local function logical_true (flag)
  return flag == "1" or flag == "true"
end

--------------
--
-- Mirror Data Storage Provider, 2017.03.07
--

---- MIRROR with AltUI Data Storage Provider functionality
local function MirrorHandler (_,x) 
  local tag = x.mirror
  if tag then
    local dev, srv, var = tag:match "^(%d+)%.?([^%.]*)%.?([^%.]*)"    -- blank if field missing
    srv = ((srv ~= '') and (srv ~= '*')) and srv or x.lul_service     -- use default if not defined or wildcard
    var = ((var ~= '') and (var ~= '*')) and var or x.lul_variable
    
    local sysNo, devNo = (x.lul_device or ''): match "(%d+)%-(%d+)"
    if dev and sysNo == "0" then    -- only mirror local devices
      local message = "VeraBridge DSP Mirror: %s.%s.%s --> %s.%s.%s@" .. ip
      luup.log (message: format(devNo, x.lul_service, x.lul_variable, dev, srv, var))
      local request = "/data_request?id=variableset&DeviceNum=%s&serviceId=%s&Variable=%s&Value=%s"
      local req = request: format(dev, srv, var, url.escape(x.new or ''))
      luup.log (req) 
      remote_request (req)
    end
  end
  return "OK", "text/plain"
end


-- register VeraBridge as an AltUI Data Storage Provider
local function register_AltUI_Data_Storage_Provider ()
  local MirrorCallback    = "HTTP_VeraBridgeMirror_" .. ip
  local MirrorCallbackURL = "http://127.0.0.1:3480/data_request?id=lr_" .. MirrorCallback
  -- the use of :3480 above is correct, since this is a localhost openLuup request
  
  local AltUI
  for devNo, d in pairs (luup.devices) do
    if d.device_type == "urn:schemas-upnp-org:device:altui:1" 
    and d.device_num_parent == 0 then   -- look for it on the LOCAL machine (might be bridged to another!)
      AltUI = devNo
      break
    end
  end
  
  if not AltUI then return end
  
  luup.log ("registering with AltUI [" .. AltUI .. "] as Data Storage Provider")
  _G[MirrorCallback] = MirrorHandler
  luup.register_handler (MirrorCallback, MirrorCallback)
  
  local newJsonParameters = {
    {
        default = "device.serviceId.name",
        key = "mirror",
        label = "Mirror",
        type = "text"
--      },{
--        default = "/data_request?id=lr_" .. MirrorCallback,
--        key = "graphicurl",
--        label = "Graphic Url",
--        type = "url"
      }
    }
  local arguments = {
    newName = "Vera@" .. ip,
    newUrl = MirrorCallbackURL,
    newJsonParameters = json.encode (newJsonParameters),
  }

  luup.call_action (SID.altui, "RegisterDataProvider", arguments, AltUI)
end


-- plugin startup
function init (lul_device)
  luup.log (ABOUT.NAME)
  luup.log (ABOUT.VERSION)
  
  devNo = lul_device
  ip = luup.attr_get ("ip", devNo)
  luup.log (ip)
  
  OFFSET = findOffset ()
  luup.log ("device clone numbering starts at " .. OFFSET)

  -- User configuration parameters: @explorer and @logread options
  
  BridgeScenes = uiVar ("BridgeScenes", "true")
  CloneRooms  = uiVar ("CloneRooms", '')        -- if set to 'true' then clone rooms and place devices there
  ZWaveOnly   = uiVar ("ZWaveOnly", '')         -- if set to 'true' then only Z-Wave devices are considered by VeraBridge.
  Included    = uiVar ("IncludeDevices", '')    -- list of devices to include even if ZWaveOnly is set to true.
  Excluded    = uiVar ("ExcludeDevices", '')    -- list of devices to exclude from synchronization by VeraBridge, 
                                              -- ...takes precedence over the first two.
  
  local hmm = uiVar ("HouseModeMirror",HouseModeOptions['0'])   -- 2016.05.23
  HouseModeMirror = hmm: match "^([012])" or '0'
  setVar ("HouseModeMirror", HouseModeOptions[HouseModeMirror]) -- replace with full string
  
  BridgeScenes = logical_true (BridgeScenes) 
  CloneRooms = logical_true (CloneRooms)                        -- convert to logical
  ZWaveOnly  = logical_true (ZWaveOnly) 
  
  Included = convert_to_set (Included)
  Excluded = convert_to_set (Excluded)  
--  Mirrored, MirrorHash = set_of_mirrored_devices ()       -- create set and hash of remote device IDs which are mirrored
  
  -- map remote Zwave controller device if we are the primary VeraBridge 
  if OFFSET == BLOCKSIZE then 
    Zwave = {1}                   -- device IDs for mapping (same value on local and remote)
    set_parent (1, devNo)         -- ensure Zwave controller is an existing child 
    local d2 = luup.devices[2]
    if d2.device_num_parent ~= 0 then   --   2016.06.20
      set_parent (2, 0)           -- unhook local scene controller (remote will have its own)
    end
    luup.log "VeraBridge maps remote Zwave controller"
  end

  luup.devices[devNo].action_callback (generic_action)     -- catch all undefined action calls
  
  local Ndev, Nscn
  Ndev, Nscn, BuildVersion = GetUserData ()
  
  do -- version number
    local y,m,d = ABOUT.VERSION:match "(%d+)%D+(%d+)%D+(%d+)"
    local version = ("v%d.%d.%d"): format (y%2000,m,d)
    setVar ("Version", version)
    luup.log (version)
  end
  
  setVar ("DisplayLine1", Ndev.." devices, " .. Nscn .. " scenes", SID.altui)
  setVar ("DisplayLine2", ip, SID.altui)        -- 2018.03.02
  
  if Ndev > 0 or Nscn > 0 then
--    watch_mirror_variables (Mirrored)         -- set up variable watches for mirrored devices
    VeraBridge_delay_callback ()
    luup.set_failure (0)                      -- all's well with the world
  else
    luup.set_failure (2)                      -- say it's an authentication error
  end

  register_AltUI_Data_Storage_Provider ()     -- register with AltUI as MIRROR data storage provider
  
  return true, "OK", ABOUT.NAME
end

-----
