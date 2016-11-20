#!/usr/bin/env wsapi.cgi

module(..., package.seeall)


ABOUT = {
  NAME          = "console.lua",
  VERSION       = "2016.11.19",
  DESCRIPTION   = "console UI for openLuup",
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

--  WSAPI Lua implementation

local url       = require "socket.url"            -- for url unescape
local luup      = require "openLuup.luup"
local scheduler = require "openLuup.scheduler"    -- for job_list, delay_list, etc...


local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local console_html = [[
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>openLuup</title>
    <style> 
    body            {font-family:Arial;  font-size:10pt; background:LightGray; } 
    div             {vertical-align:middle; clear:both; }
    span.blank      {width:60px; float:left; }
    a:hover         {background-color:Brown; }
    a               {width:100px; font-weight:bold; color:White; background-color:RosyBrown; text-align:center; 
                     padding:2px; margin:6px; margin-left:0; float:left; text-decoration:none;}
    a.left          {border-radius:20px; }
    iframe          {border:none; width:100%; background:Gray; }
    #Menu           {margin-left:auto; margin-right:auto; width:80%; }
    #Output         {background:LightSteelBlue; padding:8px; padding-top:0;  width:100%;}
    
    </style>
  </head>
  <body>
    <div id="Menu">
      <a target="Output" class="left" href="/console?page=about">About</a>
      <a target="Output" class="left" href="/console?page=parameters">Parameters</a>
      <a target="Output" class="left" href="/console?page=jobs">Jobs</a>
      <a target="Output" class="left" href="/console?page=delays">Delays</a>
      <a target="Output" class="left" href="/console?page=watches">Watches</a>
      <a target="Output" class="left" href="/console?page=startup">Startup Jobs</a>
    </div>
    <div id="OutputFrame">
      <iframe name="Output" height="400px"> </iframe>
    </div>
  </body>
</html>
]]


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
                            state[b.status] or '?', b.type, b.notes or '')
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
  local delays = "%4.0fs :callback '%s'"
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

  local pages = {
    jobs    = function () listit (jlist, "Scheduled Jobs") end,
    delays  = function () listit (dlist, "Delayed Callbacks") end,
    startup = function () listit (slist, "Startup Jobs") end,
    watches = watchlist,
    about   = function () for a,b in pairs (ABOUT) do print (a .. ' : ' .. b) end end,
    
    parameters = function ()
      local info = luup.attr_get "openLuup"
      for a,b in pairs (info or {}) do
        print (table.concat {a, " : ", tostring(b)} )
      end
    end,
  }

  
  -- unpack the parameters and read the data
  local p = {}
  for a,b in (wsapi_env.QUERY_STRING or ''): gmatch "([^=]+)=([^&]*)&?" do
    p[a] = url.unescape (b)
  end
  
  lines = {}
  local status = 200
  local headers = {}
  
  local page = p.page 
  if page then
    (pages[page] or pages.info) () 
    headers["Content-Type"] = "text/plain"
  else
    lines = {console_html}
    headers["Content-Type"] = "text/html"
  end
  local return_content = table.concat (lines)

  
  local function iterator ()     -- one-shot iterator, returns content, then nil
    local x = return_content
    return_content = nil 
    return x
  end

  return status, headers, iterator
end

-----
