local ABOUT = {
  NAME          = "openLuup.plugins",
  VERSION       = "2016.06.01",
  DESCRIPTION   = "create/delete plugins",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

--
-- create/delete plugins
--
-- invoked by:
-- /data_request?id=action&
--    serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&
--     action=CreatePlugin&PluginNum=...
-- 
-- 2016.04.26  switch to GitHub update module
-- 2016.05.15  add some InstalledPlugins2 data for openLuup and AltUI
-- 2016.05.21  fix destination directory error in openLuup install!
-- 2016.05.24  build files list when plugins are installed

-- TODO: parameterize all this to be data-driven from the InstalledPlugins2 structure.

local logs          = require "openLuup.logs"
local github        = require "openLuup.github"
local vfs           = require "openLuup.virtualfilesystem"    -- for index.html install
local lfs           = require "lfs"                           -- for portable mkdir and dir

local pathSeparator = package.config:sub(1,1)   -- thanks to @vosmont for this Windows/Unix discriminator
                            -- although since lfs (luafilesystem) accepts '/' or '\', it's not necessary

local function path (x) return x: gsub ("/", pathSeparator) end

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control


-- Utility functions
local function no_such_plugin (Plugin) 
  local msg = "no such plugin: " .. (Plugin or '?')
  _log (msg) 
  return msg, "text/plain" 
end

-- return first found device ID if a device of the given type is present locally
local function present (device_type)
  for devNo, d in pairs (luup.devices) do
    if (d.device_num_parent == 0)     -- local device!!
    and (d.device_type == device_type) then
      return devNo
    end
  end
end

local function file_write (filename, content)
  local f, msg
  f, msg = io.open (filename, 'w+')
  if f then
    f: write (content)
    f: close ()
  end
  return f, msg
end

local function file_copy (source, dest)
  local attr = lfs.attributes (source)
  if attr and attr.mode ~= "file" then
    return nil, "filecopy: won't copy directory files!", 0
  end
  local f, msg, content
  f, msg = io.open (source, 'r')
  if f then
    content = f: read "*a"
    f: close ()
    f, msg = file_write (dest, content)
  end
  local bytes = content and #content or 0
  return not msg, msg, bytes 
end

local function batch_copy (source, destination, pattern)
  local total = 0
  local files = {}
  for file in lfs.dir (source) do
    local source_path = source .. file
--    _log (table.concat {"source: ", source, ", file: ", file})
    if file: match (pattern or '.') 
    and lfs.attributes (source_path).mode == "file" 
    and not file: match "^%." then            -- ignore hidden files
      local dest_path = destination..file
      local ok, msg, bytes = file_copy (source_path, dest_path)
      if ok then
        total = total + bytes
        files [#files+1] = file   -- filename only, not path
        msg = ("%-8d %s"):format (bytes, file)
        _log (msg)
      else
        _log (table.concat {file, " NOT copied: ", msg or '?'})
      end
    end
  end
  _log (table.concat {"Total size: ", total, " bytes"})
  return total, files
end

local function mkdir_tree (path)
  local i = 1
  repeat -- work along path creating directories if necessary
    local _,j = path: find ("%w+", i)
    if j then
      local dir = path:sub (1,j)
      lfs.mkdir (dir)
      i = j + 1
    end
  until not j
end

-- check to see if plugin needs to install device(s)
-- at the moment, only create the FIRST device in the list
-- (multiple devices are a bit of a challenge to identify uniquely)
local function install_if_missing (plugin)
  local devices = plugin["Devices"] or {}
  local device1 = devices[1] or {}
  local device_type = device1["DeviceType"]
  local device_file = device1["DeviceFileName"]
  local device_impl = device1["ImplFile"]
  local statevariables = device1["StateVariables"]
  local pluginnum = plugin.id
  
  local function install (plugin)
    local ip, mac, hidden, invisible, parent, room
    local name = plugin.Title or '?'
    local altid = ''
    _log ("installing " .. name)
    -- device file comes from Devices structure
    local devNo = luup.create_device (device_type, altid, name, device_file, 
      device_impl, ip, mac, hidden, invisible, parent, room, pluginnum, statevariables)  
    return devNo
  end
  
  local devNo
  if device_type and not present (device_type) then 
    devNo = install(plugin) 
  end
  return devNo
end


--------------------------------------------------
--
-- Generic table-driven updates
--

--  InstalledPlugins2[...] =    -- this is the 'ipl' parameter below
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
--        downloads = "plugins/downloads/DataYours/",
--        backup    = "plugins/backup/DataYours/",
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

-- need to replace this wih the appropriate IncludePlugins2 item
-- parameters: (1) the repository, (2) the download destination (actually, this is problably always the same)

local function generic_plugin (p, ipl, no_reload)
  local r = ipl.Repository  
  if not r.source and r.downloads then return end
  
  local updater = github.new (r.source, r.downloads)
  
  local rev = p.Version or r.default    -- this needs a "default", for when the Update box has no entry
  
  _log (table.concat ({"downloading", ipl.id, "rev", rev}, ' ') )
  local folders = r.folders or {''}    -- these are the bits of the repository that we want
  local ok = updater.get_release (rev, folders, r.pattern) 
  if not ok then return ipl.Title .. " download failed" end
  
  _log ("backing up " .. ipl.Title)
  mkdir_tree (r.backup)
  batch_copy ('.' .. pathSeparator, r.backup, r.pattern)   -- copy from /etc/cmh-ludl/
 
  local target = r.target or ''     -- destination path for install, default is /etc/cmh-ludl/
  mkdir_tree (target)
  
  _log "updating device files..."
  local s1, files = batch_copy (r.downloads, target, "[^p][^n][^g]$")   -- don't copy icons to cmh-ludl...
  _log "updating icons..."
  lfs.mkdir "icons/"
  local s2 = batch_copy (r.downloads, "icons/", "%.png$")                          -- ... but to icons/
  _log (table.concat {"Grand Total size: ", s1 + s2, " bytes"})
  
  ipl.VersionMajor = r.type
  ipl.VersionMinor = rev
  ipl.timestamp = os.time()
  local iplf = ipl.Files or {}
  for i,f in ipairs (files) do
    iplf[i] = {SourceName = f}
  end
 
  local msg = "updated version: " .. rev
  _log (msg)
  
  local devNo = install_if_missing (ipl)
  if not no_reload then luup.reload () end    -- sorry about double negative
  return devNo
end



--------------------------------------------------
--
-- openLuup
--
-- invoked by:
-- /data_request?id=action&
--    serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&
--     action=CreatePlugin&PluginNum=openLuup&Tag=0.7.0
-- OR
-- if TracRev is missing then use Version
--OR
-- /data_request?id=update&rev=0.7.0


local openLuup_updater = github.new ("akbooer/openLuup", "plugins/downloads/openLuup")

local function update_openLuup (p, ipl)
  p.Version = p.rev or p.Tag or p.Version        -- set this for generic_plugin install
  
  local dont_reload = true
  generic_plugin (p, ipl, dont_reload)   
  
  local html = "index.html"
  if not lfs.attributes (html) then     -- don't overwrite if already there
    _log "installing index.html"
    local content = vfs.read (html)
    if content then 
      file_write (html, content)
    end
  end
    
  luup.reload ()
end


--------------------------------------------------
--
-- AltUI
--
-- invoked by:
-- /data_request?id=action&
--    serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&
--     action=CreatePlugin&PluginNum=8246&TracRev=1237&Version=...
-- OR
-- if TracRev is missing then use Version
-- OR
-- /data_request?id=altui&rev=1237

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

local function update_altui (p, ipl)
  p.Version = p.rev or p.TracRev or p.Version        -- set this for generic_plugin install
  
  local dont_reload = true
  generic_plugin (p, ipl, dont_reload)   
  
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

local function update_datayours (p, ipl)
  local dont_reload = true
  local devNo = generic_plugin (p, ipl, dont_reload)   
  
  if devNo then   -- new device created, so set up parameters
    lfs.mkdir "whisper/"            -- default openLuup Whisper database location
    -- TODO: finish DataYours setup
    -- install configuration files
    -- start logging cpu and memory from device #2 by patching AltUI VariablesToSend
    luup.reload ()
  end
end


--------------------------------------------------
--
-- plugin methods
--


-- return true if successful, false if not.
local function create (p)
  local special = {
    ["openLuup"]    = update_openLuup,        -- device is already installed
    ["8211"]        = update_datayours,       -- extra configuration to do
    ["8246"]        = update_altui,           -- extracts version from code
  }
  local Plugin = p.PluginNum or p.Plugin
  local installed = luup.attr_get "InstalledPlugins2"
  
  local info
  for _,p in ipairs (installed) do
    local id = tostring (p.id)
    if id == Plugin then
      info = p
      break
    end
  end
  
  if info then
    return (special[Plugin] or generic_plugin) (p, info) 
  else
    return no_such_plugin (Plugin)
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
  
  latest_version = openLuup_updater.latest_version,
}

-----

