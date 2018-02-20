local ABOUT = {
  NAME          = "openLuup.servlet",
  VERSION       = "2018.02.19",
  DESCRIPTION   = "HTTP servlet API - interfaces to data_request, CGI and file services",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-2018 AK Booer

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
  - data_request?id=...       Luup-style system requests (both system lu_xxx, and user-defined lr_xxx)
  - Lua WSAPI CGIs            enumerated in the cgi_prefix section of the servertables.lua file
  - file requests             anything not recognised as one of the above, and on defined file paths

The add_callback_handlers () function registers a list of new request callback handler.

The execute() function essentially converts a given luup-style callback handler, which simply returns response and possibly mime-type, into both a function with WSAPI-style returns of status, headers, and iterator function, and also a task which may be executed by the scheduler.  These are essentially, servlets.  Tasks which service data_requests have <run> and <job> phases, but CGIs and file requests are immediately executed in the <run> phase only, so do not appear as scheduler jobs (thus improving response times.)

The WSAPI-style functions are used by the tasks, but also called directly by the wget() client call which processes their reponses.  If a respond() function is given to the execute() call, then the servelet is scheduled.

--]]

-- 2018.02.07   functionality extracted from openluup.server module and refactored
--              CGIs and file requests now execute in the <run> phase, rather than <job> (so faster)
-- 2018.02.15   For file requests, also look in ./www/ (a better place for web pages)
-- 2018.02.19   apply directory path aliases from server tables (rather than hard-coded)

local logs      = require "openLuup.logs"
local devices   = require "openLuup.devices"            -- to access 'dataversion'
local scheduler = require "openLuup.scheduler"
local json      = require "openLuup.json"               -- for unit testing only
local wsapi     = require "openLuup.wsapi"              -- WSAPI connector for CGI processing
local tables    = require "openLuup.servertables"       -- mimetypes and status_codes
local vfs       = require "openLuup.virtualfilesystem"  -- on possible file path

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control

-- TABLES

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
    http_handler[name] = {callback = proc, devNo = devNo}
  end
end

local function data_request (request)
  local ok, mtype
  local status = 501
  local parameters = request.parameters   
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
    ok, response, mtype = scheduler.context_switch (handler.devNo, handler.callback, request_name, parameters, format)
    if ok then
      status = 200
      response = tostring (response)      -- force string type
      content_type = mtype or content_type
    else
      status = 500
      response = "error in callback [" .. id .. "] : ".. (response or 'nil')
    end
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

local function data_request_task (request, respond)
  
  -- special scheduling parameters used by the job 
  local Timeout       -- (s)  respond after this time even if no data changes 
  local MinimumDelay  -- (ms) initial delay before responding
  local DataVersion   --      previous data version value
  
  local function run ()
    -- /data_request?DataVersion=...&MinimumDelay=...&Timeout=... parameters have special significance
    local p = request.parameters
    Timeout      = tonumber (p.Timeout)                     -- seconds
    MinimumDelay = tonumber (p.MinimumDelay or 0) * 1e-3    -- milliseconds
    DataVersion  = tonumber (p.DataVersion)                 -- timestamp
  end
  
  local function job ()
    
    -- initial delay (possibly) 
    if MinimumDelay and MinimumDelay > 0 then 
      local delay = MinimumDelay
      MinimumDelay = nil                                        -- don't do it again!
      return scheduler.state.WaitingToStart, delay
    end
    
    -- DataVersion update or timeout (possibly)
    if DataVersion 
      and not (devices.dataversion.value > DataVersion)         -- no updates yet
      and scheduler.timenow() - request.request_start < (Timeout or 0) then   -- and not timed out
        return scheduler.state.WaitingToStart, 0.5              -- wait a bit and try again
    end
    
    -- finally (perhaps) execute the request
    respond (request, data_request (request))
    
    return scheduler.state.Done, 0  
  end
  
  return {run = run, job = job}   -- return the task structure
end

----------------------------------------------------
--
-- REQUEST HANDLER: file requests
--

local function http_file (request)
  local path = request.URL.path or ''
  if request.path_list.is_directory then 
    path = path .. "index.html"                     -- look for index.html in given directory
  end
  
  path = path: gsub ("%.%.", '')                    -- ban attempt to move up directory tree
  path = path: gsub ("^/", '')                      -- remove filesystem root from path
  path = path: gsub ("luvd/", '')                   -- no idea how this is handled in Luup, just remove it!
  
--  path = path: gsub ("cmh/skins/default/img/devices/device_states/", "icons/")  -- redirect UI7 icon requests
--  path = path: gsub ("cmh/skins/default/icons/", "icons/")                      -- redirect UI5 icon requests
--  path = path: gsub ("cmh/skins/default/img/icons/", "icons/")                  -- 2017.11.14 
  
  -- 2018.02.19  apply directory path aliases from server tables
  for old,new in pairs (tables.dir_alias) do
    path = path: gsub (old, new)
  end
  
  local content_type = mime_file_type (path)
  local content_length
  local response
  local status = 500
  
  local f = io.open(path,'rb')                      -- 2016.03.05  'b' for Windows, thanks @vosmont
    or io.open ("../cmh-lu/" .. path, 'rb')         -- 2016.02.24  also look in /etc/cmh-lu/
    or io.open ("files/" .. path, 'rb')             -- 2016.06.09  also look in files/
    or io.open ("www/" .. path, 'rb')               -- 2018.02.15  also look in www/
    or io.open ("openLuup/" .. path, 'rb')          -- 2016.05.25  also look in openLuup/ (for plugins page)
    or vfs.open (path, 'rb')                        -- 2016.06.01  also look in virtualfilesystem
  
  if f then 
    response = (f: read "*a") or ''                   -- should perhaps chunk long files
    f: close ()
    status = 200
    
    -- @explorer:  2016.04.14, Workaround for SONOS not liking chunked MP3 and some headers.       
    if file_type (path) == "mp3" then       -- 2016.04.28  @akbooer, change this to apply to ALL .mp3 files
      content_length = #response            -- specifying Content-Length disables chunked sending
    end
  
  else
    status = 404
    response = "file not found:" .. path  
  end
 
  if status ~= 200 then 
    _log (response) 
  end
  
  local response_headers = {
      ["Content-Length"] = content_length,
      ["Content-Type"]   = content_type,
    }
  
  return status, response_headers, make_iterator(response)
end

-- return a task for the scheduler to handle file requests 
local function file_task (request, respond)
  return {run = function () respond (request, http_file(request)) end}   -- immediate run action (no job needed)
end

-- return a task for the scheduler to handle CGI requests 
local function cgi_task (request, respond)
  return {run = function () respond (request, wsapi.cgi(request)) end}   -- immediate run action (no job needed)
end


-- 
-- define the appropriate handlers and tasks depending on request type
--
local exec_selector = {data_request = data_request}
local task_selector = {data_request = data_request_task}

for _,prefix in pairs (tables.cgi_prefix) do
  exec_selector[prefix] = wsapi.cgi    -- add those defined in the server tables
  task_selector[prefix] = cgi_task
end

-- execute() calls the handler in one of two ways, depending on the presence of a respond function argument.
-- no respond: execute immediately and return the handler's WSAPI-style three parameters
--    respond: run as a scheduled task and call respond with the three return parameters for HTTP response
--    the function return parameters in this case those of an action call: err, msg, jobNo.
local function execute (request, respond)
  local request_root = request.path_list[1]
  if respond then
    local task = (task_selector [request_root] or file_task) (request, respond)
    local err, msg, jobNo = scheduler.run_job (task, {}, nil)  -- nil device number
    if jobNo and scheduler.job_list[jobNo] then
      local info = "job#%d :HTTP request from %s: %s"
      scheduler.job_list[jobNo].type = info: format (jobNo, tostring(request.ip), tostring(request.sock))
    end
    return err, msg, jobNo
  else
    local handler = exec_selector [request_root] or http_file
    return handler (request)    -- no HTTP response needed by server
  end
end

--- return module variables and methods

return {
    ABOUT = ABOUT,
    
    TEST = {          -- for testing only
      data_request    = data_request,
      http_file       = http_file,
      make_iterator   = make_iterator,
      wsapi_cgi       = wsapi.cgi,
    },
    
    --methods
    
    execute = execute,
    add_callback_handlers = add_callback_handlers,
  }

-----
