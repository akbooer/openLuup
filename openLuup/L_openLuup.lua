ABOUT = {
  NAME          = "L_openLuup",
  VERSION       = "2018.03.20",
  DESCRIPTION   = "openLuup device plugin for openLuup!!",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
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
-- provide added functionality, including:
--   * useful device variables
--   * useful actions
--   * plugin-specific configuration
--   * etc., etc...
--

-- 2016.06.18  add AltAppStore as child device
-- 2016.06.22  remove some dependencies on other modules
--             ...also add DataYours install configuration
-- 2016.11.18  remove HTTP handler
-- 2016.11.20  add system memory stats
-- 2016.12.05  move performance parameters to openLuup.status attribute

-- 2018.02.20  use DisplayLine2 for HouseMode
-- 2018.03.01  register openLuup as AltUI Data Storage Provider
-- 2018.03.18  register with local SMTP server to receive email for openLuup@openLuup.local
-- 2018.03.19  add daily timer for applying file retention policies in openLuup.RetentionPolicies


local json        = require "openLuup.json"
local timers      = require "openLuup.timers"       -- for scheduled callbacks
local vfs         = require "openLuup.virtualfilesystem"
local lfs         = require "lfs"
local url         = require "socket.url"
local socket      = require "socket"                -- for UDP

local INTERVAL = 120
local MINUTES  = "2m"

local SID = {
  openLuup  = "openLuup",                           -- no need for those incomprehensible UPnP serviceIds
  altui     = "urn:upnp-org:serviceId:altui1",      -- Variables = 'DisplayLine1' and 'DisplayLine2'
}

local ole               -- our own device ID
local InfluxSocket      -- for the database

local _log = function (...) luup.log (table.concat ({...}, ' ')) end
local function _debug (...)
  if ABOUT.DEBUG then print (ABOUT.NAME, ...) end
end

--
-- utilities
--

local function round (x, p)
  p = p or 1
  x = x + p / 2
  return x - x % p
end

local function display (line1, line2)
  if line1 then luup.variable_set (SID.altui, "DisplayLine1",  line1 or '', ole) end
  if line2 then luup.variable_set (SID.altui, "DisplayLine2",  line2 or '', ole) end
end

-- slightly unusual parameter list, since source file may be in virtual storage
-- source is an open file handle
local function copy_if_missing (source, destination)
  if not lfs.attributes (destination) then
    local f = io.open (destination, 'wb')
    if f then
      f: write ((source: read "*a"))    -- double parentheses to remove multiple returns from read
      f: close ()
    end
  end
  source: close ()
end


--------------------------------------------------

--
-- vital statistics
--
local cpu_prev = 0

local function set (name, value)
  luup.variable_set (SID.openLuup, name,   value,  ole)
end

local function mem_stats ()
  local y = {}
  local f = io.open "/proc/meminfo"
  if f then
    local x = f: read "*a"
    f: close ()
    for a,b in x:gmatch "([^:%s]+):%s+(%d+)"  do
      if a and b then y[a] = tonumber(b) end
    end
  end
  y.MemUsed  = y.MemTotal and y.MemFree and y.MemTotal - y.MemFree
  y.MemAvail = y.Cached   and y.MemFree and y.Cached   + y.MemFree
  return y
end

local function calc_stats ()
  local AppMemoryUsed =  math.floor(collectgarbage "count")   -- openLuup's memory usage in kB
  local now, cpu = timers.timenow(), timers.cpu_clock()
  local uptime = now - timers.loadtime + 1
  
  local cpuload = round ((cpu - cpu_prev) / INTERVAL * 100, 0.1)
  local memory  = round (AppMemoryUsed / 1000, 0.1)
  local days    = round (uptime / 24 / 60 / 60, 0.01)
  
  cpu_prev= cpu

  set ("Memory_Mb",   memory)
  set ("CpuLoad",     cpuload)
  set ("Uptime_Days", days)

  local line1 = ("%0.0f Mb, cpu %s%%, %s days"): format (memory, cpuload, days)
  display (line1)
  luup.log (line1)
 
  local set_attr = luup.attr_get "openLuup.Status"
  set_attr ["Memory"]  = memory .. " Mbyte"
  set_attr ["CpuLoad"] = cpuload .. '%'
  set_attr ["Uptime"]  = days .. " days"
  
  local y = mem_stats()
  local memfree, memavail, memtotal = y.MemFree, y.MemAvail, y.MemTotal
  if memfree and memavail then
    local mf = round (memfree  / 1000, 0.1)
    local ma = round (memavail / 1000, 0.1)
    local mt = round (memtotal / 1000, 0.1)
    
    set ("MemFree_Mb",  mf)
    set ("MemAvail_Mb", ma)
    set ("MemTotal_Mb", mt)
    
    set_attr["MemFree"]  = mf .. " Mbyte"
    set_attr["MemAvail"] = ma .. " Mbyte"
    set_attr["MemTotal"] = mt .. " Mbyte"
  end
end


--------------------------------------------------
--
-- DataYours install configuration
--
-- set up parameters and a Whisper data directory
-- to start logging some system variables

--[[ 

personal communication from @amg0 on inserting elements into VariablesToSend

... GET with a url like this
"?id=lr_ALTUI_Handler&command={8}&service={0}&variable={1}&device={2}&scene={3}&expression={4}&xml={5}&provider={6}&providerparams={7}".format(
         w.service, w.variable, w.deviceid, w.sceneid,
         encodeURIComponent(w.luaexpr),
         encodeURIComponent(w.xml),
         w.provider,
         encodeURIComponent( JSON.stringify(w.params) ), command)

some comments:
- command is 'addWatch' or 'delWatch'
- sceneid must be -1 for a Data Push Watch
- expression & xml can be empty str
- provider is the provider name ( same as passed during registration )
- providerparams is a JSON stringified version of an array,  which contains its 0,1,2 indexes the values of the parameters that were declared as necessary by the data provider at the time of the registration

the api returns 1 if the watch was added or removed, 0 if a similar watch was already registered before or if we did not remove any

--]]

local function configure_DataYours ()
  _log "DataYours configuration..."
  -- install configuration files from virtual file storage
  lfs.mkdir "whisper/"            -- default openLuup Whisper database location
  copy_if_missing (vfs.open "storage-schemas.conf", "whisper/storage-schemas.conf")
  copy_if_missing (vfs.open "storage-aggregation.conf", "whisper/storage-aggregation.conf")
  copy_if_missing (vfs.open "unknown.wsp", "whisper/unknown.wsp")  -- for blank plots
  
  -- start logging cpu and memory from device #2 by setting AltUI VariablesToSend
  local request = table.concat {
      "http://127.0.0.1:3480/data_request?id=lr_ALTUI_Handler",
      "&command=addWatch", 
      "&service=openLuup",
      "&variable=%s",                 -- variable to watch
      "&device=2",
      "&scene=-1",                    -- Data Push Watch
      "&expression= ",                -- the blank character seems to be important for some systems
      "&xml= ",                       -- ditto
      "&provider=datayours",
      "&providerparams=%s",           -- JSON parameter list
    }
  local memParams = url.escape (json.encode {
      "memory.d",                     -- one day's worth of storage
      "/data_request?id=lr_render&target={0}&title=Memory (Mb)&hideLegend=true&height=250&from=-y",
    })
  local cpuParams = url.escape (json.encode {
      "cpu.d",                        -- one day's worth of storage
      "/data_request?id=lr_render&target={{0},memory.d}&title=CPU (%) Memory (Mb) &height=250&from=-y",
    })
  local dayParams = url.escape (json.encode {
      "uptime.m",                     -- one month's worth of storage
      "/data_request?id=lr_render&target={0}&title=Uptime (days)&hideLegend=true&height=250&from=-y",
    })
  luup.inet.wget (request:format ("Memory_Mb",    memParams))
  luup.inet.wget (request:format ("CpuLoad",      cpuParams))
  luup.inet.wget (request:format ("Uptime_Days",  dayParams))
  _log "...DataYours configured"  
end


local configure = {   -- This is a dispatch list of plug ids which need special configuration
  ["8211"] = configure_DataYours,
  -- more to go here (AltUI??)
}

--
-- generic pre-install configuration actions...
-- ... only performed if there is no installed device of that type.
-- ...called with the plugin metadata as a parameter
--
local function plugin_configuration (_,meta)
  local device = (meta.devices or {}) [1] or {}
  local plugin = meta.plugin or {}
  local device_type = device.DeviceType
  local present = false
  for _,d in pairs (luup.devices) do
    if d.device_type == device_type 
    and d.device_num_parent == 0 then   -- LOCAL device of same type
      present = true
    end
  end
  if not present then 
    local plugin_id = tostring (plugin.id)
    local action = (configure [plugin_id] or function () end) 
    action ()
  end
end

--
-- GENERIC ACTION HANDLER
--
-- called with serviceId and name of undefined action
-- returns action tag object with possible run/job/incoming/timeout functions
--
local function generic_action (serviceId, name)
  
--  local function run (lul_device, lul_settings)
--  local function job (lul_device, lul_settings, lul_job)
  local noop = {
    run = function () _log ("Generic action <run>: ", serviceId, ", ", name) return true end,
    job = function () _log ("Generic action <job>: ", serviceId, ", ", name) return  4,0 end,
  }
  
  local dispatch = {
      plugin_configuration  = {run = plugin_configuration},
      -- add specifics here for other actions
    }
    
  return dispatch[name] or noop
end

------------------------
--
-- register openLuup as an AltUI Data Storage Provider
--
local udp = {

    open = function (ip_and_port)   -- returns UDP socket configured for sending to given destination
      local sock, msg, ok
      local ip, port = ip_and_port: match "(%d+%.%d+%.%d+%.%d+):(%d+)"
      if ip and port then 
        sock, msg = socket.udp()
        if sock then ok, msg = sock:setpeername(ip, port) end         -- connect to destination
      else
        msg = "invalid ip:port syntax '" .. tostring (ip_and_port) .. "'"
      end
      if ok then ok = sock end
      return ok, msg
    end
  }

function openLuup_storage_provider (_, p)
  local influx = "%s value=%s"
  _debug (json.encode {Influx_DSP = {p}})
  if InfluxSocket and p.measurement and p.new then 
    InfluxSocket: send (influx: format (p.measurement, p.new))
  end
end

local function register_Data_Storage_Provider ()
  
  local AltUI
  for devNo, d in pairs (luup.devices) do
    if d.device_type == "urn:schemas-upnp-org:device:altui:1" 
    and d.device_num_parent == 0 then   -- look for it on the LOCAL machine (might be bridged to another!)
      AltUI = devNo
      break
    end
  end
  
  if not AltUI then return end
  
  luup.log ("registering with AltUI [" .. AltUI .. "] as Data Storage Provider")
  luup.register_handler ("openLuup_storage_provider", "openLuup_DSP")
  
  local newJsonParameters = {
    {
        default = "unknown",
        key = "measurement",
        label = "Measurement[,tags]",
        type = "text"
--      },{
--        default = "/data_request?id=lr_" .. MirrorCallback,
--        key = "graphicurl",
--        label = "Graphic Url",
--        type = "url"
      }
    }
  local arguments = {
    newName = "influx",
    newUrl = "http://127.0.0.1:3480/data_request?id=lr_openLuup_DSP",
    newJsonParameters = json.encode (newJsonParameters),
  }

  luup.call_action (SID.altui, "RegisterDataProvider", arguments, AltUI)
end

------------------------
--
-- File Retention Policies
--

-- implement_retention_policies (remove)
-- calls 'remove' function for every file to be deleted
local function implement_retention_policies (policies, remove)

  local function duration (policy)    -- return max age in days for given policy
    local function x(interval) return policy[interval] or 0 end
    local days  = x"days" + 7 * x"weeks" + 30.5 * x"months" + 356 * x"years"
    if days > 0 then return days end
  end

  local age do                        -- return age in days since last modified
    local now = os.time()
    age = function (attributes)
      return (now - attributes.modification) /24 /3600
    end
  end

  local function filetypes (policy)   -- return table of applicable file types
    local types = {}
    for ext in (policy.types or ''): gmatch "%w+" do
      types[ext] = ext
    end
    return types
  end

  local function get_candidates (path, types)   -- return file candidates sorted by age
    local files = {}
    local tmp = path: match "^tmp[/\\]"     -- anything with tmp/... (or tmp\...) path
    for filename in lfs.dir (path) do
      local ext = filename: match "^[^%.].*%.(%w+)$"      -- look for file extension (non-hidden files only)
      if types[ext] or tmp then                           -- valid candidate
        local fullpath = path .. filename
        local a = lfs.attributes (fullpath)
        if a.mode == "file" then
          files[#files+1] = {name = fullpath, age = age(a)}
        end
      end
    end
    table.sort (files, function (a,b) return a.age < b.age end)
    return files
  end

  -- implement_retention_policies()

  local purge = 'retention policy %s*.(%s), age=%s, files=%s'
  for dir, policy in pairs (policies) do
    local a = lfs.attributes (dir)                -- check that path exists
    local is_dir = a and a.mode == "directory"
    local up_dir = dir: match "%.%."              -- remove any attempt to move up directory tree
    
    if is_dir and not up_dir then
      local path = dir:gsub ("[^/]$", '%1/')      -- make sure it ends with a '/'
      local types = filetypes (policy)
      local files = get_candidates (path, types)
      local max_age = duration (policy) 
      local max_files = policy.maxfiles
      _log (purge: format (path, policy.types or '', max_age or "unlimited", max_files or "unlimited"))
      
      -- apply max file policy
      if max_files then
        for i = #files, policy.maxfiles+1, -1 do
          local file = files[i]
          _log (("delete #%d %s"): format (i, file.name))
          remove (file.name)
          files[i] = nil
        end
      end
      
      -- apply max age policy
      if max_age then
        for _, file in ipairs (files) do
          if file.age > max_age then
            _log (("delete %0.0f days %s"): format(file.age, file.name))
            remove (file.name)
          end      
        end      
      end
    
    end
  end
end


------------------------
--
-- init()
--
local modeName = {"Home", "Away", "Night", "Vacation"}
local modeLine = "[%s]"

local function displayHouseMode (Mode)
  if not Mode then
    Mode = luup.variable_get (SID.openLuup, "HouseMode", ole)
  end
  Mode = tonumber(Mode)
  display (nil, modeLine: format(modeName[Mode]))
end

function openLuup_watcher (_, _, var, _, Mode)    -- 2018.02.20
  if var == "HouseMode" then
    displayHouseMode (Mode)
  end
end

function openLuup_ticker ()
  calc_stats()
  -- might want to do more here...
end

function openLuup_synchronise ()
  local days, data                      -- unused parameters
  local timer_type = 1                  -- interval timer
  local recurring = true                -- reschedule automatically, definitely not a Vera luup option! ... 
                          -- ...it ensures that rescheduling is always on time and does not 'slip' between calls.
  luup.log "synchronising to on-the-minute"
  luup.call_timer ("openLuup_ticker", timer_type, MINUTES, days, data, recurring)
  luup.log "2 minute timer launched"
  calc_stats ()
end

-- 2018.03.19  apply retention policies on a daily basis
function openLuup_retention_policies ()
  luup.log "applying file retention policies..."
  local policies = luup.attr_get "openLuup.RetentionPolicies"
  local remove = os.remove      -- use system's remove function to delete expired files
  implement_retention_policies (policies, remove)
  luup.log "...finished file retention policies"
end

-- 2018.03.18  receive email for openLuup@openLuup.local
function openLuup_email (email, data)
  -- do nothing at the moment
  -- but it's important that this handler is registered,
  -- so that email sent to this address will be accepted by the server.
end

-- 2018.03.18  receive and store email images for images@openLuup.local
function openLuup_image (email, data)
  local message = data: decode ()             -- decode MIME message
  if type (message.body) == "table" then      -- must be multipart message
    local n = 0
    for _, part in ipairs (message.body) do
      local ContentType = part.header["content-type"] or "text/plain"
      local ctype = ContentType: match "^%w+/%w+" 
      local cname = ContentType: match 'name="([^"]+)"'
      if cname and ctype: match "image" then    -- write out image files
        local f = io.open ("images/" .. cname, 'wb') 
        if f then
          n = n + 1
          f: write (part.body)
          f: close ()
        end
      end
    end
    if n > 0 then 
      local saved = "%s: saved %d image files"
      _log (saved: format(email, n))
    end
  end
end

function init (devNo)
  local msg
  ole = devNo
  displayHouseMode ()
  
  do -- timed callbacks
    
    -- synchronised heartbeat
    local later = timers.timenow() + INTERVAL         -- some minutes in the future
    later = INTERVAL - later % INTERVAL               -- adjust to on-the-hour (actually, two-minutes)
    luup.call_delay ("openLuup_synchronise", later)
    msg = ("synch in %0.1f s"): format (later)
    luup.log (msg)
    
    -- 2018.03.19  folder retention policies on a daily basis
    local timer_type = 2          -- day of week timer
    local time = "03:30:00"       -- 3:30 AM
    local days = "1,2,3,4,5,6,7"  -- every day of the week
    local data = ''
    local recurring = true
    luup.call_timer ("openLuup_retention_policies", timer_type, time, days, data, recurring)
    luup.log "started daily file retention policy job"
  
  end

  do -- version number
    local y,m,d = ABOUT.VERSION:match "(%d+)%D+(%d+)%D+(%d+)"
    local version = ("v%d.%d.%d"): format (y%2000,m,d)
    luup.variable_set (SID.openLuup, "Version", version,  ole)
    luup.log (version)
    local info = luup.attr_get "openLuup"
    info.Version = version      -- put it into openLuup table too.
  end

  do -- callback handlers
--    luup.register_handler ("HTTP_openLuup", "openLuup")
--    luup.register_handler ("HTTP_openLuup", "openluup")     -- lower case
    luup.devices[devNo].action_callback (generic_action)      -- catch all undefined action calls
    luup.variable_watch ("openLuup_watcher", SID.openLuup, "HouseMode", ole)  -- 2018.02.20
    luup.register_handler ("openLuup_email", "openLuup@openLuup.local")       -- 2018.03.18
    luup.register_handler ("openLuup_image", "images@openLuup.local")         -- 2018.03.18
  end

  do -- install AltAppStore as child device
    local ptr = luup.chdev.start (devNo)
    local altid = "AltAppStore"
    local description = "Alternate App Store"
    local device_type = "urn:schemas-upnp-org:device:AltAppStore:1"
    local upnp_file = "D_AltAppStore.xml"
    local upnp_impl = "I_AltAppStore.xml"
    luup.chdev.append (devNo, ptr, altid, description, device_type, upnp_file, upnp_impl)
    luup.chdev.sync (devNo, ptr)  
  end  
  
  do -- InfluxDB as Data Storage Provider 
    local dsp = "InfluxDB Data Storage Provider: "
    local db = luup.attr_get "openLuup.Databases.Influx"
    if db then
      local err
      register_Data_Storage_Provider ()   -- 2018.03.01
      InfluxSocket, err = udp.open (db)
      if InfluxSocket then 
        _log (dsp .. tostring(InfluxSocket))
      else
        _log (dsp .. (err or '')) end
    end
  end
  
  calc_stats ()
  
  return true, msg, ABOUT.NAME
end

-----
