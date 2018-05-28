ABOUT = {
  NAME          = "AltAppStore",
  VERSION       = "2018.05.17",
  DESCRIPTION   = "update plugins from Alternative App Store",
  AUTHOR        = "@akbooer / @amg0 / @vosmont",
  COPYRIGHT     = "(c) 2013-2018",
  DOCUMENTATION = "https://github.com/akbooer/AltAppStore",
}

-- // This program is free software: you can redistribute it and/or modify
-- // it under the condition that it is for private or home useage and 
-- // this whole comment is reproduced in the source code file.
-- // Commercial utilisation is not authorized without the appropriate written agreement.
-- // This program is distributed in the hope that it will be useful,
-- // but WITHOUT ANY WARRANTY; without even the implied warranty of
-- // MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE . 

-- Plugin for Vera and openLuup
--
-- The Alternative App Store is a collaborative effort:
--   Web/database:  @vosmont
--   (Alt)UI:       @amg0
--   Plugin:        @akbooer
--
--[[

From the AltAppStore Web page in AltUI, you get an action request to the AltAppStore plugin:

/data_request?id=action
  &output_format=json
  &DeviceNum=4&serviceId=urn:upnp-org:serviceId:AltAppStore1
  &action=update_plugin
  &metadata={...URL escaped.. JSON string...}

The metadata structure is complex (see below, it is, after all, developed by committee) 
and partially modelled on the InstalledPlugins2 structure in Vera user_data.

--]]

-- 2016.06.20   use optional target repository parameter for final download destination
-- 2016.06.21   luup.create_device didn't work for UI7, so use action call for all systems
-- 2016.06.22   slightly better log messages for <run> and <job> phases, add test request argument
-- 2016.11.23   don't allow spaces in pathnames
--              see: http://forum.micasaverde.com/index.php/topic,40406.msg299810.html#msg299810

-- 2018.02.24   upgrade SSL encryption to tls v1.2 after GitHub deprecation of v1 protocol
-- 2018.05.15   use trash/ not /tmp/ with openLuup, to avoid permissions issue with /tmp (apparently)
-- 2018.05.17   allow .svg as well as .png icon files


local https     = require "ssl.https"
local lfs       = require "lfs"
local ltn12     = require "ltn12"

local json
local Vera = luup.attr_get "SvnVersion"

if Vera then
  json = require "L_ALTUIjson"    -- we will always run with AltUI present
else
  json = require "openLuup.json"  -- AltUI may NOT be present (eg. before it's installed)
end


https.TIMEOUT = 5

local devNo     -- our own device number

local SID = {
  altui = "urn:upnp-org:serviceId:altui1",                -- Variables = 'DisplayLine1' and 'DisplayLine2'
  apps  = "urn:upnp-org:serviceId:AltAppStore1",
  hag   = "urn:micasaverde-com:serviceId:HomeAutomationGateway1",
}

local icon_directories = {
  [true] = "icons/",                                            -- openLuup icons
  [5] = "/www/cmh/skins/default/icons/",                        -- UI5 icons
  [6] = "/www/cmh_ui6/skins/default/icons/",                    -- UI6 icons, thanks to @reneboer for this information
  [7] = "/www/cmh/skins/default/img/devices/device_states/",    -- UI7 icons
}

local ludl_directories = {
  [true] = "./",                -- openLuup (since default dir may not be /etc/cmh-ludl/)
  [5] = "/etc/cmh-ludl/",       -- UI5 
  [7] = "/etc/cmh-ludl/",       -- UI7
}

local icon_folder = icon_directories[(luup.version_minor == 0 ) or luup.version_major]
local ludl_folder = ludl_directories[(luup.version_minor == 0 ) or luup.version_major]

local _log = function (...) luup.log (table.concat ({ABOUT.NAME, ':', ...}, ' ')) end

local pathSeparator = '/'

-- utilities

local function setVar (name, value, service, device)
  service = service or SID.apps
  device = device or devNo
  local old = luup.variable_get (service, name, device)
  if tostring(value) ~= old then 
   luup.variable_set (service, name, value, device)
  end
end

local function display (line1, line2)
  if line1 then luup.variable_set (SID.altui, "DisplayLine1",  line1 or '', devNo) end
  if line2 then luup.variable_set (SID.altui, "DisplayLine2",  line2 or '', devNo) end
end

-- UI7 return status : {0 = OK, 1 = Device config error, 2 = Authorization error}
local function set_failure (status)
  if (luup.version_major < 7) then status = status ~= 0 end        -- fix UI5 status type
  luup.set_failure(status)
end

-- UI5 doesn't have the luup.create_device function!

local function create_device (device_type, altid, name, device_file, 
      device_impl, ip, mac, hidden, invisible, parent, room, pluginnum, statevariables)  
  local _ = {hidden, invisible}   -- unused
  -- do appreciate the following naming inconsistencies which Luup enjoys... 
  local args = {
    deviceType = device_type,
    internalID = altid,
    Description = name,
    UpnpDevFilename = device_file,
    UpnpImplFilename = device_impl,
    IpAddress = ip,
    MacAddress = mac,
--Username 	string
--Password 	string
    DeviceNumParent = parent,
    RoomNum = room,
    PluginNum = pluginnum,
    StateVariables = statevariables,
--Reload 	boolean  If Reload is 1, the Luup engine will be restarted after the device is created. 
  }
  local err, msg, job, arg = luup.call_action (SID.hag, "CreateDevice", args, 0)
  return err, msg, job, arg
end

-------------------------------------------------------
--
-- update plugins from GitHub repository
--

local _ = {
  NAME          = "openLuup.github",
  VERSION       = "2016.06.16",
  DESCRIPTION   = "download files from GitHub repository",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

-- 2016.03.15  created
-- 2016.04.25  make generic, for use with openLuup / AltUI / anything else
-- 2016.06.16  just return file contents using iterator, don't actually write any files.

-------------------------
--
--  GitHub() - factory function for individual plugin update from GitHub
--
--  parameter:
--    archive = "akbooer/openLuup",           -- GitHub repository
--

function GitHub (archive)     -- global for access by other modules

  -- get and decode GitHub url

  local function git_request (request)
    local decoded
    local response = {}
    local errmsg
    local r, c, h, s = https.request {
      url = request,
      sink = ltn12.sink.table(response),
      protocol = "tlsv1_2"
    }
    response = table.concat (response)
    _log ("GitHub request: " .. request)
    if r then 
      decoded, errmsg = json.decode (response)
    else
      errmsg = c
      _log ("ERROR: " .. (errmsg or "unknown"))
    end
    return decoded, errmsg
  end
  
  -- return a table of tagged releases, indexed by name, 
  -- with GitHub structure including commit info
  local function get_tags ()
    local tags
    local Ftag_request  = "https://api.github.com/repos/%s/tags"
    local resp, errmsg = git_request (Ftag_request: format (archive))
    if resp then 
      tags = {} 
      for _, x in ipairs (resp) do
        tags[x.name] = x
      end
    end
    return tags, errmsg
  end
  
  -- find the tag of the newest released version
  local function latest_version ()
    local tags = {}
    local t, errmsg = get_tags ()
    if not t then return nil, errmsg end
    for v in pairs (t) do tags[#tags+1] = v end
    table.sort (tags)
    local latest = tags[#tags]
    return latest
  end
  
  -- get specific parts of tagged release
  local function get_release_by_file (v, subdirectories, pattern)
    local files, N = {}, 0
    local resp, errmsg
    
    -- iterator for each file we want
    -- returns code, name, content
    local function get_next_file ()
      N = N+1
      local x = files[N]
      if not x then return end            -- used at end of iteration (no more files)
      local content, code = https.request(x.download_url)
      return code, x.name, content, N, #files   -- code = 200 is success
    end
    
    for _, d in ipairs (subdirectories) do
      local Fcontents = "https://api.github.com/repos/%s/contents"
      local dir = d: match "%S+"    -- 2016.11.23  non-spaces
      local request = table.concat {Fcontents: format (archive),d , "?ref=", v}
      resp, errmsg = git_request (request)
      if resp then
  
        for _, x in ipairs (resp) do     -- x is a GitHub descriptor with name, path, etc...
          local wanted = (x.type == "file") and (x.name):match (pattern or '.') 
          if wanted then files[#files+1] = x end
        end
      
      else
        return nil, errmsg or "unknown error" 
      end
    end
    
    return get_next_file
  end
  
  -- GitHub()
  return {
    get_tags = get_tags,
    get_release_by_file = get_release_by_file,
    latest_version = latest_version,
  }
end

--
-- End of GitHub module
--
-------------------------------------------------------


-- utilities


-- return first found device ID if a device of the given type is present locally
local function present (device_type)
  for devNo, d in pairs (luup.devices) do
    if ((d.device_num_parent == 0)      -- local device...
    or  (d.device_num_parent == 2))     -- ...or child of openLuup device
    and (d.device_type == device_type) then
      return devNo
    end
  end
end

-- check to see if plugin needs to install device(s)
-- at the moment, only create the FIRST device in the list
-- (multiple devices are a bit of a challenge to identify uniquely)
local function install_if_missing (meta)
  local devices = meta["Devices"] or meta["devices"] or {}
  local device1 = devices[1] or {}
  local device_type = device1["DeviceType"]
  local device_file = device1["DeviceFileName"]
  local device_impl = device1["ImplFile"]
  local statevariables = device1["StateVariables"]
  local pluginnum = meta.id
  local name = meta.plugin.Title or '?'
  
  local function install ()
    local ip, mac, hidden, invisible, parent, room
    local altid = ''
    _log ("installing " .. name)
    create_device (device_type, altid, name, device_file, 
      device_impl, ip, mac, hidden, invisible, parent, room, pluginnum, statevariables)  
  end
  
  -- install_if_missing()
  if device_type and not present (device_type) then 
    install() 
    return true
  end
end

local function file_copy (source, destination)
  local f = io.open (source, "rb")
  if f then
    local content = f: read "*a"
    f: close ()
    local g = io.open (destination, "wb")
    if g then
      g: write (content)
      g: close ()
    else
      _log ("error writing", destination)
    end
  end
end

--[[
-------------------------------------------------------
--
-- THIS IS EXAMPLE METADATA FROM THE APP STORE ACTION REQUEST
--

{
  devices = {{
      DeviceFileName = "ALTUI",
      DeviceType = "D_ALTUI.xml",
      ImplFile = "I_ALTUI.xml",
      Invisible = "0"
    }},
  plugin = {
    AllowMultiple = 0,
    AutoUpdate = 1,
    Description = "Alternate user interface and feature set extension for VERA & openLuup",
    Icon = "https://apps.mios.com/plugins/icons/8246.png",
    Instructions = "http://forum.micasaverde.com/index.php/topic,33309.0.html",
    Title = "ALTUI",
    id = 8246
  },
  repository = {
    folders = {""},
    pattern = "[DIJLS]_ALTUI%w*%.%w+",
    source = "amg0/ALTUI",
    type = "GitHub",
    versions = {["2"] = {release = "1763"}}
  },
  version = {
    major = "1",
    minor = "58.1763"
  },
  versionid = "2"
}

-------------------------------------------------------
--
-- AltAppStore's own InstalledPlugins2 structure:
--

local AltAppStore =  
  {
    AllowMultiple   = "0",
    Title           = "AltAppStore",
    Icon            = "https://raw.githubusercontent.com/akbooer/AltAppStore/master/AltAppStore.png", 
    Instructions    = "https://github.com/akbooer/AltAppStore",  --TODO: change to better documentation
    AutoUpdate      = "0",
    VersionMajor    = "not",
    VersionMinor    = "installed",
    id              = "AltAppStore",
--    timestamp       = os.time(),
    Files           = {},
    Devices         = {
      {
        DeviceFileName  = "D_AltAppStore.xml",
        DeviceType      = "urn:schemas-upnp-org:device:AltAppStore:1",
        ImplFile        = "I_AltAppStore.xml",
        Invisible       =  "0",
--        CategoryNum = "1",
--        StateVariables = "..." -- see luup.create_device documentation
      },
    },
    Repository      = {
      {
        type      = "GitHub",
        source    = "akbooer/AltAppStore",
  --      folders = {                     -- these are the bits we need
  --        "subdir1",
  --        "subdir2",
  --      },
  --      pattern = "[DIJLS]_%w+%.%w+"     -- Lua pattern string to describe wanted files
        pattern   = "AltAppStore",                   -- pattern match string for required files
      },
    }
  }


--]]

-- update the relevant data for the Plugins page, creating new entry if required
local function update_InstalledPlugins2 (meta, files)

  local IP2 = luup.attr_get "InstalledPlugins2"
  if type(IP2) ~="table" then return end
  
  -- find the plugin in IP2, if present
  local id = tostring(meta.plugin.id) 
  local plugin
  for _,p in ipairs (IP2) do
    if id == tostring (p.id) then
      plugin = p
      break
    end
  end
  
  -- create new entry if required
  if not plugin then
    plugin = meta.plugin
    IP2[#IP2+1] = plugin
  end
  
  -- update fields
  plugin.Files = files or {}
  plugin.Devices = meta.devices
  plugin.Repository = meta.repository
  
  plugin.VersionMajor = meta.version.major or '?'
  plugin.VersionMinor = meta.version.minor or '?'
end

-------------------------------------------------------
--
-- the update_plugin action is implemented in two parts:
-- <run>  validity checks, etc.
-- <job>  phased download, with control returned to scheduler between individual files
--

-- these variables are shared between the two phases...
local meta        -- the plugin metadata
local next_file   -- download iterator
local downloads      -- location for downloads
local total       -- total file transfer size
local files       -- files list
local test

function update_plugin_run(args)
  
--  p.metadata = p.metadata or json.encode (AltAppStore)     -- TESTING ONLY!
  test = false
  if args.test then
    _log "test <run> phase..."
    test =  tostring (args.test)
    return true
  end

  _log "starting <run> phase..."
  meta = json.decode (args.metadata)
  
  if type (meta) ~= "table" then 
    _log "invalid metadata: JSON table decode error"
    return false                            -- failure
  end
  
  local d = meta.devices
  local p = meta.plugin
  local r = meta.repository
  local v = meta.version
  
  if not (d and p and r and v) then 
    _log "invalid metadata: missing repository, plugin, devices, or version"
    return false
  end
  
  local t = r.type
  local w = (r.versions or {}) [meta.versionid] or {}
  local rev = w.release
  if not (t == "GitHub" and type(rev) == "string") then
    _log "invalid metadata: missing GitHub release"
    return false
  end
  
  if Vera then
    downloads = table.concat ({'', "tmp", "AltAppStore",''}, pathSeparator)
  else  -- 2018.05.15 use trash/ not /tmp/ with openLuup, to avoid permissions issue with /tmp (apparently)
    lfs.mkdir "trash"   -- ensure the trash/directory is present
    downloads = table.concat ({"trash", "AltAppStore",''}, pathSeparator)
  end
  lfs.mkdir (downloads)
  local updater = GitHub (r.source)
    
  _log ("downloading", r.source, '['..rev..']', "to", downloads) 
  local folders = r.folders or {''}    -- these are the bits of the repository that we want
  local info
  next_file, info = updater.get_release_by_file (rev, folders, r.pattern) 
  
  if not next_file then
    _log ("error downloading:", info)
    return false
  end
  
  _log ("getting contents of version:", rev)
  
  display ("Downloading...", p.Title or '?')
  total = 0
  files = {}
  _log "scheduling <job> phase..."
  return true                               -- continue with <job>
end

-- these are the standard job return states
local jobstate =  {
    NoJob=-1,
    WaitingToStart=0,         -- If you return this value, 'job' runs again in 'timeout' seconds 
    InProgress=1,
    Error=2,
    Aborted=3,
    Done=4,
    WaitingForCallback=5,     -- This means the job is running and you're waiting for return data
    Requeue=6,
    InProgressPendingData=7,
 }

function update_plugin_job()
  
  if test then 
    _log ("test <job> phase, parameter = " .. test)
    display (nil, test)
    return jobstate.Done,0 
  end
  
  local title = meta.plugin.Title or '?'
  local status, name, content, N, Nfiles = next_file()
  if N and N == 1 then _log "starting <job> phase..." end
  if status then
    if status ~= 200 then
      _log ("download failed, status:", status)
      display (nil, title .. " failed")
      --tidy up
      return jobstate.Error,0
    end
    local f, err = io.open (downloads .. name, "wb")
    if not f then 
      _log ("failed writing", name, "with error", err)
      display (nil, title .. " failed")
      return jobstate.Error,0
    end
    f: write (content)
    f: close ()
    local size = #content or 0
    total = total + size
    local percent = "%s %0.0f%%"
    local column = "(%d of %d) %6d %s"
    _log (column:format (N, Nfiles, size, name))
    display (nil, percent: format (title, 100 * N / Nfiles))
    return jobstate.WaitingToStart,0        -- reschedule immediately
  else
    -- finish up
    _log "...final <job> phase"
    _log ("Total size", total)
    display (nil, (title) .. " 100%")
 
    -- copy/compress files to final destination... 
    local target = meta.repository.target or ludl_folder
    _log ("updating icons in", icon_folder, "...")
    _log ("updating device files in", target, "...")
    
    local Nicon= 0
    for file in lfs.dir (downloads) do
      local source = downloads .. file
      local attributes = lfs.attributes (source)
      if file: match "^[^%.]" and attributes.mode == "file" then
        local destination
        if file:match ".+%.[ps][nv]g$" then    -- 2018.05.17  ie. *.png or *.svg (or pvg or sng !!)
          Nicon = Nicon + 1
          destination = icon_folder .. file
          file_copy (source, destination)
        else
          files[#files+1] = {SourceName = file}
          destination = target .. file
          if Vera then   
            os.execute (table.concat ({"pluto-lzo c", source, destination .. ".lzo"}, ' '))
          else
            file_copy (source, destination)
          end
        end
        os.remove (source)
      end
    end
    
    _log ("...", Nicon,  "icon files")
    _log ("...", #files, "device files")
       
    update_InstalledPlugins2 (meta, files)
    _log (meta.plugin.Title or '?', "update completed")
    
    local new_install = install_if_missing (meta)
    -- only perform reload if there was already a version installed
    -- in order to start using the new files.
    -- If a new device has been created, it will be using them, and
    -- plugins often generate system reloads anyway as part of first-time setup.
    if not new_install then luup.reload() end
    display ('','')
    return jobstate.Done,0        -- finished job
  end
end


-------------------------------------------------------
--
-- Alt App Store
--

-- plugin initialisation
function AltAppStore_init (d)
  devNo = d  
  _log "starting..." 
  display (ABOUT.NAME,'')  
  
  do -- version number
    local y,m,d = ABOUT.VERSION:match "(%d+)%D+(%d+)%D+(%d+)"
    local version = ("v%d.%d.%d"): format (y%2000,m,d)
    setVar ("Version", version)
    _log (version)
  end
  
  set_failure (0)
  return true, "OK", ABOUT.NAME
end

-----

