
local t = require "luaunit"

-- openLuup.scheduler TESTS

local socket = require "socket"     -- for delay function
local s      = require "openLuup.scheduler"

luup = {}     -- for device context

local TIMEOUT = 1
local jobReturn 

-- THIS IS WHAT A CLIENT JOB LOOKS LIKE:

local N = 0  
local sequence = {s.state.Requeue, s.state.InProgress, s.state.Done}

local myJob = {
     
-- <run> (not really a job)
-- variables: lul_device is a number that is the device id. lul_settings is a table with all the arguments to the action.
-- return value: true or false where true means the function ran ok, false means it failed. 
run = function (lul_device, lul_settings)
  jobReturn = {device = lul_device, settings=lul_settings, comment = "<run> tag"}  -- save our environment
  return true
end,

-- <job>
-- variables: lul_device is a number that is the device id. lul_settings is a table with all the arguments to the action. lul_job is the id number of the job.
-- return value: The first is the job status and is a number from 0-5, and the second is the timeout in seconds.
job = function (lul_device, lul_settings, lul_job)
  N = N + 1
  return sequence[N]        -- run through the test sequence
end,

-- <timeout>
-- variables: same as for job above.
-- return value: same as for job above
timeout = function (lul_device, lul_settings, lul_job)
  return job_state.Done
end,

-- <incoming> (returned by a job)
-- variables: same as for job above, plus lul_data which is a binary string with the data received
-- return value: return 3 values with the syntax return a,b,c. 
-- The first two are the same as with job, and the 3rd is a true or false indicating if the incoming data was intended for this job. 
incoming = function (lul_device, lul_settings, lul_job, lul_data)
end,

}  -- END OF myJob

                    
---------------------------------------


TestScheduler = {}     -- luup tests

function TestScheduler:setUp ()
end

function TestScheduler:tearDown ()
end

-- basics

function TestScheduler:test_basic_types ()
  t.assertIsFunction (s.device_start)
  t.assertIsFunction (s.run_job)
--  t.assertIsFunction (s.job_watch)
--  t.assertIsFunction (s.get)
  t.assertIsFunction (s.status)
--  t.assertIsFunction (s.set)
end

function TestScheduler:test_status ()
  local status, notes = s.status (42)      -- missing job
  t.assertEquals (status, s.state.NoJob)
  t.assertIsString (notes)
  t.assertEquals (notes , "no such job #42")
end

function TestScheduler:test_run_true ()
  local runTrue = { run = function () return true  end}
  local error, error_msg, jobNo, return_arguments = s.run_job (runTrue, {})
  t.assertEquals (error, 0)
--  t.assertEquals (jobNo, 0)
--  t.assertIsTable (return_arguments)
end

function TestScheduler:test_run_target ()
  local runTarget = { run = function (devNo) return devNo == 42 end}
  local error, error_msg, jobNo, return_arguments = s.run_job (runTarget, {}, nil, 42)
  t.assertEquals (error, 0)
--  t.assertEquals (jobNo, 0)
--  t.assertIsTable (return_arguments)
end

function TestScheduler:test_null_job ()
  local nullJob = { }
  local error, error_msg, jobNo, return_arguments = s.run_job (nullJob, {})
  t.assertEquals (error, 0)
--  t.assertEquals (jobNo, 0)
--  t.assertIsTable (return_arguments)
end

function TestScheduler:test_run_false ()
  local runFalse = { run = function () return false end}
  local error, error_msg, jobNo, return_arguments = s.run_job (runFalse, {})
  t.assertEquals (error, -1)
--  t.assertEquals (jobNo, 0)
--  t.assertIsTable (return_arguments)
end

function TestScheduler:test_job_done ()
  local jobDone = { job = function () return s.state.Done  end}
  local error, error_msg, jobNo, return_arguments = s.run_job (jobDone, {})
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertNotEquals (jobNo, 0)
  t.assertIsTable (return_arguments)
  s.step ()      -- one cycle of processing
  local status, notes = s.status (jobNo)
  t.assertEquals (status, s.state.Done)
  t.assertEquals (notes, '')
end

function TestScheduler:test_job_target ()
  local jobTarget = { 
    job = function (devNo) 
      if devNo == 42 
        then return s.state.Done 
        else return s.state.Error 
      end
    end}
  local error, error_msg, jobNo, return_arguments = s.run_job (jobTarget, {}, nil, 42)
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertNotEquals (jobNo, 0)
  t.assertIsTable (return_arguments)
  s.step ()      -- one cycle of processing
  local status, notes = s.status (jobNo)
  t.assertEquals (status, s.state.Done)
  t.assertEquals (notes, '')
end

function TestScheduler:test_job_error ()
  local jobError = { job = function () return s.state.Error end}
  local error, error_msg, jobNo, return_arguments = s.run_job (jobError, {})
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertNotEquals (jobNo, 0)
  t.assertIsTable (return_arguments)
  s.step ()      -- one cycle of processing
  local status, notes = s.status (jobNo)
  t.assertEquals (status, s.state.Error)
  t.assertEquals (notes, '')
end

function TestScheduler:test_call ()
  local error, error_msg, jobNo, return_arguments = s.run_job (myJob, {})
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertIsTable (return_arguments)
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.WaitingToStart)
  t.assertEquals (notes, '')
  
  for _, seq in ipairs (sequence) do
    s.step()
    local status, notes = s.status (jobNo)   
    t.assertEquals (notes, '')
    t.assertEquals (status, seq)
  end  
end

function TestScheduler:test_delayed ()
  local Ndelay = 0
  local delay_sequence = {s.state.WaitingToStart, s.state.Done}
  local delayed = {
          job = function () Ndelay = Ndelay+1; return delay_sequence [Ndelay], TIMEOUT end
        }
  local error, error_msg, jobNo, return_arguments = s.run_job (delayed, {})
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertIsTable (return_arguments)
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.WaitingToStart)
  t.assertEquals (notes, '')
  
  s.step()   -- should stay in waiting to start status and then run after timeout period
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.WaitingToStart)
  t.assertEquals (notes, '')
  
  socket.select ({}, nil, TIMEOUT)      -- wait a bit
  
  s.step()   -- should run to completion
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.Done)
  t.assertEquals (notes, '')
end

function TestScheduler:test_no_timeout_tag ()
  local timeout = {
          job = function () return s.state.WaitingForCallback, TIMEOUT end, -- wait forever !
        }
  local error, error_msg, jobNo, return_arguments = s.run_job (timeout, {})
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertIsTable (return_arguments)
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.WaitingToStart)
  t.assertEquals (notes, '')
  
  s.step()   -- should now be in WaitingForCallback forever
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.WaitingForCallback)
  t.assertEquals (notes, '')
  
  socket.select ({}, nil, TIMEOUT)      -- wait a bit
  
  s.step()   -- should timeout and exit with Aborted status
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.Aborted)
  t.assertEquals (notes, "no action tag specified for: timeout")
end


function TestScheduler:test_timeout_tag ()
  local timeout = {
          job = function () return s.state.WaitingForCallback, TIMEOUT end, -- wait forever !
          timeout = function () return s.state.Done, 0 end
        }
  local error, error_msg, jobNo, return_arguments = s.run_job (timeout, {})
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertIsTable (return_arguments)
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.WaitingToStart)
  t.assertEquals (notes, '')
  
  s.step()   -- should now be in WaitingForCallback forever
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.WaitingForCallback)
  t.assertEquals (notes, '')
  
  socket.select ({}, nil, TIMEOUT)      -- wait a bit
  
  s.step()   -- should timeout and exit with Done status
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.Done)
  t.assertEquals (notes, '')
end

function TestScheduler:test_invalid_state ()
  local invalid = {
      job = function () return 42,0 end
    }
  local error, error_msg, jobNo, return_arguments = s.run_job (invalid, {})
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertIsTable (return_arguments)
  
  s.step()   -- should now have exited with an invalid state
  
  local status, notes = s.status (jobNo)   
  t.assertEquals (status, s.state.Aborted)
  t.assertEquals (notes, "invalid job state returned: 42")
end


function TestScheduler:test_context ()
  local function fct (x)
    t.assertEquals (x, math.pi)
    t.assertEquals (luup.device, 42)
    return 888
  end
  local ok,y = s.context_switch (42, fct, math.pi)
  t.assertEquals (ok, true)
  t.assertIsNil (luup.device)
  t.assertEquals (y, 888)
end


function TestScheduler:test_action_returns ()
  luup = require "openLuup.luup"
  local devNo = luup.create_device ("my_device_type")         -- create a device
  
  luup.variable_set ("my_service_id", "number", 42, devNo)    -- and a serviceId with variable
  local action_returns = { 
      serviceId = "my_service_id",                    -- define action as being in same service
      run = function () return true end,              -- run does nothing itself...
      returns = {FancyOutputName = "number"},         -- ...but should return the state variable
    }
  local error, error_msg, jobNo, return_arguments = s.run_job (action_returns, {})
  t.assertEquals (error, 0)
--  t.assertEquals (jobNo, 0)
  t.assertIsTable (return_arguments)
--  t.assertEquals (#return_arguments, 1)
--  t.assertEquals (return_arguments.FancyOutputName, 42)
end
  

function TestScheduler:test_ ()
  
end


-------------------

if not multifile then t.LuaUnit.run "-v" end

-------------------
