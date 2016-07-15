local ABOUT = {
  NAME          = "openLuup.userdata",
  VERSION       = "2016.07.15",
  DESCRIPTION   = "user_data saving and loading, plus utility functions used by HTTP requests",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

-- user_data
-- saving and loading, plus utility functions used by HTTP requests id=user_data, etc.

-- 2016.05.09   return length of user_data.json file on successful save
-- 2016.05.12   moved load_user_data to this module from init
-- 2016.05.15   use InstalledPlugins2 list
-- 2016.05.21   handle empty InstalledPlugins2 in user_data file on loading
-- 2016.05.22   ignore table structure in writing user_data attributes
-- 2016.05.24   update InstalledPlugins2 list
-- 2016.06.06   fix load error if missing openLuup structure (upgrading from old version)
-- 2016.06.08   add pre-defined startup code for new systems
-- 2016.06.22   add metadata routine for plugin install
-- 2016.06.24   remove defaults from pre-installed repository data (always use "master"
-- 2016.06.28   change install parameters for VeraBridge (device and icon file locations)
-- 2016.06.30   split save into two functions: json & save to allow data compression

local json    = require "openLuup.json"
local rooms   = require "openLuup.rooms"
local logs    = require "openLuup.logs"
local scenes  = require "openLuup.scenes"
local chdev   = require "openLuup.chdev"
local lfs     = require "lfs"

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control

--
-- Here a complete list of top-level (scalar) attributes taken from an actual Vera user_data2 request
-- the commented out items are either vital tables, or useless parameters.

local attributes = { 
--  AltEventServer = "127.0.0.1",
--  AutomationDevices = 0,
  BuildVersion = "*1.7.0*", 
  City_description = "Greenwich",
  Country_description = "UNITED KINGDOM",
--  DataVersion = 563952001,
--  DataVersion_Static = "32",
--  DeviceSync = "1426564006",
  Device_Num_Next = "1",
--  ExtraLuaFiles = {},
--  InstalledPlugins = {},
--  InstalledPlugins2 = {},
  KwhPrice = "0.15",
  LoadTime = os.time(),
  Mode = "1",                               -- House Mode
  ModeSetting = "1:DC*;2:DC*;3:DC*;4:DC*",  -- see: http://wiki.micasaverde.com/index.php/House_Modes
  PK_AccessPoint = "88800000",   -- TODO: pick up machine serial number from EPROM or such like,
--  PluginSettings = {},
--  PluginsSynced = "0",
--  RA_Server = "vera-us-oem-relay41.mios.com",
--  RA_Server_Back = "vera-us-oem-relay11.mios.com",
  Region_description = "England",
--  ServerBackup = "1",
--  Server_Device = "vera-us-oem-device12.mios.com",
--  Server_Device_Alt = "vera-us-oem-device11.mios.com",
--  SetupDevices = {},
--  ShowIndividualJobs = 0,
  StartupCode = [[

-- You can personalise the installation by changing these attributes,
-- which are persistent and may be removed from the Startup after a reload.
local attr = luup.attr_set

-- Geographical location
attr ("City_description", "Greenwich")
attr ("Country_description", "UNITED KINGDOM")
attr ("Region_description", "England")
attr ("latitude", "51.48")
attr ("longitude", "0.0")

-- other parameters
attr ("TemperatureFormat", "C")
attr ("PK_AccessPoint", "88800000")
attr ("currency", "£")
attr ("date_format", "dd/mm/yy")
attr ("model", "Not a Vera")
attr ("timeFormat", "24hr")
attr ("timezone", "0")

-- Any other startup processing may be inserted here...
luup.log "startup code completed"

]]
,
--  SvnVersion = "*13875*",
  TemperatureFormat = "C",
--  UnassignedDevices = 0,
--  Using_2G = 0,
--  breach_delay = "30",
--  category_filter = {},
  currency = "£",
  date_format = "dd/mm/yy",
--  device_sync = "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,18,19,20,21",
--  devices = {},
--  energy_dev_log = "41,",
--  firmware_version = "1",
  gmt_offset = "0",
--  ip_requests = {},
--  ir = 0,
  latitude = "51.48",
--  local_udn = "uuid:4d494342-5342-5645-0000-000002b03069",
  longitude = "0.0",
  mode_change_delay = "30",
  mode_change_mode = '',      -- TODO: implement mode_change_mode
  mode_change_time = '',      -- TODO: implement mode_change_time
  model = "Not a Vera",
--  net_pnp = "0",
--  overview_tabs = {},
--  rooms = {},
--  scenes = {},
--  sections = {},
--  setup_wizard_finished = "1",
--  shouldHelpOverlayBeHidden = true,
  skin = "AltUI",         -- was "mios",
--  static_data = {},
--  sync_kit = "0000-00-00 00:00:00",
  timeFormat = "24hr",
  timezone = "0",
--  users = {},
--  weatherSettings = {
--    weatherCountry = "UNITED KINGDOM",
--    weatherCity = "Oxford England",
--    tempFormat = "C" },
--  zwave_heal = "1426331082",    

-- openLuup specials

  ShutdownCode = '',

}



-------
--
-- pre-installed plugins
--

local default_plugins_version = "2016.07.15"  --<<<-- change this to force update of default_plugins

local preinstalled = {
  
  openLuup = 

    {
      AllowMultiple   = "0",
      Title           = "openLuup",
      Icon            = "https://avatars.githubusercontent.com/u/4962913",
      Instructions    = "http://forum.micasaverde.com/index.php/board,79.0.html",
      AutoUpdate      = "0",
      VersionMajor    = '',
      VersionMinor    = "baseline.",
      TargetVersion   = default_plugins_version,      -- openLuup uses this for the InstalledPlugins2 version number
      id              = "openLuup",
      timestamp       = os.time(),
      Files           = (function ()                  -- generate this list dynamically
                          local F = {}
                          for f in lfs.dir "openLuup/" do
                            if f: match "^.+%..+$" then F[#F+1] = {SourceName = f} end
                          end
                          return F
                        end) (),
      Devices         = {},                           -- no devices to install!!
      Repository      = {
        type      = "GitHub",
        source    = "akbooer/openLuup",               -- the openLuup repository
        target    = "./openLuup/",                    -- not /etc/cmh-ludl/, like everything else
        pattern   = ".+%.lua$",                       -- pattern match string for required files
        folders   = {"/openLuup"},                    -- these are the bits of the repository that we want
       },
    },

  AltUI = 

    {
      AllowMultiple   = "0",
      Title           = "Alternate UI",
      Icon            = "plugins/icons/8246.png",     -- usage: http://apps.mios.com/icons/8246.png
      Instructions    = "http://forum.micasaverde.com/index.php/board,78.0.html",
      AutoUpdate      = "1",                          -- not really "auto", but will prompt on browser refresh
      VersionMajor    = "not",
      VersionMinor    = "installed",
      id              = 8246,                         -- this is the genuine MiOS plugin number
      timestamp       = os.time(),
      Files           = {},                           -- populated on download from repository
      Devices         = {
        {
          DeviceFileName  = "D_ALTUI.xml",
          DeviceType      = "urn:schemas-upnp-org:device:altui:1",
          ImplFile        = "I_ALTUI.xml",
          Invisible       =  "0",
--          CategoryNum = "1"
        },
      },
      Repository      = {     
        type      = "GitHub",
        source    = "amg0/ALTUI",                   -- @amg0 repository
        pattern   = "ALTUI",                        -- pattern match string for required files
        folders   = {                               -- these are the bits of the repository that we want
          '',               -- the main folder
          "/blockly",       -- and blocky editor
        },
      },
    },

  AltAppStore =

    {
      AllowMultiple   = "0",
      Title           = "Alternate App Store",
      Icon            = "https://raw.githubusercontent.com/akbooer/AltAppStore/master/AltAppStore.png",
      Instructions    = "https://github.com/akbooer/AltAppStore",
      AutoUpdate      = "0",
      VersionMajor    = '',
      VersionMinor    = "baseline.",
      id              = "AltAppStore",
      timestamp       = os.time(),
      Files           = {                             -- it's part of the openLuup baseline
          {SourceName = "L_AltAppStore.lua"},         -- this is a physical file in ./openLuup/
        },
      Devices         = {
        {
          DeviceFileName  = "D_AltAppStore.xml",
          DeviceType      = "urn:schemas-upnp-org:device:AltAppStore:1",
          ImplFile        = "I_AltAppStore.xml",
          Invisible       =  "0",
        },
      },
      Repository      = {
        type      = "GitHub",
        source    = "akbooer/openLuup",               -- get this from openLuup, NOT from AltAppStore...
        folders   = {"/openLuup"},                    -- these are the bits of the repository that we want
        target    = "./openLuup/",                    -- ...and put it back INTO ./openLuup/ folder
        pattern   = "L_AltAppStore",                  -- only .lua file (others are in virtualfilesystem)
      },
    },

  VeraBridge = 

    {
      AllowMultiple   = "1",
      Title           = "VeraBridge",
      Icon            = "https://raw.githubusercontent.com/akbooer/openLuup/master/VeraBridge/VeraBridge.png",
      Instructions    = "http://forum.micasaverde.com/index.php/board,79.0.html",
      AutoUpdate      = "0",
      VersionMajor    = "not",
      VersionMinor    = "installed",
      id              = "VeraBridge",
      timestamp       = os.time(),
      Files           = {
          {SourceName = "L_VeraBridge.lua"},          -- this is a physical file in ./openLuup/
        },
      Devices         = {
        {
          DeviceFileName  = "D_VeraBridge.xml",
          DeviceType      = "VeraBridge",
          ImplFile        = "I_VeraBridge.xml",
          Invisible       =  "0",
        },
      },
      Repository      = {
        type      = "GitHub",
        source    = "akbooer/openLuup",               -- actually comes from the openLuup repository
        target    = "./openLuup/",                    -- ...and put it back INTO ./openLuup/ folder
        pattern   = "L_VeraBridge",                   -- only .lua file (others are in virtualfilesystem)
        folders   = {"/openLuup"},                    -- these are the bits of the repository that we want
      },
    },

  DataYours =

    {
      AllowMultiple   = "0",
      Title           = "DataYours",
      Icon            = "https://raw.githubusercontent.com/akbooer/DataYours/master/icons/DataYours.png",
      Instructions    = "https://github.com/akbooer/DataYours/tree/master/Documentation",
      AutoUpdate      = "0",
      VersionMajor    = "not",
      VersionMinor    = 'installed',
      id              = 8211,
      timestamp       = os.time(),
      Files           = {},
      Devices         = {
        {
          DeviceFileName  = "D_DataYours.xml",
          DeviceType      = "urn:akbooer-com:device:DataYours:1",
          ImplFile        = "I_DataYours.xml",
          Invisible       =  "0",
          StateVariables  = [[
            urn:akbooer-com:serviceId:DataYours1,DAEMONS=Watch Cache Graph
            urn:akbooer-com:serviceId:DataYours1,LOCAL_DATA_DIR=whisper/
          ]],
        },
      },
      Repository      = {
        type      = "GitHub",
        source    = "akbooer/Datayours",
        pattern   = "[DILS]_Data%w+%.%w+",             -- pattern match string for required files
      },
    },

  Arduino =

    {
      AllowMultiple   = "1",
      Title           = "MySensors Arduino",
      Icon            = "https://www.mysensors.org/icon/MySensors.png", 
      Instructions    = "https://github.com/mysensors/Vera/tree/UI7",
      AutoUpdate      = "0",
      VersionMajor    = "not",
      VersionMinor    = "installed",
      id              = "Arduino",
      timestamp       = os.time(),
      Files           = {},
      Devices         = {
        {
          DeviceFileName  = "D_Arduino1.xml",
          DeviceType      = "urn:schemas-arduino-cc:device:arduino:1",
          ImplFile        = "I_Arduino1.xml",
          Invisible       =  "0",
        },
      },
      Repository      = {
        type      = "GitHub",
        source    = "mysensors/Vera",
        pattern   = "[DILS]_Arduino%w*%.%w+",             -- pattern match string for required files
      },
    },

  Razberry =

    {
      AllowMultiple   = "1",
      Title           = "RaZberry (ALPHA)",
      Icon            = "https://raw.githubusercontent.com/amg0/razberry-altui/master/iconRAZB.png", 
      Instructions    = "https://github.com/amg0/razberry-altui",
      AutoUpdate      = "1",
      VersionMajor    = "not",
      VersionMinor    = "installed",
      id              = "razberry-altui",
      timestamp       = os.time(),
      Files           = {},
      Devices         = {
        {
          DeviceFileName  = "D_RAZB.xml",
          DeviceType      = "urn:schemas-upnp-org:device:razb:1",
          ImplFile        = "I_RAZB.xml",
          Invisible       =  "0",
        },
      },
      Repository      = {
        type      = "GitHub",
        source    = "amg0/razberry-altui",
        pattern   = "RAZB",
      },
    },
  }   -- end of preinstalled plugins


local default_plugins = {
    preinstalled.openLuup,
    preinstalled.AltUI,
    preinstalled.AltAppStore,
    preinstalled.VeraBridge,
    preinstalled.Razberry,
    preinstalled.Arduino,
    preinstalled.DataYours,
  }

--
-- PLUGINS
--

-- given installed plugin structure, generate index by ID
local function plugin_index (plugins)
  local index = {}
  for i,p in ipairs (plugins) do
    local id = tostring (p.id)
    if id then index[id] = i end
  end
  return index
end

-- find the requested plugin data, and index in structure
local function find_installed_data (plugin)
  plugin = tostring(plugin)
  local installed = luup.attr_get "InstalledPlugins2" or {}
  local info, idx
  for i,p in ipairs (installed) do
    local id = tostring (p.id)
    if id == plugin then
      info, idx = p, i
      break
    end
  end
  return info, idx
end

-- build update_plugin metadata from InstalledPlugins2 structure
local function plugin_metadata (id, tag)
  
  local IP = find_installed_data (id)    -- get the named InstalledPlugins2 metadata
  if IP then 
    local r = IP.Repository
    local major = r.type or "GitHub"
    tag = tag or "master"
    r.versions = {[tag] = {release = tag}}
    local plugin = {}
    for a,b in pairs (IP) do
      if type(b) ~= "table" then plugin[a] = b end    -- copy all the scalar data
    end
    return  {                             -- reformat for update_plugin request
        devices     = IP.Devices,
        plugin      = plugin,
        repository  = IP.Repository,
        version     = {major = major, minor = tag},
        versionid   = tag,
      }
  end
  return nil, table.concat {"metadata for'", id or '?', "' not found"}
end


--
-- LOAD and SAVE
--

-- load user_data (persistence for attributes, rooms, devices and scenes)
local function load_user_data (user_data_json)  
  _log "loading user_data json..."
  local user_data, msg = json.decode (user_data_json)
  if msg then 
    _log (msg)
  else
    -- ATTRIBUTES
    local attr = attributes or {}
    for a,b in pairs (attr) do                    -- go through the template for names to restore
      if type(b) ~= "table" then
        luup.attr_set (a, user_data[a] or b)        -- use saved value or default
      -- note that attr_set also handles the "special" attributes which are mirrored in luup.XXX
      end
    end
    
    -- ROOMS    
    _log "loading rooms..."
    for _,x in pairs (user_data.rooms or {}) do
      rooms.create (x.name, x.id)
      _log (("room#%d '%s'"): format (x.id,x.name)) 
    end
    _log "...room loading completed"
    
    -- DEVICES  
    _log "loading devices..."    
    for _, d in ipairs (user_data.devices or {}) do
      if d.id ~= 2 then               -- device #2 is reserved
        local dev = chdev.create {      -- the variation in naming within luup is appalling
            devNo = d.id, 
            device_type     = d.device_type, 
            internal_id     = d.altid,
            description     = d.name, 
            upnp_file       = d.device_file, 
            upnp_impl       = d.impl_file or '',
            json_file       = d.device_json or '',
            ip              = d.ip, 
            mac             = d.mac, 
            hidden          = nil, 
            invisible       = d.invisible == "1",
            parent          = d.id_parent,
            room            = tonumber (d.room), 
            pluginnum       = d.plugin,
            statevariables  = d.states,      -- states : table {id, service, variable, value}
            disabled        = d.disabled,
            username        = d.username,
            password        = d.password,
          }
        dev:attr_set ("time_created", d.time_created)     -- set time_created to original, not current
        -- set other device attributes
        for a,v in pairs (d) do
          if type(v) ~= "table" and not dev.attributes[a] then
            dev:attr_set (a, v)
          end
        end
        luup.devices[d.id] = dev                          -- save it
      end 
    end 
  
    -- SCENES 
    _log "loading scenes..."
    local Nscn = 0
    for _, scene in ipairs (user_data.scenes or {}) do
      local new, msg = scenes.create (scene)
      if new and scene.id then
        Nscn = Nscn + 1
        luup.scenes[scene.id] = new
        _log (("[%s] %s"): format (scene.id or '?', scene.name))
      else
        _log (table.concat {"error in scene id ", scene.id or '?', ": ", msg or "unknown error"})
      end
    end
    _log ("number of scenes = " .. Nscn)
    
    for i,n in ipairs (luup.scenes) do _log (("scene#%d '%s'"):format (i,n.description)) end
    _log "...scene loading completed"
  
    -- PLUGINS
    _log "loading installed plugin info..."
    
    local installed = user_data.InstalledPlugins2 or {}
    local index = plugin_index (installed)
    
    -- check TargetVersion of openLuup to see if InstalledPlugins2 defaults are current   
    local ol = installed[index.openLuup] or {}
    local refresh = ol.TargetVersion ~= default_plugins_version
    
    -- copy any missing defaults (may have been deleted) to the new list
    for _, default_plugin in ipairs (default_plugins) do
      local existing = index[tostring(default_plugin.id)]
      if not existing then 
        installed[#installed+1] = default_plugin          -- add any missing defaults
      elseif refresh then 
      default_plugin.VersionMajor = installed[existing].VersionMajor  -- preserve version info
      default_plugin.VersionMinor = installed[existing].VersionMinor
      installed[existing] = default_plugin                -- out of date, so replace info anyway
      end
    end
    -- log the full list of installed plugins
    for _, plugin in ipairs (installed) do
      local version = table.concat {plugin.VersionMajor or '?', '.', plugin.VersionMinor or '?'}
      local ver = "[%s] %s (%s)"
      _log (ver: format (plugin.id, plugin.Title, version))
    end
    attr.InstalledPlugins2 = installed
  end
  _log "...user_data loading completed"
  return not msg, msg
end

--

-- user_data devices table
local function devices_table (device_list)
  local info = {}
  local serviceNo = 0
  for _,d in pairs (device_list) do 
    local states = {}
    for i,item in ipairs(d.variables) do
      states[i] = {
        id = item.id, 
        service = item.srv,
        variable = item.name,
        value = item.value,
      }
    end
    local curls 
    if d.serviceList then         -- add the ControlURLs
      curls = {}
      for _,x in ipairs (d.serviceList) do
        serviceNo = serviceNo + 1
        curls["service_" .. serviceNo] = {
          service = x.serviceId, 
          serviceType = x.serviceType, 
          ControlURL = "upnp/control/dev_" .. serviceNo,
          EventURL = "/upnp/event/dev_" .. serviceNo,
    }
      end
    end
    
    local status = d:status_get() or -1      -- 2016.04.29
--    if status == -1 then status = nil end     -- don't report 'normal' status ???
    local tbl = {     
      ControlURLs     = curls,                              
      states          = states,
      status          = status,
    }
    for a,b in pairs (d.attributes) do tbl[a] = b end
    info[#info+1] = tbl
  end
  return info
end

-- json ()
-- top-level attributes and key tables: devices, rooms, scenes
local function json_user_data (localLuup)   -- refactored thanks to @explorer
  local luup = localLuup or luup
  local data = {rooms = {}, scenes = {}}
  -- scalar attributes
  for a,b in pairs (attributes) do
    if type(b) ~= "table" then data[a] = b end
  end
  -- devices
  data.devices = devices_table (luup.devices or {})
  -- plugins
  data.InstalledPlugins2 = attributes.InstalledPlugins2 or default_plugins   -- 2016.05.15 and 2016.05.30
  -- rooms
  local rooms = data.rooms
  for i, name in pairs (luup.rooms or {}) do 
    rooms[#rooms+1] = {id = i, name = name}
  end
  -- scenes
  local scenes = data.scenes
  for _, s in pairs (luup.scenes or {}) do
    scenes[#scenes+1] = s: user_table ()
  end    
  --
  return json.encode (data)   -- json text or nil, error message if any
end
 
-- save ()
local function save_user_data (localLuup, filename)   -- refactored thanks to @explorer
  local result, message
  local j, msg = json_user_data (localLuup)

  if not j then
    message = "syntax error in user_data: " .. (msg or '?')
  else
    local f, err = io.open (filename or "user_data.json", 'w')
    if not f then
      message =  "error writing user_data: " .. (err or '?')
    else
      f:write (j)
      f:write '\n'
      f:close ()
      result = #j   -- 2016.05.09 return length of user_data.json file
    end
  end

  return result, message
end


return {
  ABOUT           = ABOUT,
  
  attributes      = attributes, 
  default_plugins = default_plugins,
  
  -- methods  
  
  devices_table       = devices_table, 
  plugin_metadata     = plugin_metadata,
  find_installed_data = find_installed_data, 

  json  = json_user_data,
  load  = load_user_data,
  save  = save_user_data,
}

