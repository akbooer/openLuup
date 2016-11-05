#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "backup.sh",
  VERSION       = "2016.10.27",
  DESCRIPTION   = "user_data backup script /etc/cmh-ludl/cgi-bin/cmh/backup.sh",
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

local DIRECTORY = "backup"      -- change this is you want to backup elsewhere

-- WSAPI Lua implementation of backup.sh
-- backup written to ./backups/backup.openLuup-AccessPt-YYYYY-MM-DD

-- 2016.06.30   use new compression module to reduce backup file size.
-- 2016.07.12   return HTML page with download link
-- 2016.07.17   add title to HTML page
-- 2016.10.27   changed formatting of backup message to handle fractional file sizes

local userdata = require "openLuup.userdata"
local compress = require "openLuup.compression"
local lfs = require "lfs"

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

-- template for HTML return page
local html = [[
<!DOCTYPE html>
<html>
<head><title>Backup</title></head>
<body>
backup completed: <p>%s<p>
and written to <strong>%s</strong><p>
<a href=../../%s download type="application/octet-stream">DOWNLOAD</a><p>
</body>
</html>
]]

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
  local fmt = "%s/backup.openLuup-%s-%s.lzap"
  local fname = fmt: format (DIRECTORY, PK, DATE)  
  _log ("backing up user_data to " .. fname)
  
  local ok, msg = userdata.json (nil)   -- save current luup environment
  local small                           -- compressed file
  if ok then 
    local f
    f, msg = io.open (fname, 'wb')
    if f then 
      local codec = compress.codec (nil, "LZAP")  -- full binary codec with header text
      small = compress.lzap.encode (ok, codec)
      f: write (small)
      f: close ()
      ok = #ok / 1000    -- convert to file sizes
      small = #small / 1000
    else
      ok = false
    end
  end
  
  local headers = {["Content-Type"] = "text/plain"}
  local status, return_content
  if ok then 
    msg = ("%0.0f kb compressed to %0.0f kb (%0.1f:1)") : format (ok, small, ok/small)
    local body = html: format (msg, fname, fname)
    headers["Content-Type"] = "text/html"
    status, return_content = 200, body
  else
    status, return_content = 500, "backup failed: " .. msg
  end
  _log (msg)
  
  local function iterator ()     -- one-shot iterator, returns content, then nil
    local x = return_content
    return_content = nil 
    return x
  end

  return status, headers, iterator
end

-----
