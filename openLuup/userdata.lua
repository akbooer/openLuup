local ABOUT = {
  NAME          = "openLuup.userdata",
  VERSION       = "2016.05.24",
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

local json    = require "openLuup.json"
local rooms   = require "openLuup.rooms"
local logs    = require "openLuup.logs"
local scenes  = require "openLuup.scenes"
local chdev   = require "openLuup.chdev"

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
  StartupCode = "",
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
  model = "Not a Vera",
--  net_pnp = "0",
--  overview_tabs = {},
--  rooms = {},
--  scenes = {},
--  sections = {},
--  setup_wizard_finished = "1",
--  shouldHelpOverlayBeHidden = true,
--  skin = "mios",
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

--
-- preset plugin data
--

local InstalledPlugins2 = {}

  InstalledPlugins2[1] =      -- we'll always put openLuup in pole position!
    {
      AllowMultiple   = "0",
      Title           = "openLuup",
      Icon            = "https://avatars.githubusercontent.com/u/4962913",
      Instructions    = "http://forum.micasaverde.com/index.php/board,79.0.html",
      AutoUpdate      = "0",
      VersionMajor    = "GitHub",
      VersionMinor    = '?',
      id              = "openLuup",
      Repository      = {          
          backup            = "plugins/backup/altui/",
          downloads         = "plugins/downloads/altui/",
          blockly_downloads = "plugins/downloads/altui/blockly/",
        },
      Files = {},
    }


  InstalledPlugins2[2] =      -- Sorry, relegated to #2 position!
    {
      AllowMultiple   = "0",
      Title           = "Alternate UI",
      Icon            = "plugins/icons/8246.png",  -- usage: http://apps.mios.com/icons/8246.png
      Instructions    = "http://forum.micasaverde.com/index.php/board,78.0.html",
      AutoUpdate      = "1",
      VersionMajor    = "GitHub",
      VersionMinor    = '?',
      id              = 8246,
      timestamp       = os.time(),
      Files           = {},
    }

  InstalledPlugins2[3] =  
    {
      AllowMultiple   = "1",
      Title           = "VeraBridge",
      Icon            = "https://raw.githubusercontent.com/akbooer/openLuup/master/VeraBridge/VeraBridge.png",
      Instructions    = "http://forum.micasaverde.com/index.php/board,79.0.html",
--        Hidden          = "0",
      AutoUpdate      = "0",
--      Version         = 28706,
      VersionMajor    = "GitHub",
      VersionMinor    = '?',
--      "SupportedPlatforms": null,
--      "MinimumVersion": null,
--      "DevStatus": null,
--      "Approved": "0",
      id              = "VeraBridge",
--      "TargetVersion": "28706",
      timestamp       = os.time(),
      Files           = {},
      Devices         = {},
      Directories     = {
        backup        = "",
        download      = "",
        install       = "",
        repository    = ""
      },
    }


  InstalledPlugins2[4] =  
    {
      AllowMultiple   = "0",
      Title           = "DataYours",
      Icon            = "https://raw.githubusercontent.com/akbooer/DataYours/master/icons/DataYours.png",
      Instructions    = "https://github.com/akbooer/DataYours/tree/master/Documentation",
      AutoUpdate      = "0",
--      Version         = 28706,
      VersionMajor    = "not",
      VersionMinor    = 'installed',
      id              = 8211,
--      "TargetVersion": "28706",
      timestamp       = os.time(),
      Files           = {},
      Devices         = {},
      Directories     = {
        backup        = "",
        download      = "",
        install       = "",
        repository    = ""
      },
    }


  InstalledPlugins2[5] = 
    {
      AllowMultiple   = "0",
      Title           = "MySensors Arduino",
      Icon            = "https://www.mysensors.org/icon/MySensors.png", 
      Instructions    = "https://github.com/mysensors/Vera/tree/UI7",
      Hidden          = "0",
      AutoUpdate      = "0",
      VersionMajor    = "not",
      VersionMinor    = "installed",
      id              = "Arduino",
      timestamp       = os.time(),
      Files           = {},
    }

  InstalledPlugins2[6] = 
    {
      AllowMultiple   = "0",
      Title           = "iPhoneLocator",
      Icon            = "https://raw.githubusercontent.com/amg0/IPhoneLocator/master/iconIPhone.png", 
      Instructions    = "https://github.com/amg0/IPhoneLocator",
      Hidden          = "0",
      AutoUpdate      = "0",
      VersionMajor    = "not",
      VersionMinor    = "installed",
      id              = "4686",
      timestamp       = os.time(),
      Files           = {},
    }


--  InstalledPlugins2[6] = 
--    {
--      AllowMultiple   = "0",
--      Title           = "Generic",
--      Icon            = "images/plugin.png", 
--      Instructions    = "http://forum.micasaverde.com/index.php/board,78.0.html",
--      Hidden          = "0",
--      AutoUpdate      = "0",
--      VersionMajor    = "MiOS_Trac",
--      VersionMinor    = '?',
--      id              = "Test",
--      timestamp       = os.time(),
--      Files           = {},
--    }



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
    local i = user_data.InstalledPlugins2
    local plugins = InstalledPlugins2
    if i and next(i) then plugins = i end
    attr.InstalledPlugins2 = plugins
    for _, plugin in ipairs (plugins) do
      _log (table.concat {"id: ", plugin.id, ", name: ", plugin.Title})
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

-- save ()
-- top-level attributes and key tables: devices, rooms, scenes
-- TODO: [, sections, users, weatherSettings]
local function save_user_data (localLuup, filename)   -- refactored thanks to @explorer
  local luup = localLuup or luup
  local result, message
  local data = {rooms = {}, scenes = {}}
  -- scalar attributes
  for a,b in pairs (attributes) do
    if type(b) ~= "table" then data[a] = b end
  end
  -- devices
  data.devices = devices_table (luup.devices or {})
  -- plugins
  data.InstalledPlugins2 = attributes.InstalledPlugins2   -- 2016.05.15
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
  local j, msg = json.encode (data)
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
  devices_table   = devices_table, 
  load            = load_user_data,
  save            = save_user_data,
}

