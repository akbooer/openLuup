local ABOUT = {
  NAME          = "openLuup.scheduler",
  VERSION       = "2019.01.28",
  DESCRIPTION   = "openLuup job scheduler",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2019 AK Booer

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
-- openLuup job scheduler
--
-- The scheduler handles creation / running / deletion of jobs which run asynchronously.  
-- It is a non-preemptive (cooperative) scheduler, 
-- so requires good behaviour in terms of client job run time.
-- Included in asynchronous processing are: delays / timers / watch callbacks / actions / jobs...
-- ...and incoming data for registered sockets
-- Callbacks which use named global functions are resolved using the appropriate device context
-- by lookup in the relevant module or the global table.
--

-- 2016.11.02  add startup_list handling, kill_job
-- 2016.11.18  add delay callback type (string) parameter, and silent mode

-- 2017.02.22  add extra (non-variable) returns to action calls (used by generic action handlers)
-- 2017.05.01  add user-defined parameter settings to a job, see luup.job.set[ting]
-- 2017.05.05  update current time in handling of delays

-- 2018.01.30  add logging info to job structure, move timenow() and sleep() here from timers
-- 2018.03.21  add default exit state to jobs
-- 2018.04.07  sandbox string and table system libraries
-- 2018.04.10  add get_socket_list to methods and timenow/name to the list elements
-- 2018.04.22  fix missing device 0 description in meta.__index:sandbox ()
-- 2018.04.25  update sandbox function (I believe that this one actually works properly)
-- 2018.06.06  add extra time parameter to variable_watch callbacks (for historian)
-- 2018.08.04  coerce error return to string in context_switch() (thanks @rigpapa)

-- 2019.01.28  add sandbox lookup table to metatable for external pretty-printing (console)


local logs      = require "openLuup.logs"
local socket    = require "socket"        -- socket library needed to access time in millisecond resolution

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

-- LOCAL aliases for timenow() and sleep() functions

local timenow = socket.gettime    -- system time in seconds, with millsecond resolution

-- Sleeps a certain number of milliseconds
-- NB: doesn't use CPU cycles, but does block the whole process...  not advised!!
local function sleep (milliseconds)
  socket.sleep ((tonumber (milliseconds) or 0)/1000)      -- wait a bit
end


-- LOCAL variables

local current_device = 0 -- 2015-11-14   moved the current device context luup.device to here

local exit_code     -- set to Unix process exit code to stop scheduler

local delay_list = {}                 -- list of delay callbacks
local watch_list = {}                 -- list of watch callbacks
local socket_list = {}                -- table of socket watch callbacks (for incoming data) 

-- adds a function to the delay list
-- note optional final parameters which define:
--    device context in which to run, and text name
local function add_to_delay_list (fct, seconds, data, devNo, type)  
  delay_list[#delay_list+1] = {
    callback = fct,
    delay = seconds,
    devNo = devNo or current_device,
    type = type,
    time = timenow() + seconds, 
    parameter = data, 
  }
end

-- adds a changed variable to the callback list
-- NOTE: that the variable itself has a list of watchers (with their device contexts)
local function watch_callback (var)
  watch_list[#watch_list+1] = var 
end


-- socket_watch (socket, action_with_incoming_tag),  add socket to list watched for incoming
-- optional io parameter is pointer to a device's I/O table with an intercept flag
local function socket_watch (sock, action, io, name)  
  socket_list[sock] = {
    callback = action,
    devNo = current_device,
    io = io or {intercept = false},   -- assume no intercepts: incoming data is passed to handler
    time = timenow (),                -- just for the console Sockets page
    name = name or "anon",            -- ditto
  }
end

-- socket_unwatch (),  remove socket from list watched for incoming
local function socket_unwatch (sock)  
  socket_list[sock] = nil
end

-- context_switch (devNo, fct, parameters, ...)
-- system-wide routine to pass control to different device code
-- basically a pcall, which sets and restores current_context to given devNo
-- this should be the only (x)pcall in the whole of openLuup
-- if devNo is nil, the existing device context is retained
local function context_switch (devNo, fct, ...)
  local old = current_device                    -- save current device context
  current_device = devNo or old
  local function restore (ok, msg, ...) 
    current_device = old                        -- restore old device context
    if not ok then
      _log (" ERROR: " .. tostring(msg or '?'), "openLuup.context_switch")  -- 2018.08.04 
    end
    return ok, msg, ... 
  end
  return restore (pcall (fct, ...))
end

-- CONSTANTS

local job_linger = 180        -- number of seconds before finished job is forgotten


local state =  {
    NoJob=-1,
    WaitingToStart=0,         --  If you return this value, 'job' runs again in 'timeout' seconds 
    InProgress=1,
    Error=2,
    Aborted=3,
    Done=4,
    WaitingForCallback=5,     -- This means the job is running and you're waiting for return data
    Requeue=6,
    InProgressPendingData=7,
 }
 
local valid_state = {}
for _,s in pairs (state) do valid_state[s] = s end

local exit_state = {
  [state.Error]       = true, 
  [state.Aborted]     = true,
  [state.Done]        = true,
}

local run_state = {
  [state.InProgress]      = true,
  [state.Requeue]         = true,
}

local wait_state = {
  [state.WaitingForCallback]    = true,
  [state.InProgressPendingData] = true,
}

-- LOCALS

local next_job_number = 1
local startup_list = {}

local job_list = setmetatable ( 
    {},      -- jobs indexed by job number
    {__index = function (_, idx)
        return {status = state.NoJob, notes = "no such job #" .. tostring(idx)}   -- 2016.02.01  add 'tostring'
      end,
    } 
  )

-------------
--
-- Sandbox for system libraries
--
-- Lua 5.1 strings are very special since EVERY string has a metatable with {__index = string}
-- You can't sandbox this in the obvious way, because it needs to work for both this
--
--   string.foo(str, ...)
--
-- and this
--
--   str: foo (...)
--
-- the code below doesn't prevent modification of the original table's contents
-- this would have to be done by an empty proxy table with its own __newindex() method
-- other library modules can generally be sandboxed just with shallow copies
--
 
local function sandbox (tbl, name)
  
  local devmsg = "device %s %s '%s.%s' (a %s value)"
  local function fail(...) error(devmsg: format (...), 3) end

  name = name or "{}"
  local lookup = {}             -- user function lookup indexed by [device][key]
  local meta = {__index = {}}   -- used to store proxy functions for each new key
  meta.lookup = lookup          -- 2019.01.28
  
  function meta:__newindex(k,v)   -- only ever called if key not already defined
  -- so this sandbox can't protect the original table keys from being changed
  -- for that, you'd need another layer which makes a shallow copy for each user context
    
    -- this is the proxy function which actually calls the user-defined function
    local function proxy (...) 
      local d = current_device or 0
      local fct = (lookup[d] or {}) [k]
      if not fct then
        fail (d, "attempted to reference", name, k, "nil")
      end
      return fct (...) 
    end

    local d = current_device or 0   -- k,v pairs are indexed by current device number
    local vtype = type(v)
    if vtype ~= "function" then fail (d, "attempted to define", name, k, vtype) end
    _log (devmsg: format (d, "defined", name, k, vtype), ABOUT.NAME..".sandbox")
    lookup[d] = lookup[d] or {}
    lookup[d][k] = v
    if not tbl[k] then                  -- proxy only needs to be set once
      rawset (meta.__index, k, proxy)
    end
  end

  function meta.__tostring ()    -- totally optional pretty-printing of sandboxed table contents
    local boxmsg = "\n   [%d] %s"
    local idxmsg = "        %-12s = %s"
    local x = {name .. ".sandbox:", '', "   Private items (by device):"}
    local empty = #x
    local function p(l) x[#x+1] = l end
    local function devname (d) 
      return ((luup.devices[d] or {}).description or "System"): match "^%s*(.+)" 
    end
    local function sorted(t)
      local y = {}
      for k,v in pairs (t) do y[#y+1] = idxmsg: format (k, tostring(v)) end
      table.sort (y)
      return table.concat (y, '\n')
    end
    for d, idx in pairs (lookup) do
      p (boxmsg: format (d, devname(d)))
      p (sorted(idx))
    end
    if #x == empty then x[#x+1] ="\n        -- none --" end
    p "\n   Shared items: \n"
    p (sorted (tbl))
    p ""                 -- blank line at end
    return table.concat (x, '\n')
  end

  setmetatable (tbl, meta)
end


sandbox (string, "string")

--
--
-------------


 local function missing (idx)   -- handle missing job tag
    return function (_, _, job)
      job.notes = "no action tag specified for: " .. tostring(idx)
      return state.Aborted, 0
    end
end

 
-- dispatch a task
local function dispatch (job, method)
  job.logging.invocations = job.logging.invocations + 1  -- how do I run thee?  Let me count the ways.
  local ok, status, timeout = context_switch (job.devNo, job.tag[method] or missing(method), 
                                                  job.target, job.arguments, job) 
  timeout = tonumber (timeout) or 0
  if ok then 
    status = status or state.Done                 -- 2018.03.21  add default exit state to jobs
    if not valid_state[status or ''] then
      job.notes = "invalid job state returned: " .. tostring(status)
      status = state.Aborted
    end
  else
    job.notes = status   -- error message from device context
    _log ("job aborted : " .. tostring(status))
    status = state.Aborted
  end  
  job.now = timenow()        -- 2017.05.05  update, since dispatched task may have taken a while
  job.expiry = job.now + timeout
  if exit_state[job.status] then
    job.expiry = job.now + job_linger
  end
  job.status  = status
  job.timeout = timeout
end
 
 
-- METHODS

-- parameters: job_number (number), device (string or number)
-- returns: job_status (number), notes (string)
local function status (job_number, device)
  local _ = device
  -- TODO: find out what job 'notes' are
  local info = job_list[job_number] or {}
  -- TODO: implement job number filtering
  return info.status, info.notes
end


-- create a job and schedule it to run
-- arguments is a table of name-value pairs, devNo is the device number
local function create_job (action, arguments, devNo, target_device)
  local jobNo = next_job_number
  next_job_number = next_job_number + 1
  
  local newJob = 
    {              -- this is the job structure
      arguments   = {},
      devNo       = devNo,              -- system jobs may have no device number
      status      = state.WaitingToStart,
      notes       =  '',                -- TODO: find out what job 'notes' are _really_ for - think it's 'comments'?
      timeout     = 0,
      type        = nil,                -- used in request id=status, and possibly elsewhere
      expiry      = timenow(),          -- time to go
      target      = target_device,
      settings    = {},                 -- 2017.05.01  user-defined parameter list
      -- job tag entry points
      tag = {
        job       = action.job,
        incoming  = action.incoming,
        timeout   = action.timeout,
      },
      -- log info
      logging = {
        created     = timenow(),
        invocations = 0,          -- number of times invoked
      },
      -- dispatcher
      dispatch  = dispatch,
    }
  
  for name, value in pairs (arguments or {}) do   -- copy the parameters
    newJob.arguments[name] = tostring(value)
  end
  
  job_list[jobNo] = newJob      -- add to the list
  return jobNo 
end

    
-- function: run_job
-- parameters: action object (with run/job/timeout/incoming methods), arguments (table), devNo
-- returns: error (number), error_msg (string), job (number), arguments (table)
--
-- Invokes the service + action, passing in the arguments (table of string->string pairs) to the device. 
-- If the invocation could not be made, only error will be returned with a value of -1. 
-- error is 0 if the device reported the action was successful. 
-- arguments is a table of string->string pairs with the return arguments from the action. 
-- If the action is handled asynchronously by a Luup job, 
-- then the job number will be returned as a positive integer.
--
local function run_job (action, arguments, devNo, target_device)
  local error = 0         -- assume success
  local error_msg
  local jobNo = 0
  local return_arguments = {}
  local args = arguments or {}      -- local copy
  local target = target_device or devNo
  
  if action.run then              -- run executes immediately and returns true or false
    local ok, response, error_msg = context_switch (devNo, action.run, target, args) 
    local _ = error_msg     -- unused at present
    args = {}               -- erase input arguments, in case we go on to a <job> (Luup does this)
    
    if not ok then return -1, response end         -- pcall error return with message in response
    if response == false then return -1 end        -- code has run OK, but returned fail status
  end
  
  if action.job then          -- we actually need to create a job to schedule later
    jobNo = create_job (action, args, devNo, target)
    return_arguments.JobID = tostring (jobNo)  -- the table contains {["JobID"] = "XX"}
  end
 
  if action.returns then                       -- return arguments list for call_action
    local dev = (luup or {devices = {}}).devices[target]
    if dev then
      local svc = dev.services[action.serviceId]      -- find the service variables on the target device
      if svc then
        local vars = svc.variables
        if vars then
          for name, relatedStateVariable in pairs (action.returns) do
            return_arguments[name] = (vars[relatedStateVariable] or {}).value 
          end
        end
      end
    end
  end
  
  -- 2017.02.22 add any extra (non-device-variable) returns
  for a,b in pairs (action.extra_returns or {}) do return_arguments[a] = b end

  return error, error_msg or '', jobNo, return_arguments
end

-- kill given jobNo
local function kill_job (jobNo)
  local job = job_list[jobNo]
  local msg
  if job then
    job.status = state.Aborted
    job.expiry = 0
    msg = "killed job#" .. jobNo
  else
    msg = "no such job#" .. jobNo
  end
  _log (msg, "openLuup.kill_job") 
end


local function device_start (entry_point, devNo, name)
  -- job wrapper for device initialisation
  local function startup_job (_,_,job)       -- note that user code is run in protected mode
    local label = ("[%s] %s device startup"): format (tostring(devNo), name or '')
    _log (label)
    local a,b,c = entry_point (devNo)       -- call the startup code 
    local completion = "%s completed: status=%s, msg=%s, name=%s"
    local text = completion: format (label, tostring(a),tostring(b), tostring(c))
    _log (text)
    local _ = job   -- unused at present
--    if job.notes == '' then
--      job.notes = text      -- use this as the startup job comments
--    end
    return state.Done, 0  
  end
  
  local jobNo = create_job ({job = startup_job}, {}, devNo)
  local job = job_list[jobNo]
  local text = "job#%d :plugin %s"
  job.type = text: format (jobNo, (name or ''): match "^%s*(.+)")
  startup_list[jobNo] = job  -- put this into the startup job list too 
  return jobNo
end    

-- step through one cycle of task processing
local function task_callbacks ()
  local N = 0       -- loop iteration count
  repeat
    N = N + 1
    local njn = next_job_number
  
    local local_job_list = {}
    do
      for jobNo, job in pairs (job_list) do 
        local_job_list[jobNo] = job  -- make local copy: list might be changed by jobs spawning
      end
    end
  
    for jobNo, job in pairs (local_job_list) do 
      
      job.now = timenow()
      
      if job.status == state.WaitingToStart and job.now >= job.expiry then
        job.status = state.InProgress   -- wake up after timeout period
      end

      if run_state[job.status] then
        job.status = state.InProgress   
        job: dispatch "job"       
      end
   
      if wait_state[job.status] then
        local incoming = false
        if incoming then          -- TODO: get 'incoming' status to do the right thing
          job: dispatch "incoming"
        elseif job.now > job.expiry then
          job: dispatch "timeout"         
        end
      end

      job.now = timenow()        -- 2017.05.05  update, since dispatched job may have taken a while
      if exit_state[job.status] and job.now > job.expiry then 
        job_list[jobNo] = nil   -- remove the job entirely from the actual job list (not local_job_list)
      end
    end
  until njn == next_job_number        -- keep going until no more new jobs queued
        or N > 5                      -- or too many iterations
end

----
--
-- Socket callbacks (incoming data)
--

local function socket_callbacks (timeout)
  local list = {}
  for sock, io in pairs (socket_list) do
    if not io.intercept then    -- io.intercept will stop the incoming handler from receiving data
      list[#list + 1] = sock
    end
  end  
  local recvt = socket.select (list, nil, timeout)  -- wait for something to happen (but not for too long)
  for _,sock in ipairs (recvt) do
    local info = socket_list[sock]
    local call = info.callback        -- registered callback handler
    local dev  = info.devNo
    local ok, msg = context_switch (dev, call, sock)    -- dispatch  
    if not ok then 
      _log (tostring(info.callback) .. " ERROR: " .. (msg or '?'), "luup.incoming_callback") 
    end
  end
end


----
--
-- Luup callbacks
--

local function luup_callbacks ()
  
  -- variable_watch list
  -- call handler with parameters: device, service, variable, value_old, value_new.
  local N = 0       -- loop iteration count
--  repeat
    N = N + 1
    local old_watch_list = watch_list
    watch_list = {}                       -- new list, because callbacks may change some variables!
    for _, callback in ipairs (old_watch_list) do
      for _, watcher in ipairs (callback.watchers) do   -- single variable may have multiple watchers
        local var = callback.var
        if not watcher.silent then
          _log (("%s.%s.%s %s"): format(var.dev, var.srv, var.name, tostring (watcher.callback)), 
                  "luup.watch_callback") 
        end
        local ok, msg = context_switch (watcher.devNo, watcher.callback, 
          var.dev, var.srv, var.name, var.old, var.value, var.time)   -- 2018.06.06 add extra time parameter 
        if not ok then
          _log (("%s.%s.%s ERROR %s %s"): format(var.dev or '?', var.srv, var.name, 
                                              msg or '?', tostring (watcher.callback))) 
        end
      end
    end
--  until #watch_list == 0 or N > 5   -- guard against race condition: a changes b, b changes a
  
  -- call_delay list  
  local now = timenow()
  local old_list = delay_list 
  delay_list = {}                        -- new list, because callbacks may add to delay list
  for _, schedule in ipairs (old_list) do 
    if schedule.time <= now then 
      local ok, msg = context_switch (schedule.devNo, schedule.callback, schedule.parameter) 
      if not ok then _log (tostring(schedule.callback) .. " ERROR: " .. (msg or '?'), "luup.delay_callback") end
      now = timenow()        -- 2017.05.05  update, since dispatched task may have taken a while
    else
      delay_list[#delay_list+1] = schedule   -- carry forward into new list      
    end
  end
end

local function stop (code)
  local _ = code          -- unused at present
  _log ("schedule stop request after " .. next_job_number .. " jobs")
  exit_code = 0
end

-- Main execution loop (only stopped by "exit" request)
local function start ()
  _log "starting"
  repeat                        -- this is the main scheduling loop!
    
    task_callbacks ()                     -- run tasks/jobs
    luup_callbacks ()                     -- do Luup callbacks (variable_watch, call_delay)
    
    -- it is the following call which throttles the whole round-robin scheduler if there is no work to do
    socket_callbacks (0.5)                -- wait for incoming (but not for too long)        
    
  until exit_code
  _log ("exiting with code " .. tostring (exit_code))
  _log (next_job_number .. " jobs completed ")
  return exit_code
end


---- export variables and methods

return {
    ABOUT = ABOUT,
    TEST = {                      -- for testing only
      step        = task_callbacks,
    },
    
    -- constants
    state             = state,
    -- variables
    job_list          = job_list,
    startup_list      = startup_list,
    --methods
    add_to_delay_list = add_to_delay_list,
    current_device    = function() return current_device end, 
    context_switch    = context_switch,
    delay_list        = function () return delay_list end,
    get_socket_list   = function () return socket_list end,
    device_start      = device_start,
    kill_job          = kill_job,
    run_job           = run_job,
    status            = status,   
    socket_watch      = socket_watch,
    socket_unwatch    = socket_unwatch,
    sleep             = sleep,
    start             = start,
    stop              = stop,
    timenow           = timenow,
    watch_callback    = watch_callback,
}

------------


