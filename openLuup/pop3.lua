local ABOUT = {
  NAME          = "openLuup.pop3",
  VERSION       = "2018.04.23",
  DESCRIPTION   = "POP3 server",
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
-- POP3 Post Office Protocol server
--
-- This is a complete implementation of a POP3 server
-- which handles parallel client sessions and multiple accounts.
--
-- See:
--  https://tools.ietf.org/html/rfc1939

-- 2018.03.28  derived from SMTP and using new core server functions in openLuup.io


local logs      = require "openLuup.logs"
local tables    = require "openLuup.servertables"     -- for myIP
local ioutil    = require "openLuup.io"               -- for core server functions

local lfs  = require "lfs"
local mime = require "mime"       -- for base64 encoding of uidl

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)


-----------
--
-- Mailbox object and methods
--


-- returns a mailbox object operating on the given folder
-- messages have a .msg extension
-- all mailbox methods should be called with colon syntax, eg. mailbox:status()
local function mailbox (folder)
  local messages = {}
  
  -- clear message directory to avoid further operations with this object
  local function close () 
    messages = {} 
  end
  
  -- overall status of mailbox
  -- returns total number of messages and total size
  local function status ()
    local n = 0
    local total = 0
    for _, msg in ipairs (messages) do
      if not msg.delete then
        n = n + 1
        total = total + msg.size
      end
    end
    return n, total
  end
  
  --  From RFC 1939: 
  --    The unique-id of a message is an arbitrary server-determined string, 
  --    consisting of one to 70 characters in the range 0x21 to 0x7E, 
  --    which uniquely identifies a message within a maildrop and which persists across sessions. 
  --    
  --    My fairly arbitrary choice is to use base64 encoding of the file name
  --  
  -- return the 'scan listing' of message i (if not deleted)
  -- returns: message number, message size, unique-id, timestamp
  local function list (_, i)
    local msg = messages[i]
    if msg and not msg.delete then
      local uid = mime.b64(msg.name)                              -- unique identifier
      local timestamp = tonumber (msg.name: match "^%d+") or 0    -- timestamp (from name)
      return i, msg.size, uid, timestamp
    end
  end
  
  -- scan() - returns iterator for non-deleted messages
  local function scan ()
    local function loop (n, i)    -- stateless iterator
      while i < n do 
        i = i + 1
        local _, size, uidl, timestamp = list(i, i)  -- (dummy first parameter for list call
        if size then return i, size, uidl, timestamp end  -- else try next message
      end
    end
    return loop, #messages, 0
  end
  
  -- retrieve() - return the whole of message i as a list of lines
  local function retrieve (_, i)
    local lines
    local msg = messages[i]
    if msg and not msg.delete then
      lines = {}
      for line in io.lines (folder .. msg.name) do
        lines[#lines+1] = line
      end
    end
    return lines
  end
  
  -- delete() - return message number, if successfully marked for delete
  local function delete (_, i)
    local msg = messages[i]
    if msg and not msg.delete then
      msg.delete = true
      return i
    end
  end
  
  -- reset() - undelete all messages
  local function reset ()
    for _, msg in ipairs (messages) do
      msg.delete = nil
    end
  end
  
  -- this is the naughty one that actually deletes message files.
  -- action should be "delete" to make it happen
  -- returns number of messages actually deleted
  local function update (_, action)
    local n = 0
    local yes = action and (action: lower() == "delete")
    for _, msg in ipairs (messages) do
      if msg.delete then
        if yes then
          n = n + 1
          os.remove (folder .. msg.name)
--        else
--          print ("would have deleted: " .. folder .. msg.name)
        end
      end
    end
    close ()    -- don't do that again this session!
    return n
  end
    
  -- write (data)
  -- saves a message to the mailbox
  local function write (_, data)
    local id
    local name = tostring(os.time()): gsub("%.","_")    -- TODO: higher accuracy than 1 sec?
    local fname = table.concat {folder, name, ".msg"}
    local f, err = io.open (fname, 'wb')
    if f then
      for _,line in ipairs (data) do
        f:write (line .. '\n')
      end
      f: close ()
      id = name
    end
    return id, err   -- return msg id if ok, or nil and error message if failure
  end
  
  -- open()
  -- create a snapshot of the directory for use by other methods
  for name in lfs.dir (folder) do
    if name: match "%.msg$" then
      local a = lfs.attributes (folder .. name)
      messages[#messages+1] = {name = name, size = a.size}
    end
  end
  table.sort (messages, function (a,b) return a.name < b.name end)
  
  return {
    close     = close,
    delete    = delete,
    reset     = reset,
    retrieve  = retrieve,
    list      = list,
    scan      = scan,
    status    = status,
    update    = update,
    write     = write,
  }
  
end

-----------
--
-- POP server
--

-- authorized maibox accounts
local accounts = {}     -- table of authorized accounts

local iprequests = {}  -- connection statistics for console page

local popVersion        -- for greeting banner line
do
  local y,m,d = ABOUT.VERSION:match "(%d+)%D+(%d+)%D+(%d+)"
  local version = ("v%d.%d.%d"): format (y%2000,m,d)
  popVersion = ("%s %s"): format (ABOUT.NAME, version)
end

local function start (config)

  -- simple responses
  local OK  = "+OK "
  local ERR = "-ERR "

  -- transaction states
  local authorization = "authorization"
  local transaction   = "transaction"
  local update        = "update"
  

  -- POP3 servlet, called for each new client socket
  
  local function POP3servlet (client)
    local state             -- current transaction state of the client
    local maildrop          -- mailbox object for use in transaction and update states
    local user, pass        -- client username and password
    
    local function poplog (msg) _log   (table.concat {msg, ' ', tostring(client)}) end
    local function popdbg (msg) _debug (table.concat {msg, ' ', tostring(client)}) end
    local _log   = poplog
    local _debug = popdbg
    
    -- POP3 Authorization state commands
    
    local function USER (_, msg)
      user = msg: match "%S+"
      return OK
    end

    local function PASS (_, msg)
      pass = msg: match "%S+"
      if maildrop then maildrop: close () end
      if not accounts[user] then return ERR end
      maildrop = mailbox (accounts[user])
      return OK, transaction    -- authorization completed, move to transaction state
    end

    local function APOP (_, auth)
      user, pass = auth: match "(%S+)%s+(%S+)"
      return PASS (_, pass or '')
    end

    local function QUIT ()
      return OK, update
    end

    -- POP3 Transaction state commands

    local function STAT ()
      local Nfiles, Nbytes = maildrop: status()
      if Nfiles and Nbytes then  
        return table.concat {OK, Nfiles, ' ', Nbytes}
      end
    end

    -- generate scan listing or uidls
    -- attr is 1 (size) or 2 (unique-id), depending on application
    local function info (msg, attr)
      local reply
      local function select (...) return ({...})[attr] end
      local i = tonumber(msg)
      if i then                                   -- looking for a particular message...
        local _, size, name = maildrop: list(i)
        if size then
          reply = table.concat {OK, i, ' ', select(size, name)}  -- OK, return the message number and attr
        else
          reply = ERR                             -- oops, didn't find it (or was marked for delete)
        end
      else                                        -- return complete listing...
        reply = {OK}
        for i,size,name in maildrop:scan() do
          reply[#reply+1] = table.concat {i, ' ', select(size, name)}
        end
        reply[#reply+1] = '.'                     -- add termination character
        reply = table.concat (reply, '\r\n')
      end
      return reply
    end

    -- generate scan listing
    local function LIST (_, msg)
      return info (msg, 1)        -- size is attribute #1 in scan listing
    end

    -- generate uidl listing
    local function UIDL (_, msg)
      return info (msg, 2)        -- uidl is attribute #2 in scan listing
    end

    -- retrieve a message
    local function RETR (_, i)
      local reply
      local msg = maildrop: retrieve(tonumber (i))
      if msg then
        msg[1] = table.concat {OK, '\r\n', msg[1]}  -- add initial positive response
        for i, line in ipairs (msg) do
          if line:sub(1,1) == '.' then
            msg[i] = '.' .. msg[i]                  -- byte-stuff termination character, if necessary
          end
        end
        msg[#msg+1] = '.'                           -- add termination character
        reply = table.concat (msg, '\r\n')
      else
        reply = ERR
      end
      return reply
    end

    -- get the first part of a message
    local function TOP (_, mn)
      local reply
      local lines, inc = 0,0
      local i,N = mn:match "%s*(%d+)%s*(%d+)"
      N = tonumber (N)
      local top = {}
      local msg = maildrop: retrieve(tonumber (i))
      if msg and N then
        msg[1] = table.concat {OK, '\r\n', msg[1]}  -- add initial positive response
        for i, line in ipairs (msg) do
          lines = lines + inc
          if #line == 0 then inc = 1 end            -- start counting body lines when just <CRLF>
          if line:sub(1,1) == '.' then
            top[i] = '.' .. line                    -- byte-stuff termination character, if necessary
          else
            top[i] = msg[i]
          end
          if lines == N then break end              -- bail out when line count reached
        end
        top[#top+1] = '.'                           -- add termination character
        reply = table.concat (top, '\r\n')
      else
        reply = ERR
      end
      return reply
    end

    -- mark for deletion
    local function DELE (_, i)
      local reply
      local ok = maildrop: delete(tonumber (i))
      if ok then
        reply = OK
      else
        reply = ERR
      end
      return reply
    end

    local function NOOP ()
      return OK
    end

    -- clear flags marking messages for deletion
    local function RSET ()
      maildrop: reset ()
      return OK
    end

    local function unknown (x)
      return ERR .. "unknown command " .. x: upper()
    end

-- From RFC-1939, section 3. Basic Operation
--   "A POP3 session progresses through a number of states during its
--   lifetime.  Once the TCP connection has been opened and the POP3
--   server has sent the greeting, the session enters the AUTHORIZATION
--   state.  In this state, the client must identify itself to the POP3
--   server.  Once the client has successfully done this, the server
--   acquires resources associated with the client's maildrop, and the
--   session enters the TRANSACTION state.  In this state, the client
--   requests actions on the part of the POP3 server."
    local action = {
        authorization = {user=USER, pass=PASS, apop=APOP, quit=QUIT},
        transaction = {stat=STAT, list=LIST, uidl=UIDL, top = TOP, retr=RETR, 
                          dele=DELE, noop=NOOP, rset=RSET, quit=QUIT},
        update = {},
      }
--   "When the client has issued the QUIT command, the session enters the UPDATE state.  
--   In this state, the POP3 server releases any resources acquired during
--   the TRANSACTION state and says goodbye.  The TCP connection is then closed."


    -- incoming() is called by the io.server when there is data to read
    local function incoming ()
      local line, err = client: receive()
      local cmd, params = (line or ''): match "^(%a+)%s*(.-)$"
      if not err and cmd then
        _debug (line)
        cmd = (cmd or ''): lower()
        
        local dispatch = action[state][cmd] or unknown
        local response, newstate = dispatch (cmd, params)
        
        local msg = response or ERR
        _debug (msg)
        client: send (msg .. '\r\n')
        
        if newstate == update then 
          if state == transaction then  -- only update mailbox from transaction state,
            local n = maildrop: update "delete"   -- delete files marked for delete
            if n > 0 then _log (n .. " messages deleted") end
          end
          client: close() 
        end
        
        state = newstate or state
        
      else
        client: close ("read error: " ..  (err or "non-ASCII request"))    --eg. timeout
      end
    end
    
  
    -- servlet()
  
    -- initial greeting contains special syntax timestamp, see RFC 1939 APOP
    local greeting = "%s <%s.%s@%s>"
    local unique = tostring {}: match "0x(.+)"
    local banner = greeting: format (popVersion, unique, os.time(), tables.myIP)

    _log (banner)
    _debug (banner)
    state = authorization
    client: send (OK .. banner .. '\r\n')
    
    return incoming   -- callback for incoming messages
  end

  
  -- start()
  
  local default_accounts = {
      mail    = "mail/",          -- generic email
      events  = "events/",        -- notification events
    }
  for name, folder in pairs (config.accounts or default_accounts) do
        accounts[name] = folder
  end
  
  -- returned server object has stop method, but we'll not be using it
  return ioutil.server.new {
      port      = config.Port or 11011,                 -- incoming port
      name      = "POP3",                               -- server name
      backlog   = config.Backlog or 32,                 -- queue length
      idletime  = config.CloseIdleSocketAfter or 600,   -- connect timeout
      servlet   = POP3servlet,                          -- our own servlet
      connects  = iprequests,                           -- use our own table for info
    }
  
end


--- return module variables and methods
return {
    ABOUT = ABOUT,
    
    TEST = { },         -- for testing only
    
    -- constants
    myIP = tables.myIP,

    -- variables
    iprequests  = iprequests,
    accounts    = accounts,
    
    -- methods
    start = start,
    
    -- modules
    mailbox = {open = mailbox},    -- allow programmatic manipulation of mailbox folders

}