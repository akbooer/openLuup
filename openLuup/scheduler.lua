local _NAME = "openLuup.scheduler"
local revisionDate = "2015.10.15"
local banner = "version " .. revisionDate .. "  @akbooer"

--
-- openLuup job scheduler
--
-- The scheduler handles creation / running / deletion of jobs which run asynchronously.  
-- It is a cooperative scheduler so requires good behaviour in terms of client job run time.
-- Included in asynchronous processing are: delays / timers / watch callbacks / actions / jobs...
-- ...and incoming data for registered sockets
-- Callbacks which use named global functions are resolved using the appropriate device context
-- by lookup in the relevant module or the global table.
--

local logs      = require "openLuup.logs"
local socket    = require "socket"         -- socket library needed to access time in millisecond resolution

--  local log
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control


-- LOCAL variables

local exit_code     -- set to Unix process exit code to stop scheduler

local delay_list = {}                 -- list of delay callbacks
local watch_list = {}                 -- list of watch callbacks
local socket_list = {}                -- table of socket watch callbacks (for incoming data) 

-- adds a function to the delay list
-- note optional final parameters which defines device context in which to run
local function add_to_delay_list (fct, seconds, data, devNo)
  delay_list[#delay_list+1] = {
    callback = fct,
    devNo = devNo or (luup or {}).device,
    time = socket.gettime() + seconds, 
    parameter = data, 
  }
end

-- adds a changed variable to the callback list
-- NOTE: that the variable itself has a list of watchers (with their device contexts)
local function watch_callback (var)
  watch_list[#watch_list+1] = var 
end


-- socket_watch (socket, action_with_incoming_tag),  add socket to list watched for incoming
local function socket_watch (sock, action)  
  socket_list[sock] = {
    callback = action,
    devNo = (luup or {}).device,
  }
end

-- socket_unwatch (),  remove socket from list watched for incoming
local function socket_unwatch (sock)  
  socket_list[sock] = nil
end

-- context_switch (devNo, fct, parameters, ...)
-- system-wide routine to pass control to different device code
-- basically a pcall, which sets and restores luup.device to given devNo
-- this should be the only pcall in the whole of openLuup
-- if devNo is nil, the existing device context is retained
local function context_switch (devNo, ...)
  local l = luup or {}                    -- luup not present in testing, perhaps
  local old = l.device                    -- save current device context
  l.device = devNo or old
  local function restore (ok, msg, ...) 
    l.device = old                        -- restore old device context
    if not ok then
      _log (" ERROR: " .. (msg or '?'), "openLuup.context_switch") 
    end
    return ok, msg, ... 
  end
  return restore (pcall (...))
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

local job_list = setmetatable ( 
    {},      -- jobs indexed by job number
    {__index = function (_, idx)
        return {status = state.NoJob, notes = "no such job #" .. idx}
      end,
    } 
  )
  
 local function missing (idx)   -- handle missing job tag
    return function (_, _, job)
      job.notes = "no action tag specified for: " .. tostring(idx)
      return state.Aborted, 0
    end
end

 
-- dispatch a task
local function dispatch (job, method)
  local ok, status, timeout = context_switch (job.devNo, job.tag[method] or missing(method), 
                                                  job.target, job.arguments, job) 
  timeout = tonumber (timeout) or 0
  if ok then 
    if not valid_state[status or ''] then
      job.notes = "invalid job state returned: " .. tostring(status)
      status = state.Aborted
    end
  else
    job.notes = status   -- error message from device context
    _log ("job aborted : " .. tostring(status))
    status = state.Aborted
  end  
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
      notes       =  '',                -- TODO: find out what job 'notes' are _really_ for
      timeout     = 0,
      type        = nil,                -- used in request id=status, and possibly elsewhere
      expiry      = socket.gettime (),                 -- time to go
      target      = target_device,
      -- job tag entry points
      tag = {
        job       = action.job,
        incoming  = action.incoming,
        timeout   = action.timeout,
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
  
  return error, error_msg, jobNo, return_arguments
end

local function device_start (entry_point, devNo)
  -- job wrapper for device initialisation
  local function startup_job ()       -- note that user code is run in protected mode
    _log "device startup"
    local a,b,c = entry_point (devNo)       -- call the startup code 
    _log (("device startup completed: status=%s, msg=%s, name=%s" ): format (tostring(a),tostring(b), tostring(c)))
    return state.Done, 0  
  end
  
  local jobNo = create_job ({job = startup_job}, {}, devNo)
  job_list[jobNo].type = table.concat {'[', devNo, '] ', "device"}  -- TODO: embellish with description
  -- TODO: put this into the startup job list too (ephemeral)
  return jobNo
end    
    -- TODO: device startup status and messages
  --[[
  startup": {

    "tasks": 

[

        {
            "id": 1,
            "status": 2,
            "type": "Test Plugin[58]",
            "comments": "Lua Engine Failed to Load"
        }
    ]

},
  ]]--


-- step through one cycle of task processing
local function task_callbacks ()
  local N = 0       -- loop iteration count
  repeat
    N = N + 1
    local njn = next_job_number
  
    local local_job_list = {}
    
    for jobNo, job in pairs (job_list) do 
      local_job_list[jobNo] = job  -- make local copy: list might be changed by jobs spawning
    end
    
    for jobNo, job in pairs (local_job_list) do 
      
      job.now = socket.gettime ()
      
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

      if exit_state[job.status] and job.now > job.expiry then 
        job_list[jobNo] = nil   -- remove the job entirely from the actual job list (not local copy)
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
  for sock in pairs (socket_list) do
    list[#list + 1] = sock
  end  
  local recvt = socket.select (list, nil, timeout)  -- wait for something to happen (but not for too long)
  for _,sock in ipairs (recvt) do
    local info = socket_list[sock]
    local call = info.callback        -- registered callback handler
    local dev  = info.devNo
    local ok, msg = context_switch (dev, call, sock)    -- dispatch  
    if not ok then 
      _log (tostring(schedule.callback) .. " ERROR: " .. (msg or '?'), "luup.incoming_callback") 
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
    watch_list = {}                                   -- new list, because callbacks may change some variables!
    for _, var in ipairs (old_watch_list) do
      for _, watcher in ipairs (var.watchers) do              -- single variable may have multiple watchers
        _log (("%d.%s.%s %s"): format(var.dev or 888, var.srv, var.name, tostring (watcher.callback)), 
                  "luup.watch_callback") 
        local ok, msg = context_switch ( 
          watcher.devNo, watcher.callback, var.dev, var.srv, var.name, var.old, var.value) 
        if not ok then
          _log (("%d.%s.%s ERROR %s %s"): format(var.dev or 888, var.srv, var.name, 
                                              msg or '?', tostring (watcher.callback))) 
        end
      end
    end
--  until #watch_list == 0 or N > 5   -- guard against race condition: a changes b, b changes a
  
  -- call_delay list  
  local now = socket.gettime()
  local old_list = delay_list 
  delay_list = {}                        -- new list, because callbacks may add to delay list
  for _, schedule in ipairs (old_list) do 
    if schedule.time <= now then 
      local ok, msg = context_switch (schedule.devNo, schedule.callback, schedule.parameter) 
      if not ok then _log (tostring(schedule.callback) .. " ERROR: " .. (msg or '?'), "luup.delay_callback") end
    else
      delay_list[#delay_list+1] = schedule   -- carry forward into new list      
    end
  end
end

local function stop (code)
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
    -- constants
    state             = state,
    version           = banner,
    -- variables
    job_list          = job_list,
    --methods
    add_to_delay_list = add_to_delay_list,
    context_switch    = context_switch,
    device_start      = device_start,
    run_job           = run_job,
    status            = status,   
    watch_callback    = watch_callback,
    socket_watch      = socket_watch,
    socket_unwatch    = socket_unwatch,
    start             = start,
    stop              = stop,
    step              = task_callbacks,      -- for testing only
}

------------


