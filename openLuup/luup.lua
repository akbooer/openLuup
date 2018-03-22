local ABOUT = {
  NAME          = "openLuup.luup",
  VERSION       = "2018.03.22",
  DESCRIPTION   = "emulation of luup.xxx(...) calls",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
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
-- openLuup - an emulation of Luup calls to allow some Vera plugins to run on a non-Vera machine
--  

-- 2016.05.10  update userdata_dataversion when top-level attribute set
-- 2016.05.15  change set_failure logic per discussion here: http://forum.micasaverde.com/index.php/topic,37672.0.html
-- 2016.05.17  set_failure sets urn:micasaverde-com:serviceId:HaDevice1 / CommFailure variable in device
-- 2016.05.26  add device number to CommFailure variables in set_failure (thanks @vosmont)
-- 2016.06.06  add special handling of top-level "openLuup" attribute
-- 2016.07.18  improve call_action error messages
-- 2016.07.20  truncate very long values in variable_set log output and remove control characters
-- 2016.11.02  add job type to timer calls
-- 2016.11.18  add call_delay function name as timer type
-- 2016.12.06  change attr_get/set for structured openLuup attributes

-- 2017.10.12  make luup.sunrise/sunset() return integer (thanks @a-lurker)
-- 2017.10.15  check parameter types for callback functions (thanks @a-lurker)
-- 2017.04.16  add missing luup.ir.pronto_to_gc100() (thanks @a-lurker)
-- 2017.04.18  check parameter types in chdev calls (thanks @a-lurker)
-- 2017.04.21  allow both integer AND boolean parameter to set failure (thanks @a-lurker)
-- 2017.05.01  user-defined parameter job settings
-- 2017.05.23  allow string or number parameter on call_delay()
-- 2017.06.08  fix data parameter error in call_timer (introduced in type-checking)
-- 2017.06.19  correct first word of GC100 code (thanks again @a-lurker)

-- 2018.02.10  ensure valid error in luup.call_action() even if missing parameters
-- 2018.03.08  extend register_handler to work with email (local SMTP server)
-- 2018.03.22  use renamed io.luupio module, use logs.register()


local logs          = require "openLuup.logs"

local server        = require "openLuup.server"
local scheduler     = require "openLuup.scheduler"
local devutil       = require "openLuup.devices"
local Device_0      = require "openLuup.gateway"
local timers        = require "openLuup.timers"
local userdata      = require "openLuup.userdata"
local loader        = require "openLuup.loader"   -- simply to access shared environment
local smtp          = require "openLuup.smtp"     -- for register_handler to work with email

-- luup sub-modules
local chdev         = require "openLuup.chdev"
local io            = require "openLuup.io"    


--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

local _log_altui_variable  = logs.altui_variable

-----

-- devices contains all the devices in the system as a table indexed by the device number 
-- not necessarily contiguous!

local devices = {}

-- rooms contains all the rooms as a table of strings indexed by the room number 
-- not necessarily contiguous!

local rooms = {}

-- scenes contains all the scenes in the system as a table indexed by the scene number. 
-- The members are: room_num (number), description(string), hidden(boolean)

local scenes = {}

-- remotes contains all the remotes in the system as a table indexed by the remote id. 
-- The members are: remote_file (string), room_num (number), description(string)

local remotes = {}

-----
--
-- parameter checking routine
--
-- a,b,c = parameters ({list of types}, parameters)
-- where types can include the usual, but also "number_or_string"
-- throws an error pointing to the caller's caller (ie. where the wrong parameter actually is)
-- eg.
--     a,b,c = parameters ({"string", "number", "table"}, ...)
--
local parameters
  do
    local class = {
        number_or_string = {string = 1, number = 1},
        table_or_string  = {string = 1, table  = 1},
        string_or_number = {string = 1, number = 1},
        string_or_table  = {string = 1, table  = 1},
      }
    local message = "parameter #%d should be type %s but is %s"

    parameters = function (syntax, ...)
      for i,p in ipairs {...} do
        local t = type(p)
        local s = syntax[i] or t
        if not (class [s] or {[s] = 1}) [t] then
          error (message: format (i, s, t), 3)
        end
      end
      return ...  -- note that this even works for embedded nil parameters
    end
  end


-----
--
-- GLOBAL functions: Luup API
--
 
--[[
startup": {

    "tasks": [
  {
    "id": 12,
    "status": 2,
    "type": "Vera Connect WWN",
    "comments": "Please go to 'Authorize' tab and authorize VeraConnect!"
  },

  {
      "id": 13,
      "status": 2,
      "type": "Squeezebox: ",
      "comments": "Setup incomplete.  IP address and port required."
  }
]

},

--]]
-- function: task
-- parameters: message (string), status (number), description (string), handle (number)
-- return: handle (number)
--
-- When the Luup engine is starting status messages are displayed for the various modules as they're initialized. 
-- Normally each device, including Luup devices, automatically log their status and the user is shown an error 
-- if the device doesn't start, such as if the 'startup' function returns an error.
--
-- If you have other startup sequences which you want the user to see to know that startup hasn't finished yet, 
-- call this function passing in a handle of -1 for the first call. 
-- The status should be: 1=Busy, 2=Error, 4=Successful. Message is the current state,
-- such as 'downloading', and description describes the module, like 'Smartphone UI'. 
-- After the first call, store the handle and pass it on future calls to update the status rather than add a new one.
local task_handle = 0
local function task (message, status, description, handle)
  if handle == -1 then 
    task_handle = task_handle + 1
    handle = task_handle
  end
  _log (table.concat {"status=", status or '?', " ", description or '?', ' : ', message or ''}, "luup.task")
  return handle
end

--------------
--
--  DEVICE related API
--

-- log message for missing dev / srv/ var
local function log_missing_dev_srv_name (dev, srv, name, tag)
    local fmt = "No such device/serviceId/name %s.%s.%s"
    local msg = fmt: format (tostring(dev or '?'),srv or '?', name or '?')
    _log (msg, tag or ABOUT.NAME)
end

-- function: is_ready
-- parameters: device (string or number)
-- returns: ready (boolean)
--
-- Checks whether a device has successfully completed its startup sequence. If so, is_ready returns true. 
-- If your device shouldn't process incoming data until the startup sequence is finished, 
-- you may want to add a condition to the <incoming> block that only processes data if is_ready(lul_device) is true.
local function is_ready (...)
  local device = parameters ({"number_or_string"}, ...)
  local dev = devices[device]
  return dev and dev:is_ready() 
end

-- function: variable_set
-- parameters: service (string), variable (string), value (string), device (string or number), [startup (bool)]
-- returns: nothing 
local function variable_set (service, name, value, device, startup)
    -- shorten long variable strings, removing control characters
    local function truncate (text)
      text = (text or ''): gsub ("%c", ' ')
      if #text > 120 then text = text: sub (1,115) .. "..." end    -- truncate long variable values
      return text
    end
  device = device or scheduler.current_device()    -- undocumented luup feature!
  local dev = devices[device]
  if not dev then 
    log_missing_dev_srv_name (device, service, name, "luup.variable_set")
    return
  end
  service = tostring (service)
  name = tostring(name)
  value = tostring (value)
  local var = dev:variable_set (service, name, value, not startup) 
  if var then
    local old = var.old  or "MISSING"
    local info = "%s.%s.%s was: %s now: %s #hooks:%d" 
    local msg = info: format (device,service, name, truncate(old), truncate(value), #var.watchers)
    _log (msg, "luup.variable_set")
    _log_altui_variable (var)              -- log for altUI to see
  end 
end

-- function: variable_get
-- parameters: service (string), variable (string), device (string or number)
-- returns: value (string) and Unix time stamp (number) of when the variable last changed
local function variable_get (service, name, device)
  device = device or scheduler.current_device()    -- undocumented luup feature!
  local dev = devices[device]
  if not dev then 
    log_missing_dev_srv_name (device, service, name, "luup.variable_get")
    return
  end
  local var = dev:variable_get (service, name) or {}
  return var.value, var.time
end


-- function: device_supports_service
-- parameters: service ID (string), device (string or number)
-- returns: true if the device supports the service, false otherwise
--
-- A device supports a service if there is at least a command or state variable
-- defined for that device using that service. 
-- BUT...
-- Setting UPnP variables is unrestricted and free form, 
-- and the engine doesn't really know if a device actually uses it or does anything with it. 
local function device_supports_service (...)
  local serviceId, device = parameters ({"string", "number_or_string"}, ...)
  local support
  local dev = devices[device]
  if dev then
    support = dev:supports_service (serviceId)
  else
    log_missing_dev_srv_name (device, serviceId, '', "luup.device_supports_service")
  end
  return support
end

-- function: devices_by_service   -- not well defined!!
local function devices_by_service ()
  error ("devices_by_service not implemented", 2)
end

-- function attr_set ()
-- parameters: attribute (string), value(string), device (string or number)
-- returns: none
--
-- Sets the top level attribute for the device to value. Examples of attributes are 'mac', 'name', 'id', etc. 
-- Like attr_get, if the device is zero OR MISSING it sets the top-level user_data json tag.
local function attr_set (attribute, value, device)
  local special_name = {  
    -- these top-level attributes ALSO live in luup.XXX 
    -- but are not necessarily strings, and may have different name
    City_description = {name = "city"}, 
    PK_AccessPoint   = {name = "pk_accesspoint", number = true},
    longitude        = {number = true},
    latitude         = {number = true},
    timezone         = {},
  }
  device = device or 0
  value = tostring (value  or '')
  attribute = tostring (attribute or '')
  if device == 0 then
    if attribute: match "^openLuup%." then                    -- 2016.12.06 
      local x = userdata.attributes
      for y,z in attribute: gmatch "([^%.]+)(%.?)" do
        if (z == '.') then
          x[y] = x[y] or {}
          x = x[y]
        else
          x[y] = value
        end
      end
    else
      userdata.attributes [attribute] = value
      local special = special_name[attribute] 
      if special then 
        if special.number then value = tonumber(value) end
        luup[special.name or attribute] = value or ''
      end 
    end
    devutil.new_userdata_dataversion ()     -- 2016.05.10  update userdata_dataversion when top-level attribute set
  else
    local dev = devices[device]
    if dev then
      dev: attr_set (attribute, value)
      _log (("%s.%s = %s"): format (tostring (device), attribute, value), "luup.attr_set")
    else
      log_missing_dev_srv_name (device, "ATTRIBUTE", attribute, "luup.attr_set")
    end
  end
end

-- function: attr_get
-- parameters: attribute (string), device (string or number)
-- returns: string or none (note: none means nothing at all. It does not mean 'nil')
--
-- Gets the top level attribute for the device. Examples of attributes are 'mac', 'name', 'id', etc. 
-- If the attribute doesn't exist, it returns nothing. If the number 0 is passed in for device, OR MISSING,
-- it gets the top level attribute from the master userdata, like firmware_version.
local function attr_get (attribute, device)
  local attr
  device = device or 0
  attribute = tostring (attribute or '')
  if device == 0 then
    if attribute: match "^openLuup%." then                    -- 2016.12.06 
      local x = userdata.attributes
      for y,z in attribute: gmatch "([^%.]+)(%.?)" do
        if (z == '.') then
          x = x[y] or {}
        else
          attr = x[y]
        end
      end
    else
      attr = userdata.attributes [attribute]
    end
  else
    local dev = devices[device]
    if dev then
      attr = dev: attr_get (attribute)
    else
      log_missing_dev_srv_name (device, "ATTRIBUTE", attribute, "luup.attr_get")
    end
  end
  return attr
end


-- function: ip_set
-- parameters: value (string), device (string or number)
-- returns: none
--
-- Sets the IP address for a device. 
-- This is better than setting the "ip" attribute using attr_set 
-- because it updates internal values additionally, so a reload isn't required.
local function ip_set (...)
  local value, device = parameters ({"string", "number_or_string"}, ...)
  attr_set ("ip", value, device)
  local dev = devices[device]
  if dev then
    dev.ip = value
  end
end

--function: mac_set
-- parameters: value (string), device (string or number)
-- returns: none
--
-- Sets the mac address for a device. 
-- This is better than setting the "mac" attribute using attr_set 
-- because it updates internal values additionally, so a reload isn't required. 
local function mac_set (...)
  local value, device = parameters ({"string", "number_or_string"}, ...)
  attr_set ("mac", value, device)
  local dev = devices[device]
  if dev then
    dev.mac = value
  end
end

 
-- function: set_failure
-- parameters: value (int), device (string or number)
-- 2017.04.21  but see also: http://forum.micasaverde.com/index.php/topic,27420.msg207850.html#msg207850
-- returns:
--
-- Luup maintains a 'failure' flag for every device to indicate if it is not functioning. 
-- You can set the flag to 1 if the device is failing, 0 if it's working, 
-- and 2 if the device is reachable but there's an authentication error. 
-- The lu_status URL will show for the device: <tooltip display="1" tag2="Lua Failure"/>
local function set_failure (status, device)
  local map = {[0] = -1, 2,2, [true]=2, [false] = -1}   -- apparently this mapping is used... ANOTHER MiOS inconsistency!
  _log ("status = " .. tostring(status), "luup.set_failure")
  local devNo = device or scheduler.current_device()
  local dev = devices[devNo]
  if dev then 
    dev:status_set (map[status or 0] or -1)  -- 2016.05.15
    local time = 0
    if status ~= 0 then time = os.time() end
    local HaSID = "urn:micasaverde-com:serviceId:HaDevice1"
    variable_set (HaSID, "CommFailure", status, devNo)     -- 2016.05.17 and 2015.05.26
    variable_set (HaSID, "CommFailureTime", time, devNo)
  end  
end

--
-- CALLBACKS
--

-- utility function to find the actual callback function given name and current context
local function entry_point (name, subsystem)
  local fct, env
  -- look in device environment, or startup, or globally
  local dev = devices[scheduler.current_device() or 0]
  env = (dev and dev.environment) or {}
  fct = env[name] or loader.shared_environment[name] or _G[name]   
  if not fct then
    local msg = "unknown global function name: " .. (name or '?')
    _log (msg, subsystem or "luup.callbacks")
  end
  return fct
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

local function call_action (service, action, arguments, device)
  local function find_handler (dev) -- (recursively)
    if dev and dev.device_num_parent ~= 0 then        -- action may be handled by parent
      local parent = devices[dev.device_num_parent] or {}
      if parent.handle_children then     -- action IS handled by parent
        _log ("action will be handled by parent: " .. dev.device_num_parent, "luup.call_action")
        dev = find_handler (parent)
      end
    end
    return dev
  end
  
  local devNo = tonumber (device) or 0
  service = service or '?'                -- 2018.02.10  ensure valid error even if missing parameters
  action = action or '?'
  _log (("%d.%s.%s "): format (devNo, service, action), "luup.call_action")
  
  local function missing_action ()
    log_missing_dev_srv_name (devNo, service, action, "luup.call_action")
    return 401, "Invalid service/action/device", 0, {}
  end
  
  -- action returns: error, message, jobNo, arrguments
  local e,m,j,a
  
  if devNo == 0 then
    e,m,j,a = Device_0: call_action (service, action, arguments) 
  else
    local target_device = devices[devNo]
    if target_device then
      local dev = find_handler (target_device)
      if dev then   
        e,m,j,a = dev: call_action (service, action, arguments, devNo) 
      else
        e,m,j,a = missing_action ()
      end
    else
      e,m,j,a = missing_action ()
    end
  end
  
  return e,m,j,a
 end

-- function: call_delay
-- parameters: function_name (string), seconds (number), data (string)
-- returns: result (number)
--
-- The function will be called in seconds seconds (the second parameter), with the data parameter.
-- The function returns 0 if successful. 
local function call_delay (...) 
  local global_function_name, seconds, data = parameters ({"string", "number_or_string"}, ...) 
  local fct = entry_point (global_function_name, "luup.call_delay")
  if fct then 
    -- don't bother to log call_delay, since it happens rather frequently
    return timers.call_delay(fct, seconds, data, global_function_name) 
  end
end

-- function: call_timer
-- parameters: function to call, type (number), time (string), days (string), data 
-- returns: result (number)
--
-- The function will be called in seconds seconds (the second parameter), with the data parameter.
-- Returns 0 if successful. 

local function call_timer (...)
  local global_function_name, timer_type, time, days, data, recurring = parameters ({"string", "number"}, ...)
  local ttype = {"interval", "day of week", "day of month", "absolute"}
  local fmt = "%s: time=%s, days={%s}"
  local msg = fmt: format (ttype[timer_type or ''] or '?', time or '', days or '')
  local fct = entry_point (global_function_name, "luup.call_timer")
  if fct then
    _log (msg, "luup.call_timer")
    local e,_,j = timers.call_timer(fct, timer_type, time, days, data, recurring)      -- 2016.03.01   
    if j and scheduler.job_list[j] then
      local text = "job#%d :timer '%s' (%s)"
      scheduler.job_list[j].type = text: format (j, global_function_name, msg)
    end
    return e
  end
end


-- strangely NOT part of the job module:
-- function: job_watch
-- parameters: function_name (string), device (string or number)
-- returns: nothing
--
-- Whenever a job is created, finished, or changes state then function_name will be called. 
-- If the device is nil or not specified, function_name will be called for all jobs, 
-- otherwise only for jobs that involve the specified device.

local function job_watch (...)
  local global_function_name, device = parameters ({"string"}, ...)
  local fct = entry_point (global_function_name "luup.job_watch")
  -- TODO: implement job_watch
  local _,_ ,_= global_function_name, device, fct    -- to suppress 'unused' warning
  error "luup.job_watch not implemented"
end


-- function: register_handler
-- parameters: function_name (string), request_name (string)
-- returns: nothing
--
-- When a certain URL is requested from a web browser or other HTTP get, 
-- function_name will be called and whatever string and content_type it returns will be returned.
--
-- The request is made with the URL: data_request?id=lr_[the registered name] on port 3480. 

local function register_handler (...)
  local global_function_name, request_name = parameters ({"string", "string"}, ...)
  local fct = entry_point (global_function_name, "luup.register_handler")
  if fct then
    -- fixed callback context - thanks @reneboer
    -- see: http://forum.micasaverde.com/index.php/topic,36207.msg269018.html#msg269018
    local msg = ("global_function_name=%s, request=%s"): format (global_function_name, request_name)
    _log (msg, "luup.register_handler")
    local email = request_name: match "@"       -- not an HTTP request, but an SMTP email address
    if email  then                              -- 2018.03.08
      smtp.register_handler (fct, request_name)
    else
      server.add_callback_handlers ({["lr_"..request_name] = fct}, scheduler.current_device())
    end
  end
end


-- function: variable_watch
-- parameters: function_name (string), service (string), variable (string or nil), device (string or number)
-- returns: nothing
--
-- Whenever the UPnP variable is changed for the specified device, 
-- which if a string is interpreted as a UDN [NOT IMPLEMENTED] 
-- and if a number as a device ID, function_name will be called
-- with parameters: device, service, variable, value_old, value_new.
-- If variable is nil, function_name will be called whenever any variable in the service is changed. 
-- If device is nil see: http://forum.micasaverde.com/index.php/topic,34567.0.html
-- thanks @vosmont for clarification of undocumented feature
local function variable_watch (...)
  local global_function_name, service, variable, device = parameters ({"string", "string"}, ...)
  local fct = entry_point (global_function_name, "luup.variable_watch")
  if not fct then
    _log ("callback function '" .. global_function_name .. "' not found", "luup.variable_watch")
    return
  end
  
  local dev = devices[device or '']
  -- NB: following call deals with missing device/service/variable,
  --     so CAN'T use the dev:variable_watch (...) syntax, since dev may not be defined!
  devutil.variable_watch (dev, fct, service, variable, global_function_name)
  
  local fmt = "callback=%s, watching=%s.%s.%s"
  local msg = fmt: format (global_function_name, (dev and device) or '*', service or '*', variable or '*')
  _log (msg, "luup.variable_watch")
end

--------------
--
--  INTERNET related API
--

-- MODULE inet
local inet = {
-- This reads the URL and returns 3 variables: 
--   the first is a numeric error code which is 0 if successful;
--   the second variable is a string containing the contents of the page;
--   the third variable is the HTTP status code.
-- If Timeout is specified, the function will timeout after that many seconds. 
-- The default value for Timeout is 5 seconds. 
-- If Username and Password are specified, they will be used for HTTP Basic Authentication.
--
  wget = function (URL, Timeout, Username, Password)
  return server.wget (URL, Timeout, Username, Password)
  end
}

 
-- function: create_device
-- parameters:
--      device_type, internal_id, description, upnp_file, upnp_impl, 
--      ip, mac, hidden, invisible, parent, room, pluginnum, statevariables,
--      pnpid, nochildsync, aeskey, reload, nodupid
-- returns: the device ID
--
-- This creates the device with the parameters given, and returns the device ID. 
--
local function create_device (...)
  local devNo, dev = chdev.create_device (...)      -- make it so
  devices[devNo] = dev                              -- save it in the device table
  return devNo
end

--
-- user ShutDown code
--

local function compile_and_run (lua, name)
  _log ("running " .. name)
  local startup_env = loader.shared_environment    -- shared with scenes
  local source = table.concat {"function ", name, " () ", lua, "end" }
  local code, error_msg = 
    loader.compile_lua (source, name, startup_env) -- load, compile, instantiate
  if not code then 
    _log (error_msg, name) 
  else
    local ok, err = scheduler.context_switch (nil, code[name])  -- no device context
    if not ok then _log ("ERROR: " .. err, name) end
    code[name] = nil      -- remove it from the name space
  end
end

-- function: reload
-- parameters: none
-- returns: none
--
local function reload (exit_status)
  
  if not exit_status then         -- we're going to reload
    exit_status = 42              -- special 'reload' exit status
    local fmt = "device %d '%s' requesting reload"
    local devNo = scheduler.current_device() or 0
    local name = (devices[devNo] or {}).description or "_system_"
    local txt = fmt:format (devNo, name)
    print (os.date "%c", txt)
    _log (txt)
  end
  
  _log ("saving user_data", "luup.reload") 
  local ok, msg = userdata.save (luup)
  assert (ok, msg or "error writing user_data")
  
  local shutdown = attr_get "ShutdownCode"
  if shutdown and (shutdown ~= '') then
    compile_and_run (shutdown, "_openLuup_user_Shutdown_") 
  end
  
  local fmt = "exiting with code %s - after %0.1f hours"
  _log (fmt:format (tostring (exit_status), (os.time() - timers.loadtime) / 60 / 60))
  os.exit (exit_status) 
end 


-- 2017.04.18   CHDEV module with parameter checking

local chdev_module = {
  
  start = function (...)
    parameters ({"number"}, ...)
    return chdev.chdev.start (...)
  end,
  
  append = function (device, ptr, altid, ...)
    parameters ({"number", "table", "number_or_string"}, device, ptr, altid)
    return chdev.chdev.append (device, ptr, tostring(altid), ...)   -- force string type for altid
  end,
  
  sync = function (...)
    parameters ({"number", "table"}, ...)
    return chdev.chdev.sync (...)
  end,
  
}


-- JOB module

local job = {  

-- parameters: job_number (number), device (string or number)
-- returns: job_status (number), notes (string)
  status = scheduler.status,
  
-- function: set
-- parameters: job (userdata), setting (string), value (string) OR table of {name = value} pairs
-- returns: nothing
--
-- This stores a setting(s) for a job.  
--
  set = function (...)       -- 2017.05.01  user-defined parameter job settings
    local job, setting, value = parameters ({"table", "table_or_string"}, ...)
    if type(setting) ~= "table" then 
      setting = {[setting] = value}
    end
    local set = job.settings
    if set then
      for name,val in pairs (setting) do
        set[name] = tostring(val)
      end
    end
  end,

-- function: setting aka. get !
-- parameters: job (userdata), setting (string)
-- returns: value (string)
--
-- This returns a setting for a job.
--
  setting = function (...)   -- 2017.05.01  user-defined parameter job settings
    local job, setting = parameters ({"table", "string"}, ...)
    return (job.settings or {}) [setting]
  end,
}

-- IR module
-- thanks to @a-lurker for this.
-- see: http://forum.micasaverde.com/index.php/topic,37268.0.html

local ir = {
  pronto_to_gc100 = function (pronto)
    -- replace the pronto code preamble with the GC100 preamble
    local rate
    rate, pronto = pronto: match "^%s*%x+%s+(%x+)%s+%x+%s+%x+%s+(.+)" -- extract preamble
    
    local PRONTO_PWM_HZ = 4145152  -- a constant measured in Hz and is the PWM frequencyof Philip's Pronto remotes
    rate = math.floor ( PRONTO_PWM_HZ / (tonumber(rate, 16) or 100) )
    
    local gc100 = {rate, 1, 1}
    for hexStr in pronto: gmatch "%x+" do
      gc100[#gc100+1] = tonumber(hexStr, 16)
    end
    
    return table.concat(gc100, ',')
  end
}

-----
--
-- export values and methods
--

local version = userdata.attributes.BuildVersion: match "*([^*]+)*"
local a,b,c = version: match "(%d+)%.(%d+)%.(%d+)"
local version_branch, version_major, version_minor = tonumber(a), tonumber(b), tonumber(c)

return {
  
    -- constants: really not expected to be changed dynamically
    
    hw_key              = "--hardware key--",
    event_server        = '',   
    event_server_backup = '',   
    ra_server           = '',
    ra_server_backup    = '',
    version             = version,
    version_branch      = version_branch,
    version_major       = version_major,
    version_minor       = version_minor,
    
    -- variables: these are problematical, since they may be changed by attr_set()  (qv.)
    
    city                = userdata.attributes.City_description,
    latitude            = tonumber (userdata.attributes.latitude),
    longitude           = tonumber (userdata.attributes.longitude),
    pk_accesspoint      = tonumber (userdata.attributes.PK_AccessPoint),  
    timezone            = userdata.attributes.timezone,

    -- functions
    
    attr_get            = attr_get,
    attr_set            = attr_set,
    call_action         = call_action,  
    call_delay          = call_delay,
    call_timer          = call_timer,
    chdev               = chdev_module,
    create_device       = create_device,    
    device_supports_service = device_supports_service,    
    devices_by_service  = devices_by_service,   
    inet                = inet,
    io                  = io.luupio,
    ip_set              = ip_set,
    is_night            = timers.is_night,  
    is_ready            = is_ready,
    job                 = job, 
    job_watch           = job_watch,
    log                 = function (msg, level) logs.send (msg, level, scheduler.current_device()) end,
    mac_set             = mac_set,
    register_handler    = register_handler, 
    reload              = reload,
--    require             = "what is this?"  --the redefined 'require' which deals with pluto.lzo ??
    set_failure         = set_failure,
    sleep               = scheduler.sleep,
    sunrise             = function () return math.floor(timers.sunrise ()) end, -- 2017.04.12
    sunset              = function () return math.floor(timers.sunset ()) end,
    task                = task,
    variable_get        = variable_get,
    variable_set        = variable_set,
    variable_watch      = variable_watch,

    -- tables 
    
    ir                  = ir,
    remotes             = remotes,
    rooms               = rooms,
    scenes              = scenes,
    devices             = devices, 
--    xj                  = {xml_node_text = function: 0xbc7b78} -- "what is this?",

}

-----------
