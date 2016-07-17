local ABOUT = {
  NAME          = "openLuup.server",
  VERSION       = "2016.07.17",
  DESCRIPTION   = "HTTP/HTTPS GET/POST requests server and luup.inet.wget client",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
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

---------------------

-- 2016.07.12   start refactoring: request dispatcher and POST queries
-- 2016.07.14   request object parameter and WSAPI-style returns for all handlers
-- 2016.07.17   HTML error pages

local socket    = require "socket"
local url       = require "socket.url"
local http      = require "socket.http"
local https     = require "ssl.https"
local logs      = require "openLuup.logs"
local devices   = require "openLuup.devices"            -- to access 'dataversion'
local scheduler = require "openLuup.scheduler"
local json      = require "openLuup.json"               -- for unit testing only
local wsapi     = require "openLuup.wsapi"              -- WSAPI connector for CGI processing
local tables    = require "openLuup.servertables"       -- mimetypes and status_codes
local vfs       = require "openLuup.virtualfilesystem"

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control

-- CONSTANTS

local CHUNKED_LENGTH      = 16000     -- size of chunked transfers
local CLOSE_SOCKET_AFTER  = 90        -- number of seconds idle after which to close socket
local MAX_HEADER_LINES    = 100       -- limit lines to help mitigate DOS attack or other client errors

-- TABLES

local mimetype = tables.mimetypes
local status_codes = tables.status_codes

local iprequests = {}     -- log of incoming requests {ip = ..., mac = ..., time = ...} indexed by ip

local http_handler = {    -- the data_request?id=... handler dispatch list
  TEST = {
      callback = function (...) return json.encode {...}, mimetype.json end    -- just for testing
    },
  }
  
local function file_type (filename)
  return filename: match "%.([^%.]+)$"     -- extract extension from filename
end

-- GLOBAL functions

local function mime_file_type (filename)
  return mimetype[file_type (filename) or '']                        -- returns nil if unknown
end

-- add callbacks to the HTTP handler dispatch list  
-- and remember the device context in which it's called
-- fixed callback context - thanks @reneboer
-- see: http://forum.micasaverde.com/index.php/topic,36207.msg269018.html#msg269018
local function add_callback_handlers (handlers, devNo)
  for name, proc in pairs (handlers) do     
    http_handler[name] = {callback = proc, devNo = devNo}
  end
end

-- http://forums.coronalabs.com/topic/21105-found-undocumented-way-to-get-your-devices-ip-address-from-lua-socket/
local myIP = (
  function ()    
    local mySocket = socket.udp ()
    mySocket:setpeername ("42.42.42.42", "424242")  -- arbitrary IP and PORT
    local ip = mySocket:getsockname () 
    mySocket: close()
    return ip or "127.0.0.1"
  end) ()

-- return HTML for error given numeric status code and optional extended error message
local function error_html(status, msg)
  local html = [[
  <!DOCTYPE html>
  <html>
    <head><title>%d - %s</title></head>
    <body><p>%s</p></body>
  </html>
  ]]
  local content = html: format (status, status_codes[status] or "Error", tostring(msg or "Unknown error"))
  return content, #content, "text/html"
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

-- turn a content string into a one-shot iterator, returning same (for WSAPI-style handler returns)
local function make_iterator (content)      -- one-shot iterator (no need for coroutines!)
  return function ()
    local x = content
    content = nil
    return x
  end
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
-- REQUEST HANDLER: /data_request?id=... queries only (could be GET or POST)
--

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
    local request_name = id: gsub ("^lr_", '')     -- remove leading "lr_"
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
  path = path: gsub ("cmh/skins/default/img/devices/device_states/", "icons/")  -- redirect UI7 icon requests
  path = path: gsub ("cmh/skins/default/icons/", "icons/")                      -- redirect UI5 icon requests
  
  local content_type = mime_file_type (path)
  local content_length
  local response
  local status = 500
  
  local f = io.open(path,'rb')                      -- 2016.03.05  'b' for Windows, thanks @vosmont
    or io.open ("../cmh-lu/" .. path, 'rb')         -- 2016.02.24  also look in /etc/cmh-lu/
    or io.open ("files/" .. path, 'rb')             -- 2016.06.09  also look in files/
    or io.open ("openLuup/" .. path, 'rb')          -- 2016.05.25  also look in openLuup/
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


----------------------------------------------------
--
-- return a request object containing all the information a handler needs
-- only required parameter is request_URI, others have sensible defaults.

local function request_object (request_URI, headers, post_content, method, http_version)
  -- picks the appropriate handler depending on request type
  local selector = {
      ["cgi"]           = wsapi.cgi,
      ["cgi-bin"]       = wsapi.cgi,
      ["upnp"]          = wsapi.cgi,
      ["data_request"]  = data_request,
    }
  
  local self_reference = {
    ["localhost"] = true,
    ["127.0.0.1"] = true, 
    ["0.0.0.0"] = true, 
    [myIP] = true,
  }
  
  if not (request_URI: match "^https?://") or (request_URI: match "^//") then request_URI = "//" .. request_URI end
 
  local URL = url.parse (request_URI)                 -- parse URL

  -- construct parameters from query string or POST content
  local parameters
  method = method or "GET"
  if method == "GET" and URL.query then
    parameters = parse_parameters (URL.query)   -- extract useful parameters from query string
  elseif method == "POST" and headers["Content-Type"] == "application/x-www-form-urlencoded" then
    parameters = parse_parameters (post_content)
  end

  local path_list = url.parse_path (URL.path) or {}   -- split out individual parts of the path
  local handler   = selector [path_list[1]] or http_file
  local internal  = self_reference [URL.host] and URL.port == "3480"  -- 2016-03-16 check for port #, thanks @reneboer

  return setmetatable ({
      URL           = URL,
      headers       = headers or {},
      post_content  = post_content or '',
      method        = method,
      http_version  = http_version or "HTTP/1.1",
      path_list     = path_list,
      internal      = internal,
      parameters    = parameters or {},

      handler = handler },{__call = handler})    -- allows the request object to be called directly
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
    status, headers, iterator = request ()            -- make the request call
    result = make_content (iterator)                  -- build the return string
  
  else
    
    -- EXTERNAL request OR not port 3480 
    local scheme = http
    local URL = request.URL
    URL.scheme = URL.scheme or "http"                 -- assumed undefined is http request
    if URL.scheme == "https" then scheme = https end  -- 2016.03.20
    URL.user = Username                               -- add authorization credentials
    URL.password = Password
    URL= url.build (URL)                              -- reconstruct request for external use
    scheme.TIMEOUT = Timeout or 5
    result, status = scheme.request (URL)
  
  end
  
  if result and status == 200 then status = 0 end     -- wget has a strange return code
  return status, result or ''                         -- note reversal of parameter order cf. http.request()
end


----------------------------------------------------
--
-- RESPOND to requests over HTTP
--

-- generate response
local function http_response (status, headers, iterator)
  
  local Hdrs = {}           -- force CamelCaps-style header names
  for a,b in pairs (headers) do Hdrs[CamelCaps(a)] = b end
  headers = Hdrs        
  
  local response = make_content (iterator)    -- just for the moment, simply unwrap the iterator
  local content_type = headers["Content-Type"]
  local content_length = headers["Content-Length"]  
 
  if status ~= 200 then 
    headers = {}
    response, content_length, content_type = error_html (status, response)
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
  return ok, err
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
--    socket.sleep(0.001) -- TODO: REMOVE SLEEP !!!!
    send (sock, hex: format (j-i+1))
    ok, err = send (sock,x,i,j)
    send (sock, "\r\n")
    i,j = j + 1, math.min (j + n, N)
  end
  send (sock, "0\r\n\r\n")
  return ok, err, Nc
end

-- build response and send it
local function respond (sock, ...)

  local headers, response, chunked = http_response (...)
  send (sock, headers)
  
  local ok, err, nc
  if chunked then
    ok, err, nc= send_chunked (sock, response, CHUNKED_LENGTH)
  else
    ok, err, nc = send (sock, response)
  end
  return #response, nc or 0
end
 
---------
--
-- handle each client request by running an asynchronous job
--

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

-- process client request
local function client_request (sock)
  local request                         -- the request object
  local start_time = socket.gettime()   -- remember when we started (for timeout)
 
  -- receive client request
  local function receive ()
    local headers, post_content
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
    
      request = request_object (request_URI, headers, post_content, method, http_version)
       
      if not (method == "GET" or method == "POST") then
        err  ="Unsupported HTTP request:" .. method
      end
    
    else
      sock: close ()
      _log (("receive error: %s %s"): format (err or '?', tostring (sock)))
    end
    return err
  end
  
  -- special scheduling parameters used by the job 
  local Timeout       -- (s)  respond after this time even if no data changes 
  local MinimumDelay  -- (ms) initial delay before responding
  local DataVersion   --      previous data version value
  
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
      and socket.gettime() - start_time < (Timeout or 0) then   -- and not timed out
        return scheduler.state.WaitingToStart, 0.5              -- wait a bit and try again
    end
    
    -- finally (perhaps) execute the request
    local n, nc = respond (sock, request ())              -- execute and respond 
    
    local t = math.floor (1000*(socket.gettime() - start_time))
    local completed = "request completed (%d bytes, %d chunks, %d ms) %s"
    _log (completed:format (n, nc, t, tostring(sock)))
    
    return scheduler.state.Done, 0  
  end
  
  
  -- client_request ()
  local ip = sock:getpeername()                         -- who's asking?
  ip = ip or '?'
  iprequests [ip] = {ip = ip, date = os.time(), mac = "00:00:00:00:00:00"} --TODO: real MAC address - how?
  local err = receive ()
  if not err then
    
    -- /data_request?DataVersion=...&MinimumDelay=...&Timeout=... parameters have special significance
    if request.handler == data_request then      
      local p = request.parameters
      Timeout      = tonumber (p.Timeout)                     -- seconds
      MinimumDelay = tonumber (p.MinimumDelay or 0) * 1e-3    -- milliseconds
      DataVersion  = tonumber (p.DataVersion)                 -- timestamp
    end

    --  err, msg, jobNo = scheduler.run_job ()
    local _, _, jobNo = scheduler.run_job ({job = job}, {}, nil)  -- nil device number
    if jobNo and scheduler.job_list[jobNo] then
      scheduler.job_list[jobNo].notes = "HTTP request from " .. tostring(ip)
    end
  end
  return err
end

--
-- this is a job for each new client connection
-- (may handle multiple requests sequentially)
--

local function new_client (sock)
  local expiry
  
  local function incoming (sock)
    local err = client_request (sock)                  -- launch new job to handle request 
    expiry = socket.gettime () + CLOSE_SOCKET_AFTER      -- update socket expiry 
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
  
  _log ("new client connection: " .. tostring(sock))
  expiry = socket.gettime () + CLOSE_SOCKET_AFTER         -- set initial socket expiry 
  sock:settimeout(nil)                                    -- this is a timeout on the HTTP read
--  sock:settimeout(10)                                   -- this is a timeout on the HTTP read
  sock:setoption ("tcp-nodelay", true)                    -- trying to fix timeout error on long strings
  scheduler.socket_watch (sock, incoming)                 -- start listening for incoming
--  local err, msg, jobNo = scheduler.run_job {job = job}
  local _, _, jobNo = scheduler.run_job {job = job}
  if jobNo and scheduler.job_list[jobNo] then
    scheduler.job_list[jobNo].notes = "HTTP new " .. tostring(sock)
  end
end

----
--
-- start (), sets up the HTTP request handler
-- returns list of utility function(s)
-- 
local function start (port, backlog)
  local server, msg = socket.bind ('*', port, backlog or 64) 
   
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
      data_request    = data_request,
      http_file       = http_file,
      http_response   = http_response,
      make_content    = make_content,
      make_iterator   = make_iterator,
      request_object  = request_object,
      wsapi_cgi       = wsapi.cgi,
    },
    
    -- constants
    myIP = myIP,
    
    -- variables
    iprequests = iprequests,
    
    --methods
    add_callback_handlers = add_callback_handlers,
    wget = wget,
    send = send,
    start = start,
  }

-----
