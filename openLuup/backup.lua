#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "backup.sh",
  VERSION       = "2018.07.12",
  DESCRIPTION   = "user_data backup script /etc/cmh-ludl/cgi-bin/cmh/backup.sh",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
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

local DIRECTORY_DEFAULT = "backup"      -- default backup directory

-- WSAPI Lua implementation of backup.sh
-- backup written to ./backups/backup.openLuup-AccessPt-YYYYY-MM-DD

-- 2016.12.10   initial version
-- 2016.06.30   use new compression module to reduce backup file size.
-- 2016.07.12   return HTML page with download link
-- 2016.07.17   add title to HTML page
-- 2016.10.27   changed formatting of backup message to handle fractional file sizes
-- 2016.12.10   use directory path from openLuuup system attribute

-- 2018.07.12   add &retrieve=filename option (for console page)


local userdata  = require "openLuup.userdata"
local compress  = require "openLuup.compression"
local wsapi     = require "openLuup.wsapi"      -- for the require library methods
local lfs       = require "lfs"

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
  
  local DIRECTORY = (luup.attr_get "openLuup.Backup.Directory") or DIRECTORY_DEFAULT
  lfs.mkdir (DIRECTORY)
   
  local function backup ()
    local PK = userdata.attributes.PK_AccessPoint or "AccessPt"
    local DATE = os.date "%Y-%m-%d" or "0000-00-00"
    local fmt = "%s/backup.openLuup-%s-%s.lzap"
    local fname = fmt: format (DIRECTORY: gsub('/$',''), PK, DATE)  
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
    return status, headers, return_content
  end
  
  
  -- retrieve the contents of a backup file, uncompressing if necessary
  local function retrieveFile (file)
    local headers = {["Content-Type"] = "text/plain"}
    local fname = table.concat {DIRECTORY: gsub('/$',''), '/', file}
    local f, err = io.open (fname, 'rb')
    if not f then return  404, headers, err or "Unknown error opening file" end
    
    local code = f: read "*a"
    f: close ()
    
    if file: match "%.lzap$" then                       -- it's a compressed user_data file
      local codec = compress.codec (nil, "LZAP")        -- full-width binary codec with header text
      code = compress.lzap.decode (code, codec)         -- uncompress the file
    end
    
    headers["Content-Type"] = "application/json"
    return 200, headers, code
  end
  
  -----------
  
  local status, headers, return_content
  
    
  local req = wsapi.request.new(wsapi_env)
  local retrieve = req.GET.retrieve     -- &retrieve=filename option

  if retrieve then
    status, headers, return_content = retrieveFile (retrieve)
  else
    status, headers, return_content = backup ()
  end
  
  local function iterator ()     -- one-shot iterator, returns content, then nil
    local x = return_content
    return_content = nil 
    return x
  end

  return status, headers, iterator
end

-----
