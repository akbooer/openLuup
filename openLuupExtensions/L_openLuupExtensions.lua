local ABOUT = {
  NAME          = "openLuup:Extensions",
  VERSION       = "2016.05.10",
  DESCRIPTION   = "openLuup:Extensions plugin for openLuup!!",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

--
-- provide added functionality, including:
--   * useful device variables
--   * useful actions
--   * etc., etc...
--

local timers  = require "openLuup.timers"
local json    = require "openLuup.json"

local INTERVAL = 120
local MINUTES  = "2m"

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

local cpu_prev = 0
local function ticker ()
  local AppMemoryUsed =  math.floor(collectgarbage "count")   -- openLuup's memory usage in kB
  local now, cpu = timers.timenow(), timers.cpu_clock()
  local uptime = now - timers.loadtime + 1
  
  local cpu_2m = round ((cpu - cpu_prev) / INTERVAL * 100, 0.1)
  cpu_prev= cpu
  local percent = round (100 * cpu / uptime, 0.1)
  local memory  = round (AppMemoryUsed / 1000, 0.1)
  local days    = round (uptime / 24 / 60 / 60, 0.01)
  local hours   = round (cpu /60 /60, 0.01)
  
  luup.variable_set (SID.ole, "Memory_Mb",       memory,  lul_device)
  luup.variable_set (SID.ole, "Cpu_2m",          cpu_2m,  lul_device)
  luup.variable_set (SID.ole, "CpuLoad_Percent", percent, lul_device)
  luup.variable_set (SID.ole, "CpuLoad_Hours",   hours,   lul_device)
  luup.variable_set (SID.ole, "Uptime_Days",     days,    lul_device)
  
  display (
    "Uptime " .. days .. " days", 
    "Memory " .. memory .. " Mb,  CPU " .. percent .. " %")
  
  local sfmt = "openLuup PLUGIN memory: %0.1f Mb, uptime: %0.2f days, cpu: %0.2f hours (%0.1f%%)"
  local stats = sfmt: format (memory, days, hours, percent)
  luup.log (stats)
end

-- HTTP requests

function HTTP_Extensions (r, p, f)
  local x = {}
  local fmt = "%-16s   %s   "
  for a,b in pairs (ABOUT) do
    x[#x+1] = fmt:format (a, tostring(b))
  end
  x = table.concat (x, '\n')
  return x
end


-- init

local function synchronise ()
  local days, data                      -- unused parameters
  local timer_type = 1                  -- interval timer
  local recurring = true                -- reschedule automatically
  timers.call_timer (ticker, timer_type, MINUTES, days, data, recurring)
  luup.log "synchronisation completed, system monitor started"
end

function init ()
  local later = timers.timenow() + INTERVAL    -- some minutes in the future
  later = INTERVAL - later % INTERVAL          -- adjust to on-the-hour 
  timers.call_delay (synchronise, later)
  local msg = ("synchronising in %0.1f seconds"): format (later)
  
  luup.register_handler ("HTTP_Extensions", "version")
  
  display "Uptime 0"
  return true, msg, ABOUT.NAME
end

-----
