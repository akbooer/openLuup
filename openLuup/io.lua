local ABOUT = {
  NAME          = "openLuup.io",
  VERSION       = "2016.11.09",
  DESCRIPTION   = "I/O module for plugins",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2016 AK Booer

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
-- 2016.01.26 fix for protocol = cr, crlf, raw
-- 2016.01.28 @cybrmage fix for read timeout
-- 2016.01.30 @cybrmage log fix for device number
-- 2016.01.31 socket.select() timeouts, 0 mapped to nil for infinite wait
-- 2016.02.15 'keepalive' option for socket - thanks to @martynwendon for testing the solution
-- 2016.11.09 implement version of @vosmont's "cr" protocol in io.read()
--            see: http://forum.micasaverde.com/index.php/topic,40120.0.html

local OPEN_SOCKET_TIMEOUT = 5       -- wait up to 5 seconds for initial socket open
local READ_SOCKET_TIMEOUT = 5       -- wait up to 5 seconds for incoming reads

local socket    = require "socket"
local logs      = require "openLuup.logs"
local scheduler = require "openLuup.scheduler"

--  local log
--local function _log (msg, name) logs.send (msg, name or _NAME) end
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME, scheduler.current_device()) end

logs.banner (ABOUT)   -- for version control

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

local function get_dev_and_socket (device)
  local devNo = tonumber (device) or scheduler.current_device()
  local dev = devNo and luup.devices [devNo] 
  return dev, (dev or {io = {}}).io.socket, devNo
end

local function read_raw (sock)
  return sock: receive (1)             -- single byte only
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
  
  local function incoming (sock)
    local data, err = receive (sock, protocol)        -- get data
    if data then
      _log (("bytes received: %d, status: %s %s"): format ((#data or 0), err or "OK", tostring(sock)), "luup.io.incoming")
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
    scheduler.run_job ({run = connect}, nil, devNo)   -- run now 
--    local _,_, jobNo = scheduler.run_job ({job = connect}, nil, devNo)   -- ...or, schedule for later 
--    _log (("starting job #%d to connect to %s:%s"): format (jobNo or 0, ip, tostring(port)), "luup.io.open")
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
    dev.io.intercept = false                      -- turn off intercept now this read is done
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


-- return methods

return {
--  ABOUT = ABOUT,      -- commented out, because this is a module visible to the user
  intercept     = intercept, 
  is_connected  = is_connected,
  open          = open, 
  read          = read, 
  write         = write, 
}

----




