local version = "openLuup.loader  2016.02.25  @akbooer"

--
-- Loader for Device, Implementation, and JSON files
-- including Lua code compilation for implementations and scenes
-- and also load/save for user_data (scene and room persistence)
--
-- the reading/parsing are separate functions for easy unit testing.
--

-- 2016.02.22  add root tag in devices, scpd tag in services,
--             create index of short_codes in service files (for use by sdata)
-- 2016.02.23  memoize file reader
-- 2016.02.24  don't attempt to read implementation file 'X'
-- 2016.02.25  handle both .png and .swf icons (thanks @reneboer, and @vosmont)

------------------
--
-- save a pristine environment for new device contexts and scene/startup code
--

local function shallow_copy (a)
  local b = {}
  for i,j in pairs (a) do 
      b[i] = j 
  end
  return b
end

local function _pristine_environment ()
  local ENV

  local function new_environment (name)
    local new = shallow_copy (ENV)
    new._NAME = name                -- add environment name global
    new._G = new                    -- self reference - this IS the new global environment
    return new 
  end

  ENV = shallow_copy (_G)           -- copy the original _G environment
  ENV.arg = nil                     -- don't want to expose command line arguments
  ENV.module = function () end      -- module is noop
  return new_environment
end

local new_environment = _pristine_environment ()

local shared_environment  = new_environment "openLuup_startup_and_scenes"

local service_data = {}         -- cache for serviceType and serviceId data, indexed by both

local static_data = {}          -- cache for decoded static JSON data, indexed by filename

------------------

local xml  = require "openLuup.xml"
local json = require "openLuup.json"


----
--
-- CONSTANTS
--

local mcv  = "urn:schemas-micasaverde-com:device:"
local upnp = "urn:schemas-upnp-org:device:"

local categories_lookup =             -- info about device types and categories
  {
      {id =  1, name = "Interface",          type = mcv  .. "HomeAutomationGateway:1"},
      {id =  2, name = "Dimmable Switch",    type = upnp .. "DimmableLight:1"},  
      {id =  3, name = "On/Off Switch",      type = upnp .. "BinaryLight:1"},
      {id =  4, name = "Sensor",             type = mcv  .. "DoorSensor:1"},
      {id =  5, name = "HVAC",               type = upnp .. "HVAC_ZoneThermostat:1"}, 
      {id =  6, name = "Camera",             type = upnp .. "DigitalSecurityCamera:1"},  
      {id =  6, name = "Camera",             type = upnp .. "DigitalSecurityCamera:2"},  
      {id =  7, name = "Door Lock",          type = mcv  .. "DoorLock:1"},
      {id =  8, name = "Window Covering",    type = mcv  .. "WindowCovering:1"},
      {id =  9, name = "Remote Control",     type = mcv  .. "RemoteControl:1"}, 
      {id = 10, name = "IR Transmitter",     type = mcv  .. "IrTransmitter:1"}, 
      {id = 11, name = "Generic I/O",        type = mcv  .. "GenericIO:1"},
      {id = 12, name = "Generic Sensor",     type = mcv  .. "GenericSensor:1"},
      {id = 13, name = "Serial Port",        type =         "urn:micasaverde-org:device:SerialPort:1"},  -- yes, it really IS different       
      {id = 14, name = "Scene Controller",   type = mcv  .. "SceneController:1"},
      {id = 15, name = "A/V",                type = mcv  .. "avmisc:1"},
      {id = 16, name = "Humidity Sensor",    type = mcv  .. "HumiditySensor:1"},
      {id = 17, name = "Temperature Sensor", type = mcv  .. "TemperatureSensor:1"},
      {id = 18, name = "Light Sensor",       type = mcv  .. "LightSensor:1"},
      {id = 19, name = "Z-Wave Interface",   type = mcv  .. "ZWaveNetwork:1"},
      {id = 20, name = "Insteon Interface",  type = mcv  .. "InsteonNetwork:1"},
      {id = 21, name = "Power Meter",        type = mcv  .. "PowerMeter:1"},
      {id = 22, name = "Alarm Panel",        type = mcv  .. "AlarmPanel:1"},
      {id = 23, name = "Alarm Partition",    type = mcv  .. "AlarmPartition:1"},
      {id = 23, name = "Alarm Partition",    type = mcv  .. "AlarmPartition:2"},
      {id = 24, name = "Siren",              type = mcv  .. "Siren:1"},
  }

local cat_by_dev = {}                         -- category number lookup by device type
local cat_name_by_dev = {}                    -- category  name  lookup by device type
for _,cat in ipairs (categories_lookup) do
  cat_by_dev[cat.type] = cat.id 
  cat_name_by_dev[cat.type] = cat.name 
end


--  utilities

-- memoize: return new function which caches its previously computed results
local function memoize (fct)
  local cache = setmetatable ({}, {__mode = "kv"})
  return function (x)
--    if cache[x] then print ("HIT", x) else print ('',"MISS",x) end
    cache[x] = cache[x] or fct(x)
    return cache[x]
  end
end


local function raw_read (filename)
  local f = io.open (filename) 
  if not f then f = io.open ("../cmh-lu/" .. filename) end    -- look in 'cmh-lu/' directory
  if f then 
    local data = f: read "*a"
    f: close () 
    return data
  end
end

local cached_read = memoize (raw_read)    -- 2016.02.23

local function xml_read (filename)
  local info = cached_read (filename) 
  return xml.decode(info)
end

-- parse device file, or empty table if error
local function parse_device_xml (device_xml)
  local d, service_list
  if type(device_xml) == "table" and device_xml.root then -- 2016.02.22, added 'root' nesting
    d = device_xml.root.device    -- find relevant part
  end
  local x = d or {}                                               -- ensure there's something there  
  d = {}
  for a,b in pairs (x) do
    d[a] = b              -- retain original capitalisation...
    d[a:lower()] = b      -- ... and fold to lower case
  end
  -- save service list
  local URLs = d.serviceList
  if URLs and URLs.service then
    URLs = URLs.service
    if #URLs == 0 then URLs = {URLs} end      -- make it a one-element list
    service_list = URLs
  end
  return {
    -- notice the name inconsistencies in some of these entries,
    -- that's why we re-write the whole thing, rather than just pass the read device object
    -- NOTE: every parameter in the file of interest MUST be declared here or will not be visible
    category_num    = d.category_num,
    device_type     = d.deviceType, 
    impl_file       = (d.implementationList or {}).implementationFile, 
    json_file       = d.staticJson, 
    friendly_name   = d.friendlyName,
    handle_children = d.handleChildren, 
    manufacturer    = d.manufacturer,
    modelName       = d.modelName,
    protocol        = d.protocol,
    service_list    = service_list,
    subcategory_num = d.subcategory_num,
  }
end 
 
-- read and parse device file, if present
local function read_device (upnp_file)
  local info = {}
  if upnp_file then info =  parse_device_xml (xml_read (upnp_file)) end
  return info
end

-- utility function: given an action structure from an implementation file, build a compilable object
-- with all the supplied action tags (run / job / timeout / incoming) and name and serviceId.
local function build_action_tags (actions)
  local top  = " = function (lul_device, lul_settings, lul_job, lul_data) "
  local tail = " end, "
  local tags = {"run", "job", "timeout", "incoming"}
  if #actions == 0 then actions = {actions} end   -- make it a one-element list
  local action = {"_openLuup_ACTIONS_ = {"}
  for _, a in ipairs (actions) do
    if a.name and a.serviceId then
      local object = {'{ name = "', a.name, '", serviceId = "', a.serviceId, '", '}
      for _, tag in ipairs (tags) do
        if a[tag] then
          object[#object+1] = table.concat{tag, top, a[tag], tail}
        end
      end
      object[#object+1] = ' }, '
      action[#action+1] = table.concat (object)
    end
  end
  action[#action+1] = '}'
  return table.concat (action or {}, '\n')
end

-- build <incoming> handler
local function build_incoming (lua)
  return table.concat ({
    "function _openLuup_INCOMING_ (lul_device, lul_data)",
    lua,
    "end"}, '\n')
end

-- read implementation file, if present, and build actions, files, and code.
local function parse_impl_xml (impl_xml)
  local i, actions, incoming
  if type (impl_xml) == "table" then i = impl_xml.implementation end    -- find relevant part
  i = i or {}                                                           -- ensure there's something there 
  -- build actions into an array called "_openLuup_ACTIONS_" 
  -- which will be subsequently compiled and linked into the device's services
  if i.actionList and i.actionList.action then
    actions = build_action_tags (i.actionList.action)
  end
  -- build general <incoming> tag (not job specific ones)
  if i.incoming and i.incoming.lua then
    incoming = build_incoming (i.incoming.lua)
  end
  -- load 
  local loadList = {}   
  if i.files then 
    for fname in i.files:gmatch "[%w%_%-%.%/%\\]+" do
      loadList[#loadList+1] = raw_read (fname)          -- 2016.02.23 not much point in caching .lua files
    end
  end   
  loadList[#loadList+1] = i.functions                   -- append any xml file functions
  loadList[#loadList+1] = actions                       -- append the actions for jobs
  loadList[#loadList+1] = incoming                      -- append the incoming data handler
  local source_code = table.concat (loadList, '\n')     -- concatenate the code
--  local gsub = {lt = '<', gt = '>', amp = '&'}
--  source_code = source_code: gsub ("&(%w+);", gsub)     -- fix all XML quoted characters
  return {
    protocol    = i.settings and i.settings.protocol,   -- may be defined here, but more normally in device file
    source_code = source_code,
    startup     = i.startup,
  }
end

-- read and parse implementation file, if present
local function read_impl (impl_file)
  local info = {}
  if impl_file and impl_file ~= 'X' then info =  parse_impl_xml (xml_read (impl_file)) end
  return info
end

-- parse service files
local function parse_service_xml (service_xml)
  local actions   = xml.extract (service_xml, "scpd", "actionList", "action")   -- 2016.02.22 added "scpd" nesting
  local variables = xml.extract (service_xml, "scpd", "serviceStateTable", "stateVariable") -- ditto
  -- now build the return argument list  {returnName = RelatedStateVariable, ...}
  -- indexed by action name
  local returns = {}
  for _,a in ipairs (actions) do
    local argument = xml.extract (a, "argumentList", "argument")
    local list = {}
    for _,k in ipairs (argument) do
      if k.direction: match "out" and k.name and k.relatedStateVariable then
        list [k.name] = k.relatedStateVariable
      end
    end
    returns[a.name] = list
  end
  -- now build lookup table of short_codes (for use by sdata request)
  local short_codes = {}
  for _,v in ipairs (variables) do
    short_codes[v.name] = v.shortCode
  end
  
  return {
    actions     = actions,
    returns     = returns,
    short_codes = short_codes,
    variables   = variables,
  }
end 
 
-- read and parse service file, if present
-- openLuup only needs the service files to determine the return arguments for actions
-- the 'relatedStateVariable' tells what data to return for 'out' arguments
local function read_service (service_file)
  local info = {}
  if service_file then info =  parse_service_xml (xml_read (service_file)) end
  return info
end

local icon_path      -- redirect path set by function below (if called at all)

-- called with new path for icon access, eg "http://172.16.42.151:3480/icons/"
local function icon_redirect (path)
  icon_path = json.encode (path): sub (1,-2)    -- strip off trailing double quote character
end

-- force port 3480 access for all icons
local function rewrite_icon_path (j)
  return (j: gsub ('"[^"]+%.[ps][nw][gf]"', 
    function (x)
      if x: match '"http' then return x end
      local new = icon_path .. x: match '[^"/=]+%.%a+"'
--      print ("icon: ", x, new)
      return new
    end
    ))
end


-- read JSON file, if present.
-- openLuup doesn't use the json files, except to put into the static_data structure
-- which is passed on to any UI through the /data_request?id=user_Data HTTP request.
local function read_json (json_file)
  local data, msg
  if json_file then 
    local j = raw_read (json_file)        -- 2016.02.23, no point in caching since Lua structure itself is cached below
    if j then 
      if icon_path then                   -- 2016.02.23
        j = rewrite_icon_path (j)
      end
      data, msg = json.decode (j) 
    end
  end
  return data, msg
end

-- Lua compilation

-- compile the code
-- essentially a wrapper for the loadstring function to apply the correct environment
local function compile_lua (source_code, name, old)  
  local a, error_msg = loadstring (source_code, name)    -- load it
  local env
  if a then
    env = old or new_environment (name)  -- use existing environment if supplied
--    env.luup = luup                      -- add the global luup table
    env.luup = shallow_copy (luup)       -- add a COPY of the global luup table
    -- ... so that luup.device can be unique for each environment
    setfenv (a, env)                     -- Lua 5.1 specific function environment handling
    a, error_msg = pcall(a)              -- instantiate it
    if not a then env = nil end          -- erase if in error
  end 
  return env, error_msg
end


-- the definition of a device with UPnP xml files is a complete mess.  
-- The functional definition is sprayed over a variety of files with various inter-dependencies.
-- This function attempts to wrap the assembly into one place.
-- defined filename parameters override the definitions embedded in other files.
local function assemble_device_from_files (devNo, device_type, upnp_file, upnp_impl, json_file)
  
  -- returns non-blank contents of x or nil
  local function non_blank (x) 
    return x and x: match "%S+"
  end
    
  -- read device file, if present  
  local d = read_device (upnp_file)                
  d.device_type = non_blank (d.device_type) or device_type      --  file overrides parameter
  -- read service files, if referenced, and save service_data
  if d.service_list then
    for _,x in ipairs (d.service_list) do
      local stype = x.serviceType 
      if stype then
        if not service_data[stype] then                       -- if not previously stored
          local sfile = x.SCPDURL
          service_data[stype] = read_service (sfile)    -- save the serviceType details
        end
        local sid = x.serviceId
        if sid then
          service_data[sid] = service_data[stype]             -- point the serviceId to the same
        end
      end
    end
  end

  -- read JSON file, if present and not already cached, and save it in static_data structure
  local file = non_blank (json_file) or d.json_file     -- parameter overrides file
  d.json_file = file                                    -- update file actually used 
  if file and not static_data[file] then
    local json = read_json (file)  
    if json then
      json.device_json = file       -- insert possibly missing info (for ALTUI icons - thanks @amg0!)
    end
    static_data [file] = json  
  end
  
  -- read implementation file, if present  
  file = non_blank(upnp_impl) or d.impl_file          -- parameter overrides file
  d.impl_file = file                                  -- update file actually used
  local i = {}
  if file then 
    i = read_impl (file) 
  end
  
  -- load and compile the amalgamated code from <files>, <functions>, <actions>, and <startup> tags
  local code, error_msg
  if i.source_code then
    local name = ("[%d] %s"): format (devNo, file or '?')
    code, error_msg = compile_lua (i.source_code, name)  -- load, compile, instantiate    
    if code then 
      code.luup.device = devNo        -- set local value for luup.device
      code.lul_device  = devNo        -- make lul_device in scope for the whole module
    end
    i.source_code = nil   -- free up for garbage collection
  end
  
  -- look for protocol in both device and implementation files 
  d.protocol = d.protocol or i.protocol
  
  -- set up code environment (for context switching)
  code = code or {}
  d.environment     = code  
  
  -- add category information  
  d.category_num    = tonumber (d.category_num) or cat_by_dev[device_type] or 0
  d.category_name   = cat_name_by_dev [device_type]
  
  -- dereference code entry point
  d.entry_point = code[i.startup or ''] 
  
  -- dereference action list 
  d.action_list     = code._openLuup_ACTIONS_
  code._openLuup_ACTIONS_ = nil             -- remove from code name space
  
  -- dereference incoming asynchronous I/O callback
  d.incoming = code._openLuup_INCOMING_
  code._openLuup_INCOMING_ = nil             -- remove from code name space

  return d, error_msg
end


return {
    -- tables
    service_data        = service_data,
    shared_environment  = shared_environment,
    static_data         = static_data,  
    
    -- methods
    assemble_device     = assemble_device_from_files,
    compile_lua         = compile_lua,
    icon_redirect       = icon_redirect,
    new_environment     = new_environment,
    parse_service_xml   = parse_service_xml,
    parse_device_xml    = parse_device_xml,
    parse_impl_xml      = parse_impl_xml,
    read_service        = read_service,
    read_device         = read_device,
    read_impl           = read_impl,
    read_json           = read_json,
    version             = version,
  }
