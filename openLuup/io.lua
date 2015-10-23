local _NAME = "openLuup.io"
local revisionDate = "2015.10.15"
local banner = "       version " .. revisionDate .. "  @akbooer"

--
-- openLuupIO - I/O module for plugins
-- 
local OPEN_SOCKET_TIMEOUT = 5       -- wait up to 5 seconds for initial socket open

local socket    = require "socket"
local logs      = require "openLuup.logs"
local devutil   = require "openLuup.devices"
local scheduler = require "openLuup.scheduler"

--  local log
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control

-- utility function

local function get_dev_and_socket (device)
  local devNo = tonumber (device or luup.device)
  local dev = devNo and luup.devices [devNo] 
  return dev, (dev or {io = {}}).io.socket, devNo
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
-- Generally you do not need to call the open function because the socket is usually started automatically when the Luup engine starts. 
-- This is because the user typically either (a) associates a device with the destination io device, such as selecting an RS232 port for an alarm panel, 
-- where the RS232 is proxied by a socket, or (b) because the configuration settings for the device already include an IP address and port.
--
-- There is no 'function: close'.

local function open (device, ip, port)
  local dev, sock, devNo = get_dev_and_socket (device)  
  
  local function incoming (sock)
    local data, err = sock: receive "*l"        -- get data
    if data then
      _log (("bytes received: %d, status: %s"): format ((#data or 0), err or "OK"), "luup.io.incoming")
      local ok, msg = scheduler.context_switch (devNo, dev.io.incoming, devNo, data) 
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
      ok, msg = sock:connect (ip, port) 
    end
    _log ("connecting to " .. ip .. ':' .. port, "luup.io.open")
    if ok then
      if dev.io.incoming and not dev.io.intercept then
        _log "connect OK"
        scheduler.socket_watch (sock, incoming)
      end
      dev.io.socket = sock 
    else
      _log ("connect FAIL: " .. (msg or '?'))
    end
    return scheduler.state.Done
  end

  if dev and not sock then
    local _,_, jobNo = scheduler.run_job ({run = connect}, nil, devNo)   -- schedule for later 
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
  local status, msg 
  local dev, sock = get_dev_and_socket (device)  
  if dev and sock then
    local _, tx, err = socket.select (nil, {sock}, 5)         -- 5 second timeout if not ready
    if err then 
      _log ("error: " .. err, "luup.io.write") 
    else
      status, msg = sock: send (data..'\n')        -- send the message
      _log (("bytes sent: %d, status: %s"): format (status or 0, msg or "OK"), "luup.io.write") 
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
  local dev, sock = get_dev_and_socket (device)  
  if sock then scheduler.socket_unwatch (sock) end    -- bypass <incoming> processing
  dev.io.intercept = true
end

-- function: read
-- parameters: timeout (number), device (string or number)
-- returns: data (string)
--
-- This reads a block of data from the socket. 
-- You must have called intercept previously so the data is passed. The time unit for timeout is seconds.

local function read (timeout, device)
  local data, msg
  local dev, sock = get_dev_and_socket (device)  
  if dev and sock and dev.io.intercept then
    sock: settimeout (timeout)
    data, msg = sock: receive ()        -- get data
    if not data then _log ("error: " .. (msg or '?'), "luup.io.read") end
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
  intercept     = intercept, 
  is_connected  = is_connected,
  open          = open, 
  read          = read, 
  write         = write, 
}

----




