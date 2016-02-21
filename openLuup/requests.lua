local _NAME = "openLuup.requests"
local revisionDate = "2015.11.09"
local banner = " version " .. revisionDate .. "  @akbooer"

--
-- openLuupREQUESTS - Luup Requests, as documented at http://wiki.mios.com/index.php/Luup_Requests
--
-- These are all implemented as standard luup.register_handler callbacks with the usual three parameters
--

-- 2016.02.21  correct sdata scenes table - thanks @ronluna

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
local plugins       = require "openLuup.plugins"
local loader        = require "openLuup.loader"       -- for static_data and loadtime

--  local log
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control

local build_version = '*' .. luup.version .. '*'  -- needed in sdata and user_data

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
    luup.devices[devNo] = nil
    luup.reload ()
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
      dev[#dev+1] = {
        name = d.description,
        altid = d.id,
        id = i,
        category = d.category_num,
        subcategory = d.subcategory_num,
        room = d.room_num,
        parent = d.device_num_parent,
      }
    end
  end
  return dev
end

local function sdata_scenes_table ()
  local info = {}
  for id, s in pairs (luup.scenes) do    -- TODO: actually, should only return changed ones
    info[#info + 1] = {
      id = id,
      room = s.room_num,
      name = s.description,
      active = 0,
    }
  end
  return info
end

-- This is an abbreviated form of user_data and status (sdata = summary data). 
-- It allows a user interface that is only worried about control, and not detailed configuration, 
-- to get a summary of the data that would normally be presented to the user and to monitor the changes.
-- http://VeraIP:3480/data_request?id=sdata&output_format=json
local function sdata(r,p,f)
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
    version = build_version,
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
    local debug = {device_ver = d:version_get()}
    if not d.invisible and d:version_get() > dv then
      info = info or {}         -- create table if not present
      local states = {}
      for serviceId, srv in pairs(d.services) do
        for name,item in pairs(srv.variables) do
          local ver = item.version
--          debug[name] = ver
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
      info[#info+1] = {id = i, status = -1, Jobs = {}, PendingJobs = 0, states = states}
    end
  end
  return info
end

local function status_scenes_table ()
  local info = {}
  for _, s in pairs (luup.scenes) do    -- TODO: actually, should only return changed scenes ?
    info[#info + 1] = {
      id = s.id,
      Jobs = {},
      status = -1,
      active = false,
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
  for id, job in pairs (scheduler.job_list) do
    tasks[#tasks + 1] = {
      id = id,
      status = job.status,
      type = job.type or ("device_no_" .. (job.devNo or '(system)')), 
      comments = job.notes,
    }
  end
  return startup
end

-- This returns the current status for all devices including all the current UPnP variables and the status of any active jobs. 
-- http://172.16.42.14:3480/data_request?id=status&DeviceNum=47
local function status (r,p,f)
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
local function user_data (r,p,f) 
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
      InstalledPlugins2 = plugins.installed (),
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
    local sd = {}
    for _, data in pairs (loader.static_data) do    -- bundle up the JSON data for all devices 
      sd[#sd+1] = data
    end
    user_data2.static_data = sd
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
local function room (r,p,f)
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

Because the json data can be long it is recommended to send it as an http POST instead of GET with the data passed with the name "json"  -- TODO: POST for JSON not yet implemented

list returns the JSON data for an existing scene. 

Example: http://ip_address:3480/data_request?id=scene&action=rename&scene=5&name=Chandalier&room=Garage
Example: http://ip_address:3480/data_request?id=scene&action=delete&scene=5
Example: http://ip_address:3480/data_request?id=scene&action=create&json=[valid json data]
Example: http://ip_address:3480/data_request?id=scene&action=list&scene=5

--]]

local function scene (r,p,f)  
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
local function variableset (r,p,f)
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
local function variableget (r,p,f)
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
      if Watts then
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

--TODO: return arguments
--[[
  HTTP:
  ERROR: Invalid Service
  ERROR: No implementation
  Luup:
   401 Invalid service/action/device
   401 "Invalid Service"  
   501 "No implementation"
--]]
local function action (r,p,f)
  -- notice that the argument list is the full HTTP query including DeviceNum, serviceId, and action
  local error, error_msg, job, arguments = luup.call_action (p.serviceId, p.action, p, tonumber(p.DeviceNum))
  local mime_type = "text/plain"
  local result = tostring(error)
  if type (arguments) == "table" then
    arguments.OK = "OK"
    result = {["u:"..p.action.."Response"] = arguments}
    if f == "json" then
      result = json.encode (result)
      mime_type = "application/json"
    else
      result = xml.encode (result)
      result = result: gsub ("^(%s*<u:%w+)", '<?xml version="1.0"?>\n%1 xmlns:u="Unknown Service"')
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
    local url = p.url or cam:variable_get (sid, "URL") or ''
--    local timeout = tonumber(cam:variable_get (sid, "Timeout")) or 5
    local timeout = tonumber(p.timeout) or 5
    if url then
      status, image = luup.inet.wget ("http://" .. ip .. url.value, timeout)
    end
  end
  if image then
    return image, "image/jpeg"
  else
    return "ERROR"
  end
end


-- misc

local function alive () return "OK" end                          -- return OK if the engine is running

local function debug() luup.debugON = not luup.debugON; return "DEBUG = ".. tostring(luup.debugON) end -- toggle debug

local function exit () scheduler.stop() ; return ("requested openLuup exit at "..os.date()) end     -- quit openLuup

local function reload () luup.reload () end     -- reload openLuup

local function file (_,p) return server.http_file (p.parameters or '') end                 -- file access

local function altui (_,p) plugins.create {PluginNum = 8246, TracRev=tonumber(p.rev)} end    -- install ALTUI

--
-- export all Luup requests
--

  return {
      action              = action, 
      alive               = alive,
      device              = device,
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
      variableget         = variableget, 
      variableset         = variableset,
      -- openLuup specials
      altui               = altui,        
      debug               = debug,
      exit                = exit,
    }
  

------------


