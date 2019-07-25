#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "backup.sh",
  VERSION       = "2018.07.28",
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
-- 2018.07.28   use wsapi.response library

-- 2019.07.17   use new HTML factory method


local userdata  = require "openLuup.userdata"
local compress  = require "openLuup.compression"
local wsapi     = require "openLuup.wsapi"      -- for the require and response library methods
local lfs       = require "lfs"
local xml       = require "openLuup.xml"


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
  
  local req = wsapi.request.new(wsapi_env)
  local res = wsapi.response.new ()

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
    
    local h = xml.createHTMLDocument "Backup"
    if ok then 
      msg = ("%0.0f kb compressed to %0.0f kb (%0.1f:1)") : format (ok, small, ok/small)
      h.body: appendChild {
        h.div {
          "backup completed: ", h.p (msg),
          "written to ", h.b (fname),
          h.p {h.a {href="../../".. fname, download=fname, type="application/octet-stream", "DOWNLOAD"}}}
      }
    else
      res.status = 500
      h.body: appendChild {h.div {"backup failed: ", msg} }
    end
    _log (msg)
    res.content_type = "text/html"
    res: write (tostring (h))
  end
  
  -- retrieve the contents of a backup file, uncompressing if necessary
  local function retrieveFile (file)
    local fname = table.concat {DIRECTORY: gsub('/$',''), '/', file}
    local f, err = io.open (fname, 'rb')
    if f then 
      local code = f: read "*a"
      f: close ()
      
      if file: match "%.lzap$" then                       -- it's a compressed user_data file
        local codec = compress.codec (nil, "LZAP")        -- full-width binary codec with header text
        code = compress.lzap.decode (code, codec)         -- uncompress the file
      end
      
      res: write (code)
      res.content_type = "application/json"
    else
      res.status = 404
      res: write (err or "Unknown error opening file")
    end
  end
  
  -----------
  
  local retrieve = req.GET.retrieve     -- &retrieve=filename option

  if retrieve then
    retrieveFile (retrieve)
  else
    backup ()
  end

  return res: finish ()
end

-----
