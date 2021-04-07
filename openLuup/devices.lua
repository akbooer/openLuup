local ABOUT = {
  NAME          = "openLuup.devices",
  VERSION       = "2021.04.07",
  DESCRIPTION   = "low-level device/service/variable objects",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2021 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-2021 AK Booer

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
-- 2018.05.25  use circular buffer for history cache, add history meta-functions, history watcher
-- 2018.06.01  add shortSid to variables, for historian
-- 2018.06.22  make history cache default for all variables
-- 2018.06.25  add shortSid to service object

-- 2019.04.18  do not create variable history for Zwave serviceId or epoch values
-- 2019.04.24  changed job.notes to job.type in call_action()
-- 2019.04.25  add touch() function to make device appear in status request, etc.
-- 2019.08.12  add delete_single_var() to allow console to surgically remove one variable
-- 2019.12.10  add sl_ prefix special case for variable history caching
--             see: https://community.getvera.com/t/reactor-on-altui-openluup-variable-updates-condition/211412/16
-- 2019.12.11  correct nil parameter handling in variable_watch() - thanks @rigpapa

-- 2020.06.20  fix nil attribute name in attr_set()

-- 2021.01.04  add devNo to device structure - required for missing service/variable creation (for watches)
--             allow watches to be set on undefined services/variables (thanks @rigpapa)
-- 2021.03.09  add pathname to each variable, and publish instant updates over MQTT
-- 2021.03.10  fix benign error in delete_single_var()
-- 2021.03.11  add publish_variable_updates() method to toggle flag
-- 2021.04.07  correct MQTT published variable value


local scheduler = require "openLuup.scheduler"        -- for watch callbacks and actions
local publish   = require "openLuup.mqtt" .publish    -- for instant status

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

local history_watchers = {}     -- for data historian watchers

local CacheSize = 1000          -- default value over-ridden by initalisation configuration

local PublishVariableUpdates = false

local function publish_variable_updates(flag)
  PublishVariableUpdates = flag
end

-----
--
-- VARIABLE object 
-- 
-- Note that there is no "get" function (except for metahistory methods), 
-- object variables can be read directly (but setting MUST use the method)
--

-- metahistory methods are shared between all variable instances
-- and manage data retrieval from the in-memory history cache
-- the order of returned data is VALUE, TIME to align with luup.variable_get() syntax
local metahistory = {}
  
  -- enable cache (which might already be enabled)
  function metahistory:enableCache ()
    self.history = self.history or {}    -- here's the cache!
  end
  
  -- disable cache (which might already be enabled)
  function metahistory:disableCache ()
    self.history = nil                  -- remove cache
    self.hipoint = nil                  -- and the pointer
    self.hicache = nil                  -- and local cache size
  end
  
  -- get the latest value,time pair (with millisecond precision)
  function metahistory: newest ()
    local history = self.history
    if history and #history > 0 then
      local n = 2 * self.hipoint
      return history[n], history[n-1]
    end
  end
  
  -- get the oldest value,time pair (with millisecond precision)
  function metahistory: oldest ()
    local history = self.history
    if history and #history > 0 then
      local n = 2 * self.hipoint
      return history[n+2] or history[2], history[n+1] or history[1]   -- cache may not yet be full
    end
  end
  
  -- get the value at or before given time t, and actual time that value was set
  function metahistory: at (t)
  
    -- return location of largest time element in history <= t using bisection, or nil if none
    local function locate (history, hipoint, t)
      local function bisect (a,b)
        if a >= b then return a end
        local c = math.ceil ((a+b)/2)
        if t < history[(2*(c+hipoint-1) % #history)+1]     -- unwrap circular buffer
          then return bisect (a,c-1)
          else return bisect (c,b)
        end
      end 
      local n = #history / 2
      local p = 2 * hipoint + 1
      if n == 0 or t < (history[p] or history[1])   -- oldest point is at 2*hipoint+1 or 1
        then return nil 
        else return bisect (1, n) 
      end
    end
    
    -- at()
    local history = self.history
    if t and history and #history > 0 then
      local i = locate (history, self.hipoint, t)
      if i then
        local j = i + i
        return history[j], history[j-1]   -- return value and ACTUAL sample time
      end
    end
  end

  -- fetch()  returns V and t arrays
  function metahistory: fetch (from, to)
    local now = os.time()
    local v, t = {}, {} 
    local n = 0
    local Vold, Told = self: oldest()
    local hist, ptr = self.history or {}, self.hipoint or 0
    
    from = from or now - 24*60*60                     -- default to 24 hours ago 
    to   = to or now                                  -- default to now
    from = math.max (from, Told or 0)                 -- can't go before earliest
    to   = math.min (to, now)                         -- can't go beyond now
    
    local function scan (a,b)
      for i = a,b, 2 do
        local T,V = hist[i], hist[i+1]
        if T >= from then               -- TODO: could improve this linear search with bisection
          if T > to then break end
          n = n + 1
          if n == 1 then
            if T > from then            -- insert first point at start time...
              t[n], v[n] = from, Vold   --    ... using previous value
              n = 2
            end
          end
          t[n], v[n] = T, V
        end
        Vold = V
      end
    end
    
    scan (2*ptr +1, #hist)
    scan (1, 2*ptr)
    
    if (n > 0) and (to > t[#t]) then                  -- insert final point and end time
      t[#t+1], v[#v+1] = to, Vold
    end

    return v, t
  end
  
-- old rules were:   
--    dates_and_times = "*.*.{*Date*,*Time*,*Last*,Poll*,Configured,CommFailure}"
--    zwave_devices = "*.ZWaveDevice1.*"
--
--   most of these now caught by the epoch filter in variable_set()
local ignoreServiceHistory = {    -- these are the shortServiceIds for which we don't want history
  ZWaveDevice1  = true,
  ZWaveNetwork1 = true,
}

local ignoreVariableHistory = {   -- ditto variable names (regardless of serviceId)
  Configured  = true,
  CommFailure = true,
}

local variable = {}             -- variable CLASS

function variable.new (name, serviceId, devNo)    -- factory for new variables
  local device = device_list[devNo] or {}
  local vars = device.variables or {}
  local varID = #vars                             -- 2018.01.31
  
  local history                                   -- 2019.04.18
  local shortSid  = serviceId: match "[^:]+$" or serviceId
  if not (ignoreServiceHistory[shortSid] or ignoreVariableHistory[name]) then history = {} end
  
  new_userdata_dataversion ()                     -- say structure has changed

  local pathname = table.concat ({devNo, shortSid, name}, '/')   -- 2021.03.09
  
  vars[varID + 1] =                               -- 2018.01.31
  setmetatable (                                  -- 2018.05.25 add history methods 
    {
      -- variables
      dev       = devNo,
      id        = varID,                          -- unique ID
      name      = name,                           -- name (unique within service)
      pathname  = pathname,                       -- dev.srv.var (for Historian and MQTT)
      srv       = serviceId,
      shortSid  = shortSid,
      silent    = nil,                            -- set to true to mute logging
      mqtt      = true,                           -- set to false to disable MQTT updates
      watchers  = {},                             -- callback hooks
      -- history
      history   = history,                        -- set to nil to disable history
      hipoint   = 0,                              -- circular buffer pointer managed by variable_set()
      hicache   = nil,                            -- local cache size, overriding global CacheSize
      -- methods
      set       = variable.set,
    }, 
      {__index = metahistory} )
  return vars[#vars]
end
 
 
function variable:set (value)
  local t = scheduler.timenow()                   -- time to millisecond resolution
  value = tostring(value or '')                   -- all device variables are strings
  
  -- 2021.03.09, 2021.04.07 instant status updates over MQTT
  local changed = value ~= self.value
  if changed and PublishVariableUpdates and self.mqtt then
    publish ("openLuup/update/" .. self.pathname, value)
  end
  
  -- 2018.04.25 'VariableWithHistory'
  -- history is implemented as a circular buffer, limited to CacheSize time/value pairs
  local history = self.history 
  if history then
    local v = tonumber(value)                     -- only numeric values
    if v then
      local epoch = v > 1234567890                -- cheap way to identify recent epochs? (and other big numbers!)
      if (changed                                 -- only cache changes
      or  (self.name: sub(1,3) == "sl_"))         -- 2019.12.10 sl_ prefix special case
      and not epoch then
        local hipoint = (self.hipoint or 0) % (self.hicache or CacheSize) + 1
        local n = hipoint + hipoint
        self.hipoint = hipoint
        history[n-1] = t
        history[n]   = v
      end
      -- it's up to the watcher(s) to decide whether to record repeated values or only changes
      -- (this should help to mitigate nil values in Whisper historian archives)
      scheduler.watch_callback {var = self, watchers = history_watchers} -- for write-thru disc cache
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
    -- constants
    shortSid      = serviceId: match "[^:]+$" or serviceId,
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
-- now: https://community.getvera.com/t/openluup-and-luup-variable-watch/189487
-- thanks @vosmont for clarification of undocumented feature
--

local function variable_watch (dev, fct, serviceId, variable, name, silent)  
  local callback = {
    callback = fct, 
    devNo = scheduler.current_device (),    -- devNo is current device context
    name = name,
    hash = table.concat ({tostring(fct), tostring(dev) or '*', serviceId or '*', variable or '*'}, '.'),   -- 2015.05.15
    silent = silent,                            -- avoid logging some system callbacks (eg. scene watchers)
  }
  if dev then
    -- a specfic device
    if serviceId then
      local srv = dev.services[serviceId]
      if not srv then                               -- 2021.01.04  create missing service (so watch is actually set)
        srv = service.new (serviceId, dev.devNo)
        dev.services[serviceId] = srv
      end
      if variable then 
        local var = srv.variables[variable] 
        if not var then                             -- 2021.01.04  create missing variable (so watch is actually set)
          var = srv: variable_set (variable)
          srv.variables[variable]  = var
        end
        var.watchers[#var.watchers+1] = callback    -- set the watch on the variable
      else                                      
        srv.watchers[#srv.watchers+1] = callback    -- set the watch on the service
      end
    else
      dev.watchers[#dev.watchers+1] = callback      -- set the watch on the device
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
      if variable == "history" then
        callback.name = "data historian"
        callback.silent = true
        history_watchers[1] = callback    -- only allow one of these
      end
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
  
  -- function delete_vars
  -- parameter: device 
  -- deletes all variables in all services (but retains actions)
  -- needed for AltUI modify_user_data() call used to remove a single variable (and replace all the others)
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
  
  -- function delete_var
  -- removes a single var
  -- this is harder than it seems, 
  -- it's indexed in two places, and existing vars have to be renumbered
  local function delete_single_var (dev, id)
    -- IDs start at zero
    local v = dev.variables
    local var = v[id+1]                         -- this is the one to go
    local svc = dev.services[var.srv]           -- this is its service
    table.remove (v, id+1)                      -- remove from device variables array 
    for i, x in ipairs (v) do x.id = i-1 end    -- renumber the whole array
    svc.variables[var.name] = nil               -- remove from service variables (fixed missing .variables 2021.03.10)
    dev: touch()                                -- say we changed something
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
        scheduler.watch_callback {var = var, watchers = dev.watchers}     -- 2020.12.27  changed to dev.watcher (for style)
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
       -- 2016.03.01, then 2019.04.24 changed job.notes to job.type
      scheduler.job_list[j].type = table.concat ({"action: ", serviceId or '?', action or '?'}, ' ')
    end
    return e,m,j,a
  end
 
  -- function attr_set ()
  -- parameters: attribute (string), value(string) OR table of {name = value} pairs
  -- returns: nothing
  --
  -- Sets the top level attribute(s) for the device to value(s). 
  local function attr_set (self, attribute, value)
    if type (attribute) ~= "table" then attribute = {[attribute or '?'] = value} end    -- 2020.06.20
    for name, value in pairs (attribute) do 
      if not attributes[name] then new_userdata_dataversion() end   -- structure has changed
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
 
  -- touch: update the version number
  local function touch ()
    new_dataversion ()                      -- update system data version...
    version = dataversion.value             -- ...and now update the device version 
  end
  
  -- new () starts here
  
  new_dataversion ()                                      -- say something's changed
  new_userdata_dataversion ()                             -- say it's structure, not just values
  version = dataversion.value                             -- set the device's version number
   
  device_list[devNo] =  {
      -- data structures
      
      devNo               = devNo,         -- 2021.01.04  required for missing service/variable creation
      
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
      
      variable_set        = variable_set, 
      variable_get        = variable_get,
      version_get         = function () return version end,
      
      delete_single_var   = delete_single_var,  -- 2019.08.12
      delete_vars         = delete_vars,        -- 2018.01.31
      touch               = touch,              -- 2019.04.25
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
  publish_variable_updates  = publish_variable_updates,

  set_cache_size  = function(s) CacheSize = s end,
  
}



------
