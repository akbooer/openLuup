local ABOUT = {
  NAME          = "openLuup.server",
  VERSION       = "2018.03.22",
  DESCRIPTION   = "HTTP/HTTPS GET/POST requests server core and luup.inet.wget client",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
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

--
-- openLuup SERVER - HTTP GET request server and client
--

-- 2016.02.20   add "index.html" for file requests ending with '/
-- 2016.02.24   also look for files in /cmh-lu/
-- 2016.02.25   make myIP global (used for rewriting icon urls)
-- 2016.02.29   redirect file requests for UI5 and UI7 icons
-- 2016.03.05   io.open with 'rb' for Windows, thanks @vosmont
-- 2016.03.16   wget now checks port number when intercepting local traffic, thanks @reneboer
-- 2016.03.20   added svg to mime types and https support to wget, thanks @cybrmage
-- 2016.04.14   @explorer: Added workaround for Sonos not liking chunked transfers of MP3 files. 
-- 2016.04.14   @explorer: Parametrized HTTP response functions - better control over transfer mode and headers.
-- 2016.04.15   @explorer: Added a few common MIME types such as css, mp3 (@akbooer moved to external file)
-- 2016.04.28   @akbooer, change Sonos file fix to apply to ALL .mp3 files
-- 2016.05.10   handle upnp/control/hag requests (AltUI redirects from port 49451) through WSAPI
-- 2016.05.17   log "No handler" responses
-- 2016.05.25   also look for files in openLuup/ (for plugins page)
-- 2016.06.01   also look for files in virtualfilesystem
-- 2016.06.09   also look in files/ directory
-- 2016.07.06   add 'method' to WSAPI server call
-- 2016.07.12   start refactoring: request dispatcher and POST queries
-- 2016.07.14   request object parameter and WSAPI-style returns for all handlers
-- 2016.07.17   HTML error pages
-- 2016.07.18   add 'actual_status' return to wget (undocumented Vera feature?)
-- 2016.08.03   remove optional "lu_" prefix from system callback request names
-- 2016.09.16   remove /port_3480 redirects from parsed URI - thanks @explorer
-- 2016.09.17   increase BACKLOG parameter to solve stalled updates - thanks @explorer (again!) 
--              see: http://forum.micasaverde.com/index.php/topic,39129.msg293629.html#msg293629
-- 2016.10.17   use CGI prefixes from external servertables module
-- 2016.11.02   change job.notes to job.type for new connections and requests
-- 2016.11.07   add requester IP to new connection log message
-- 2016.11.18   test for nil URL.path 

-- 2017.02.06   allow request parameters from URL and POST request body (rather than one or other)
-- 2017.02.08   thanks to @amg0 for finding error in POST parameter handling
-- 2017.02.21   use find, not match, with plain string option for POST parameter encoding test
-- 2017.03.03   fix embedded spaces in POST url-encoded parameters (thanks @jswim788)
-- 2017.03.15   add server table structure to startup call
-- 2017.05.05   add error logging to wget (thanks @a-lurker), change socket close error message
-- 2017.05.25   fix wget error logging format
-- 2017.06.14   use Authorization header for wget basic authorization, rather than in the URL (now deprecated)
-- 2017.11.14   add extra icon path alias

-- 2018.01.11   remove edit of /port_3480 in URL.path as per 2016.09.16 above, in advance of Vera port updates
-- 2018.02.07   some functionality exported to new openluup.servlet module (cleaner interface)
-- 2018.02.26   reinstate /port_3480 removal for local host requests only (allows Vera-style URLs to work here)
-- 2018.03.09   move myIP code to servertables (more easily shared with other servers, eg. SMTP)
-- 2018.03.15   fix relative URL handling in request object
-- 2018.03.22   export http_handler from servlet for use by console server page


local socket    = require "socket"
local url       = require "socket.url"
local http      = require "socket.http"
local https     = require "ssl.https"
local ltn12     = require "ltn12"                       -- for wget handling
local mime      = require "mime"                        -- for basic authorization in wget

local logs      = require "openLuup.logs"
local scheduler = require "openLuup.scheduler"
local tables    = require "openLuup.servertables"       -- mimetypes and status_codes
local servlet   = require "openLuup.servlet"

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

-- CONFIGURATION DEFAULTS

local BACKLOG                   = 2000      -- used in socket.bind() for queue length
local CHUNKED_LENGTH            = 16000     -- size of chunked transfers
local CLOSE_IDLE_SOCKET_AFTER   = 90        -- number of seconds idle after which to close socket
local MAX_HEADER_LINES          = 100       -- limit lines to help mitigate DOS attack or other client errors
local URL_AUTHORIZATION         = true      -- use URL rather than Authorization header for wget basic authorization

local PORT -- filled in during start()

-- TABLES

local status_codes = tables.status_codes

local iprequests = {}     -- log of incoming requests {ip = ..., mac = ..., time = ...} indexed by ip

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

-- convert HTTP GET or POST content into query parameters
local function parse_parameters (query)
  local p = {}
  for n,v in query: gmatch "([%w_]+)=([^&]*)" do          -- parameters separated by unescaped "&"
    if v ~= '' then p[n] = url.unescape(v) end            -- now can unescape parameter values
  end
  return p
end

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
-- return a request object containing all the information a handler needs
-- only required parameter is request_URI, others have sensible defaults.
 

local self_reference = {
  ["localhost"] = true,
  ["127.0.0.1"] = true, 
  ["0.0.0.0"] = true, 
  [myIP] = true,
}

local function request_object (request_URI, headers, post_content, method, http_version, sock, ip)
  
  local request_start = socket.gettime()
  
  -- we seem to get requests without the usual prefix, eg. just "/data_request..."
  -- think this is from persistent connections from the browser (AltUI in particular)
  -- without the scheme, ip, and port, then the request would be mis-handled
  
  if not (request_URI: match "^%w+://") then 
    if request_URI: match "^/" then    -- 2018.03.15  it's a relative URL, must be served from here
      request_URI = table.concat {"http://", myIP, ':', PORT,  request_URI }    -- 2018.02.26
    else
      request_URI = "http://" .. request_URI    -- assume it's an external HTTP request
    end
  end
 
  local URL = url.parse (request_URI)               -- parse URL

  -- construct parameters from query string and/or POST content
  local parameters = {}
  method = method or "GET"
  if URL.query then
    parameters = parse_parameters (URL.query)   -- extract useful parameters from query string
  end
  
  if method == "POST" 
  and (headers["Content-Type"] or ''): find ("application/x-www-form-urlencoded",1,true) then -- 2017.02.21
    local p2 = parse_parameters (post_content:gsub('+', ' '))   -- 2017.03.03 fix embedded spaces
    for a,b in pairs (p2) do        -- 2017.02.06  combine URL and POST parameters
      parameters[a] = b
    end
  end

  local internal  = self_reference [URL.host] and URL.port == PORT    -- 2016-03-16 check for port #, thanks @reneboer
  if internal and URL.path then                                       -- 2016.11.18
    URL.path = URL.path:gsub ("/port_3480", '')                       -- 2016.09.16, thanks @explorer 
  end
  local path_list = url.parse_path (URL.path) or {}   -- split out individual parts of the path

  return {
      URL           = URL,
      headers       = headers or {},
      post_content  = post_content or '',
      method        = method,
      http_version  = http_version or "HTTP/1.1",
      path_list     = path_list,
      internal      = internal,
      parameters    = parameters or {},
      request_start = request_start,
      sock          = sock,
      ip            = ip,
    }
end


----------------------------------------------------
--
-- HTTP CLIENT request (for luup.inet.wget)
--
-- issue a GET request, handling local ones to port 3480 without going over HTTP
local function wget (request_URI, Timeout, Username, Password) 
  local result, status
  local request = request_object (request_URI)        -- build the request
  
  if request.internal then
    
    -- INTERNAL request
    local headers, iterator
    status, headers, iterator = servlet.execute (request) -- make the request call
    result = make_content (iterator)                  -- build the return string
  
  else
    
    -- EXTERNAL request OR not port 3480 
    local scheme = http
    local URL = request.URL
    URL.scheme = URL.scheme or "http"                 -- assumed undefined is http request
    if URL.scheme == "https" then scheme = https end  -- 2016.03.20
    if URL_AUTHORIZATION then                         -- 2017.06.15
      URL.user = Username                             -- add authorization credentials to URL
      URL.password = Password
    end
    URL = url.build (URL)                             -- reconstruct request for external use
    scheme.TIMEOUT = Timeout or 5
    
    if Username and not URL_AUTHORIZATION then        -- 2017.06.14 build Authorization header
      local flag
      local auth = table.concat {Username, ':', Password or ''}
      local headers = {
          Authorization = "Basic " .. mime.b64 (auth),
        }
      result = {}
      flag, status = scheme.request {
          url=URL, 
          sink=ltn12.sink.table(result),
          headers = headers,
        }
      result = table.concat (result)
    else
      result, status = scheme.request (URL)
    end
--  
  end
  
  local wget_status = status                          -- wget has a strange return code
  if status == 200 then
    wget_status = 0 
  else                                                -- 2017.05.05 add error logging
    local error_message = "WGET status: %s, request: %s"  -- 2017.05.25 fix wget error logging format
    _log (error_message: format (status, request_URI))
  end
  return wget_status, result or '', status            -- note reversal of parameter order cf. http.request()
end


----------------------------------------------------
--
-- RESPOND to requests over HTTP
--

-- generate response
local function http_response (status, headers, iterator)
  
  local Hdrs = {}           -- force CamelCaps-style header names
  for a,b in pairs (headers or {}) do Hdrs[CamelCaps(a)] = b end
  headers = Hdrs        
  
  local response = make_content (iterator)    -- just for the moment, simply unwrap the iterator
  local content_type = headers["Content-Type"]
  local content_length = headers["Content-Length"]  
 
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
  headers["Access-Control-Allow-Origin"] = "*"   -- @d55m14 -- see: http://forum.micasaverde.com/index.php/topic,31078.msg248418.html#msg248418
  headers["Connection"] = "keep-alive" 
--    headers["Accept-Encoding"] = "Identity"        -- added 2015.12.19 to stop chunked responses
--    headers["Allow"] = "GET"                       -- added 2015.10.06
  
  local chunked
  if not content_length then
    headers["Transfer-Encoding"] = "Chunked"
    chunked = true
  end
  
  local crlf = "\r\n"
  local status_line = "HTTP/1.1 %d %s"
  local h = { status_line: format (status, status_codes[status] or "Unknown error") }
  for k, v in pairs(headers) do 
    h[#h+1] = table.concat { k, ": ", v }
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
local function send_chunked (sock, x, n)
  local N = #x
  n = n or N
  local ok, err = true
  local i,j = 1, math.min(n, N)
  local hex = "%x\r\n"
  local Nc = 0
  while i <= N and ok do
    Nc = Nc + 1
    send (sock, hex: format (j-i+1))
    ok, err = send (sock,x,i,j)
    send (sock, "\r\n")
    i,j = j + 1, math.min (j + n, N)
  end
  send (sock, "0\r\n\r\n")
  return ok, err, Nc
end

-- build response and send it
local function respond (request, ...)
  local sock = request.sock

  local headers, response, chunked = http_response (...)
  send (sock, headers)
  
  local ok, err, nc
  if chunked then
    ok, err, nc= send_chunked (sock, response, CHUNKED_LENGTH)
  else
    ok, err, nc = send (sock, response)
  end
  
  local t = math.floor (1000*(socket.gettime() - request.request_start))
  local completed = "request completed (%d bytes, %d chunks, %d ms) %s"
  _log (completed:format (#response, nc, t, tostring(sock)))
  
end
 

-- convert headers to table with name/value pairs, and CamelCaps-style names
local function http_read_headers (sock)
  local n = 0
  local line, err
  local headers = {}
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
local function receive (sock)
  local request                               -- the request object
  local headers, post_content
  
  local ip = sock:getpeername() or '?'        -- who's asking?
  iprequests [ip] = {ip = ip, date = os.time(), mac = "00:00:00:00:00:00"} --TODO: real MAC address - how?
  
  local line, err = sock:receive()        -- read the request line
  if not err then  
    _log (line .. ' ' .. tostring(sock))
    
    -- Request-Line = Method SP Request-URI SP HTTP-Version CRLF
    local method, request_URI, http_version = line: match "^(%u+)%s+(.-)%s+(HTTP/%d%.%d)%s*$"
    
    headers, err = http_read_headers (sock)
    if method == "POST" then
      local length = tonumber(headers["Content-Length"]) or 0
      post_content, err = sock:receive(length)
    end
  
    request = request_object (request_URI, headers, post_content, method, http_version, sock, ip)
     
    if not (method == "GET" or method == "POST") then
      err = "Unsupported HTTP request:" .. method
    end
  
  else
    sock: close ()
    _log (("socket closed: %s %s"): format (err or '?', tostring (sock)))
  end
  return request, err
end
  

---------
--
-- handle each client request by running an asynchronous job
--

--
-- this is a job for each new client connection
-- (may handle multiple requests sequentially)
--

local function new_client (sock)
  local expiry
  
  local function incoming (sock)
    local request, err = receive (sock)                       -- get the request         
    if not err then
      --  returns are as in err, msg, jobNo = scheduler.run_job ()
      local _, _, _ = servlet.execute (request, respond)
    end
    
    expiry = socket.gettime () + CLOSE_IDLE_SOCKET_AFTER      -- update socket expiry 
    if err and (err ~= "closed") then 
      _log ("read error: " ..  tostring(err) .. ' ' .. tostring(sock))
      sock: close ()                                -- it may be closed already
      scheduler.socket_unwatch (sock)               -- stop watching for incoming
      expiry = 0
    end
  end

--  local function job (devNo, args, job)
  local function job ()
    if socket.gettime () > expiry then                    -- close expired connection... 
      _log ("closing client connection: " .. tostring(sock))
      sock: close ()                                      -- it may be closed already
      scheduler.socket_unwatch (sock)                     -- stop watching for incoming
      return scheduler.state.Done, 0                      -- and exit
    else
      return scheduler.state.WaitingToStart, 5            -- ... checking every 5 seconds
    end
  end
  
  -- new_client ()
  local ip = sock:getpeername() or '?'                    -- who's asking?
  local connect = "new client connection from %s: %s"
  _log (connect:format (ip, tostring(sock)))
  expiry = socket.gettime () + CLOSE_IDLE_SOCKET_AFTER    -- set initial socket expiry 
  sock:settimeout(nil)                                    -- this is a timeout on the HTTP read
--  sock:settimeout(10)                                   -- this is a timeout on the HTTP read
  sock:setoption ("tcp-nodelay", true)                    -- trying to fix timeout error on long strings
  scheduler.socket_watch (sock, incoming)                 -- start listening for incoming
--  local err, msg, jobNo = scheduler.run_job {job = job}
  local _, _, jobNo = scheduler.run_job {job = job}
  if jobNo and scheduler.job_list[jobNo] then
    local info = "job#%d :HTTP new connection %s"
    scheduler.job_list[jobNo].type = info: format (jobNo, tostring(sock))
  end
end

----
--
-- start (), sets up the HTTP request handler
-- returns list of utility function(s)
-- 
local function start (port, config)
  config = config or {}               -- 2017.03.15 server configuration table
  BACKLOG = config.Backlog or BACKLOG
  CHUNKED_LENGTH = config.ChunkedLength or CHUNKED_LENGTH
  CLOSE_IDLE_SOCKET_AFTER = config.CloseIdleSocketAfter or CLOSE_IDLE_SOCKET_AFTER
  URL_AUTHORIZATION = config.WgetAuthorization == "URL"
  PORT = port
  
  local server, msg = socket.bind ('*', port, BACKLOG) 
   
  -- new client connection
  local function server_incoming (server)
    repeat                                              -- could be multiple requests
      local sock = server:accept()
      if sock then new_client (sock) end
    until not sock
  end

  local function stop()
    server: close()
  end

  -- start(), create HTTP server job and start listening
  if server then 
    server:settimeout (0)                                       -- don't block 
    scheduler.socket_watch (server, server_incoming)            -- start watching for incoming
    _log (table.concat {"starting HTTP server on ", myIP, ':', port, ' ', tostring(server)})
    return {stop = stop}
  else
    _log ("error starting server: " .. (msg or '?'))
  end  
end

--- return module variables and methods

return {
    ABOUT = ABOUT,
    
    TEST = {          -- for testing only
      CamelCaps       = CamelCaps,
      http_response   = http_response,
      make_content    = make_content,
      request_object  = request_object,
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
    wget = wget,
    send = send,
    start = start,
  }

-----
