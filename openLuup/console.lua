#!/usr/bin/env wsapi.cgi

module(..., package.seeall)


ABOUT = {
  NAME          = "console.lua",
  VERSION       = "2019.05.12",
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
-- 2019.03.22  use xml.html5 module to construct tables, and xml.escape() rather than internal routine
-- 2019.04.03  use "startup" as time option for historian plots
-- 2019.04.05  add latest value to historian cache table
-- 2019.04.08  use SVG for avatar, rather than link to GitHub icon
-- 2019.04.24  make avatar link to AltUI home page, sortable cache and jobs tables
-- 2019.05.01  use page=render to wrap graphics
-- 2019.05.02  rename startup page to plugins and include cpu usage
-- 2019.05.10  use new device:get_shortcodes() in device_states()


-- TODO: HTML pages with tabbed tables?
-- see: http://qnimate.com/tabbed-area-using-html-and-css-only/
-- TODO: modal pop-ups?
-- see: https://jsfiddle.net/kumarmuthaliar/GG9Sa/1/

--  WSAPI Lua implementation

local lfs       = require "lfs"                   -- for backup file listing
local vfs       = require "openLuup.virtualfilesystem"
local luup      = require "openLuup.luup"         -- not automatically in scope for CGIs
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

local xml       = require "openLuup.xml"          -- for xml.escape(), and...
local html5     = xml.html5                       -- html5 and svg libraries


local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local state =  {[-1] = "No Job", [0] = "Wait", "Run", "Error", "Abort", "Done", "Wait", "Requeue", "Pending"} 
local date = "%Y-%m-%d %H:%M:%S"


local function todate (epoch)
  return os.date (date, epoch)
end

local function cpu_ms (cpu)
  return string.format ("%0.3f", cpu * 1000)
end

local function rhs (text)
  return {text, style="text-align:right"}  -- only works in table.row/header calls
end

-- hms()  converts seconds to hours, minutes, seconds [, milliseconds] for display
local function dhms (x, full, milliseconds)
  local y = {}
  local time = "%s %02d:%02d:" .. (milliseconds and "%06.3f" or "%02.0f" ) 
  for _, f in ipairs {60, 60, 24} do
    y[#y+1] = x % f
    x = math.floor (x / f)
  end
  x = (x == 0) and '' or x .. ','      -- zero days shows blank
  local full_dhms = time: format (x, y[3], y[2],y[1])
  if not full then full_dhms = full_dhms: match "^[0:,%s]*(%d.*)" end
  return full_dhms
end

-- sorted version of the pairs iterator
-- use like this:  for a,b in sorted (x, fct) do ... end
-- optional second parameter is sort function cf. table.sort
local function sorted (x, fct)
  fct = fct or function(a, b) 
    if type(a) ~= type(b) then a,b = tostring(a), tostring(b) end
    return a < b 
  end
  local y, i = {}, 0
  for z in pairs(x) do y[#y+1] = z end
  table.sort (y, fct) 
  return function ()
    i = i + 1
    local z = y[i]
    return z, x[z]  -- if z is nil, then x[z] is nil, and loop terminates
  end
end

-----------------------------

local function html5_title (x) return html5.h4 {x} end
local function red (x) return ('<font color="crimson">%s</font>'): format (x)  end
local function status_number (n) if n ~= 200 then return red (n) end; return n end


-- sort table list elements by first index, then number them in sequence
local function sort_and_number (list)
  table.sort (list, function (a,b) return a[1] < b[1] end)
  for i, row in ipairs (list) do row[1] = i end
  return list
end

 
local function sorted_table (href)
  href = href .. "&sort=" 
  local cache_sort_direction = {} -- sort state for cache table columns (stateful... sorry!)
  local previous_key = 1          -- ditto
  local function columns (titles)
    local header = {}
    for i, title in ipairs (titles) do
      header[i] = html5.a {title, href = href .. i}
    end
    return header
  end
  local function sort (info, key)
    key = tonumber(key)
    if key then 
      if key ~= 0 then 
        cache_sort_direction[key] = not cache_sort_direction[key]     -- 0 retains current sort order
      else
        key = previous_key
      end
    else
      key = 1
      cache_sort_direction = {}    -- clear the sort direction
    end
    previous_key = key
    cache_sort_direction[1] = nil     -- never toggle first column
    local reverse = cache_sort_direction[key]
    local function in_order (a,b) 
      a, b = a[key] or tostring(a), b[key] or tostring(b)
      if type(a) ~= type(b) then a,b = tostring(a), tostring(b) end
      local sort
      if reverse then sort = a > b else sort = a < b end  -- note that a > b is not the same as not (a < b)
      return sort
    end
    if key then table.sort (info, in_order) end
  end
  return {
    columns = columns,
    sort = sort,
  }
end

local sorted_joblist = sorted_table "/console?page=jobs&table=scheduled"
local sorted_expired = sorted_table "/console?page=jobs&table=expired"

local function joblist (p)
--  local columns = {'#', "date / time", "device", "status", "run", "cpu(ms)", "job #", "info", "notes"}
  local columns = {'#', "date / time", "device", "status", "run", "hh:mm:ss.sss", "job #", "info", "notes"}
  local function format_rows (tbl, list)
    local milli = true
    for i, row in ipairs (list) do
      row[1] = i
--      row[6] = rhs (cpu_ms (row[6]))
      row[6] = rhs (dhms (row[6], nil, milli))
      row[7] = rhs (row[7])
      tbl.row (row)
    end
  end
  local s = sorted_joblist
  local w = sorted_expired
  local t = html5.table()
  local x = html5.table()
  t.header (s.columns (columns))
  x.header (w.columns (columns))
  local jlist, xlist = {}, {}
  for jn, j in pairs (scheduler.job_list) do
    local status = state[j.status] or ''
    local n = j.logging.invocations
    local tbl = scheduler.exit_state[j.status] and xlist or jlist
    tbl[#tbl+1] = {j.expiry, todate(j.expiry + 0.5), j.devNo or "system", status, n, 
                          j.logging.cpu, -- cpu time in seconds, here
                          jn, j.type or '?', j.notes or ''}
  end
  local col = tonumber (p.sort) or 1
  s.sort (jlist, p.table == "scheduled" and col or 0)
  w.sort (xlist, p.table == "expired"   and col or 0)
  format_rows (t, jlist)
--  table.sort (xlist, function (a,b) return a[1] > b[1] end)
  format_rows (x, xlist)
  if #xlist == 0 then x.row {{"--- none ---", colspan = 9}} end
  local div = html5.div {html5_title "Scheduled Jobs", t, 
    html5.br(), html5_title "Completed Jobs", html5.h5 {"(within last three minutes)"}, x}
  return div
end

local function delaylist ()
  local t = html5.table()
  t.header {"#", "date / time", "device", "status", "hh:mm:ss", "info"}
  local dlist = {}
  for _,b in pairs (scheduler.delay_list()) do
    local delay = math.floor (b.delay + 0.5)
    dlist[#dlist+1] = {b.time, todate(b.time), b.devNo, "Delay", delay, "callback: " .. (b.type or '')}
  end
  for _, row in ipairs (sort_and_number(dlist)) do
    row[5] = rhs (dhms(row[5]))
    t.row (row)
  end
  local div = html5.div {html5_title "Delayed Callbacks", t}
  return div
end

local function plugins ()
  local milli = true
  local cpu = scheduler.system_cpu()
  local uptime = timers.timenow() - timers.loadtime
  local percent = cpu * 100 / uptime
  percent = ("%0.1f"): format (percent)
  
  local d = html5.table()
  d.header { {"Plugin CPU usage (" .. percent .. "% system load)", colspan = 6, 
      title = "Plugin CPU is for code run in device context only"} }
  d.header {'#', "device", "status", "hh:mm:ss.sss", "name", "message"}
  local i = 0
  for n, dev in sorted (luup.devices) do
    local cpu = dev.attributes["cpu(s)"]
    if cpu then 
      i = i + 1
      d.row {i, n, dev.status, 
        rhs (dhms(cpu, nil, milli)), dev.description:match "%s*(.+)", dev.status_message or ''} 
    end
  end

  local t = html5.table()
  t.header { {"Plugin CPU usage at startup", colspan = 8, title = "Job CPU is total of device and system times"} }
--  t.header {"#", "date / time", "device", "status", "cpu(ms)", "job #", "info", "notes"}
  t.header {"#", "date / time", "device", "status", "hh:mm:ss.sss", "job #", "info", "notes"}
  local jlist = {}
  for jn, b in pairs (scheduler.startup_list) do
    local status = state[b.status] or ''
    if status ~= "Done" then status = red (status) end
    jlist[#jlist+1] = {b.expiry, todate(b.expiry + 0.5), b.devNo or "system", 
      status, b.logging.cpu, jn, b.type or '?', b.notes or ''}
  end
  for _, row in ipairs (sort_and_number(jlist)) do
    row[5] = rhs (dhms(row[5], nil, milli))
    t.row (row)
  end
  local div = html5.div {html5_title "Plugins", d, html5.br (), html5_title "Startup Jobs", t}
  return div
end

local function watchlist ()
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
  t.header {'#', "dev", "callback", "watching"}
  for _, row in ipairs (sort_and_number(W)) do
    t.row (row)
  end
  local div = html5.div {html5_title "Variable Watches", t}
  return div
end

local function printlog (p)
--    2019.03.22   use xml.escape() in preference
--    local fwd = {['<'] = "&lt;", ['>'] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;", ['&'] = "&amp;"}
--    local function escape (x) return (x: gsub ([=[[<>"'&]]=], fwd)) end
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
    local pre = html5.pre {xml.escape (x)}
    local div = html5.div {html5_title (name), pre}
    return div
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
  local pattern = "backup%.openLuup%-%w+%-([%d%-]+)%.?%w*"
  local files = get_matching_files_from ("backup/", pattern)
  local t = html5.table ()
  t.header {"yyyy-mm-dd", "(kB)", "filename"}
  for _,f in ipairs (files) do 
    local hyperlink = html5.a {
      href = "cgi-bin/cmh/backup.sh?retrieve="..f.name, 
      download = f.name: gsub (".lzap$",'') .. ".json",
      f.name}
    t.row {f.date, f.size, hyperlink} 
  end
  local div = html5.div { html5_title ("Backup directory: ", dir), t} 
  return div
end

local function devname (d)
  d = tonumber(d) or 0
  local name = (luup.devices[d] or {}).description or 'system'
  name = name: match "^%s*(.+)"
  local number = table.concat {'[', d, '] '}
  return number .. name
end

local function connectionsTable (iprequests)
  local t = html5.table ()
  t.header { {"Received connections:", colspan=3} }
  t.header {"IP address", "#connects", "date / time"}
  for ip, req in pairs (iprequests) do
    t.row {ip, req.count, todate(req.date)}
  end
  if t.length() == 0 then t.row {'', "--- none ---", ''} end
  return t
end


local function httplist ()    
  local function requestTable (requests, title, columns)
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
        t.row {name, count, status_number(status)}
      end
    end
    if t.length() == 0 then t.row {'', "--- none ---", ''} end
    return t
  end
  
  local div = html5.div { html5_title "HTTP Web Server", 
      connectionsTable (http.iprequests),   
      requestTable (http.http_handler, "/data_request?", {"id=... ", "#requests  ","status"}),
      requestTable (http.cgi_handler, "CGI requests", {"URL ", "#requests  ","status"}),
      requestTable (http.file_handler, "File requests", {"filename ", "#requests  ","status"}),
    }
  return div
end

local function smtplist ()
  local none = "--- none ---"
  
  local function sortedTable (title, info, ok)
    local t = html5.table ()
    t.header { {title, colspan = 3} }
    t.header {"Address", "#messages", "for device"}
    local index = {}
    for ip in pairs (info) do index[#index+1] = ip end
    table.sort (index)    -- get the email addresses into order
    for _,ip in ipairs (index) do
      local dest = info[ip]
      local name = devname (dest.devNo)
      if ok(ip) then 
        t.row {ip, dest.count, name}
      end
    end
    if t.length() == 0 then t.row {'', none, ''} end
    return t
  end
  
  local t = html5.table ()
  t.header {{ "Blocked senders:", colspan=2 }}
  t.header {"eMail address","#attempts"}
  for email in pairs (smtp.blocked) do
    t.row {email, '?'}
  end
  if t.length() == 0 then t.row {'', none, ''} end
  
  local div = html5.div { html5_title "SMTP eMail Server",
    connectionsTable (smtp.iprequests),
    sortedTable ("Registered email sender IPs:", smtp.destinations, function(x) return not x:match "@" end),
    sortedTable ("Registered destination mailboxes:", smtp.destinations, function(x) return x:match "@" end),
    t }
  
  return div
end

local function pop3list ()
  local T = html5.div {}
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
    T[#T+1] = t
  end
  
  local div = html5.div {html5_title "POP3 eMail Server", 
    connectionsTable (ioutil.udp.iprequests), T}
  
  return div
end

local function udplist ()
  local t0 = html5.table ()
  t0.header { {"Registered listeners:", colspan = 3} }
  t0.header {"port", "#datagrams", "for device"}
  local list = {}
  for port, x in pairs(ioutil.udp.listeners) do
    local dname = devname (x.devNo)
    list[#list+1] = {port = port, n = x.count, dev = dname}
  end
  table.sort (list, function (a,b) return a.port < b.port end)
  for _,x in ipairs (list) do 
    t0.row {x.port, x.n, x.dev} 
  end
  if t0.length() == 0 then t0.row {'', "--- none ---", ''} end 
  
  local t = html5.table()
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
  
  local div = html5.div {html5_title "UDP datagram Listeners", 
    connectionsTable (ioutil.udp.iprequests), 
    t0, t}
  
  return div
end


local function sockets ()
  local cols = {}
  local sock_drawer = scheduler.get_socket_list()    -- list is indexed by socket !!
  for sock, x in pairs (sock_drawer) do
    local sockname = table.concat {tostring(x.name), ' ', tostring(sock)}
    cols[#cols+1] = {x.time, os.date(date, x.time), x.devNo or 0, sockname}
  end
  table.sort (cols, function (a,b) return a[1] > b[1] end)
  
  local t = html5.table()
  t.header {"#", "date / time", "device", "socket"}
  for i,x in ipairs (cols) do x[1] = i; t.row (x) end
  if #cols == 0 then t.row {0, '', "--- none ---", ''} end
  
  local div = html5.div {html5_title "Watched Sockets", t}
  return div
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
      return t
    end
    local T = html5.div {}
    for d, idx in pairs (lookup) do
      T[#T+1] = sorted(idx, boxmsg: format (d, devname(d)))
    end
    T[#T+1] = sorted (tbl, "Shared items:")
    return T
  end
  
  local div = html5.div {html5_title "Sandboxed system tables"}
  for n,v in pairs (_G) do
    local meta = ((type(v) == "table") and getmetatable(v)) or {}
    if meta.__newindex and meta.__tostring and meta.lookup then   -- not foolproof, but good enough?
      div[#div+1] = html5.p { n, ".sandbox"} 
      div[#div+1] = format(v)
    end
  end
  return div
end

local function images ()
  local files = get_matching_files_from ("images/", '^[^%.]+%.[^%.]+$')     -- *.*
  local t = html5.table ()
  t.header {'#', "filename"}
  for i,f in ipairs (files) do 
    t.row {i, html5.a {href="/images/" .. f.name, target="image", f.name}}
  end
  local div = html5.div {
      html5_title "Images",
      html5.nav {t}, 
      html5.article {[[<iframe name="image" width="50%" >]]},
    }
  return div
end

local function trash ()
  local files = get_matching_files_from ("trash/", '^[^%.]+%.[^%.]+$')     -- *.*
  local t = html5.table ()
  t.header {'#', "filename", "size"}
  for i,f in ipairs (files) do
    t.row {i, f.name, f.size}
  end
  if t.length() == 0 then t.row {'', "--- none ---", ''} end
  local div = html5.div {html5_title "Trash", t}
  return div
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

local function historian (_, req)
  
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
      
  local t = html5.table()
  t.header {"device ", "service", "#points", "value",
    {"variable (archived if checked)", title="note that the checkbox field \n is currently READONLY"} }
  
--  local link = [[<a href="/render?target=%s&from=%s">%s</a>]]
  local link = [[<a href="]] .. req.script_name .. [[?page=render&target=%s&from=%s">%s</a>]]
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
      --
--[[

<form action="/action_page.php" name="foo" method="get" onChange="foo.submit()">
  Points:
  <input type="range" name="points" min="0" max="100">
  <input type="submit">
</form>

--]]
      --
      t.row { {dname, colspan = 5, style = "font-weight: bold"} }
    end
    prev = dname
    local check = x.archived and "checked" or ''
    t.row {'', v.srv: match "[^:]+$" or v.srv, h, v.value, tick: format (check, vname)}
  end
  
  local t0 = html5.table()
  t0.header { {"Summary:", colspan = 2, title = "cache statistics since reload"} }
  t0.row {"total # device variables", rhs (N)}
  t0.row {"total # variables with history", rhs (#H)}
  t0.row {"total # history points", rhs (T)}
  
  local div = html5.div {html5_title "Data Historian Cache Memory", t0, t}
  return div
end


local function database (_, req)
  local folder = luup.attr_get "openLuup.Historian.Directory"
  
  if not folder then
    return "On-disk archiving not enabled"
  end
  
  local whisper_edit = lfs.attributes "cgi/whisper-edit.lua"    -- is the editor there?
  
  -- stats
  local s = hist.stats
  local tot, cpu, wall = s.total_updates, s.cpu_seconds, s.elapsed_sec
  
  local cpu_rate   = cpu / tot * 1e3
  local wall_rate  = wall / tot * 1e3
  local write_rate = 60 * tot / (timers.timenow() - timers.loadtime)
  
  local function dp1(x) return rhs (x - x % 0.1) end
  
  local t0 = html5.table ()
  t0.header { {"Summary: " .. folder, colspan = 2, title="disk archive statistics since reload"} }
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
        a.fct = i.aggregationMethod
        a.retentions = tostring(i.retentions) -- text representation of archive retentions
        a.updates = tally[filename] or ''
        local finderName, devnum, description = hist.metrics.pkdsv2finder (pk,d,s,v)
        a.finderName = finderName
        a.devnum = devnum or ''
        a.description = description or "-- unknown --"
        local links = {}
        if a.finderName then 
--          local link = [[<a href="/render?target=%s&from=-%s">%s</a>]]      -- use relative time format
          local link = [[<a href="]] .. req.script_name .. [[?page=render&target=%s&from=-%s">%s</a>]] 
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
  
  local function link_to_editor (name)
    local link = name
    if whisper_edit then 
      link = html5.a {
        href = table.concat {"/cgi/whisper-edit.lua?target=", folder, name, ".wsp"}, 
                                target = "_blank", name}
    end
    return link
  end
  
  local t = html5.table ()
  t.header {'', "archives", "(kB)", "fct", "#updates", 
    {"filename (node.dev.srv.var)", title = "hyperlink to Whisper file editor, if present"} }
  local prev
  local N,T = 0,0
  for _,f in ipairs (files) do 
    N = N + 1
    T = T + f.size
    local devnum = f.devnum     -- openLuup device number (if present)
    if devnum ~= prev then 
      t.row { {html5.strong {'[', f.devnum, '] ', f.description}, colspan = 6} }
    end
    prev = devnum
    t.row {'', f.links or f.retentions, f.size, f.fct, f.updates, link_to_editor (f.shortName)}
  end
  
  T = T / 1000;
  t0.row {"total size (Mb)", rhs (T - T % 0.1)}
  t0.row {"total # files", rhs (N)}
  t0.row {"total # updates", rhs (tot)}
  
  local div = html5.div {html5_title "Data Historian Disk Database", t0, t}
  return div
end

local function plugin_globals ()
  local ignored = {"ABOUT", "_NAME", "lul_device"}
  local ignore = {}
  for _, name in pairs (ignored) do ignore[name] = true end
  local t = html5.table ()
  t: header {"device", "variable", "value"}
  for dno,d in pairs (luup.devices) do
    local env = d.environment
    if env then
      local x = {}
      for n,v in pairs (env or {}) do 
        if not _G[n] and not ignore[n] and type(v) ~= "function" then x[n] = v end
      end
      if next(x) then
        local dname = devname (dno)
        t: row {{html5.strong {dname}, colspan = 3}}
        for n,v in sorted (x) do
          t: row {'', n, tostring(v)}
        end
      end
    end
  end    
  local div = html5.div {html5_title "Plugin Globals", t}
  return div
end

local function device_states ()
  local ignored = {"commFailure"}
  local ignore = {}
  local maxlength = 40
  for _, name in pairs (ignored) do ignore[name] = true end
  local t = html5.table ()
  t: header {"device", "state", "value"}
  for dno,d in sorted (luup.devices, function(a,b) return a < b end) do   -- nb. not default string sort
    local info = {}
    if not d.invisible then
      local states = d: get_shortcodes()
      for n, v in pairs (states) do
        if n and not ignore[n] then info[n] = v end
      end
      if next(info) then
        local dname = devname (dno)
        t: row {{html5.strong {dname}, colspan = 3}}
        for n,v in sorted (info) do
          local s = tostring(v)
          local number = tonumber(v)
          if number and number > 1234567890 then
            s = os.date ("%c", number)
          else
            if #s > maxlength then s = s: sub(1, maxlength) .. "..." end
          end
          t: row {'', n, s}
        end
      end
    end
  end
  local div = html5.div {html5_title "Device States", t}
  return div
end

local sorted_cache = sorted_table "/console?page=cache"

local function cache (p)
  local s = sorted_cache
  local t = html5.table ()
  t: header (s.columns {'#', "last access", "# hits", "bytes", "filename"})
  
  local N, H = 0, 0
  local strong = html5.strong
  local info = {}
  for name in vfs.dir() do 
    local v = vfs.attributes (name) 
    local d = (v.access ~= 0) and os.date (date, v.access) or ''
    info[#info+1] = {name, d, v.hits, v.size, name} 
  end
  
  s.sort (info, p.sort)
  for i, row in ipairs (info) do
    H = H + row[3]      -- hits accumulator
    N = N + row[4]      -- size accumulator
    row[1] = i          -- replace primary sort key with line number
    row[4] = rhs (row[4])
    t.row (row)
  end
  
  t:row { '', '', strong {H}, strong {math.floor (N/1000 + 0.5), " (kB)"}, strong {"Total"}}
  local div = html5.div {html5_title "File System Cache", t}
  return div
end

local function parameters ()
  local info = luup.attr_get "openLuup"
  local t = html5.table ()
  t.header {"section", "name", "value" }
  for n,v in sorted (info) do 
    if type(v) ~= "table" then
      t.row {n, '', tostring(v)}
    else
      t.row { {n, colspan = 3, style = "font-weight: bold"} }
      for m,u in sorted (v) do
        t.row { '', m, tostring(u) }
      end
    end
  end
  local div = html5.div {html5_title "openLuup Parameters", t}
  return div
end

local function render (p, req)
  local background = p.background or "GhostWhite"
  local iframe = html5.iframe {
    height = "450px", width = "96%", 
    style= "margin-left: 2%; margin-top:30px; background-color:"..background,
    src="/render?" .. req.query_string,
    }
  local div = html5.div {html5_title "Graphics", iframe}
  return div
end

local function tabulate (info)
  local t
  if type(info) == "table" then
    t = html5.table ()
    t: header {"name", "value"}
    for n,v in sorted (info) do
      t: row {n, tabulate (v)}
    end
  else
    t = tostring(info)
  end
  return t
end

local function about () 
  local ABOUTopenLuup = luup.devices[2].environment.ABOUT   -- use openLuup about, not console
  local t = html5.table ()
  for a,b in sorted (ABOUTopenLuup) do
    b = tostring(b)
--    if b: lower() : match "^http" then b = html5.a {href = b, b} end
    b = b: gsub ("http%S+",  '<a href=%1 target="_blank">%1</a>')
    t.row {{a, style = "font-weight: bold"}, 
      html5.pre {b, style = "margin-top: 0.5em; margin-bottom: 0.5em;"}}
  end
  local div = html5.div {html5_title "About...", t}
  return div
end  

local pages = {
  about   = about,
  backups = backups,
  database = database,
  delays  = delaylist,
  images  = images,
  jobs    = joblist,
  log     = printlog,
  plugins = plugins,
  watches = watchlist,
  http    = httplist,
  smtp    = smtplist,
  pop3    = pop3list,
  sockets = sockets,
  sandbox = sandbox,
  trash   = trash,
  udp     = udplist,
  cache   = cache,
  render  = render,
  
  historian   = historian,
  parameters  = parameters,
  globals     = plugin_globals,
  states     = device_states,
  
--    userdata  = function (p) return title "Userdata", preformatted (requests.user_data (_, p)) end,
--    status    = function (p) return title "Status",   preformatted (requests.status (_, p)) end,
--    sdata     = function (p) return title "Sdata",    preformatted (requests.sdata (_, p)) end,
  
}

  
local a, body, div, footer, head, style, title = 
  html5.a, html5.body, html5.div, html5.footer, html5.head, html5.style, html5.title

local button, pre = html5.button, html5.pre
local hr = html5.hr {style = "color:Sienna;"}

local menu = div {class="menu", style="background:DarkGrey;",
  div {
    div {
      class="dropdown", 
      style="vertical-align:middle; height:60px;",
      a {href="/data_request?id=lr_ALTUI_Handler&command=home#", target="_blank",  vfs.read "icons/openLuup.svg"}},
    
    div {class="dropdown",
      button {class="dropbtn", "openLuup"},
      div {class="dropdown-content",
        a {class="left", href="/console?page=about", "About"},
        a {class="left", href="/console?page=parameters", "Parameters"},
        a {class="left", href="/console?page=historian", "Historian"},
        hr,
        a {class="left", href="/console?page=globals", "Globals"},
        a {class="left", href="/console?page=states", "States"},
      }},

    div {class="dropdown",
      button {class="dropbtn", "Files"},
      div {class="dropdown-content",
        a {class="left", href="/console?page=backups", "Backups"},
        a {class="left", href="/console?page=images", "Images"},
        a {class="left", href="/console?page=database", "History DB"},
        a {class="left", href="/console?page=cache", "Cache"},
        a {class="left", href="/console?page=trash", "Trash"},
      }},

    div {class="dropdown",
      button {class="dropbtn", "Scheduler"},
      div {class="dropdown-content",
        a {class="left", href="/console?page=jobs", "Jobs"},
        a {class="left", href="/console?page=delays", "Delays"},
        a {class="left", href="/console?page=watches", "Watches"},
        a {class="left", href="/console?page=sockets", "Sockets"},
        a {class="left", href="/console?page=sandbox", "Sandboxes"},
        a {class="left", href="/console?page=plugins", "Plugins"},
      }},

    div {class="dropdown",
      button {class="dropbtn", "Servers"},
      div {class="dropdown-content",
        a {class="left", href="/console?page=http", "HTTP Web"},
        a {class="left", href="/console?page=smtp", "SMTP eMail"},
        a {class="left", href="/console?page=pop3", "POP3 eMail"},
        a {class="left", href="/console?page=udp", "UDP  datagrams"},
      }},

    div {class="dropdown",
      button {class="dropbtn", "Logs"},
      div {class="dropdown-content",
        a {class="left", href="/console?page=log", "Log"},
        a {class="left", href="/console?page=log&version=1", "Log.1"},
        a {class="left", href="/console?page=log&version=2", "Log.2"},
        a {class="left", href="/console?page=log&version=3", "Log.3"},
        a {class="left", href="/console?page=log&version=4", "Log.4"},
        a {class="left", href="/console?page=log&version=5", "Log.5"},
        a {class="left", href="/console?page=log&version=startup", "Startup Log"},
    }}},
  
}


----------------------------------------
-- run()
--

function run (wsapi_env)
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax

  local req = wsapi.request.new (wsapi_env)
  local p = req.GET 
  local page = pages[p.page] or function () end

  local html = html5.document { 
      head {'<meta charset="utf-8">',
        title {"Console"},
        style {vfs.read "openLuup_console.css"}},
    
      body {
        menu,
        div {class="content",
          page (p, req),
          footer {"<hr/>", pre {os.date "%c"}},
    }}}
  
  local res = wsapi.response.new ()
  res: write (html)  
  return res: finish()
end

-----
