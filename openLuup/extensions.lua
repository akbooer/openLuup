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
local plugins   = require "openLuup.plugins"

local INTERVAL = 120
local MINUTES  = "2m"

local SID = {
  ole   = "openLuup",                       -- no need for those incomprehensible UPnP serviceIds
  altui = "urn:upnp-org:serviceId:altui1",  -- Variables = 'DisplayLine1' and 'DisplayLine2'
}

local ole               -- our own device ID
local latest = '?'      -- latest tagged GitHub version of openLuup

local function round (x, p)
  p = p or 1
  x = x + p / 2
  return x - x % p
end

local function display (line1, line2)
  if line1 then luup.variable_set (SID.altui, "DisplayLine1",  line1 or '', ole) end
  if line2 then luup.variable_set (SID.altui, "DisplayLine2",  line2 or '', ole) end
end

-----

-- vital statistics
local cpu_prev = 0

local function calc_stats ()
  local AppMemoryUsed =  math.floor(collectgarbage "count")   -- openLuup's memory usage in kB
  local now, cpu = timers.timenow(), timers.cpu_clock()
  local uptime = now - timers.loadtime + 1
  
  local cpuload = round ((cpu - cpu_prev) / INTERVAL * 100, 0.1)
  local memory  = round (AppMemoryUsed / 1000, 0.1)
  local days    = round (uptime / 24 / 60 / 60, 0.01)
  
  cpu_prev= cpu

  luup.variable_set (SID.ole, "Memory_Mb",   memory,  ole)
  luup.variable_set (SID.ole, "CpuLoad",     cpuload, ole)
  luup.variable_set (SID.ole, "Uptime_Days", days,    ole)

  local line1 = ("%0.0f Mb, cpu %s%%, up %s days"): format (memory, cpuload, days)
  display (line1)
  luup.log (line1)
 
  local set_attr = userdata.attributes.openLuup
  set_attr ["Memory"]  = memory .. " Mbyte"
  set_attr ["CpuLoad"] = cpuload .. '%'
  set_attr ["Uptime"]  = days .. " days"
end

-- HTTP requests

--function HTTP_openLuup (r, p, f)
function HTTP_openLuup ()
  local x = {}
  local fmt = "%-16s   %s   "
  for a,b in pairs (ABOUT) do
    x[#x+1] = fmt:format (a, tostring(b))
  end
  local info = luup.attr_get "openLuup"
  x[#x+1] = "----------"
  for a,b in pairs (info or {}) do
    x[#x+1] = table.concat {a, " : ", tostring(b)} 
  end
  x = table.concat (x, '\n')
  return x
end

-- init

function OLE_ticker ()
  calc_stats()
end

function OLE_synchronise ()
  local days, data                      -- unused parameters
  local timer_type = 1                  -- interval timer
  local recurring = true                -- reschedule automatically, definitely not a Vera luup option! ... 
                          -- ...it ensures that rescheduling is always on time and does not 'slip' between calls.
  luup.call_timer ("OLE_ticker", timer_type, MINUTES, days, data, recurring)
  local latest = "latest: " .. (plugins.latest_version () or '?')
  display (nil, latest)
  calc_stats ()
end

function init (devNo)
  ole = devNo
  local later = timers.timenow() + INTERVAL    -- some minutes in the future
  later = INTERVAL - later % INTERVAL          -- adjust to on-the-hour (actually, two-minutes)
  luup.call_delay ("OLE_synchronise", later)
  local msg = ("synch in %0.1f s"): format (later)
  luup.log (msg)
  display (nil, '')
  
  luup.register_handler ("HTTP_openLuup", "openLuup")
  luup.register_handler ("HTTP_openLuup", "openluup")     -- lower case
  
  calc_stats ()
  return true, msg, ABOUT.NAME
end

-----
