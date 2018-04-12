local ABOUT = {
  NAME          = "openLuup.smtp",
  VERSION       = "2018.04.11",
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

-- See:
--  https://tools.ietf.org/html/rfc821                              original SMTP
--  https://tools.ietf.org/html/rfc1869#section-4.5                 SMTP Extensions
--  https://tools.ietf.org/html/rfc5321                             SMTP
--  https://tools.ietf.org/html/draft-murchison-sasl-login-00       AUTH LOGIN
--  https://tools.ietf.org/html/rfc4616                             AUTH PLAIN
--  https://tools.ietf.org/html/rfc3207                             SMTP over TLS
--  http://www.iana.org/assignments/sasl-mechanisms/

-- 2018.03.05   initial implementation, extracted from HTTP server
-- 2018.03.14   first release
-- 2018.03.15   remove lowercase folding of addresses.  Add Received header and timestamp.
-- 2018.03.16   only deliver message header and body, not whole state
-- 2018.03.17   add MIME decoder
-- 2018.03.20   add IP connection and message counts
-- 2018.03.26   add extra error logging, and AUTH LOGIN
-- 2018.04.02   deliver to IP listener before other email handlers for faster triggering
-- 2018.04.10   made quotes around multipart boundary optional
-- 2018.04.11   refactor to use io.server.new()


local smtp      = require "socket.smtp"             -- TODO: add SMTP client code for sending emails
local mime      = require "mime"                    -- only used by mime module, not by smtp server itself

local logs      = require "openLuup.logs"
local scheduler = require "openLuup.scheduler"
local tables    = require "openLuup.servertables"
local timers    = require "openLuup.timers"         -- for rfc_5322_date()
local ioutil    = require "openLuup.io"               -- for core server functions

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)


-----
--
-- Multipurpose Internet Mail Extensions (MIME)
-- see, for example: https://en.wikipedia.org/wiki/MIME
--
--
-- This MIME module is not used at all by the SMTP server, but
-- provided as convenience utilities via both the smtp.mime module, and
-- as a hidden decode method attached to the SMTP data object passed to request handlers
-- thus, in a handler,  message = data: decode() -- will decode into a structure with headers and bodies.
--
-- message = { header={...}, body=... } 
-- for a simple message, a body is a decoded string (from base64 or quoted-printable)
-- for a multipart message, a body is a list of messages (possibly themselves nested multiparts)
-- header is BOTH an ordered list of headers AND an index by header name (wrapped to lower case)


-- decode words if required, else just return original text
local function rfc2047_encoded_words (text)
  local form = "=%?([^%?]+)%?([BQ])%?(.+)%?="     -- see RFC 2047 Encoded Word
  local decode = {B = mime.unb64, Q = mime.unqp}  -- TODO: actually, 'Q' is not quite the same as quoted-printable
  local decoded_text
  for charset, encoding, encoded_text in text: gmatch (form) do
    local _ = charset       -- TODO: really ought to do something with the charset info?
    decoded_text = (decoded_text or '') .. decode [encoding] (encoded_text) 
  end
  return decoded_text or text
end

-- parse and decode headers, adding index to same table as input list
local function decode_headers (header)
  for i,b in ipairs (header) do    -- decode the headers, and index by name
    local name, value = b: match "([^:]+):%s+(.+)"
    if name then
      local decoded = rfc2047_encoded_words (value)
      header[i] = table.concat {name, ": ", decoded}    -- rebuild decoded header
      header[name:lower()] = decoded                    -- fold name to lower case and use it as index
    end
  end
  return header
end

-- decode according to "content-transfer-encoding" header
local function decode_content (body, header)
  local mime_decoder = {
      ["base64"] = mime.unb64,
      ["quoted-printable"] = mime.unqp,
    }
  local function text_decoder (body)
     return table.concat (body, '\r\n')
  end
  local ContentTransferEncoding = header["content-transfer-encoding"]
  _debug ("content-transfer-encoding", ContentTransferEncoding or "--none--")
  local decoder = mime_decoder[ContentTransferEncoding]
  if decoder then
    body = decoder (table.concat (body))    -- TODO: use ltn12 source/filter/sink chain instead?
  else
    body = text_decoder (body)
  end
  return body
end

-- MIME message decoding
local function decode_message (data)

  local nextline do     -- iterator for lines of data
    local i = 0         -- hidden line counter
    nextline = function () i = i + 1; return data[i] end
  end

  -- read and unwrap multiline headers until blank line indicating end
  local function read_headers ()
    local header = {}
    for line in nextline do   -- unwrap the headers
      local spaces, text = line: match "^(%s+)(.+)"
      if spaces then
        header[#header] = table.concat {header[#header], ' ', text }  -- join multiple lines
      else
         header[#header+1] = line
      end
      if #line == 0 then break end
    end
    header[#header] = nil     -- remove last (blank) line
    return header
  end
  
  -- decode_message ()
  local header = decode_headers(read_headers())
  
  local ContentType = header["content-type"] or "text/plain"
  local boundary = ContentType: match 'boundary="?([^"]+)"?'
  local body = {}                     -- body part
  _debug ("Content-Type:", ContentType)
  _debug ("Boundary:", boundary or "--none--")
  if boundary then
    local part = {}                   -- multipart message
    for line in nextline do
      if line: find (boundary, 3, true) then  -- PLAIN match for the boundary pattern
        part[#part+1] = body                  -- save body part (which includes its own headers)
        body = {}
      else
        body[#body+1] = line
      end
    end
    -- now decode each individual part...
    _debug ("#parts:", #part)
    body = {}                         -- throw away last part (if any) after final boundary, and...
    for i = 2,#part do                -- ...ignore first part which is only there for non-mime clients
      body[#body+1] = decode_message (part[i])
    end
  else
    for line in nextline do      -- just a single part      
      body[#body+1] = line
    end
    body = decode_content (body, header)      
  end
  return {body=body, header=header}
end


--[[

  SMTP - Simple Mail Transfer Protocol

Fmom RFC 821:

APPENDIX E: Theory of Reply Codes

The three digits of the reply each have a special significance. The first digit denotes whether the 
response is good, bad or incomplete. An unsophisticated sender-SMTP will be able to determine its next 
action (proceed as planned, redo, retrench, etc.) by simply examining this first digit. A sender-SMTP 
that wants to know approximately what kind of error occurred (e.g., mail system error, command syntax 
error) may examine the second digit, reserving the third digit for the finest gradation of information.

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

The third digit gives a finer gradation of meaning in each category specified by the second digit. The
list of replies illustrates this. Each reply text is recommended rather than mandatory, and may even 
change according to the command with which it is associated. On the other hand, the reply codes must 
strictly follow the specifications in this section. Receiver implementations should not invent new codes 
for slightly different situations from the ones described here, but rather adapt codes already defined.

--]]

local myDomain do 
  local y,m,d = ABOUT.VERSION:match "(%d+)%D+(%d+)%D+(%d+)"
  local version = ("v%d.%d.%d"): format (y%2000,m,d)
  myDomain = ("(%s %s) [%s]"): format (ABOUT.NAME, version, tables.myIP)
end

local iprequests = {}       -- log incoming request IPs

local destinations = {}     -- table of registered email addresses (shared across all server instances)

local blocked = {           -- table of blocked senders
    ["spam@not.wanted.com"] = true,
  }

-- register a listener for the incoming mail
local function register_handler (callback, email)
  if not destinations[email] then                    -- only allow one unique reader for this email address
    destinations[email] = {
        callback = callback, 
        devNo = scheduler.current_device (),
        email = email,
        count = 0,
      }
    return 1
  end
  return nil, "access to this mailbox address not allowed"
end

-- use asynchronous job to deliver the mail to the destination(s)
local function deliver_mail (state)
  
  local function job ()
    _debug "Mail Delivery job"
    local meta = {__index = {decode = decode_message}}  -- provide MIME decoder method...
    local data = setmetatable (state.data, meta)        -- ...as part of the delivered data object
    
    local function deliver (info)
      if info then 
        info.count = info.count + 1                     -- 2018.03.20  increment mailbox message counter
        _log (table.concat {"EMAIL delivery to handler for: ", info.email})
        local ok, err = scheduler.context_switch (info.devNo, info.callback, info.email, data)
        if not ok then
          _log (table.concat {"ERROR delivering email to handler for: ", info.email, " : ", err})
        end
      end
    end
    -- IP listener
    local ip = (state.domain or "[0.0.0.0]"): match "%[(%d+%.%d+%.%d+%.%d+)%]"
    if destinations[ip] then
      _debug (" IP listener", ip)
      deliver (destinations[ip])
    end
    -- email recipients
    for i, recipient in ipairs (state.forward_path) do
      _debug (" Recipient #" ..i, recipient)
      deliver (destinations[recipient])
    end
    return scheduler.state.Done, 0
  end
  
  _debug "Deliver Mail:"
  _debug (" Data lines:", #(state.data or {}))
  _debug (" Sender:", state.reverse_path)
  scheduler.run_job {job = job}
end


-- reply codes
local function code (n, text) 
  local msg = tables.smtp_codes[n] or '%s'
  msg = msg: format (text)
  return table.concat {n, ' ', msg}
end

local OK  = code(250)       -- success
local ERR = code(451)       -- internal error code  

----
--
-- start (), sets up the HTTP request handler
-- 

local function start (config)

  --[[

  TODO: May need to add SSL handling...
  ... what about certificates, etc.?

    client, error = ssl.wrap(client, SSL_params) 
    if not client then
      _log (ip_port .. " SSL wrap error: " .. tostring(error))
      return
    end

    rc, error = client:dohandshake()
    if not rc then
      _log(ip_port .. " SSL handshake error: " .. tostring(error))
      return
    end
   

  --]]


  -- SMTP servlet, called for each new client socket
  
  local function SMTPservlet (client)
    local ip = client.ip        -- client's IP address
    
    local state = {}   -- the current state of the conversation  
    
    local function send_client (msg) 
      _debug ("SEND:", msg)
      return client:send (table.concat {msg, '\r\n'}) 
    end
    
    -- return this client to quiescent state
    local function reset_client ()
      state.domain        = nil
      state.reverse_path  = nil
      state.forward_path  = {}
      state.data          = {}
    end
    
    -- SMTP commands

    -- helo  initialisation
    local function HELO (_, domain)
      reset_client ()
      state.domain = ("(%s) [%s]"): format (domain, ip)
      return OK 
    end
    
    -- ehlo initialisation
    local function EHLO (_, domain)
      reset_client ()
      state.domain = ("(%s) [%s]"): format (domain, ip)
      return "250 AUTH LOGIN" 
    end
    
    -- auth
    local function AUTH (_, method)
      -- see: https://tools.ietf.org/html/draft-murchison-sasl-login-00
      local function LOGIN ()
        send_client "334 VXNlciBOYW1lAA=="    -- "Username:"
        local line, err = client: receive ()
        _debug (line or err)
        send_client "334 UGFzc3dvcmQA"        -- "Password:"
        line, err = client: receive ()
        _debug (line or err)
        return code(235)                      -- Authentication successful
      end
      
      local function not_implemented (x)
        return code(504, x)                   -- unrecognised
      end
      
      local implemented = {login = LOGIN}     -- dispatch list of implemented authorisation protocols
      
      local authorize = implemented[method: lower()] or not_implemented
      
      return authorize()
    end
    
    -- sender
    local function MAIL (_, from) 
      local reply
      local sender = from: match "[Ff][Rr][Oo][Mm]:.-([^@<%s]+@[%w-%.]+).-$"
      if not sender then 
        reply = code(501, tostring (from))    -- could be nil
      else
        if blocked[sender] then
          _log ("blocked sender: " .. sender)
          reply = code (552)          -- rejected
        else
          state.reverse_path = sender
          reply = OK
        end
      end
      return reply
    end
    
    -- receiver
    local function RCPT (_, to) 
      local reply
      local receiver = to: match "^[Tt][Oo]:.-([^@<%s]+@[%w-%.]+).-$"
      if state.reverse_path and 
        (destinations[receiver]  or ABOUT.DEBUG) then -- 2018.03.26  accept any destination in DEBUG mode
        local r = state.forward_path 
        r[#r+1] = receiver
        reply = OK 
      else
        _log ("no such mailbox: " .. receiver)
        reply = code(550, receiver or '?')      -- No such user
      end
      return reply
    end
    
    -- verify (not recommended to implement for security reasons)
    local function VRFY () 
      return code(252)         -- "unable to verify"
    end

    -- data iterator (compatible with ltn12 source)
    local function next_data ()
      local line, err = client: receive ()
      if not line then
        _log ("ERROR during SMTP DATA transfer: " .. tostring(err))
        client: close()
      else
        line = (line ~= '.') and line: gsub ("^%.%.", "%.") or nil   -- data transparency handling
      end
      return line, err
    end

    -- message data
    local function DATA ()
      send_client (code (354))
      local reply, errmsg
      local data = state.data
      data[1] = ("Received: from %s"): format (state.domain)
      data[2] = (" by %s;"): format (myDomain)
      data[3] = (" %s"): format (timers.rfc_5322_date())            -- timestamp
      data[4] = nil                                                 -- ensure no further data, yet
      for line, err in next_data do
        errmsg = err                -- TODO: bail out here if transmission error
        data[#data+1] = line        -- add to the data buffer
      end
      _debug ("#data lines=" .. #data)
      if errmsg then
        reply = ERR -- otherwise we closed the socket anyway
      else
        deliver_mail (state)    -- TODO: move this to dispatcher
        reply = OK 
      end
      return reply
    end 

    local function NOOP ()
      return OK
    end

    -- reset
    local function RSET () 
      reset_client()
      return OK
    end

    -- final exit
    local function QUIT ()
      return code (221, myDomain)
    end
    
    -- unknown
    local function not_implemented (d)
      d = (d or '?'):upper()
      _log ("command not implemented: " .. d)
      return code(502, d)
    end
      
    -- From RFC-5321, section 4.5.1 Minimum Implementation
    -- "In order to make SMTP workable, the following minimum implementation
    -- MUST be provided by all receivers.  The following commands MUST be
    -- supported to conform to this specification:"
    local action = {ehlo = EHLO, helo = HELO, auth = AUTH,
                    mail = MAIL, rcpt = RCPT, vrfy = VRFY, data = DATA,
                    rset = RSET, noop = NOOP, quit = QUIT}
    -- Also see section 7.3.  VRFY, EXPN, and Security:
    --   "As discussed in Section 3.5, individual sites may want to disable
    --   either or both of VRFY or EXPN for security reasons (see below).  As
    --   a corollary to the above, implementations that permit this MUST NOT
    --   appear to have verified addresses that are not, in fact, verified.
    --   If a site disables these commands for security reasons, the SMTP
    --   server MUST return a 252 response, rather than a code that could be
    --   confused with successful or unsuccessful verification."
    
    
    -- incoming() is called by the io.server when there is data to read
    local function incoming ()
      local line, err = client: receive()         -- read the request line
      local cmd, params = (line or ''): match "^(%a%a%a%a)%s*(.-)$"
      if not err and cmd then  
        _debug (line)
        cmd = (cmd or ''): lower()
        
        local fct = action[cmd] or not_implemented
        local response = fct (cmd, params)
        
        local msg = response or ERR
        send_client (msg)
        
        if cmd == "quit" then
          client: close ()
        end
        
      else
        if err ~= "closed" then 
          _log ("read error: " ..  err or "non-ASCII request")    --eg. timeout
        end
        client: close ()
      end
    end

    -- servlet()

    if blocked[ip] then
      -- TODO: close socket
      _log ("closed incoming connection from blocked IP " .. ip)
    else
      _log (myDomain)
      reset_client ()
      send_client (code(220, myDomain))
    end
    
    return incoming   -- callback for incoming messages
  end
  
  
  -- start(), create server and start listening

  -- RFC 821 requires at least 5 minutes idle time, and a queue of 100...
 
  -- returned server object has stop method, but we'll not be using it
  return ioutil.server.new {
      port      = config.Port or 2525,                  -- incoming port
      name      = "SMTP",                               -- server name
      backlog   = config.Backlog or 100,                -- queue length
      idletime  = config.CloseIdleSocketAfter or 300,   -- connect timeout
      servlet   = SMTPservlet,                          -- our own servlet
      connects  = iprequests,                           -- use our own table for info
    }
end


---------------------
--
-- module initialisation
--

-- special email destinations for openLuup...
local function local_email (email, data)
  -- EMAIL processing goes here!
  _debug (email)
  
  if email == "test@openLuup.local" then
    _log ("TO: " .. email)
    for i,line in ipairs(data) do
      _log (line, "openLuup.smtp.test")
      print (i,line)
    end
  end
end


do -- init
  register_handler (local_email, "postmaster@openLuup.local")
  register_handler (local_email, "test@openLuup.local")
end

--- return module variables and methods
return {
    ABOUT = ABOUT,
    
    TEST = { },           -- for testing only
    
    -- constants
    myIP = tables.myIP,

    -- variables
    destinations  = destinations,
    iprequests    = iprequests,
    blocked       = blocked,
    
    -- methods
    start = start,
    register_handler = register_handler,              -- callback for completed mail messages
    
    -- modules
    mime = {
      decode          = decode_message,
      decode_headers  = decode_headers,
      decode_content  = decode_content,
      
      rfc2047_encoded_words = rfc2047_encoded_words,
    },
    
    client = {
      -- TODO: mail client functionality (send, secure_send, ...)
    },
    
  }

-----
