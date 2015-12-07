local version = "openLuup.gateway    2015.11.19  @akbooer"

-- HOME AUTOMATION GATEWAY
--
-- this is the Lua implementation of the Home Automation Gateway device, aka. Device 0
--

local plugins     = require "openLuup.plugins"
local scenes      = require "openLuup.scenes"
local userdata    = require "openLuup.userdata"     -- for HouseMode
local loader      = require "openLuup.loader"       -- for compile_lua

local devutil = require "openLuup.devices"

--- create the device!!


--local Device_0 = chdev.create {
--    devNo = 0, 
--    device_type = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
--}

local Device_0 = devutil.new (0)

-- No need for an implementation file - we can define all the services right here

local SID = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"

-- create a variable for CreateDevice return info
-- ...and, incidentally, the whole service also, which gets extended below...
Device_0: variable_set (SID, "DeviceNum", '')


--[[ action=CreateDevice
Create a device using the given parameters.

deviceType is the UPnP device type.
internalID is the specific ID (also known as altid) of the device; 
Description is the device name, which is shown to the user on the dashboard.
UpnpDevFilename is the UPnP device description file name.
UpnpImplFilename is the implementation file to use.
IpAddress is the IP address and port of the device.
DeviceNumParent is the device number of the parent device.
RoomNum is the number of the room the device will be in.
PluginNum tells the device which plugin to use. 
The plugin will be installed automatically if it's not already installed.
StateVariables is a string containing the variables you want set when the device is created. 
You can specify multiple variables by separating them with a line feed ('\n'), and use ',
' and '=' to separate service, variable and value, like this: 
  service,variable=value\nservice,variable=value\n...
If Reload is 1, the Luup engine will be restarted after the device is created. 

--]]

local function CreateDevice (_, p)
-- luup.create_device (device_type, internal_id, description, upnp_file, upnp_impl, 
--                  ip, mac, hidden, invisible, parent, room, pluginnum, statevariables...)
  local hidden, invisible, pluginnum
  local devNo = luup.create_device (
    p.deviceType or '', p.internalId or '', p.Description, 
    p.UpnpDevFilename, p.UpnpImplFilename,
    p.IpAddress, p.MacAddress, 
    hidden, invisible, 
    p.DeviceNumParent, tonumber(p.RoomNum),
    pluginnum, p.StateVariables)
    
    Device_0:variable_set (SID, "DeviceNum", devNo)    -- for return variable
  return true  
end

-- action=CreatePluginDevice&PluginNum=int 	
-- Creates a device for plugin #PluginNum.
-- StateVariables 	string 
local function CreatePluginDevice (_, p) 
  return plugins.create (p.PluginNum) 
end

-- action=CreatePlugin&PluginNum=int 	
-- Create a plugin with the PluginNum number and Version version. 
-- StateVariables are the variables that will be set when the device is created. 
-- For more information look at the description of the CreateDevice action above. 
local function CreatePlugin (_, p)
  return plugins.create (p)
end


-- action=DeleteDevice&DeviceNum=...
local function DeleteDevice ()
  return
end


-- build the action list

Device_0.services[SID].actions = 
  {
    
    CreateDevice = {  -- run creates device, returning job number, reload (if any) deferred to job
      run = CreateDevice,
      job = function (_, p) 
        if p.Reload == '1' then luup.reload () end
      end,
      name = "CreateDevice",
      returns = {DeviceNum = "DeviceNum"},
      serviceId = SID,
    },
    
    CreatePluginDevice  = {run = CreatePluginDevice},
    CreatePlugin        = {run = CreatePlugin},
    DeleteDevice        = {run = DeleteDevice},
    
    -- DeletePlugin 	PluginNum 	int 	Uninstall the given plugin. 
    DeletePlugin = {
      run = function (_, p)
        plugins.delete (p)
        luup.reload ()    
      end
    },
    
    -- LogIpRequest 	IpAddress 	UDN 	MacAddress 	UDN 
    LogIpRequest = {
      
    },
    
    -- action=ModifyUserData&inUserData=...&DataFormat=json&Reload=...
    -- Make changes to the UserData.
    --   inUserData is the new UserData object which will be added or replace a UserData object.
    --   DataFormat must be json.
    --   If Reload is 1 the LuaUPnP engine will reload after the UserData is modified. 
    --   For more information read http://wiki.micasaverde.com/index.php/ModifyUserData
    ModifyUserData = {
      
    },
    
    -- Reload the LuaUPnP engine. 
    Reload = {
      run = function ()
        luup.reload ()
        return true
      end
    },
     
    -- action=RunLua&Code=...
    -- error message should be plain text "ERROR: Code failed"
    RunLua = { 
      run = function (_, p) 
        local ok, status = loader.compile_lua (
          p.Code or "return 'ERROR: code failed'",
          "RunLua",
          scenes.environment)   -- runs in scene/startup context
        return ok and (status ~= false)   
      end, 
    },   
    
    -- action=RunScene&SceneNum=...
    -- Run the given scene. 
    RunScene = {
      run = function (_, p)
        local scene_num = tonumber (p.SceneNum)
        local scene = luup.scenes[scene_num or '']
        if scene then
          scene.run ()
        end
        return true
      end
    },
    
    -- action=SetHouseMode&Mode=...
    -- TODO: mode change delay (easy to do with job or call_delay)
    SetHouseMode = { 
      run = function (_, p) 
        local valid = {
            ["1"] = "1",    -- "home"
            ["2"] = "2",    -- "away"
            ["3"] = "3",    -- "night"
            ["4"] = "4",    -- "vacation"
          }
        local new = valid[p.Mode or ''] or "1"
        userdata.attributes.Mode = new
        userdata.attributes.mode_change_time = os.time()
        userdata.attributes.mode_change_mode = new
        return true
      end, 
    },

    --[[ 
    SetVariable - Create or change the value of a variable.
    DeviceNum can be an UDN or a number.
    Service is the service ID of the variable.
    Variable is the variable name.
    Value is the new variable value. 
    --]]
    SetVariable = {
      
    }
  } 

return Device_0


