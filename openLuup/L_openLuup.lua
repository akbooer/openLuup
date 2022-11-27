ABOUT = {
  NAME          = "L_openLuup",
  VERSION       = "2022.11.27",
  DESCRIPTION   = "openLuup device plugin for openLuup!!",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2022 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  FORUM         = "https://smarthome.community/",
  DONATE        = "https://www.justgiving.com/DataYours/",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2022 AK Booer

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
--   * SMTP mail handlers
--   * Data Storage Provider gateways
--   * Retention policy implementation for directories
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
-- 2018.03.21  add SendToTrash and EmptyTrash actions to apply file retention policies
-- 2018.03.25  set openLuup variables without logging (but still trigger watches)
--             ...also move UDP open() to io.udp.open()
-- 2018.03.28  add application Content-Type to images@openLuup.local handler
-- 2018.04.02  fixed type on openLuup_images - thanks @jswim788!
-- 2018.04.08  use POP3 module to save email to mailbox. Add events mailbox folder
-- 2018.04.15  fix number types in SendToTrash action
-- 2018.05.02  add StartTime device variable, also on Control panel (thanks @rafale77)
-- 2018.05.16  SendToTrash applied to the trash/ folder will DELETE selected files
-- 2018.06.11  Added Vnumber (purely numeric six digit version number yymmdd) for @rigpapa
-- 2018.08.30  fixed nil ctype in openLuup_images (thanks @ramwal)

-- 2019.04.18  remove generic plugin_configuration functionality (no longer required)

-- 2020.02.20  add EmptyRoom101 service action

-- 2021.04.06  add MQTT device/variable PUBLISH, and broker stats
-- 2021.04.08  only PUBLISH if MQTT configured (thanks @ArcherS)
-- 2021.05.20  use carbon cache to archive historian and mqtt server metrics
-- 2021.05.23  add solar RA,DEC and ALT,AZ plus GetSolarCoords service with options (Unix) epoch parameter


local json        = require "openLuup.json"
local timers      = require "openLuup.timers"       -- for scheduled callbacks
local ioutil      = require "openLuup.io"           -- NOT the same as luup.io or Lua's io.
local pop3        = require "openLuup.pop3"
local hist        = require "openLuup.historian"    -- for metrics archive

local lfs         = require "lfs"
local smtp        = require "socket.smtp"             -- smtp.message() for formatting events

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

-- GLOBALS (just for fun, to show up in Console Globals page)

_G["Memory Used (Mb)"]  = 0
_G["Uptime (days)"]     = 0
_G["CPU Load (%)"]      = 0

--
-- utilities
--

local function round (x, p)
  p = p or 1
  x = x + p / 2
  return x - x % p
end

local function set (name, value, sid)
  local watch = true
--  luup.variable_set (SID.openLuup, name,   value,  ole)
  luup.devices[ole]:variable_set (sid or SID.openLuup, name, value, watch)    -- 2018.03.25  silent setting (but watched)
end

local function display (line1, line2)
  if line1 then set ("DisplayLine1",  line1 or '', SID.altui) end
  if line2 then set ("DisplayLine2",  line2 or '', SID.altui) end
end


--------------------------------------------------

--
-- vital statistics
--
local cpu_prev = 0

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
  
  local cpu_load = round ((cpu - cpu_prev) / INTERVAL * 100, 0.1)
  local memory_mb  = round (AppMemoryUsed / 1000, 0.1)
  local uptime_days    = round (uptime / 24 / 60 / 60, 0.01)
  cpu_prev= cpu
  
  -- store the results as module globals
  _G["Memory Used (Mb)"]  = memory_mb
  _G["Uptime (days)"]     = uptime_days
  _G["CPU Load (%)"]      = cpu_load
  
  -- store the results as device variables
  set ("Memory_Mb",   memory_mb)
  set ("CpuLoad",     cpu_load)
  set ("Uptime_Days", uptime_days)

  local line1 = ("%0.0fMb, %s%%cpu, %0.1fdays"): format (memory_mb, cpu_load, uptime_days)
  display (line1)
  luup.log (line1)
 
  -- store the results as top-level system attributes
  local set_attr = luup.attr_get "openLuup.Status"
  set_attr ["Memory"]  = memory_mb .. " Mbyte"
  set_attr ["CpuLoad"] = cpu_load .. '%'
  set_attr ["Uptime"]  = uptime_days .. " days"
  
  -- system memory info
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
--      plugin_configuration  = {run = plugin_configuration},
      -- add specifics here for other actions
    }
    
  return dispatch[name] or noop
end

------------------------
--
-- register openLuup as an AltUI Data Storage Provider
--

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

-- implement_retention_policies (policies, process)
-- calls 'process' function for every matching file
-- policies is a table of the form:
--[[
    { 
      [folderName1] = {types = "jpg gif tmp", days=1, weeks=1, months=1, years=1, maxfiles=42},
      [folderName2] = {types = "*", weeks=3, maxfiles=42},
      [...]
    }
--]]

local function implement_retention_policies (policies, process)

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
    for ext in (policy.types or ''): gmatch "[%*%w]+" do
      types[ext] = ext
    end
    return types
  end

  local function get_candidates (path, types)   -- return file candidates sorted by age
    local files = {}
    local wildcard = types['*']                          -- anything goes
    for filename in lfs.dir (path) do
      local hidden = filename: match "^%."                -- hidden files start with '.'
      local ext = filename: match "%.(%w+)$"              -- file extensions end with ".xxx'
      if not hidden and (types[ext] or wildcard) then     -- valid candidate
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

  local purge = "retention policy %s*.(%s), age=%s, #files=%s"
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
          _log (("select #%d %s"): format (i, file.name))
          process (file.name)
          files[i] = nil
        end
      end
      
      -- apply max age policy
      if max_age then
        for _, file in ipairs (files) do
          if file.age > max_age then
            _log (("select %0.0f day old %s"): format(file.age, file.name))
            process (file.name)
          end      
        end      
      end
    
    end
  end
end

------------------------
--
-- ACTIONS
--

-- 2018.03.21  SendToTrash
--
--  Parameters: 
--    Folder    (string) path of folder below openLuup current directory
--    MaxDays   (number) maximum age of files (days) to retain
--    MaxFiles  (number) maximum number of files to retain
--    FileTypes (string) one or more file extensions to apply, or * for anything
--
function SendToTrash (p)
  
  local function trash (file)
    local filename = file: match "[/\\]*([^/\\]+)$"    -- ignore leading path to leave just the filename
    os.rename (file, "trash/" .. filename)
  end
  
  -- try to protect ourself from any damage!
  local locked = {"openLuup", "cgi", "cgi-bin", "cmh", "files", "history", "icons", "whisper", "www"}
  local prohibited = {}
  for _, dir in ipairs(locked) do prohibited[dir] = dir end   -- turn list into indexed table
  
  local folder = (p.Folder or ''): match "^[%./\\]*(.-)[/\\]*$" -- just pull out the relevant path
  if prohibited[folder] then
    luup.log ("cannot select files in protected folder " .. tostring(folder))
    return
  end
  
  if folder then
    luup.log "applying file retention policy..."
    local days = tonumber (p.MaxDays)               -- 2018.04.15
    local maxfiles = tonumber (p.MaxFiles)
    local policy = {[folder] = {types = p.FileTypes, days = days, maxfiles = maxfiles}}
    local process = trash
    if folder == "trash" then process = os.remove end   -- actually DELETE files if policy applied to trash/
    implement_retention_policies (policy, process)
    luup.log "...finished applying file retention policy"
  end
end

function EmptyTrash (p)
  local yes = p.AreYouSure or ''
  if yes: lower() == "yes" then
    local n = 0
    luup.log "emptying trash/ folder..."
    for file in lfs.dir "trash" do
      local hidden = file: match "^%."                -- hidden files start with '.'
      if not hidden then
        local ok,err = os.remove ("trash/" .. file)
        if ok then
          n = n + 1
--          luup.log ("deleted " .. file)
        else
          luup.log ("unable to delete " .. file .. " : " .. (err or '?'))
        end
      end
    end
    luup.log (n .. " files permanently deleted from trash")
  end
end


function EmptyRoom101 (p)           -- 2020.02.20
  local yes = p.AreYouSure or ''
  if yes: lower() == "yes" then
    local n = 0
    luup.log "deleting devices in Room 101..."
    for devNo,d in pairs (luup.devices) do
      if d.room_num == 101 then
        luup.devices[devNo] = nil
        n = n + 1
      end
    end
    luup.log (n .. " devices deleted")
  end
end

------------------------
--
-- MQTT updates
--

local mqtt_devnums, mqtt_next

local function get_next_dev ()
  if not mqtt_devnums then
    mqtt_devnums = {}
    for n in pairs(luup.devices) do
      mqtt_devnums[#mqtt_devnums + 1] = n
    end
    mqtt_next = 1
  end
  local dev = luup.devices[mqtt_devnums[mqtt_next]]
  mqtt_next = mqtt_next + 1
  if mqtt_next > #mqtt_devnums then mqtt_devnums = nil end
  return dev    -- may be nil, if device was recently deleted
end

local function mqtt_dev_json (d)
  local info = {}
  for _, srv in pairs(d.services) do
    local s = {}
    info[srv.shortSid] = s
    for v, var in pairs (srv.variables) do
      s[v] = var.value
    end
  end

  local D = {[tostring(d.devNo)] = info}
  local message = json.encode(D)
  return message
end

local function mqtt_round_robin ()
  local mqtt = luup.openLuup.mqtt
  local dt = luup.attr_get "openLuup.MQTT.PublishDeviceStatus" or "0"
  if dt == "0" then 
    dt = 10    -- set default delay time to check for changes
  elseif mqtt then
    local dd = get_next_dev ()
    if dd then
      local message = mqtt_dev_json (dd)
      mqtt.publish ("openLuup/status", message)
    end
  end
  dt = tonumber (dt)
  timers.call_delay (mqtt_round_robin, dt, '', "MQTT openLuup/status")
end


-- see: https://mosquitto.org/man/mosquitto-8.html
local function mqtt_sys_broker_stats ()
  local mqtt = luup.openLuup.mqtt
  local prefix = "$SYS/broker/"
  -- augment client stats
  local stats = mqtt.statistics
  local nc = 0
  for _ in pairs(mqtt.iprequests) do nc = nc + 1 end    -- count the clients
  stats["clients/total"] = nc
  stats["clients/connected"] = nc
  stats["clients/maximum"] = math.max (stats["clients/maximum"], nc)
  
  local rmc = 0
  for _ in pairs (mqtt.retained) do rmc = rmc + 1 end   -- count the retained messages
  stats["retained/messages/count"] = rmc

  if luup.attr_get "openLuup.MQTT" then   -- 2021.04.08 only publish if MQTT configured
    local mqtt_carbon = hist.CarbonCache["mqtt"]
    for n, v in pairs (stats) do
      mqtt.publish (prefix..n, tostring(v))
      if mqtt_carbon then
        mqtt_carbon.update ("broker."..n: gsub ('/','.'), v)   -- 2021.05.20 add to graphite archives
      end
    end
  end
  timers.call_delay (mqtt_sys_broker_stats, 60, '', "MQTT $SYS/broker/#")
end


------------------------
--
-- Carbon metrics
--
local function carbon_metrics ()
  local carbon_cache = hist.CarbonCache["carbon"]
  if carbon_cache then
    local stats = hist.stats 
    carbon_cache.update ("agents.historian.updateOperations", stats.total_updates)
  end
end

------------------------
--
-- Sun position updates (cf. Heliotrope plugin)
--
local function sun_position (t, lat, lng)
  local function sol (n,v)
    v = ("%0.3f"): format(v)
    set (n,v, "solar")
  end
  local RA,DEC,ALT,AZ = timers.util.sol_rdaa(t, lat, lng)
  sol ("RA", RA)
  sol ("DEC", DEC)
  sol ("ALT", ALT)
  sol ("AZ", AZ)
end

-- GetSolarCoords action
function GetSolarCoords (p)
  local t = tonumber (p.Epoch)
  local lat = tonumber (p.Latitude)
  local lng = tonumber (p.Longitude)
  sun_position (t, lat, lng)              -- update parameters, which are then returned by the service
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
  display (nil, modeLine: format(modeName[Mode] or ''))
end

function housemode_watcher (_, _, var, _, Mode)    -- 2018.02.20
  if var == "HouseMode" then
    displayHouseMode (Mode)
  end
end

function openLuup_ticker ()
  calc_stats()
  sun_position()
  carbon_metrics()
  -- might want to do more here...
  -- TODO: update gmt_offset system attribute? (to accommodate DST change)
end

function openLuup_synchronise ()
  local days, data                      -- unused parameters
  local timer_type = 1                  -- interval timer
  local recurring = true                -- reschedule automatically, definitely not a Vera luup option! ... 
                          -- ...it ensures that rescheduling is always on time and does not 'slip' between calls.
  luup.log "synchronising to on-the-minute"
  luup.call_timer ("openLuup_ticker", timer_type, MINUTES, days, data, recurring)
  luup.log "2 minute timer launched"
  openLuup_ticker ()
end

-- 2018.03.18  receive email for openLuup@openLuup.local
function openLuup_email (email, data)
  local _,_ = email, data
  -- do nothing at the moment
  -- but it's important that this handler is registered,
  -- so that email sent to this address will be accepted by the server.
end

-- 2018.03.18  receive and store email images for images@openLuup.local
function openLuup_images (email, data)
  local function log (...) _log ("openLuup.images", ...) end
  local message = data: decode ()             -- decode MIME message
  if type (message.body) == "table" then      -- must be multipart message
    local n = 0
    for i, part in ipairs (message.body) do
      
      local ContentType = part.header["content-type"] or "text/plain"
      local ctype = ContentType: match "^%w+/%w+" 
      local cname = ContentType: match 'name%s*=%s*"?([^/\\][^"]+)"?'   -- avoid absolute paths
      if cname and cname: match "%.%." then cname = nil end           -- avoid any attempt to move up folder tree
      cname = cname or os.date "Snap_%Y%m%d-%H%M%S-" .. i .. ".jpg"   -- make up a name if necessary      
      log ("Content-Type:", ContentType) 
      
      ctype = ctype or ''                     -- 2018.08.30
      if (ctype: match "image")               -- 2018.03.28  add application type
      or (ctype: match "application") then    -- write out image files  (thanks @jswim788)
        local f, err = io.open ("images/" .. cname, 'wb') 
        if f then
          n = n + 1
          f: write (part.body)
          f: close ()
        else
          log ("ERROR writing:", cname, ' ', err)
        end
      end
    end
    if n > 0 then 
      local saved = "%s: saved %d image files"
      _log (saved: format(email, n))
    else
      _log "no image attachments found"
    end
  end
end

-- save message to mailbox
local function save_message (path, mailbox, data)
  local function log (...) _log (mailbox, ...) end
  local mbx = pop3.mailbox.open (path)
  local id, err = mbx: write (data)
  if id then
    log ("saved email message id: " .. id)
  else
    log ("ERROR saving email message: " .. (err or '?'))
  end
  mbx: close()

end

-- real mailbox
function openLuup_mailbox (...)
  save_message ("mail/", ...)
end

-- events mailbox
-- just stores the key headers of of incoming mail
function openLuup_events (mailbox, data)
  local message = data: decode ()             -- decode MIME message
  local headers = message.header
  
  local newHeaders = {["content-type"] = "text/plain"}    -- vanilla message
  for a,b in pairs (headers) do 
    if type(a) == "string" and not a: match "^content" then
      newHeaders[a] = b
    end
  end
  newHeaders.subject = newHeaders.subject or "---no subject---"
  
  local newData = {}
  for a in smtp.message {headers = newHeaders, body = ''} do    -- no body text
      newData[#newData+1] = a: gsub ('\r','')                   -- remove redundant <CR>
  end

  save_message ("events/", mailbox, newData)
end


function init (devNo)
  local msg
  ole = devNo
  displayHouseMode ()

  do -- version number
    local y,m,d = ABOUT.VERSION:match "(%d+)%D+(%d+)%D+(%d+)"
    local version = ("v%d.%d.%d"): format (y%2000,m,d)
    local Vnumber = tonumber ((y%2000)..m..d)
    set ("Version", version)
    set ("Vnumber", Vnumber)
    luup.log (version)
    local info = luup.attr_get "openLuup"
    info.Version = version      -- put it into openLuup table too.
    info.Vnumber = Vnumber      -- ditto --
  end
  
  do -- synchronised heartbeat
    local later = timers.timenow() + INTERVAL         -- some minutes in the future
    later = INTERVAL - later % INTERVAL               -- adjust to on-the-hour (actually, two-minutes)
    luup.call_delay ("openLuup_synchronise", later)
    msg = ("sync in %0.1f s"): format (later)
    luup.log (msg)
  end
  
  do -- callback handlers
--    luup.register_handler ("HTTP_openLuup", "openLuup")
--    luup.register_handler ("HTTP_openLuup", "openluup")     -- lower case
    luup.devices[devNo].action_callback (generic_action)      -- catch all undefined action calls
    luup.variable_watch ("housemode_watcher", SID.openLuup, "HouseMode", ole) -- 2018.02.20
    luup.register_handler ("openLuup_email", "openLuup@openLuup.local")       -- 2018.03.18  bit bucket
    luup.register_handler ("openLuup_images", "images@openLuup.local")        -- 2018.03.18  save images
    luup.register_handler ("openLuup_events", "events@openLuup.local")        -- 2018.03.18  save events
    luup.register_handler ("openLuup_mailbox", "mail@openLuup.local")         -- 2018.04.02  actual mailbox
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
    local db = luup.attr_get "openLuup.DataStorageProvider.Influx"
    if db then
      local err
      register_Data_Storage_Provider ()   -- 2018.03.01
      InfluxSocket, err = ioutil.udp.open (db)
      if InfluxSocket then 
        _log (dsp .. tostring(InfluxSocket))
      else
        _log (dsp .. (err or '')) 
      end
    end
  end
  
  do -- MQTT updates
    local p = luup.attr_get "openLuup.MQTT.PublishVariableUpdates"
    if p == "true" then
      luup.log "starting MQTT round-robin device status messages"
    end
    mqtt_round_robin ()   -- ... but start the timer anyway, in case it's turned on later
    luup.log "starting MQTT $SYS/broker statistics"
    mqtt_sys_broker_stats ()
  end
  
  set ("StartTime", luup.attr_get "openLuup.Status.StartTime")        -- 2018.05.02
  openLuup_ticker ()
  
  return true, msg, ABOUT.NAME
end

-----
