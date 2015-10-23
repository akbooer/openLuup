local version = "openLuup.loader  2015.10.22  @akbooer"

--
-- Loader for Device, Implementation, and JSON files
-- including Lua code compilation for implementations and scenes
-- and also load/save for user_data (scene and room persistence)
--
-- the reading/parsing are separate functions for easy unit testing.
--

------------------
--
-- save a pristine environment for new device contexts and scene/startup code
--

local function _pristine_environment ()
  local ENV

  local function shallow_copy2 (a)
    local b = {}
    for i,j in pairs (a) do 
      b[i] = j 
    end
    return b
  end

  local function shallow_copy (a)
    local b = {}
    for i,j in pairs (a) do 
--      if type (j) == "table" then
--        b[i] = shallow_copy2 (j)       -- TODO: check this stops people messing with system modules
--      else
        b[i] = j 
--      end
    end
    return b
  end

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

------------------

local xml  = require "openLuup.xml"
local json = require "openLuup.json"

-- parse device file, or empty table if error
local function parse_device_xml (device_xml)
  local d, service_list
  if type(device_xml) == "table" then d = device_xml.device end   -- find relevant part
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
    category_num    = d.category_num,
    device_type     = d.deviceType, 
    impl_file       = (d.implementationList or {}).implementationFile, 
    json_file       = d.staticJson, 
    friendly_name   = d.friendlyName,
    handle_children = d.handleChildren, 
    service_list    = service_list,
    subcategory_num = d.subcategory_num,
  }
end 
 
-- read and parse device file, if present
local function read_device (upnp_file)
  local info = {}
  if upnp_file then info =  parse_device_xml (xml:read (upnp_file)) end
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
      local f = io.open (fname)
      if f then
        local code = f:read "*a"
        f:close ()
        loadList[#loadList+1] = code
      end
    end
  end   
  loadList[#loadList+1] = i.functions                   -- append any xml file functions
  loadList[#loadList+1] = actions                       -- append the actions for jobs
  loadList[#loadList+1] = incoming                      -- append the incoming data handler
  local source_code = table.concat (loadList, '\n')     -- concatenate the code
  return {
    source_code = source_code,
    startup     = i.startup,
  }
end

-- read and parse implementation file, if present
local function read_impl (impl_file)
  local info = {}
  if impl_file then info =  parse_impl_xml (xml:read (impl_file)) end
  return info
end

-- parse service files
local function parse_service_xml (service_xml)
  local actions   = xml.extract (service_xml, "actionList", "action")
  local variables = xml.extract (service_xml, "serviceStateTable", "stateVariable")
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
  return {
    actions   = actions,
    returns   = returns,
    variables = variables,
  }
end 
 
-- read and parse service file, if present
-- openLuup only needs the service files to determine the return arguments for actions
-- the 'relatedStateVariable' tells what data to return for 'out' arguments
local function read_service (service_file)
  local info = {}
  if service_file then info =  parse_service_xml (xml:read (service_file)) end
  return info
end


 
-- read JSON file, if present.
-- openLuup doesn't use the json files, except to put into the static_data structure
-- which is passed on to any UI through the /data_request?id=user_Data HTTP request.
local function read_json (json_file)
  local data, msg
  local f 
  if json_file then f = io.open (json_file, 'r') end
  if f then
    local j = f: read "*a"
    if j then data, msg = json.decode (j) end
    f: close ()
  end
  return data, msg
end

-- Lua compilation

-- compile the code
-- essentially a wrapper for the loadstring function to apply the correct environment
-- optional 'globals' parameter is table of name/value pairs to place into the global environment
local function compile_lua (source_code, name, old, globals)  
  local a, error_msg = loadstring (source_code, name)    -- load it
  local env
  if a then
    env = old or new_environment (name)  -- use existing environment if supplied
    env.luup = luup                      -- add global luup table
    if globals then
      for a,b in pairs (globals) do
        env[a] = b
      end
    end
    setfenv (a, env)                     -- Lua 5.1 specific function environment handling
    a, error_msg = pcall(a)              -- instantiate it
    if not a then env = nil end          -- erase if in error
  end 
  return env, error_msg
end

-- user_data

local function load_user_data (filename)
  local user_data, message, err
  local f = io.open (filename or "user_data.json", 'r')
  if f then 
    local user_data_json = f:read "*a"
    f:close ()
    user_data, err = json.decode (user_data_json)
    if not user_data then
      message = "error in user_data: " .. err
    end
  else
    user_data = {}
    message = "cannot open user_data file"    -- not an error, _per se_, there may just be no file
  end
  return user_data, message
end


local function save_user_data (luup, filename)
  local result, message
  local f = io.open (filename or "user_data.json", 'w')
  if not f then
    message =  "error writing user_data"
  else
    -- scenes
    local scenes = {}
    for _, s in pairs (luup.scenes or {}) do
      scenes[#scenes+1] = s:user_table ()
    end
    -- rooms
    local rooms = {}
    for i, name in pairs (luup.rooms or {}) do 
      rooms[#rooms+1] = {id = i, name = name}
    end
    --
    local j, msg = json.encode {scenes = scenes, rooms = rooms}
    if j then
      f:write (j)
      result = true
    else
      message = "syntax error in user_data: " .. (msg or '?')
    end
    f:close ()
  end
  return result, message
end

return {
    compile_lua         = compile_lua,
    new_environment     = new_environment,
    parse_service_xml   = parse_service_xml,
    parse_device_xml    = parse_device_xml,
    parse_impl_xml      = parse_impl_xml,
    read_service        = read_service,
    read_device         = read_device,
    read_impl           = read_impl,
    read_json           = read_json,
    shared_environment  = new_environment "openLuup_startup_and_scenes",
--    load_user_data    = load_user_data,
--    save_user_data    = save_user_data,
    version             = version,
  }
