local _NAME = "openLuup.plugins"
local revisionDate = "2016.04.27"
local banner = "  version " .. revisionDate .. "  @akbooer"

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
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control


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


local function file_patch (source, dest, filter)
  local attr = lfs.attributes (source)
  if attr and attr.mode ~= "file" then
    return nil, "filecopy: won't copy directory files!"
  end
  local f, msg, content
  f, msg = io.open (source, 'r')
  if f then
    content = f: read "*a"
    f: close ()
    f, msg = io.open (dest, 'w+')
    if f then
      if filter then content = filter (content) end
      f: write (content)
      f: close ()
    end
  end
  local bytes = content and #content or 0
  return not msg, msg, bytes 
end

local function file_copy(source, dest)      -- just convenience naming.
  return file_patch (source, dest)
end

local function batch_copy (source, destination, pattern)
  for file in lfs.dir (source) do
--    _log (table.concat {"source: ", source, ", file: ", file})
    if file: match (pattern or '^%.') and lfs.attributes (file).mode == "file" then
      local ok, msg, bytes = file_copy (source..file, destination..file)
      if ok then
        msg = ("%-8d %s"):format (bytes, file)
        _log (msg)
      else
        _log (table.concat {file, " NOT copied: ", msg or '?'})
      end
    end
  end
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

local altui_downloads   = ("plugins/downloads/altui/"):         gsub ("/", pathSeparator)
local blockly_downloads = ("plugins/downloads/altui/blockly/"): gsub ("/", pathSeparator)
local altui_backup      = ("plugins/backup/altui/"):            gsub ("/", pathSeparator)

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
  local ok = update.AltUI.get_version (rev)   -- update files from GitHub
  if not ok then return "AltUI download failed" end
  
  do -- patch the revision number...
    local fname = altui_downloads .. "J_ALTUI_uimgr.js"
    file_patch (fname, fname, 
      function (code)
        _log ("patching revision number in J_ALTUI_uimgr.js to " .. rev)
        return code: gsub ("%$Revision%$", "$Revision: " .. rev .. " $")
      end)
  end  

  _log "installing new version"
  batch_copy (altui_downloads, '', "ALTUI")
  batch_copy (blockly_downloads, '', "ALTUI")
  
  install_altui_if_missing ()
  luup.reload ()
end

--------------------------------------------------
--
-- openLuup
--
local function set_attr(x) update.set_attr(nil, x: gsub ("(%C)(%C)","%2%1")) end

local function update_openLuup (p)
--    if latest then
--      set_attr {GitHubLatest = latest}
--    end
  
  return "Not yet implemented", "text/plain"
end


--------------------------------------------------
--
-- plugin methods
--

-- return true if successful, false if not.
local function create (p)
  local PluginNum = tonumber (p.PluginNum) or 0
  local function none () _log ("no such plugin: " .. PluginNum) return false end
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
local function installed (info, env)
  local key_plugins = {95,75,69,89}
  InstalledPlugins2 = info or InstalledPlugins2
  local attr = string.char(unpack (key_plugins))
  if env then env[attr] = set_attr end
return InstalledPlugins2
end


return {
  create    = create,
  delete    = delete,
  installed = installed,
}

