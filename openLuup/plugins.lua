local ABOUT = {
  NAME          = "openLuup.plugins",
  VERSION       = "2016.05.24",
  DESCRIPTION   = "create/delete plugins",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

--
-- create/delete plugins
-- 
-- 2016.04.26  switch to GitHub update module
-- 2016.05.15  add some InstalledPlugins2 data for openLuup and AltUI
-- 2016.05.21  fix destination directory  error in openLuup install!
-- 2016.05.24  build files list when plugins are installed

-- TODO: parameterize all this to be data-driven from the InstalledPlugins2 structure.

local logs          = require "openLuup.logs"
local github        = require "openLuup.github"
local lfs           = require "lfs"             -- for portable mkdir and dir

local pathSeparator = package.config:sub(1,1)   -- thanks to @vosmont for this Windows/Unix discriminator
                            -- although since lfs (luafilesystem) accepts '/' or '\', it's not necessary

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control


-- invoked by:
-- /data_request?id=action&
--    serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&
--     action=CreatePlugin&PluginNum=8246&TracRev=1237

-- Utility functions

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
    f, msg = io.open (dest, 'w+')
    if f then
      f: write (content)
      f: close ()
    end
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
        files [#files+1] = dest_path
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

local altui_backup      = ("plugins/backup/altui/"):            gsub ("/", pathSeparator)
local altui_downloads   = ("plugins/downloads/altui/"):         gsub ("/", pathSeparator)
local blockly_downloads = ("plugins/downloads/altui/blockly/"): gsub ("/", pathSeparator)

local AltUI_updater = github.new ("amg0/ALTUI", "plugins/downloads/altui")

local function install_altui_if_missing ()
  
  local function install ()
    local upnp_impl, ip, mac, hidden, invisible, parent, room
    local pluginnum = 8246
    luup.create_device ('', "ALTUI", "ALTUI", "D_ALTUI.xml", 
      upnp_impl, ip, mac, hidden, invisible, parent, room, pluginnum)  
  end
  
  local function missing ()
    for _, d in pairs (luup.devices) do
      if (d.device_num_parent == 0)     -- local device!!
      and (d.device_type == "urn:schemas-upnp-org:device:altui:1") then
        return false    -- it's not missing
      end
    end
    return true   -- it IS missing
  end
  
  if missing() then install() end
end


local function update_altui (p)
  local rev =  tonumber (p.TracRev or p.Version) or "master"
  
  _log "backing up AltUI plugin"
  mkdir_tree (altui_backup)
  batch_copy ('.' .. pathSeparator, altui_backup, "ALTUI")

  _log ("downloading ALTUI rev " .. rev)  
  local subdirectories = {    -- these are the bits of the repository that we want
    '',           -- root
    "/blockly",   -- blockly editor
  }
  
  local ok = AltUI_updater.get_release (rev, subdirectories, "ALTUI")
  if not ok then return "AltUI download failed" end

  _log "installing new AltUI version..."
  local s1, f1 = batch_copy (altui_downloads, '', "ALTUI")
  local s2 = batch_copy (blockly_downloads, '', "ALTUI")
  _log (table.concat {"Grand Total size: ", s1 + s2, " bytes"})

  install_altui_if_missing ()
  
  local IP2 = luup.attr_get "InstalledPlugins2"
  local ipl = IP2[2] or {}
  ipl.VersionMinor = rev   -- 2016.05.15
  local iplf = ipl.Files or {}
  for i,f in ipairs (f1) do       -- don't include the blockly files in this list
    iplf[i] = {SourceName = f}
  end
  local msg = "AltUI installed version: " .. rev
  _log (msg)
  luup.reload ()
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

local function path (x) return x: gsub ("/", pathSeparator) end

local openLuup_backup       = path "plugins/backup/openLuup/openLuup/"
local bridge_backup         = path "plugins/backup/openLuup/VeraBridge/"
local openLuup_downloads    = path "plugins/downloads/openLuup/openLuup/"
local bridge_downloads      = path "plugins/downloads/openLuup/VeraBridge/"

local cgi_bin_cmh   = path "cgi-bin/cmh/"
local upnp_control  = path "upnp/control/"

local openLuup_updater = github.new ("akbooer/openLuup", "plugins/downloads/openLuup")

local function update_openLuup (p)
  local rev = p.Tag or p.Version or "development"
  
  _log "backing up openLuup"
  mkdir_tree (openLuup_backup)
  mkdir_tree (bridge_backup)
  local s1, f1 = batch_copy ('openLuup' .. pathSeparator, openLuup_backup)        -- /etc/cmh-ludl/openLuup folder
  local s2, f2 = batch_copy ('.' .. pathSeparator, bridge_backup, "VeraBridge")   -- VeraBridge from /etc/cmh-ludl/
  _log (table.concat {"Grand Total size: ", s1 + s2, " bytes"})
  
  _log ("downloading openLuup rev " .. rev)  
  local subdirectories = {    -- these are the bits of the repository that we want
    "/openLuup",
    "/VeraBridge",
  }
  
  local ok = openLuup_updater.get_release (rev, subdirectories) 
  if not ok then return "openLuup download failed" end
 
  local cmh_ludl = ''
  local openLuup = path "openLuup/"
  
  _log "installing new openLuup version..."
  s1, f1 = batch_copy (openLuup_downloads, openLuup)
  s2, f2 = batch_copy (bridge_downloads, cmh_ludl)
  _log (table.concat {"Grand Total size: ", s1 + s2, " bytes"})

  _log "installing CGI files"
  mkdir_tree (cgi_bin_cmh)
  file_copy (path "openLuup/backup.lua", cgi_bin_cmh .. "backup.sh")    -- to enable user_data backups
  mkdir_tree (upnp_control)
  file_copy (path "openLuup/hag.lua", upnp_control .. "hag")            -- to enable Startup Lua editing, etc.
  
  local IP2 = luup.attr_get "InstalledPlugins2"
  local ipl = IP2[1] or {}
  ipl.VersionMinor = rev   -- 2016.05.15
  local iplf = ipl.Files or {}
  for i,f in ipairs (f1) do
    iplf[i] = {SourceName = f}          -- don't include the VeraBridge files in this list
  end
  local msg = "openLuup installed version: " .. rev
  _log (msg)
  luup.reload ()
end


--------------------------------------------------
--
-- VeraBridge
--
-- invoked by:
-- /data_request?id=action&
--    serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&
--     action=CreatePlugin&PluginNum=VeraBridge&Version=...
-- OR
-- if TracRev is missing then use Version
--OR
-- /data_request?id=update&rev=0.7.0


local bridge_updater = github.new ("akbooer/openLuup", "plugins/downloads/")

local function update_bridge (p)

  local bridge_backup         = path "plugins/backup/VeraBridge/"
  local bridge_downloads      = path "plugins/downloads/"
  
--  local rev = p.Version or "master"
  local rev = p.Version or "development"
  
  _log "backing up VeraBridge"
  mkdir_tree (bridge_backup)
  batch_copy ('.' .. pathSeparator, bridge_backup, "VeraBridge")   -- VeraBridge from /etc/cmh-ludl/
  
  _log ("downloading VeraBridge rev " .. rev)  
  local subdirectories = {    -- these are the bits of the repository that we want
    "/VeraBridge",
  }
  
  local ok = bridge_updater.get_release (rev, subdirectories) 
  if not ok then return "VeraBridge download failed" end
 
  local cmh_ludl = ''
  mkdir_tree (cmh_ludl)
  
  _log "installing new VeraBridge version..."
  local _,f1 = batch_copy (bridge_downloads .. "VeraBridge/", cmh_ludl)

  local IP3 = luup.attr_get "InstalledPlugins2"
  local ipl = IP3[3] or {}
  ipl.VersionMinor = rev   -- 2016.05.15
  local iplf = ipl.Files or {}
  for i,f in ipairs (f1) do
    iplf[i] = {SourceName = f}
  end
  
  local msg = "VeraBridge installed version: " .. rev
  _log (msg)
  luup.reload ()
end


--------------------------------------------------
--
-- Generic table-driven updates
--
-- invoked by:
-- /data_request?id=action&
--    serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&
--     action=CreatePlugin&PluginNum=VeraBridge&Version=...


-- need to replace this wih the appropriate IncludePlugins2 item
-- parameters: (1) the repository, (2) the download destination (actually, this is problably always the same)
local generic_updater = github.new ("akbooer/openLuup", "plugins/downloads/")

local function update_generic (p)  -- TODO: finish this

  -- these are the places to put the backup and downloads:
  local bridge_backup         = path "plugins/backup/VeraBridge/"
  local bridge_downloads      = path "plugins/downloads/"
  
--  local rev = p.Version or "master"
  local rev = p.Version or "development"    -- this need to be a "default", for when the Update box has no entry
  
  _log "backing up VeraBridge"
  mkdir_tree (bridge_backup)
  local s2 = batch_copy ('.' .. pathSeparator, bridge_backup, "VeraBridge")   -- VeraBridge from /etc/cmh-ludl/
  
  _log ("downloading VeraBridge rev " .. rev)  
  local subdirectories = {    -- these are the bits of the repository that we want
    "/VeraBridge",
  }
  
  local ok = bridge_updater.get_release (rev, subdirectories) 
  if not ok then return "VeraBridge download failed" end
 
  local cmh_ludl = ''
--  cmh_ludl = "CMH_LUDL_TEST/"       -- TODO: testing only
  mkdir_tree (cmh_ludl)
  
  _log "installing new VeraBridge version..."
  s2 = batch_copy (bridge_downloads .. "VeraBridge/", cmh_ludl)

  local IP2 = luup.attr_get "InstalledPlugins2"
  IP2[3] = IP2[3] or {}
  IP2[3].VersionMinor = rev   -- 2016.05.15
  
  local msg = "VeraBridge installed version: " .. rev
  _log (msg)
  luup.reload ()
end


--------------------------------------------------
--
-- TEST plugin methods
--

local function update_test (p)
 local IP2 = luup.attr_get "InstalledPlugins2"
  IP2[5] = IP2[5] or {}
  IP2[5].VersionMinor = p.Version or os.time()
  _log "update_test for plugins"
end


--------------------------------------------------
--
-- plugin methods
--

-- return true if successful, false if not.
local function create (p)
  local PluginNum = p.PluginNum or p.Plugin
  local function none () 
    local msg = "no such plugin: " .. (PluginNum or '?')
    _log (msg) 
    return msg, "text/plain" 
  end
  local dispatch = {
    ["openLuup"]    = update_openLuup, 
    ["VeraBridge"]  = update_bridge,
    ["Test"]        = update_test,
    ["8211"]        = none,           -- DataYours
    ["8246"]        = update_altui,
  }
  return (dispatch[PluginNum or ''] or none) (p) 
end

local function delete ()
  _log "Can't delete plugin"
  return false
end

-----

return {
  ABOUT     = ABOUT,
  
  create    = create,
  delete    = delete,
}

-----

