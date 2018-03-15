local ABOUT = {
  NAME          = "openLuup.smtp",
  VERSION       = "2018.03.15",
  DESCRIPTION   = "SMTP server and client",
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
-- SMTP (Simple Mail Transfer Protocol) server and client
--

-- 2018.03.05   initial implementation, extracted from HTTP server
-- 2018.03.14   first release
-- 2018.03.15   remove lowercase folding of addresses.  Add Received header and timestamp.


local socket    = require "socket"
local smtp      = require "socket.smtp"

local logs      = require "openLuup.logs"
local scheduler = require "openLuup.scheduler"
local tables    = require "openLuup.servertables"
local timers    = require "openLuup.timers"         -- for rfc_5322_date()

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

-- CONFIGURATION DEFAULTS

-- RFC 821 requires at least 5 minutes and a queue of 100...
local CLOSE_IDLE_SOCKET_AFTER   = 300         -- number of seconds idle after which to close socket
local BACKLOG = 100

--[[

See:
  https://tools.ietf.org/html/rfc821
  https://tools.ietf.org/html/rfc1869#section-4.5
  https://tools.ietf.org/html/rfc5321

Fmom RFC 821:

APPENDIX E: Theory of Reply Codes

The three digits of the reply each have a special significance. The first digit denotes whether the response is good, bad or incomplete. An unsophisticated sender-SMTP will be able to determine its next action (proceed as planned, redo, retrench, etc.) by simply examining this first digit. A sender-SMTP that wants to know approximately what kind of error occurred (e.g., mail system error, command syntax error) may examine the second digit, reserving the third digit for the finest gradation of information.

There are five values for the first digit of the reply code:

1yz Positive Preliminary - Command accepted [Note: SMTP does not have any commands that allow this type of reply]
2yz Positive Completion - The requested action has been successfully completed.
3yz Positive Intermediate - The command has been accepted, but the requested action is being held in abeyance.
4yz Transient Negative Completion - The command was not accepted and the requested action did not occur.
5yz Permanent Negative Completion - The command was not accepted and the requested action did not occur.

The second digit encodes responses in specific categories:

x0z Syntax - syntax errors.
x1z Information - replies to requests for information, such as status or help.
x2z Connections - replies referring to the transmission channel.
x3z Unspecified as yet.
x4z Unspecified as yet.
x5z Mail system - indicate the status of the receiver mail system.

The third digit gives a finer gradation of meaning in each category specified by the second digit. The list of replies illustrates this. Each reply text is recommended rather than mandatory, and may even change according to the command with which it is associated. On the other hand, the reply codes must strictly follow the specifications in this section. Receiver implementations should not invent new codes for slightly different situations from the ones described here, but rather adapt codes already defined.

--]]

-- reply codes
local function code (n, text) 
  local msg = tables.smtp_codes[n] or '%s'
  msg = msg: format (text)
  return table.concat {n, ' ', msg}
end

local OK = code(250)

local myIP = tables.myIP

local myDomain = ("[%s] %s %s"): format (myIP, ABOUT.NAME, ABOUT.VERSION)

local iprequests = {}       -- log incoming request IPs

local destinations = {}     -- table of registered email addresses (shared across all server instances)

local blacklist = {}      -- table of blacklisted senders


-- register a listener for the incoming mail
local function register_handler (callback, email)
  if not destinations[email] then                    -- only allow one unique reader for this email address
    destinations[email] = {
        callback = callback, 
        devNo = scheduler.current_device (),
        email = email,
      }
    return 1
  end
  return nil, "access to this email address not allowed"
end

-- use asynchronous job to deliver the mail to the destination(s)
local function deliver_mail (state)
  local message = {               -- copy the current state
      domain = state.domain,
      reverse_path = state.reverse_path,
      forward_path = state.forward_path,
      data = state.data,
    }
  
  local function job ()
    _debug "Mail Delivery job"
    local function deliver (info)
      if info then 
        local ok, err = scheduler.context_switch (info.devNo, info.callback, info.email, message)
        if ok then
          _log (table.concat {"EMAIL delivered to handler for: ", info.email})
        else
          _log (table.concat {"ERROR delivering email to handler for: ", info.email, " : ", err})
        end
      end
    end
    -- email recipients
    for i, recipient in ipairs (message.forward_path) do
      _debug (" Recipient #" ..i, recipient)
      deliver (destinations[recipient])
    end
    -- IP listener
    local ip = state.domain: match "%[(%d+%.%d+%.%d+%.%d+)%]"
    if destinations[ip] then
      _debug (" IP listener", ip)
      deliver (destinations[ip])
    end
    return scheduler.state.Done, 0
  end
  
  _debug "Deliver Mail:"
  _debug (" Data lines:", #(message.data or {}))
  _debug (" Sender:", message.reverse_path)
  scheduler.run_job {job = job}
end


--
--
--

local function new_client (sock)
  local expiry
  local ip        -- client's IP address
  
  -- close the socket, stop watching it, and expire the job
  local function close_client (msg)
    local txt = table.concat {msg, ' ', tostring(sock)}
    _log (txt)
    sock: close ()                                -- it may be closed already
    scheduler.socket_unwatch (sock)               -- stop watching for incoming
    expiry = 0
  end

  local state = {}   -- the current state of the conversation  
  
  local function send_client (msg) 
    _debug ("SEND:", msg)
    return sock:send (table.concat {msg, '\r\n'}) 
  end
  
  -- return this client to quiescent state
  local function reset_client ()
    state.domain        = nil
    state.reverse_path  = nil
    state.forward_path  = {}
    state.data          = {}
  end
  
  -- helo and ehlo initialisation
  local function helo (domain)
    reset_client ()
    state.domain = ("%s [%s]"): format (domain, ip)
    send_client (OK) 
  end
  
  -- sender
  local function mail (from) 
    local reply
    local sender = from: match "[Ff][Rr][Oo][Mm]:.-([^@<%s]+@[%w-%.]+).-$"
    if not sender then 
      reply = code(501, tostring (from))    -- could be nil
    else
      if blacklist[sender] then
        reply = code (552)          -- rejected
      else
        state.reverse_path = sender
        reply = OK
      end
    end
    send_client (reply)
  end
  
  -- receiver
  local function rcpt (to) 
    local receiver = to: match "^[Tt][Oo]:.-([^@<%s]+@[%w-%.]+).-$"
    if state.reverse_path and destinations[receiver] then
      local r = state.forward_path 
      r[#r+1] = receiver
      send_client (OK) 
    else
      send_client (code(550, receiver or '?'))       -- No such user
    end
  end
  
  -- data iterator (compatible with ltn12 source)
  local function next_data ()
    local line, err = sock: receive ()
    if not line then
      close_client ("error during SMTP DATA transfer: " .. tostring(err))
    else
      line = (line ~= '.') and line: gsub ("^%.%.", "%.") or nil   -- data transparency handling
    end
    return line, err
  end

  -- message data
  local function data ()
    send_client (code (354))
    local errmsg
    local data = state.data
    data[1] = ("Received: from %s"): format (state.domain)
    data[2] = (" by %s;"): format (myDomain)                      -- TODO: syntax not correct
    data[3] = (" %s"): format (timers.rfc_5322_date())            -- timestamp
    data[4] = nil                                                 -- ensure no further data, yet
    for line, err in next_data do
      errmsg = err
      data[#data+1] = line        -- add to the data buffer
    end
    if not errmsg then            -- otherwise we closed the socket anyway
      send_client (OK) 
      deliver_mail (state)
      end
  end 

  -- final exit
  local function quit ()
    send_client (code (221, myDomain))
    close_client "SMTP QUIT received" 
  end
  
  -- unknown
  local function not_implemented (d)
    send_client (code(502, d or '?'))
  end
    
-- From RFC-5321, section 4.5.1 Minimum Implementation
-- In order to make SMTP workable, the following minimum implementation
-- MUST be provided by all receivers.  The following commands MUST be
-- supported to conform to this specification:
    local dispatch = {
      EHLO = helo,    -- extended HELO functionality the same as HELO, because it has no extensions!
      HELO = helo,
      MAIL = mail,
      RCPT = rcpt,
      DATA = data,
      RSET = function () reset_client() ; send_client (OK) end,
      NOOP = function () send_client (OK) end,
      QUIT = quit, 
      VRFY = function () send_client (code(252)) end,   -- "unable to verify"
    }
  
  -- incoming() is called by the scheduler when there is data to read
  local function incoming ()
    local line, err = sock: receive()         -- read the request line
    if not err then  
--      _debug (#line, line)
      local cmd, params = line: match "^(%a%a%a%a)%s*(.-)$"
      cmd = (cmd or ''): upper()
      local fct = dispatch[cmd]
      if fct then
        fct (params or '')
      else
        not_implemented (line)
      end
      expiry = socket.gettime () + CLOSE_IDLE_SOCKET_AFTER      -- update socket expiry 
    else
      local msg = "socket closed"
      if err ~= "closed" then 
        msg = "read error: " ..  err    --eg. timeout
      end
      close_client (msg)
    end
  end

  -- run(), preamble to main job
  local function run ()
    reset_client ()
    send_client (code(220, myDomain) )
  end
  
  --  job (devNo, args, job)
  local function job ()     -- TODO: wake and exit job before timeout
    if socket.gettime () > expiry then                    -- close expired connection... 
      close_client "closing client connection"
      return scheduler.state.Done, 0                      -- and exit
    else
      return scheduler.state.WaitingToStart, 5            -- ... checking every 5 seconds
    end
  end
  
  -- new_client ()

  do -- initialisation
    ip = sock:getpeername() or '?'                                            -- who's asking?
    iprequests [ip] = {ip = ip, date = os.time(), mac = "00:00:00:00:00:00"}  --TODO: real MAC address - how?
    local connect = "new SMTP client connection from %s: %s"
    _log (connect:format (ip, tostring(sock)))
  end

  do -- configure the socket
    expiry = socket.gettime () + CLOSE_IDLE_SOCKET_AFTER    -- set initial socket expiry 
    sock:settimeout(nil)                                    -- no socket timeout on read
    sock:setoption ("tcp-nodelay", true)                    -- allow consecutive read/writes
    scheduler.socket_watch (sock, incoming)                 -- start listening for incoming
  end

  do -- run the job
    local _, _, jobNo = scheduler.run_job {run = run, job = job}
    if jobNo and scheduler.job_list[jobNo] then
      local info = "job#%d :SMTP new connection %s"
      scheduler.job_list[jobNo].type = info: format (jobNo, tostring(sock))
    end
  end
end

----
--
-- start (), sets up the HTTP request handler
-- returns list of utility function(s)
-- 
local function start (port, config)
  config = config or {}               -- 2017.03.15 server configuration table
  CLOSE_IDLE_SOCKET_AFTER = config.CloseIdleSocketAfter or CLOSE_IDLE_SOCKET_AFTER
  BACKLOG = config.Backlog or BACKLOG
  port = tostring(port)
  
  local server, err = socket.bind ('*', port, BACKLOG) 
   
  -- new client connection
  local function server_incoming (server)
    repeat                                              -- could be multiple requests
      local sock = server:accept()
      if sock then new_client (sock) end
    until not sock
  end

  local function stop()
    _log (table.concat {"stopping SMTP server on port: ", port, ' ', tostring(server)})
    server: close()
  end

  -- start(), create server and start listening
  local mod, msg
  if server then 
    server:settimeout (0)                                       -- don't block 
    scheduler.socket_watch (server, server_incoming)            -- start watching for incoming
    msg = table.concat {"starting SMTP server on port: ", port, ' ', tostring(server)}
    mod = {stop = stop}
  else
    msg = "error starting SMTP server: " .. tostring(err)
  end  
  _log (msg)
  return mod, msg
end

-- receive email for openLuup...
local function local_email (email, message)
  -- EMAIL processing goes here!
  _debug (email)
  if ABOUT.DEBUG then
    local json = require "openLuup.json"
    json.default.max_array_length = 5000
    local f = io.open ("SMTP/data/message.json", 'wb')
    if f then 
      local j,e = json.encode(message)
      f: write (j or e)
      f: close ()
    end
  end
end


do -- init

  register_handler (local_email, "postmaster@openLuup.local")
  register_handler (local_email, "openLuup@openLuup.local")

end

--- return module variables and methods
return {
    ABOUT = ABOUT,
    
    TEST = {          -- for testing only
    },
    
    -- constants
    myIP = myIP,

    -- variables
    iprequests  = iprequests,
    
    --methods
    start = start,
    register_handler = register_handler,              -- callback for completed mail messages
  }

-----
