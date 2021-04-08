local ABOUT = {
  NAME          = "openLuup.servlet",
  VERSION       = "2021.04.08",
  DESCRIPTION   = "HTTP servlet API - interfaces to data_request, CGI and file services",
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

--[[

This module is the interface between the HTTP port 3480 server and the handlers which implement the requests.

Requests are of three basic types:
  - data_request?id=...             Luup-style system requests (both system lu_xxx, and user-defined lr_xxx)
  - Lua WSAPI CGIs                  enumerated in the cgi_prefix section of the servertables.lua file
  - openLuup Shelly-like requests   relay / scene / status /...
  - file requests                   anything not recognised as one of the above, and on defined file paths,
                                    or as redirected from servertables dir_alias table.

The add_callback_handlers () function registers a list of new request callback handlers.

The execute() function essentially converts a given luup-style callback handler, which simply returns response and possibly mime-type, into both a function with WSAPI-style returns of status, headers, and iterator function, and also a task which may be executed by the scheduler.  These are essentially, servlets.  

If a respond() function is given to the execute() call, then the servlet is scheduled.  CGI and file
requests are currently implemented as <run> tags, so do not appear as scheduler jobs (thus improving response times.)
The data_request one is a more complex task with, run as an asynchronous job, to handle the 
MinimumDelay, Timeout, and DataVersion parameters which all affect timing of the response.

The WSAPI-style functions are used by the servlet tasks, but also called directly by the wget() client call which processes their reponses directly.

--]]

-- 2018.02.07   functionality extracted from openluup.server module and refactored
--              CGIs and file requests now execute in the <run> phase, rather than <job> (so faster)
-- 2018.02.15   For file requests, also look in ./www/ (a better place for web pages)
-- 2018.02.19   apply directory path aliases from server tables (rather than hard-coded)
-- 2018.03.22   add invocation count to data_request calls, export http_handler, use logs.register()
-- 2018.07.15   use raw_read() in file handler, for consistency in path search order

-- 2019.04.03   ignore MinimumDelay parameter from AltUI requests (to improve responsiveness)
-- 2019.05.11   add GET or POST method to job info in execute()
-- 2019.05.14   add Cache-Control header, don't chunk small file responses
-- 2019.06.11   move cache_control definition to server_tables module
-- 2019.07.28   call servlets with pre-built WSAPI environment
-- 2019.07.29   use WSAPI request library to parse GET and POST parameters for /data_request...
-- 2019.08.12   /data_request?id=xxx&foo=a&foo=b, collapses to simply &foo=b (thanks, indirectly, @DesT)
-- 2019.11.29   add client socket to servlet.execute() parameter list and data_request handlers
--   see: https://community.getvera.com/t/expose-http-client-sockets-to-luup-plugins-requests-lua-namespace/211263

-- 2020.01.29   add "dontrespond" mimetype option for external data_requests
--   see: https://community.getvera.com/t/expose-http-client-sockets-to-luup-plugins-requests-lua-namespace/211263/7

-- 2021.04.02   add fourth request type: Shelly-like relay / scene / status / ... (from old shelly_cgi)
-- 2021.04.08   add MQTT subscriber for Shelly-like commands, per the above


local logs      = require "openLuup.logs"
local devices   = require "openLuup.devices"            -- to access 'dataversion'
local scheduler = require "openLuup.scheduler"
local json      = require "openLuup.json"               -- for unit testing only
local wsapi     = require "openLuup.wsapi"              -- WSAPI connector for CGI processing
local tables    = require "openLuup.servertables"       -- mimetypes and status_codes, and serviceIds
local loader    = require "openLuup.loader"             -- for raw_read()
local mqtt      = require "openLuup.mqtt"

--local _log, _debug = logs.register (ABOUT)
local _log, _debug = logs.register (ABOUT)

-- TABLES

local SID = tables.SID

local mimetype = tables.mimetypes
  
local function file_type (filename)
  return filename: match "%.([^%.]+)$"     -- extract extension from filename
end

-- GLOBAL functions

local function mime_file_type (filename)
  return mimetype[file_type (filename) or '']                        -- returns nil if unknown
end

-- turn a content string into a one-shot iterator, returning same (for WSAPI-style handler returns)
local function make_iterator (content)      -- one-shot iterator (no need for coroutines!)
  return function ()
    local x = content
    content = nil
    return x
  end
end


----------------------------------------------------
--
-- REQUEST HANDLER: /data_request?id=... queries only (could be GET or POST)
--

-- add callbacks to the HTTP handler dispatch list  
-- and remember the device context in which it's called
-- fixed callback context - thanks @reneboer
-- see: http://forum.micasaverde.com/index.php/topic,36207.msg269018.html#msg269018

local http_handler = {    -- the data_request?id=... handler dispatch list
  TEST = {
      callback = function (...) return json.encode {...}, mimetype.json end    -- just for testing
    },
  }

local function add_callback_handlers (handlers, devNo)
  for name, proc in pairs (handlers) do     
    http_handler[name] = {callback = proc, devNo = devNo, count = 0}
  end
end

local function data_request (wsapi_env, req, client)
  _debug ((client or {}).ip or "internal") 
  -- 2019.07.29 use WSAPI request library to parse GET and POST parameters...
  -- the library's built-in req.params mechanism is built on demand for an individual request parameter, 
  -- so not used here... this complete list is built from the GET and POST parameters individually
  local parameters = {}
  -- 2019.08.12 collapse table of multiple values to single (final) value
  -- 2019.10.12 only return non-zero length strings, thanks @a-lurker
  -- see: https://community.getvera.com/t/openluup-and-url-parameters/210507
  local function last_value (x) 
    local v = type(x) == "table" and x[#x] or x 
    if #v > 0 then return v end
  end
  req = req or wsapi.request.new (wsapi_env)            -- request may have been prebuilt by data_request_task
  for n,v in pairs (req.POST) do parameters[n] = last_value (v) end
  for n,v in pairs (req.GET)  do parameters[n] = last_value (v) end  -- GET parameter overrides POST, if both defined
  -----
  
  local ok, mtype
  local status = 501
  local id = parameters.id or '?'
  local content_type
  local response = "No handler for data_request?id=" .. id     -- 2016.05.17   log "No handler" responses
  
  local handler = http_handler[id]
  if handler and handler.callback then 
    local format = parameters.output_format
    parameters.id = nil               -- don't pass on request id to user...
    parameters.output_format = nil    -- ...or output format in parameters
    -- fixed callback request name - thanks @reneboer
    -- see: http://forum.micasaverde.com/index.php/topic,36207.msg269018.html#msg269018
    local request_name = id: gsub ("^l[ru]_", '')     -- remove leading "lr_" or "lu_"
    ok, response, mtype = scheduler.context_switch (handler.devNo, handler.callback, request_name, parameters, format,
                                client)     -- 2019.11.29
    if ok then
      status = 200
      response = tostring (response)      -- force string type
      content_type = mtype or content_type
    else
      status = 500
      response = "error in callback [" .. id .. "] : ".. (response or 'nil')
    end
    handler.count  = (handler.count or 0) + 1            -- 2018.03.22
    handler.status = status
  end
  
  if status ~= 200 then
    _log (response or 'not a data request')
  end
  
  -- WSAPI-style return parameters: status, headers, iterator
  local response_headers = {
--      ["Content-Length"] = #response,     -- with no length, allow chunked transfers
      ["Content-Type"]   = content_type,
    }
  return status, response_headers, make_iterator(response)
end

-- handler_task returns a task to process the request with possibly run and job entries

local function data_request_task (wsapi_env, respond, client)
  local request_start = scheduler.timenow ()
  local req = wsapi.request.new (wsapi_env)   -- use WSAPI library to parse GET and POST parameters
  local p = req.params
  
  -- /data_request?DataVersion=...&MinimumDelay=...&Timeout=...
  -- parameters have special significance for scheduling the job 
  local Timeout      = tonumber (p.Timeout)                   -- (s)  respond after this time even if no data changes 
  local DataVersion  = tonumber (p.DataVersion)               --      previous data version value
  local MinimumDelay = tonumber (p.MinimumDelay or 0) * 1e-3  -- (ms) initial delay before responding
  
  -- 2019.04.03  adjust MinimumDelay option from AltUI, it is a band-aid for Vera, openLuup queues responses anyway
  if MinimumDelay and p._ then   -- assume this request is from AltUI
    MinimumDelay = 0.1    -- 100ms
  end
    
  local function job ()
    
    -- initial delay (possibly) 
    if MinimumDelay and MinimumDelay > 0 then 
      local delay = MinimumDelay
      MinimumDelay = nil                                              -- don't do it again!
      return scheduler.state.WaitingToStart, delay
    end
    
    -- DataVersion update or timeout (possibly)
    if DataVersion 
      and not (devices.dataversion.value > DataVersion)               -- no updates yet
      and scheduler.timenow() - request_start < (Timeout or 0) then   -- and not timed out
        return scheduler.state.WaitingToStart, 0.5                    -- wait a bit and try again
    end
    
    -- finally (perhaps) execute the request
    local status, headers, iterator = data_request (wsapi_env, req, client)
      
    if headers["Content-Type"] ~= "dontrespond" then respond (status, headers, iterator) end  -- 2020.01.29
    
    return scheduler.state.Done, 0  
  end
  
  return {job = job}   -- return the task structure
end

----------------------------------------------------
--
-- REQUEST HANDLER: file requests
--
local file_handler = {}     -- table of requested files

local function file_request (wsapi_env)
  local cache_control = tables.cache_control                 -- 2019.05.14  max-age indexed by filetype
  
  local path = wsapi_env.SCRIPT_NAME
  if path: match "/$" then path = path .. "index.html" end   -- look for index.html in given directory
  
  path = path: gsub ("%.%.", '')                    -- ban attempt to move up directory tree
  path = path: gsub ("^/", '')                      -- remove filesystem root from path
  path = path: gsub ("luvd/", '')                   -- no idea how this is handled in Luup, just remove it!
  
  -- 2018.02.19  apply directory path aliases from server tables
  for old,new in pairs (tables.dir_alias) do
    path = path: gsub (old, new)
  end
  
  local content_type = mime_file_type (path)
  local status = 500  
  local response_headers = {}
  
  -- 2018.07.15  use raw_read() for consistency in path search order
  -- 2019.04.12  remove vfs.read() here since raw_read now does an initial search of the cache
  local response = loader.raw_read (path)
  
  if response then 
    status = 200
    local ftype = file_type (path)
    local max_age = cache_control[ftype] or 0
    response_headers ["Cache-Control"] = "max-age=" .. max_age    -- 2019.05.14
    response_headers ["Content-Type"]  = content_type
    
    -- @explorer:  2016.04.14, Workaround for SONOS not liking chunked MP3 and some headers.       
    if ftype == "mp3"        -- 2016.04.28  @akbooer, change this to apply to ALL .mp3 files, fix 2019.05.14
    or #response < 16000 
    then
      response_headers ["Content-Length"] = #response    
    end
  
  else
    status = 404
    response = "file not found:" .. path  
    response_headers ["Content-Type"]   = mimetype ["txt"]
    response_headers ["Content-Length"] = #response    
  end
 
  if status ~= 200 then 
    _log (response) 
  end
  
  local stats = file_handler[path] or {count = 0}   -- log statistics for console page
  stats.size = #response
  stats.status = status
  stats.count = stats.count + 1
  file_handler[path] = stats
  
  return status, response_headers, make_iterator(response)
end

----------------------------------------------------
--
-- REQUEST HANDLER: openLuup Shelly-like requests
--

local requests = setmetatable ({}, {__index = 
    function (x, a)
      local req = require "openLuup.requests"        -- can't be done at initialisation (circular reference)
      rawset (x, a, req[a])
      return x[a]
    end
  })

-- perform generic luup action
local function call_action (info, ...)
  -- returns: error (number), error_msg (string), job (number), arguments (table)
  info.status, info.message, info.job = luup.call_action(...)
end

-- easy HTTP request to run a scene
local function scene (info) 
  if luup.scenes[info.id] then
    call_action(info, SID.hag, "RunScene", {SceneNum = info.id}, 0)
  end
  return info
end

-- easy HTTP request to switch a switch
local turn = {
    on      = function (info) call_action (info, SID.switch, "SetTarget", {newTargetValue = '1'}, info.id) end,
    off     = function (info) call_action (info, SID.switch, "SetTarget", {newTargetValue = '0'}, info.id) end,
    toggle  = function (info) call_action (info, SID.hadevice, "ToggleState", {}, info.id) end,
  }
  
local function relay (info)
  local op = info.parameters.turn
  local fct = turn[op]
  local id = info.id 
  local d = luup.devices[id]
  if fct and d then fct(info) end
  return info
end

local function status (info)
  local result = requests.status (nil, {DeviceNum = info.id})   -- already JSON encoded
  return (result == "Bad Device") and info or result            -- info has default error message
end

local function unknown (info)
  info.status = -1
  info.message = "invalid action request"
  return info
end


local dispatch = {
    relay     = relay,
    scene     = scene,
    status    = status,
  }
  
local function exec_shelly_like_command (command, parameters)
  local action, path = command: match "/?(%w+)/?(.*)"
  local id = tonumber(path: match "^%d+")
  
  local ol = luup.openLuup
  local finders = { 
      relay = ol.find_device,
      scene = ol.find_scene,
    }
  local finder = finders[action]
    
  if not id and finder then         -- try device/scene by name
    local name = wsapi.util.url_decode (path: match "^[^/%?]+")
    id = finder {name = name}
  end
  
  local info = {command = command, id = id, parameters = parameters}
  local fct = dispatch[action] or unknown
  
  unknown(info)   -- set default error message (to be over-written)
  
  local reply, err = fct(info)       -- input and output parameters also returned (unencoded) in info
  if type(reply) == "table" then
    reply, err = json.encode(reply)
  end
  return reply, err
end

-- CGI entry point

local function ol_request (wsapi_env)
  
  local req = wsapi.request.new(wsapi_env)
  local res = wsapi.response.new ()
  res:content_type "text/plain" 
  
  local command = req.script_name                         -- eg. /relay/42 or scene/32
  
  local reply, err = exec_shelly_like_command (command, req.GET)
  res: write (reply or err)
  res:content_type "application/json"
  
  return res:finish()
end

----------------------------------------------------
--
-- REQUEST HANDLER: CGI requests
--

-- only here to log the usage statistics
local cgi_handler = {}

local function cgi_request (wsapi_env)
  local path = wsapi_env.SCRIPT_NAME
  local status, headers, iterator = wsapi.cgi (wsapi_env)
  
  local stats = cgi_handler[path] or {count = 0}   -- log statistics for console page
  stats.status = status
  stats.count = stats.count + 1
  cgi_handler[path] = stats

  return status, headers, iterator
end


-- return a task for the scheduler to handle file requests 
local function file_task (wsapi_env, respond)
  return {run = function () respond (file_request(wsapi_env)) end} -- immediate run action (no job)
end

-- return a task for the scheduler to handle file requests 
local function ol_task (wsapi_env, respond)
  return {run = function () respond (ol_request(wsapi_env)) end} -- immediate run action (no job)
end

-- return a task for the scheduler to handle CGI requests 
local function cgi_task (wsapi_env, respond)
  return {run = function () respond (cgi_request(wsapi_env)) end} -- immediate run action (no job)
end


-- 
-- define the appropriate handlers and tasks depending on request type
--
local exec_selector = {
    data_request = data_request,
    relay = ol_request,
    scene = ol_request,
    status = ol_request,
  }

local task_selector = {
    data_request = data_request_task,
    relay = ol_task,
    scene = ol_task,
    status = ol_task,
  }

for _,prefix in pairs (tables.cgi_prefix) do
  exec_selector[prefix] = wsapi.cgi    -- add those defined in the server tables
  task_selector[prefix] = cgi_task
end

-- execute() calls the handler in one of two ways, depending on the presence of a respond function argument.
-- no respond: execute immediately and return the handler's WSAPI-style three parameters
--    respond: run as a scheduled task and call respond with the three return parameters for HTTP response
--    the function return parameters in this case those of an action call: err, msg, jobNo.
-- 2019.11.29  added client parameter
local function execute (wsapi_env, respond, client)
  local request_root = wsapi_env.SCRIPT_NAME: match "[^/]+"     -- get the first path element in the request
  if respond then
    local task = (task_selector [request_root] or file_task) (wsapi_env, respond, client)
    return scheduler.run_job (task, {}, nil)   -- nil device number,  returns err, msg, jobNo
  else
    local handler = exec_selector [request_root] or file_request
    return handler (wsapi_env)    -- no HTTP response needed by server
  end
end


------------------------
--
-- MQTT subscriber for Shelly-like commands
--
-- relay / scene / status
--
local function mqtt_command (topic, json_message)
  local parameters, err
  _log (table.concat {"MQTT COMMAND: ", topic," = ", json_message})
  local n = tonumber (json_message)
  if n then 
    parameters = {turn = n}
  else
    if #json_message == 0 then json_message = '{}' end
    parameters, err = json.decode (json_message)
  end
  if parameters then
    exec_shelly_like_command (topic, parameters)
  else
    _log ("ERROR: " .. (err or '?'))
  end
end

do -- MQTT commands
  mqtt.register_handler (mqtt_command, "relay/#")
  mqtt.register_handler (mqtt_command, "scene/#")
  mqtt.register_handler (mqtt_command, "status/#")
  mqtt.register_handler (mqtt_command, "status")
end

--- return module variables and methods

return {
    ABOUT = ABOUT,
    
    TEST = {          -- for testing only
      data_request    = data_request,
      ol_request      = ol_request,
      http_file       = file_request,
      make_iterator   = make_iterator,
      wsapi_cgi       = wsapi.cgi,
    },
    
    -- variables
    
    http_handler  = http_handler,    -- for console info, via server module
    file_handler  = file_handler,
    cgi_handler   = cgi_handler,
    
    --methods
    
    execute = execute,
    add_callback_handlers = add_callback_handlers,
    
  }

-----
