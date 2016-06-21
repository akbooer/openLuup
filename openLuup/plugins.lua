local ABOUT = {
  NAME          = "openLuup.plugins",
  VERSION       = "2016.06.20",
  DESCRIPTION   = "Plugin updates from Plugins page",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

--
-- Handles plugin updates from AltUI Plugins page, 
-- converting requests into action calls to the AltAppStore plugin
-- invoked by one of a number of HTTP requests (qv.)
-- 
-- 2016.04.26  switch to GitHub update module
-- 2016.05.15  add some InstalledPlugins2 data for openLuup and AltUI
-- 2016.05.21  fix destination directory error in openLuup install!
-- 2016.05.24  build files list when plugins are installed
-- 2016.06.06  complete configuration of DataYours install (to log cpu and memory, "out of the box")
-- 2016.06.06  add missing dkjson.lua to AltUI install
-- 2016.06.08  add add_ancilliary_files to export table
-- 2016.06.20  convert to using AltAppStore plugin

local logs          = require "openLuup.logs"
local json          = require "openLuup.json"                 -- for DataYours AltUI configuration
local vfs           = require "openLuup.virtualfilesystem"    -- for index.html install
local lfs           = require "lfs"                           -- for portable mkdir and dir
local url           = require "socket.url"                    -- for escaping request parameters

local pathSeparator = package.config:sub(1,1)   -- thanks to @vosmont for this Windows/Unix discriminator
                            -- although since lfs (luafilesystem) accepts '/' or '\', it's not necessary

--local function path (x) return x: gsub ("/", pathSeparator) end

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control

--[[

---------------------------------------------------------

THINGS TO KNOW:

From the Plugins page, AltUI issues two types of requests 
depending on whether or not anything is entered into the Update box:

empty request to openLuup:

/data_request?id=update_plugin&Plugin=openLuup

entry of "v0.8.2" to VeraBridge update box:

/data_request?id=action&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&action=CreatePlugin&PluginNum=VeraBridge&Version=v0.8.2

Because the MiOS plugin store version has nothing to do with AltUI build versions, @amg0 tags GitHub releases and passes these to openLuup when a browser refresh plugin update is initiated:

...need an example here with &TracRev=... 

---------------------------------------------------------

--]]


-- Utility functions

-- return first found device ID if a device of the given type is present locally
local function device_present (device_type)
  for devNo, d in pairs (luup.devices) do
    if ((d.device_num_parent == 0)      -- local device...
    or  (d.device_num_parent == 2))     -- ...or child of openLuup device
    and (d.device_type == device_type) then
      return devNo
    end
  end
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
-- InstalledPlugins2[...] =    
--    {
--      AllowMultiple   = "0",
--      Title           = "DataYours",
--      Icon            = "images/plugin.png", 
--      Instructions    = "http://forum.micasaverde.com/index.php/board,78.0.html",
--      AutoUpdate      = "0",
--      VersionMajor    = "GitHub",
--      VersionMinor    = '?',
--      id              = "8211",         -- use genuine MiOS ID, otherwise name
--      timestamp       = os.time(),
--      Files           = {},
--      Devices         = {
--        {
--          DeviceFileName = "D_IPhone.xml",
--          DeviceType = "urn:schemas-upnp-org:device:IPhoneLocator:1",
--          ImplFile = "D_IPhone.xml",
--          Invisible =  "0",
--          CategoryNum = "1",
--          StateVariables = "..." -- see luup.create_device documentation
--        },
--      },
--
--      -- openLuup extras
--
--     Repository       = {
--        type      = "GitHub",
--        source    = "akbooer/Datayours",
--        target    = ''    -- normally, which is /etc/cmh-ludl/, but not for openLuup itself (openLuup/)
--        default   = "development",      -- or "master" or any tagged release
--        folders = {                     -- these are the bits we need
--          "subdir1",
--          "subdir2",
--        },
--        pattern = "[DILS]_%w+%.%w+"     -- Lua pattern string to describe wanted files
--      },
--
--    }


--------------------------------------------------
--
-- openLuup
--

-- add extra files if absent
local function add_ancillary_files ()  
  local html = "index.html"
  copy_if_missing (vfs.open (html), html)
  
  local reload = "openLuup_reload"
  if pathSeparator ~= '/' then reload = reload .. ".bat" end   -- Windows version
  copy_if_missing (vfs.open (reload), reload)
end

local function update_openLuup ()
  
  
  add_ancillary_files ()
  
  luup.reload ()
end


--------------------------------------------------
--
-- AltUI
--

-- get the AltUI version number from the actual code
-- so it doesn't matter which branch this was retrieved from
local function get_altui_version ()
  local v
  local f = io.open "J_ALTUI_uimgr.js"
  if f then
      local t = f:read "*a"
      f: close()
      if t then
          v = t: match [["$Revision:%s*(%w+)%s*$"]]
      end
  end
  return v
end

local function update_altui (_, ipl)
  
  local _,dkjson = luup.inet.wget "https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua"
  local dkname = "dkjson.lua"
  vfs.write (dkname, dkjson)
  copy_if_missing (vfs.open(dkname), dkname)
  
  local rev = get_altui_version() or ipl.VersionMinor    -- recover ACTUAL version from source code, if possible  
  ipl.VersionMinor = rev   -- 2016.05.15
  local msg = "AltUI installed version: " .. rev
  _log (msg)
  luup.reload ()
end


--------------------------------------------------
--
-- DataYours 
--
-- this has a special installer because it has to create the plugin if missing
-- and provide appropriate parameters and a Whisper data directory

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

local function update_datayours ()
  lfs.mkdir "whisper/"            -- default openLuup Whisper database location
  -- install configuration files from virtual file storage
  copy_if_missing (vfs.open "storage-schemas.conf", "whisper/storage-schemas.conf")
  copy_if_missing (vfs.open "storage-aggregation.conf", "whisper/storage-aggregation.conf")
  -- create unknown.wsp file so that there's a blank plot shown for a new variable
  local whisper = require "L_DataWhisper"
  whisper.create ("whisper/unknown.wsp", "1d:1d")
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
  luup.inet.wget (request:format ("Memory_Mb", memParams))
  luup.inet.wget (request:format ("CpuLoad",   cpuParams))
    
end


--------------------------------------------------
--
-- plugin methods
--

-- find the requested pluin data in InstalledPlugins2 structure
local function find_installed_data (plugin)
  plugin = tostring(plugin)
  local installed = luup.attr_get "InstalledPlugins2" or {}
  local info
  for _,p in ipairs (installed) do
    local id = tostring (p.id)
    if id == plugin then
      info = p
      break
    end
  end
  return info
end


-- build update_plugin metadata from InstalledPlugins2 structure
local function metadata (id, tag)
  local IP = find_installed_data (id)    -- get the named InstalledPlugins2 metadata
  if IP then 
    local r = IP.Repository
    local major = r.type or "GitHub"
    local tag = tag or r.default or "master"
    r.versions = {[tag] = {release = tag}}
    return json.encode {                      -- reformat for update_plugin request
        devices     = IP.Devices,
        plugin      = IP,
        repository  = r,
        version     = {major = major, minor = tag},
        versionid   = tag,
      }
  end
  return nil, table.concat {"metadata for'", id or '?', "' not found"}
end

--------------------------------------------------

-- this function returns an HTTP message in reponse to an update request.
local function create (p)
  local special = {
    ["openLuup"]    = update_openLuup,        -- device is already installed
    ["8211"]        = update_datayours,       -- extra configuration to do
    ["8246"]        = update_altui,           -- extracts version from code
  }
  
  local Plugin = p.PluginNum or p.Plugin
  local tag = p.Tag or p.TracRev or p.Version   -- pecking order for parameter names
  local meta, errmsg = metadata (Plugin, tag)
--  _log (meta)                                   -- TODO: testing only
    
  if meta then
    local sid = "urn:upnp-org:serviceId:AltAppStore1"
    local act = "update_plugin"
    local arg = {metadata = meta}
    local dev = device_present "urn:schemas-upnp-org:device:AltAppStore:1"
    local _, error_msg = luup.call_action (sid, act, arg, dev)
    
    -- NOTE: that the above action executes asynchronously and the function call
    --       returns immediately, so you CAN'T do a luup.reload() here !!
    return error_msg or "OK"
--    return (special[Plugin] or generic_plugin) (p, info) 
  else
    local msg = errmsg or "no such plugin: " .. (Plugin or '?')
    _log (msg) 
    return msg, "text/plain" 
  end
end


local function delete ()
  _log "Can't delete plugin"    -- TODO: delete plugins!
  return false
end

-----

return {
  ABOUT     = ABOUT,
  
  create    = create,
  delete    = delete,
  
  add_ancillary_files = add_ancillary_files,            -- for others to use (qv. openLuup_installer script)
  latest_version = function () return "unknown" end,    -- TODO: fix openLuup latest version display
  metadata  = metadata,
--  present   = present,
}

-----

