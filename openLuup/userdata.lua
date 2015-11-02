local version = "openLuup.user_data  2015.10.30  @akbooer"

-- user_data
-- saving and loading, plus utility functions used by HTTP requests id=user_data, etc.

local json = require "openLuup.json"

local plugins = require "openLuup.plugins"

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

local function parse_user_data (user_data_json)
  return json.decode (user_data_json)
end


local function load_user_data (filename)
  local user_data, message, err
  local f = io.open (filename or "user_data.json", 'r')
  if f then 
    local user_data_json = f:read "*a"
    f:close ()
    user_data, err = parse_user_data (user_data_json)
    if not user_data then
      message = "error in user_data: " .. err
    end
  else
    user_data = {}
    message = "cannot open user_data file"    -- not an error, _per se_, there may just be no file
  end
  return user_data, message
end

--

-- user_data devices table
local function devices_table (device_list)
  local info = {}
  local serviceNo = 0
  for _,d in pairs (device_list) do 
    local states = {}
      for serviceId, srv in pairs(d.services) do
        for name,item in pairs(srv.variables) do
          states[#states+1] = {
          id = item.id, 
          service = serviceId,
          variable = name,
          value = item.value,
        }
      end
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
    
    local tbl = {     
      ControlURLs     = curls,                              
      states          = states,
    }
    for a,b in pairs (d.attributes) do tbl[a] = b end
    info[#info+1] = tbl
  end
  return info
end

-- save ()
-- top-level attributes and key tables: devices, rooms, scenes
-- TODO: [, sections, users, weatherSettings]
local function save_user_data (luup, filename)
  local result, message
  local f = io.open (filename or "user_data.json", 'w')
  if not f then
    message =  "error writing user_data"
  else
    local data = {rooms = {}, scenes = {}}
    -- scalar attributes
    for a,b in pairs (attributes) do
      data[a] = b
    end
    -- devices
    data.devices = devices_table (luup.devices or {})
    -- plugins
    data.InstalledPlugins2 = {}   -- TODO: replace with plugins.installed()
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
    if j then
      f:write (j)
      f:write '\n'
      result = true
    else
      message = "syntax error in user_data: " .. (msg or '?')
    end
    f:close ()
  end
  return result, message
end

return {
  attributes      = attributes,
  devices_table   = devices_table, 
  load            = load_user_data,
  parse           = parse_user_data,
  save            = save_user_data,
  version         = version,
}

