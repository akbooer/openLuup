local ABOUT = {
  NAME          = "openLuup.io",
  VERSION       = "2021.03.24b",
  DESCRIPTION   = "I/O module for plugins",
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

--
-- openLuupIO - I/O module for plugins
-- 
-- The Vera/MiOS I/O model is particularly arcane.  Some documentation ...
-- here: http://wiki.micasaverde.com/index.php/Luup_Lua_extensions#Module:_io
-- and here: http://wiki.micasaverde.com/index.php/Luup_Plugins_ByHand#.3Cprotocol.3E
--
-- thanks to @cybrmage for pointing out some implementation problems here.
-- see: http://forum.micasaverde.com/index.php/topic,35972.msg266490.html#msg266490
-- and: http://forum.micasaverde.com/index.php/topic,35983.msg266858.html#msg266858

-- 2016.01.26  fix for protocol = cr, crlf, raw
-- 2016.01.28  @cybrmage fix for read timeout
-- 2016.01.30  @cybrmage log fix for device number
-- 2016.01.31  socket.select() timeouts, 0 mapped to nil for infinite wait
-- 2016.02.15  'keepalive' option for socket - thanks to @martynwendon for testing the solution
-- 2016.11.09  implement version of @vosmont's "cr" protocol in io.read()
--             see: http://forum.micasaverde.com/index.php/topic,40120.0.html

-- 2017.04.10  add Logfile.Incoming option
-- 2017.04.27  only disable intercept after non-raw reads
--             see: http://forum.micasaverde.com/index.php/topic,48814.0.html

-- 2018.03.22  move luup-specific IO functions into sub-module luupio
-- 2018.03.28  add server module for core server framework methods
-- 2018.04.10  use servlet model for io.server incoming callbacks
-- 2018.04.19  add udp.register_handler for incomgin datagrams
-- 2018.06.27  better error message on startup failure

-- 2019.01.25  set_raw_blocksize, see: http://forum.micasaverde.com/index.php/topic,119217.0.html
-- 2019.03.17  __index() function in client socket allows ANY valid socket call to be used
-- 2019.05.11  add request IP to incoming server job info
-- 2019.11.29  server.new() watches client proxy, rather than socket itself, as passed to incoming handler
--   see: https://community.getvera.com/t/expose-http-client-sockets-to-luup-plugins-requests-lua-namespace/211263

-- 2021.03.24  add client.send() with check for socket ready


local OPEN_SOCKET_TIMEOUT = 5       -- wait up to 5 seconds for initial socket open
local READ_SOCKET_TIMEOUT = 5       -- wait up to 5 seconds for incoming reads

local RAW_BLOCKSIZE = 1

local socket    = require "socket"
local logs      = require "openLuup.logs"
local scheduler = require "openLuup.scheduler"

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

local empty = setmetatable ({}, {__newindex = function() error ("read-only", 2) end})

--[[
 <protocol>

Is the protocol to use to talk to the device if you'll be sending data over the network or a serial port. The protocol tag tells Luup what's considered a single chunk of data. By using a format, from the supported list below, you avoid byte-by-byte processing on input streams as the Luup engine will chunk the data to you and pass it to your Lua code handling <incoming> requests. Lua code is much cleaner when it handles data in chunks. If you have a protocol that's not natively supported, and is likely to be used by other devices, let us know and we'll add it to the Luup engine so you don't need to mess with it.

Valid values for this tag are:

    cr - all incoming commands are terminated with a carriage return+line character, and all outgoing data should have a cr appended. Incoming data will have the cr stripped off.
    crlf - all incoming commands are terminated with a carriage return+line feed character, and all outgoing data should have a cr+lf appended. Incoming data will have the cr/lf stripped off.
    stxetx - all incoming commands are surrounded by STX and ETX characters. If you send the string "test" the framework will add the STX before and the ETX at the end, and if the string "<stx>test<etx>" is received, the framework will strip the STX and ETX and pass the string "test" to your incoming data handler.
    raw - makes no modifications to outgoing data, and calls your incoming data callback for each byte received. This adds more overhead since the engine needs to call your Luup function for every character, and makes your code complex. So, generally avoid using 'raw' and let us add support for your protocol if you have a new one we don't yet support. 

Caution: the <protocol> tag can be either in the I_xxxx file or the D_xxxx file or both. If the latter, they must be identical.

--]]

-- utility functions

local function set_raw_blocksize (n)    -- 2019.01.25
  RAW_BLOCKSIZE = n
end
  
local function get_dev_and_socket (device)
  local devNo = tonumber (device) or scheduler.current_device()
  local dev = devNo and luup.devices [devNo] 
  return dev, (dev or {io = {}}).io.socket, devNo
end

local function read_raw (sock)
  return sock: receive (RAW_BLOCKSIZE)             -- single byte only
end

local function read_cr (sock)          -- 2016.11.09 
  local buffer = {}
  local data, err, ch
  repeat
    ch, err = sock: receive (1)
    local cr = (ch == "\r")
    if not cr then buffer[#buffer+1] = ch end
  until err or cr
  if not err then data = table.concat (buffer) end
  return data, err
end

local function read_crlf (sock)
  -- From the LuaSocket documentation: 
  -- The line is terminated by a LF character (ASCII 10), optionally preceded by a CR character (ASCII 13). 
  -- The CR and LF characters are not included in the returned line. 
  -- In fact, all CR characters are ignored by the pattern. 
  return sock: receive "*l"
end

local function read_nothing () end

local reader = {raw = read_raw, cr = read_cr, crlf = read_crlf}   
-- TODO: 'stxetx' mode for read NOT currently supported

local function receive (sock, protocol)
  return (reader [protocol] or read_nothing) (sock)
end

local function send (sock, data, protocol)
  local eol = {cr = "\r", crlf = "\r\n"}      -- TODO: 'stxetx' mode for write NOT currently supported
  local fmt = "message length: %s, bytes sent: %d, status: %s %s"
  if eol[protocol] then data = data .. eol[protocol] end
  local status, msg, last = sock: send (data)             -- send the message
  _log (fmt: format (#data, status or last-1, msg or "OK", tostring(sock)), "luup.io.write") 
  return status
end
  
-- function: open
-- parameters: device (string or number), ip (string), port (as number or string),
-- returns: nothing
--
-- This opens a socket on 'port' to 'ip' and stores the handle to the socket in 'device'. 
-- The opening of a socket can take time depending on the network, and a Luup function should return quickly 
-- whenever possible because each top-level device's Lua implementation runs in a single thread. 
-- So the actual opening of the socket occurs asynchronously and this function returns nothing. 
-- You will know that the socket opening failed if your subsequent call to write fails.
--
-- Generally you do not need to call the open function 
-- because the socket is usually started automatically when the Luup engine starts. 
-- This is because the user typically either 
--  (a) associates a device with the destination io device, 
--      such as selecting an RS232 port for an alarm panel, where the RS232 is proxied by a socket, or 
--  (b) because the configuration settings for the device already include an IP address and port.
--
-- There is no 'function: close'.

local function open (device, ip, port)
  local dev, sock, devNo = get_dev_and_socket (device)  
  local protocol = dev.io.protocol
  local openLuup = luup.attr_get "openLuup"
  
  local function incoming (sock)
    local data, err = receive (sock, protocol)        -- get data
    if data then
      if openLuup.Logfile.Incoming == "true" then
        _log (("bytes received: %d, status: %s %s"): format ((#data or 0), 
            err or "OK", tostring(sock)), "luup.io.incoming")
      end
      local ok, msg = scheduler.context_switch (devNo, dev.io.incoming, devNo, data) 
      if not ok then _log(msg) end
    else
      if err == "closed" then 
        sock: close ()            -- close our end
        scheduler.socket_unwatch (sock)
        _log ("socket connection closed " .. tostring (sock))
      else
        _log ((err or '?') .. ' ' .. tostring (sock))
      end
    end
  end

  local function connect ()
    local ok, msg
    sock, msg = socket.tcp ()
    if sock then
      sock:settimeout (OPEN_SOCKET_TIMEOUT)
      sock:setoption ("tcp-nodelay", true)    -- so that alternate read/write works as expected (no buffering)
      sock:setoption ("keepalive", true)      -- keepalive, thanks to @martynwendon for testing this solution
      ok, msg = sock:connect (ip, port) 
    end
    local fmt = "connecting to %s:%s, using %s protocol %s"
    _log (fmt: format (ip, port,dev.io.protocol or "unknown", tostring(sock) ), "luup.io.open")
    if ok then
      _log "connect OK"
      dev.io.socket = sock 
      if dev.io.incoming then
        scheduler.socket_watch (sock, incoming, dev.io)   -- pass the device io table containing intercept flag
      end
    else
      _log ("connect FAIL: " .. (msg or '?'))
    end
    return scheduler.state.Done
  end

  if dev and not sock then
    local jobNo
    scheduler.run_job ({run = connect}, nil, devNo)   -- run now 
--    local __,__, jobNo = scheduler.run_job ({job = connect}, nil, devNo)   -- ...or, schedule for later 
    _debug (("starting job #%d to connect to %s:%s"): format (jobNo or 0, ip, tostring(port)), "luup.io.open")
  end
end

-- function: write
-- parameters: data (string), optional device (string or number)
-- returns: result (boolean or nil)
--
-- The device id defaults to self, if omitted. In Lua a string can contain binary data, so data may be a binary block. 
-- This sends data on the socket that was opened automatically or with the open function above, and associated to 'device'. 
-- If the socket is not already open, write will wait up to 5 seconds for the socket before it returns an error. 
-- Result is 'true' if the data was sent successfully, and is 'false' or nil if an error occurred.

local function write (data, device)
  local status 
  local dev, sock = get_dev_and_socket (device)  
  if dev and sock then
    local _, _, err = socket.select (nil, {sock}, 5)         -- 5 second timeout if not ready for writing
    if err then 
      local fmt = "error: %s %s"
      _log (fmt:format (err or '?', tostring(sock)), "luup.io.write") 
    else
      status = send (sock, data, dev.io.protocol)        -- send the message
    end
  end
  return not not status               -- just return true or false (not the returned byte count)
end

-- function: intercept
-- parameters: device (string or number)
-- returns: nothing
--[[
Normally when data comes in on a socket (I/O Port), the block of data is first passed to any pending jobs that are running for the device and 
are marked as 'waiting for data'. If there are none, or if none of the jobs' incoming data handlers report that they consumed (i.e. processed) the data, 
then the block of data is passed to the general 'incoming' function handler for the device. 
If you want to bypass this normal mechanism and read data directly from the socket, call intercept first 
to tell Luup you want to read incoming data with the read function. 
This is generally used during the initialization or startup sequences for devices. 
For example, you may need to send some data (a), receive some response (b), send some more data (c), receive another response (d), etc. 
In this case you would call 'intercept' first, then send a, then call read and confirm you got b, then call intercept again, then send c, then read d, and so on.

You can call the read function without calling intercept and any incoming data will be returned by that function after it's called. 
The reason why you generally must call intercept is because normally you want to send some data and get a response. 
If you write the code like this send(data) data=read() then it's possible the response will arrive in the brief moment between the execution of send() and read(), 
and therefore get sent to the incoming data handler for the device. 
Intercept tells Luup to buffer any incoming data until the next read, bypassing the normal incoming data handler. 
So intercept() send(data) data=read() ensures that read will always get the response. 
If the device you're communicating with sends unsolicited data then there's the risk that the data you read is not the response you're looking for. 
If so, you can manually pass the response packet to the incoming data handler.

--]]

local function intercept (device) 
  local dev = get_dev_and_socket (device)  
  if dev then
    dev.io.intercept = true      -- bypass <incoming> processing, FOR ONE READ ONLY
  end
end

-- function: read
-- parameters: timeout (number), device (string or number)
-- returns: data (string)
--
-- This reads a block of data from the socket. 
-- You must have called intercept previously so the data is passed. The time unit for timeout is seconds.

local function read (timeout, device)
  local data, msg
  if timeout == 0 then timeout = nil end                    -- 0 means no timeout in luup
  local dev, sock = get_dev_and_socket (device)  
  if dev and sock and dev.io.intercept then
    local _,_,msg1 = socket.select ({sock}, nil, timeout)   -- use select to implement reliable timeout 
    if not msg1 then
      data, msg = receive (sock, dev.io.protocol)           -- get data
    end
    local msg = msg or msg1
    if not data then 
      local fmt = "error: %s %s"
      local text = fmt: format (msg or '?', tostring(sock))
      _log (text, "luup.io.read")
    else
      local fmt = "bytes received: %d, status: %s %s"
      local text = fmt: format ((#data or 0), msg or "OK", tostring(sock))
      _log (text, "luup.io.read")
    end
    if dev.io.protocol ~= "raw" then              -- 2017.04.27 only disable for non-raw reads
      dev.io.intercept = false                    -- turn off intercept now this read is done
    end
    sock:settimeout (READ_SOCKET_TIMEOUT)         -- revert to incoming timeout
  end
  return data
end

-- function: is_connected
-- parameters: device (string or number)
-- returns: connected (boolean)
--
-- This function returns true if there is a valid IO port connected, otherwise returns false. 
-- Unplugging the LAN cable associated with the port, will not set the flag to false.

local function is_connected (device)
  local _, sock = get_dev_and_socket (device)  
  return not not sock 
end

------------
--
-- Server/Client modules
--

-- utility function to log incoming connection requests for console server pages
local function log_request (connects, ip)
  ip = ip or '?'
  local info = connects [ip] or
          {ip = ip, count = 0, mac = "00:00:00:00:00:00"}  -- real MAC address - can't find a way to do it!
  info.date = os.time()
  info.count = info.count + 1
  connects [ip] = info
end

------------
--
-- UDP Module
--
-- This is a bit different from a normal client/server connection model, because UDP is transaction-free.
-- You can open socket to send a datagram somewhere, and also listen on one to receive from elsewhere.


local udp = {
    iprequests  = {},     -- incoming connections, indexed by IP
    listeners   = {},     -- registered listener ports
    senders     = {},     -- opened sender ports
  }

   -- open for send
  function udp.open (ip_and_port)   -- returns UDP socket configured for sending to given destination
    local sock, msg, ok
    local ip, port = ip_and_port: match "(%d+%.%d+%.%d+%.%d+):(%d+)"
    if ip and port then 
      sock, msg = socket.udp()
      if sock then ok, msg = sock:setpeername(ip, port) end   -- connect to destination
      
      -- record info for console server page
      udp.senders[#udp.senders+1] = {                         -- can't index by port, perhaps not unique
          devNo = scheduler.current_device (),
          ip_and_port = ip_and_port,
          sock = sock,
          count = 0,      -- don't, at the moment, count number of datagrams sent
        }
    else
      msg = "invalid ip:port syntax '" .. tostring (ip_and_port) .. "'"
    end
    if ok then ok = sock end
    return ok, msg
  end
    
    
  -- register a handler for the incoming datagram
  -- callback function is called with (port, {datagram = ..., ip = ...}, "udp")
  function udp.register_handler (callback, port)
    local sock, msg, ok = socket.udp()                -- create the UDP socket
    local function udplog (msg) _log (msg,  "openLuup.io.udp") end
    local _log = udplog

    -- this callback invoked by the scheduler in protected mode (and caller device context)
    local function incoming ()
      local datagram, ip 
      repeat
        datagram, ip = sock:receivefrom()             -- non-blocking since timeout = 0 (also get sender IP)
        if datagram then 
          ip = ip or '?'
          log_request (udp.iprequests, ip)                          -- log the IP request
          local list = udp.listeners[port] or {count = 0}
          list.count = list.count + 1                               -- log the listener port
          callback (port, {datagram = datagram, ip = ip}, "udp")     -- call the user-defined handler
        end
      until not datagram
    end

    -- register_handler()
    if sock then
      sock:settimeout (0)                           -- don't block! 
      ok, msg = sock:setsockname('*', port)         -- listen for any incoming datagram on port
      if ok and callback then
        
        udp.listeners[port] = {                     -- record info for console server page
            callback = callback, 
            devNo = scheduler.current_device (),
            port = port,
            count = 0,
          }
        
        scheduler.socket_watch (sock, incoming, nil, "UDP ")     -- start watching for incoming
        msg = "listening for UDP datagram on port " .. port
        _log (msg)
      else
        _log (msg or "unknown error or missing callback function")
      end
    end
  
  end


------------
--
-- TCP Module
--

local tcp = {
  
     -- TODO: implement TCP client (cf. wget)
     
  }


------------
--
-- Generic Server Module
--
-- This core functionality may be used by HTTP, SMTP, POP, and other servers, to provide services.
-- It offers callbacks on connections and incoming data, and socket management, including timeouts.
--

local server = {}

--[[

Usage:

local ok, err = io.server.new (config)
  
function incoming (client)  -- client object is a proxy socket
  client: receive()
  client: send ()
  client: close ()
end

function startup (client)
  -- some initialisation of user code
end

--]]


-- server.new{}, returns server object with methods: stop
-- parameters:
--    {
--      port = 1234,            -- incoming port
--      name = "SMTP",          -- server name
--      backlog = 100,          -- queue length
--      idletime = 30,          -- close idle socket after
--      servlet = servlet,      -- callback on initial connection
--      connects = connects,    -- a table to report connection statistics
--    }
--
-- servlet is a function which is called with a client object for every new connection.
-- it returns a function to be called for each new incoming line.
--

function server.new (config)
  
  config = config or {}
  local idletime = config.idletime or 30                -- 30 second default on no-activity timeout
  local backlog = config.backlog or 64                  -- default pending queue length
  local name = config.name or "anon"
  local port = tostring (config.port)
  local servlet = config.servlet
  local connects = config.connects or {}                -- statistics of incoming connections
  local select = socket.select
  
  local ip                                              -- client's IP address
  local server, err = socket.bind ('*', port, backlog)  -- create the master listening port
  
  local logline = "%s %s server on port: %s " .. tostring(server)
  local function iolog (msg) _log (msg,  "openLuup.io.server") end
  local _log = iolog
  
  -- call for every new client connection
  local function new_client (sock)
    local expiry
    local incoming -- defined by servlet return
    
    -- passthru to client callback to update timeout
    local function callback ()
      expiry = socket.gettime () + idletime      -- update socket expiry 
      incoming ()
    end
    
    do -- initialisation
      ip = sock:getpeername() or '?'                                    -- who's asking?
      log_request (connects, ip)
      local connect = "%s connection from %s %s"
      _log (connect:format (name, ip, tostring(sock)))
    end
    
    -- create the client object... a modified socket
    -- 2019.03.17 __index() function allows ANY valid socket call to be used
    local client = {            -- client object
        ip = ip,                              -- ip address of the client
        closed = false,
      }
      client.send = function (self, ...)      -- 2021.03.24 check socket ready to send
        local s = {sock}
        local _, x = select (empty, s, 0.2)      -- check OK to send, with small delay
        if #x == 0 then return nil, "socket.select() not ready to send ".. tostring(sock) end
        return sock: send (...)
      end
      client.close = function (self, msg)         -- note optional log message cf. standard socket close
          if not self.closed then
            self.closed = true
            local disconnect = "%s connection closed %s %s"
            _log (disconnect: format (name, msg or '', tostring(sock)))
--            scheduler.socket_unwatch (sock)   -- immediately stop watching for incoming, 2019.11.29 change to client
            scheduler.socket_unwatch (client)   -- immediately stop watching for incoming
            sock: close ()
          end
          expiry = 0             -- let the job timeout
        end
      setmetatable (client,{
        __index = function (s, f) 
            s[f] = function (_, ...) return sock[f] (sock, ...) end
            return s[f]  -- it's there now, so no need to recreate it in future
          end,
        __tostring = function() return tostring(sock) end,   -- for pretty log
      })
  
    do -- configure the socket
      expiry = socket.gettime () + idletime     -- set initial socket expiry 
      sock:settimeout(nil)                      -- no socket timeout on read
      sock:setoption ("tcp-nodelay", true)      -- allow consecutive read/writes
    end
    
    do -- start a new user servlet using client socket and set up its callback
      incoming = servlet(client)                -- give client object and get user incoming callback
--      scheduler.socket_watch (sock, callback, nil, name)   -- start listening for incoming, 2019.11.29 change to client
      scheduler.socket_watch (client, callback, nil, name)   -- start listening for incoming
    end
    
    --  job (), wait for job expiry
    local function job ()
      if socket.gettime () > expiry then                    -- close expired connection... 
        client: close "EXPIRED"
        return scheduler.state.Done, 0                      -- and exit
      else
        return scheduler.state.WaitingToStart, 5            -- ... checking every 5 seconds
      end
    end

    do -- run the job
      local _, _, jobNo = scheduler.run_job {job = job}
      if jobNo and scheduler.job_list[jobNo] then
        local info = "server: %s connection from %s %s"
        scheduler.job_list[jobNo].type = info: format (name, tostring(ip), tostring(sock))  -- 2019.05.11
      end
    end
  end  -- of new_client

  -- new client connection
  local function server_incoming (server)
    repeat                                              -- could be multiple requests
      local sock = server:accept()
      if sock then new_client (sock, config) end
    until not sock
  end

  local function stop()
    _log (logline: format ("stopping", name, port))
    server: close()
  end
  
  -- new (), create server and start listening
  local mod, msg
  if server and servlet then 
    server:settimeout (0)                                           -- don't block 
    scheduler.socket_watch (server, server_incoming, nil, name)     -- start watching for incoming
    msg = logline: format ("starting", name, port)
    mod = {stop = stop}
  else
    -- "%s %s server on port: %s " .. tostring(server)
    msg = logline: format ("ERROR starting", name, port .. ' - ' .. tostring(err))
  end  
  _log (msg)
  return mod, msg
end


------------

-- return methods

return {
  ABOUT = ABOUT,
  
  set_raw_blocksize = set_raw_blocksize,    -- 2019.01.25
  
  luupio = {                    -- this is the luup.io module as seen by the user       
    intercept     = intercept, 
    is_connected  = is_connected,
    open          = open, 
    read          = read, 
    write         = write, 
  },

  udp = udp,
  
  tcp = tcp,
  
  server = server,
  
}

----




