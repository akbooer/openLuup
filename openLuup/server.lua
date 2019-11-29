local ABOUT = {
  NAME          = "openLuup.http",
  VERSION       = "2019.11.29",
  DESCRIPTION   = "HTTP/HTTPS GET/POST requests server",
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
-- openLuup SERVER - HTTP GET/POST request server
--

--[[

This HTTP server has gone through many evolutions since ~2013.  Although it might seem preferable to 
use a native system browser, this turns out to be hard to configure in all the possible systems
on which openLuup might be run.  This bespoke server code is adequate (just about.)

Many people have contributed to finding and fixing bugs over the years, in particular thanks go to:
   @amg0, @cybrmage, @d55m14, @explorer (many times), @jswim788, @reneboer, and @vosmont

--]] 

-- 2019.08.01   Significant refactoring
--              WGET split out into separate openluup.client 
--              Servlets now use WSAPI environment as their only input parameter
--              (and return the usual status, headers, iterator parameters)
-- 2019.11.29   add client socket to servlet.execute() parameter list
--   see: https://community.getvera.com/t/expose-http-client-sockets-to-luup-plugins-requests-lua-namespace/211263


local url       = require "socket.url"

local logs      = require "openLuup.logs"
local ioutil    = require "openLuup.io"                 -- for core server functions
local tables    = require "openLuup.servertables"       -- mimetypes and status_codes
local servlet   = require "openLuup.servlet"
local scheduler = require "openLuup.scheduler"          -- just for logging servlet jobs (with execution time)
local wsapi     = require "openLuup.wsapi"              -- to build WSAPI request environment

--local _log, _debug = logs.register (ABOUT)
local _log = logs.register (ABOUT)

-- CONFIGURATION DEFAULTS

local CHUNKED_LENGTH            = 16000     -- size of chunked transfers
local MAX_HEADER_LINES          = 100       -- limit lines to help mitigate DOS attack or other client errors

local PORT -- filled in during start()

-- TABLES

local status_codes = tables.status_codes

local iprequests = {}     -- log of incoming requests for console Server page

local myIP = tables.myIP

-- return HTML for error given numeric status code and optional extended error message
local function error_html(status, msg)
  local html = [[
<!DOCTYPE html>
<html>
  <head><title>%d - %s</title></head>
  <body><p>%s</p></body>
</html>
]]
  local title = status_codes[status] or "Error"
  local body = msg and tostring(msg) or "Unknown error"
  local content = html: format (status, title, body)
  return content, "text/html"
end


-- local functions

-- turn an iterator into a single content string
local function make_content (iterator)
  local content = {}
  for x in iterator do content[#content+1] = tostring(x) end
  return table.concat (content)
end

-- convert individual header names to CamelCaps, for consistency
local function CamelCaps (text)
  return text: gsub ("(%a)(%a*)", function (a,b) return a: upper() .. (b or ''): lower() end)
end


----------------------------------------------------
--
-- RESPOND to requests over HTTP
--

-- generate response from the three WSAPI-style parameters
local function http_response (status, headers, iterator)
  
  local Hdrs = {}           -- force CamelCaps-style header names
  for a,b in pairs (headers or {}) do Hdrs[CamelCaps(a)] = b end
  headers = Hdrs        
  
  -- 2018.07.06  catch any error in servlet response iterator
  
  local ok, response = pcall (make_content, iterator)    -- just for the moment, simply unwrap the iterator
  local content_type = headers["Content-Type"]
  local content_length = headers["Content-Length"]  
 
  if not ok then status = 500 end    -- 2018.06.07  Internal Server Error
  
  if status ~= 200 then 
    headers = {}
    response, content_type = error_html (status, response)
    content_length = #response
  end
  
  -- see https://mimesniff.spec.whatwg.org/
  if not content_type or content_type == '' then        -- limited mimetype sniffing
    if response then
      local start = response: sub (1,50) : lower ()
      if start: match "^%s*<!doctype html[%s>]" 
      or start: match "^%s*<html[%s>]"
        then content_type = "text/html"
      elseif
        start: match "^%s*<%?xml"
        then content_type = "text/xml"
      else 
        content_type = "text/plain"
      end
    end
  end
  
  headers["Content-Type"] = content_type
  headers["Content-Length"] = content_length
  headers["Server"] = "openLuup/" .. ABOUT.VERSION
  headers["Access-Control-Allow-Origin"] = "*"
  headers["Connection"] = "keep-alive" 
  
  local chunked
  if not content_length then
    headers["Transfer-Encoding"] = "Chunked"
    chunked = true
  end
  
  local crlf = "\r\n"
  local status_line = "HTTP/1.1 %d %s"
  local h = { status_line: format (status, status_codes[status] or "Unknown error") }
  for k, v in pairs(headers) do 
    if type (v) ~= "table" then v = {v} end   -- 2019.07.19  WSAPI sends multiple cookies as an array ???
    for i = 1,#v do h[#h+1] = table.concat { k, ": ", v[i] } end
  end
  h[#h+1] = crlf    -- add final blank line delimiting end of headers
  headers = table.concat (h, crlf) 
  
  return headers, response, chunked
end
  
-- simple send
local function send (sock, data, ...)
  local ok, err, n = sock: send (data, ...)
  if not ok then
    _log (("error '%s' sending %d bytes to %s"): format (err or "unknown", #data, tostring (sock)))
  end
  if n then
    _log (("...only %d bytes sent"): format (n))
  end
  return ok, err, 0   -- 2018.02.07  add 0 chunks!
end

-- specific encoding for chunked messages (trying to avoid long string problem)
local function send_chunked (sock, x)
  local N = #x
  local ok, err = true
  local i,j = 1, math.min(CHUNKED_LENGTH, N)
  local hex = "%x\r\n"
  local Nc = 0
  while i <= N and ok do
    Nc = Nc + 1
    send (sock, hex: format (j-i+1))
    ok, err = send (sock,x,i,j)
    send (sock, "\r\n")
    i,j = j + 1, math.min (j + CHUNKED_LENGTH, N)
  end
  send (sock, "0\r\n\r\n")
  return ok, err, Nc
end
 

-- convert headers to table with name/value pairs, and CamelCaps-style names
local function http_read_headers (sock)
  local n = 0
  local line, err
  local headers = {}
  -- TODO:   remove quotes, if present, from header values?
  local header_format = "(%a[%w%-]*)%s*%:%s*(.+)%s*"   -- essentially,  header:value pairs
  repeat
    n = n + 1
    line, err = sock:receive()
    local hdr, val = (line or ''): match (header_format)
    if val then headers[CamelCaps (hdr)] = val end
  until (not line) or (line == '') or n > MAX_HEADER_LINES 
  return headers, err
end

-- receive client request
local function receive (client)
  local wsapi_env                               -- the request object
  local headers, post_content
    
  local line, err = client:receive()        -- read the request line
  if err then  
    client: close (ABOUT.NAME .. ".receive " .. err)
    return nil, err
  end
  
  _log (line .. ' ' .. tostring(client))
  
  -- Request-Line = Method SP Request-URI SP HTTP-Version CRLF
  local method, request_URI, http_version = line: match "^(%u+)%s+(.-)%s+(HTTP/%d%.%d)%s*$"
  
  if not (method == "GET" or method == "POST") then
    err = "Unsupported HTTP request:" .. method
    return nil, err
  end
  
  headers, err = http_read_headers (client)
  if method == "POST" then
    local length = tonumber(headers["Content-Length"]) or 0
    post_content, err = client:receive(length)
  end

  local URL = url.parse (request_URI)
  URL.path = URL.path:gsub ("/port_3480", '')        -- 2016.09.16, thanks @explorer, and 2019.08.11 @DesT!
  wsapi_env = wsapi.make_env (URL.path, URL.query, headers, post_content, method, http_version)
  
  return wsapi_env
end
  

---------
--
-- this is called by a job for each new client socket connection...
-- may handle multiple requests sequentially through repeated calls to incoming() 
--
local function HTTPservlet (client)  
  -- incoming() is called by the io.server for each new client request
  return function --[[incoming--]] ()
    local wsapi_env, err = receive (client)         -- get the request (in the form of a WSAPI environment)       
    local request_start = scheduler.timenow()
    
    -- build response and send it
    local function respond (...)
      if client.closed then return end    -- 2018.04.12 don't bother to try and respond to closed socket!
      
      local headers, response, chunked = http_response (...)
      send (client, headers)
      
      local send_mode = chunked and send_chunked or send
      local ok, err, nc = send_mode (client, response)
      local _,_ = ok, err   -- TODO: change error handling in respond()
      local t = math.floor (1000*(scheduler.timenow() - request_start))
      local completed = "request completed (%d bytes, %d chunks, %d ms) %s"
      _log (completed:format (#response, nc, t, tostring(client)))
    end
    
    -- error return
    if err then 
      client: close (ABOUT.NAME.. ".incoming " .. err)
      return
    end
  
    -- run the appropriate servlet
    -- 2019.11.29  added client parameter
    local _, msg, jobNo = servlet.execute (wsapi_env, respond, client)  -- returns are as for scheduler.run_job ()

    -- log the outcome
    if jobNo and scheduler.job_list[jobNo] then
      local info = "request: HTTP %s from %s %s"  -- 2019.05.11
      scheduler.job_list[jobNo].type = 
        info: format (wsapi_env.REQUEST_METHOD, tostring(client.ip), tostring(client))
    else 
      _log (msg or "unknown error scheduling servlet")
    end
  end
end

----
--
-- start (), sets up the HTTP request handler
-- returns list of utility function(s)
-- 
local function start (config)
  PORT = tostring(config.Port or 3480)
  
  -- start(), create HTTP server
  return ioutil.server.new {
      port      = PORT,                                 -- incoming port
      name      = "HTTP",                               -- server name
      backlog   = config.Backlog or 2000,               -- queue length
      idletime  = config.CloseIdleSocketAfter or 90,    -- connect timeout
      servlet   = HTTPservlet,                          -- our own servlet
      connects  = iprequests,                           -- use our own table for info
    }

end

---------------------------------------------

--- return module variables and methods
return {
    ABOUT = ABOUT,
    
    TEST = {          -- for testing only
      CamelCaps       = CamelCaps,
      http_response   = http_response,
      make_content    = make_content,
    },
    
    -- constants
    myIP = myIP,
    
    -- variables
    iprequests    = iprequests,
    
    http_handler  = servlet.http_handler,   -- export for use by console server page
    file_handler  = servlet.file_handler,
    cgi_handler   = servlet.cgi_handler,
    
    --methods
    add_callback_handlers = servlet.add_callback_handlers,
    start = start,
  }

-----
