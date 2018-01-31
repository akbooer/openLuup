local ABOUT = {
  NAME          = "openLuup.requests",
  VERSION       = "2018.01.29",
  DESCRIPTION   = "Luup Requests, as documented at http://wiki.mios.com/index.php/Luup_Requests",
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

--
-- openLuup.requests - Luup Requests, as documented at http://wiki.mios.com/index.php/Luup_Requests
--
-- These are all implemented as standard luup.register_handler callbacks with the usual three parameters
--

-- 2016.02.21  correct sdata scenes table - thanks @ronluna
-- 2016.02.22  add short_codes to sdata device table - thanks @ronluna
-- 2016.03.11  ensure that device delete removes all children and any relevant scene actions
-- 2016.03.15  add update for openLuup version downloads
-- 2016.04.10  add scene active and status flags in sdata and status reports
-- 2016.04.25  openLuup update changes
-- 2016.04.29  add actual device status to status response 
-- 2016.05.18  generic update_plugin request for latest version
-- 2016.05.23  fix &id=altui plugin numbering string (thanks @amg0)
-- 2016.06.04  remove luup.reload() from device delete action: AltUI requests reload anyway
-- 2016.06.20  better comments for plugin updates and openLuup-specific requests
-- 2016.06.22  move HTTP request plugin update/delete code to here from plugins
-- 2016.07.14  change 'file' request internal syntax to use server.wget
-- 2016.07.18  better error returns for action request
-- 2016.08.09  even better error returns for action request!
-- 2016.11.02  use startup_list (not job_list) in status response
-- 2016.11.15  only show non-successful startup jobs

-- 2017.01.10  fix non-integer values in live_energy_usage, thanks @reneboer
--             see: http://forum.micasaverde.com/index.php/topic,41249.msg306290.html#msg306290
-- 2017.02.05  add 'test' request (for testing!)
-- 2017.11.08  modifiy 'test' reporting text

-- 2018.01.29  and ns parameter option to user_Data request to ignore static_data object (new Luup feature?)

local server        = require "openLuup.server"
local json          = require "openLuup.json"
local xml           = require "openLuup.xml"
local scheduler     = require "openLuup.scheduler"
local devutil       = require "openLuup.devices"      -- for dataversion
local logs          = require "openLuup.logs"
local rooms         = require "openLuup.rooms"
local scenes        = require "openLuup.scenes"
local timers        = require "openLuup.timers"
local userdata      = require "openLuup.userdata"
local loader        = require "openLuup.loader"       -- for static_data, service_data, and loadtime

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control


-- Utility functions

-- return first found device ID if a device of the given type is present locally
local function device_present (device_type)
  for devNo, d in pairs (luup.devices) do
    if ((d.device_num_parent == 0)      -- local device...
    or  (d.device_num_parent == 2))     -- ...or child of openLuup device
    and (d.device_type == device_type) then
      return devNo
    end
  end
end

-----
--
-- LOCAL functions: HTTP request handlers
--

local function categories_table (devices)
  local names = {}
  for _,d in pairs (devices or luup.devices) do       -- first pass to find unique device categories
    if not d.invisible and d.category_num ~= 0 then
      names[d.category_num] = d.category_name        -- could be multiple occurrences, so just overwrite
    end
  end
  local info = {}
  for id,name in pairs (names) do                     -- second loop to return only those categories referenced
    info[#info+1] = {id = id, name = name}
  end
  return info
end

local function rooms_table ()
  local info = {}
  for i, name in pairs (luup.rooms) do
    info[#info+1] = {id = i, name = name, section = 1}
  end
  return info
end

local function sections_table ()
  return { {name = "My Home", id = 1} }
end

local function iprequests_table () 
  local info = {}
  for _,x in pairs (server.iprequests) do
    info[#info + 1] = x
  end
  return info 
end

--
-- non-user Luup HTTP requests
--

-- device
-- This renames or deletes a device. Use action=rename or action=delete. 
-- For rename, you can optionally assign a room by passing either the ID or the name.
--
--   http://ip_address:3480/data_request?id=device&action=rename&device=5&name=Chandelier&room=3
--   http://ip_address:3480/data_request?id=device&action=rename&device=5&name=Chandelier&room=Garage
--   http://ip_address:3480/data_request?id=device&action=delete&device=5
--
-- TODO: add better status messages
local function device (_,p)
  local devNo = tonumber (p.device)
  local dev = luup.devices[devNo]

  local function rename ()
    if p.name then
      dev.description = p.name
      dev.attributes.name = p.name
    end
    if p.room then
      local idx = {}
      for i,room in pairs(luup.rooms) do
        idx[room] = i
      end
      dev.room_num = tonumber(p.room) or idx[p.room] or 0
      dev.attributes.room = dev.room_num
    end
  end
  local function delete ()
    local tag = {}                -- list of devices to delete
    local function tag_children (n)
      tag[#tag+1] = n 
      for i,d in pairs (luup.devices) do
        if d.device_num_parent == n then tag_children (i) end
      end
    end
    tag_children(devNo)           -- find all the children, grand-children, etc...
    for _,j in pairs (tag) do
      luup.devices[j] = nil
    end    
    scenes.verify_all()           -- 2016.03.11 ensure there are no references to these devices in scene actions
    -- AltUI variable watch triggers will have to take care of themselves!
  end
  local function noop () end

  if dev then
    local valid = {rename = rename, delete = delete};
    (valid[p.action or ''] or noop) ()
    devutil.new_userdata_dataversion ()     -- say something major has changed
  end
  return "OK"       -- seems not to be specific about errors!
end


-- invoke
--This request shows the list of devices and the actions they support through the UPnP services specified in their UPnP device description file. 
--Only the actions with a star (*) preceding their name are implemented.
--
--    http://ip_address:3480/data_request?id=invoke
--    http://ip_address:3480/data_request?id=invoke&DeviceNum=6
--    http://ip_address:3480/data_request?id=invoke&UDN=uuid:4d494342-5342-5645-0002-000000000002 
--
local function invoke ()
  --TODO: lu_invoke
  error "*** invoke not yet implemented ***"
  return ''
end

-- Returns the recent IP requests in order by most recent first, [ACTUALLY, IT'S NOT ORDERED]
-- including information about devices in use and if the IP is blacklisted (ignored by the plug and play mechanism).  [NOT IMPLEMENTED] 
-- Optionally append timeout to specify the oldest IP request in seconds.  [NOT IMPLEMENTED]
local function iprequests () 
  local ips = json.encode({ip_requests = iprequests_table ()})
  return ips, "application/json" 
end

--
-- SDATA
--

local function sdata_devices_table (devices)
  local dev = {}
  for i,d in pairs (devices or luup.devices) do
    if not d.invisible then
      local info = {
        name = d.description,
        altid = d.id,
        id = i,
        category = d.category_num,
        subcategory = d.subcategory_num,
        room = d.room_num,
        parent = d.device_num_parent,
        state = -1,                       -- TODO: reflect true state from job status
      }
      -- add the additional information from short_code variables indexed in the service_data
      local sd = loader.service_data
      for svc, s in pairs (d.services) do
        local known_service = sd[svc]
        if known_service then
          for var, v in pairs(s.variables) do
            local short = known_service.short_codes[var]
            if short then info[short] = v.value end
          end
        end
      end
      dev[#dev+1] = info
    end
  end
  return dev
end

local function sdata_scenes_table ()
  local info = {}
  for id, s in pairs (luup.scenes) do    -- TODO: actually, should only return changed ones
    local running = s.running
    info[#info + 1] = {
      id = id,
      room = s.room_num,
      name = s.description,
      active = running and "1" or "0",
      state  = running and 4 or -1,
    }
  end
  return info
end

-- This is an abbreviated form of user_data and status (sdata = summary data). 
-- It allows a user interface that is only worried about control, and not detailed configuration, 
-- to get a summary of the data that would normally be presented to the user and to monitor the changes.
-- http://VeraIP:3480/data_request?id=sdata&output_format=json
local function sdata(...)
  local sdata = {
    categories = categories_table (),
    dataversion = devutil.dataversion.value,
    devices = sdata_devices_table (),
    full = 1,       -- TODO: make full=0 for partial updates
    loadtime = timers.loadtime,
    mode = tonumber(luup.attr_get "Mode"),
    rooms = rooms_table(),
    scenes = sdata_scenes_table(),
    serial_number = tostring (luup.pk_accesspoint),
    sections = sections_table(),
    state = -1,
    temperature = luup.attr_get "TemperatureFormat",
    version = luup.attr_get "BuildVersion",
  }
  return json.encode (sdata) or 'error in sdata', "application/json"
end 
--
-- STATUS
--

local function status_devices_table (device_list, data_version)
  local info 
  local dv = data_version or 0
  local dev_dv
  for i,d in pairs (device_list) do 
--    dev_dv = d:version_get() or 0
    if d:version_get() > dv then
      info = info or {}         -- create table if not present
      local states = {}
      for serviceId, srv in pairs(d.services) do
        for name,item in pairs(srv.variables) do
          local ver = item.version
--          if item.version > dv then
          do
            states[#states+1] = {
              id = item.id, 
              service = serviceId,
              variable = name,
              value = item.value,
            }
          end
        end
      end
      -- The lu_status URL will show for the device: <tooltip display="1" tag2="Lua Failure"/>
      local status = {
        id = i, 
        status = d:status_get() or -1,      -- 2016.04.29
        tooltip = {display = "0"},
        Jobs = {}, 
        PendingJobs = 0, 
        states = states
      }
      info[#info+1] = status
    end
  end
  return info
end

local function status_scenes_table ()
  local info = {}
  for id, s in pairs (luup.scenes) do    -- TODO: actually, should only return changed scenes ?
    local running = s.running
    info[#info + 1] = {
      id = id,
      Jobs = s.jobs or {},
      active = running,
      status = running and 4 or -1,
    }
  end
  return info
end

local function status_startup_table ()
  local tasks = {}
  local startup = {tasks = tasks}
  -- TODO: startup tasks:
  --[[
    startup": {
      "tasks": [
        {
            "id": 1,
            "status": 2,
            "type": "Test Plugin[58]",
            "comments": "Lua Engine Failed to Load"
        }
      ]
    },
]]--
  for id, job in pairs (scheduler.startup_list) do
    if job.status ~= scheduler.state.Done then
      tasks[#tasks + 1] = {
        id = id,
        status = job.status,
        type = job.type or ("device_no_" .. (job.devNo or '(system)')), 
        comments = job.notes,
      }
    end
  end
  return startup
end

-- This returns the current status for all devices including all the current UPnP variables and the status of any active jobs. 
-- http://172.16.42.14:3480/data_request?id=status&DeviceNum=47
local function status (_,p)
  local status = {                                -- basic top level attributes
    alerts = {},
    TimeStamp = os.time(),
    Mode = tonumber(luup.attr_get "Mode"),       
    LoadTime = timers.loadtime,
    DataVersion = devutil.dataversion.value,
    UserData_DataVersion = devutil.userdata_dataversion.value 
  }
  local d = os.date "*t"
  local x = os.date ("%Y-%m-%d %H:%M:%S")   -- LocalTime = "2015-07-26 14:23:50 D" (daylight savings)
  status.LocalTime = (x .. (({[true] = " D"})[d.isdst] or ''))
  local dv = tonumber(p.DataVersion)
  local device_list = luup.devices
  local DeviceNum = tonumber(p.DeviceNum)
  if DeviceNum then                                     -- specific device
    if not luup.devices[DeviceNum] then return "Bad Device" end
    device_list = {[DeviceNum] = luup.devices[DeviceNum]} 
  else                                                  -- ALL devices
  end
  local info = status_devices_table (device_list, dv)
  if DeviceNum then 
--        (info[1].id or _) = nil    
    status["Device_Num_"..DeviceNum] = (info or {})[1]
  else 
    status.devices = info
    status.startup = {tasks = {}}
    status.scenes  = status_scenes_table ()
    status.startup = status_startup_table () 
  end
  --TODO: status.visible_devices = ?
  return json.encode (status) or 'error in status', "application/json"
end

--
-- USER_DATA
--

local category_filter = {
  {
    Label = {
      lang_tag = "ui7_all",
      text = "All"},
    categories = {},
    id = 1},
  {
    Label = {
      lang_tag = "ui7_av_devices",
      text = "Audio/Video"},
    categories = {"15"},
    id = 2},
  {
    Label = {
      lang_tag = "ui7_lights",
      text = "Lights"},
    categories = {"2","3"},
    id = 3},
  {
    Label = {
      lang_tag = "ui7_cameras",
      text = "Cameras"},
    categories = {"6"},
    id = 4},
  {
    Label = {
      lang_tag = "ui7_door_locks",
      text = "Door locks"},
    categories = {"7"},
    id = 5},
  {
    Label = {
      lang_tag = "ui7_sensors",
      text = "Sensors"},
    categories = {"4","12","16","17","18"},
    id = 6},
  {
    Label = {
      lang_tag = "ui7_thermostats",
      text = "Thermostats"},
    categories = {"5"},
    id = 7}
}


local function user_scenes_table()
  local scenes = {}
  for _,sc in pairs (luup.scenes) do
    scenes[#scenes+1] = sc.user_table()
  end
  return scenes
end

-- This returns the configuration data for Vera, 
-- which is a list of all devices and the UPnP variables which are persisted between resets [NOT YET IMPLEMENTED]
-- as well as rooms, names, and other data the user sets as part of the configuration.
local function user_data (_,p) 
  local result = "NO_CHANGES"
  local mime_type = "text/plain"
  local dv = tonumber(p.DataVersion)
  local distance = math.abs (devutil.dataversion.value - (dv or 0))
  if not dv 
  or (dv < devutil.dataversion.value) 
  or distance > 1000        -- ignore silly values
  then 
    local user_data2 = {
      LoadTime = timers.loadtime,
      DataVersion = devutil.userdata_dataversion.value, -- NB: NOT the same as the status DataVersion
      InstalledPlugins2 = userdata.attributes.InstalledPlugins2,
      category_filter = category_filter,
      devices = userdata.devices_table (luup.devices),
      ip_requests = iprequests_table(),
      rooms = rooms_table(),
      scenes = user_scenes_table(),
      sections = sections_table(),
    }
    for a,b in pairs (userdata.attributes) do      -- add all the top-level attributes
      user_data2[a] = b
    end
    if p.ns ~= '1' then     -- 2018.01.29
      local sd = {}
      for _, data in pairs (loader.static_data) do    -- bundle up the JSON data for all devices 
        sd[#sd+1] = data
      end
      user_data2.static_data = sd
    end
    mime_type = "application/json"
    result = json.encode (user_data2)
  end
  return  result, mime_type
end

-- room
--
--Example: http://ip_address:3480/data_request?id=room&action=create&name=Kitchen
--Example: http://ip_address:3480/data_request?id=room&action=rename&room=5&name=Garage
--Example: http://ip_address:3480/data_request?id=room&action=delete&room=5

--This creates, renames, or deletes a room depending on the action. 
--To rename or delete a room you must pass the room id for the with room=N.
--
local function room (_,p)
  local name = (p.name ~= '') and p.name
  local number = tonumber (p.room)

  local function create () rooms.create (name) end
  local function rename () rooms.rename (number, name) end
  local function delete () rooms.delete (number) end
  local function noop () end

  do -- room ()
    local valid = {create = create, rename = rename, delete = delete};
    (valid[p.action or ''] or noop) ()
    devutil.new_userdata_dataversion ()     -- say something major has changed
  end
  return "OK"       -- seems not to be specific about errors!
end

--[[

SCENES

When using the 'create' command json must be valid JSON for a scene as documented in Scene_Syntax. 
The name, room and optional id (if you're overwriting an existing scene) are passed in the json, so nothing is on the command line except the json. 

Because the json data can be long it is recommended to send it as an http POST instead of GET with the data passed with the name "json" 

list returns the JSON data for an existing scene. 

Example: http://ip_address:3480/data_request?id=scene&action=rename&scene=5&name=Chandalier&room=Garage
Example: http://ip_address:3480/data_request?id=scene&action=delete&scene=5
Example: http://ip_address:3480/data_request?id=scene&action=create&json=[valid json data]
Example: http://ip_address:3480/data_request?id=scene&action=list&scene=5

--]]

local function scene (_,p)  
  local name = (p.name ~= '') and p.name
  local room = (p.room ~= '') and p.room
  local number = tonumber (p.scene)
  local response
  --Example: http://ip_address:3480/data_request?id=scene&action=delete&scene=5
  local function delete (scene) 
    if scene then 
      scene:stop()                             -- stop scene triggers and timers
      luup.scenes[scene.user_table().id] = nil -- remove reference to the scene
    end
  end
  --Example: http://ip_address:3480/data_request?id=scene&action=create&json=[valid json data]
  local function create () 
    local new_scene, msg = scenes.create (p.json)
    if new_scene then
      local id = new_scene.user_table().id
      if luup.scenes[id] then
        delete (luup.scenes[id])               -- remove the old scene with this id
      end
      luup.scenes[id] = new_scene              -- slot into scenes table
    end
    return msg    -- nil if all OK
  end
  --Example: http://ip_address:3480/data_request?id=scene&action=rename&scene=5&name=Chandelier&room=Garage
  local function rename (scene) 
    local new_room_num
    if room then
      local room_index = {}
      for i, name in pairs (luup.rooms) do room_index[name] = i end
      new_room_num = room_index[room]
    end
    if scene then scene.rename (name, new_room_num) end
  end
  --Example: http://ip_address:3480/data_request?id=scene&action=list&scene=5
  local function list (scene)
    if scene and scene.user_table then
      return json.encode (scene.user_table()) or "ERROR"
    end
    return "ERROR"
  end
  local function noop () return "ERROR" end

  do -- scene ()
    local valid = {create = create, rename = rename, delete = delete, list = list}
    response = (valid[p.action or ''] or noop) (luup.scenes[number or ''])
    if p.action ~= "list" then devutil.new_userdata_dataversion () end  -- say something major has changed
  end
  return response or "OK"
end

-- http://ip_address:3480/data_request?id=variableset&DeviceNum=6&serviceId=urn:micasaverde-com:serviceId:DoorLock1&Variable=Status&Value=1
-- If you leave off the DeviceNum and serviceID, then this sets a top-level json tag called "Variable" with the value.
local function variableset (_,p)
  local devNo = tonumber (p.DeviceNum) or 0
--  if devNo == 0 and not p.serviceId and p.Variable then
  if (not p.serviceId) and p.Variable then
    luup.attr_set (p.Variable, p.Value, devNo)
  else
    luup.variable_set (p.serviceId, p.Variable, p.Value or '', devNo) 
  end
  return "OK"
end

-- http://ip_address:3480/data_request?id=variableget&DeviceNum=6&serviceId=urn:micasaverde-com:serviceId:DoorLock1&Variable=Status
-- If you leave off the DeviceNum and serviceId, then this gets a top-level json tag called "Variable".
local function variableget (_,p)
  local result
  local devNo = tonumber (p.DeviceNum) or 0
  if devNo == 0 and p.Variable then
    result = tostring (userdata.attributes[p.Variable])
  else
    result = luup.variable_get (p.serviceId, p.Variable, devNo) 
  end
  return result
end

-- reports the current energy usage in a tab delimited format. 
local function live_energy_usage ()
  local live_energy_usage = {}
  local sid = "urn:micasaverde-com:serviceId:EnergyMetering1"
  local fmt = "%d\t%s\t%s\t%d\t%d"
  for devNo, dev in pairs (luup.devices) do
    local svc = dev.services[sid]
    if svc then
      local Watts = svc.variables.Watts 
      if Watts and tonumber (Watts.value)then       -- 2017.01.10 thanks @reneboer
        local room = luup.rooms[dev.room_num or 0] or ''
        local line = fmt: format (devNo, dev.description, room, dev.category_num, Watts.value)
        live_energy_usage[#live_energy_usage+1] = line
      end
    end
  end 
  return table.concat (live_energy_usage, '\n')
end

-- eg:  /data_request?id=action&output_format=json&DeviceNum=0&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&action=SetHouseMode&Mode=2
-- with response:
--{"u:SetHouseModeResponse": {"OK": "OK"}}

local function action (_,p,f)
  -- notice that the argument list is the full HTTP query including DeviceNum, serviceId, and action
  local error, error_msg, _, arguments = luup.call_action (p.serviceId, p.action, p, tonumber(p.DeviceNum))
  local result, mime_type = '', "text/plain"
  if error ~= 0 then
    if error == -1 then error_msg = "Device does not handle service/action" end
    result = "ERROR: " .. (error_msg or error or '?')
  else
    arguments = arguments or {}
    arguments.OK = "OK"
    result = {["u:"..p.action.."Response"] = arguments}
    if f == "json" then
      result = json.encode (result)
      mime_type = "application/json"
    else
      result = xml.encode (result)
      result = result: gsub ("^(%s*<u:[%w_]+)", '<?xml version="1.0"?>\n%1 xmlns:u="' .. (p.serviceId or "UnknownService") .. '"')
      mime_type = "application/xml"
    end
  end
  return result, mime_type
end

-- jobstatus
-- Returns the status of a job. 
-- The parameters are job, which is the job ID and optionally plugin, which is the plugin name. 
-- For a Z-Wave job the plugin parameter must be zwave. [NOT IMPLEMENTED]
-- If job is invalid the status returned is -1.

local function jobstatus ()
  error "NOT YET IMPLEMENTED: jobstatus"
end

--
-- CAMERA
--
--[[
 request_image

Returns an image from a camera. This fetches the image from the camera using the URL variable for the device. Pass arguments:

cam = the device id of the camera.  This is the only mandatory argument.
res = optional: a resolution, which gets appended to the variable.  
      So passing "low" means the image from the URL_low variable will be returned.
      If it doesn't exist it reverts to the standard URL or DirectStreamingURL
timeout = optional: how long to wait for the image to be retrieved, 
      or how long to retrieve video. defaults to 10 seconds.
url = optional: override the camera's default URL
ip = optional: override the camera's default ip
user or pass = optional: override the camera's default username/password

--]]

local function request_image (_, p)
  local sid = "urn:micasaverde-com:serviceId:Camera1"
  local image, status
  local devNo = tonumber(p.cam)
  local cam = luup.devices[devNo]
  if cam then
    local ip = p.ip or luup.attr_get ("ip", devNo) or ''
    local url = p.url or luup.variable_get (sid, "URL", devNo) or ''
--    local timeout = tonumber(cam:variable_get (sid, "Timeout")) or 5
    local timeout = tonumber(p.timeout) or 5
    if url then
      status, image = luup.inet.wget ("http://" .. ip .. url, timeout)
    end
  end
  if image then
    return image, "image/jpeg"
  else
    return "ERROR"
  end
end

--[[
---------------------------------------------------------

PLUGIN UPDATES: THINGS TO KNOW:

From the Plugins page, AltUI issues two types of requests 
depending on whether or not anything is entered into the Update box:

empty request to openLuup:

/data_request?id=update_plugin&Plugin=openLuup

entry of "v0.8.2" to VeraBridge update box:

/data_request?id=action&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&action=CreatePlugin&PluginNum=VeraBridge&Version=v0.8.2

... NOTE: the difference between the parameter names specifying the Plugin!!

Because the MiOS plugin store Version has nothing to do with AltUI build versions, @amg0 tags GitHub releases and passes these to openLuup when a browser refresh plugin update is initiated:

This, for example, is an update request from AltUI after a browser refresh discovers there's a new version

/data_request?id=action&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&action=CreatePlugin&PluginNum=8246&Version=31806&TracRev=1788

---------------------------------------------------------
--]]

--
-- update_plugin ()
-- This is a genuine Vera-style request for an update
-- originated from the Update button of the plugins page
-- the TracRev parameter (pre-GitHub!) is used by AltUI to override the MiOS Version number 
local function update_plugin (_,p) 
  
  local Plugin = p.PluginNum or p.Plugin
  local tag = p.TracRev or p.Version          -- pecking order for parameter names
  local meta, errmsg = userdata.plugin_metadata (Plugin, tag)
    
  if meta then
    local sid = "urn:upnp-org:serviceId:AltAppStore1"
    local act = "update_plugin"
    local arg = {metadata = json.encode (meta)}
    local dev = device_present "urn:schemas-upnp-org:device:AltAppStore:1"
    
    -- check for pre-install device-specific configuration, failure means do NOT install
    local status
    status, errmsg = luup.call_action ("openLuup", "plugin_configuration", meta, 2) 
    
    if status == 0 then
      _, errmsg = luup.call_action (sid, act, arg, dev)       -- actual install
      
      -- NOTE: that the above action executes asynchronously and the function call
      --       returns immediately, so you CAN'T do a luup.reload() here !!
      --       (it's done at the end of the <job> part of the called action)
    end
  end
  
  if errmsg then _log (errmsg) end
  return errmsg or "OK", "text/plain" 
end

-- delete_plugin ()
local function delete_plugin (_, p)
  local Plugin = p.PluginNum  or '?'
  local IP, idx = userdata.find_installed_data (Plugin)
  if idx then
    local device_type = IP.Devices[1].DeviceType                -- assume it's there!
    table.remove (userdata.attributes.InstalledPlugins2, idx)   -- move all the higher indices down, also
    _log ("removing plugin devices of type: " .. (device_type or '?'))
    for devNo, d in pairs (luup.devices) do                     -- remove associated devices....
      if (d.device_type == device_type) 
      and (d.device_num_parent == 0) then     -- local device of correct type...
        _log ("delete device #" .. devNo)
        local msg = device (_, {action="delete", device=devNo}) -- call device action in this module
        _log (msg or ("Plugin removed: " .. devNo))
      end
    end
    _log ("Plugin_removed: " .. Plugin)
  end
  return "No such plugin: " .. Plugin, "text/plain"
end


--
-- Miscellaneous
--

-- return OK if the engine is running
local function alive () return "OK" end

-- file access
local function file (_,p) 
  local _,f = server.wget ("http://localhost:3480/" .. (p.parameters or '')) 
  return f 
end

-- reload openLuup
local function reload () luup.reload () end

--
-- openLuup additions
--
local function test (r,p)
  local d = {"data_request","id=" .. r}   -- 2017.11.08
  for a,b in pairs (p) do
    d[#d+1] = table.concat {a,'=',b}
  end
  return table.concat (d,'\n')
end

-- easy HTTP request to force a download of AltUI
local function altui (_,p) return update_plugin (_, {PluginNum = "8246", Version= p.Version}) end

-- easy HTTP request to force openLuup update (not used by AltUI)
local function update (_,p) return update_plugin (_, {PluginNum = "openLuup", Version = p.Version}) end

-- toggle debug flag (not yet used)
local function debug() luup.debugON = not luup.debugON; return "DEBUG = ".. tostring(luup.debugON) end

-- force openLuup final exit openLuup (to exit calling script reload loop)
local function exit () scheduler.stop() ; return ("requested openLuup exit at "..os.date()) end

--
-- export all Luup requests
--

return {
  ABOUT = ABOUT,
  
  action              = action, 
  alive               = alive,
  device              = device,
  delete_plugin       = delete_plugin,
  file                = file,
  iprequests          = iprequests,
  invoke              = invoke,
  jobstatus           = jobstatus,
  live_energy_usage   = live_energy_usage,
  reload              = reload,
  request_image       = request_image,
  room                = room,
  scene               = scene,
  sdata               = sdata, 
  status              = status, 
  status2             = status, 
  user_data           = user_data, 
  user_data2          = user_data,
  update_plugin       = update_plugin,      -- download latest plugin version
  variableget         = variableget, 
  variableset         = variableset,
  
  -- openLuup specials
  altui               = altui,              -- download AltUI version from GitHub
  debug               = debug,              -- toggle debug flag
  exit                = exit,               -- shutdown
  test                = test,               -- for testing!
  update              = update,             -- download openLuup version from GitHub
}


------------


