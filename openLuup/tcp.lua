local ABOUT = {
  NAME          = "openLuup.tcp",
  VERSION       = "2024.01.03",
  DESCRIPTION   = "TCP Server module",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2024 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2024 AK Booer

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
-- TCP Server module
--
-- 2024.01.03  separated from openLuup.io
-- 


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
  local sendwait = config.sendwait or 0.1               -- socket.select() timeout
  
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
        local _, x = select (empty, s, sendwait)      -- check OK to send, with small delay
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
      sock:setoption ("keepalive", true)        -- TODO: * * * TESTING keepalive * * *    2021.03.25 
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
  
  server = server,
  
  udp = udp,
  
}

----




