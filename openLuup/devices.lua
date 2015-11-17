local revisionDate = "2015.11.16"
local banner = "     version " .. revisionDate .. "  @akbooer"

--
-- openLuup.devices
--

local files     = require "openLuup.loader"           -- reads device .xml and .json files
local scheduler = require "openLuup.scheduler"        -- for scheduling startup function

--
-- SYSTEM data versions
--

local initial_dataversion = (os.time() % 10e5) * 1e3 + 1
local dataversion = {value = initial_dataversion}             -- updated as data changes
local userdata_dataversion = {value = initial_dataversion}    -- updated as device/service/variable structure changes

-- update the global devices dataversion, and the current device version
local function new_dataversion ()
  dataversion.value = dataversion.value + 1
end

local function new_userdata_dataversion ()
  userdata_dataversion.value = userdata_dataversion.value + 1   -- checkpoint of user_data ???
  dataversion.value = dataversion.value + 1                     -- update this too, for good luck
end

local static_data = {}          -- cache for decoded static JSON data, indexed by filename

local service_data = {}         -- cache for serviceType and serviceId data, indexed by both

local sys_watchers = {}         -- list of system-wide (ie. non-device-specific) watchers

----
--
-- CONSTANTS
--

local mcv  = "urn:schemas-micasaverde-com:device:"
local upnp = "urn:schemas-upnp-org:device:"

local categories_lookup =             -- info about device types and categories
  {
      {id =  1, name = "Interface",          type = mcv  .. "HomeAutomationGateway:1"},
      {id =  2, name = "Dimmable Switch",    type = upnp .. "DimmableLight:1"},  
      {id =  3, name = "On/Off Switch",      type = upnp .. "BinaryLight:1"},
      {id =  4, name = "Sensor",             type = mcv  .. "DoorSensor:1"},
      {id =  5, name = "HVAC",               type = upnp .. "HVAC_ZoneThermostat:1"}, 
      {id =  6, name = "Camera",             type = upnp .. "DigitalSecurityCamera:1"},  
      {id =  6, name = "Camera",             type = upnp .. "DigitalSecurityCamera:2"},  
      {id =  7, name = "Door Lock",          type = mcv  .. "DoorLock:1"},
      {id =  8, name = "Window Covering",    type = mcv  .. "WindowCovering:1"},
      {id =  9, name = "Remote Control",     type = mcv  .. "RemoteControl:1"}, 
      {id = 10, name = "IR Transmitter",     type = mcv  .. "IrTransmitter:1"}, 
      {id = 11, name = "Generic I/O",        type = mcv  .. "GenericIO:1"},
      {id = 12, name = "Generic Sensor",     type = mcv  .. "GenericSensor:1"},
      {id = 13, name = "Serial Port",        type =         "urn:micasaverde-org:device:SerialPort:1"},  -- yes, it really IS different       
      {id = 14, name = "Scene Controller",   type = mcv  .. "SceneController:1"},
      {id = 15, name = "A/V",                type = mcv  .. "avmisc:1"},
      {id = 16, name = "Humidity Sensor",    type = mcv  .. "HumiditySensor:1"},
      {id = 17, name = "Temperature Sensor", type = mcv  .. "TemperatureSensor:1"},
      {id = 18, name = "Light Sensor",       type = mcv  .. "LightSensor:1"},
      {id = 19, name = "Z-Wave Interface",   type = mcv  .. "ZWaveNetwork:1"},
      {id = 20, name = "Insteon Interface",  type = mcv  .. "InsteonNetwork:1"},
      {id = 21, name = "Power Meter",        type = mcv  .. "PowerMeter:1"},
      {id = 22, name = "Alarm Panel",        type = mcv  .. "AlarmPanel:1"},
      {id = 23, name = "Alarm Partition",    type = mcv  .. "AlarmPartition:1"},
      {id = 23, name = "Alarm Partition",    type = mcv  .. "AlarmPartition:2"},
      {id = 24, name = "Siren",              type = mcv  .. "Siren:1"},
  }

local cat_by_dev = {}                         -- category number lookup by device type
local cat_name_by_dev = {}                    -- category  name  lookup by device type
for _,cat in ipairs (categories_lookup) do
  cat_by_dev[cat.type] = cat.id 
  cat_name_by_dev[cat.type] = cat.name 
end

-----
--
-- VARIABLE object 
-- 
-- Note that there is no "get" function, object variables can be read directly (but setting should use the method)
--

local variable = { VarID = 0 }                    -- unique variable number incremented for each now instance
  
function variable.new (name, serviceId, devNo)     -- factory for new variables
  variable.VarID = variable.VarID + 1
  new_userdata_dataversion ()                     -- say structure has changed
  return {
      -- variables
      dev       = devNo,
      id        = variable.VarID,                 -- unique ID
      name      = name,                           -- name (unique within service)
      srv       = serviceId,
      watchers  = {},                             -- callback hooks
      -- methods
      set       = variable.set,
    }
end
  
function variable:set (value)
  new_dataversion ()                              -- say value has changed
  self.old      = self.value or "EMPTY"
  self.value    = tostring(value or '')           -- set new value (all device variables are strings)
  self.time     = os.time()                       -- save time of change
  self.version  = dataversion.value               -- save version number
  return self
end


-----
--
-- SERVICE object 
--
-- Services contain variables and actions
--

local service = {}
  
function service.new (serviceId, devNo)        -- factory for new services
  local actions   = {}
  local variables = {}

  -- set variable value, creating new one if required, and returning variable object
  local function variable_set (self, name, value)
    local var = variables[name] or variable.new(name, serviceId, devNo)   -- create new if absent
    variables[name] = var
    return var:set (value)
  end

  -- get variable value, returning nil if missing
  local function variable_get (self, name)
    return variables[name]
  end
  
  return {
    -- variables
    actions       = actions,
    variables     = variables,
    watchers      = {},                       -- callback hooks for service (any variable)
    -- methods
    variable_set  = variable_set,
    variable_get  = variable_get,
  }
end


-----
--
-- WATCH devices, services and variables
-- 
-- function: variable_watch
-- parameters: device (number), function (function), service (string), variable (string or nil)
-- returns: nothing
-- Adds the function to the list(s) of watchers
-- If variable is nil, function will be called whenever any variable in the service is changed. 
-- If device is nil see: http://forum.micasaverde.com/index.php/topic,34567.0.html
-- thanks @vosmont for clarification of undocumented feature
--

local function variable_watch (dev, fct, serviceId, variable)
  local callback = {callback = fct, devNo = (luup or {}).device}    -- devNo is current context
  if dev then
    -- a specfic device
    local srv = dev.services[serviceId]
    if srv then
      local var = srv.variables[variable] 
      if var then                                 -- set the watch on the variable
        var.watchers[#var.watchers+1] = callback
      else                                        -- set the watch on the service
        srv.watchers[#srv.watchers+1] = callback
      end
    else
      dev.watchers[#dev.watchers+1] = callback     -- set the watch on the device
    end
  else
    -- ALL devices
    if serviceId then   -- can only watch specific service across all devices
      sys_watchers[serviceId] = sys_watchers[serviceId] or {}
      local srv = sys_watchers[serviceId]
      local var = variable or "*"
      srv[var] = srv[var] or {}
      local watch = srv[var]
      watch[#watch+1] = callback  -- set the watch on the variable or service
    end
  end
end


-----
--
-- DEVICE object 
--
--
-- Devices support services with variables.  They also contain attributes.
-- At a minimum, this call requires a device_number AND a device_type OR upnp_file (device file).

--[[ 
function: create
parameters:

    device_number (number)    *** NB: extra parameter cf. luup.create ***
    device_type (string)
    internal_id (string)
    description (string)
    upnp_file (string)
    upnp_impl (string)
    ip (string)
    mac (string)
    hidden (boolean)
    invisible (boolean)
    parent (number)
    room (number)
    pluginnum (number)
    statevariables (string)
    pnpid (number)
    nochildsync (string)
    aeskey (string)
    reload (boolean)
    nodupid (boolean) 

This creates the device with the parameters given, and returns the device object 

You can specify multiple variables by separating them with a line feed (\n) and use a, and = to separate service, variable and value, like this: service,variable=value\nservice..
]]

local function create (devNo, device_type, internal_id, description, upnp_file, upnp_impl, ip, mac, hidden, invisible, parent, room, pluginnum, statevariables, ...)
  local attributes            -- device attributes
  local services    = {}      -- all service variables and actions here
  local version               -- set device version (used to flag changes for HTTP requests)
  local code                  -- the module containing the device implementation code
  local missing_action        -- an action callback to catch missing actions
  local watchers    = {}      -- list of watchers for any service or variable
  
  -- Checks whether a device has successfully completed its startup sequence. If so, is_ready returns true. 
  local function is_ready ()
    return true           -- TODO: wait on startup sequence 
  end
 
  -- function: variable_set
  -- parameters: service (string), variable (string), value (string), watch (boolean)
  -- if watch is true, then invoke any watchers for this device/service/variable
  -- returns: the variable object 
  local function variable_set (self, serviceId, name, value, watch)
    local srv = services[serviceId] or service.new(serviceId, devNo)     -- create serviceId if missing
    services[serviceId] = srv
    local var = srv:variable_set (name, value)                    -- this updates the variable's data version
    version = dataversion.value                                   -- ...and now update the device version 
    if watch then
    -- note that this only _schedules_ the callbacks, they are not actually invoked _now_
      local dev = self
      local sys = sys_watchers[serviceId] or {}  
      if sys["*"] then                -- flag as service value change to non-specific device watchers
        scheduler.watch_callback {var = var, watchers = sys["*"]} 
      end 
      if sys[name] then               -- flag as variable value change to non-specific device watchers
        scheduler.watch_callback {var = var, watchers = sys[name]} 
      end 
      if #dev.watchers > 0 then           -- flag as device value change to watchers
        scheduler.watch_callback {var = var, watchers = watchers} 
      end 
      if #srv.watchers > 0 then       -- flag as service value change to watchers
        scheduler.watch_callback {var = var, watchers = srv.watchers} 
      end 
      if #var.watchers > 0 then       -- flag as variable value change to watchers
        scheduler.watch_callback {var = var, watchers = var.watchers} 
      end 
    end
    return var
  end
 
  -- function: variable_get
  -- parameters: service (string), variable (string)
  -- returns: the variable object
  local function variable_get (self, serviceId, name)
    local var
    local srv = services[serviceId]
    if srv then var = srv:variable_get (name) end
    return var, srv
  end
  
  -- function: supports_service
  -- parameters: service ID (string)
  -- returns: true if the device supports the service, false otherwise
  local function supports_service (self, service)
    return not not services[service]    -- only return true/false, not contents!
  end
 
  -- internal function to create and set service actions (from implementation file)
  -- action_tags is a structure with (possibly) run/job/timeout/incoming functions
  -- it also has 'name' and 'serviceId' fields
  -- and may have 'returns' added below using information (from service file)
 local function action_set (serviceId, name, action_tags)
    local srv = services[serviceId] or service.new(serviceId, devNo)     -- create serviceId if missing
    services[serviceId] = srv
    srv.actions[name] = action_tags
    -- add any return parameters from service_data
    local sdata = service_data[serviceId] or {returns = {}}
    action_tags.returns = sdata.returns[name]
  end
   
  -- function: call_action
  -- parameters: service (string), action (string), arguments (table), device (number)
  -- returns: error (number), error_msg (string), job (number), arguments (table)
  --
  -- Invokes the UPnP service + action, passing in the arguments (table of string->string pairs) to the device. 
  -- If the invocation could not be made, only error will be returned with a value of -1. 
  -- error is 0 if the UPnP device reported the action was successful. 
  -- arguments is a table of string->string pairs with the return arguments from the action. 
  -- If the action is handled asynchronously by a Luup job, 
  -- then the job number will be returned as a positive integer.
  --
  -- NOTE: that the target device may be different from the device which handles the action
  --       if the <handleChildren> tag has been set to 1 in the parent's device file.

  local function call_action (self, serviceId, action, arguments, target_device)
     -- 'act' is an object with (possibly) run / job / timeout / incoming methods
     -- note that the loader has also added 'name' and 'serviceId' fields to the action object
    local act = (services[serviceId] or {actions = {}}).actions [action] 
    if not act and missing_action then
      -- create a new action, dynamically linking to the supplied action handler
      act = missing_action (serviceId, action)
      action_set (serviceId, action, act)   -- "a" has {run/job/timeout/incoming} + name and serviceId
    end
    if act then     
      return scheduler.run_job (act, arguments, devNo, target_device or devNo)
    else
      return -1, "no such service"
    end
  end
 
  -- function attr_set ()
  -- parameters: attribute (string), value(string) OR table of {name = value} pairs
  -- returns: nothing
  --
  -- Sets the top level attribute(s) for the device to value(s). Examples of attributes are 'mac', 'name', 'id', etc. 
  -- TODO: clear up some confusion about whether mac, name, etc, should also be updated in the device itself.
  -- TODO: at the moment, attr_set does _not_ update the dataversion - is this right?
  local function attr_set (self, attribute, value)
    if type (attribute) ~= "table" then attribute = {[attribute] = value} end
    for name, value in pairs (attribute) do 
      if not attributes[name] then new_userdata_dataversion() end   -- structure has changed
      attributes[name] = tostring(value)
    end
  end
    
  -- function: attr_get
  -- parameters: attribute (string), device (string or number)
  -- returns: the value
  --
  -- Gets the top level attribute for the device. Examples of attributes are 'mac', 'name', 'id', etc. 
  local function attr_get (self, attribute)
    return attributes[attribute]
  end
  
  -- CREATE ()
  -- create (devNo, device_type, internal_id, description, upnp_file, upnp_impl, ip, mac, 
  --              hidden, invisible, parent, room, pluginnum, statevariables, ...)

  new_dataversion ()                                      -- say something's changed
  new_userdata_dataversion ()                             -- say it's structure, not just values
  version = dataversion.value                             -- set the device's version number
  
  -- read device file, if present  
  local d = files.read_device (upnp_file)                
  device_type = d.device_type or device_type              -- device file overrides input parameter
  
  -- read service files, if referenced, and save service_data
  if d.service_list then
    for _,x in ipairs (d.service_list) do
      local stype = x.serviceType 
      if stype then
        if not service_data[stype] then                       -- if not previously stored
          local sfile = x.SCPDURL
          service_data[stype] = files.read_service (sfile)    -- save the serviceType details
        end
        local sid = x.serviceId
        if sid then
          service_data[sid] = service_data[stype]             -- point the serviceId to the same
        end
      end
    end
  end
  
  -- read JSON file, if present and not already cached, and save it in static_data structure
  local j = d.json_file
  if j and not static_data[j] then
    local json = files.read_json (j)  
    if json then
      json.device_json = j              -- insert possibly missing info (for ALTUI icons - thanks @amg0!)
    end
  static_data [j] = json  
  end
  
  -- read implementation file, if present  
  if not upnp_impl or upnp_impl == '' then                -- input parameter overrides device file
    upnp_impl = d.impl_file
  end
  local i = {}
  if upnp_impl then i = files.read_impl (upnp_impl) end   -- assume files in current directory
  -- load and compile the amalgamated code from <files>, <functions>, <actions>, and <startup> tags
  
  if i.source_code then
    local error_msg
    local name = "device_" .. devNo
    local globals = {lul_device = devNo}
    code, error_msg = files.compile_lua (i.source_code, name, nil, globals)  -- load, compile, instantiate
    if not code then print ("Compile Lua error:",error_msg) end
    i.source_code = nil   -- free up for garbage collection
  end
 
  code = code or {}
  code.lul_device = devNo
  -- go through actions and link into services
  local action_list = code._openLuup_ACTIONS_
  if action_list then
    for _, a in ipairs (action_list) do
      action_set (a.serviceId, a.name, a)   -- "a" has {run/job/timeout/incoming} + name and serviceId
    end
  end
  code._openLuup_ACTIONS_ = nil             -- remove from code name space
  
  local incoming_handler = code._openLuup_INCOMING_
  code._openLuup_INCOMING_ = nil             -- remove from code name space
  
  -- go through the variables and set them
  -- syntax is: "serviceId,variable=value" separated by new lines
  if type(statevariables) == "string" then
    for srv, var, val in statevariables: gmatch "%s*([^,]+),([^=]+)=([^%c]*)" do
      variable_set (nil, srv, var, val)
    end
  end
  
  -- set known attributes

  attributes = {
    id              = devNo,                        -- device id
    altid           = internal_id or '',            -- altid (called id in luup.devices, confusing, yes?)
    device_type     = device_type or '',
    device_file     = upnp_file,
    device_json     = d.json_file,
    category_num    = tonumber (d.category_num) or cat_by_dev[device_type] or 0,
    id_parent       = tonumber (parent) or 0,
    impl_file       = upnp_impl,
    invisible       = invisible and "1" or "0",   -- convert true/false to "1"/"0"
    manufacturer    = d.manufacturer or '',
    model           = d.modelName or '',
    name            = description or d.friendly_name or ('_' .. (device_type:match "(%w+):%d+$" or'?')), 
--    plugin          = tostring(pluginnum),      -- TODO: set plugin number
    room            = tostring(tonumber (room or 0)),   -- why it's a string, I have no idea
    subcategory_num = tonumber (d.subcategory_num) or 0,
    time_created    = os.time(), 
    ip              = ip or '',
    mac             = mac or '',
  }

  -- schedule device startup code
  
  local startup = i.startup or ''                       -- to avoid nil indexing of environment below
  local entry_point = code[startup] 
  
  if entry_point then 
    scheduler.device_start (entry_point, devNo)         -- schedule startup in device context
  end
  return setmetatable (
      {    -- create entry for the devices table
        category_num        = attributes.category_num,
        description         = attributes.name,
        device_num_parent   = attributes.id_parent,
        device_type         = attributes.device_type, 
        embedded            = false,                  -- if embedded, it doesn't have its own room
        hidden              = hidden or false,        -- if hidden, it's not shown on the dashboard
        id                  = attributes.altid,
        invisible           = invisible or false,     -- if invisible, it's 'for internal use only'
        ip                  = attributes.ip,
        mac                 = attributes.mac,
        pass                = '',
        room_num            = tonumber (attributes.room),
        subcategory_num     = tonumber (attributes.subcategory_num),
--      udn                 = "uuid:4d494342-5342-5645-0003-000002b03069",     -- we don't do UDNs
        user                = '',    
      }, 
    {
--TODO:    __metatable = "access denied",
    __index = 
      {     -- and things which are NOT visible in the real version
        category_name       = cat_name_by_dev [device_type],
        handle_children     = d.handle_children == "1",
        serviceList         = d.service_list,
        startup             = i.startup,
        --
        attributes          = attributes,
        environment         = code,
        services            = services,
        watchers            = watchers,
        io                  = {
            incoming            = incoming_handler, 
         },             -- area for io related data (see luup.io)
        -- note that all the following methods should be called with device:function() syntax...
        action_callback     = function (self, f) missing_action = f or self end,
        attr_get            = attr_get,
        attr_set            = attr_set,
        call_action         = call_action,
        is_ready            = is_ready,
        supports_service    = supports_service,
        variable_set        = variable_set, 
        variable_get        = variable_get,
        version_get         = function () return version end,
        -- for debug only
        service_data        = service_data,
      }
    } )
end

-- export variables and methods

return {
  -- variables
  dataversion           = dataversion,
  userdata_dataversion  = userdata_dataversion,
  service_data          = service_data,
  static_data           = static_data,
  version               = banner,           -- this is the module software version
  
  -- methods
  create                    = create,
  variable_watch            = variable_watch,
  new_dataversion           = new_dataversion,
  new_userdata_dataversion  = new_userdata_dataversion,
}



------

