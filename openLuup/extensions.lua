local ABOUT = {
  NAME          = "openLuup:Extensions",
  VERSION       = "2016.05.24",
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

local timers    = require "openLuup.timers"
local userdata  = require "openLuup.userdata"

local INTERVAL = 120
local MINUTES  = "2m"

local SID = {
  ole   = "openLuup",                       -- no need for those incomprehensible UPnP serviceIds
  altui = "urn:upnp-org:serviceId:altui1",  -- Variables = 'DisplayLine1' and 'DisplayLine2'
}

local ole   -- our own device ID

-- init

local function display (line1, line2)
  luup.variable_set (SID.altui, "DisplayLine1",  line1 or '', ole)
  luup.variable_set (SID.altui, "DisplayLine2",  line2 or '', ole)
end

-----

-- vital statistics
local function calc_stats ()
  local AppMemoryUsed =  math.floor(collectgarbage "count")   -- openLuup's memory usage in kB
  local now, cpu = os.time(), timers.cpu_clock()
  local elapsed = now - timers.loadtime + 1
  
  local percent = 100 * cpu / elapsed         -- % cpu
  local memory = AppMemoryUsed / 1000         -- Mb
  local uptime = elapsed / 24 / 60 / 60       -- days
   
  percent = ("%0.2f"): format (percent)
  memory  = ("%0.1f"): format (memory)
  uptime  = ("%0.2f"): format (uptime)
  
  luup.variable_set (SID.ole, "Memory_Mb",       memory,  ole)
  luup.variable_set (SID.ole, "CpuLoad_Percent", percent, ole)
  luup.variable_set (SID.ole, "Uptime_Days",     uptime,  ole)

  local line1 = ("%sMb, cpu %s%%, up %s days"): format (memory, percent, uptime)
  local line2 = ''                      -- TODO: "version: v0.7.0  (latest v0.8.3)"
  display (line1, line2)
  luup.log (line1)
 
  local set_attr = userdata.attributes.openLuup
  set_attr ["Memory"]  = memory .. "Mbyte"
  set_attr ["CpuLoad"] = percent .. '%'
  set_attr ["Uptime"]  = uptime .. " days"
end

-----

local function ticker ()
  print ("luup.device", luup.device)
  calc_stats()
end

-- HTTP requests

--function HTTP_openLuup (r, p, f)
function HTTP_openLuup ()
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
  calc_stats ()
end

function init (devNo)
  ole = devNo
  local later = timers.timenow() + INTERVAL    -- some minutes in the future
  later = INTERVAL - later % INTERVAL          -- adjust to on-the-hour 
  timers.call_delay (synchronise, later)
  local msg = ("synchronising in %0.1f seconds"): format (later)
  print (msg)
  
  luup.register_handler ("HTTP_openLuup", "version")
  
  calc_stats ()
  return true, msg, ABOUT.NAME
end

-----
