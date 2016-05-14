local ABOUT = {
  NAME          = "openLuup.plugins",
  VERSION       = "2016.05.11",
  DESCRIPTION   = "create/delete plugins",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

--
-- create/delete plugins
-- 
--  2016.04.26  switch to GitHub update module
--

local logs          = require "openLuup.logs"
local update        = require "openLuup.update"
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


local InstalledPlugins2 = {}


--[[
{

    "Version": 28706,
    "AllowMultiple": "0",
    "Title": "Alternate UI",
    "Icon": "plugins/icons/8246.png",
    "Instructions": "http://forum.micasaverde.com/index.php/board,78.0.html",
    "Hidden": "0",
    "AutoUpdate": "1",
    "VersionMajor": "0",
    "VersionMinor": "67",
    "SupportedPlatforms": null,
    "MinimumVersion": null,
    "DevStatus": null,
    "Approved": "0",
    "id": 8246,
    "TargetVersion": "28706",
    "timestamp": 1441211941,

    "Files": 

[

{

    "SourceName": "iconALTUI.png",
    "SourcePath": null,
    "DestName": "iconALTUI.png",
    "DestPath": "",
    "Compress": "0",
    "Encrypt": "0",
    "Role": "M"   -- Device, Service, JavaScript (or JSON) 

},
{

    "SourceName": "I_ALTUI.xml",
    "SourcePath": null,
    "DestName": "I_ALTUI.xml",
    "DestPath": "",
    "Compress": "1",
    "Encrypt": "0",
    "Role": "I"

}
    ],
"Devices": 
[

    {
        "DeviceFileName": "D_ALTUI.xml",
        "DeviceType": "urn:schemas-upnp-org:device:altui:1",
        "ImplFile": "I_ALTUI.xml",
        "Invisible": "0",
        "CategoryNum": "1"
    }

],
"Lua": 
[

{

    "FileName": "L_ALTUI.lua"

},

        {
            "FileName": "L_ALTUIjson.lua"
        }
    ],
},
--]]


--[[

-- for the future: installed plugins info

  local function update_installed_plugins (afiles, bfiles)
    
    local function file_list (F, files)
      for _, f in ipairs(files) do
        F[#F+1] = {
          SourceName = f,
  --      "SourcePath": null,
        DestName =  f,
        DestPath = "",
  --      "Compress": "0",
  --      "Encrypt": "0",
  --      "Role": "M"   -- Device, Service, JavaScript (or JSON) 
        }
      end
    end

    local files = {}
    file_list (files, afiles)
    file_list (files, bfiles)
    InstalledPlugins2[1] =      -- we'll always put ALTUI in pole position!
      {
        AllowMultiple   = "0",
        Title           = "Alternate UI",
        Icon            = "http://code.mios.com/trac/mios_alternate_ui/export/12/iconALTUI.png",
        Instructions    = "http://forum.micasaverde.com/index.php/board,78.0.html",
        Hidden          = "0",
        AutoUpdate      = "1",
  --      Version         = 28706,
        VersionMajor    = Vmajor or '?',
        VersionMinor    = Vminor or '?',
  --      "SupportedPlatforms": null,
  --      "MinimumVersion": null,
  --      "DevStatus": null,
  --      "Approved": "0",
        id              = 8246,
  --      "TargetVersion": "28706",
        timestamp       = os.time(),
        Files           = files,
      }
  end

--]]


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
  for file in lfs.dir (source) do
    local source_path = source .. file
--    _log (table.concat {"source: ", source, ", file: ", file})
    if file: match (pattern or '.') 
    and lfs.attributes (source_path).mode == "file" 
    and not file: match "^%." then            -- ignore hidden files
      local ok, msg, bytes = file_copy (source_path, destination..file)
      if ok then
        total = total + bytes
        msg = ("%-8d %s"):format (bytes, file)
        _log (msg)
      else
        _log (table.concat {file, " NOT copied: ", msg or '?'})
      end
    end
  end
  _log (table.concat {"Total size: ", total, " bytes"})
  return total
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
--     action=CreatePlugin&PluginNum=8246&TracRev=1237
-- OR
-- /data_request?id=altui&TracRev=1237

local altui_backup      = ("plugins/backup/altui/"):            gsub ("/", pathSeparator)
local altui_downloads   = ("plugins/downloads/altui/"):         gsub ("/", pathSeparator)
local blockly_downloads = ("plugins/downloads/altui/blockly/"): gsub ("/", pathSeparator)

local AltUI_updater = update.new ("amg0/ALTUI", "plugins/downloads/altui")

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
  local rev =  tonumber (p.TracRev) or "master"
  
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

  _log "installing new AltUI version"
  local s1 = batch_copy (altui_downloads, '', "ALTUI")
  local s2 = batch_copy (blockly_downloads, '', "ALTUI")
  _log (table.concat {"Grand Total size: ", s1 + s2, " bytes"})

  install_altui_if_missing ()
  
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
--     action=CreatePlugin&PluginNum=0&Tag=0.7.0
--OR
-- /data_request?id=update&Tag=0.7.0

local function path (x) return x: gsub ("/", pathSeparator) end

local openLuup_backup       = path "plugins/backup/openLuup/openLuup/"
local extensions_backup     = path "plugins/backup/openLuup/openLuupExtensions/"
local bridge_backup         = path "plugins/backup/openLuup/VeraBridge/"
local openLuup_downloads    = path "plugins/downloads/openLuup/openLuup/"
local extensions_downloads  = path "plugins/downloads/openLuup/openLuupExtensions/"
local bridge_downloads      = path "plugins/downloads/openLuup/VeraBridge/"

local openLuup_updater = update.new ("akbooer/openLuup", "plugins/downloads/openLuup")

local function update_openLuup (p)
  local rev = p.Tag or "master"
  
  _log "backing up openLuup"
  mkdir_tree (openLuup_backup)
  mkdir_tree (bridge_backup)
  mkdir_tree (extensions_backup)
  local s1 = batch_copy ('openLuup' .. pathSeparator, openLuup_backup)        -- /etc/cmh-ludl/openLuup folder
  local s2 = batch_copy ('.' .. pathSeparator, bridge_backup, "VeraBridge")   -- VeraBridge from /etc/cmh-ludl/
  local s3 = batch_copy ('.' .. pathSeparator, extensions_backup, "openLuupExtensions")   -- VeraBridge from /etc/cmh-ludl/
  _log (table.concat {"Grand Total size: ", s1 + s2 + s3, " bytes"})
  
  _log ("downloading openLuup rev " .. rev)  
  local subdirectories = {    -- these are the bits of the repository that we want
    "/openLuup",
    "/VeraBridge",
    "/openLuupExtensions",
  }
  
  local ok = openLuup_updater.get_release (rev, subdirectories) 
  if not ok then return "openLuup download failed" end
 
  local cmh_ludl = ''
--  cmh_ludl = "CMH_LUDL_TEST/"       -- TODO: testing only
  mkdir_tree (cmh_ludl)
  
  _log "installing new openLuup version"
  s1 = batch_copy (openLuup_downloads, cmh_ludl)
  s2 = batch_copy (bridge_downloads, cmh_ludl)
  s3 = batch_copy (extensions_downloads, cmh_ludl)
  _log (table.concat {"Grand Total size: ", s1 + s2 + s3, " bytes"})

  luup.attr_set ("GitHubVersion", rev)
--  set_attr {GitHubLatest = latest}    -- TODO: perhaps move to Extensions plugin
  
  local msg = "openLuup installed version: " .. rev
  _log (msg)
  luup.reload ()
end


--------------------------------------------------
--
-- plugin methods
--

-- return true if successful, false if not.
local function create (p)
  local PluginNum = tonumber (p.PluginNum) or 0
  local function none () 
    local msg = "no such plugin: " .. PluginNum
    _log (msg) 
    return msg, "text/plain" 
  end
  local dispatch = {
    [0]     = update_openLuup, 
    [8246]  = update_altui,
  }
  return (dispatch[PluginNum] or none) (p) 
end

local function delete ()
  _log "Can't delete plugin"
  return false
end

-- set or retrieve installed plugins info
local function installed (info)
  InstalledPlugins2 = info or InstalledPlugins2
return InstalledPlugins2
end

-----

return {
  ABOUT     = ABOUT,
  
  create    = create,
  delete    = delete,
  installed = installed,
}

-----

