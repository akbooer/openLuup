#!/usr/bin/env wsapi.cgi

module(..., package.seeall)


ABOUT = {
  NAME          = "console.lua",
  VERSION       = "2019.06.07",
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
-- 2019.05.15  add number of callbacks to Delay and Watch tables
-- 2019.05.16  split HTTP request table in system- and user-defined
-- 2019.05.25  split Database tables into known and unknown devices
-- 2019.05.27  tabbed pages and new layout
-- 2019.06.04  use CCS Framework W3.css, lightweight with no JavaScript libraries.  Perfect match!


--  WSAPI Lua implementation

local lfs       = require "lfs"                   -- for backup file listing, and historian files
local vfs       = require "openLuup.virtualfilesystem"
local luup      = require "openLuup.luup"         -- not automatically in scope for CGIs
local scheduler = require "openLuup.scheduler"    -- for job_list, delay_list, etc...
local userdata  = require "openLuup.userdata"     -- for device user_data
local http      = require "openLuup.http"
local smtp      = require "openLuup.smtp"
local pop3      = require "openLuup.pop3"
local ioutil    = require "openLuup.io"
local hist      = require "openLuup.historian"    -- for disk archive stats   
local timers    = require "openLuup.timers"       -- for startup time
local whisper   = require "openLuup.whisper"
local wsapi     = require "openLuup.wsapi"        -- for response library
local loader    = require "openLuup.loader"       -- for static data (devices page)
local json      = require "openLuup.json"         -- for console_menus.json
local xml       = require "openLuup.xml"          -- for xml.escape(), and...
local html5     = xml.html5                       -- html5 and svg libraries

-- get local copy of w3.css if we haven't got one already
-- so that we can work offline if required
if not loader.raw_read "w3.css" then 
  local https = require "ssl.https"
  local ltn12 = require "ltn12"
  local css = io.open ("www/w3.css", "wb")
  https.request{ 
    url = "https://www.w3schools.com/w3css/4/w3.css", 
    sink = ltn12.sink.file (css),
  }
end


local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local script  -- name of this CGI script
local function selfref (...) return table.concat {script, '?', ...} end   -- for use in hrefs

local state =  {[-1] = "No Job", [0] = "Wait", "Run", "Error", "Abort", "Done", "Wait", "Requeue", "Pending"} 

local function todate (epoch) return os.date ("%Y-%m-%d %H:%M:%S", epoch) end


-- formats a value nicely
local function nice (x, maxlength)
  maxlength = maxlength or 50
  local s = tostring (x)
  local number = tonumber(s)
  if number and number > 1234567890 then s = todate (number) end
  if #s > maxlength then s = s: sub(1, maxlength) .. "..." end
  return s
end

local function dev_or_scene_name (d, tbl)
  d = tonumber(d) or 0
  local name = (tbl[d] or {}).description or 'system'
  name = name: match "^%s*(.+)"
  local number = table.concat {'[', d, '] '}
  return number .. name
end

local function devname (d) return dev_or_scene_name (d, luup.devices) end
local function scene_name (d) return dev_or_scene_name (d, luup.scenes) end

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

-----------------------------

local function html5_title (x) return html5.h4 {x} end
local function red (x) return ('<font color="crimson">%s</font>'): format (x)  end
local function status_number (n) if n ~= 200 then return red (n) end; return n end
local function page_wrapper (title, ...) return html5.div {html5_title (title), ...} end


-- make a simple HTML table from data
local function create_table_from_data (columns, data, formatter)
  local tbl = html5.table {class="w3-small"}
  tbl.header (columns)
  for i,row in ipairs (data) do 
    if formatter then formatter (row, i) end  -- pass the formatter both current row and row number
    tbl.row (row) 
  end
  if #data == 0 then tbl.row {"--- none ---"} end
  return tbl
end

-- sort table list elements by first index, then number them in sequence
local function sort_and_number (list)
  table.sort (list, function (a,b) return a[1] < b[1] end)
  for i, row in ipairs (list) do row[1] = i end
  return list
end

 
local function sorted_table ()
  local cache_sort_direction = {} -- sort state for cache table columns (stateful... sorry!)
  local previous_key = 1          -- ditto
  local function columns (titles)
    local header = {}
    for i, title in ipairs (titles) do
      header[i] = html5.a {title, href = selfref ("sort=", i)}
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

-- text display

local ace = {
  root = "www/ace-builds/src-noconflict",
  }

ace.present = lfs.attributes (ace.root)

function ace.editor (text, language)
  return html5.div {class = "", html5.pre {text}}
end
--
-- Pages
--

local sorted_joblist = sorted_table ()
local sorted_expired = sorted_table ()

local pages = {}

-- returns unformatted data for both running and completed jobs
-- also metatable function to format a final table
-- and a default sort order
local function jobs_tables (p, running, title)
  local jlist = {}
  for jn, j in pairs (scheduler.job_list) do
    local status = state[j.status] or ''
    local n = j.logging.invocations
    local ok = scheduler.exit_state[j.status]
    if running then ok = not ok end
    if ok then
      jlist[#jlist+1] = {j.expiry, todate(j.expiry + 0.5), j.devNo or "system", status, n, 
                          j.logging.cpu, -- cpu time in seconds, here
                          jn, j.type or '?', j.notes or ''}
    end
  end
  -----
  local columns = {'#', "date / time", "device", "status", "run", "hh:mm:ss.sss", "job #", "info", "notes"}
  table.sort (jlist, function (a,b) return a[1] > b[1] end)
  -----
  local milli = true
  local tbl = create_table_from_data (columns, jlist,
    function (row, i)
      row[1] = i
      row[6] = rhs (dhms (row[6], nil, milli))
      row[7] = rhs (row[7])
    end)
  return html5.div {class = "w3-responsive", page_wrapper(title, tbl) }	-- may be wide, let's scroll sideways
end

pages.running   = function (p) return jobs_tables (p, true,  "Jobs Currently Running") end
pages.completed = function (p) return jobs_tables (p, false, "Jobs Completed within last 3 minutes") end


function pages.plugins ()
  local i = 0
  local data = {}
  for n, dev in pairs (luup.devices) do
    local cpu = dev.attributes["cpu(s)"]
    if cpu then 
      i = i + 1
      data[i] = {i, n, dev.status, cpu, dev.description:match "%s*(.+)", dev.status_message or ''} 
    end
  end
  -----
  local columns = {'#', "device", "status", "hh:mm:ss.sss", "name", "message"}
  table.sort (data, function (a,b) return a[2] < b[2] end)
  -----
  local milli = true
  local cpu = scheduler.system_cpu()
  local uptime = timers.timenow() - timers.loadtime
  local percent = cpu * 100 / uptime
  percent = ("%0.1f"): format (percent)
  local tbl = html5.table {class = "w3-small"}
  tbl.header (columns)
  for _, row in ipairs(data) do
    row[4] = rhs (dhms(row[4], nil, milli))
    tbl.row (row) 
  end
  local title = "Plugin CPU usage (" .. percent .. "% system load)"
  return page_wrapper(title, tbl)
end


function pages.startup ()
  local jlist = {}
  for jn, b in pairs (scheduler.startup_list) do
    local status = state[b.status] or ''
    jlist[#jlist+1] = {b.expiry, todate(b.expiry + 0.5), b.devNo or "system", 
      status, b.logging.cpu, jn, b.type or '?', b.notes or ''}
  end
  -----
  local columns = {"#", "date / time", "device", "status", "hh:mm:ss.sss", "job #", "info", "notes"}
  table.sort (jlist, function (a,b) return a[2] < b[2] end)
  -----
  local milli = true
  local tbl = html5.table {class = "w3-small"}
  tbl.header (columns)
  for i, row in ipairs (jlist) do
    row[1] = i
    if row[4] ~= "Done" then row[4] = red (row[4]) end
    row[5] = rhs (dhms(row[5], nil, milli))
    tbl.row (row)
  end
  local title = "Plugin Startup Jobs CPU usage"
  return page_wrapper(title, tbl)
end


-- call_delay
function pages.delays ()
  local dlist = {}
  for _,b in pairs (scheduler.delay_list()) do
    local delay = math.floor (b.delay + 0.5)
    local calls = scheduler.delay_log[tostring(b.callback)] or 0
    dlist[#dlist+1] = {b.time, todate(b.time), b.devNo, 
      calls, "Delay", delay, "callback: " .. (b.type or '')}
  end
  -----
  local columns = {"#", "date / time", "device", "#calls", "status", "hh:mm:ss", "info"}
  sort_and_number(dlist)  
  -----
  local tbl = create_table_from_data (columns, dlist,
    function (row)    -- formatter function to decorate specific items
      row[6] = rhs(dhms (row[6]))
    end)
  return page_wrapper("Callbacks: Delays", tbl)
end
 
-- variable_watch
  
function pages.watches ()
  local W = {}
  local function isW (w, d,s,v)
    if next (w.watchers) then
      for _, what in ipairs (w.watchers) do
        local calls = scheduler.watch_log[what.hash] or 0
        W[#W+1] = {what.devNo, what.devNo, what.name or '?', calls, table.concat ({d,s or '*',v or '*'}, '.')}
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
  -----
  local columns = {'#', "dev", "callback", "#calls", "watching"}
  -----
  local tbl = create_table_from_data (columns, W)
  return page_wrapper("Callbacks: Variable Watches", tbl)
end

-- system parameters
function pages.parameters ()
  local data = {}
  local columns = {"section", "name", "value" }
  local info = luup.attr_get "openLuup"
  for n,v in sorted (info) do 
    if type(v) ~= "table" then
      data[#data+1] = {n, '', tostring(v)}
    else
      data[#data+1] =  { {n, colspan = #columns, style = "font-weight: bold"} }
      for m,u in sorted (v) do
        data[#data+1] =  { '', m, tostring(u) }
      end
    end
  end
  local tbl = create_table_from_data (nil, data)
  return page_wrapper("openLuup Parameters (from Lua Startup)", tbl)
end

-- system parameters
function pages.top_level ()
  local unwanted = {ShutdownCode = true, StartupCode = true}
  local t = html5.table {class = "w3-small"}
--  t.header {"attribute", "value"}
  local attributes = userdata.attributes
  for n,v in sorted (attributes) do
    if type(v) ~= "table" and not unwanted[n] then t.row {n, nice(v) } end
  end
  return page_wrapper ("Top-level Attributes", t)
end

-- plugin globals
  
function pages.globals ()
  local columns = {"device", "variable", "value"}
  local data = {}
  local ignored = {"ABOUT", "_NAME", "lul_device"}
  local ignore = {}
  for _, name in pairs (ignored) do ignore[name] = true end
  for dno,d in pairs (luup.devices) do
    local env = d.environment
    if env then
      local x = {}
      for n,v in pairs (env or {}) do 
        if not _G[n] and not ignore[n] and type(v) ~= "function" then x[n] = v end
      end
      if next(x) then
        local dname = devname (dno)
        data[#data+1] = {{html5.strong {dname}, colspan = #columns}}
        for n,v in sorted (x) do
          data[#data+1] = {'', n, tostring(v)}
        end
      end
    end
  end 
  local tbl = create_table_from_data (nil, data)
  return page_wrapper("Plugin Globals", tbl)
end

-- state table
function pages.states ()
  local columns = {"device", "state", "value"}
  local ignored = {"commFailure"}
  local ignore = {}
  for _, name in pairs (ignored) do ignore[name] = true end
  local data = {}
  for dno,d in sorted (luup.devices, function(a,b) return a < b end) do   -- nb. not default string sort
    local info = {}
    if not d.invisible then
      local states = d: get_shortcodes()
      for n, v in pairs (states) do
        if n and not ignore[n] then info[n] = v end
      end
      if next(info) then
        local dname = devname (dno)
        data[#data+1] = {{html5.strong {dname}, colspan = #columns}}
        for n,v in sorted (info) do
          data[#data+1] = {'', n, nice (v)}
        end
      end
    end
  end
  local tbl = create_table_from_data (nil, data)
  return page_wrapper("Device States (defined by service file short_names)", tbl)
end


-- backups
function pages.backups ()
  local columns = {"yyyy-mm-dd", "(kB)", "filename"}
  local dir = luup.attr_get "openLuup.Backup.Directory" or "backup/"
  local pattern = "backup%.openLuup%-%w+%-([%d%-]+)%.?%w*"
  local files = get_matching_files_from (dir, pattern)
  local data = {}
  for _,f in ipairs (files) do 
    local hyperlink = html5.a {
      href = "cgi-bin/cmh/backup.sh?retrieve="..f.name, 
      download = f.name: gsub (".lzap$",'') .. ".json",
      f.name}
    data[#data+1] = {f.date, f.size, hyperlink} 
  end
  local tbl = create_table_from_data (columns, data)
  local backup = html5.div {
    html5.a {class="w3-button w3-round w3-light-green", href = "cgi-bin/cmh/backup.sh?", target="_blank",
                "Backup Now"}}
  return page_wrapper("Backup directory: " .. dir, backup, tbl)
end

-- sandboxes
function pages.sandboxes ()               -- 2018.04.07
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
      local t = html5.table {class="w3-small w3-hoverable w3-card"}
      t.header {{title, colspan = 2}}
--      t.header {"name","type"}
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
  
  local div = html5.div {html5_title "Sandboxed system tables (by plugin)"}
  for n,v in pairs (_G) do
    local meta = ((type(v) == "table") and getmetatable(v)) or {}
    if meta.__newindex and meta.__tostring and meta.lookup then   -- not foolproof, but good enough?
      div[#div+1] = html5.p { n, ".sandbox"} 
      div[#div+1] = format(v)
    end
  end
  return div
end


--------------------------------


function pages.log (p)
  local page = p.page or ''  
  local name = luup.attr_get "openLuup.Logfile.Name" or "LuaUPnP.log"
  local ver = page: match "%.(.+)"
  if page == "startup_log" then
    name = "logs/LuaUPnP_startup.log"
  elseif ver then
    name = table.concat {name, '.', ver}
  end
  local pre
  local f = io.open (name)
  if f then
    local x = f:read "*a"
    f: close()
    pre = html5.pre {xml.escape (x)}
  end
  return page_wrapper(name, pre)
end

for i = 1,5 do pages["log." .. i] = pages.log end         -- add the older file versions
pages.startup_log = pages.log

-- generic connections table for all servers
local function connectionsTable (iprequests)
  local t = html5.table {class = "w3-small w3-card"}
  t.header { {"Received connections:", colspan=3} }
  t.header {"IP address", "#connects", "date / time"}
  for ip, req in pairs (iprequests) do
    t.row {ip, req.count, todate(req.date)}
  end
  if t.length() == 0 then t.row {'', "--- none ---", ''} end
  return t
end


function pages.http ()    
  local function requestTable (requests, title, columns, include_zero)
    local t = html5.table {class = "w3-small w3-card"}
    t.header { {title, colspan = 3} }
    t.header (columns)
    local calls = {}
    for name in pairs (requests) do calls[#calls+1] = name end
    table.sort (calls)
    for _,name in ipairs (calls) do
      local call = requests[name]
      local count = call.count
      local status = call.status
      if include_zero or (count and count > 0) then
        t.row {name, count or 0, status and status_number(status) or ''}
      end
    end
    if t.length() == 0 then t.row {'', "--- none ---", ''} end
    return t
  end
  
  local lu, lr = {}, {}     -- 2019.05.16 system- and user-defined requests
  for n,v in pairs (http.http_handler) do
    local tbl = n: match "^lr_" and lr or lu
    tbl[n] = v
  end
  
  return html5.div {
      html5_title "HTTP Web server (port 3480)",
      connectionsTable (http.iprequests),   
      requestTable (lu, "/data_request? (system)", {"id=lu_... ", "#requests  ","status"}),
      requestTable (lr, "/data_request? (user-defined)", {"id=lr_... ", "#requests  ","status"}, true),
      requestTable (http.cgi_handler, "CGI requests", {"URL ", "#requests  ","status"}),
      requestTable (http.file_handler, "File requests", {"filename ", "#requests  ","status"}),
    }
end

function pages.smtp ()
  local none = "--- none ---"
  
  local function sortedTable (title, info, ok)
    local t = html5.table {class = "w3-small w3-card"}
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
  
  local t = html5.table {class = "w3-small w3-card"}
  t.header {{ "Blocked senders:", colspan=2 }}
  t.header {"eMail address","#attempts"}
  for email in pairs (smtp.blocked) do
    t.row {email, '?'}
  end
  if t.length() == 0 then t.row {'', none, ''} end
  
  return html5.div {
    html5_title "SMTP eMail server",
    connectionsTable (smtp.iprequests),
    sortedTable ("Registered email sender IPs:", smtp.destinations, function(x) return not x:match "@" end),
    sortedTable ("Registered destination mailboxes:", smtp.destinations, function(x) return x:match "@" end),
    t }
end

function pages.pop3 ()
  local T = html5.div {}
  local header = "Mailbox '%s': %d messages, %0.1f (kB)"
  local accounts = pop3.accounts    
  for name, folder in pairs (accounts) do
    local mbx = pop3.mailbox.open (folder)
    local total, bytes = mbx: status()
    
    local t = html5.table {class = "w3-small w3-card w3-hoverable"}
    t.header { {header: format (name, total, bytes/1e3), colspan = 3 } }
    t.header {'#', "date / time", "size (bytes)"}
    
    local list = {}
    for _, size, _, timestamp in mbx:scan() do
      list[#list+1] = {t = timestamp, d = todate (timestamp), s = size}
    end
    table.sort (list, function (a,b) return a.t > b.t end)  -- newest first
    for i,x in ipairs (list) do 
      t.row {i, x.d, x.s} 
    end
    mbx: close ()
    if t.length() == 0 then t.row {'', "--- none ---", ''} end
    T[#T+1] = t
  end
  
  return html5.div {
    html5_title "POP3 eMail client server",
    connectionsTable (ioutil.udp.iprequests), T}
end

function pages.udp ()
  local t0 = html5.table {class = "w3-small w3-card"}
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
  
  local t = html5.table {class = "w3-small w3-card"}
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
  
  return html5.div {
    html5_title "UDP datagram ports",
    connectionsTable (ioutil.udp.iprequests), 
    t0, t}
end


function pages.sockets ()
  local data = {}
  local sock_drawer = scheduler.get_socket_list()    -- list is indexed by socket !!
  for sock, x in pairs (sock_drawer) do
    local sockname = table.concat {tostring(x.name), ' ', tostring(sock)}
    data[#data+1] = {x.time, todate (x.time), x.devNo or 0, sockname}
  end
  -----
  local columns = {"#", "date / time", "device", "socket"}
  table.sort (data, function (a,b) return a[1] > b[1] end)
  -----
  local t = create_table_from_data (columns, data, function (row) row[1] = 1 end)
  return page_wrapper ("Server sockets watched for incoming connections", t)
end


function pages.images (p)
  local files = get_matching_files_from ("images/", '^[^%.]+%.[^%.]+$')     -- *.*
  local data = {}
  for i,f in ipairs (files) do 
    data[#data+1] = {i, html5.a {href=selfref ("image=",i), f.name}}
  end
  local src = (files[tonumber(p.image)] or {}) .name
  if src then src = "images/" .. src end
  local index = create_table_from_data ({'#', "filename"}, data)
  local div = html5.div
  return div {
      html5_title "Image files in images/ folder",
      div {class = "w3-row",
      -- TODO: IMAGES
        div {class = "w3-container w3-quarter", index} ,
        div {class = "w3-container w3-rest", 
          html5.img {style="object-fit: contain;", width="70%", src=src}},
      }}
end


function pages.trash (p)
  -- empty?
  if (p.AreYouSure or '') :lower() :match "yes" then    -- empty the trash
    luup.call_action ("openLuup", "EmptyTrash", {AreYouSure = "yes"}, 2)
    local continue = html5.a {class="w3-button w3-round w3-green",
      href = selfref "page=trash", "Continue..."}
    return page_wrapper ("Trash folder being emptied", continue)
  end
  -- list files...
  local files = get_matching_files_from ("trash/", '^[^%.]+%.[^%.]+$')     -- *.*
  local data = {}
  for i,f in ipairs (files) do 
    data[#data+1] = {i, f.name, f.size}
  end
  local tbl = create_table_from_data ({'#', "filename", "size"}, data)
  local empty = html5.a {class="w3-button w3-round w3-red",
    onclick = "return confirm('Empty Trash: Are you sure?')", 
    href = selfref "page=trash&AreYouSure=yes", "Empty Trash"}
  return page_wrapper ("Files pending delete in trash/ folder", empty, tbl)
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

-- quick pass of variables with history
local function scan_cache ()
  local N = 0     -- total number of variables
  local T = 0     -- total number of cached history points
  local H = {}    -- variables with history
  for _,d in pairs (luup.devices) do
    for _,v in ipairs (d.variables) do 
      N = N + 1 
      local hist = v.history
      if hist and #hist > 2 then 
        H[#H+1] = v 
        T = T + #hist / 2
      end
    end
  end
  return H, N, T
end

function pages.summary ()
  local H, N, T = scan_cache()
  local t0 = html5.table {class = "w3-small"}
  t0.header { {"Cache statistics:", colspan = 2} }
  t0.row {"total # device variables", rhs (N)}
  t0.row {"total # variables with history", rhs (#H)}
  t0.row {"total # history points", rhs (T)}
  
  local folder = luup.attr_get "openLuup.Historian.Directory"
  if not folder then
    t0.header { {"Disk archiving not enabled", colspan = 2} }
  else
    -- disk archiving is enabled
    local s = hist.stats
    local tot, cpu, wall = s.total_updates, s.cpu_seconds, s.elapsed_sec
    
    local cpu_rate   = cpu / tot * 1e3
    local wall_rate  = wall / tot * 1e3
    local write_rate = 60 * tot / (timers.timenow() - timers.loadtime)
    
    local function dp1(x) return rhs (x - x % 0.1) end
    
    N, T = 0, 0
    mapFiles (folder, 
      function (a)        -- file attributes including path, name, size,... (see lfs.attributes)
        local filename = a.name: match "^(.+).wsp$"
        if filename then
          N = N + 1
          T = T + a.size
        end
      end)
    T = T / 1000

    t0.row { {colspan=2, '&nbsp;'} }
    t0.header { {"Disk archive folder: " .. folder, colspan = 2} }
    t0.row {"updates/min", dp1 (write_rate)}
    t0.row {"time/point (ms)", dp1(wall_rate)}
    t0.row {"cpu/point (ms)", dp1(cpu_rate)}
    
    t0.row {"total size (Mb)", rhs (T - T % 0.1)}
    t0.row {"total # files", rhs (N)}
    t0.row {"total # updates", rhs (tot)}
  end

  local div = html5.div {html5_title "Data Historian statistics summary", t0}
  return div
end

function pages.cache (_, req)
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
  local H = scan_cache ()
  for i, v in ipairs (H) do H[i] = {v=v, sortkey = {v.dev, v.shortSid, v.name}} end   -- add the keysort key!
  table.sort (H, keysort)
      
  local t = html5.table {class = "w3-small"}
  t.header {"device ", "service", "#points", "value",
    {"variable (archived if checked)", title="note that the checkbox field \n is currently READONLY"} }
  
  local link = [[<a href="]] .. req.script_name .. [[?page=graphics&target=%s&from=%s">%s</a>]]
  local tick = '<input type="checkbox" readonly %s /> %s'
  local prev  -- previous device (for formatting)
  for _, x in ipairs(H) do
    local v = x.v
    local finderName = hist.metrics.var2finder (v)
    local archived = archived[finderName]
    local vname = v.name
    if finderName then 
      local _,start = v:oldest()      -- get earliest entry in the cache (if any)
      if start then
        local from = timers.util.epoch2ISOdate (start + 1)    -- ensure we're AFTER the start... 
        vname = link: format (finderName, from, vname)        -- ...and use fixed time format
      end
    end
    local h = #v.history / 2
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
    local check = archived and "checked" or ''
    t.row {'', v.srv: match "[^:]+$" or v.srv, h, v.value, tick: format (check, vname)}
  end
  
  local div = html5.div {html5_title "Data Historian in-memory Cache", t}
  return div
end


local function database_tables (_, req)
  local folder = luup.attr_get "openLuup.Historian.Directory"
  
  if not folder then
    return "On-disk archiving not enabled"
  end
  
  local whisper_edit = lfs.attributes "cgi/whisper-edit.lua"    -- is the editor there?
    
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
          local link = [[<a href="]] .. req.script_name .. [[?page=graphics&target=%s&from=-%s">%s</a>]]  -- relative time
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
  
  local t = html5.table {class = "w3-small"}
  local t2 = html5.table {class = "w3-small"}
  t.header {'', "archives", "(kB)", "fct", "#updates", 
    {"filename (node.dev.srv.var)", title = "hyperlink to Whisper file editor, if present"} }
  t2.header {'', "archives", "(kB)", "fct", '', 
    {"filename (node.dev.srv.var)", title = "hyperlink to Whisper file editor, if present"} }
  local prev
  for _,f in ipairs (files) do 
    local devnum = f.devnum     -- openLuup device number (if present)
    local tbl = t
    if devnum == '' then
      tbl = t2
    elseif devnum ~= prev then 
      t.row { {html5.strong {'[', f.devnum, '] ', f.description}, colspan = 6} }
    end
    prev = devnum
    tbl.row {'', f.links or f.retentions, f.size, f.fct, f.updates, link_to_editor (f.shortName)}
  end
  
  if t2.length() == 0 then t2.row {'', "--- none ---", ''} end
  return t, t2
end

pages.database = function (...) 
  local t, _ = database_tables(...) 
  return page_wrapper ("Data Historian Disk Database", t) 
end

pages.orphans = function (...) 
  local _, t = database_tables(...) 
  return page_wrapper ("Orphaned Database Files  - from non-existent devices", t) 
end

-- file cache

local sorted_cache = sorted_table ()

function pages.file_cache (p)
  local s = sorted_cache
  local t = html5.table {class = "w3-small w3-hoverable"}
  t: header (s.columns {'#', "last access", "# hits", "bytes", "filename"})
  
  local N, H = 0, 0
  local strong = html5.strong
  local info = {}
  for name in vfs.dir() do 
    local v = vfs.attributes (name) 
    local d = (v.access ~= 0) and todate (v.access) or ''
    info[#info+1] = {name, d, v.hits, v.size, name} 
  end
  
  s.sort (info, p.sort)
  for i, row in ipairs (info) do
    H = H + row[3]      -- hits accumulator
    N = N + row[4]      -- size accumulator
    row[1] = i          -- replace primary sort key with line number
    row[3] = rhs (row[3])
    row[4] = rhs (row[4])
    t.row (row)
  end
  
  t:row { '', '', strong {H}, strong {math.floor (N/1000 + 0.5), " (kB)"}, strong {"Total"}}
  local div = html5.div {html5_title "File Server Cache", t}
  return div
end

-- create new persistent variable
local function sticky (default, numeric)
  local x = default
  return function (new_value)
    if numeric then new_value = tonumber (new_value) end
    x = new_value or x       -- update the value if one given
    return x
  end
end

-- create new persistent numeric variable
local function sticky_number (default) return sticky (default, true) end
local sticky_variable = sticky_number ()

-- create persistent values for all pages
local sticky_page      = sticky "about"
local sticky_room     = sticky "All"
local sticky_device   = sticky_number (2)
local sticky_scene    = sticky_number (1)

--
-- Devices
--

-- generic device page
local function device_page (p, fct)
  local d = luup.devices[sticky_device(p.device)]
  local title = devname(sticky_device()) 
  fct = d and fct or function (_, t) return t .. " - no such device" end
  return page_wrapper (fct (d, title))   -- call back with actual device    
end

local function get_display_variables (d)
  local altui = "urn:upnp-org:serviceId:altui1"      -- Variables = 'DisplayLine1' and 'DisplayLine2'
  local vars = (d.services[altui] or {}).variables or {}
  local line1 = (vars.DisplayLine1 or {}) .value or ''
  local line2 = (vars.DisplayLine2 or {}) .value or ''
  return line1, line2
end

function pages.control (p)
  return device_page (p, function (d, title)
    local t = html5.table {class = "w3-small"}
    local line1, line2 = get_display_variables (d)
    local states = d:get_shortcodes ()
    for n,v in sorted (states) do t.row {n, nice(v)} end
    local br = html5.br {}
    return title .. " - status and control", br, line1, br, line2, br, t
  end)
end

function pages.attributes (p)
  return device_page (p, function (d, title)
    local attr = {}
    for n,v in sorted (d.attributes) do attr[#attr+1] = {n, nice(v)} end
    return title .. " - attributes", create_table_from_data (nil, attr)
  end)
end


local sorted_variables = sorted_table ()

function pages.cache_history (p)
  return device_page (p, function (d, title)
    local vnum = sticky_variable (p.variable)
    local v = d and d.variables and d.variables[vnum]
    local TV = {}
    if v then
      local V,T = v:fetch (v:oldest (), os.time())    -- get the whole cache from the oldest available time
      for i, t in ipairs (T) do TV[#TV+1] = {t, V[i]} end
    end
    local t = create_table_from_data ({"time", "value"}, TV, function (row) row[1] = nice (row[1]) end)
    return title .. '.' .. (v.name or '?'), t
  end)
end

function pages.variables (p)
  return device_page (p, function (d, title)
    local s = sorted_variables
    local t = html5.table {class = "w3-small"}
    t.header (s.columns {"id", "service", '', "variable", "value"})
    local info = {}
    for n,v in pairs (d.variables) do
      local history =  v.history and #v.history > 2 and 
                          html5.a {href = selfref ("page=cache_history&variable=", n), "history"} or ''
      info[#info+1] = {v.id, v.srv, history, v.name, nice(v.value) }
    end
    s.sort (info, p.sort)
    for _, row in ipairs (info) do 
      row[4] = {title = row[2], row[4]}     -- add mouse-over pop-up serviceId
      t.row (row) 
    end
    return title .. " - variables", t
  end)
end

function pages.actions (p)
  return device_page (p, function (d, title)
    local sd = loader.service_data
    local t = html5.table {class = "w3-small"}
    t.header {"serviceId", "action", "arguments"}
    for s,srv in sorted (d.services) do
      local service_actions = (sd[s] or {}) .actions
      local action_index = {}         -- service actions indexed by name
      for _, act in ipairs (service_actions or {}) do
        action_index[act.name] = act.argumentList or {}
      end
      for a in sorted (srv.actions) do
        t.row {s, a}
        local action_arguments = action_index[a]
        if action_arguments then
          for _, v in ipairs (action_arguments) do
            if (v.direction or ''): match "in" then t.row {'','', v.name} end
          end
        end
      end
    end
    return title .. " - implemented actions", t
  end)
end

function pages.events (p)
  return device_page (p, function (d, title)
      local e = {}
      local columns = {"id", "event / variable : (serviceId)"}
      local json_file = d.attributes.device_json
      local static_data = loader.static_data[json_file] or {}
      local eventList2 = static_data.eventList2
      if eventList2 then
        for i, event in ipairs (eventList2) do
            e[#e+1] = {event.id, event.label.text}
        end
      end
    return title .. " - generated events", create_table_from_data (columns, e)
  end)
end

function pages.user_data (p)
  return device_page (p, function (d, title)
    local j, err
    local dtable = userdata.devices_table {[sticky_device()] = d}
    j, err = json.encode (dtable)
    return title .. " - JSON user_data", 
    html5.div {class = "w3-panel w3-border", html5.pre {j or err} }
  end)
end

local function rooms_selector ()
  local current_room = sticky_room()
  local function room_button (x)
    local colour = x == current_room and "w3-grey" or "w3-light-gray"
    return html5.a {class = "w3-bar-item w3-button " .. colour, href = selfref ("room=", x), x }
  end
  local rooms = html5.div {
--    class="w3-bar-block w3-col w3-grey", style="width:12em;",
    class="w3-bar-block w3-col w3-border w3-border-grey", style="width:12em;",
    room_button "All", room_button "Favourites", room_button "No Room"}
  for _,r in pairs (luup.rooms) do
    rooms[#rooms+1] = room_button (r)
  end
  return rooms
end

-- returns a function to decide whether given room number is in selected set
local function room_wanted ()
  local room = sticky_room ()
  local room_index = {["No Room"] = 0}
  for n, r in pairs (luup.rooms) do room_index[r] = n end
  local all_rooms = room == "All"
  local favourite_room = room == "Favourites"
  local room_number = room_index[room]
  return function (d)
    return all_rooms or d.room_num == room_number
  end
end

local function panel_wrapper (...)
  return html5.div {class = "w3-small w3-margin-left w3-margin-bottom",
    style="width:240px; height:80px; float:left; border:1px solid Silver; border-radius:4px; display:inline-block; ", ...}
end

function pages.devices (p)
  local static_data = loader.static_data
   
  local function device_panel (self)          -- 2019.05.12
    local id = self.attributes.id
    local line1, line2 = get_display_variables (self)
    
    local json_file = self.attributes.device_json or ''   -- such a shame to have to use the JSON file!
    local icon = (static_data[json_file] or {}) .default_icon or ''
    if icon ~= '' and not icon: lower() : match "^http" then icon = "/icons/" .. icon end
    local img = html5.img {src = icon, alt="no icon", style = "width:48px; height:48px;"}
    img = html5.a {href=selfref ("page=device&device=", id), img} -- ********
    
    local div, span = html5.div, html5.span
   local panel = panel_wrapper (
        div {style="background:LightGrey; border-bottom:1px solid Grey; margin:0; padding:4px;", devname (id)},
        div {div {style = "clear:none;",
          div {style="float: left; clear: none; margin:2px;", img}, 
          div {style="float: left; clear: right;", span {line1, html5.br{}, line2 } } } } )
    return panel
  end
  
  -- devices   
--  local devs = {class="content", style="margin-left:12em; display: flex; flex:90%; flex-flow:row wrap; width:80%;" }
--  local devs = {class="content", style="margin-left:12em; " }
  local devs = html5.div {class="w3-rest", style="text-align:justified; " }
  local wanted = room_wanted()        -- get function to filter by room
  for _, d in pairs (luup.devices) do
    if wanted(d) or d.attributes.bookmark == '1' then   -- TODO: favourites
      devs[#devs+1] = device_panel (d)
    end
  end

  local room_nav = rooms_selector (p)
  local ddiv = html5.div {room_nav, html5.div {class="w3-rest", devs} }
  return ddiv
end

--
-- ["Scene"] = {"header", "triggers", "timers", "lua", "group_actions", "json"},
--

-- generic scene page
local function scene_page (p, fct)
  local i = sticky_scene(p.scene)
  local s = luup.scenes[i]
  local title = scene_name (i) 
  fct = s and fct or function (_, t) return t .. " - no such scene" end
  return page_wrapper (fct (s, title))   -- call back with actual scene    
end

function pages.header (p)
  return scene_page (p, function (scene, title)
    local info = {
      {"name", scene.description},
      {"paused", tostring (scene.paused)},
      {"room", luup.rooms[scene.room_num] or "no room"},
      {"modes", scene: user_table() .modeStatus} }
    local t = create_table_from_data ({"field", "value"}, info)
    return title .. " - scene header", t
  end)
end

function pages.triggers (p)
  return scene_page (p, function (scene, title)
    local pre = html5.pre {json.encode (scene:user_table() .triggers)}
    return title .. " - scene triggers", pre
  end)
end

function pages.timers (p)
  return scene_page (p, function (scene, title)
    local pre = html5.pre {json.encode (scene:user_table() .timers)}
    return title .. " - scene timers", pre
  end)
end
  
function pages.lua (p)
  return scene_page (p, function (scene, title)
    local pre = html5.pre {scene:user_table() .lua}
    return title .. " - scene Lua", pre
  end)
end
 
function pages.group_actions (p)
  return scene_page (p, function (scene, title)
    local pre = html5.pre {json.encode (scene:user_table() .groups)}
    return title .. " - actions (in delay groups)", pre
  end)
end
 
function pages.json (p)
  return scene_page (p, function (scene, title)
    local pre = html5.pre {tostring (scene)}
    return title .. " - JSON scene definition", pre
  end)
end

function pages.scenes (p)
  local function scene_panel (self)
    local utab = self: user_table()
    local id = utab.id
    local earliest_time
    for _,timer in ipairs (utab.timers or {}) do
      local next_run = timer.next_run 
      if next_run and timer.enabled == 1 then
        earliest_time = math.min (earliest_time or next_run,  next_run)
      end
    end
    local next_run = earliest_time and "◷ " .. nice (earliest_time) or ''
    local last_run = utab.last_run
    last_run = last_run and "&#x2713; " .. nice (last_run) or ''
    local t = html5.div {html5.span {style="font-size: 8pt;",
        last_run, html5.br{}, next_run}, style="margin:3px;" }
    
    local img = html5.a {href= selfref("page=scene&scene=", id), "scene"} -- ********
    local div = html5.div
    local panel = panel_wrapper (
      div {style="background:LightGrey; border-bottom:1px solid Grey; margin:0; padding:4px;", scene_name(id)},
      div {div {style = "clear:none;",
        div {style="float: left; clear: none; margin:2px;", img}, 
        div {style="float: right; padding-right:8px;", html5.span {last_run, html5.br{}, next_run } } } } )
    return panel
  end
  
  -- scenes   
  local wanted = room_wanted()        -- get function to filter by room
  local scenes = {class="content", style="margin-left:12em; " }
  for _,s in pairs (luup.scenes) do
    local u = s: user_table()
    if wanted(s) or u.favorite then   -- TODO: favourites
      scenes[#scenes+1] = scene_panel (s)
    end
  end
  local room_nav = rooms_selector (p)
  local section = html5.section (scenes)
  return html5.div {room_nav, section}
end

function pages.lua_startup ()
  local code = userdata.attributes.StartupCode or ''
  return page_wrapper ("Lua Startup Code", html5.pre {code})
end

function pages.lua_shutdown ()
  local code = userdata.attributes.ShutdownCode or ''
  return page_wrapper ("Lua Shutdown Code", html5.pre {code})
end

local Lua_Test_Code = ''

function pages.lua_code_test ()
  local code = Lua_Test_Code or ''
  return page_wrapper ("Lua Test Code", html5.pre {code})
end

function pages.graphics (p, req)
  local background = p.background or "GhostWhite"
  local iframe = html5.iframe {
    height = "450px", width = "96%", 
    style= "margin-left: 2%; margin-top:30px; background-color:"..background,
    src="/render?" .. req.query_string,
    }
  return iframe
end

function pages.rooms_table ()
  local t = html5.table {}
  t.header {"id", "name"}
  for n, v in sorted (luup.rooms) do
    t.row {n,v}
  end
  return page_wrapper ("Rooms Table", t)
end

function pages.devices_table ()
  local t = html5.table {}
  t.header {"id", "name"}
  for n, v in sorted (luup.devices) do
    t.row {n,v.description}
  end
  return page_wrapper ("Devices Table", t)
end

function pages.scenes_table ()
--[[
{
	 description = "test",
	 hidden = false,
	 paused = false,
	 room_num = 0,
	 running = true
}]]
  local s = {}
  for n,x in pairs (luup.scenes) do
    s[#s+1] = {n,  x.description, luup.rooms[x.room_num] or "no room", tostring (x.paused)}
  end
  local t = create_table_from_data ({"id", "name", "room", "paused"}, s)
  return page_wrapper ("Scenes Table", t)
end

function pages.plugins_table ()
  local t = html5.table {class = "w3-table w3-bordered"}
  t.header {'', "Name","Version", "Auto", "Files", "Actions", "Update", "Unistall"}
  local IP2 = userdata.attributes.InstalledPlugins2 or userdata.default_plugins
  for _, p in ipairs (IP2) do
    -- http://apps.mios.com/plugin.php?id=8246
    local src = p.Icon or ''
    local mios_plugin = src: match "^plugins/icons/"
    if mios_plugin then src = "http://apps.mios.com/" .. src end
    local icon = html5.img {src=src, alt="no icon", height=35, width=35}
    local version = table.concat ({p.VersionMajor, p.VersionMinor}, '.')
    local files = {}
    for _, f in ipairs (p.Files or {}) do files[#files+1] = f.SourceName end
    table.sort (files)
    table.insert (files, 1, "Files")
    local select = {style = "width:18em;", onchange="location = this.value;" }
    for _, f in ipairs (files) do select[#select+1] = html5.option {value=f, f} end
    files = html5.form {html5.select (select)}
    local help = html5.a {href=p.Instructions or '', target="_blank", "help"}
    t.row {icon, p.Title, version, p.AutoUpdate, files, help, '',''} 
  end
  return page_wrapper ("Plugins", t)
end

function pages.about () 
  local ABOUTopenLuup = luup.devices[2].environment.ABOUT   -- use openLuup about, not console
  local t = html5.table {class = "w3-table-all w3-cell"}
  for a,b in sorted (ABOUTopenLuup) do
    b = tostring(b): gsub ("http%S+",  '<a href=%1 target="_blank">%1</a>')
    t.row { {a, style = "font-weight: bold"},  html5.pre {style="line-height: 1;", b}}
  end
  return t
end  

function pages.reload ()
  luup.log "Reload requested by openLuup console"
  local _,_, jno = scheduler.run_job {job = luup.reload}
  luup.log ("Shutdown job = " .. (jno or '?'))
  return page_wrapper "Please wait a moment while system reloads"
end

  
-- switch dynamically between different menu styles
local user_json = luup.attr_get "openLuup.Console.Menu"
local menu_json = sticky (user_json or "default_console_menus.json")

function pages.current () return pages.home () end
function pages.classic () return pages.home "classic_console_menus.json" end
function pages.default () return pages.home "default_console_menus.json" end
function pages.altui   () return pages.home "altui_console_menus.json"   end
function pages.user    () return pages.home (user_json) end


-------------------------------------------


local a, div = html5.a, html5.div
 
local page_groups = {
    ["Historian"] = {"summary", "cache", "database", "orphans"},
    ["System"]    = {"parameters", "top_level", "globals", "states", "sandboxes", "RELOAD"},
    ["Device"]    = {"control", "attributes", "variables", "actions", "events", "user_data"},
    ["Scene"]     = {"header", "triggers", "timers", "lua", "group_actions", "json"},
    ["Scheduler"] = {"running", "completed", "startup", "plugins", "delays", "watches"},
    ["Servers"]   = {"http", "smtp", "pop3", "udp", "sockets", "file_cache"},
    ["Utilities"] = {"backups", "images", "trash"},
    ["Menu Style"]= {"current", "classic", "default", "altui", "user"},
    ["Lua Code"]  = {"lua_startup", "lua_shutdown", "lua_code_test", "lua_test(2)", "lua_test(3)"},
    ["Tables"]    = {"rooms_table", "plugins_table", "devices_table", "triggers_table", "scenes_table"},
    ["Logs"]      = {"log", "log.1", "log.2", "log.3", "log.4", "log.5", "startup_log"},
  }

local page_groups_index = {}        -- groups indexed by page name
for group_name, group_pages in pairs (page_groups) do
  for _, page in ipairs (group_pages) do
    page_groups_index[page] = group_name
  end
end

-- remove spaces from multi-word names and create index
local short_name_index = {}       -- long names indexed by short names
local function short_name(name) 
  local short = name: gsub(' ','_'): lower()
  short_name_index[short] = name
  return short
end

-- make a page link button
local function make_button(name, current)
  local confirm
  local short = short_name(name)
  local colour = "w3-amber"
  if short == "reload" then 
    colour = "w3-red"
    confirm = "return confirm('System Reload: Are you sure?')"
  elseif short == current then 
    colour = "w3-grey"
  end
  local link = {class="w3-button w3-round " .. colour, href=selfref ("page=", short), 
                  onclick=confirm, short_name_index[short]}
  return html5.a (link)
end

-- walk the menu tree defined by the named JSON file, calling the user function for each item
local function map_menu_tree (fct)
  local console_json = loader.raw_read (menu_json ())
  local console = json.decode(console_json) or {}
  for _, menu in ipairs (console.menus or {}) do fct (menu) end
end

function pages.home (menu_page)
  local menu = menu_json (menu_page)      -- set the menu structure, if changed
  
  -- create a list of all the page groups referenced by current menu structure
  local group_names = {}
  local function add_name (name)
    local page_name = short_name(name)
    local group_name1 = page_groups_index[page_name]    -- is the page in a group ?
    local group_name2 = page_groups [name] and name     -- or the name of a group ?
    local group_name = group_name1 or group_name2
    group_names[group_name or '?'] = page_groups[group_name] 
  end
  map_menu_tree  (function  (menu)
    add_name (menu[1])                       -- try the top-level menu name too
    for _, name in ipairs (menu[2] or {}) do
      add_name(name) 
    end
  end)

  local index = {}
  for group, pages in sorted (group_names) do
    local pnames = div {class = "w3-padding", make_button (group, short_name(group))}    -- highlight the group name button
    for _, page in ipairs (pages) do
      pnames[#pnames+1] = make_button (page)
    end
    index[#index+1] = pnames
  end
  
  local div = html5.div {html5.h4 {"Page Index"}, div(index)} 
  return div
end


local function page_nav (current, previous)
  local pagename = current: gsub ("^.", function (x) return x:upper() end)
  
  -- want to be able to use group name as a page... 
  local Current = current: gsub ("^.", function(x) return x:upper() end)    -- restore the leading capital
  local page_group = page_groups[Current]  or {}                            -- get the group, if it exists
  current = sticky_page (page_group[1])                                     -- use the first page in the group
  -----
  
  local tabs = {}
  local group = page_groups_index[current]
  if group then
    for _, name in ipairs (page_groups[group]) do 
      tabs[#tabs+1] = make_button (name, current) 
    end
  end
  local messages = div (make_button ("Messages &#x25BC ")) 
--    html5.span {class="w3-badge w3-red w3-display-topright",1}}
  messages.onclick="ShowHide('messages')" 
  return div {class="w3-container w3-row w3-margin-top",
   html5.span {class = "w3-container w3-cell w3-cell-middle w3-round w3-border w3-border-grey",
        a {class="nodec", href = selfref ("page=", previous), "&lArr;"}, " / ",     -- left arrow
        a {class="nodec", href = selfref "page=current", "Home"},     " / ", 
        pagename}, 
    div {class="w3-container w3-cell", messages},
    div {class = "w3-panel w3-border w3-hide", id="messages",  "hello"},
    div {html5.h3 {group or pagename}, div (tabs) }},
    current     -- return a possibly modified page 
end


-- dynamically build HTML menu from table structure {name, {items}, page}
local function dynamic_menu ()
  local icon = a {class = "w3-dropdown-hover w3-grey",
        href="/data_request?id=lr_ALTUI_Handler&command=home#", target="_blank",  
        html5.img {height=42, alt="openLuup", src="icons/openLuup.svg", class="w3-button"} }
  local menus = div {class = "w3-bar w3-grey", icon}
  map_menu_tree (function (menu)
    local name = menu[1]
    local dropdown = {class="w3-dropdown-hover"}
    if #menu == 1 then      -- it's just a simple button to a page
      dropdown[1] = a {class="w3-button w3-margin-small", href=selfref ("page=", short_name(name)), name}
    else
      dropdown[1] = div {class="w3-button w3-margin-small", name}
      local dropdown_content = 
        {class="w3-dropdown-content w3-bar-block w3-border-grey w3-light-grey w3-card-4"}
      local border = ''
      for _, item in ipairs (menu[2] or {}) do
        if item == "hr" then 
          border = " w3-border-top"                   -- give next item a line above...
        else
          dropdown_content[#dropdown_content+1] = 
            a {class="w3-bar-item w3-button" .. border, href=selfref ("page=", short_name(item)), item}
          border = ''
        end
      end
      dropdown[2] = div (dropdown_content)
    end
    menus[#menus+1] = div (dropdown)
  end)  
  return menus
end


----------------------------------------
-- run()
--

function run (wsapi_env)
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax

  local req = wsapi.request.new (wsapi_env)
  script = req.script_name      -- save to use in links
  local p = req.GET 
  
  local previous = sticky_page ()
  local current  = sticky_page (p.page)
  
  sticky_room (p.room)
--  sticky_device (p.device)
--  sticky_scene (p.scene)
--  sticky_variable = (p.variable)
  
  local navigation, actual_page = page_nav (current, previous)
  local dispatch = pages[actual_page] or function () end
  local sheet = dispatch (p, req)
  local formatted_page = div {class = "w3-container", navigation, sheet}
  
  local html = html5.document { 
    
    html5.title {script: match "(%w+)$"},
[[
  <meta charset="utf-8" name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="w3.css">
]],

    html5.style {
[[  
  pre {line-height: 1.1; font-size:10pt;}
  a.nodec { text-decoration: none; } a.nodec:hover { text-decoration: underline; }
  th,td {width:1px; white-space:nowrap; padding: 0 16px 0 16px;}
  table {table-layout: fixed; margin-top:20px}
]]},

    html5.script {
[[
function ShowHide(id) {
  var x = document.getElementById(id);
  if (x.className.indexOf("w3-show") == -1) {
    x.className += " w3-show";
  } else {
    x.className = x.className.replace(" w3-show", "");
  }
}]]},

    html5.body {class = "w3-light-grey",
      dynamic_menu (),
      div {
        formatted_page,
        div {class="w3-footer w3-small w3-margin-top w3-border-top w3-border-grey", html5.p {os.date "%c"}},
      }}}
  
  local res = wsapi.response.new ()
  res: write (html)  
  return res: finish()
end


-----
