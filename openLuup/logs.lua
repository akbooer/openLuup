local ABOUT = {
  NAME          = "openLuup.logs",
  VERSION       = "2016.04.30",
  DESCRIPTION   = "basic log file handling, including versioning",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

-- log handling - basic at the moment

local socket = require "socket"

local start_time = os.time()

--[[

Vera records different types of log entries, in its log files, according to logging levels. By default only log levels 1-10 will make it to /var/log/cmh/LuaUPnP.log and all other types of messages are discarded.

To add more log levels edit the file /etc/cmh/cmh.conf. To see all log entries check the verbose option on Advanced/Logs, or put a comment character (#) in front of the LogLevels= line in /etc/cmh/cmh.conf

 #LogLevels = 1,2,3,4,5,6,7,8,9,50,40

Here's a full list of the log types that Vera supports:

LV_CRITICAL         1
LV_WARNING          2
LV_STARTSTOP        3
LV_JOB              4
LV_HA               5
LV_VARIABLE         6
LV_EVENT            7
LV_ACTION           8
LV_ENUMERATION      9
LV_STATUS           10
LV_CHILD_DEVICES    11
LV_DATA_REQUEST     12

LV_LOCKING          20
LV_IR               28
LV_ALARM            31
LV_SOCKET           32
LV_DEBUG            35
LV_PROFILER         37
LV_PROCESSUTILS     38

// Z-Wave starts with 4
LV_ZWAVE            40
LV_SEND_ZWAVE       41
LV_RECEIVE_ZWAVE    42

// Lua starts with 5
LV_LUA              50
LV_SEND_LUA         51
LV_RECEIVE_LUA      52

// Insteon starts with 6
LV_INSTEON          60
LV_SEND_INSTEON     61
LV_RECEIVE_INSTEON  62

// Low level debugging starts with 2+ ZWave/Lua/Insteon
LV_ZWAVE_DEBUG      24
LV_LUA_DEBUG        25
LV_INSTEON_DEBUG    26

--]]


-- return formatted current time (or given time) as a string
-- ISO 8601 date/time: YYYY-MM-DDThh:mm:ss or other specified format
local function formatted_time (date_format, now)
  now = now or socket.gettime()                        -- millisecond resolution
  date_format = date_format or "%Y-%m-%dT%H:%M:%S"     -- ISO 8601
  local date = os.date (date_format, now)
  local ms = math.floor (1000 * (now % 1)) 
  return ('%s.%03d'):format (date, ms)
end


-- dummy io modiule for missing files
local function dummy_io (functions)
  local function noop () end
  functions = functions or {}
  return {
    write   = functions.write   or noop,
    close   = functions.close   or noop,
    setvbuf = functions.setvbuf or noop,
  }
end

--
-- syslog
--[[

local syslog = {
  
--emergency, alert, critical, error, warning, notice, info, debug = 0,1,2,3,4,5,6,7,


server = function (ip_and_port, tag, hostname)
  local sock = socket.udp()
  local facility = 1    -- 'user'
  local ip, port = ip_and_port: match "^(%d+%.%d+%.%d+%.%d+):(%d+)$"
  if not ip or not port then return nil, "invalid IP or PORT" end
  if not tag or tag == '' then tag = "Plugin" end
  tag = tag: gsub("[^%w]","") or "XXX"  -- only alphanumeric, no spaces or other
  
  local function send (self, content, severity)
    content  = tostring (content)
    severity = tonumber (severity) or info
    local priority = facility*8 + (severity%8)
    local msg = ("<%d>%s %s %s: %s\n"):format (priority, os.date "%b %d %H:%M:%S", hostname, tag, content)
    sock:send (msg) 
  end
  
  local ok, err = sock:setpeername(ip, port)
  if ok then ok = {send = send} end
  return ok, err
end

}
--]]

--
-- log message to luup.log file
--

-- logfile ()   open new logfile with a number of archived versions, and lines per version
-- returns table with send function to actually log new data
local function openLuup_logger (info)
  local f
  local logfile_name, versions, maxLines = info.name, info.versions or 0, info.lines or 2000
  local N = 0                                 -- current line number
  local formatted_time = formatted_time
  
  -- open log  
  local function open_log ()
    local function print_not_write (self, msg)  -- in case there's a problem opening file
      print (msg:gsub ("%s+",' '))
    end
    local f = io.open (logfile_name, 'w') or dummy_io {write = print_not_write}
    f:setvbuf "line" 
    return f
  end

  -- rename old files
  local function rotate_logs ()
    for i = versions-1,1,-1 do
      os.rename (logfile_name..'.'..(i), logfile_name..'.'..(i+1))
    end
    os.rename (logfile_name, logfile_name..'.'..(1))
  end

  -- write data
  local function write (message)
    f:write (message)
    N = N + 1
    if (N % maxLines) == 0 then 
      local runtime = (os.time() - start_time) / 60 / 60 / 24
      local fmt = "%s   :: openLuup LOG ROTATION :: (runtime %0.1f days) \n"
      local message = fmt: format (formatted_time "%Y-%m-%d %H:%M:%S", runtime)
      f:write (message)
      f: close ()
      rotate_logs () 
      f = open_log ()
      f:write (message)
    end
  end

  -- format and write log
  local function send (msg, subsystem_or_number, devNo)
    subsystem_or_number = subsystem_or_number or 50
    if type (subsystem_or_number) == "number" then subsystem_or_number = "luup_log" end
    local now = formatted_time "%Y-%m-%d %H:%M:%S"
    local message = table.concat {now, "   ",subsystem_or_number, ":", devNo or '', ": ", tostring(msg), '\n'}
    write (message)
  end
  
  -- logfile init
  rotate_logs ()       -- save the old ones
  f = open_log ()      -- start anew
  return {send = send}
end

--
-- write log for ALTUI to parse: contains only variables and scene runs
--
-- writes to usual Vera log location: /tmp/logs/cmh/LuaUPnP.log
--

--[[
Note that ALTUI now parses logs for scene and variable info.  

From @amg0 (personal communication):

It is based on pattern matching of the logs but done in 2 places.
a first one done by LUA in the Handler, then a second one in javascript to refine/finish the work

for scene:
in LUA
- var cmd = "cat /var/log/cmh/LuaUPnP.log | grep 'Scene::RunScene running {0}'".format(id);
then the result is searched in Javascript to extract the date/time & scene name with the following regexp
- var re = /\d*\t(\d*\/\d*\/\d*\s\d*:\d*:\d*.\d*).*Scene::RunScene running \d+ (.*) <.*/g;


for device variable:
in LUA
- var cmd = "cat /var/log/cmh/LuaUPnP.log | grep 'Device_Variable::m_szValue_set device: {0}.*;1m{1}\033'".format(device.id,state.variable);
then the result is searched in Javascript to extract the date/time & old and new value with the following regexp
- var re = /\d*\t(\d*\/\d*\/\d*\s\d*:\d*:\d*.\d*).*was: (.*) now: (.*) #.*/g;



This means you need to match this:

for scenes:
this:
  08	07/16/15 16:18:20.649	Scene::RunScene running 3 RGBW Full ON <0x743d4520>
with:
 "%d*\t(%d*/%d*/%d*%s%d*:%d*:%d*.%d*).*Scene::RunScene running %d+ (.*) <.*"

for variables:
this:
  06	07/14/15 15:34:17.485	Device_Variable::m_szValue_set device: 5 service: urn:akbooer-com:serviceId:EventWatcher1 variable: AppMemoryUsed was: 863 now: 943 #hooks: 1 upnp: 0 skip: 0 v:(nil)/NONE duplicate:0 <0x76376520>
with:
  "%d*\t(%d*/%d*%/%d*%s%d*:%d*:%d*.%d*).*was: (.*) now: (.*) #.*"



--]]

local function altui_logger (info)
  local f
  local logfile_name, maxLines = info.name, info.lines or 2000
  local N = 0                                 -- current line number
  local formatted_time = formatted_time
    
   -- open log  
  local function open_log ()
    local f = io.open (logfile_name, 'w') or dummy_io {}
    f:setvbuf "line" 
    return f
  end
  
  -- rename old files
  local function rotate_logs ()
    os.rename (logfile_name, logfile_name.. ".1")
  end
  
  local function write (message)
    f:write (message)
    N = N + 1
    if (N % maxLines) == 0 then 
      f: close ()
      rotate_logs () 
      f = open_log ()
    end
   end
  
  local function variable (var)
    local now = formatted_time "%m/%d/%y %H:%M:%S"
    local vfmt =   "%02d\t%s\tDevice_Variable::m_szValue_set device: %d service: %s " ..
                    "variable: \027[35;1m%s\027[0m was: %s now: %s #hooks: %d \n"
    local msg = vfmt: format (6, now, var.dev, var.srv, var.name, 
                var.old or "MISSING", var.value, #var.watchers)
    write (msg)
    return msg    -- for testing
  end
  
  local function scene (scn)
    local now = formatted_time "%m/%d/%y %H:%M:%S"
    local sfmt = "%02d\t%s Scene::RunScene running %d %s <%s>\n"
    local msg = sfmt: format (8, now, scn.id, scn.name, "0x0")
    write (msg)
    return msg    -- for testing
  end
  
  -- altui_logger init ()
  
  rotate_logs ()       -- save the old ones
  f = open_log ()      -- start anew
  return {
    scene     = scene,
    variable  = variable,
  }
end


-- INIT

-- openLuup log
local normal = openLuup_logger {name = "LuaUPnP.log", versions = 5, lines =2000}

-- altui log (for variable and scene history)
-- note that altui reads from /var/log/cmh/LuaUPnP.log
local altui  = altui_logger {name = "/var/log/cmh/LuaUPnP.log", lines = 5000}

-- display module banner
local function banner (ABOUT)
  local msg = ("%" .. 25-#ABOUT.NAME .. "s %s  @akbooer"): format ("version", ABOUT.VERSION)
  normal.send (msg, ABOUT.NAME, '')
end

-- export methods

return {
  ABOUT = ABOUT,
  
  banner          = banner,
  send            = normal.send,
  altui_variable  = altui.variable,
  altui_scene     = altui.scene,
  -- for testing
  openLuup_logger = openLuup_logger,
  altui_logger    = altui_logger,
  }

----
