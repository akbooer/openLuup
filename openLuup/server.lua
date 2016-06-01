local ABOUT = {
  NAME          = "openLuup.server",
  VERSION       = "2016.06.01",
  DESCRIPTION   = "HTTP/HTTPS GET/PUT requests server and luup.inet.wget client",
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

local socket    = require "socket"
local url       = require "socket.url"
local http      = require "socket.http"
local https     = require "ssl.https"
local logs      = require "openLuup.logs"
local devices   = require "openLuup.devices"    -- to access 'dataversion'
local scheduler = require "openLuup.scheduler"
local json      = require "openLuup.json"       -- only for non-string response error message
local wsapi     = require "openLuup.wsapi"      -- WSAPI connector for CGI processing
local mime      = require "openLuup.mimetypes"
local vfs       = require "openLuup.virtualfilesystem"

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control

-- CONSTANTS

local CLOSE_SOCKET_AFTER  = 90        -- number of seconds idle after which to close socket

-- TABLES

local iprequests = {}     -- log of incoming requests {ip = ..., mac = ..., time = ...} indexed by ip

local http_handler = {} -- the handler dispatch list

local function file_type (filename)
  return filename: match "%.([^%.]+)$"     -- extract extension from filename
end

-- GLOBAL functions

local function MIME (filename)
  return mime[file_type (filename) or '']                        -- returns nil if unknown
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

-- local functions

-- convert HTTP request string into parsed URL with parameter table
local function http_parse_request (request)
  local URL = url.parse (request)
  if URL and URL.query then
  local parameters = {}
    for n,v in URL.query: gmatch "([%w_]+)=([^&]*)" do      -- parameters separated by unescaped "&"
      if v ~= '' then parameters[n] = url.unescape(v) end   -- now can unescape parameter values
    end
    URL.query_parameters = parameters
  end
  return URL
end

-- handle /data_request queries only
local function http_query (URL)
  local ok, response, mtype
  local parameters = URL.query_parameters
  local request = parameters.id or ''
  local handler = http_handler[request]
  if handler and handler.callback then 
    local format = parameters.output_format
    parameters.id = nil               -- don't pass on request id to user...
    parameters.output_format = nil    -- ...or output format in parameters
    -- fixed callback request name - thanks @reneboer
    -- see: http://forum.micasaverde.com/index.php/topic,36207.msg269018.html#msg269018
    local request_name = request: gsub ("^lr_", '')     -- remove leading "lr_"
    ok, response, mtype = scheduler.context_switch (handler.devNo, handler.callback, request_name, parameters, format)
    if not ok then _log ("error in callback: " .. request .. ", error is " .. (response or 'nil')) end
  else 
    response = "No handler for id=" .. request     -- 2016.05.17   log "No handler" responses
    _log (response)
  end
  return (response or 'not a data request'), mtype
end

  
-- handle file requests
-- parameter is either a path string, or a parsed URL table
local function http_file (URL, headers)
  if type(URL) == "string" then URL = {path = URL} end
  local path = URL.path
  path = path: gsub ("%.%.", '')                    -- ban attempt to move up directory tree
  path = path: gsub ("^/", '')                      -- remove filesystem root from path
  path = path: gsub ("luvd/", '')                   -- no idea how this is handled in Luup, just remove it!
  path = path: gsub ("cmh/skins/default/img/devices/device_states/", "icons/")  -- redirect UI7 icon requests
  path = path: gsub ("cmh/skins/default/icons/", "icons/")                      -- redirect UI5 icon requests
  local response_type = MIME (path)
  local info, chunked, response_headers
  local f = io.open(path,'rb')                      -- 2016.03.05  'b' for Windows, thanks @vosmont
    or io.open ("../cmh-lu/" .. path, 'rb')         -- 2016.02.24  also look in /etc/cmh-lu/
    or io.open ("openLuup/" .. path, 'rb')          -- 2016.05.25  also look in openLuup/
    or vfs.open (path, 'rb')                        -- 2016.06.01  also look in virtualfilesystem
  if f then 
    info = (f: read "*a") or ''                   -- should perhaps buffer long files
--    _log ("file length = "..#info, "openLuup.HTTP.FILE")
    f: close ()
    -- @explorer:  2016.04.14, Workaround for SONOS not liking chunked MP3 and some headers.       
    if file_type (path) == "mp3" then    -- 2016.04.28  @akbooer, change this to apply to ALL .mp3 files
      chunked = false
      response_headers = {}
    end
  
  else
    _log ("file not found:" .. path, "openLuup.HTTP.FILE")  
  end
  return info, response_type, chunked, response_headers
end

-- dispatch to appropriate handler depending on whether query or not
-- URL parameter is parsed table of URL structure (see url.parse)

local is_cgi = {["cgi"] = true, ["cgi-bin"] = true, ["upnp"] = true}       -- root locations of CGI directories

local function http_dispatch_request (URL, headers, post_content)    
  local dispatch
-- see: http://forum.micasaverde.com/index.php/topic,34465.msg254637.html#msg254637
-- and: http://forum.micasaverde.com/index.php/topic,34465.msg254650.html#msg254650
  if URL.query and URL.path:match "/data_request$" then     -- Thanks @vosmont 
    dispatch = http_query       
  else
    local url_parts = url.parse_path (URL.path)    
    if is_cgi[url_parts[1]] then       -- deal with CGI calls through WSAPI
      dispatch = wsapi.cgi
    else
      if URL.path: match "/$" then URL.path = URL.path .. "index.html" end   -- 2016.02.20
      dispatch = http_file 
    end
  end
  return dispatch (URL, headers or {}, post_content or '') 
end

-- issue a GET request, handling local ones without going over HTTP
-- Note: that in THIS CASE, the request might be to port 3480, OR ANY OTHER,
--       in which case the filesystem root will be different.
local function wget (URL, Timeout, Username, Password) 
  if not (URL: match "^https?://") or (URL: match "^//") then URL = "//" .. URL end
  local result, status
  local self_reference = {
    ["localhost"] = true,
    ["127.0.0.1"] = true, 
    ["0.0.0.0"] = true, 
    [myIP] = true,
  }
  URL = http_parse_request (URL)                      -- break it up into bits  
  if ((URL.port or '') == "3480")                     -- 2016-03-16 check for port #, thanks @reneboer
  and self_reference [URL.host] then                  -- INTERNAL request
    result = http_dispatch_request (URL)
    if result then status = 0 else status = -1 end    -- assume success
  else                                                -- EXTERNAL request   
    local scheme = http
    URL.scheme = URL.scheme or "http"                 -- assumed undefined is http request
    if URL.scheme == "https" then scheme = https end  -- 2016.03.20
    URL.user = Username                               -- add authorization credentials
    URL.password = Password
    URL= url.build (URL)                              -- reconstruct request for external use
    scheme.TIMEOUT = Timeout or 5
    result, status = scheme.request (URL)
    if result and status == 200 then status = 0 end   -- wget has a strange return code
  end
  return status, result or ''                         -- note reversal of parameter order
end

local function send (sock, data, ...)
--    socket.sleep(0.001) -- TODO: REMOVE SLEEP !!!!
--  socket.select (nil, {sock}, 5)    -- wait for it to be ready.  TODO: fixes timeout error on long strings?
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
    socket.sleep(0.001) -- TODO: REMOVE SLEEP !!!!
    send (sock, hex: format (j-i+1))
    ok, err = send (sock,x,i,j)
    send (sock, "\r\n")
    i,j = j + 1, math.min (j + n, N)
  end
  send (sock, "0\r\n\r\n")
  return ok, err, Nc
end


local function http_response (sock, response, type, chunked, response_headers)
  response = response or ''
  local t = _G.type(response)
  if t ~= "string" then -- Thanks @CudaNet
    -- see: http://forum.micasaverde.com/index.php/topic,34939.msg259460.html#msg259460
    _log ("WARNING - HTTP response is of type " .. t)
    response = json.encode (response)
    _log ("HTTP response: " .. response)
  end
  if not type then                                          -- guess missing type
    if response and response: match "^%s*<!DOCTYPE html" 
      then type = "text/html"
      else type = "text/plain"
    end
  end
  local status = "200 OK"
  if not response then
    status = "404 Not Found"
    response = ''
  end

  -- @explorer: reworked beyond this point:
  if response_headers == nil then
    response_headers = {}
    response_headers["Accept-Encoding"] = "Identity"        -- added 2015.12.19 to stop chunked responses
    response_headers["Allow"] = "GET"                       -- added 2015.10.06
    response_headers["Access-Control-Allow-Origin"] = "*"   -- @d55m14 
      -- see: http://forum.micasaverde.com/index.php/topic,31078.msg248418.html#msg248418
    response_headers["Transfer-Encoding"] = "Chunked"
    response_headers["Connection"] = "keep-alive" 
  end
  response_headers["Content-Type"] = type or "text/plain"
  if chunked == false then
    response_headers["Content-Length"] = #response
  else
    chunked = true
    response_headers["Transfer-Encoding"] = "Chunked"
  end
  response_headers["Server"] = "openLuup/" .. ABOUT.VERSION

  local crlf = "\r\n"
  local headers = "HTTP/1.1 " .. status .. crlf
  for k, v in pairs(response_headers) do headers = headers .. k .. ": " .. v .. crlf end
  headers = headers .. crlf 

  send (sock, headers)
  local ok, err, nc
  if chunked then
    ok, err, nc= send_chunked (sock, response, 16000)
  else
    ok, err, nc = send (sock, response)
  end
  return #(response or {}), nc or 0
end
  
-- convert headers to table with name/value pairs
local function http_read_headers (sock)
  local n = 0
  local line, err
  local headers = {}
  local header_format = "([%a%-]+)%s*%:%s*(.+)%s*"   -- essentially,  header:value pairs
  repeat
    n = n + 1
    line, err = sock:receive()
--    _log ("Request Headers: "..(line or '')) -- **********
    local hdr, val = (line or ''): match (header_format)
    if val then headers[hdr] = val end
  until (not line) or (line == '') or n > 16      -- limit lines to help avoid DOS attack 
  return headers, err
end
 
---------
--
-- handle each client request by running an asynchronous job
--

-- if MinimumTime specified, then make initial delay
local function client_request (sock)
  local URL           -- URL table structure with named components (see url.parse in LuaSocket)
  local headers       -- the request headers
  local post_content  -- content of POST (if any)
  
  local Timeout       -- (s)  query line parameter 
  local MinimumDelay  -- (ms) ditto
  local DataVersion   -- ditto
  local start_time = socket.gettime()   -- remember when we started (for timeout)
 
  -- receive client request
  local function receive ()
    local method, path, major, minor        -- this is the structure of an HTTP request line
    local line, err = sock:receive()        -- read the request line
    if not err then  
      method, path, major, minor = line: match "^(%u+)%s+(.-)%s+HTTP/(%d)%.(%d)%s*$"
      _log ((path or line) .. ' ' .. tostring(sock))
      URL = http_parse_request (path)           -- ...and break it up into bits  
      headers, err = http_read_headers (sock)
      --_log ("HTTP request headers : " .. json.encode(headers))
      if method == "GET" and minor then         -- non-nil 'minor' ensures that request line was correctly parsed
        if URL.query then                       -- some query parameters have special significance
          local p = URL.query_parameters
          Timeout      = tonumber (p.Timeout)
          MinimumDelay = tonumber (p.MinimumDelay or 0) * 1e-3
          DataVersion  = tonumber (p.DataVersion)
        end
      elseif method == "POST" then
        if not err then
          local content_type = headers["Content-Type"]
          local length = tonumber(headers["Content-Length"]) or 0
          post_content, err = sock:receive(length)
        end
--        _log ("HTTP POST context : " .. json.encode(post_content))
      else
        -- TODO: error response to client
        _log ("Unsupported HTTP request:" .. method)
      end
    else
      sock: close ()
      _log (("receive error: %s %s"): format (err or '?', tostring (sock)))
    end
    return err
  end
  
  local function exec_request ()
    local response, type, chunked, response_headers = http_dispatch_request (URL, headers, post_content) 
    local n, nc = http_response (sock, response, type, chunked, response_headers)
    local t = math.floor (1000*(socket.gettime() - start_time))
    _log (("request completed (%d bytes, %d chunks, %d ms) %s"):format (n, nc, t, tostring(sock)))
  end
  
  local function job ()
    -- initial delay (possibly) 
    if MinimumDelay and MinimumDelay > 0 then 
      local delay = MinimumDelay
      MinimumDelay = nil                                -- don't do it again!
      return scheduler.state.WaitingToStart, delay
    end
    -- DataVersion update or timeout (possibly)
    if DataVersion 
      and not (devices.dataversion.value > DataVersion)         -- no updates yet
      and socket.gettime() - start_time < (Timeout or 0) then   -- and not timed out
        return scheduler.state.WaitingToStart, 0.5              -- wait a bit and try again
    end
    -- finally (perhaps) execute the request
    exec_request ()                                     -- run the request 
    return scheduler.state.Done, 0  
  end
  
  
  -- client_request ()
  local ip = sock:getpeername()                         -- who's asking?
  ip = ip or '?'
  iprequests [ip] = {ip = ip, date = os.time(), mac = "00:00:00:00:00:00"} --TODO: real MAC address?
  local err = receive ()
  if not err then
    local err, msg, jobNo = scheduler.run_job ({job = job}, {}, nil)  -- nil device number
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

  local function job (devNo, args, job)
    if socket.gettime () > expiry then                            -- close expired connection... 
      _log ("closing client connection: " .. tostring(sock))
      sock: close ()                                -- it may be closed already
      scheduler.socket_unwatch (sock)               -- stop watching for incoming
      return scheduler.state.Done, 0                -- and exit
    else
      return scheduler.state.WaitingToStart, 5            -- ... checking every 5 seconds
    end
  end
  
  _log ("new client connection: " .. tostring(sock))
  expiry = socket.gettime () + CLOSE_SOCKET_AFTER        -- set initial socket expiry 
  sock:settimeout(nil)                                    -- this is a timeout on the HTTP read
--  sock:settimeout(10)                                    -- this is a timeout on the HTTP read
  sock:setoption ("tcp-nodelay", true)            -- TODO: trying to fix timeout error on long strings
  scheduler.socket_watch (sock, incoming)                -- start listening for incoming
  local err, msg, jobNo = scheduler.run_job {job = job}
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
    
    -- constants
    myIP = myIP,
    
    -- variables
    iprequests = iprequests,
    
    --methods
    MIME = MIME,
    add_callback_handlers = add_callback_handlers,
    http_file = http_file,
    wget = wget,
    send = send,
    start = start,
  }

-----
