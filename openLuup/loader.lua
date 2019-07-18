local ABOUT = {
  NAME          = "openLuup.loader",
  VERSION       = "2019.07.14.",
  DESCRIPTION   = "Loader for Device, Service, Implementation, and JSON files",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2019 AK Booer

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

--
-- Loader for Device, Implementation, and JSON files
-- including Lua code compilation for implementations and scenes
--
-- the reading/parsing are separate functions for easy unit testing.
--

-- 2016.02.22  add root tag in devices, scpd tag in services,
--             create index of short_codes in service files (for use by sdata)
-- 2016.02.23  memoize file reader
-- 2016.02.24  don't attempt to read implementation file 'X'
-- 2016.02.25  handle both .png and .swf icons (thanks @reneboer, and @vosmont)
-- 2016.03.19  honour order of <files> and <functions> in implementation files (thanks @logread and @cybrmage)
-- 2016.04.14  @explorer added device category name lookup by category number. 
-- 2016.04.16  tidy up some previous edits
-- 2016.05.12  pre-load openLuup static data
-- 2016.05.21  fix for invalid argument list in parse_service_xml
-- 2016.05.24  virtual file system for system .xml and .json files
-- 2016.06.09  also look in files/ directory
-- 2016.06.18  also look in openLuup/ directory (for AltAppStore)
-- 2016.11.06  make "crlf" the default I/O protocol
--             see: http://forum.micasaverde.com/index.php/topic,37661.msg298022.html#msg298022

-- 2018.02.19  remove obsolete icon_redirect functionality (now done in servlet file request handler)
-- 2018.03.13  add handleChildren to implementation file parser
-- 2018.03.17  changes to enable plugin debugging by ZeroBrane Studio (thanks @explorer)
--             see: http://forum.micasaverde.com/index.php/topic,38471.0.html
-- 2018.04.06  use scheduler.context_switch to wrap device code compilation (for sandboxing)
-- 2018.04.22  parse_impl_xml added action field for /data_request?id=lua&DeviceNum=... 
-- 2018.05.10  SUBSTANTIAL REWRITE, to accomodate new XML DOM parser
-- 2018.05.26  add new line before action end - beware final comment lines!! Debug dump erroneous source code.
-- 2018.07.15  change search path order in raw_read()
-- 2018.11.21  implement find_file (for @rigpapa)

-- 2019.04.12  change cached_read() to use virtualfilesystem explicitly (to register cache hits)
-- 2019.04.14  do not cache service or implementation .xml files 
-- 2019.05.29  find_file() also looks in built-in/ for 'last chance' files
-- 2019.06.02  export cat_by_dev table for chdev to set device category (thanks @reneboer)
-- 2019.06.12  move compile_and_run here from loader (to be used also by console)
-- 2019.06.16  add loader.dir() to walk search path
-- 2019.07.14  use new XML Document methods


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
--    new.table = shallow_copy (ENV.table)    -- can sandbox individual tables like this, if necessary
--    but string library has to be sandboxed quite differently, see scheduler sandbox function
    return new 
  end

  ENV = shallow_copy (_G)           -- copy the original _G environment
  ENV.arg = nil                     -- don't want to expose command line arguments
  ENV.ABOUT = nil                   -- or this module's ABOUT!
  ENV.module = function () end      -- module is noop
  ENV.socket = nil                  -- somehow this got in there (from openLuup.log?)
  ENV._G = nil                      -- each one gets its own, above
  return new_environment
end

local new_environment = _pristine_environment ()

local shared_environment  = new_environment "openLuup_startup_and_scenes"

------------------

local lfs = require "lfs"
local json = require "openLuup.json"
local vfs  = require "openLuup.virtualfilesystem"
local scheduler = require "openLuup.scheduler"  -- for context_switch()
local xml = require "openLuup.xml"

local service_data = {}         -- cache for serviceType and serviceId data, indexed by both

local static_data = {}          -- cache for decoded static JSON data, indexed by filename


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
--[[
also:  --TODO: find out device types for new categories
  25 	Weather 		
  26 	Philips Controller 		
  27 	Appliance 		
  28 	UV Sensor 		
  29 	Mouse Trap 		
  30 	Doorbell 		
  31 	Keypad
]]
}

local cat_by_dev = {}                         -- category number lookup by device type
local cat_name_by_dev = {}                    -- category  name  lookup by device type
local cat_name_by_num = {}                    -- category  name  lookup by category num
for _, cat in ipairs (categories_lookup) do
  cat_by_dev[cat.type] = cat.id 
  cat_name_by_dev[cat.type] = cat.name 
  cat_name_by_num[cat.id] = cat.name 
end


--  utilities

-- 2019.06.11 add pretty() to shared environment:


-- pretty (), 
-- pretty-print for Lua
-- 2014.06.26   @akbooer
-- 2015.11.29   use names for global variables (ie. don't expand _G or system libraries)
--              use fully qualified path names for circular references
--              improve formatting of isolated nils in otherwise contiguous numeric arrays
--              improve formatting of nested tables
-- 2016.01.09   fix for {a = false}
-- 2016.02.26   use rawget to investigate array numeric indices, preload enc[_G] = _G only
-- 2016.03.10   fix for {nil,nil, 3,nil,5}
-- 2019.06.25   fix for out of order discontiguous numeric indices {nil,nil,3, [42]=42, nil,nil,nil,7,8,9}

----------------------------


function shared_environment.pretty (Lua)        -- 2014 - 2019.06.25   @akbooer
  local L, N_NILS = {}, 2                       -- number of allowed nils between contiguous numeric indices
  local tab, enc = '  ', {[_G] = "_G"}          -- don't expand global environment
  local function p(...) for _, x in ipairs {...} do if x~='' then L[#L+1] = x end; end; end
  local function ctrl(y) return ("\\%03d"): format (y:byte ()) end          -- deal with escapes, etc.
  local function quote(x) return x:match '"' and "'" or '"' end             -- pick appropriate quotation mark
  local function str_obj(x) local q = quote(x); return table.concat {q, x:gsub ("[\001-\031]", ctrl), q} end
  local function brk_idx(x) return '[' .. tostring(x) .. ']' end
  local function str_idx(x) return x:match "^[%a_][%w_]*$" or brk_idx(str_obj (x)) end
  local function val (x, depth, name) 
    if name == "_G" or enc[x] then p(enc[x] or "_G") return end             -- previously encoded
    local t = type(x)
    if t == "string" then p(str_obj (x))  return end
    if t ~= "table"  then p(tostring (x)) return end
    if not next(x) then p "{}" return end
    local id_num, id_str = {}, {}
    for i in pairs(x) do 
      if type(i) == "number" then id_num[#id_num+1]=i else id_str[#id_str+1]= i end 
    end
    
    enc[x] = name; depth = depth + 1; p '{'                                 -- start encoding this table
    local nl1, nl2 = '\n'..tab:rep (depth), '\n'..tab:rep (depth-1) 
    
    table.sort (id_num)
    local i, num_lines, nl_num = 1, 0, ''
    for _,j in ipairs (id_num) do                                            -- numeric indices
      if (j > 0) and (i + N_NILS >= j) then                                  -- contiguous indices
        p(nl_num); nl_num=''
        for _ = i, j - 1 do p "nil," end
        val (x[j], depth, name..brk_idx (j)) ; p ','
        i = j + 1
      else                                                                  -- discontiguous indices
        nl_num = nl1
        num_lines = num_lines + 1
        local fmt_idx = brk_idx (j)
        p (nl_num, fmt_idx, " = "); val (x[j], depth, name..fmt_idx); p (',')
      end
    end

    table.sort (id_str, function(a,b) return tostring(a) < tostring(b) end)
    local nl_str = (#id_str > 1 or #id_num > 0) and nl1 or ''
    for _,j in ipairs (id_str) do                                           -- non-numeric indices
      local fmt_idx = str_idx(tostring(j))
      p (nl_str, fmt_idx, " = "); val (x[j], depth, name..'.'..fmt_idx); p (',')
    end
    L[#L] = nil                                                             -- stomp over final comma
    if num_lines + #id_str > 1 then p(nl2) end                              -- indent file brace, if necessary
    enc[x] = nil; p '}'                                                     -- finish encoding this table
  end
  val(Lua, 0, '_') 
  return table.concat(L) 
end 

 
function shared_environment.pretty_old (Lua)    -- 2014 - 2016.03.10   @akbooer
  local con, tab, enc = table.concat, '  ', {[_G] = "_G"}                -- don't expand global environment
  local function ctrl(y) return ("\\%03d"): format (y:byte ()) end       -- deal with escapes, etc.
  local function str_obj(x) return '"' .. x:gsub ("[\001-\031]", ctrl) .. '"' end
  local function brk_idx(x) return '[' .. tostring(x) .. ']' end
  local function str_idx(x) return x:match "^[%a_][%w_]*$" or brk_idx(str_obj (x)) end
  local function nl (d,x) if x then return '\n'..tab:rep (d),'\n'..tab:rep (d-1) else return '','' end end
  local function val (x, depth, name) 
    if enc[x] then return enc[x] end                                    -- previously encoded
    local t = type(x)
    if t ~= "table" then return (({string = str_obj})[t] or tostring) (x) end
    enc[x] = name                                                       -- start encoding this table
    local idx, its, y = {}, {}, {rawget (x,1) or rawget (x,2) and true}
    for i in pairs(x) do                                                -- fix isolated nil numeric indices
      y[i] = true; if (type(i) == "number") and rawget(x,i+2) then y[i+1] = true end
    end
    for i in ipairs(y) do                                               -- contiguous numeric indices
      y[i] = nil; its[i] = val (rawget(x,i), depth+1, con {name,'[',i,']'}) 
    end
    if #its > 0 then its = {con (its, ',')} end                         -- collapse to single line
    for i in pairs(y) do 
      if (rawget(x,i) ~= nil) then idx[#idx+1] = i end                  -- list and sort remaining non-nil indices
    end
    table.sort (idx, function (a,b) return tostring(a) < tostring(b) end)
    for _,j in ipairs (idx) do                                          -- remaining indices
      local fmt_idx = (({string = str_idx})[type(j)] or brk_idx) (j)
      its[#its+1] = fmt_idx .." = ".. val (x[j], depth+1, name..'.'..fmt_idx) 
    end
    enc[x] = nil                                                        -- finish encoding this table
    local nl1, nl2 = nl(depth, #idx > 1)                                -- indent multiline tables 
    return con {'{', nl1, con {con (its, ','..nl1) }, nl2, '}'}         -- put it all together
  end
  return val(Lua, 1, '_') 
end 


-- 2019.06.16  dir() walks search path, with optional filename pattern
local paths = {"openLuup/", "./", "../cmh-lu/" , "files/", "www/"}

local function dir (pattern)
  local fname = {}
  for _, path in ipairs(paths) do
    if lfs.attributes (path) then     -- lfs.dir() throws an error if path doesn't exist
      for file in lfs.dir (path) do
        if not pattern or file: match (pattern) then
          fname[file] = true    -- overwrite duplicates
        end
      end
    end
  end
  for filepath in vfs.dir() do
    local file = filepath: match "[^/]+$"       -- remove any leading directory tree
    if not pattern or file: match (pattern) then
      fname[file] = true    -- overwrite duplicates
    end
  end
  local files = {}
  for f in pairs (fname) do
      files[#files+1] = f
  end
  table.sort (files)
  local j = 0
  return function () j = j+1; return files[j] end
end

-- 2018.11.21  return search path and file descriptor
local function open_file (filename)
-- 2018.07.15  changed search path order to look first in openLuup/ (for system files, esp. VeraBridge)
  local fullpath
  local function open (path, vfs)
    fullpath = path .. filename
    return (vfs or io).open (fullpath, 'rb')
  end
  local f = open "openLuup/"        -- 2016.06.18  look in openLuup/ (for AltAppStore)
    or open "./"                    -- current directory (cmh-ludl/) 
    or open "../cmh-lu/"            -- look in 'cmh-lu/' directory
    or open "files/"                -- 2016.06.09  also look in files/
    or open "www/"                  -- 2018.02.15  also look in www/
    or open ("built-in/", vfs)      -- 2019.05.29  also look in built-in/ for 'last chance' files
  return f, fullpath
end  

-- find the full path name of a file
local function find_file (filename)
  local f, path = open_file (filename)
  if f then
    f: close ()
    return path
  end
end

-- 2019.04.14  cached read, using the virtualfilesystem, and caching result if cache parameter non-nil
local function cached_read (filename, cache)     -- 2016.02.23, and 2019.04.12
  local errmsg
  local content = vfs.read (filename)                     -- always try the cache first
  if not content then
    local f, errmsg = open_file (filename)                -- otherwise, the actual file system
    if f then 
      content = f: read "*a"
      f: close () 
    end
    if not content then                                   -- still none, so error
      errmsg = "raw_read: " .. (errmsg or "error reading: " .. (filename or '?'))
    elseif cache then 
      vfs.write (filename, content)           -- put it into the permanent cache for next time
    end
  end
  return content, errmsg
end

-- raw_read, NOT caching the result
local function raw_read (filename)
  return cached_read (filename, false)
end

-- read xml file, caching the result if cache parameter non-nil
local function xml_read (filename, cache)
  filename = filename or "(missing filename)"
  local raw_xml = cached_read (filename, cache) 
  if not raw_xml then
    return nil, "ERROR: unable to read XML file " .. filename
  end
  local x = xml.decode(raw_xml)
  if not x.documentElement then     -- invalid or missing XML
    return nil, "ERROR: invalid XML file: " .. filename
  end
  return x, raw_xml   -- 2016.03.19   return raw_xml for order-sensitive processing
end

-- DEVICES

-- parse device file, or empty table if error
local function parse_device_xml (xmlDoc)
  
  local root = xmlDoc.documentElement
  if root.nodeName ~= "root" then error ("Device XML root element name is not 'root'") end
  -- should also check root.xmlns == "urn:schemas-upnp-org:device-1-0"
  
  local device = xmlDoc.xpath (root, "//device") [1]
  if not device then error ("device file syntax error", 1) end
    
  local d = {}
  for _,x in ipairs (device.childNodes) do
    d[x.nodeName:lower()] = x.textContent            -- force lower case versions
  end
  
  local impl = xmlDoc.xpath (device, "//implementationList/implementationFile") [1]
  local impl_file = (impl or {}).textContent
  
  local service_list = {}
  for svc in xmlDoc.xpathIterator (device, "//serviceList/service") do
    local service = {}
    for _,x in ipairs (svc.childNodes) do service[x.nodeName] = x.textContent end
    service_list[#service_list+1] = service
  end
  
  return {
    -- notice the name inconsistencies in some of these entries,
    -- that's why we re-write the whole thing, rather than just pass the read device object
    -- NOTE: every parameter in the file of interest MUST be declared here or will not be visible
    category_num    = tonumber (d.category_num),
    device_type     = d.devicetype, 
    impl_file       = impl_file, 
    json_file       = d.staticjson, 
    friendly_name   = d.friendlyname,
    handle_children = d.handlechildren, 
    local_udn       = d.local_udn,
    manufacturer    = d.manufacturer,
    modelName       = d.modelname,
    protocol        = d.protocol,
    service_list    = service_list,
    subcategory_num = tonumber (d.subcategory_num),
  }
end 

-- read and parse device file, if present
local function read_device (upnp_file)
  local info
  local x, errmsg = xml_read (upnp_file, true)    -- ...and cache the result
  if x then info = parse_device_xml (x) end
  return info, errmsg
end

-- IMPLEMENTATIONS

-- utility function: given an action structure from an implementation file, build a compilable object
-- with all the supplied action tags (run / job / timeout / incoming) and name and serviceId.
local function build_action_tags (actions)
  local top  = " = function (lul_device, lul_settings, lul_job, lul_data) "
  local tail = "\n end, "     -- 2018.05.26  add new line before action end... beware final comment lines!!
  local tags = {"run", "job", "timeout", "incoming"}
  
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
      lua or '',
      "end"}, '\n')
end


-- read implementation file, if present, and build actions, files, and code.
local function parse_impl_xml (xmlDoc, raw_xml)
  
  local implementation = xmlDoc.documentElement
  if implementation.nodeName ~= "implementation" then 
    error ("Implementation XML root element name is not 'implementation'") end
  -- apparently, no namespace to check!
  
  local i = {}
  -- get the basic text elements
  for _, x in ipairs (implementation.childNodes) do
    local name, value = x.nodeName, x.textContent
    i[name:lower()] = value      -- force lower case version, --TODO: value may be nil?? NOT with textContent
  end
  
  -- build general <incoming> tag (not job specific ones)
  local incoming_lua = xmlDoc.xpath (implementation, "//incoming/lua") [1]
  local lua = (incoming_lua or {}).textContent
  local incoming = build_incoming (lua)
  

  local settings_protocol = xmlDoc.xpath (implementation, "//settings/protocol") [1]
  local protocol = (settings_protocol or {}).textContent
  
  -- build actions into an array called "_openLuup_ACTIONS_" 
  -- which will be subsequently compiled and linked into the device's services
  local action_list = {}
  for act in xmlDoc.xpathIterator (implementation, "//actionList/action") do
    local action = {}
    for _,x in ipairs (act.childNodes) do action[x.nodeName] = x.textContent end
    action_list[#action_list+1] = action
  end
  local actions = build_action_tags (action_list)
  
  -- 2016.03.19  determine the order of <files> and <functions> tags
  raw_xml = raw_xml or ''
  local file_pos = raw_xml:find "<files>" or 0
  local func_pos = raw_xml:find "<functions>" or 0
  local files_first = file_pos < func_pos   
  
  ----------
  --
  -- 2018.03.17 from @explorer: ZeroBrane debugging support:
  -- determine the number of line breaks in the XML before functions start and insert them in front
  -- of the functions to help debugger’s current position when going through the code from I_device.xml
  local functions = i.functions or ''
  local _, line_count = string.gsub( raw_xml:sub(0, func_pos), "\n", "")
  functions = string.rep("\n", line_count) .. functions
  --
  ----------
  
  -- load 
  local loadList = {}   
  local files = i.files or ''
  if not files_first then loadList[#loadList+1] = functions end   -- append any xml file functions
  for fname in files:gmatch "[%w%_%-%.%/%\\]+" do
    loadList[#loadList+1] = raw_read (fname)          -- 2016.02.23 not much point in caching .lua files
  end
  
  if files_first then loadList[#loadList+1] = functions end     -- append any xml file functions
  loadList[#loadList+1] = actions                               -- append the actions for jobs
  loadList[#loadList+1] = incoming                              -- append the incoming data handler
  local source_code = table.concat (loadList, '\n')             -- concatenate the code

  return {
    handle_children = i.handlechildren,     -- 2018.03.13
    protocol    = protocol,                 -- may be defined here, but more normally in device file
    source_code = source_code,
    startup     = i.startup,
    files       = files,                    -- 2018.03.17  ZeroBrane debugging support
    actions     = actions,                  -- 2018.04.22  added for /data_request?id=lua
  }
end

-- read and parse implementation file, if present
local function read_impl (impl_file)
  if impl_file == 'X' then return {}, '' end  -- special no-op name used by VeraBridge

  local info
  -- 2016.03.19  NOTE: that xml_read returns TWO parameters: a table structure AND the raw xml text
  local x, raw = xml_read (impl_file)   -- raw contains error message if x is nil
  if x then 
    info = parse_impl_xml (x, raw) 
  end
  return info, raw
end

-- SERVICES

-- parse service files
local function parse_service_xml (xmlDoc)
  
  local scpd = xmlDoc.documentElement
  if scpd.nodeName ~= "scpd" then 
    error ("Service XML root element name is not 'scpd'") end
  -- should also check scpd.xmlns == "urn:schemas-upnp-org:device-1-0"
  
  local variables = {}
  local short_codes = {}          -- lookup table of short_codes (for use by sdata request)
  for var in xmlDoc.xpathIterator (scpd, "//serviceStateTable/stateVariable") do
    local variable = {}
    for _,x in ipairs (var.childNodes) do variable[x.nodeName] = x.textContent end
    if variable.name then
      variables[#variables+1] = variable
      short_codes[variable.name] = variable.shortCode
    end
  end
 
  -- all the service actions
  local actions = {}
  
  for act in xmlDoc.xpathIterator (scpd, "//actionList/action") do
    local action = {}
    for _,x in ipairs (act.childNodes) do action[x.nodeName] = x.textContent end
    if action.name then
      local argumentList = {}      
      for arg in xmlDoc.xpathIterator (act, "//argumentList/argument") do
        local a = {}
        for _,x in ipairs (arg.childNodes) do a[x.nodeName] = x.textContent end
        if a.name then
          argumentList[#argumentList+1] = a
        end
      end
      action.argumentList = argumentList
      actions[#actions+1] = action
    end
  end

  -- return arguments {actionName = {returnName = RelatedStateVariable, ...}, ... }
  local returns = {}

  for _,action in ipairs (actions) do
    local returnsList
    for _,a in ipairs (action.argumentList) do
      local related = a.relatedStateVariable
      if related and (a.direction or ''): match "out" then
        returnsList = returnsList or {}
        returnsList [a.name] = related
      end
    end
    returns[action.name] = returnsList
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
  local info
  local x, errmsg = xml_read (service_file)  -- not cached, since service files are decoded and saved in service_data
  if x then info = parse_service_xml (x) end
  return info, errmsg
end


-- read JSON file, if present.
-- openLuup doesn't use the json files, except to put into the static_data structure
-- which is passed on to any UI through the /data_request?id=user_data HTTP request.
local function read_json (json_file)
  local data, msg
  if json_file then 
    -- 2019.04.12 use raw_read so that file not cached (but still read from cache if there)
    local j = raw_read (json_file)
    if j then 
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
    env.luup = shallow_copy (luup)       -- add a COPY of the global luup table
    -- ... so that luup.device can be unique for each environment
    setfenv (a, env)                     -- Lua 5.1 specific function environment handling
    a, error_msg = pcall(a)              -- instantiate it
    if not a then env = nil end          -- erase if in error
  end 
  return env, error_msg
end

-- what it says...
local function compile_and_run (lua, name, print_function)
  print_function = print_function or function () end      -- print function for the compiled code to use
  local startup_env = shared_environment    -- shared with scenes
  local source = table.concat {"function ", name, " (print) ", lua, '\n', "end" }
  local ok, code, err 
  code, err = compile_lua (source, name, startup_env) -- load, compile, instantiate
  if code then 
    ok, err = scheduler.context_switch (nil, code[name], print_function)  -- no device context
    code[name] = nil      -- remove it from the name space
  end
  return ok, err
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
  local d = {}
  if non_blank (upnp_file) then
    local derr
    d, derr = read_device (upnp_file)   
    if not d then return d, derr end
  end
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
    local ierr
    i, ierr = read_impl (file) 
    if not i then return i, ierr end
  end

  -- load and compile the amalgamated code from <files>, <functions>, <actions>, and <startup> tags
  local code, error_msg
  if i.source_code then
    
  -----
  --
  -- 2018.03.17 from @explorer: ZeroBrane debugging support:
  -- use actual filenames to make it work with ZeroBrane
  -- limitations:
  -- works only when I_plugin.xml code is in <functions> or <files>, not both
  -- only single file is supported now
  -- TODO: consider not concatenating the source code in parse_impl_xml but compiling them separately.
  -- for code in XML files, keep XML but start XML lines with comments "-- " to match the line number.

--    local name = ("[%d] %s"): format (devNo, file or '?')
    local name = non_blank (i.files) or file or '?'                  -- 2018.03.17
  --
  -----

    -- 2018.04.06  wrap compile in context_switch() ...
    do              -- ...to get correct device numbering for sandboxed functions
    
      local ok
      ok, code, error_msg = scheduler.context_switch (devNo,
          compile_lua, i.source_code, name)  -- load, compile, instantiate    
      if error_msg and ABOUT.DEBUG then
        local f = io.open ("DUMP_" .. ((name: match "[^%.]+") or "XXX") .. ".lua", 'w')
        if f then
          f: write (i.source_code)
          f: close ()
        end
      end
    end
    
    if code then 
      code.luup.device = devNo        -- set local value for luup.device
      code.lul_device  = devNo        -- make lul_device in scope for the whole module
    end
    i.source_code = nil   -- free up for garbage collection
  end

  -- look for protocol AND handleChildren in BOTH device and implementation files 
  d.protocol = d.protocol or i.protocol or "crlf"               -- 2015.11.06
  d.handle_children = d.handle_children or i.handle_children    -- 2018.03.13
  
  -- set up code environment (for context switching)
  code = code or {}
  d.environment     = code  

  -- add category information  
  d.category_num    = tonumber (d.category_num) or cat_by_dev[device_type] or 0
  d.category_name   = cat_name_by_dev [device_type] or cat_name_by_num[d.category_num]

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


------

return {
  ABOUT = ABOUT,

  TEST = {},
  
  -- tables
  cat_by_dev          = cat_by_dev,         -- 2019.06.02
  service_data        = service_data,
  shared_environment  = shared_environment,
  static_data         = static_data,  

  -- methods
  assemble_device     = assemble_device_from_files,
  compile_lua         = compile_lua,
  compile_and_run     = compile_and_run,
  dir                 = dir,              -- walk the search path
  find_file           = find_file,
  new_environment     = new_environment,
  parse_service_xml   = parse_service_xml,
  parse_device_xml    = parse_device_xml,
  parse_impl_xml      = parse_impl_xml,
  raw_read            = raw_read,         -- so that other modules have same search path
  read_service        = read_service,
  read_device         = read_device,
  read_impl           = read_impl,
  read_json           = read_json,
  
  -- module
  xml = xml,
  
}

