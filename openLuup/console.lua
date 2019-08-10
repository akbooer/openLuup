#!/usr/bin/env wsapi.cgi

module(..., package.seeall)


ABOUT = {
  NAME          = "console.lua",
  VERSION       = "2019.08.10",
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
-- 2019.07.14  use new xml.createNewHtmlDocument() factory method
-- 2019.07.31  use new server module (name reverted from http)


--  WSAPI Lua CGI implementation

local lfs       = require "lfs"                   -- for backup file listing, and historian files
local vfs       = require "openLuup.virtualfilesystem"
local luup      = require "openLuup.luup"         -- not automatically in scope for CGIs
local scheduler = require "openLuup.scheduler"    -- for job_list, delay_list, etc...
local requests  = require "openLuup.requests"     -- for plugin updates, etc...
local userdata  = require "openLuup.userdata"     -- for device user_data
local server    = require "openLuup.server"       -- for HTTP server stats
local smtp      = require "openLuup.smtp"
local pop3      = require "openLuup.pop3"
local ioutil    = require "openLuup.io"
local scenes    = require "openLuup.scenes"
local hist      = require "openLuup.historian"    -- for disk archive stats   
local timers    = require "openLuup.timers"       -- for startup time
local whisper   = require "openLuup.whisper"
local wsapi     = require "openLuup.wsapi"        -- for response library
local loader    = require "openLuup.loader"       -- for static data (devices page)
local json      = require "openLuup.json"         -- for console_menus.json
local xml       = require "openLuup.xml"          -- for HTML constructors

local xhtml     = xml.createHTMLDocument ()       -- factory for all HTML tags

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

local options = luup.attr_get "openLuup.Console" or {}   -- get configuration parameters
--[[
      Menu ="",           -- add menu JSON definition file here
      Ace_URL = "https://cdnjs.cloudflare.com/ajax/libs/ace/1.4.3/ace.js",
      EditorTheme = "eclipse",
]]
--

local service_data  = loader.service_data

local unicode = {
--  double_vertical_bar = "&#x23F8;",
--  black_right_pointing_triangle ="&#x25B6",
  black_down_pointing_triangle ="▼",
  leftwards_double_arrow = "⇐",
  clock_three = "◷",     -- actually, WHITE CIRCLE WITH UPPER RIGHT QUADRANT
  black_star  = "★",
  white_star  = "☆",
  check_mark  = "✓",     
--  cross_mark  = "&#x2718;",
--  pencil      = "&#x270e;",
--  power       = "&#x23FB;",     -- NB. not yet commonly implemented.
}


local function missing_index_metatable (name)
  return {__index = function(_, tag) 
    return function() 
      return table.concat {"No such ", name, ": '",  tag or "? [not specified]", "'"} 
      end
    end}
  end

local pages = setmetatable ({}, missing_index_metatable "Page")

local actions = setmetatable ({}, missing_index_metatable "Action")

local code_editor -- forward reference

----------------------------------------
--
-- XMLHttpRequest
--
-- AJAX-style handler for /data_request?id=XMLHttpRequest&... to return sub-page updates.
-- Uses the /data_request syntax which already supports asynchronous responses triggered
-- by system updates using the Timeout / DataVersion / MinimumDelay parameters.
--

-- populated further on by XMLHttpRequest callback handlers
local XMLHttpRequest = setmetatable ({}, missing_index_metatable "XMLHttpRequest")

server.add_callback_handlers {XMLHttpRequest = 
  function (_, p) return XMLHttpRequest[p.action] (p) end}


----------------------------------------


local SID = {
  altui   = "urn:upnp-org:serviceId:altui1",                  -- 'DisplayLine1' and 'DisplayLine2'
  ha      = "urn:micasaverde-com:serviceId:HaDevice1", 		    -- 'BatteryLevel'
  switch  = "urn:upnp-org:serviceId:SwitchPower1",             -- on/off control
  dimming = "urn:upnp-org:serviceId:Dimming1",                 -- slider control
  temp    = "urn:upnp-org:serviceId:TemperatureSensor1",
  humid   = "urn:micasaverde-com:serviceId:HumiditySensor1",
}

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local script_name  -- name of this CGI script
  
-- switch dynamically between different menu styles
local menu_json = options.Menu ~= '' and options.Menu or "altui_console_menus.json"

-- remove spaces from multi-word names and create index
local short_name_index = {}       -- long names indexed by short names
local function short_name(name) 
  local short = name: gsub('%s+','_'): lower()
  short_name_index[short] = name
  return short
end
 
local page_groups = {
--    ["House Mode"]= {"home", "away", "night", "vacation"},
    ["Historian"] = {"summary", "cache", "database", "orphans"},
    ["System"]    = {"parameters", "top_level", "globals", "states", "sandboxes", "RELOAD"},
    ["Device"]    = {"control", "attributes", "variables", "actions", "events", "user_data"},
    ["Scene"]     = {"header", "triggers", "timers", "history", "lua", "group_actions", "json"},
    ["Scheduler"] = {"running", "completed", "startup", "plugins", "delays", "watches"},
    ["Servers"]   = {"http", "smtp", "pop3", "udp", "sockets", "file_cache"},
    ["Utilities"] = {"backups", "images", "trash"},
    ["Lua Code"]  = {"lua_startup", "lua_shutdown", "lua_test", "lua_test2", "lua_test3"},
    ["Tables"]    = {"rooms_table", "plugins_table", "devices_table", "scenes_table", "triggers_table"},
    ["Logs"]      = {"log", "log.1", "log.2", "log.3", "log.4", "log.5", "startup_log"},
  }

local page_groups_index = {}        -- groups indexed by page name
for group_name, group_pages in pairs (page_groups) do
  for i, page in ipairs (group_pages) do
    if i == 1 then pages[short_name(group_name)] = pages[page] end   -- create page alias to first in group
    page_groups_index[page] = group_name
  end
end

-- look for user-defined device panels
-- named U_xxx.lua, derived from trailing word of device type:
-- urn:schemas-micasaverde-com:device:TemperatureSensor:1, would be U_TemperatureSensor.lua
local user_defined = {}
for f in loader.dir "^U_.-%.lua$" do
  local name = f: match "^U_(.-)%.lua$"
  local ok, user = pcall (require, "U_" .. name)
  if ok then user_defined[name] = user end
end

local function selfref (...) return table.concat {script_name, '?', ...} end   -- for use in hrefs

local state =  {[-1] = "No Job", [0] = "Wait", "Run", "Error", "Abort", "Done", "Wait", "Requeue", "Pending"} 

local function todate (epoch) return os.date ("%Y-%m-%d %H:%M:%S", epoch) end

local function truncate (s, maxlength)
  maxlength = maxlength or 24
  if #s > maxlength then s = s: sub(1, maxlength) .. "..." end
  return s
end

-- restore the leading capital in each word and convert underscores to spaces
local function capitalise (x)
  return x :gsub ('_', ' ') :gsub ("(%w)(%w*)", function (a,b) return a:upper() .. b end)
end

-- formats a value nicely
local function nice (x, maxlength)
  local s = tostring (x)
  local number = tonumber(s)
  if number and number > 1234567890 then s = todate (number) end
  return truncate (s, maxlength or 50)
end

local function dev_or_scene_name (d, tbl)
  d = tonumber(d) or 0
  local name = (tbl[d] or {}).description or 'system'
  name = name: match "^%s*(.+)" or "???"
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


local function get_device_icon (d)
  local img  
  -- user-defined icon
  local dtype = (d.attributes.device_type or ''): match "(%w+):?%d*$"   -- pick the last word
  local user = user_defined[dtype] or {}
  if user.icon then 
    img = user.icon(d.attributes.id) -- TODO: parse a string to get DOM
  else
    local icon = d:get_icon ()
    if icon ~= '' and not icon: lower() : match "^http" then icon = "/icons/" .. icon end
    img = xhtml.img {src = icon, alt="no icon", style = "width:50px; height:50px;"}
  end

  return xhtml.a {href=selfref ("page=control&device=", d.attributes.id), img}
end

-- create HTML for a group of house mode buttons
-- selected parameter is a string, e.g. "1,3" with 'on' buttons 
local function house_mode_group (selected)  
  selected = tostring (selected)
  local mode_name = {"Home", "Away", "Night", "Vacation"}
  local on = {}
  for x in selected: gmatch "%d" do on[tonumber(x)] = true end
  local function mode_button (number, icon)
    local name = mode_name[number]
    local colour =''
    if on[number] then colour = "w3-light-green" end
    return xhtml.div {title=name, class="w3-button w3-round " .. colour, 
      xhtml.img {height=50, width=50, alt=name, src=icon}}
  end
  
  return xhtml.div {class = "w3-cell w3-bar w3-padding w3-round w3-border",
    mode_button (1, "/icons/home-solid.svg"), 
    mode_button (2, "/icons/car-side-solid.svg"),
    mode_button (3, "/icons/moon-solid.svg"),
    mode_button (4, "/icons/plane-solid.svg"),
  }
end


local function confirm (name)
  return name:lower():match "reload" and "return confirm('System Reload: Are you sure?')" or nil
end

-- make a page link button
local function make_button(name, current)
  local short = short_name(name)
  local colour = "w3-amber"
  local onclick = confirm(short)
  if onclick then 
    colour = "w3-red"
  elseif short == current then 
    colour = "w3-grey"
  end
  local icon = short_name_index[short]
  local link = {class="w3-button w3-round " .. colour, href=selfref ("page=", short), 
                  onclick=onclick, icon}
  return xhtml.a (link)
end
  
-- return the appropriate set of page buttons for the current page 
-- you can also use group name as a page... 
local function page_group_buttons (page)  
  local groupname = page_groups_index[page] 
                    or capitalise (page)    -- restore the leading capital
  local group = page_groups[groupname]  or {}
  local tabs = {}
  for _, name in ipairs (group) do 
    tabs[#tabs+1] = make_button (name, page) 
  end
  return tabs, groupname
end

-- build a vertical menu for the sidebar
local function filter_menu (items, current_item, request)
  local menu = xhtml.div {class = "w3-margin-bottom  w3-border w3-border-grey"}
  for i, name in ipairs (items) do
    local colour = (name == current_item) and "w3-grey" or "w3-light-gray"
    menu[i] = xhtml.a {class = "w3-bar-item w3-button "..colour, href = selfref (request, name), name }
  end
  return xhtml.div {class="w3-bar-block w3-col", style="width:12em;", menu}
end

-- sidebar menu built from function arguments
local function sidebar (p, ...)
  local sidebar_menu = xhtml.div {class="w3-bar-block w3-col", style="width:12em;"}
  for i, fct in ipairs {...} do sidebar_menu[i] = fct(p) end
  return sidebar_menu
end

-- walk the menu tree, calling the user function for each item
local function map_menu_tree (fct)
  local console_json = loader.raw_read (menu_json)
  local console = json.decode(console_json) or {}
  for _, menu in ipairs (console.menus or {}) do fct (menu) end
end

-----------------------------

local function html5_title (...) return xhtml.h4 {...} end
local function red (x) return xhtml.span {class = "w3-red", x}  end
local function status_number (n) if n ~= 200 then return red (n) end; return n end
local function page_wrapper (title, ...) return xhtml.div {html5_title (title), ...} end


-- make a simple HTML table from data
local function create_table_from_data (columns, data, formatter)
  local tbl = xhtml.table {class="w3-small"}
  tbl.header (columns)
  for i,row in ipairs (data) do 
    if formatter then formatter (row, i) end  -- pass the formatter both current row and row number
    tbl.row (row) 
  end
  if #data == 0 then tbl.row {"--- none ---"} end
  return tbl
end

--
-- Actions (without changing current page)
--

function actions.bookmark (p)
  local dev = luup.devices[tonumber (p.dev)]
  if dev then
    local a = dev.attributes
    a.bookmark = (a.bookmark ~= '1') and '1' or '0'
  end
  local scn = luup.scenes[tonumber (p.scn)]
  if scn then
    local a = scn.user_table ()
    a.favorite = not a.favorite
  end
end

function actions.toggle_pause (p)
  local scene = luup.scenes[tonumber (p.scn)]
  if scene then scene.on_off () end
end

function actions.run_scene (p)
  local scene = luup.scenes[tonumber (p.scn)]
  if scene then scene.run () end    -- TODO: run this asynchronously?
end

function actions.slider (_, req)
  local q = req.params        -- works for GET or POST
  local devNo = tonumber(q.dev)
  local dev = luup.devices[devNo]
  if dev then 
    -- use luup.call_action() so that bridged device actions are handled by VeraBridge
    local a,b,j = luup.call_action (SID.dimming, "SetLoadLevelTarget", {newLoadlevelTarget=q.slider}, devNo) 
    local _={a,b,j}   -- TODO: status return to messages?
  end
end

function actions.switch (_, req)
  local q = req.params        -- works for GET or POST
  local devNo = tonumber(q.dev)
  local dev = luup.devices[devNo]
  if dev then 
    local v = luup.variable_get (SID.switch, "Target", devNo)
    local target = v == '1' and '0' or '1'    -- toggle action
    -- this uses luup.call_action() so that bridged device actions are handled by VeraBridge
    local a,b,j = luup.call_action (SID.switch, "SetTarget", {newTargetValue=target}, devNo) 
    local _={a,b,j}   -- TODO: status return to messages?
  end
end

-- action=update_plugin&plugin=openLuup&update=version
function actions.update_plugin (_, req)
  local q = req.params
  requests.update_plugin (_, {Plugin=q.plugin, Version=q.version})
  -- actual update is asynchronous, so return is not useful
end

-- action=call_action (_, req)
function actions.call_action (_, req)
  local q = req.POST    -- it must be a post in order to loop through the params
  if q then
    local act, srv, dev = q.act, q.srv, q.dev
    q.act, q.srv, q.dev = nil, nil, nil         -- remove these from the request and use the rest of the parameter list
    -- action returns: error, message, jobNo, arrguments
--    print ("ACTION", act, srv, dev)
    local e,m,j,a = luup.call_action  (srv, act, q, tonumber (dev))
    local _ = {e,m,j,a}   -- TODO: write status return to message?
  end
end

-- Pages
--

-- returns unformatted data for both running and completed jobs
-- also metatable function to format a final table
-- and a default sort order
local function jobs_tables (_, running, title)
  local jlist = {}
  for jn, j in pairs (scheduler.job_list) do
    local status = j.status or state.NoJob
    local n = j.logging.invocations
    local ok = scheduler.exit_state[status]
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
      row[4] = scheduler.error_state[row[4]] and red (state[row[4]]) or state[row[4]]
      row[6] = rhs (dhms (row[6], nil, milli))
      row[7] = rhs (row[7])
    end)
  return xhtml.div {class = "w3-responsive", page_wrapper(title, tbl) }	-- may be wide, let's scroll sideways
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
  local tbl = xhtml.table {class = "w3-small"}
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
  local tbl = xhtml.table {class = "w3-small"}
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
  table.sort (dlist, function (a,b) return a[1] < b[1] end)  
  -----
  local tbl = create_table_from_data (columns, dlist,
    function (row, i)    -- formatter function to decorate specific items
      row[1] = i
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
  local ignore = {"ShutdownCode", "StartupCode", "LuaTestCode", "LuaTestCode2", "LuaTestCode3"}
  local unwanted = {}
  for _, x in pairs (ignore) do unwanted[x] = true; end
  local t = xhtml.table {class = "w3-small"}
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
        data[#data+1] = {{xhtml.strong {dname}, colspan = #columns}}
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
        data[#data+1] = {{xhtml.strong {dname}, colspan = #columns}}
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
    local hyperlink = xhtml.a {
      href = "cgi-bin/cmh/backup.sh?retrieve="..f.name, 
      download = f.name: gsub (".lzap$",'') .. ".json",
      f.name}
    data[#data+1] = {f.date, f.size, hyperlink} 
  end
  local tbl = create_table_from_data (columns, data)
  local backup = xhtml.div {
    xhtml.a {class="w3-button w3-round w3-light-green", href = "cgi-bin/cmh/backup.sh?", target="_blank",
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
      local t = xhtml.table {class="w3-small w3-hoverable w3-card w3-padding"}
      t.header {{title, colspan = 2}}
--      t.header {"name","type"}
      for _, row in ipairs(y) do
        t.row (row)
      end
      return t
    end
    local T = xhtml.div {}
    for d, idx in pairs (lookup) do
      T[#T+1] = sorted(idx, boxmsg: format (d, devname(d)))
    end
    T[#T+1] = sorted (tbl, "Shared items:")
    return T
  end
  
  local div = xhtml.div {html5_title "Sandboxed system tables (by plugin)"}
  for n,v in pairs (_G) do
    local meta = ((type(v) == "table") and getmetatable(v)) or {}
    if meta.__newindex and meta.__tostring and meta.lookup then   -- not foolproof, but good enough?
      div[#div+1] = xhtml.p { n, ".sandbox"} 
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
--    pre = xhtml.pre {xml.escape (x)}
    pre = xhtml.pre {x}     -- 2019.07.14  new HTML escapes all text
  end
  local end_of_page_buttons = page_group_buttons (page)
  return page_wrapper(name, pre, xhtml.div (end_of_page_buttons))
end

for i = 1,5 do pages["log." .. i] = pages.log end         -- add the older file versions
pages.startup_log = pages.log

-- generic connections table for all servers
local function connectionsTable (iprequests)
  local t = xhtml.table {}
--  t.header { {"Received connections:", colspan=3} }
  t.header {"IP address", "#connects", "date / time"}
  for ip, req in pairs (iprequests) do
    t.row {ip, req.count, todate(req.date)}
  end
  if t.length() == 0 then t.row {'', "--- none ---", ''} end
  return xhtml.div {class = "w3-small w3-card w3-padding w3-cell", xhtml.h5 {"Received connections:"}, t}
end


function pages.http ()    
  local function requestTable (requests, title, columns, include_zero)
  local t = xhtml.table {class = "w3-small w3-card w3-padding"}
--    t.header { {title, colspan = 3} }
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
--    return t
    return xhtml.div {class = "w3-small w3-padding", xhtml.h5 {title}, t}
  end
  
  local lu, lr = {}, {}     -- 2019.05.16 system- and user-defined requests
  for n,v in pairs (server.http_handler) do
    local tbl = n: match "^lr_" and lr or lu
    tbl[n] = v
  end
  
  return xhtml.div {
      html5_title "HTTP Web server (port 3480)",
      connectionsTable (server.iprequests),   
      requestTable (lu, "/data_request? (system)", {"id=lu_... ", "#requests  ","status"}),
      requestTable (lr, "/data_request? (user-defined)", {"id=lr_... ", "#requests  ","status"}, true),
      requestTable (server.cgi_handler, "CGI requests", {"URL ", "#requests  ","status"}),
      requestTable (server.file_handler, "File requests", {"filename ", "#requests  ","status"}),
    }
end

function pages.smtp ()
  local none = "--- none ---"
  
  local function sortedTable (title, info, ok)
    local t = xhtml.table {class = "w3-small w3-card w3-padding"}
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
  
  local t = xhtml.table {class = "w3-small w3-card w3-padding"}
  t.header {{ "Blocked senders:", colspan=2 }}
  t.header {"eMail address","#attempts"}
  for email in pairs (smtp.blocked) do
    t.row {email, '?'}
  end
  if t.length() == 0 then t.row {'', none, ''} end
  
  return xhtml.div {
    html5_title "SMTP eMail server",
    connectionsTable (smtp.iprequests),
    sortedTable ("Registered email sender IPs:", smtp.destinations, function(x) return not x:match "@" end),
    sortedTable ("Registered destination mailboxes:", smtp.destinations, function(x) return x:match "@" end),
    t }
end

function pages.pop3 ()
  local T = xhtml.div {}
  local header = "Mailbox '%s': %d messages, %0.1f (kB)"
  local accounts = pop3.accounts    
  for name, folder in pairs (accounts) do
    local mbx = pop3.mailbox.open (folder)
    local total, bytes = mbx: status()
    
    local t = xhtml.table {class = "w3-small w3-card w3-padding"}
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
  
  return xhtml.div {
    html5_title "POP3 eMail client server",
    connectionsTable (ioutil.udp.iprequests), T}
end

function pages.udp ()
  local t0 = xhtml.table {class = "w3-small w3-card w3-padding"}
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
  
  local t = xhtml.table {class = "w3-small w3-card w3-padding"}
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
  
  return xhtml.div {
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
  local t = create_table_from_data (columns, data, function (row, i) row[1] = i end)
  return page_wrapper ("Server sockets watched for incoming connections", t)
end


function pages.images ()
  local files = get_matching_files_from ("images/", '^[^%.]+%.[^%.]+$')     -- *.*
  local data = {}
  for i,f in ipairs (files) do 
    data[#data+1] = {i, xhtml.a {target="image", href="images/" .. f.name, f.name}}
  end
  local index = create_table_from_data ({'#', "filename"}, data)
  local div = xhtml.div
  return div {
      html5_title "Image files in images/ folder",
      div {class = "w3-row",
        div {class = "w3-container w3-quarter", index} ,
        div {class = "w3-container w3-rest", 
          xhtml.iframe {style= "border: none;", width="100%", height="500px", name="image"}},
      }}
end


function pages.trash (p)
  -- empty?
  if (p.AreYouSure or '') :lower() :match "yes" then    -- empty the trash
    luup.call_action ("openLuup", "EmptyTrash", {AreYouSure = "yes"}, 2)
    local continue = xhtml.a {class="w3-button w3-round w3-green",
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
  local empty = xhtml.a {class="w3-button w3-round w3-red",
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
  local t0 = xhtml.table {class = "w3-small"}
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

    t0.header { {"Disk archive folder: " .. folder, colspan = 2} }
    t0.row {"updates/min", dp1 (write_rate)}
    t0.row {"time/point (ms)", dp1(wall_rate)}
    t0.row {"cpu/point (ms)", dp1(cpu_rate)}
    
    t0.row {"total size (Mb)", rhs (T - T % 0.1)}
    t0.row {"total # files", rhs (N)}
    t0.row {"total # updates", rhs (tot)}
  end

  local div = xhtml.div {html5_title "Data Historian statistics summary", t0}
  return div
end

function pages.cache ()
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
      
  local t = xhtml.table {class = "w3-small"}
  t.header {"device ", "service", "#points", "value",
    {"variable (archived if checked)", title="note that the checkbox field \n is currently READONLY"} }
  
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
        local link = "page=graphics&target=%s&from=%s"
        vname = xhtml.a {href= selfref (link: format (finderName, from, vname)), vname}
      end
    end
    local h = #v.history / 2
    local dname = devname(v.dev)
    if dname ~= prev then 
      t.row { {xhtml.b {dname}, colspan = 5} }
    end
    prev = dname
    local check = archived and 1 or nil
    local tick = xhtml.input {type="checkbox", readonly=1, checked = check} 
    local short_service_name = v.srv: match "[^:]+$" or v.srv
    t.row {'', short_service_name, h, v.value, xhtml.span {tick, ' ', vname}}
  end
  
  local div = xhtml.div {html5_title "Data Historian in-memory Cache", t}
  return div
end


local function database_tables ()
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
          local link = "page=graphics&target=%s&from=-%s"  -- relative time
          for arch in a.retentions: gmatch "[^,]+" do
            local _, duration = arch: match "([^:]+):(.+)"                  -- rate:duration
            links[#links+1] = xhtml.a {href = selfref (link: format (a.finderName, duration)), arch}
          end
          a.links = xhtml.span (links)
        end
        return a
      end
    end)
  
  table.sort (files, keysort)
  
  local function link_to_editor (name)
    local link = name
    if whisper_edit then 
      link = xhtml.a {
        href = table.concat {"/cgi/whisper-edit.lua?target=", folder, name, ".wsp"}, 
                                target = "_blank", name}
    end
    return link
  end
  
  local t = xhtml.table {class = "w3-small"}
  local t2 = xhtml.table {class = "w3-small"}
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
      t.row { {xhtml.strong {'[', f.devnum, '] ', f.description}, colspan = 6} }
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
function pages.file_cache (p)  
  local info = {}
  for name in vfs.dir() do 
    local v = vfs.attributes (name) 
    local d = (v.access ~= 0) and todate (v.access) or ''
    info[#info+1] = {name, d, v.hits, v.size, name} 
  end

  -- sorting according to sidebar menu selection
  local key = {}
  local options = {"Sort by...", "Last Access", "Cache Hits", "File Size", "File Name"}
  for i,v in ipairs(options) do key[v] = i end
  local sort_by = p.sort or options[1]
  local sort_menu = sidebar (p, function () return filter_menu (options, sort_by, "sort=") end)
  if sort_by ~= options[1] and sort_by ~= options[5] then
    local index = key[sort_by] or 1
    table.sort (info, function (a,b) return a[index] > b[index] end)  -- reverse sort these columns
  end
  
  local N, H = 0, 0
  local t = create_table_from_data (
    {'#', "last access", "# hits", "bytes", "filename"}, info, 
    function (row, i) 
      H = H + row[3]      -- hits accumulator
      N = N + row[4]      -- size accumulator
      row[1] = i          -- replace primary sort key with line number
      row[3] = rhs (row[3])
      row[4] = rhs (row[4])
      row[5] = xhtml.a {target="_parent", 
        href = selfref ("page=viewer&file=" ..row[5]), row[5]} -- add link to view file
    end)  
  local strong = xhtml.strong
  t:row { '', '', strong {H}, strong {math.floor (N/1000 + 0.5), " (kB)"}, strong {"Total"}}
  
  local div = xhtml.div {
    html5_title "File Server Cache", sort_menu,
    xhtml.div {class = "w3-panel w3-rest", t} }
  return div
end

--
-- Devices
--

local function get_display_variables (d)
  local svcs = d.services
  local vars = (svcs[SID.altui] or {}).variables or {}
  local line1, line2
  
  -- AltUI Display variables
  local dl1 = (vars.DisplayLine1 or {}) .value
  local dl2 = (vars.DisplayLine2 or {}) .value
  if dl1 or dl2 then return dl1 or '', dl2 or '' end
  
  -- common services
  local temp = (svcs[SID.temp] or {}).variables or {}
  local humid = (svcs[SID.humid] or {}).variables or {}
  if temp or humid then 
    temp  = (temp.CurrentTemperature or {}).value
    humid = (humid.CurrentLevel or {}).value
    if temp  then temp = temp .. '°' end
    if humid then humid = humid .. '%' end
    if humid and temp then temp = temp .. ", " end
    return xhtml.span {class="w3-large ", temp or '', humid}
  end
  
  
  return line1, line2
end

local function device_controls (d)
  local switch, slider = ' ',' '
  local srv = d.services[SID.switch]
  if srv then    -- we need an on/off switch
--    local Target = (srv.variables.Target or {}).value == "1" and 1 or nil
    switch = xhtml.form {
      action=selfref (), method="post", 
        xhtml.input {name="action", value="switch", hidden=1},
        xhtml.input {name="dev", value=d.attributes.id, hidden=1},
        xhtml.input {type="image", class="w3-hover-opacity",
          src="/icons/power-off-solid.svg", alt='on/off', height=24, width=24}
--        html5.input {type="checkbox", class="switch", checked=Target, name="switch", onchange="this.form.submit();" }
      }
  end
  srv = d.services[SID.dimming]
  if srv then    -- we need a slider
    local LoadLevelTarget = (srv.variables.LoadLevelTarget or {}).value or 0
    slider = xhtml.form {
      oninput="LoadLevelTarget.value = slider.valueAsNumber + ' %'",
      action=selfref (), method="post", 
        xhtml.input {name="action", value="slider", hidden=1},
        xhtml.input {name="dev", value=d.attributes.id, hidden=1},
        xhtml.output {name="LoadLevelTarget", ["for"]="slider", value=LoadLevelTarget, LoadLevelTarget .. '%'},
        xhtml.input {type="range", name="slider", onchange="this.form.submit();",
          value=LoadLevelTarget, min=0, max=100, step=1},
      }
  end
  return switch, slider
end

local function device_panel (self)          -- 2019.05.12
  local id = self.attributes.id
  local line1, line2 = get_display_variables (self)
  local img = get_device_icon (self)
  
  local flag = unicode.white_star
  if self.attributes.bookmark == "1" then flag = unicode.black_star end
  local bookmark = xhtml.a {class = "nodec w3-hover-opacity", href=selfref("action=bookmark&dev=", id), flag}
  
  local battery = (((self.services[SID.ha] or {}) .variables or {}) .BatteryLevel or {}) .value
  battery = battery and (battery .. '%') or ' '
  
  local switch, slider = device_controls(self)
  local div, span = xhtml.div, xhtml.span
  local panel = xhtml.div {class = "w3-small w3-margin-left w3-margin-bottom w3-round w3-border w3-card dev-panel", 
    div {class="top-panel", 
      bookmark, ' ', truncate (devname (id)), span{style="float: right;", battery }},
    div {class = "w3-row", style="height:54px; padding:2px;", 
      div {class="w3-col", style="width:50px;", img} , 
      div {class="w3-padding-small w3-rest w3-display-container", style="height:50px;",
        line1, xhtml.br{}, line2,
        div {class="w3-display-topright w3-padding-small", switch},
        div {class="w3-display-bottommiddle", slider},
        } } }
  return panel
end

-- generic device page
local function device_page (p, fct)
  local devNo = tonumber (p.device) or 2
  local d = luup.devices[devNo]
  local title = devname(devNo) 
  fct = d and fct or function (_, t) return t .. " - no such device" end
  return page_wrapper (fct (d, title))   -- call back with actual device    
end

function pages.control (p)
  return device_page (p, function (d, title)
    local dtype = (d.attributes.device_type or ''): match "(%w+):?%d*$"   -- pick the last word
    local user = user_defined[dtype] or {}
    local t = xhtml.table {class = "w3-small"}
    local s
    if user.control then 
      local user_control = user.control (d.attributes.id)     -- either HTML DOM tree, or...
      if type (user_control) == "string" then                 -- ... text/html string
        local x = xml.decode (user_control)
        user_control = x.documentElement
      end
      s = xhtml.div {class="w3-rest", user_control} 
    end
    local states = d:get_shortcodes ()
    for n,v in sorted (states) do t.row {n, nice(v)} end
    return title .. " - status and control", 
      xhtml.div {class="w3-row", 
        xhtml.div{class="w3-col", style="width:350px;", device_panel(d), t}, s}
  end)
end

function pages.attributes (p, req)
  return device_page (p, function (d, title)
    local q = req.POST
    local name = q.attribute
    local value = q.value
    if name and value and d.attributes[name] then d:attr_set (name, value) end -- only change existing attribute
    --
    local attr = xhtml.div{class = "w3-container"}
    for n,v in sorted (d.attributes) do 
      attr[#attr+1] = xhtml.form{
        class = "w3-form w3-padding-small", method="post", style="float:left", action=selfref(),
        xhtml.label {xhtml.b{n}}, 
        xhtml.input {hidden=1, name="page", value="attributes"},
        xhtml.input {hidden=1, name="attribute", value=n},
        xhtml.input {class="w3-input w3-round w3-border w3-hover-border-red",type="text", size=28, 
          name="value", value = nice(v, 99), autocomplete="off", onchange="this.form.submit()"} }
    end
    return title .. " - attributes", attr
  end)
end

function pages.cache_history (p)
  return device_page (p, function (d, title)
    local vnum = tonumber(p.variable)
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
    local t = xhtml.table {class = "w3-small"}
    t.header {"id", "service", '', "variable", "value"}
    local info = {}
    local history, graph = ' ', ' '
    for n,v in pairs (d.variables) do
      if v.history and #v.history > 2 then 
        history = xhtml.a {href=selfref ("page=cache_history&variable=", n), title="history", 
                xhtml.img {width="18px;", height="18px;", alt="history", src="/icons/calendar-alt-regular.svg"}} 
        graph = xhtml.a {href=selfref ("page=graphics&variable=", n), title="graph", 
                xhtml.img {width="18px;", height="18px;", alt="graph", src="/icons/chart-bar-solid.svg"}}
      end
      local actions = xhtml.div {history, graph}
      info[#info+1] = {v.id, v.srv, actions, v.name, nice(v.value) }
    end
    for _, row in ipairs (info) do 
      local serviceId = row[2]
      row[2] = {title = serviceId, row[2]: match "%w+$"}      -- add mouse-over pop-up serviceId
      row[4] = {title = serviceId, row[4]}                    -- ditto
      t.row (row) 
    end
    return title .. " - variables", t
  end)
end

function pages.actions (p)
  return device_page (p, function (d, title)
    local devNo = d.attributes.id
    local t = xhtml.div {class = "w3-container "}
    for s,srv in sorted (d.services) do
      local service_actions = (service_data[s] or {}) .actions
      local action_index = {}         -- service actions indexed by name
      for _, act in ipairs (service_actions or {}) do
        action_index[act.name] = act.argumentList or {}
      end
      for a in sorted (srv.actions) do
        local args = xhtml.div {class="w3-container w3-cell"}
        local form = xhtml.form {method="post", action=selfref (),
          xhtml.input {hidden=1, name="action", value="call_action"},
          xhtml.input {hidden=1, name="dev", value=devNo},
          xhtml.input {hidden=1, name="srv", value=s},
          xhtml.div{class = "w3-container w3-cell", style="width:250px;",
            xhtml.input {class="w3-button w3-round w3-blue", type="submit", name="act", title=s, value=a} },
            args}
        t[#t+1] = xhtml.div {class="w3-cell-row w3-border-top w3-padding", form}
        local action_arguments = action_index[a]
        if action_arguments then
          for _, v in ipairs (action_arguments) do
            if (v.direction or ''): match "in" then 
              args[#args+1] = xhtml.div {
                xhtml.label {class= "w3-small", v.name},
                xhtml.input {class="w3-input w3-border w3-hover-border-red", type="text", size= 40, name = v.name} }
            end
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
      for _, event in ipairs (eventList2) do
          e[#e+1] = {event.id, event.label.text}
      end
    end
    table.sort (e, function (a,b) return a[1] < b[1] end)
    local t = create_table_from_data (columns, e)
    t.class = nil     -- remove "w3-small"
    return title .. " - generated events", t
  end)
end

function pages.user_data (p)
  return device_page (p, function (d, title)
    local j, err
    local dnum = tonumber (p.device) or 2
    local dtable = userdata.devices_table {[dnum] = d}
    j, err = json.encode (dtable)
    local readonly = true
    return title .. " - JSON user_data", 
--      xhtml.div {class = "w3-panel w3-border", xhtml.pre {j or err} }
      xhtml.div {code_editor (j or "[]", 500, "json", readonly)}

  end)
end

local function scene_filter (p)
  return filter_menu ({"All Scenes", "Runnable", "Paused"}, p.scn_sort, "scn_sort=")
end

local function device_sort (p)
  return filter_menu ({"Sort by Name", "Sort by Id"}, p.dev_sort, "dev_sort=")
end

local function rooms_selector (p)
  local rooms = {}
  for _,r in pairs (luup.rooms) do rooms[#rooms+1] = r end
  table.sort (rooms)
  table.insert (rooms, 1, "No Room")    -- note reverse order
  table.insert (rooms, 1, "Favourites")
  table.insert (rooms, 1, "All Rooms")
  return filter_menu (rooms, p.room, "room=")
end

-- returns a function to decide whether given room number is in selected set
local function room_wanted (p)
  local room = p.room or "All Rooms"
  local bookmarks = room == "Favourites"
  local room_index = {["No Room"] = 0}
  for n, r in pairs (luup.rooms) do room_index[r] = n end
  local all_rooms = room == "All Rooms"
  local room_number = room_index[room]
  return function (x)  -- works for devices or scenes
    local room_match = all_rooms or x.room_num == room_number
    local scene_favorite = x.page and x:user_table().favorite               -- only scenes have pages
    local device_favorite = x.attributes and x.attributes.bookmark == '1'   -- only devices have attributes
    local bookmarked = scene_favorite or device_favorite
    return room_match or (bookmarks and bookmarked)
  end
end

-- returns an iterator which sorts items, key= "Sort by Name" or "Sort by Id" 
local function sorted_by_id_or_name (p, tbl)
  local x = {}
  local by_name = p.dev_sort == "Sort by Name"
  for id, item in pairs (tbl) do 
    x[#x+1] = {item = item, key = by_name and item.description or id} 
  end
  table.sort (x, function (a,b) return a.key < b.key end)
  local i = 0
  return function() i = i + 1 return (x[i] or {}).item end
end

-- devices   
function pages.devices (p)  
  local devs = xhtml.div {class="w3-rest" }
  local wanted = room_wanted(p)        -- get function to filter by room
  
  for d in sorted_by_id_or_name (p, luup.devices) do
    if wanted(d) then devs[#devs+1] = device_panel (d) end
  end

  local room_nav = sidebar (p, rooms_selector, device_sort)
  local ddiv = xhtml.div {room_nav, xhtml.div {class="w3-rest", devs} }
  return ddiv
end

--
-- ["Scene"] = {"header", "triggers", "timers", "lua", "group_actions", "json"},
--

-- generic scene page
local function scene_page (p, fct)
  local i = tonumber(p.scene)
  local s = luup.scenes[i]
  local title = scene_name (i) 
  fct = s and fct or function (_, t) return t .. " - no such scene" end
  return page_wrapper (fct (s, title))   -- call back with actual scene    
end
local function scene_panel (self)
  local utab = self: user_table()
  
  --TODO: move scene next run code to scenes module
  local id = utab.id
  local earliest_time
  for _,timer in ipairs (utab.timers or {}) do
    local next_run = timer.next_run 
    if next_run and timer.enabled == 1 then
      earliest_time = math.min (earliest_time or next_run,  next_run)
    end
  end
  local next_run = earliest_time and table.concat {unicode.clock_three, ' ', nice (earliest_time) or ''}
  local last_run = utab.last_run
  last_run = last_run and table.concat {unicode.check_mark, ' ', nice (last_run)} or ''
  
  local div = xhtml.div
  local d, wh, woo = 28, 18, 14
  local run = self.paused 
          and 
              xhtml.img {width=d, height=d, 
                title="scene is paused", src="icons/pause-solid.svg"} 
          or
              xhtml.a {href= selfref("action=run_scene&scn=", id), class = "w3-hover-opacity",
                xhtml.img {width=d, height=d, title="run scene", src="icons/play-solid.svg"} }
  
  local edit_clone_history = xhtml.span {class="w3-wide",
    xhtml.a {href= selfref("page=header&scene=", id), title="view/edit scene", class="w3-margin-right w3-hover-opacity",
      xhtml.img {width=wh, height=wh, src="icons/edit.svg"} },
    xhtml.a {href= selfref("action=clone&scene=", id), title="clone scene", class="w3-margin-right w3-hover-opacity",
      xhtml.img {width=wh, height=wh, src="icons/clone.svg"} },
    xhtml.a {href= selfref("page=history&scene=", id), title="scene history", class="w3-margin-right w3-hover-opacity",
      xhtml.img {width=wh, height=wh, src="icons/calendar-alt-regular.svg"} } }
  local flag = utab.favorite and unicode.black_star or unicode.white_star
  local bookmark = xhtml.a {class="nodec  w3-hover-opacity", href=selfref("action=bookmark&scn=", id), flag}
  local br = xhtml.br {}
  local on_off = xhtml.a {href= selfref("action=toggle_pause&scn=", id), title="toggle pause", class="w3-hover-opacity",
      xhtml.img {width=woo, height=woo, src="icons/power-off-solid.svg"} }
  local highlight = self.paused and '' or "w3-hover-border-red"
  local panel = xhtml.div {class = "w3-small w3-margin-left w3-margin-bottom w3-round w3-border w3-card scn-panel",
    div {class="top-panel", bookmark, ' ', truncate (scene_name(id)), xhtml.span{style="float: right;", on_off } }, 
    div {class = "w3-display-container", style ="height:70px",
      div {class="w3-padding-small w3-margin-left w3-display-left " .. highlight, 
        style = "border:2px solid grey; border-radius: 4px;", run } , 
      div {class="w3-padding-small w3-display-topright", last_run, br, next_run } ,
      div {class="w3-padding-small w3-display-bottomright", edit_clone_history } 
      }  } 
  return panel
end

function pages.header (p)
  return scene_page (p, function (scene, title)
    local modes = scene: user_table() .modeStatus
    return title .. " - scene header", 
      xhtml.div {class="w3-row", 
        xhtml.div{class="w3-col", style="width:550px;", 
          xhtml.div {class = "w3-container", scene_panel(scene)}, 
          xhtml.div {class = "w3-container w3-margin-left w3-padding w3-hover-border-red w3-round w3-border",
            xhtml.h6 "Active modes (all if none selected)",
            house_mode_group (modes) }}}
  end)
end

function pages.triggers (p)
  return scene_page (p, function (scene, title)
    local pre = xhtml.pre {json.encode (scene:user_table() .triggers)}
    return title .. " - scene triggers", pre
  end)
end

function pages.timers (p)
  return scene_page (p, function (scene, title)
    local pre = xhtml.pre {json.encode (scene:user_table() .timers)}
    return title .. " - scene timers", pre
  end)
end

function pages.history (p)
  return scene_page (p, function (scene, title)
    local h = {}
    for i,v in ipairs (scene: user_table() .openLuup.history) do h[i] = {nice(v.at), v.by} end
    table.sort (h, function (a,b) return a[1] > b[1] end)
    local t = create_table_from_data  ({"date/time", "initiated by"}, h)
    return title .. " - scene history", t
  end)
end
  
function pages.lua (p)
  return scene_page (p, function (scene, title)
    local readonly = true
    local Lua = scene:user_table() .lua
    return title .. " - scene Lua", 
      xhtml.div {code_editor (Lua, 500, "lua", readonly)}
  end)
end
 
function pages.group_actions (p)
  return scene_page (p, function (scene, title)
    local pre = xhtml.pre {json.encode (scene:user_table() .groups)}
    return title .. " - actions (in delay groups)", pre
  end)
end
 
function pages.json (p)
  return scene_page (p, function (scene, title)
    local readonly = true
    return title .. " - JSON scene definition",
      xhtml.div {code_editor (tostring(scene), 500, "json", readonly)}
  end)
end

local function paused_or_not (p, s)
  local f = p.scn_sort
  return f == "All Scenes" or (f == "Paused") and s.paused or (f ~= "Paused") and not s.paused
end

-- scenes   
function pages.scenes (p)  
  local wanted = room_wanted(p)        -- get function to filter by room
  local scenes = {style="margin-left:12em; " }
  for s in sorted_by_id_or_name (p, luup.scenes) do
    if wanted(s) and paused_or_not(p, s) then
      scenes[#scenes+1] = scene_panel (s)
    end
  end
  local room_nav = sidebar (p, rooms_selector, device_sort, scene_filter)
  local section = xhtml.section (scenes)
  return xhtml.div {room_nav, section}
end

 
---------------------------------------
--
-- Editor/Viewer - may use Ace editor if configured, else just textarea
--

-- save some user_data.attribute Lua, and for some types, run it and return the printer output
-- two key input parameters: lua_code and codename
-- if both present, then update the relevant userdata code
-- either may be absent - if no code, then codename userdata is run, if code and codename, then it's updated
function XMLHttpRequest.submit_lua (p)
  local v, r = "valid", "runnable"
  local valid_name = {
    StartupCode = v, ShutdownCode = v,
    LuaTestCode = r, LuaTestCode2 = r, LuaTestCode3 = r}
  
  local newcode = p.lua_code
  local codename = p.codename
  if not codename then return "No code name!" end
  
  local valid = valid_name[codename]
  if not valid then return "Named code does not exist in user_data: " .. codename end
  
  local code = newcode or userdata.attributes[codename]
  userdata.attributes[codename] = code        -- possibly update the value
  if valid ~= "runnable" then return '' end
  
  local P = {''}            ---lines and time---
  local function prt (...)
    local x = {...}         -- NB: some of these parameters may be nil, hence use of select()
    for i = 1, select('#', ...) do P[#P+1] = tostring(x[i]); P[#P+1] = ' \t' end
    P[#P] = '\n'
  end
  
  local cpu = timers.cpu_clock()
  local ok, err = loader.compile_and_run (code, codename, prt)
  cpu = ("%0.1f"): format(1000 * (timers.cpu_clock() - cpu))
  if not ok then prt ("ERROR: " .. err) end
  
  local N = #P - 1
  P[1] = table.concat {"--- ", N, " line", N == 1 and '' or 's', " --- ", cpu, " ms --- ", "\n"}
  local printed = table.concat (P)
--  local _, nlines = printed:gsub ('\n',{})    -- the proper way to count lines
  return printed
end

-- text editor
function code_editor (code, height, language, readonly, codename)
  local h = xhtml
  if not code or code == '' then code = ' ' end   -- ensure non-empty code div
  codename = codename or ' '
  height = (height or "500") .. "px;"
  language = language or "lua"
--  local submit_button = h.input {class="w3-button w3-round w3-green w3-margin", value="Submit"}
  local submit_button
  
  if options.Ace_URL ~= '' then
    if not readonly then 
      submit_button = h.p {class="w3-button w3-round w3-green w3-margin", onclick = "EditorSubmit()", "Submit"}
    end
    local page = h.div {id="editor", class="w3-border", style = "width: 100%; height:"..height, code }
    local form = xhtml.form {
      action= "/data_request?id=XMLHttpRequest&action=submit_lua&codename=" .. codename, 
      method="post", 
      target = "output", 
      h.input {type="hidden", name="lua_code", id="lua_code"}, 
      submit_button}
    local ace = h.script {src = options.Ace_URL, type="text/javascript", charset="utf-8"}
    local script = h.script {
    'var editor = ace.edit("editor");',
    'editor.setTheme("ace/theme/', options.EditorTheme, '");',
    'editor.session.setMode("ace/mode/', language,'");',            -- also mode: "ace/mode/javascript",
    'editor.session.setOptions({tabSize: 2, readOnly: '.. tostring(not not readonly) .. '});',
    [[function EditorSubmit() {
      var element = document.getElementById("lua_code");
      element.value = ace.edit("editor").getSession().getValue();
      element.form.submit();}
    ]]}
    return ace, page, form, script
  
  else  -- use plain old textarea for editing
    if not readonly then 
      submit_button = h.input {class="w3-button w3-round w3-green w3-margin", value="Submit", type = "submit"}
    end
    local form = h.form {action= selfref (), method="post",
      h.div {
        h.textarea {name="lua_code", id="lua_code", 
          style = table.concat {
            "width: 100%; resize: none; height:", height,
            "font-family:Monaco, Menlo, Ubuntu Mono, Consolas, ", 
                        "source-code-pro, monospace; font-size:9pt; line-height: 1.3;"},
          code}},
      submit_button}
    return form
  
  end
end

-- editable (but not runnable) pages
local function lua_edit (codename, height)
  local readonly = false
  return xhtml.div {
    xhtml.iframe {name = "output", style="display: none;"},    -- hidden output area for response page
    code_editor (userdata.attributes[codename], height, "lua", readonly, codename)}
end

function pages.lua_startup   () return page_wrapper ("Lua Startup Code",  lua_edit "StartupCode")  end
function pages.lua_shutdown  () return page_wrapper ("Lua Shutdown Code", lua_edit "ShutdownCode") end

-- editable and runnable pages
local function lua_exec (codename, title)
  local form =  xhtml.div {class = "w3-col w3-half",
    html5_title (title or codename),  code_editor (userdata.attributes[codename], 500, "lua", false, codename) }  
  local output = xhtml.div {class="w3-half", style="padding-left:16px;", 
    html5_title "Console Output:", 
    xhtml.iframe {name="output", height="500px", width="100%", 
      style="border:1px grey; background-color:white; overflow:scroll"} }
  return xhtml.div {class="w3-row", form, output}
end

pages["lua_test"]   = function () return lua_exec ("LuaTestCode",  "Lua Test Code")    end
pages["lua_test2"]  = function () return lua_exec ("LuaTestCode2", "Lua Test Code #2") end
pages["lua_test3"]  = function () return lua_exec ("LuaTestCode3", "Lua Test Code #3") end

-- read-only view of files
function pages.viewer (_, req)
  local mode = setmetatable ({js = "javascript"}, {__index=function(_,x) return x end}) -- special case
  local file = req.params.file or ''
  local language = file: match "%w+$" or ''
  local text = loader.raw_read (file) or ''
  local readonly = true
  local div = xhtml.div {code_editor (text, 500, mode[language], readonly)}
  return page_wrapper (file,  div)
end

function pages.graphics (p, req)
  local background = p.background or "GhostWhite"
  return xhtml.iframe {
    height = "450px", width = "96%", 
    style= "margin-left: 2%; margin-top:30px; background-color:"..background,
    src="/render?" .. req.query_string}
end

function pages.create_room ()
   local form = xhtml.form {class = "w3-container w3-form w3-third", 
    action = selfref "page=rooms_table", method="post",
    xhtml.label {"Room name"},
    xhtml.input {class="w3-input w3-border w3-hover-border-red", type="text", name="name", autocomplete="off", },
    xhtml.input {class="w3-button w3-round w3-red w3-margin", type="submit", value="Create Room"},
  }
  return xhtml.div {class="w3.card", form} 
end

function pages.rooms_table (p, req)
  local function room_count (tbl)
    local room = {}
    for _,x in pairs (tbl) do
      local r = x.room_num
      room[r] = (room[r] or 0) + 1
    end
    return room
  end
  if req.method == "POST" and p.name then
    luup.rooms.create (p.name)
  end
  local droom = room_count (luup.devices)
  local sroom = room_count (luup.scenes)
  local create = xhtml.a {class="w3-button w3-round w3-green", 
    href = selfref "page=create_room", "+ Create", title="create new room"}
  local t = xhtml.table {class = "w3-small w3-hoverable"}
  t.header {"id", "name", "#devices", "#scenes"}
  t.row {0, "No Room", rhs(droom[0] or 0), rhs(sroom[0] or 0)}
  for n, v in sorted (luup.rooms) do
    t.row {n,v, rhs(droom[n] or 0), rhs(sroom[n] or 0)}
  end
  return page_wrapper ("Rooms Table", create, t)
end

function pages.device_created (_,req)
  local q = req.params
  local name = q.name or ''
  if not name:match "%w" then name = "_New_Device_" end
  local div
  if q.name ~= '' and q.d_file and q.i_file then
    local devNo = luup.create_device (nil, '', q.name, q.d_file, q.i_file)
    if devNo then     -- offer to go there
      div = xhtml.div {
        xhtml.p {"Device #" , devNo, " created"},
        xhtml.a {class="w3-button w3-green w3-round", 
          href=selfref "page=device&device=" .. devNo, "Go to new device page"}}
    else
      div = xhtml.p "Error creating device"
    end
  end
  return div
end

function pages.create_device ()
  local function options (label_text, name, pattern, value)
    local listname = name .. "_options"
    local label = xhtml.label {label_text}
    local input = xhtml.input {list=listname, name=name, value=value, class="w3-input"}
    local datalist = xhtml.datalist {id= listname}
    for file in loader.dir (pattern) do
      datalist[#datalist+1] = xhtml.option {value=file}
    end
    return xhtml.div {label, input, datalist}
  end

  local form = xhtml.form {class = "w3-container w3-form w3-third", 
    action = selfref "page=device_created", method="post",
    xhtml.label {"Device name"},
    xhtml.input {class="w3-input w3-border w3-hover-border-red", type="text", name="name", autocomplete="off", },
    options ("Device file", "d_file", "^D_.-%.xml$", "D_"),
    options ("Implementation file", "i_file", "^I_.-%.xml$", "I_"),
    xhtml.input {class="w3-button w3-round w3-red w3-margin", type="submit", value="Create Device"},
  }
  return xhtml.div {class="w3.card", form}
end

function pages.devices_table (p)
  local create = xhtml.a {class="w3-button w3-round w3-green", 
    href = selfref "page=create_device", "+ Create", title="create new device"}
  local t = xhtml.table {class = "w3-small w3-hoverable"}
  t.header {"id", "name", "favourite", "room"}  
  local wanted = room_wanted(p)        -- get function to filter by room  
  for d in sorted_by_id_or_name (p, luup.devices) do
    local devNo = d.attributes.id
    if wanted(d) then t.row {devNo, xhtml.a {href = selfref "page=control&device="..devNo, d.description}, 
        d.attributes.bookmark or '0', luup.rooms[d.room_num] or "no room"} end
  end
  local room_nav = sidebar (p, rooms_selector, device_sort)
  local ddiv = xhtml.div {room_nav, xhtml.div {class="w3-rest w3-panel", create, t} }
  return page_wrapper ("Devices Table", ddiv)
end

function pages.scene_created (_,req)
  local q = req.params
  local name = q.name or ''
  if not name:match "%w" then name = "_New_Scene_" end
  local div
  if q.name ~= '' then
    local scn = scenes.create {name = name}
    local scnNo = scn:user_table().id
    local msg = "Scene #%d '%s' created"
    if scnNo then     -- offer to go there
      luup.scenes[scnNo] = scn      -- insert into scene table
      div = xhtml.div {
        xhtml.p (msg: format (scnNo,name)),
        xhtml.a {class="w3-button w3-green w3-round", 
          href=selfref "page=scene&scene=" .. scnNo, "Go to new scene page"}}
    else
      div = xhtml.p "Error creating scene"
    end
  end
  return div
end

function pages.create_scene ()
   local form = xhtml.form {class = "w3-container w3-form w3-third", 
    action = selfref "page=scene_created", method="post",
    xhtml.label {"Scene name"},
    xhtml.input {class="w3-input w3-border w3-hover-border-red", type="text", name="name", autocomplete="off", },
    xhtml.input {class="w3-button w3-round w3-red w3-margin", type="submit", value="Create Scene"},
  }
  return xhtml.div {class="w3.card", form} 
end

function pages.scenes_table (p)
  local create = xhtml.a {class="w3-button w3-round w3-green", 
    href = selfref "page=create_scene", "+ Create", title="create new scene"}
  local scn = {}
  local wanted = room_wanted(p)        -- get function to filter by room  
  for x in sorted_by_id_or_name (p, luup.scenes) do
    local u = x: user_table()
    local n = u.id
    if wanted(x) and paused_or_not(p, x) then 
      scn[#scn+1] = {n,  xhtml.a {href = selfref "page=header&scene="..n, x.description}, 
        x:user_table().favorite, luup.rooms[x.room_num] or "no room", tostring (x.paused)}
    end
  end
  local t = create_table_from_data ({"id", "name", "favourite", "room", "paused"}, scn)  
  t.class = "w3-small w3-hoverable"
  local room_nav = sidebar (p, rooms_selector, device_sort, scene_filter)
  local sdiv = xhtml.div {room_nav, xhtml.div {class="w3-rest w3-panel", create, t} }
  return page_wrapper ("Scenes Table", sdiv)
end

function pages.plugins_table ()
  local t = xhtml.table {class = "w3-bordered"}
  t.header {'', "Name","Version", "Auto", "Files", "Actions", "Update", '', "Unistall"}
  local IP2 = userdata.attributes.InstalledPlugins2 or userdata.default_plugins
  for _, p in ipairs (IP2) do
    -- http://apps.mios.com/plugin.php?id=8246
    local src = p.Icon or ''
    local mios_plugin = src: match "^plugins/icons/"
    if mios_plugin then src = "http://apps.mios.com/" .. src end
    local icon = xhtml.img {src=src, alt="no icon", height=35, width=35} 
    local version = table.concat ({p.VersionMajor, p.VersionMinor}, '.')
    local files = {}
    for _, f in ipairs (p.Files or {}) do files[#files+1] = f.SourceName end
    table.sort (files)
--    local choice = {style="width:12em;", onchange="location = this.value;", 
    local choice = {style="width:12em;", name="file", onchange="this.form.submit()", 
      xhtml.option {value='', "Files", disabled=1, selected=1}}
    for _, f in ipairs (files) do choice[#choice+1] = xhtml.option {value=f, f} end
    files = xhtml.form {action=selfref(), 
      xhtml.input {hidden=1, name="page", value="viewer"},
      xhtml.select (choice)}
    local help = xhtml.a {href=p.Instructions or '', target="_blank", title="help",
      xhtml.img {src="/icons/question-circle-solid.svg", alt="help", height=24, width=24} }
    local info = xhtml.a {target="_blank", title="info",
      href=table.concat {"http://github.com/",p.Repository.source or '',"#readme"}, 
      xhtml.img {src="/icons/info-circle-solid.svg", alt="info", height=24, width=24} }
    local update = xhtml.form {
      action = selfref(), method="post",
      xhtml.input {hidden=1, name="action", value="update_plugin"},
      xhtml.input {hidden=1, name="plugin", value=p.id},
      xhtml.div {class="w3-display-container",
        xhtml.input {class="w3-hover-border-red", type = "text", autocomplete="off", name="version", value=''},
        xhtml.input {class="w3-display-right", type="image", src="/icons/retweet.svg", 
          title="update", alt='', height=28, width=28} } }
    t.row {icon, p.Title, version, p.AutoUpdate, files, xhtml.span{help, info}, update, ''} 
  end
  return page_wrapper ("Plugins", t)
end

function pages.about () 
  local function embedded_links (t)   -- replace embedded http reference with real links
    local s = {}
    local function p (...) for _,x in ipairs {...} do s[#s+1] = x end; end
    local c = 1
    t = tostring(t)
    repeat
      local a,b = t:find ("http%S+", c)
      if a then 
        p (t:sub (c, a-1), t:sub (a,b))
        c = b + 1
      else
        if c < #t then p (t:sub(c,-1)) end
      end
    until not a
    for i = 2,#s,2 do s[i] = xhtml.a {href=s[i], target="_blank", s[i]} end  -- add link
    return s
  end
  local ABOUTopenLuup = luup.devices[2].environment.ABOUT   -- use openLuup about, not console
  local t = xhtml.table {class = "w3-table-all w3-cell w3-card"}
  for a,b in sorted (ABOUTopenLuup) do
    t.row { xhtml.b {a},  xhtml.pre (embedded_links(b))}
  end
  return t
end  

function pages.reload ()
  luup.log "Reload requested by openLuup console"
  local _,_, jno = scheduler.run_job {job = luup.reload}
  luup.log ("Shutdown job = " .. (jno or '?'))
  return page_wrapper "Please wait a moment while system reloads"
end

pages.reload_luup_engine = pages.reload    -- alias for top-level menu


-------------------------------------------


local a, div = xhtml.a, xhtml.div

function pages.home ()
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
    local pnames = div {class = "w3-bar w3-padding", 
      make_button (group, short_name(group))}    -- highlight the group name button
    for _, page in ipairs (pages) do
      pnames[#pnames+1] = make_button (page)
    end
    index[#index+1] = pnames
  end
  
  local house_mode = tonumber (luup.attr_get "Mode") 
  local hmg = house_mode_group (house_mode)
  hmg.class = hmg.class .. ' ' .. "w3-hover-border-red"
  
  return xhtml.div {
    xhtml.h4 "House Mode", hmg,
    xhtml.h4 {"Page Index"}, div(index)} 
end


local function page_nav (current, previous)
  local pagename = capitalise (current)
--  local onclick="document.getElementById('messages').style.display='block'" 
  local messages = div (xhtml.div {class="w3-button w3-round w3-border", "Messages ▼ "})
  messages.onclick="ShowHide('messages')" 
--  local msg = xhtml.div {class="w3-container w3-green w3-bar", 
--    xhtml.span {onclick="this.parentElement.style.display='none'",
--      class="w3-button", "x"},
--       nice (os.time()), ' ', "Click on the X to close this panel" }
  local tabs, groupname = page_group_buttons (current)
  return div {class="w3-container w3-row w3-margin-top",
    xhtml.span {class = "w3-container w3-cell w3-cell-middle w3-round w3-border w3-border-grey",
          a {class="nodec", href = selfref ("page=", previous), unicode.leftwards_double_arrow}, " / ", 
          a {class="nodec", href = selfref "page=home", "Home"},     " / ", 
          pagename}, 
      div {class="w3-container w3-cell", messages},
      div {class = "w3-panel w3-border w3-hide", id="messages",  
        "hello",
        },
      div {xhtml.h3 {groupname}, div (tabs) }}
end


-- dynamically build HTML menu from table structure {name, {items}, page}
local function dynamic_menu ()
  local icon = a {class = "w3-dropdown-hover w3-grey",
        href="/data_request?id=lr_ALTUI_Handler&command=home#", target="_blank",  
        xhtml.img {height=42, alt="openLuup", src="icons/openLuup.svg", class="w3-button"} }
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
          local onclick = confirm (item)            -- check for confirm box on reload
          dropdown_content[#dropdown_content+1] = 
            a {class="w3-bar-item w3-button" .. border, href=selfref ("page=", short_name(item)), onclick = onclick, item}
          border = ''
        end
      end
      dropdown[2] = div (dropdown_content)
    end
    menus[#menus+1] = div (dropdown)
  end)  
  return menus
end

local static_menu

----------------------------------------
-- run()
--

function run (wsapi_env)
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output
  local function noop() end
  
  local res = wsapi.response.new ()
  local req = wsapi.request.new (wsapi_env)

  script_name = req.script_name      -- save to use in links
  local h = xml.createHTMLDocument "openLuup"    -- the actual return HTML document
  local body

  local p = req.params  
  local P = capitalise (p.page or '')
  if page_groups[P] then p.page = page_groups[P][1] end     -- replace group name with first page in group
  
  local cookies = {page = "about", previous = "about",      -- cookie defaults
    device = "2", scene = "1", room = "All Rooms", dev_sort = "Sort by Name", scn_sort = "All Scenes"}
  for cookie in pairs (cookies) do
    if p[cookie] then 
      res: set_cookie (cookie, p[cookie])                   -- update cookie with URL parameter
    else
      p[cookie] = req.cookies[cookie] or cookies[cookie]     -- set any missing parameters from session cookies
    end
  end
  
  -- ACTIONS
  if p.action then
   (actions[p.action] or noop) (p, req)
  end
  
  -- PAGES
  if p.page ~= p.previous then res: set_cookie ("previous", p.page) end
  
  local navigation = page_nav (p.page, p.previous)

  local sheet = pages[p.page] (p, req)
  local formatted_page = div {class = "w3-container", navigation, sheet}
  
  static_menu = static_menu or dynamic_menu()    -- build the menu tree just once

  body = {
    static_menu,
    h.div {
      formatted_page,
      h.div {class="w3-footer w3-small w3-margin-top w3-border-top w3-border-grey", h.p {os.date "%c"}},
    }}
  
  h.documentElement[1]:appendChild {  -- the <HEAD> element
    h.meta {charset="utf-8", name="viewport", content="width=device-width, initial-scale=1"},
    h.link {rel="stylesheet", href="w3.css"},

    h.style {
  [[  
    pre {line-height: 1.1; font-size:10pt;}
    a.nodec { text-decoration: none; } 
    th,td {width:1px; white-space:nowrap; padding: 0 16px 0 16px;}
    table {table-layout: fixed; margin-top:20px}
    .dev-panel {width:240px; float:left; }
    .scn-panel {width:240px; float:left; }
    .top-panel {background:LightGrey; border-bottom:1px solid Grey; margin:0; padding:4px;}
    .top-panel-blue {background:LightBlue; border-bottom:1px solid Grey; margin:0; padding:4px;}
  ]]},
    
    h.script {
  [[
  function ShowHide(id) {
    var x = document.getElementById(id);
    if (x.className.indexOf("w3-show") == -1) {
      x.className += " w3-show";
    } else {
      x.className = x.className.replace(" w3-show", "");
    }
  }]]}}
  
  h.body.class = "w3-light-grey"
  h.body:appendChild (body)
  local html = tostring(h)
  res: write (html)  
  return res: finish()
end


-----
