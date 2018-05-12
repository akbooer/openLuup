local ABOUT = {
  NAME          = "openLuup.devices",
  VERSION       = "2018.05.01",
  DESCRIPTION   = "low-level device/service/variable objects",
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
-- openLuup.devices
--

-- 2016.03.01  added notes to action jobs
-- 2016.04.15  added per-device variable numbering (thanks @explorer)
-- 2016.04.29  added device status
-- 2016.07.19  improve call_action error handling
-- 2016.11.19  added callback name to watch callback structure

-- 2018.01.30  changed variable numbering to start at 0 (for compatibility with ModifyUserData)
-- 2018.01.31  add delete_vars() to device (for ModifyUserData to replace all state variables)
-- 2018.04.05  move get/set status to chdev (more a luup thing than a devices thing)
-- 2018.04.25  inspired to start work on 'VariableWithHistory'
-- see: http://forum.micasaverde.com/index.php/topic,16166.0.html
-- and: http://blog.abodit.com/2013/02/variablewithhistory-making-persistence-invisible-making-history-visible/
-- 2018.05.01  use millisecond resolution time for variable history (luup.variable_get truncates this)


local scheduler = require "openLuup.scheduler"        -- for watch callbacks and actions

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

local device_list  = {}         -- internal list of devices

local sys_watchers = {}         -- list of system-wide (ie. non-device-specific) watchers

-----
--
-- VARIABLE object 
-- 
-- Note that there is no "get" function, object variables can be read directly (but setting should use the method)
--

local variable = {}             -- variable CLASS

function variable.new (name, serviceId, devNo)    -- factory for new variables
  local device = device_list[devNo] or {}
  local vars = device.variables or {}
  local varID = #vars                             -- 2018.01.31
  new_userdata_dataversion ()                     -- say structure has changed
  vars[varID + 1] = {                             -- 2018.01.31
      -- variables
      dev       = devNo,
      id        = varID,                          -- unique ID
      name      = name,                           -- name (unique within service)
      srv       = serviceId,
      silent    = nil,                            -- set to true to mute logging
      watchers  = {},                             -- callback hooks
      -- methods
      set       = variable.set,
    }
  return vars[#vars]
end
  
function variable:set (value)
  local t = scheduler.timenow()                   -- time to millisecond resolution
  value = tostring(value or '')                   -- all device variables are strings
  --
  -- 2018.04.25 'VariableWithHistory'
  -- note that retention policies are not implemented here, so the history just grows
  local history = self.history 
  if history and value ~= self.value then         -- only record CHANGES in value
    local v = tonumber(value)                     -- only numeric values at the moment
    if v then
      local n = #history
      history[n+1] = t
      history[n+2] = v
    end
  end
  --
  local n = dataversion.value + 1                 -- say value has changed
  dataversion.value = n
  
  self.old      = self.value or "EMPTY"
  self.value    = value                           -- set new value 
  self.time     = t                               -- save time of change
  self.version  = n                               -- save version number
  return self
end


-----
--
-- SERVICE object 
--
-- Services contain variables and actions
--

local service = {}              -- service CLASS
  
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

local function variable_watch (dev, fct, serviceId, variable, name, silent)  
  local callback = {
    callback = fct, 
    devNo = scheduler.current_device (),    -- devNo is current device context
    name = name,
    silent = silent,                            -- avoid logging some system callbacks (eg. scene watchers)
  }
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
    else
      -- no service id
    end
  end
end


-----
--
-- DEVICE object 
--
--
-- Devices support services with variables.  
-- They also contain attributes and have a unique device_number.
-- Callback handlers can also be set for variable changes and missing actions

-- new device
local function new (devNo)  
  
  local attributes  = {}      -- device attributes
  local services    = {}      -- all service variables and actions here
  local version               -- set device version (used to flag changes)
  local missing_action        -- an action callback to catch missing actions
  local watchers    = {}      -- list of watchers for any service or variable
--  local status      = -1      -- device status
  
--  local function status_get (self)            -- 2016.04.29
--    return status
--  end
  
--  local function status_set (self, value)     -- 2016.04.29
--    if status ~= value then
----      new_dataversion ()
--      new_userdata_dataversion ()
--      status = value
--    end
--  end
  
  -- function delete_vars
  -- parameter: device 
  -- deletes all variables in all services (but retains actions)
  local function delete_vars (dev)
    local v = dev.variables
    for i in ipairs(v) do v[i] = nil end    -- clear each element, don't replace whole table
    
    for _,svc in pairs(dev.services) do
      local v = svc.variables
      for name in pairs (v) do    -- remove all the old service variables!
        v[name] = nil             -- clear each element, don't replace whole table
      end
    end
    
    new_userdata_dataversion ()
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
   
  -- function: action_set ()
  -- parameters: service (string) name (string), action_tags (table)
  -- returns: nothing
  local function action_set (self, serviceId, name, action_tags)
    -- action_tags is a structure with (possibly) run/job/timeout/incoming functions
    -- it also has 'name' and 'serviceId' fields
    -- and may have 'returns' defining action variables to return
      local srv = services[serviceId] or service.new(serviceId, devNo)   -- create serviceId if missing
      services[serviceId] = srv
      srv.actions[name] = action_tags
  end
  
  -- function: call_action
  -- parameters: service (string), action (string), arguments (table), device (number)
  -- returns: error (number), error_msg (string), job (number), arguments (table)
  --
  -- Invokes the service + action, passing in arguments (table of string->string pairs) to the device. 
  -- If the invocation could not be made, only error will be returned with a value of -1. 
  -- error is 0 if the action was successful. 
  -- arguments is a table of string->string pairs with the return arguments from the action. 
  -- If the action is handled asynchronously by a job, 
  -- then the job number will be returned as a positive integer.
  --
  -- NOTE: that the target device may be different from the device which handles the action
  --       if the <handleChildren> tag has been set to 1 in the parent's device file.

  local function call_action (self, serviceId, action, arguments, target_device)
    -- 'act' is an object with (possibly) run / job / timeout / incoming methods
    -- note that the loader has also added 'name' and 'serviceId' fields to the action object
    
    local act, svc
    svc = services[serviceId]
    if svc then act = svc.actions [action] end
    
    if not act and missing_action then              -- dynamically link to the supplied action handler
      act = missing_action (serviceId, action)      -- might still return nil action
    end
    
    if not act then 
      if not svc then 
        return 401, "Invalid Service",   0, {} 
      else
        return 501, "No implementation", 0, {} 
      end
    end

    local e,m,j,a = scheduler.run_job (act, arguments, devNo, target_device or devNo)
    if j and scheduler.job_list[j] then
      scheduler.job_list[j].notes = table.concat ({"Action", serviceId or '?', action or '?'}, ' ') -- 2016.03.01
    end
    return e,m,j,a
  end
 
  -- function attr_set ()
  -- parameters: attribute (string), value(string) OR table of {name = value} pairs
  -- returns: nothing
  --
  -- Sets the top level attribute(s) for the device to value(s). 
  -- TODO: at the moment, attr_set does _not_ update the dataversion - is this right?
  local function attr_set (self, attribute, value)
    if type (attribute) ~= "table" then attribute = {[attribute] = value} end
    for name, value in pairs (attribute) do 
      if not attributes[name] then new_userdata_dataversion() end   -- structure has changed
--      attributes[name] = tostring(value)
      new_dataversion ()                              -- say value has changed
      attributes[name] = value
    end
  end
    
  -- function: attr_get
  -- parameters: attribute (string), device (string or number)
  -- returns: the value
  --
  -- Gets the top level attribute for the device. 
  local function attr_get (self, attribute)
    return attributes[attribute]
  end
 
  -- new () starts here
  
  new_dataversion ()                                      -- say something's changed
  new_userdata_dataversion ()                             -- say it's structure, not just values
  version = dataversion.value                             -- set the device's version number
   
  device_list[devNo] =  {
      -- data structures
      
      attributes          = attributes,
      services            = services,
      watchers            = watchers,
      variables           = {},            -- 2016.04.15  complete list of device variables by ID
      
      -- note that these methods should be called with device:function() syntax...
      call_action         = call_action,
      action_set          = action_set,
      action_callback     = function (self, f) missing_action = f or self end,
      
      attr_get            = attr_get,
      attr_set            = attr_set,
      
--      status_get          = status_get,
--      status_set          = status_set,
      
      variable_set        = variable_set, 
      variable_get        = variable_get,
      version_get         = function () return version end,
      
      delete_vars         = delete_vars,    -- 2018.01.31
    }
    
  return device_list[devNo]
  
end


-- export variables and methods

return {
  ABOUT = ABOUT,
  
  -- variables
  dataversion           = dataversion,
  device_list           = device_list,
  sys_watchers          = sys_watchers,         -- only for use by console routine
  userdata_dataversion  = userdata_dataversion,
  
  -- methods
  new                       = new,
  variable_watch            = variable_watch,
  new_dataversion           = new_dataversion,
  new_userdata_dataversion  = new_userdata_dataversion,
}



------

