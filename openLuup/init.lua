local ABOUT = {
  NAME          = "openLuup.init",
  VERSION       = "2024.03.02",
  DESCRIPTION   = "initialize Luup engine with user_data, run startup code, start scheduler",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2024 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-2024 AK Booer

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
-- openLuup - Initialize Luup engine
--  

-- 2016.05.12  moved load_user_data from this module to userdata
-- 2016.06.08  add 'altui' startup option to do new install
-- 2016.06.09  add files/ directory to Lua search path
-- 2016.06.18  add openLuup/ directory to Lua search path
-- 2016.06.19  switch to L_AltAppStore module for initial AltUI download
-- 2016.06.30  uncompress user_data file if necessary
-- 2016.07.19  correct syntax error in xml action request response
-- 2016.11.18  add delay callback name

-- 2017.01.05  add new line before end of Startup Lua (to guard against unterminated final comment line)
-- 2017.03.15  add Server.Backlog parameter to openLuup attribute (thanks @explorer)
-- 2017.04.10  add Logfile.Incoming parameter to openLuup attribute (thanks @a-lurker)
-- 2017.06.14  add Server.WgetAuthorization for wget header basic authorization or URL-style

-- 2018.01.18  add openLuup.Scenes prolog and epilog parameters
-- 2018.02.05  move scheduler callback handler initialisation from here to request module
-- 2018.02.19  add current directory to startup log
-- 2018.02.25  add ip address to openLuup.Server
-- 2018.03.09  add SMTP server
-- 2018.04.04  add POP3 server
-- 2018.04.23  re-order module loading (to tidy startup log banners)
-- 2018.04.25  change server module name back to http, and use openLuup.HTTP... attributes
-- 2018.05.25  add Data Historian configuration
-- 2018.05.29  remove HTTP.WgetAuthorization option
-- 2018.06.14  rename openLuup.Databases to openLuup.DataStorageProvider

-- 2019.03.14  change openLuup parameter comment style
-- 2019.06.12  move compile_and_run to loader (to be used also by console)
-- 2019.06.14  add Console options
-- 2019.07.31  use new server module (name reverted from http)
-- 2019.10.14  set HTTP client port with client.start()

-- 2020.03.18  report correct HTTP port in startup error message
-- 2020.04.03  use optional arg[2] to define HTTP server port
-- 2020.04.23  update Ace editor link to https://cdnjs.cloudflare.com/ajax/libs/ace/1.4.11/ace.js
-- 2020.05.01  log json module version info (thanks @a-lurker)
-- 2020.07.04  use proxy for require()

-- 2021.01.30  add MQTT server and Shelly bridge
-- 2021.03.02  update Ace editor link to https://cdnjs.cloudflare.com/ajax/libs/ace/1.4.12/ace.js
-- 2021.03.11  add devutil.PublishVariableUpdates (true)
-- 2021.04.02  change ShellyBridge initialisation, add prototype Tasmota bridge
-- 2021.04.30  substitute dkjson with RapidJSON, if available.
-- 2021.05.06  move require() proxy to openLuup.loader
-- 2021.05.21  add config.MQTT.Carbon for Graphite database MQTT stats
-- 2021.06.21  add config.Tasmota

-- 2022.11.07  update Ace editor link to https://cdnjs.cloudflare.com/ajax/libs/ace/1.12.5/ace.js

-- 2024.01.06  global environment prototype moved to scheduler from loader
-- 2024.02.23  update Ace editor link to https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.6/ace.js
-- 2024.03.02  tidy up obsolete files in openLuup/


local logs  = require "openLuup.logs"
local lfs   = require "lfs"
local json  = require "openLuup.json"

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end
_log (lfs.currentdir(),":: openLuup STARTUP ")
logs.banner (ABOUT)   -- for version control

local scheduler   = require "openLuup.scheduler"  -- keep this first... it prototypes the global environment
local loader      = require "openLuup.loader"

luup = require "openLuup.luup"            -- here's the GLOBAL luup environment

loader.req_table {dkjson = json.Rapid}    -- list require module proxies
  
local client        = require "openLuup.client"     -- HTTP client
local server        = require "openLuup.server"     -- HTTP server
local smtp          = require "openLuup.smtp"
local pop3          = require "openLuup.pop3"
local mqtt          = require "openLuup.mqtt"
local timers        = require "openLuup.timers"
local userdata      = require "openLuup.userdata"
local compress      = require "openLuup.compression"
local historian     = require "openLuup.historian"
local devutil       = require "openLuup.devices"      -- for devutil.PublishVariableUpdates()

local mime  = require "mime"

logs.banner (compress.ABOUT)    -- doesn't announce itself
logs.banner (timers.ABOUT)      -- ditto
logs.banner (logs.ABOUT)        -- ditto
logs.banner (json.ABOUT)

-- heartbeat monitor for memory usage and checkpointing
local chkpt = 1
local function openLuupPulse ()
  chkpt = chkpt + 1
  local delay = tonumber (luup.attr_get "openLuup.UserData.Checkpoint") or 6  -- periodic pulse ( default 6 minutes)
  timers.call_delay(openLuupPulse, delay*60, '', 'openLuup checkpoint #' .. chkpt)  
  -- CHECKPOINT !
  local name = (luup.attr_get "openLuup.UserData.Name") or "user_data.json"
  local ok, msg = userdata.save (luup, name)
  if not ok then
    _log (msg or "error writing user_data")
  end
  collectgarbage()                          -- tidy up a bit
end

--
-- INIT STARTS HERE
--

do -- change search paths for Lua require
  local cmh_lu = ";../cmh-lu/?.lua;files/?.lua;openLuup/?.lua"
  package.path = package.path .. cmh_lu       -- add /etc/cmh-lu/ to search path
end

do -- Devices 1 and 2 are the Vera standard ones (but #2, _SceneController, replaced by openLuup)
  luup.attr_set ("Device_Num_Next", 1)  -- this may get overwritten by a subsequent user_data load

  local device_type, int_id, descr, upnp_file, upnp_impl, ip, mac, hidden, invisible, parent, room, pluginnum
  local _ = {device_type, int_id, descr, upnp_file, upnp_impl, ip, mac, hidden, invisible, parent, room, pluginnum}
  invisible = true
  luup.create_device ("urn:schemas-micasaverde-com:device:ZWaveNetwork:1", '',
    "ZWave", "D_ZWaveNetwork.xml", upnp_impl, ip, mac, hidden, invisible)
--  luup.create_device ("urn:schemas-micasaverde-com:device:SceneController:1", '',
--                      "_SceneController", "D_SceneController1.xml", nil, nil, nil, nil, invisible, 1)
  invisible = false
  luup.create_device ("openLuup", '', "    openLuup", "D_openLuup.xml",
                        upnp_impl, ip, mac, hidden, invisible, parent, room, "openLuup")
end

do -- set attributes, possibly decoding if required
  local set_attr = userdata.attributes 
  set_attr["openLuup"] = {  -- note that any of these may be changed by Lua Startup before being used
    Backup = {
      Compress = "LZAP",
      Directory = "backup/",
    },
    Console = {
      Menu = "",           -- add user-defined menu JSON definition file here
--      Ace_URL = "https://cdnjs.cloudflare.com/ajax/libs/ace/1.12.5/ace.js",
      Ace_URL = "https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.6/ace.js",
      EditorTheme = "eclipse",
    },
    DataStorageProvider = {
      ["-- Influx"]   = "172.16.42.129:8089",
      ["-- Graphite"] = "127.0.0.1:2003",
    },
    Logfile = {
      Name      = "logs/LuaUPnP.log",
      Lines     = 2000,
      Versions  = 5,
      Incoming  = "true",
    },
    Status = {
      IP = server.myIP,
      StartTime = os.date ("%Y-%m-%dT%H:%M:%S", timers.loadtime),
    },
    UserData = {
      Checkpoint  = 60,                   -- checkpoint every sixty minutes
      Name        = "user_data.json",     -- not recommended to change
    },
    Historian = {
      CacheSize = 1024,                   -- in-memory cache size (per variable) (allows 7 days of 10 min)
      ["-- Directory"] = "history/",      -- on-disc archive folder
      ["-- DataYours"] = "whisper/",      -- DataYours whisper folder
      ["-- Carbon"] = "graphite/carbon/", -- CarbonCache for Historian server stats
      Graphite_UDP  = '',
      InfluxDB_UDP  = '',
    },
    HTTP = {
      Backlog = 2000,                     -- used in socket.bind() for queue length
      ChunkedLength = 16000,              -- size of chunked transfers
      CloseIdleSocketAfter = 90,          -- number of seconds idle after which to close socket
      SelectWait = 0.1,                   -- seconds to wait for socket ready to send
    },
    SMTP = {
      Backlog = 100,                      -- RFC 821 recommended minimum queue length
      CloseIdleSocketAfter = 300,         -- number of seconds idle after which to close socket
      Port = 2525,
    },
    POP3 = {
      Backlog = 32,
      CloseIdleSocketAfter = 600,         -- RFC 1939 minimum value for autologout timer
      Port = 11011,
    },
-- not, by default, enabled
--    MQTT = {
--      Backlog = 100,
--      CloseIdleSocketAfter = 120,
--      Port = 1883,
--      Carbon = "graphite/mqtt/"          -- CarbonCache for MQTT server stats
--      Bridge_UDP = 2883,
--      PublishVariableUpdates = "true",  -- publish /update/ messages for individual variable changes
--      PublishDeviceStatus = 2,          -- publish a single device status every N seconds (0 = never)
--    },
    Scenes = {
      -- Prolog/Epilog are global function names to run before/after ALL scenes
      Prolog = '',                        -- name of global function to call before any scene
      Epilog = '',                        -- ditto, after any scene
    },
    Tasmota = {
      Prefix = "tele, tasmota/tele, stat",
      Topic  = "SENSOR, STATE, RESULT, LWT",
    },
    Zigbee = {
      Prefix = "zigbee2mqtt",
    },
  }
  local attrs = {attr1 = "(%C)(%C)", 0x5F,0x4B, attr2 = "%2%1", 0x45,0x59}
  local attr = string.char(unpack (attrs))
  loader.shared_environment[attr] = function (info)
    info = (info or ''): gsub (attrs.attr1,attrs.attr2)
    local u = mime.unb64(info)  
    local decoded = json.decode(u) or {} 
    for a,b in pairs (decoded) do
      set_attr[a] = b
    end
  end
end

do -- STARTUP   
  local init = arg[1] or "user_data.json"         -- optional parameter: Lua or JSON startup file
  _log ("loading configuration ".. init)
  
  if init == "reset" then luup.reload () end      -- factory reset
  
  if init == "altui" then                         -- install altui in reset system
    -- this is a bit tricky, since the scheduler is not running at this stage
    -- but we need to execute a multi-step action with <run> and <job> tags...
    userdata.attributes.InstalledPlugins2 = userdata.default_plugins
    require "openLuup.L_AltAppStore"                    -- manually load the plugin updater
    AltAppStore_init (2)                                -- give it a device to work with
    local meta = userdata.plugin_metadata (8246)        -- AltUI plugin number
    local metadata = json.encode (meta)                 -- get the metadata
    update_plugin_run {metadata = metadata}             -- <run> phase
    repeat until update_plugin_job () ~= 0              -- <job> phase
  end

  local f = io.open (init, 'rb')                          -- may be binary compressed file 
  if f then 
    local code = f:read "*a"
    f:close ()
    if code then
    
      if init: match "%.lzap$" then                       -- it's a compressed user_data file
        local codec = compress.codec (nil, "LZAP")        -- full-width binary codec with header text
        code = compress.lzap.decode (code, codec)         -- uncompress the file
      end

      local ok, err
      local json_code = code: match "^%s*{"               -- what sort of code is this?
      if json_code then 
        ok = userdata.load (code)
        code = userdata.attributes ["StartupCode"] or ''  -- substitute the Startup Lua
      end
      local name = "_openLuup_STARTUP_"
      _log ("running " .. name)
      ok, err = loader.compile_and_run (code, name)        -- the given file or the code in user_data
      if not ok then _log ("ERROR: " .. err) end
   else
      _log "no init data"
    end
  else
    _log "init file not found"
  end
end

local config = userdata.attributes.openLuup or {}

do -- log rotate and possible rename
  _log "init phase completed"
  logs.rotate (config.Logfile or {})
  _log "init phase completed"
end
  
do -- ensure some extra folders exist
   -- note that the ownership/permissions may be 'system', depending on how openLuup is started
  lfs.mkdir "events"
  lfs.mkdir "history"
  lfs.mkdir "images"
  lfs.mkdir "mail"
  lfs.mkdir "trash"
  lfs.mkdir "www"
end

do -- tidy up obsolete files
  os.remove "openLuup/rooms.lua"
  os.remove "openLuup/hag.lua"
  os.remove "openLuup/http.lua"
  os.remove "openLuup/shelly_cgi.lua"
end

local status

do --	 SERVERs and SCHEDULER
  local port = tonumber(arg[2]) or config.HTTP.Port or 3480     -- port 3480 is default
  config.HTTP.Port = port
  local s = server.start (config.HTTP)      -- start the Web server
  client.start (config.HTTP)                -- and tell the client which ACTUAL port to use!
  if not s then 
    error ("openLuup - is another copy already running?  Unable to start HTTP server on port " .. port)
  end
  
  if config.SMTP then smtp.start (config.SMTP) end

  if config.POP3 then pop3.start (config.POP3) end

  if config.Historian then historian.start (config.Historian) end
  
  luup.openLuup.mqtt = mqtt
  if config.MQTT then 
    -- 2021.02.01  start the Shelly and Tasmota bridges BEFORE MQTT server (so Shelly catches ANNOUNCE)
    require "openLuup.L_ShellyBridge"
    
    require "openLuup.L_TasmotaBridge" .start (config.Tasmota)
    
    require "openLuup.L_Zigbee2MQTTBridge" .start (config.Zigbee)
    
    mqtt.start (config.MQTT) 
    
    if config.MQTT.PublishVariableUpdates == "true" then
      devutil.publish_variable_updates (true)
    end
    local carbon = config.MQTT.Carbon 
    if carbon then historian.CarbonCache (carbon) end   -- create Graphite database for MQTT stats 
  end
  
  -- start the heartbeat
  timers.call_delay(openLuupPulse, 6 * 60, '', "first checkpoint")      -- it's alive! it's alive!!

  status = scheduler.start ()                   -- this is the main scheduling loop!
end

luup.reload (status)      -- actually, it's a final exit (but it saves the user_data.json file)

-----------
