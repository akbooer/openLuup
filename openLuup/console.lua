#!/usr/bin/env wsapi.cgi

module(..., package.seeall)


ABOUT = {
  NAME          = "console.lua",
  VERSION       = "2017.03.31",
  DESCRIPTION   = "console UI for openLuup",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2017 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-17 AK Booer

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

--  WSAPI Lua implementation

local lfs       = require "lfs"                   -- for backup file listing
local url       = require "socket.url"            -- for url unescape
local luup      = require "openLuup.luup"
local json      = require "openLuup.json"
local scheduler = require "openLuup.scheduler"    -- for job_list, delay_list, etc...
local xml       = require "openLuup.xml"          -- for escape()

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local console_html = {

prefix = [[
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Console</title>
    <style>
      body {font-family:Arial; background:LightGray; }
      
      .dropbtn {
        background-color: Sienna;
        color: white;
        padding: 16px;
        font-size: 16px;
        border: none;
        cursor: pointer;
      }

      .dropdown {
        position: relative;
        display: inline-block;
      }

      .dropdown-content {
        display: none;
        position: absolute;
        background-color: Sienna;
        min-width: 160px;
        border-top:1px solid Gray;
        box-shadow: 0px 8px 16px 0px rgba(0,0,0,0.5);
      }

      .dropdown-content a {
        color: white;
        padding: 12px 16px;
        text-decoration: none;
        display: block;
      }

      .dropdown-content a:hover {background-color: SaddleBrown}

      .dropdown:hover .dropdown-content {
        display: block;
      }

      .dropdown:hover .dropbtn {
        background-color: SaddleBrown;
      }
    </style>
  </head>
    <body>
    
    <div style="background:DarkGrey;">
    
      <div class="dropdown" >
        <img src="https://avatars.githubusercontent.com/u/4962913" alt="X"  
                style="width:60px;height:60px;border:0;vertical-align:middle;">
      </div>

      <div class="dropdown">
        <button class="dropbtn">openLuup</button>
        <div class="dropdown-content">
          <a class="left" href="/console?page=about">About</a>
          <a class="left" href="/console?page=parameters">Parameters</a>
        </div>
      </div>

      <div class="dropdown">
        <button class="dropbtn">Scheduler</button>
        <div class="dropdown-content">
          <a class="left" href="/console?page=jobs">Jobs</a>
          <a class="left" href="/console?page=delays">Delays</a>
          <a class="left" href="/console?page=watches">Watches</a>
          <a class="left" href="/console?page=startup">Startup Jobs</a>
        </div>
      </div>

      <div class="dropdown">
        <button class="dropbtn">Logs</button>
        <div class="dropdown-content">
          <a class="left" href="/console?page=log">Log</a>
          <a class="left" href="/console?page=log&version=1">Log.1</a>
          <a class="left" href="/console?page=log&version=2">Log.2</a>
          <a class="left" href="/console?page=log&version=3">Log.3</a>
          <a class="left" href="/console?page=log&version=4">Log.4</a>
          <a class="left" href="/console?page=log&version=5">Log.5</a>
          <a class="left" href="/console?page=log&version=startup">Startup Log</a>
        </div>
      </div>

      <div class="dropdown">
        <button class="dropbtn">Backups</button>
        <div class="dropdown-content">
          <a class="left" href="/console?page=backups">Files</a>
        </div>
      </div>
    </div>
    <div style="overflow:scroll;">
    <pre>
]],
--     <div style="overflow:scroll; height:500px;">

  postfix = [[
    </pre>
    </div>

  </body>
</html>

]]
}

local state =  {[-1] = "No Job", [0] = "Wait", "Run", "Error", "Abort", "Done", "Wait", "Requeue", "Pending"} 
local line = "%20s  %8s  %8s  %s %s"
local date = "%Y-%m-%d %H:%M:%S"


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

  local lines     -- print buffer
  local function print (a,b)
    local fmt = "%5s %s \n"
    lines[#lines+1] = fmt: format (a, b or '')
  end

  local job_list = scheduler.job_list
  local startup_list = scheduler.startup_list
  local delay_list = scheduler.delay_list ()

  local function joblist (job_list)
    local jlist = {}
    for _,b in pairs (job_list) do
      jlist[#jlist+1] = {
        t = b.expiry,
        l = line: format (os.date (date, b.expiry + 0.5), b.devNo or "system", 
                            state[b.status] or '?', b.type or '?', b.notes or '')
      }
    end
    return jlist
  end

  local function watchlist ()
    local W = {}
    local line = "%5s   :watch   %s (%s.%s.%s)"
    local function isW (w, d,s,v)
      if next (w.watchers) then
        for _, what in ipairs (w.watchers) do
          W[#W+1] = line:format (what.devNo, what.name or '?', d,s or '*',v or '*')
        end
      end
    end

    for d,D in pairs (luup.devices) do
      isW (D, d)
      for s,S in pairs (D.services) do
        isW (S, d,s)
        for v,V in pairs (S.variables) do
          isW (V, d,s,v)
        end
      end
    end

    print ("Variable Watches, " .. os.date "%c")
    print ('#', line: format ('dev', 'callback', "device","serviceId","variable"))
    table.sort (W)
    for i,w in ipairs (W) do
      print (i,w)
    end    
  end
  
  local jlist = joblist (job_list)
  local slist = joblist (startup_list)

  local dlist = {}
  local delays = "%4.0fs :callback %s"
  for _,b in pairs (delay_list) do
    local dtype = delays: format (b.delay, b.type or '')
    dlist[#dlist+1] = {
      t = b.time,
      l = line: format (os.date (date, b.time), b.devNo, "Delay", dtype, '')
    }
  end

  local function listit (list, title)
    print (title .. ", " .. os.date "%c")
    table.sort (list, function (a,b) return a.t < b.t end)
    print ('#', (line: format ("date       time    ", "device", "status","info", '')))
    for i,x in ipairs (list) do print (i, x.l) end
    print ''
  end

  local function printlog (p)
    local name = luup.attr_get "openLuup.Logfile.Name" or "LuaUPnP.log"
    local ver = p.version
    if ver then
      if ver == "startup" then
        name = "logs/LuaUPnP_startup.log"
      else
        name = table.concat {name, '.', ver}
      end
    end
    local f = io.open (name)
    if f then
      local x = f:read "*a"
      f: close()
      print (xml.escape (x))       -- thanks @a-lurker
    end
  end
  
  local function backups (p)
    local dir = luup.attr_get "openLuup.Backup.Directory" or "backup/"
    print ("Backup directory: ", dir)
    print ''
    local pattern = "backup%.openLuup%-%w+%-([%d%-]+)%.?%w*"
    local files = {}
    for f in lfs.dir (dir) do
      local date = f: match (pattern)
      if date then
        local attr = lfs.attributes (dir .. f) or {}
        local size = tostring (math.floor (((attr.size or 0) + 500) / 1e3))
        files[#files+1] = {date = date, name = f, size = size}
      end
    end
    table.sort (files, function (a,b) return a.date > b.date end)       -- newest to oldest
    local list = "%-12s %4s   %s"
    print (list:format ("yyyy-mm-dd", "(kB)", "filename"))
    for _,f in ipairs (files) do 
      print (list:format (f.date, f.size, f.name)) 
    end
  end
  
  
  local pages = {
    about   = function () for a,b in pairs (ABOUT) do print (a .. ' : ' .. b) end end,
    backups = backups,
    delays  = function () listit (dlist, "Delayed Callbacks") end,
    jobs    = function () listit (jlist, "Scheduled Jobs") end,
    log     = printlog,
    startup = function () listit (slist, "Startup Jobs") end,
    watches = watchlist,
    
    parameters = function ()
      local info = luup.attr_get "openLuup"
      local p = json.encode (info or {})
      print (p or "--- none ---")
    end,
  }

  
  -- unpack the parameters and read the data
  local p = {}
  for a,b in (wsapi_env.QUERY_STRING or ''): gmatch "([^=]+)=([^&]*)&?" do
    p[a] = url.unescape (b)
  end
  
  lines = {console_html.prefix}
  local status = 200
  local headers = {}
  
  local page = p.page or ''
--  if page then
    do (pages[page] or function () end) (p) end
--    headers["Content-Type"] = "text/plain"
--  else
--    lines = {console_html}
    headers["Content-Type"] = "text/html"
--  end
  print (console_html.postfix)
  local return_content = table.concat (lines)

  
  local function iterator ()     -- one-shot iterator, returns content, then nil
    local x = return_content
    return_content = nil 
    return x
  end

  return status, headers, iterator
end

-----
