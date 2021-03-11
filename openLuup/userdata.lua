local ABOUT = {
  NAME          = "openLuup.userdata",
  VERSION       = "2021.03.11",
  DESCRIPTION   = "user_data saving and loading, plus utility functions used by HTTP requests",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2021 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2021 AK Booer

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
-- 2016.08.29   update plugin versions on load
-- 2016.11.05   added gmt_offset: thanks @jswim788 and @logread
-- 2016.11.09   preserve device #2 (openLuup) room allocation across reloads (thanks @DesT)

-- 2017.01.18   add HouseMode variable to openLuup device, to mirror attribute, so this can be used as a trigger
-- 2017.04.19   sort devices_table() output (thanks @a-lurker)
-- 2017.07.19   ignore temporary "high numbered" scenes (VeraBridge)
-- 2017.08.27   fix non-numeric device ids in save_user_data()
--              ...allows renumbering of device ids using luup.attr_set()
--              ... see: http://forum.micasaverde.com/index.php/topic,50428.0.html

-- 2018.03.02   remove TODO for mode change attributes
-- 2018.03.24   use luup.rooms.create metatable method
-- 2018.04.05   do not create status as a device attribute when loading user_data
-- 2018.04.23   update_plugin_versions additions for ALT... plugins and MySensors
-- 2018.05.25   restore openLuup variables on reload (for history)
-- 2018.05.29   fix several possibly numeric attributes
-- 2018.05.29   added device (sub)category (thanks @rafale77)
-- 2018.06.26   remove DataYour from default plugins list

-- 2019.02.02   add device file manufacturer and model name (thanks @rigpapa)
-- 2019.03.18   change default currency to GBP
-- 2019.04.04   remove outdated preinstalled plugin metadata
-- 2019.04.18   fix AltAppStore showing wrong version number on Plugins page
-- 2019.05.03   don't load device attribute cpu(s)
-- 2019.05.12   use device:state_table() in devices_table()
-- 2019.05.31   update openLuup help URL to new Vera community forum
-- 2019.08.25   use local .svg icons for openLuup, AltAppStore, and VeraBridge plugins
-- 2019.10.19   add modelID attribute, per latest Vera firmware (7.30)
-- 2019.11.28   add openLuup table to saved user_data (for continuity of parameter settings between reloads)

-- 2020.01.28   replace scene:user_table() with scene.definition, following object changes in scenes
-- 2020.03.03   update ZWay implementation file to I_ZWay2.xml
-- 2020.03.31   improve plugin loading and ordering

-- 2021.03.11   remove commented out code


local json    = require "openLuup.json"
local logs    = require "openLuup.logs"
local scenes  = require "openLuup.scenes"
local chdev   = require "openLuup.chdev"
local timers  = require "openLuup.timers"   -- for gmt_offset
local lfs     = require "lfs"

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

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
  currency = "GBP",
  date_format = "dd/mm/yy",
--  device_sync = "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,18,19,20,21",
--  devices = {},
--  energy_dev_log = "41,",
--  firmware_version = "1",
  gmt_offset = tostring (timers.gmt_offset()),   -- see: http://forum.micasaverde.com/index.php/topic,40035.0.html
--  ip_requests = {},
--  ir = 0,
  latitude = "51.48",
--  local_udn = "uuid:4d494342-5342-5645-0000-000002b03069",
  longitude = "0.0",
  mode_change_delay = "30",
  mode_change_mode = '',
  mode_change_time = '',
  model = "Not a Vera",
  modelID = 0,
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
  timezone = "0",     -- apparently not used, and always "0", 
                      -- see: http://forum.micasaverde.com/index.php/topic,10276.msg70562.html#msg70562
--  users = {},
--  weatherSettings = {
--    weatherCountry = "UNITED KINGDOM",
--    weatherCity = "Oxford England",
--    tempFormat = "C" },
--  zwave_heal = "1426331082",    

-- openLuup specials

  ShutdownCode = '',
  
  LuaTestCode  = '',    -- 2019.06.11
  LuaTestCode2 = '',
  LuaTestCode3 = '',

}



-------
--
-- pre-installed plugins
--
local preinstalled = {
  
  openLuup = 

    {
      AllowMultiple   = "0",
      Title           = "openLuup",
      Icon            = "https://avatars.githubusercontent.com/u/4962913",  -- AltUI seems to need HTTPS
      Instructions    = "https://community.getvera.com/c/plugins-and-plugin-development/openluup",
      AutoUpdate      = "0",
      VersionMajor    = '',
      VersionMinor    = "baseline.",
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
      Icon            = "https://raw.githubusercontent.com/akbooer/openLuup/master/icons/VeraBridge.png",
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
  
  MySensors =

    {
      AllowMultiple   = "1",
      Title           = "MySensors",
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

  ZWay =

    {
      AllowMultiple   = "1",
      Title           = "Z-Way",
      Icon            = "https://raw.githubusercontent.com/akbooer/Z-Way/master/icons/Z-Wave.me.png", 
      Instructions    = "",
      AutoUpdate      = "0",
      VersionMajor    = "not",
      VersionMinor    = "installed",
      id              = "Z-Way",
      timestamp       = os.time(),
      Files           = {},
      Devices         = {
        {
          DeviceFileName  = "D_ZWay.xml",
          DeviceType      = "urn:akbooer-com:device:ZWay:1",
          ImplFile        = "I_ZWay2.xml",
          Invisible       =  "0",
        },
      },
      Repository      = {
        type      = "GitHub",
        source    = "akbooer/Z-Way",
--        pattern   = "",
      },
    },
  }   -- end of preinstalled plugins


local default_plugins = {
    preinstalled.openLuup,
    preinstalled.AltAppStore,
    preinstalled.VeraBridge,
    preinstalled.AltUI,
    preinstalled.ZWay,
    preinstalled.MySensors,
  }

--
-- PLUGINS
--

-- given plugin list, generate index by ID
local function plugin_index (plugins)
  local index = {}
  for i,p in ipairs (plugins) do
    index[tostring (p.id)] = i
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

-- go through the devices to see if any advertise their versions
local function update_plugin_versions (installed)
  
  -- index by plugin id and device type
  local index_by_plug = plugin_index (installed)
  local index_by_type = {}
  for i,p in ipairs (installed) do
    local id
    if p.Devices and p.Devices[1] then
      id = p.Devices[1].DeviceType
    end
    if id then index_by_type[tostring(id)] = i end
  end
  
  -- go through LOCAL devices looking for clues about their version numbers
  for _, d in pairs (luup.devices or {}) do 
    local i = index_by_plug[d.attributes.plugin] or index_by_type[d.device_type]
    local a = (d.environment or {}).ABOUT
    local IP = installed[i]
    
    local parent = d.device_num_parent
    if IP and (parent == 0 or parent == 2) then   -- LOCAL devices only! (incl. children of openLuup)
      if i and a then     -- plugins with ABOUT.VERSION
        local v1,v2,v3,prerelease = (a.VERSION or ''): match "(%d+)%D+(%d+)%D*(%d*)(%S*)"
        if v3 then
          IP.VersionMajor = v1 % 2000
          if v3 == '' then
            IP.VersionMinor = tonumber(v2)
          else
            IP.VersionMinor = table.concat ({tonumber(v2),tonumber(v3)}, '.') .. prerelease
          end
        end
      
      else    -- it gets harder, so go through variables...               example syntax
        local known = {
            ["urn:upnp-org:serviceId:altui1"]         = "Version",           --v2.15
            ["urn:upnp-org:serviceId:althue1"] 	     = "Version",           --v0.94
            ["urn:upnp-arduino-cc:serviceId:arduino1"]  = "PluginVersion",   -- 1.4
          }
        for _,v in ipairs (d.variables) do    --    (v.srv, v.name, v.value, ...)
          local name = known[v.srv]
          if name == v.name then
            IP.VersionMajor = v.value: match "v?(.*)"   -- remove leading 'v', if present
            IP.VersionMinor = ''      -- TODO: some refinement possible here with other variables?
            break
          end
        end
      end
    end
  end
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
      luup.rooms.create (x.name, x.id)            -- 2018.03.24  use luup.rooms.create metatable method
      _log (("room#%d '%s'"): format (x.id,x.name)) 
    end
    _log "...room loading completed"
    
    -- DEVICES  
    _log "loading devices..."    
    for _, d in ipairs (user_data.devices or {}) do
      if d.id == 2 then               
        
        -- device #2 is special (it's the openLuup plugin, and already exists)
        local ol = luup.devices[2]
        local room = tonumber (d.room) or 0
        ol:attr_set {room = room}     -- set the device attribute...
        ol.room_num = room            -- ... AND the device table (Luup is SO bad...)
        -- 2018.05.25 restore openLuup variables
        for _,v in ipairs ((d.states) or {}) do
          ol: variable_set (v.service, v.variable, v.value)
        end
        -- 2017.01.18 create openLuup HouseMode variable
        ol:variable_set ("openLuup", "HouseMode", luup.attr_get "Mode")  
        -- 2019.06.06 add the bookmark attribute
        ol: attr_set ("bookmark", d.bookmark)
      
      else
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
            manufacturer    = d.manufacturer,     -- 2019.02.02
            model           = d.model,            -- 2019.02.02
            parent          = d.id_parent,
            room            = tonumber (d.room), 
            pluginnum       = d.plugin,
            statevariables  = d.states,      -- states : table {id, service, variable, value}
            disabled        = d.disabled,
            username        = d.username,
            password        = d.password,
            -- 2018.05.29  added device (sub)category
            category_num    = d.category_num,
            subcategory_num = d.subcategory_num,
          }
        dev:attr_set ("time_created", d.time_created)     -- set time_created to original, not current
        -- set other device attributes (including category_num and subcategory_num)
        for a,v in pairs (d) do
          if type(v) ~= "table" and not dev.attributes[a] then
            -- 2018.04.05 status is NOT a device ATTRIBUTE
            -- 2019.05.03 cpu(s) should not be created here either!
            if not (a == "status" or a == "cpu(s)") then   
              dev:attr_set (a, v)
            end
          end
        end
        luup.devices[d.id] = dev                          -- save it
      end 
    end 
  
    -- SCENES 
    _log "loading scenes..."
    local Nscn = 0
    for _, scene in ipairs (user_data.scenes or {}) do
      if scene.id and tonumber(scene.id) < 1e5 then        -- 2017.0719 ignore temporary "high numbered" scenes (VeraBridge)
        local new, msg = scenes.create (scene)
        if new and scene.id then
          Nscn = Nscn + 1
          luup.scenes[scene.id] = new
          _log (("[%s] %s"): format (scene.id or '?', scene.name))
        else
          _log (table.concat {"error in scene id ", scene.id or '?', ": ", msg or "unknown error"})
        end
      end
    end
    _log ("number of scenes = " .. Nscn)
    
    for i,n in ipairs (luup.scenes) do _log (("scene#%d '%s'"):format (i,n.description)) end
    _log "...scene loading completed"
  
    -- PLUGINS
    _log "loading installed plugin info..."
    
--    local installed = user_data.InstalledPlugins2 or {}
    local installed = {}
    for i,p in ipairs (default_plugins) do installed[i] = p end   -- initialize installed plugins
    local index = plugin_index (installed)
    
    -- add others
    local protected = {openLuup = true, AltAppStore = true, VeraBridge = true}   -- don't mess with these
    for _, plugin in ipairs (user_data.InstalledPlugins2 or {}) do
      local existing = index[tostring(plugin.id)]
      if existing then 
        if not protected[plugin.id] then
          installed[existing] = plugin              -- replace any existing, unprotected, plugin data
        end
      else
        installed[#installed+1] = plugin            -- add any missing
      end
    end
    update_plugin_versions (installed)
    attr.InstalledPlugins2 = installed
    
    -- log the full list of installed plugins
    for _, plugin in ipairs (installed) do
      local version = table.concat {plugin.VersionMajor or '?', '.', plugin.VersionMinor or '?'}
      local ver = "[%s] %s (%s)"
      _log (ver: format (plugin.id, plugin.Title, version))
    end
  end
  _log "...user_data loading completed"
  return not msg, msg
end

--

-- user_data devices table
local function devices_table (device_list)
  local info = {}
  local serviceNo = 0
  local devs = {}
  for d in pairs (device_list) do devs[#devs+1] = d end  -- 2017.04.19
  table.sort (devs)
  for _,dnum in ipairs (devs) do 
    local d = device_list[dnum] 
    local states = d: state_table()   -- 2019.05.12
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
    local tbl = {     
      ControlURLs     = curls,                              
      states          = states,
      status          = status,
    }
    
    for a,b in pairs (d.attributes) do tbl[a] = b end
    -- 2017.08.27  fix for non-numeric device id
    -- 2018.05.29  fix several possibly numeric attributes
    local numbers = {"id", "category_num", "subcategory_num"}
    for _,name in ipairs (numbers) do
      tbl[name] = tonumber(tbl[name]) or tbl[name]    -- force numeric value, if possible
    end
    
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
  -- openLuup table attribute
  data.openLuup = attributes.openLuup         -- 2019.11.28
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
    scenes[#scenes+1] = s.definition
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
  preinstalled    = preinstalled,
  
  -- methods  
  
  devices_table           = devices_table, 
  plugin_metadata         = plugin_metadata,
  find_installed_data     = find_installed_data, 
  update_plugin_versions  = update_plugin_versions,
  
  json  = json_user_data,
  load  = load_user_data,
  save  = save_user_data,
}

