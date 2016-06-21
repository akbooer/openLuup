local ABOUT = {
  NAME          = "openLuup.init",
  VERSION       = "2016.06.20",
  DESCRIPTION   = "initialize Luup engine with user_data, run startup code, start scheduler",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

--
-- openLuup - Initialize Luup engine
--  

-- 2016.05.12  moved load_user_data from this module to userdata
-- 2016.06.08  add 'altui' startup option to do new install
-- 2016.06.09  add files/ directory to Lua search path
-- 2016.06.18  add openLuup/ directory to Lua search path
-- 2016.06.19  switch to L_AltAppStore module for initial AltUI download

local loader = require "openLuup.loader" -- keep this first... it prototypes the global environment

local logs = require "openLuup.logs"

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end
_log ('',":: openLuup STARTUP ")
logs.banner (ABOUT)   -- for version control

luup = require "openLuup.luup"       -- here's the GLOBAL luup environment

local requests      = require "openLuup.requests"
local server        = require "openLuup.server"
local scheduler     = require "openLuup.scheduler"
local timers        = require "openLuup.timers"
local userdata      = require "openLuup.userdata"
local json          = require "openLuup.json"
local mime          = require "mime"
local plugins       = require "openLuup.plugins"

-- what it says...
local function compile_and_run (lua, name)
  _log ("running " .. name)
  local startup_env = loader.shared_environment    -- shared with scenes
  local source = table.concat {"function ", name, " () ", lua, "end" }
  local code, error_msg = 
  loader.compile_lua (source, name, startup_env) -- load, compile, instantiate
  if not code then 
    _log (error_msg, name) 
  else
    local ok, err = scheduler.context_switch (nil, code[name])  -- no device context
    if not ok then _log ("ERROR: " .. err, name) end
    code[name] = nil      -- remove it from the name space
  end
end


-- heartbeat monitor for memory usage and checkpointing
local function openLuupPulse ()
  timers.call_delay(openLuupPulse, 6*60)                      -- periodic pulse (6 minutes)  
  -- CHECKPOINT !
  local ok, msg = userdata.save (luup)
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
--  loader.icon_redirect ''                   -- remove all prefix paths for icons
end

do -- Devices 1 and 2 are the Vera standard ones (but #2, _SceneController, replaced by openLuup)
  local invisible = true
  luup.attr_set ("Device_Num_Next", 1)  -- this may get overwritten by a subsequent user_data load

  -- create (device_type, int_id, descr, upnp_file, upnp_impl, ip, mac, hidden, invisible, parent, room, ...)
  luup.create_device ("urn:schemas-micasaverde-com:device:ZWaveNetwork:1", '',
    "ZWave", "D_ZWaveNetwork.xml", nil, nil, nil, nil, invisible)
--  luup.create_device ("urn:schemas-micasaverde-com:device:SceneController:1", '',
--                      "_SceneController", "D_SceneController1.xml", nil, nil, nil, nil, invisible, 1)
  luup.create_device ("openLuup", '', " openLuup", "D_openLuup.xml")
end

do -- set attributes, possibly decoding if required
  local set_attr = userdata.attributes 
  set_attr["openLuup"] = {StartTime = os.date ("%Y-%m-%dT%H:%M:%S", timers.loadtime)}
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

do -- CALLBACK HANDLERS
  -- Register lu_* style (ie. luup system, not luup user) callbacks with HTTP server
  local extendedList = {}
  for name, proc in pairs (requests) do 
    extendedList[name]        = proc
    extendedList["lu_"..name] = proc              -- add compatibility with old-style call names
  end
  server.add_callback_handlers (extendedList)     -- tell the HTTP server to use these callbacks
end

do -- STARTUP   
  local init = arg[1] or "user_data.json"         -- optional parameter: Lua or JSON startup file
  _log ("loading configuration ".. init)
  
  if init == "reset" then luup.reload () end      -- factory reset
  
  if init == "altui" then                         -- install altui in reset system
    userdata.attributes.InstalledPlugins2 = userdata.default_plugins
    -- this is a bit tricky, since the scheduler is not running at this stage
    -- but we need to execute a multi-step action with <run> and <job> tags...
    require "openLuup.L_AltAppStore"              -- manually load the plugin updater
    AltAppStore_init (2)                          -- give it a device to work with
    local meta = plugins.metadata (8246)          -- AltUI plugin number
    update_plugin_run {metadata = meta}    -- <run> phase
    repeat
      local status = update_plugin_job ()  -- <job> phase
    until status ~= 0
  end
  
  local f = io.open (init, 'r')
  if f then 
    local code = f:read "*a"
    f:close ()
    if code then
      local ok = true
      local json_code = code: match "^%s*{"    -- what sort of code is this?
      if json_code then 
        ok = userdata.load (code)
        code = userdata.attributes ["StartupCode"] or ''  -- substitute the Startup Lua
      end
      compile_and_run (code, "_openLuup_STARTUP_")  -- the given file or the code in user_data
    else
      _log "no init data"
    end
  else
    _log "init file not found"
  end
  _log "init phase completed"
end

local status

do -- SERVER and SCHEDULER
  local s = server.start "3480"                 -- start the port 3480 Web server
  if not s then 
    error "openLuup - is another copy already running?  Unable to start port 3480 server" 
  end

  -- start the heartbeat
  timers.call_delay(openLuupPulse, 6 * 60)      -- it's alive! it's alive!!

  status = scheduler.start ()                   -- this is the main scheduling loop!
end

luup.reload (status)      -- actually, it's a final exit (but it saves the user_data.json file)

-----------
