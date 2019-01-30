#!/usr/bin/env wsapi.cgi

module(..., package.seeall)


ABOUT = {
  NAME          = "console.lua",
  VERSION       = "2019.01.30",
  DESCRIPTION   = "console UI for openLuup",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-19 AK Booer

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
-- 2018.07.28  use wsapi request and response libraries
-- 2018.08.26  correct file size units in POP3 page listing

-- 2019.01.12  checkbox on Historian page to show which variables are archived (readonly at present)
-- 2019.01.22  link to external CSS file
-- 2019.01.24  move CSS to openLuup_console.css in virtualfilesystem
-- 2019.01.29  use html tables for most console pages


-- TODO: HTML pages with sorted tables?
-- see: https://www.w3schools.com/w3js/w3js_sort.asp

--  WSAPI Lua implementation

local lfs       = require "lfs"                   -- for backup file listing
local vfs       = require "openLuup.virtualfilesystem"
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
local wsapi     = require "openLuup.wsapi"        -- for response library

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local console_html = {

prefix = table.concat {
[[
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Console</title>
]],

"<style>", vfs.read "openLuup_console.css", "</style>",

[[
  
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
]]}
,
--     <div style="overflow:scroll; height:500px;">

postfix = [[
  <br/>
  </div>
  </body>
</html>

]]
}

local state =  {[-1] = "No Job", [0] = "Wait", "Run", "Error", "Abort", "Done", "Wait", "Requeue", "Pending"} 
local date = "%Y-%m-%d %H:%M:%S"


local function todate (epoch)
  return os.date (date, epoch)
end


local html5 = {}

function html5.table ()
  
  local headers = {}
  local rows = {}
  
  local function header (h)
    headers[#headers+1] = h
  end

  local function row (r)
    rows[#rows+1] = r
  end
  
  local function item (tag, x)
    if type (x) ~= "table" then x = {x} end
    local attr = {'<', tag}
    for n,v in pairs (x) do
      if n ~= 1 then
        attr[#attr+1] = table.concat {' ', n, '="', v, '"'}
      end
    end
    attr[#attr+1] = table.concat {'>', x[1] or '', '</', tag, '>'}
    return table.concat (attr)
  end

  local function render ()
    local t = {[[<br/><table>]]}
    local function new_rows (rs, typ)
      typ = typ or "td"
      for _, r in ipairs (rs) do
        local row = {}
        for _, x in ipairs (r) do
          row[#row+1] = item (typ, x)
        end
    t[#t+1] = table.concat {"  <tr>", table.concat (row), "</tr>"}
      end
    end
    
    new_rows (headers, "th")
    new_rows (rows)
    t[#t+1] = "</table>\n"
    return table.concat (t, '\n')
  end

  return setmetatable ({
      header = header, 
      row = row,
      length = function() return #rows end,
    },{
      __tostring = render,
--      __len = function () return #rows end,   -- sadly, not implemented by some v5.1 Lua implementations
    })
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
--  local function print (a,b)
--    local fmt = "%5s %s \n"
--    lines[#lines+1] = fmt: format (a, b or '')
--  end
  local function print (x)
    lines[#lines+1] = x
  end

  local function title (x)
    print (table.concat {"<h4>", x,  os.date ", %c </h4>"})
  end
  
  -- sort table list elements by first index, then number them in sequence
  local function sort_and_number (list)
    table.sort (list, function (a,b) return a[1] < b[1] end)
    for i, row in ipairs (list) do row[1] = i end
    return list
  end
  
  local function joblist2 ()
    title "Scheduled Jobs"
    local t = html5.table()
    t.header {"#", "date / time", "device", "status[n]", "info", "notes"}
    local jlist = {}
    for _,b in pairs (scheduler.job_list) do
      local status = table.concat {state[b.status] or '', '[', b.logging.invocations, ']'}
      jlist[#jlist+1] = {b.expiry, todate(b.expiry + 0.5), b.devNo or "system", status, b.type or '?', b.notes or ''}
    end
    for _, row in ipairs (sort_and_number(jlist)) do
      t.row (row)
    end
    print (tostring(t))
  end

  local function delaylist2 ()
    title "Delayed Callbacks"
    local t = html5.table()
    t.header {"#", "date / time", "device", "status", "info"}
    local dlist = {}
    local delays = "%4.0fs :callback %s"
    for _,b in pairs (scheduler.delay_list()) do
      local dtype = delays: format (b.delay, b.type or '')
      dlist[#dlist+1] = {b.time, todate(b.time), b.devNo, "Delay", dtype}
    end
    for _, row in ipairs (sort_and_number(dlist)) do
      t.row (row)
    end
    print (tostring(t))
  end

  local function startup2 ()
    title "Startup Jobs"
    local t = html5.table()
    t.header {"#", "date / time", "device", "status[n]", "info", "notes"}
    local jlist = {}
    for _,b in pairs (scheduler.startup_list) do
      local status = table.concat {state[b.status] or '', '[', b.logging.invocations, ']'}
      jlist[#jlist+1] = {b.expiry, todate(b.expiry + 0.5), b.devNo or "system", status, b.type or '?', b.notes or ''}
    end
    for _, row in ipairs (sort_and_number(jlist)) do
      t.row (row)
    end
    print (tostring(t))
  end
  
  local function watchlist2 ()
    local W = {}
    
    local function isW (w, d,s,v)
      if next (w.watchers) then
        for _, what in ipairs (w.watchers) do
          W[#W+1] = {what.devNo, what.devNo, what.name or '?', table.concat ({d,s or '*',v or '*'}, '.')}
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

    local t = html5.table()
    title "Variable Watches"
    t.header {'#', "dev", "callback", "watching"}
    for _, row in ipairs (sort_and_number(W)) do
      t.row (row)
    end
    print (tostring(t))
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
      title (name)
      print "<br/><pre>"
      print (escape (x))       -- thanks @a-lurker
      print "</pre>"
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
    title ("Backup directory: " .. dir)
    local pattern = "backup%.openLuup%-%w+%-([%d%-]+)%.?%w*"
    local files = get_matching_files_from ("backup/", pattern)
    local t = html5.table ()
    t.header {"yyyy-mm-dd", "(kB)", "filename"}
    for _,f in ipairs (files) do 
      local hyperlink = [[<a href="cgi-bin/cmh/backup.sh?retrieve=%s" download="%s">%s</a>]]
      local name = hyperlink:format (f.name, f.name: gsub (".lzap$",'') .. ".json", f.name)
      t.row {f.date, f.size, name} 
    end
    print (tostring(t))
  end
  
  local function number (n) return n end    -- TODO: remove
  
  local function status_number (n)
    if n == 200 then return n end
    return ('<font color="crimson">%d</font>'): format (n) 
  end
  
  local function devname (d)
    d = tonumber(d) or 0
    local name = (luup.devices[d] or {}).description or 'system'
    name = name: match "^%s*(.+)"
    local number = table.concat {'[', d, '] '}
    return number .. name, number, name
  end

  local function printConnections (iprequests)
--    print "<br/>"
    local t = html5.table ()
    t.header { {"Received connections:", colspan=3} }
    t.header {"IP address", "#connects", "date / time"}
    for ip, req in pairs (iprequests) do
      local count = number (req.count)
      t.row {ip, count, todate(req.date)}
    end
    if t.length() == 0 then t.row {'', "--- none ---", ''} end
    print (tostring(t))
  end
  
  
  local function httplist ()    
    local function printinfo (requests, title, columns)
      local t = html5.table ()
      t.header { {title, colspan = 3} }
      t.header (columns)
      local calls = {}
      for name in pairs (requests) do calls[#calls+1] = name end
      table.sort (calls)
      for _,name in ipairs (calls) do
        local call = requests[name]
        local count = call.count
        local status = call.status
        if count and count > 0 then
          t.row {name, number(count), status_number(status)}
        end
      end
      if t.length() == 0 then t.row {'', "--- none ---", ''} end
      print (tostring(t))
    end
    
    title "HTTP Web Server"
    printConnections (http.iprequests)     
    
    printinfo (http.http_handler, "/data_request?", {"id=... ", "#requests  ","status"})
    printinfo (http.cgi_handler, "CGI requests", {"URL ", "#requests  ","status"})
    printinfo (http.file_handler, "File requests", {"filename ", "#requests  ","status"})
    
  end
  
  local function smtplist ()
    local none = "--- none ---"
    
    local function print_sorted (title, info, ok)
      local t = html5.table ()
      t.header { {title, colspan = 3} }
      t.header {"Address", "#messages", "for device"}
      local index = {}
      for ip in pairs (info) do index[#index+1] = ip end
      table.sort (index)    -- get the email addresses into order
      for _,ip in ipairs (index) do
        local dest = info[ip]
        local name = devname (dest.devNo)
        local count = number (dest.count)
        if ok(ip) then 
          t.row {ip, count, name}
        end
      end
      if t.length() == 0 then t.row {'', none, ''} end
      print (tostring(t))
    end
    
    title "SMTP eMail Server"
    printConnections (smtp.iprequests)    
    
    print_sorted ("Registered email sender IPs:", smtp.destinations, function(x) return not x:match "@" end)
    print_sorted ("Registered destination mailboxes:", smtp.destinations, function(x) return x:match "@" end)
    
    local t = html5.table ()
    t.header {{ "Blocked senders:", colspan=2 }}
    t.header {"eMail address","#attempts"}
    for email in pairs (smtp.blocked) do
      t.row {email, '?'}
    end
    if t.length() == 0 then t.row {'', none, ''} end
    print (tostring(t))
  end
  
  local function pop3list ()
    title "POP3 eMail Server"
    printConnections (pop3.iprequests)    
    local header = "Mailbox '%s': %d messages, %0.1f (kB)"
    local accounts = pop3.accounts    
    for name, folder in pairs (accounts) do
      local mbx = pop3.mailbox.open (folder)
      local total, bytes = mbx: status()
      
      local t = html5.table()
      t.header { {header: format (name, total, bytes/1e3), colspan = 3 } }
      t.header {'#', "date / time", "size (bytes)"}
      
      local list = {}
      for _, size, _, timestamp in mbx:scan() do
        list[#list+1] = {t = timestamp, d = os.date (date, timestamp), s = size}
      end
      table.sort (list, function (a,b) return a.t > b.t end)  -- newest first
      for i,x in ipairs (list) do 
        t.row {i, x.d, x.s} 
      end
      mbx: close ()
      if t.length() == 0 then t.row {'', "--- none ---", ''} end
      print (tostring(t))
    end
  end
  
  local function udplist ()
    title "UDP datagram Listeners"
    printConnections (ioutil.udp.iprequests)    
    local t = html5.table ()
    t.header { {"Registered listeners:", colspan = 3} }
    t.header {"port", "#datagrams", "for device"}
    local list = {}
    for port, x in pairs(ioutil.udp.listeners) do
      local dname = devname (x.devNo)
      list[#list+1] = {port = port, n = x.count, dev = dname}
    end
    table.sort (list, function (a,b) return a.port < b.port end)
    for _,x in ipairs (list) do 
      t.row {x.port, x.n, x.dev} 
    end
    if t.length() == 0 then t.row {'', "--- none ---", ''} end 
    print (tostring(t))
    t = html5.table()
    t.header { {"Opened for write:", colspan = 2} }
    t.header {"ip:port", "by device"}
    list = {}
    for i, x in pairs(ioutil.udp.senders) do
      local dname = devname (x.devNo)
      list[i] = {ip_and_port = x.ip_and_port, n = x.count, dev = dname}   -- doesn't yet count datagrams sent
    end
    table.sort (list, function (a,b) return a.ip_and_port < b.ip_and_port end)
    for _,x in ipairs (list) do 
      t.row {x.ip_and_port, x.dev} 
    end
    if t.length() == 0 then t.row {"--- none ---", ''} end 
    print (tostring(t)) 
  end
  
  
  local function sockets ()
    local cols = {}
    local sock_drawer = scheduler.get_socket_list()    -- list is indexed by socket !!
    for sock, x in pairs (sock_drawer) do
      local sockname = table.concat {tostring(x.name), ' ', tostring(sock)}
      cols[#cols+1] = {0, os.date(date, x.time), x.devNo or 0, sockname}
    end
    table.sort (cols, function (a,b) return a[1] > b[1] end)
    
    local t = html5.table()
    t.header {"#", "date / time", "device", "socket"}
    for i,x in ipairs (cols) do x[1] = i; t.row (x) end
    if #cols == 0 then t.row {0, '', "--- none ---", ''} end
    
    title "Watched Sockets"
    print (tostring (t))
  end
  
  local function sandbox ()               -- 2018.04.07
    local function format (tbl)
      local lookup = getmetatable (tbl).lookup
      local boxmsg = "[%d] %s - Private items:"
      local function devname (d) 
        return ((luup.devices[d] or {}).description or "System"): match "^%s*(.+)" 
      end
      local function sorted(x, title)
        local y = {}
        for k,v in pairs (x) do y[#y+1] = {k, tostring(v)} end
        table.sort (y, function (a,b) return a[1] < b[1] end)
        local t = html5.table()
        t.header {{title, colspan = 2}}
        t.header {"name","type"}
        for _, row in ipairs(y) do
          t.row (row)
        end
        print (tostring(t))
      end
      for d, idx in pairs (lookup) do
        sorted(idx, boxmsg: format (d, devname(d)))
      end
      sorted (tbl, "Shared items:")
    end
    title "Sandboxed system tables"
    for n,v in pairs (_G) do
      local meta = ((type(v) == "table") and getmetatable(v)) or {}
      if meta.__newindex and meta.__tostring and meta.lookup then   -- not foolproof, but good enough?
        print (table.concat {'<h4>', n, ".sandbox</h4>"})  
        format(v)
      end
    end
  end
  
  local function images ()
    local files = get_matching_files_from ("images/", '^[^%.]+%.[^%.]+$')     -- *.*
    
    title "Images"
    
    print [[<nav>]]
--    local option = '%s <a href="/images/%s" target="image">%s</a>'
    local option = '<a href="/images/%s" target="image">%s</a>'
    local t = html5.table ()
    t.header {'#', "filename"}
    for i,f in ipairs (files) do 
--      print (option: format (number(i), f.name, f.name))
      t.row {i, option: format (f.name, f.name)}
    end
    print (tostring(t))
    print "</nav>"
--    print [[<iframe name="output" rows=60 cols=50 height="700px" width="50%" >]]
    print [[<article><iframe name="image" width="50%" ></article>]]

    print ''
  end
 
  local function trash ()
    local files = get_matching_files_from ("trash/", '^[^%.]+%.[^%.]+$')     -- *.*
    local t = html5.table ()
    title "Trash"
    t.header {'#', "filename", "size"}
    for i,f in ipairs (files) do
      t.row {i, f.name, f.size}
    end
    if t.length() == 0 then t.row {'', "--- none ---", ''} end
    print (tostring(t))
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
    
    -- find all the archived metrics
    local folder = luup.attr_get "openLuup.Historian.Directory"
    local archived = {}
    if folder then 
      mapFiles (folder, 
        function (a)
          local filename = a.name: match "^(.+).wsp$"
          if filename then
            local pk,d,s,v = filename: match "(%d+)%.(%d+)%.([%w_]+)%.(.+)"  -- pk.dev.svc.var
            local findername = hist.metrics.pkdsv2finder (pk,d,s,v)
            if findername then archived[findername] = true end
          end
        end)
    end
    
    -- find all the variables with history
    local N = 0
    local H = {}
    for _,d in pairs (luup.devices) do
      for _,v in ipairs (d.variables) do 
        N = N + 1 
        if v.history and #v.history > 2 then
          local finderName = hist.metrics.var2finder (v)
          H[#H+1] = {v = v, finderName = finderName, archived = archived[finderName], 
                        sortkey = {v.dev, v.shortSid, v.name}}
        end
      end
    end
     
    local T = 0
    table.sort (H, keysort)
    
    title "Data Historian Cache Memory"
    
    local t = html5.table()
    t.header {"device ", "service", "#points", "variable (archived if checked)" }
    
    local link = [[<a href="/render?target=%s&from=%s">%s</a>]]
    local tick = '<input type="checkbox" readonly %s /> %s'
    local prev  -- previous device (for formatting)
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
      local dname = devname(v.dev)
      if dname ~= prev then 
        local devname = "<strong>%s</strong>"
        --
--        devname = [[\n%14s<em>%s</em>
--        <form action="cgi/no-content.lua" method="post"> 
--        <input type="Submit" value="Update"> 
--        </form>
--        ]]
        --
        t.row { {devname: format (dname), colspan = 4} } -- , style = "background-color: lightblue;"} }
      end
      prev = dname
      local check = x.archived and "checked" or ''
      t.row {'', v.srv: match "[^:]+$" or v.srv, h, tick: format (check, vname)}
    end
    
    local t0 = html5.table()
    t0.header { {"Summary:", colspan = 2} }
    t0.row {"total # device variables", N}
    t0.row {"total # variables with history", #H}
    t0.row {"total # history points", T}
    print (tostring(t0))
    print (tostring(t))
  end
  
  
  local function database ()
    local folder = luup.attr_get "openLuup.Historian.Directory"
    
    title "Data Historian Disk Database"
    
    if not folder then
      print "On-disk archiving not enabled"
      return
    end
    
    -- stats
    local s = hist.stats
    local tot, cpu, wall = s.total_updates, s.cpu_seconds, s.elapsed_sec
    
    local cpu_rate   = cpu / tot * 1e3
    local wall_rate  = wall / tot * 1e3
    local write_rate = 60 * tot / (timers.timenow() - timers.loadtime)
    
    local function dp1(x) return x - x % 0.1 end
    
    local t0 = html5.table ()
    t0.header { {"Summary: " .. folder, colspan = 2} }
    t0.row {"updates/min", dp1 (write_rate)}
    t0.row {"time/point (ms)", dp1(wall_rate)}
    t0.row {"cpu/point (ms)", dp1(cpu_rate)}
    
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
            a.links = table.concat (links, ', ')
          end
          return a
        end
      end)
    
    table.sort (files, keysort)
    
    local t = html5.table ()
    t.header {'', "archives", "(kB)", "#updates", "filename (node.dev.srv.var)"}
    local prev
    local N,T = 0,0
    for _,f in ipairs (files) do 
      N = N + 1
      T = T + f.size
      local devnum = f.devnum     -- openLuup device number (if present)
      if devnum ~= prev then 
--        local devname = "<em>%s</em>"
        local dname = "<strong>[%s] %s</strong>"
--        local devname = "\n%s<em>%s</em>"
        t.row { { dname: format (f.devnum,f.description), colspan = 5} }
      end
      prev = devnum
      t.row {'', f.links or f.retentions, f.size, f.updates, f.shortName}
    end
    
    T = T / 1000;
    t0.row {"total # files", N}
    t0.row {"total size (Mb)", T - T % 0.1}
    t0.row {"total # updates", tot}
    print (tostring (t0))
    print (tostring (t))
  end
  
  
  local ABOUTopenLuup = luup.devices[2].environment.ABOUT   -- use openLuup about, not console
  
  local pages = {
    about   = function () 
      title "About..."
      print "<br/><pre>"
      for a,b in pairs (ABOUTopenLuup) do
        print (table.concat {a, ' : ', tostring(b), '\n'}) 
      end
      print "</pre>"
    end,
    
    backups = backups,
    database = database,
    delays  = delaylist2,
    images  = images,
    jobs    = joblist2,
    log     = printlog,
    startup = startup2,
    watches = watchlist2,
    http    = httplist,
    smtp    = smtplist,
    pop3    = pop3list,
    sockets = sockets,
    sandbox = sandbox,
    trash   = trash,
    udp     = udplist,
    
    historian   = historian,
    
    parameters = function ()
      title "openLuup Parameters"
      print "<br/><pre>"
      local info = luup.attr_get "openLuup"
      local p = json.encode (info or {})
      print (p or "--- none ---")
      print "</pre>"
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

  -- run()
  
  local req = wsapi.request.new (wsapi_env)
  local res = wsapi.response.new ()
  
  local p = req.GET 
  
  lines = {console_html.prefix}  
  local page = p.page or ''  
  do (pages[page] or function () end) (p) end  
  print (console_html.postfix)
  
  res: write (lines)

  return res: finish()
end

-----
