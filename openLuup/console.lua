#!/usr/bin/env wsapi.cgi

module(..., package.seeall)


ABOUT = {
  NAME          = "console.lua",
  VERSION       = "2018.07.19",
  DESCRIPTION   = "console UI for openLuup",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-18 AK Booer

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

-- 2017.04.26  HTML menu improvement by @explorer (thanks!)
-- 2017.07.05  add user_data, status and sdata to openLuup menu

-- 2018.01.30  add invocations count to job listing
-- 2018.03.19  add Servers menu
-- 2018.03.24  add connection count to iprequests on HTTP server page
-- 2018.04.07  add Scheduler Sandboxes menu
-- 2018.04.08  add Servers POP3 menu
-- 2018.04.10  add Scheduler Sockets menu
-- 2018.04.14  add Images menu
-- 2018.04.15  add Trash menu
-- 2018.04.19  add Servers UDP menu
-- 2018.05.15  add Historian menu
-- 2018.05.19  use openLuup ABOUT, not console
-- 2018.05.28  add Files HistoryDB menu
-- 2018.07.08  add hyperlink database files to render graphics
-- 2018.07.12  add typerlink backup files to uncompress and retrieve
-- 2018.07.15  colour code non-200 status numbers
-- 2018.07.19  use openLuup.whisper, not L_DataWhisper! (thanks @powisquare)


-- TODO: HTML pages with sorted tables?
-- see: https://www.w3schools.com/w3js/w3js_sort.asp

--  WSAPI Lua implementation

local lfs       = require "lfs"                   -- for backup file listing
local url       = require "socket.url"            -- for url unescape
local luup      = require "openLuup.luup"         -- not automatically in scope for CGIs
local json      = require "openLuup.json"
local scheduler = require "openLuup.scheduler"    -- for job_list, delay_list, etc...
local requests  = require "openLuup.requests"     -- for user_data, status, and sdata
local http      = require "openLuup.http"
local smtp      = require "openLuup.smtp"
local pop3      = require "openLuup.pop3"
local ioutil    = require "openLuup.io"
local hist      = require "openLuup.historian"    -- for disk archive stats   
local timers    = require "openLuup.timers"       -- for startup time
local whisper   = require "openLuup.whisper"

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local console_html = {

prefix = [[
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Console</title>
    <style>
      *    { box-sizing:border-box; margin:0px; padding:0px; }
      html { width:100%; height:100%; overflow:hidden; border:none 0px; }
      body { font-family:Arial; background:LightGray; width:100%; height:100%; overflow:hidden; padding-top:60px; }
      
      .menu { position:absolute; top:0px; width:100%; height:60px; }
      .content { width:100%; height:100%; overflow:scroll; padding:4px; }
      
      .dropbtn {
        background-color: Sienna;
        color: white;
        padding: 16px;
        font-size: 16px;
        line-height:18px;
        vertical-align:middle;
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
    
    <div class="menu" style="background:DarkGrey;">
    
      <div class="dropdown" >
        <img src="https://avatars.githubusercontent.com/u/4962913" alt="X"  
                style="width:60px;height:60px;border:0;vertical-align:middle;">
      </div>

      <div class="dropdown">
        <button class="dropbtn">openLuup</button>
        <div class="dropdown-content">
          <a class="left" href="/console?page=about">About</a>
          <a class="left" href="/console?page=parameters">Parameters</a>
          <a class="left" href="/console?page=historian">Historian</a>
        </div>
      </div>

      <div class="dropdown">
        <button class="dropbtn">Files</button>
        <div class="dropdown-content">
          <a class="left" href="/console?page=backups">Backups</a>
          <a class="left" href="/console?page=images">Images</a>
          <a class="left" href="/console?page=database">History DB</a>
          <a class="left" href="/console?page=trash">Trash</a>
        </div>
      </div>

      <div class="dropdown">
        <button class="dropbtn">Scheduler</button>
        <div class="dropdown-content">
          <a class="left" href="/console?page=jobs">Jobs</a>
          <a class="left" href="/console?page=delays">Delays</a>
          <a class="left" href="/console?page=watches">Watches</a>
          <a class="left" href="/console?page=sockets">Sockets</a>
          <a class="left" href="/console?page=sandbox">Sandboxes</a>
          <a class="left" href="/console?page=startup">Startup Jobs</a>
        </div>
      </div>

      <div class="dropdown">
        <button class="dropbtn">Servers</button>
        <div class="dropdown-content">
          <a class="left" href="/console?page=http">HTTP Web</a>
          <a class="left" href="/console?page=smtp">SMTP eMail</a>
          <a class="left" href="/console?page=pop3">POP3 eMail</a>
          <a class="left" href="/console?page=udp" >UDP  datagrams</a>
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
    
  </div>

  <div class="content">
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
local line = "%20s  %8s  %12s  %s %s"
local date = "%Y-%m-%d %H:%M:%S"


local function todate (epoch)
  return os.date (date, epoch)
end


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
      local status = table.concat {state[b.status] or '', '[', b.logging.invocations, ']'}
      jlist[#jlist+1] = {
        t = b.expiry,
        l = line: format (todate(b.expiry + 0.5), b.devNo or "system", 
                            status, b.type or '?', b.notes or '')
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
      l = line: format (todate(b.time), b.devNo, "Delay", dtype, '')
    }
  end

  local function listit (list, title)
    print (title .. ", " .. os.date "%c")
    table.sort (list, function (a,b) return a.t < b.t end)
    print ('#', (line: format ("date       time    ", "device", "status[n]","info", '')))
    for i,x in ipairs (list) do print (i, x.l) end
    print ''
  end

  local function printlog (p)
    local fwd = {['<'] = "&lt;", ['>'] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;", ['&'] = "&amp;"}
    local function escape (x) return (x: gsub ([=[[<>"'&]]=], fwd)) end
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
      print (escape (x))       -- thanks @a-lurker
    end
  end
  
  -- map action function onto files
  local function mapFiles (path, action)
    local files = {}
    for name in lfs.dir (path) do
      local attr = lfs.attributes (path .. name) or {}
      attr.path = path
      attr.name = name
      attr.size = tostring (math.floor (((attr.size or 0) + 500) / 1e3))  -- round to kB
      files[#files+1] = action (attr)
    end
    return files
  end
  
  -- returns specified file in a list of tables {date=x, name=y, size=z}
  local function get_matching_files_from (folder, pattern)
    local files = mapFiles (folder, 
      function (attr)
        local name = attr.name
        local date = name: match (pattern)
        if date then return {date = date, name = name, size = attr.size} end
      end)
    table.sort (files, function (a,b) return a.date > b.date end)       -- sort newest to oldest
    return files
  end
  
  local function backups ()
    local dir = luup.attr_get "openLuup.Backup.Directory" or "backup/"
    print ("Backup directory: ", dir)
    print ''
    local pattern = "backup%.openLuup%-%w+%-([%d%-]+)%.?%w*"
    local files = get_matching_files_from ("backup/", pattern)
    local list = "%-12s %4s   %s"
    print (list:format ("yyyy-mm-dd", "(kB)", "filename"))
    for _,f in ipairs (files) do 
      local hyperlink = [[<a href="cgi-bin/cmh/backup.sh?retrieve=%s" download="%s">%s</a>]]
      local name = hyperlink:format (f.name, f.name: gsub (".lzap$",'') .. ".json", f.name)
      print (list:format (f.date, f.size, name)) 
    end
  end
  
  local function number (n) return ("%7d  "): format (n) end
  local function status_number (n)
    if n == 200 then return number(n) end
    return ('<font color="red">%7d</font>'): format (n) 
  end
  
  local function devname (d)
    d = tonumber(d) or 0
    local name = (luup.devices[d] or {}).description or 'system'
    name = name: match "^%s*(.+)"
    local number = table.concat {'[', d, '] '}
    return number .. name, number, name
  end

  local function printConnections (iprequests)
    local layout1 = "     %-32s %s %s"
    local none = "--- none ---"
    local function printout (a,b,c) print (layout1: format (a,b or '',c or '')) end
    print "\n Received connections:"
    printout("IP address", "#connects", "    date     time\n")
    if not next (iprequests) then printout (none) end
    for ip, req in pairs (iprequests) do
      local count = number (req.count)
      printout (ip, count, todate(req.date))
    end
  end
  
  
  local function httplist ()
    local layout = "     %-42s %s %s"
    local function printout (a,b,c) print (layout: format (a,b or '',c or '')) end
    
    local function printinfo (requests)
      local calls = {}
      for name in pairs (requests) do calls[#calls+1] = name end
      table.sort (calls)
      for _,name in ipairs (calls) do
        local call = requests[name]
        local count = call.count
        local status = call.status
        if count and count > 0 then
          printout (name, number(count), status_number(status))
        end
      end
    end
    
    print ("HTTP Web Server, " .. os.date "%c")
    printConnections (http.iprequests)     
    
    print "\n /data_request?"
    printout ("id=... ", "#requests  ","status")
    printinfo (http.http_handler)
    
    print "\n CGI requests"
    printout ("URL ", "#requests  ","status")
    printinfo (http.cgi_handler)
    
    print "\n File requests"
    printout ("filename ", "#requests  ","status")
    printinfo (http.file_handler)
    
  end
  
  local function smtplist ()
    local layout = "     %-32s %s %s"
    local none = "--- none ---"
    local function printout (a,b,c) print (layout: format (a,b or '',c or '')) end
    
    local function print_sorted (info, ok)
      printout ("Address", "#messages", "for device\n")
      local n = 0
      local index = {}
      for ip in pairs (info) do index[#index+1] = ip end
      table.sort (index)    -- get the email addresses into order
      for _,ip in ipairs (index) do
        local dest = info[ip]
        local name = devname (dest.devNo)
        local count = number (dest.count)
        if ok(ip) then 
          n = n + 1
          printout (ip, count, name) 
        end
      end
      if n == 0 then printout (none) end
    end
    
    print ("SMTP eMail Server, " .. os.date "%c")
    printConnections (smtp.iprequests)    
    
    print "\n Registered email sender IPs:"
    print_sorted (smtp.destinations, function(x) return not x:match "@" end)
    
    print "\n Registered destination mailboxes:"
    print_sorted (smtp.destinations, function(x) return x:match "@" end)
    
    print "\n Blocked senders:"
    printout ("eMail address", '', '\n')
    if not next (smtp.blocked) then printout (none) end
    for email in pairs (smtp.blocked) do
      printout (email)
    end
  end
  
  local function pop3list ()
    
    print ("POP3 eMail Server, " .. os.date "%c")
    printConnections (pop3.iprequests)    
    
    print "\n Registered accounts:"
    
    local layout = "     %-21s %9s"
    local number = "%7s"
    local header = "\n    Mailbox '%s': %d messages, %0.1fkB"
    local accounts = pop3.accounts
    
    for name, folder in pairs (accounts) do
      local mbx = pop3.mailbox.open (folder)
      local total, bytes = mbx: status()
      print (header: format (name, total, bytes/1e3))
      print ('      #' .. (layout: format ("date       time", "size\n")))
      
      local list = {}
      for _, size, _, timestamp in mbx:scan() do
        list[#list+1] = {t=timestamp, l=layout:format (os.date (date, timestamp), size)}
      end
      table.sort (list, function (a,b) return a.t > b.t end)  -- newest first
      if #list == 0 then 
        print "              --- none ---" 
      else
        for i,x in ipairs (list) do print (number:format(i) .. x.l) end
      end
      print ''
      mbx: close ()
    end
  end
  
  local function udplist ()
    print ("UDP datagram Listeners, " .. os.date "%c")
    printConnections (ioutil.udp.iprequests)    
    
--[[
       udp.listeners[port] = {                     -- record info for console server page
            callback = callback, 
            devNo = scheduler.current_device (),
            port = port,
            count = 0,
          }
--]]
    print "\n Registered listeners:"
    local list = {}
    print        "    port           #datagrams for device \n"
    local listeners = "%8s            %5d     %s"
    for port, x in pairs(ioutil.udp.listeners) do
      local name = devname (x.devNo)
      list[#list+1] = {port = port, l = listeners:format (port, x.count, name)}
    end
    table.sort (list, function (a,b) return a.port < b.port end)
    if #list == 0 then 
      print "              --- none ---" 
    else
      for _,x in ipairs (list) do print (x.l) end
    end
    print ''
  
--[[
      udp.senders[#udp.senders+1] = {                         -- can't index by port, perhaps not unique
          devNo = scheduler.current_device (),
          ip_and_port = ip_and_port,
          sock = sock,
          count = 0,      -- don't, at the moment, count number of datagrams sent
        }
 --]]
    print "\n Opened for write:"
    list = {}
    print        "    ip:port                   by device \n"
    local senders = "%20s          %s"
    for i, x in pairs(ioutil.udp.senders) do
      local name = devname (x.devNo)
      list[i] = {ip_and_port = x.ip_and_port, l = senders:format (x.ip_and_port, name)}
    end
    table.sort (list, function (a,b) return a.ip_and_port < b.ip_and_port end)
    if #list == 0 then 
      print "              --- none ---" 
    else
      for _,x in ipairs (list) do print (x.l) end
    end
    print ''
 
  end
  
  
  local function sockets ()
    print "Watched Sockets"

    local number = "%7s"
    local layout = "     %-21s  %5s    %-20s"
    print "      #     date       time         device           socket"
    local list = {}
    local sock_drawer = scheduler.get_socket_list()    -- list is indexed by socket !!
    for sock, x in pairs (sock_drawer) do
--    callback = action,
--    devNo = current_device,
--    io = io or {intercept = false},  -- assume no intercepts: incoming data is passed to handler
      local sockname = table.concat {tostring(x.name), ' ', tostring(sock)}
      list[#list+1] = layout: format (os.date(date, x.time), x.devNo or 0, sockname)
    end
    table.sort (list, function (a,b) return a > b end)
    
    if #list == 0 then 
      print "      --- none ---" 
    else
      for i,x in ipairs (list) do print (number:format(i) .. x) end
    end
    print ''

  end
  
  local function sandbox ()               -- 2018.04.07
    print "Sandboxed system tables"
    for _,v in pairs (_G) do
      local meta = ((type(v) == "table") and getmetatable(v)) or {}
      if meta.__newindex and meta.__tostring then   -- not foolproof, but good enough?
        print ('\n' .. tostring(v))
      end
    end
  end
  
  local function images ()
    local files = get_matching_files_from ("images/", '^[^%.]+%.[^%.]+$')     -- *.*
    
    print ("Images  " .. os.date "%c", '\n')
    
    print [[<nav>]]
    local option = '%s <a href="/images/%s" target="image">%s</a>'
    for i,f in ipairs (files) do 
      print (option: format (number(i), f.name, f.name))
    end
    print "</nav>"
--    print [[<iframe name="output" rows=60 cols=50 height="700px" width="50%" >]]
    print [[<article><iframe name="image" width="50%" ></article>]]

    print ''
  end
 
  local function trash ()
    local files = get_matching_files_from ("trash/", '^[^%.]+%.[^%.]+$')     -- *.*
    print ("Trash  " .. os.date "%c", '\n')
    for i,f in ipairs (files) do print (i, f.name) end
    if #files == 0 then print "       --- none ---" end
    print ''
  end
  
  -- compares corresponding elements of array
  local function keysort (a,b) 
    a, b = a.sortkey, b.sortkey
    local function lt (i)
      local x,y = a[i], b[i]
      if not  y then return false end
      if not  x then return true  end
      if x <  y then return true  end
      if x == y then return lt (i+1) end
      return false
    end
    return lt(1)
  end

  local function historian ()
    local N = 0
    local H = {}
    for _,d in pairs (luup.devices) do
      for _,v in ipairs (d.variables) do 
        N = N + 1 
        if v.history and #v.history > 2 then
          local finderName = hist.metrics.var2finder (v)
          H[#H+1] = {v = v, finderName = finderName, sortkey = {v.dev, v.shortSid, v.name}}
        end
      end
    end
     
--    local layout = "    %8s  %10s%-28s %-20s %s"
    local layout = "    %8s  %8s %-20s %s"
    local T = 0
    table.sort (H, keysort)
    
    print ("Data Historian Cache Memory, " .. os.date(date))
    print ("\n  Total number of device variables: " .. N)
    print ("\n  Variables with History: " .. #H)
    print ''
--    print (layout: format ("#points", "device ", "name", "service", "variable \n"))
    print (layout: format ("#points", "device ", "service", "variable"))
    
    local link = [[<a href="/render?target=%s&from=%s">%s</a>]]
    local prev  -- previous device (for line spacing)
    for _, x in ipairs(H) do
      local v = x.v
      local vname = v.name
      if x.finderName then 
        local _,start = v:oldest()      -- get earliest entry in the cache (if any)
        if start then
          local from = timers.util.epoch2ISOdate (start + 1)    -- ensure we're AFTER the start... 
          vname = link: format (x.finderName, from, vname)      -- ...and use fixed time format
        end
      end
      local h = #v.history / 2
      T = T + h
--      local _, number, dname = devname(v.dev)
      local dname = devname(v.dev)
      if dname ~= prev then 
        local devname = "\n%14s<em>%s</em>"
        print(devname: format ('', dname)) 
      end
      prev = dname
--      print (layout:format (h, number, dname, v.srv: match "[^:]+$" or v.srv, vname))
      print (layout:format (h, '', v.srv: match "[^:]+$" or v.srv, vname))
    end
    print ("\n  Total number of history points:", T)
  end
  
  
  local function database ()
    local folder = luup.attr_get "openLuup.Historian.Directory"
    
    print ("Data Historian Disk Database, " .. os.date(date))
    
    if not folder then
      print "\n  On-disk archiving not enabled"
      return
    end
    
    -- stats
    local s = hist.stats
    local tot, cpu, wall = s.total_updates, s.cpu_seconds, s.elapsed_sec
    
    local cpu_rate   = cpu / tot * 1e3
    local wall_rate  = wall / tot * 1e3
    local write_rate = 60 * tot / (timers.timenow() - timers.loadtime)
    
    print ''
    local stats = "   updates/min: %0.1f,  time/point: %0.1f ms (cpu: %0.1f ms),  directory: %s"
    print (stats: format (write_rate, wall_rate, cpu_rate, folder))
    
    local tally = hist.tally        -- here's the historian's stats on individual file updates
    
    local files = mapFiles (folder, 
      function (a)        -- file attributes including path, name, size,... (see lfs.attributes)
        local filename = a.name: match "^(.+).wsp$"
        if filename then
         local pk,d,s,v = filename: match "(%d+)%.(%d+)%.([%w_]+)%.(.+)"  -- pk.dev.svc.var, for sorting
          a.sortkey = {tonumber(pk), tonumber(d), s, v}
          local i = whisper.info (folder .. a.name)
          a.shortName = filename
          a.retentions = tostring(i.retentions) -- text representation of archive retentions
          a.updates = tally[filename] or ''
          local finderName, devnum, description = hist.metrics.pkdsv2finder (pk,d,s,v)
          a.finderName = finderName
          a.devnum = devnum or ''
          a.description = description or "-- unknown --"
          local links = {}
          if a.finderName then 
            local link = [[<a href="/render?target=%s&from=-%s">%s</a>]]      -- use relative time format
            for arch in a.retentions: gmatch "[^,]+" do
              local _, duration = arch: match "([^:]+):(.+)"                  -- rate:duration
              links[#links+1] = link: format (a.finderName, duration, arch) 
            end
            a.links = table.concat (links, ',')
          end
          return a
        end
      end)
    
    table.sort (files, keysort)
    
    local list = "%s %40s %10s  %8s   %s"
    print ''
--    print (list:format ('', "archives", "size", "(kB)", "#updates", "filename (node.dev.srv.var) \n"))
    print (list:format ('', "archives", "(kB)", "#updates", "filename (node.dev.srv.var)"))
    local prev
    local N,T = 0,0
    for _,f in ipairs (files) do 
      N = N + 1
      T = T + f.size
      -- have to tab space manually, since archive links contain HTML (not visible)
      local tab = ''    
      local spc = ' '
      if f.links then tab = spc: rep(40 - #f.retentions) end
      --
      local devnum = f.devnum     -- openLuup device number (if present)
      if devnum ~= prev then 
        local devname = "\n <em>%40s</em>"
--        local devname = "\n%s<em>%s</em>"
--        print(devname: format (spc: rep(52), f.description: match "%s*(.*)"))
        print(devname: format (f.description))
      end
      prev = devnum
      print (list:format (tab, f.links or f.retentions, f.size, f.updates, f.shortName)) 
--      if i % 5 == 0 then print '' end     -- cosmetic line spacing
    end
    
    print '\n'
    T = T / 1000;
    print (list:format ('',"TOTALS: " .. N .. " database files, ", (T - T % 0.1) .. " (Mb)", tot, ''))
  end
  
  
  local ABOUTopenLuup = luup.devices[2].environment.ABOUT   -- use openLuup about, not console
  
  local pages = {
    about   = function () for a,b in pairs (ABOUTopenLuup) do print (a .. ' : ' .. tostring(b)) end end,
    backups = backups,
    database = database,
    delays  = function () listit (dlist, "Delayed Callbacks") end,
    images  = images,
    jobs    = function () listit (jlist, "Scheduled Jobs") end,
    log     = printlog,
    startup = function () listit (slist, "Startup Jobs") end,
    watches = watchlist,
    http    = httplist,
    smtp    = smtplist,
    pop3    = pop3list,
    sockets = sockets,
    sandbox = sandbox,
    trash   = trash,
    udp     = udplist,
    
    historian   = historian,
    
    parameters = function ()
      local info = luup.attr_get "openLuup"
      local p = json.encode (info or {})
      print (p or "--- none ---")
    end,
    
    userdata = function ()
      local u = requests.user_data()
      print(u)
    end,
    
    status = function ()
      local s = requests.status()
      print(s)
    end,
    
    sdata = function ()
      local d = requests.sdata()
      print(d)
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
  
  do (pages[page] or function () end) (p) end
  headers["Content-Type"] = "text/html"
  
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
