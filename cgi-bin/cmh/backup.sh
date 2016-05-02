#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "backup.sh",
  VERSION       = "2016.05.02",
  DESCRIPTION   = "user_data backup script /etc/cmh-ludl/cgi-bin/cmh/backup.sh",
  AUTHOR        = "@akbooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

local DIRECTORY = "backup"      -- change this is you want to backup elsewhere

-- WSAPI Lua implementation of backup.sh
-- backup written to ./backups/backup.openLuup-AccessPt-YYYYY-MM-DD

local userdata = require "openLuup.userdata"
local lfs = require "lfs"

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.


-- global entry point called by WSAPI connector

--[[

The environment is a Lua table containing the CGI metavariables (at minimum the RFC3875 ones) plus any 
server-specific metainformation. It also contains an input field, a stream for the request's data, 
and an error field, a stream for the server's error log. 

The input field answers to the read([n]) method, where n is the number
of bytes you want to read (or nil if you want the whole input). 

The error field answers to the write(...) method.

return values: the HTTP status code, a table with headers, and the output iterator. 

--]]

function run (wsapi_env)
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax
  
  lfs.mkdir (DIRECTORY)
   
  local PK = userdata.attributes.PK_AccessPoint or "AccessPt"
  local DATE = os.date "%Y-%m-%d" or "0000-00-00"
  local fmt = "%s/backup.openLuup-%s-%s"
  local fname = fmt: format (DIRECTORY, PK, DATE)  
  _log ("backing up user_data to " .. fname)
  
  local ok, msg = userdata.save (nil, fname)   -- save current luup environment
  
  local status, return_content
  if ok then 
    status, return_content = 200, "backup completed"
  else
    status, return_content = 500, "backup failed: " .. msg
  end
  _log (return_content)
  
  local headers = {["Content-Type"] = "text/plain"}
  
  local function iterator ()     -- one-shot iterator, returns content, then nil
    local x = return_content
    return_content = nil 
    return x
  end

  return status, headers, iterator
end

-----
