_NAME = "openLuup:Extensions"
_VERSION = "2015.11.01"
_DESCRIPTION = "openLuup:Extensions plugin for openLuup!!"
_AUTHOR = "@akbooer"

--
-- provide added functionality, including:
--   * useful device variables
--   * useful actions
--   * etc., etc...
--

local timers = require "openLuup.timers"


local SID = {
  ole   = "openLuup",                       -- no need for those incomprehensible UPnP serviceIds
  altui = "urn:upnp-org:serviceId:altui1",  -- Variables = 'DisplayLine1' and 'DisplayLine2'
}

local function round (x, p)
  p = p or 1
  x = x + p / 2
  return x - x % p
end

-- init

local function display (line1, line2)
  luup.variable_set (SID.altui, "DisplayLine1",  line1 or '', lul_device)
  luup.variable_set (SID.altui, "DisplayLine2",  line2 or '', lul_device)
end

local function ticker ()
  local AppMemoryUsed =  math.floor(collectgarbage "count")   -- openLuup's memory usage in kB
  local now, cpu = timers.timenow(), timers.cpu_clock()
  local uptime = now - timers.loadtime + 1
  
  local percent = round (100 * cpu / uptime, 0.1)
  local memory  = round (AppMemoryUsed / 1000, 0.1)
  local days    = round (uptime / 24 / 60 / 60, 0.01)
  local hours   = round (cpu /60 /60, 0.01)
  
  luup.variable_set (SID.ole, "Memory_Mb",       memory,  lul_device)
  luup.variable_set (SID.ole, "CpuLoad_Percent", percent, lul_device)
  luup.variable_set (SID.ole, "CpuLoad_Hours",   hours,   lul_device)
  luup.variable_set (SID.ole, "Uptime_Days",     days,    lul_device)
  
  display ("Uptime " .. days .. " days", "Memory " .. memory .. " Mb")
  
  local sfmt = "openLuup PLUGIN memory: %0.1f Mb, uptime: %0.2f days, cpu: %0.2f hours (%0.1f%%)"
  local stats = sfmt: format (memory, days, hours, percent)
  luup.log (stats)
end

-- init

local function synchronise ()
  local days, data                      -- unused parameters
  local timer_type = 1                  -- interval timer
  local recurring = true                -- reschedule automatically
  timers.call_timer (ticker, timer_type, "2m", days, data, recurring)
  luup.log "synchronisation completed, system monitor started"
end

function init ()
  local later = timers.timenow() + 120    -- two minutes in the future
  later = 120 - later % 120               -- adjust to on-the-hour 
  timers.call_delay (synchronise, later)
  local msg = ("synchronising in %0.1f seconds"): format (later)
  display "Uptime 0"
  return nil, msg, _NAME
end

-----
