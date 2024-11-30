#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "console.lua",
  VERSION       = "2024.04.14",
  DESCRIPTION   = "console UI for openLuup",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2024 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-2024 AK Booer

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

local ABOUTopenLuup = luup.devices[2].environment.ABOUT   -- use openLuup about, not console

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
-- 2018.07.12  add hyperlink backup files to uncompress and retrieve
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
-- 2019.08.20  add new "globals" page for individual devices

-- 2020.01.25  add openLuup watch triggers
-- 2020.01.27  start implementing object-oriented scene changes
-- 2020.02.05  use object-oriented dev:rename() rather than call to requests
-- 2020.02.12  add altid to Devices table (thanks @DesT)
-- 2020.02.19  fix missing discontiguous items in xselect() menu choices
-- 2020.03.08  added creation time to scenes table (thanks @DesT)
-- 2020.03.10  add "Move to Trash" button for orphaned historian files
-- 2020.03.17  remove autocomplete from action form parameters (passwords, etc...)
-- 2020.03.19  colour device panel header according to status
-- 2020.04.02  add App Store
-- 2020.06.28  add shared environment to pages.all_globals(), and pages.lua_globals() (thanks @a-lurker)
-- 2020.07.04  UK Covid-19 Independence Day edition! (add required_files page)
-- 2020.07.19  add cookie for plugin number (persistence with plugin JSON page, thanks @a-lurker)
-- 2020.11.17  use textarea rather than input for variables (for @therealdb)
-- 2020.12.31  add scene clone functionality (thanks @a-lurker)

-- 2021.01.09  developing scene UI
-- 2021.01.31  add MQTT server
-- 2021.03.11  @rafale77 change to slider position variable
-- 2021.03.18  add log_analysis() to pages.log
-- 2021.03.20  add pages.required for prerequisites and plugin dependencies
-- 2021.03.25  highlight log error lines in red (thanks @rafale77)
-- 2021.05.01  use native openLuup.json.Lua (for correct formatting)
-- 2021.05.02  add pseudo-service 'attributes' for consistent virtual access, and serviceId/shortSid to device object
-- 2021.05.12  add pages.rules for Historian archives, and interval buttons on Graphics page
-- 2021.06.22  change cache page clear icons to trash, and move to last column (thanks @a-lurker)
-- 2021.11.03  changed backup history download link to .lzap from .json (thanks @a-lurker)

-- 2022.07.13  fix +Create variable functionality (thanks @Donato)
-- 2022.11.06  make 'main' the default update repository for MetOffice_DataPoint plugin (no thanks to GitHub!)
-- 2022.12.21  enable history edit on variable page

-- 2023.02.10  add SameSite=Lax cookie attribute (to avoid browser console warning)
-- 2023.02.20  move some code to console_util.lua and reinstate openLuup_console.css in virtualfilesystem

-- 2024.02.08  add missing timer number in create_timer()
-- 2024.02.26  improve startup code and diagnostics
-- 2024.03.24  add subpages to MQTT server page
-- 2024.04.09  on/off switch toggles to opposite STATUS, not TARGET, add action.color() for color pickers


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
local mqtt      = require "openLuup.mqtt"
local ioutil    = require "openLuup.io"
local scenes    = require "openLuup.scenes"
local hist      = require "openLuup.historian"    -- for disk archive stats   
local timers    = require "openLuup.timers"       -- for startup time
local whisper   = require "openLuup.whisper"
local wsapi     = require "openLuup.wsapi"        -- for response library
local loader    = require "openLuup.loader"       -- for static data (devices page)
local json      = require "openLuup.json"         -- for console_menus.json
local panels    = require "openLuup.panels"       -- for default console device panels
local xml       = require "openLuup.xml"          -- for HTML constructors
local tables    = require "openLuup.servertables" -- for serviceIds
local devices   = require "openLuup.devices"      -- for cache size
local https     = require "ssl.https"             -- for w3.css download
local ltn12     = require "ltn12"                 -- ditto


local pretty = loader.shared_environment.pretty   -- for debugging

local script_name  -- name of this CGI script
local function selfref (...) return table.concat {script_name, '?', ...} end   -- for use in hrefs

local X, U = require "openLuup.console_util" (selfref)  -- xhtml, utilities

local delete_link = X.delete_link
--local xoptions = X.options
local xselect = X.select
--local xinput = X.input
local xlink = X.link
local rhs = X.rhs
local lhs = X.lhs
local get_user_html_as_dom = X.get_user_html_as_dom
local create_table_from_data = X.create_table_from_data
local code_editor = X.code_editor
local lua_scene_editor = X.lua_scene_editor
local generic_panel = X.generic_panel
local find_plugin = X.find_plugin

local todate = U.todate
local todate_ms = U.todate_ms
local truncate = U.truncate
local nice = U.nice
local commas = U.commas
local dhms = U.dhms
local sorted = U.sorted
local mapFiles = U.mapFiles
local get_matching_files_from = U.get_matching_files_from
local devname = U.devname
local scene_name = U.scene_name
local missing_index_metatable = U.missing_index_metatable


json = json.Lua         -- 2021.05.01  force native openLuup.json module for encode/decode

local xhtml     = xml.createHTMLDocument ()       -- factory for all HTML tags

local options   -- configuration options filled in during initialisation()
--[[
      Menu ="",           -- add menu JSON definition file here
      Ace_URL = "https://cdnjs.cloudflare.com/ajax/libs/ace/1.4.11/ace.js",
      EditorTheme = "eclipse",
]]
--

local service_data  = loader.service_data

local unicode = {
--  double_vertical_bar = "&#x23F8;",
--  black_right_pointing_triangle ="&#x25B6",
--black_right_pointing_triangle = json.decode '["\\u25B6"]' [1],   -- honestly, this works!
  black_down_pointing_triangle ="▼",
  leftwards_double_arrow = "⇐",
  clock_three = "◷",     -- actually, WHITE CIRCLE WITH UPPER RIGHT QUADRANT
  black_star  = "★",
  white_star  = "☆",
  check_mark  = "✓",  
  times       = '×',    -- muktiplication sign × (for close boxes)
--  cross_mark  = "&#x2718;",
--  pencil      = "&#x270e;",
--  power       = "&#x23FB;",     -- NB. not yet commonly implemented.
  nbsp        = json.decode '["\\u00A0"]' [1],
}


local pages = setmetatable ({}, missing_index_metatable "Page")

local actions = setmetatable ({}, missing_index_metatable "Action")

local readonly_meta = {__newindex = function() error ("read-only", 2) end}

local READONLY = function(x) return setmetatable (x, readonly_meta) end

local empty = READONLY {}


----------------------------------------


local SID = tables.SID

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.
 
-- switch dynamically between different menu styles
local menu_json = "openLuup_menus.json"     -- default

-- remove spaces from multi-word names and create index
local short_name_index = {}       -- long names indexed by short names
local function short_name(name) 
  local short = name: gsub('%s+','_'): lower()
  short_name_index[short] = name
  return short
end
 
local page_groups = {
    ["Apps"]      = {"plugins_table", "app_store", "luup_files", "required_files"},
    ["Historian"] = {"summary", "rules", "cache", "database", "orphans"},
    ["System"]    = {"parameters", "top_level", "all_globals", "states", "sandboxes", "RELOAD"},
    ["Device"]    = {"control", "attributes", "variables", "actions", "events", "globals", "user_data"},
    ["Scene"]     = {"header", "triggers", "timers", "history", "lua", "group_actions", "json"},
    ["Scheduler"] = {"running", "completed", "startup", "plugins", "delays", "watches"},
    ["Servers"]   = {"sockets", "http", "mqtt", "smtp", "pop3", "udp", "file_cache"},
    ["Utilities"] = {"backups", "images", "trash"},
    ["Lua Code"]  = {"lua_startup", "lua_shutdown", "lua_globals", "lua_test", "lua_test2", "lua_test3"},
    ["Tables"]    = {"rooms_table", "devices_table", "scenes_table", "triggers_table", "ip_table"},
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
local user_defined = panels.device_panel
--local user_defined = {
--    openLuup = {control = function() return 
--        '<div><a class="w3-text-blue", href="https://www.justgiving.com/DataYours/" target="_blank">' ..
--          "If you like openLuup, you could DONATE to Cancer Research UK right here</a>" ..
--          "<p>...or from the link in the page footer below</p></div>" end}
--  }
for f in loader.dir "^U_.-%.lua$" do
  local name = f: match "^U_(.-)%.lua$"
  local ok, user = pcall (require, "U_" .. name)
  if ok then user_defined[name] = user end
end

local state =  scheduler.state_name

-- restore the leading capital in each word and convert underscores to spaces
local function capitalise (x)
  return x :gsub ('_', ' ') :gsub ("(%w)(%w*)", function (a,b) return a:upper() .. b end)
end

local function user_defined_ui (d)
  local dtype = (d.attributes.device_type or ''): match "(%w+):?%d*$"   -- pick the last word
  return user_defined and user_defined[dtype] or empty
end

local function get_device_icon (d)
  local img  
  -- user-defined icon
  local user = user_defined_ui (d)
  if user.icon then 
    img = get_user_html_as_dom (user.icon(d.attributes.id))
  else
    local icon = d:get_icon ()
    if icon ~= '' and not icon: lower() : match "^http" then icon = "/icons/" .. icon end
    img = xhtml.img {title="control panel", src = icon, alt="no icon", style = "width:50px; height:50px;"}
  end

  return xhtml.a {href=selfref ("page=control&device=", d.attributes.id), img}
end

-- return HTML for navigation tree of current / previous pages
-- (used at top of all pages and also at bottom of logs, to aid navigation)
local function page_tree (current, previous)
  local pagename = capitalise (current)
  return xhtml.span {class = "w3-container w3-cell w3-cell-middle w3-round w3-border w3-border-grey",
          xhtml.a {class="nodec", href = selfref ("page=", previous), unicode.leftwards_double_arrow}, " / ", 
          xhtml.a {class="nodec", href = selfref "page=home", "Home"},     " / ", 
          pagename}
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
    return X.ButtonLink {title=name, class=colour, selfref="mode=" .. number,
      X.Icon {alt=name, src=icon}}
  end
  
  return xhtml.div {class = "w3-cell w3-bar w3-padding w3-round w3-border",
    mode_button (1, "/icons/home-solid-grey.svg"), 
    mode_button (2, "/icons/car-side-solid-grey.svg"),
    mode_button (3, "/icons/moon-solid-grey.svg"),
    mode_button (4, "/icons/plane-solid-grey.svg"),
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
  return X.ButtonLink {class=colour, selfref="page="..short, onclick=onclick, icon}
end
  
-- return the appropriate set of page buttons for the current page 
-- you can also use group name as a page... 
local function page_group_buttons (page)  
  local groupname = page_groups_index[page] 
                    or capitalise (page)    -- restore the leading capital
  local group = page_groups[groupname]  or empty
  local tabs = {}
  for _, name in ipairs (group) do 
    tabs[#tabs+1] = make_button (name, page) 
  end
  return tabs, groupname
end

-- build a vertical menu for the sidebar
local function filter_menu (items, current_item, request)
  local menu = xhtml.div {class = "w3-margin-bottom  w3-border w3-border-grey"}
  for i, item in ipairs (items) do
    local name = (type(item) == "table") and item[1] or item  -- can be string or list
    local colour = (name == current_item) and "w3-grey" or "w3-light-gray"
    menu[i] = xhtml.a {class = "w3-bar-item w3-button "..colour, href = selfref (request, name), item }
  end
  return xhtml.div {class="w3-bar-block w3-col", style="width:12em;", menu}
end


-- returns an iterator which sorts items, key= "Sort by Name" or "Sort by Id" 
-- works for devices, scenes, and variables
local function sorted_by_id_or_name (p, tbl)  -- _or_description
  local sort_options = {
    ["Sort by Id"]    = function (_, id) return id end,   -- NB: NOT the same as x.id (which is altid)!
    ["Sort by Name"]  = function (x) return x.description or x.name end,    -- name is for variables
    ["Sort by Date"]  = function (x) return -((x.definition or empty).Timestamp or 0) end} -- for scenes only
  local sort_index = sort_options[p.dev_sort] or function () end
  local x = {}
  for id, item in pairs (tbl) do 
    x[#x+1] = {item = item, key = sort_index(item, id) or id} 
  end
  table.sort (x, function (a,b) return a.key < b.key end)
  local i = 0
  return function() i = i + 1 return (x[i] or empty).item end
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
  local console = json.decode(console_json) or empty
  for _, menu in ipairs (console.menus or {}) do fct (menu) end
end

-- find the local AltUI plugin device number
local function find_AltUI ()
  for i,d in pairs (luup.devices) do
    if d.device_type == "urn:schemas-upnp-org:device:altui:1"
    and d.attributes.id_parent == 0 then 
      return i
    end
  end
end

-- find all the AltUI device watch triggers
-- optional scene number return triggers for that scene only
local function altui_device_watches (scn_no)
  local watches = {}
  local altui_dn = find_AltUI()
  if altui_dn then
    local w = luup.variable_get ("urn:upnp-org:serviceId:altui1", "VariablesToWatch", altui_dn) or ''
    for s,v,d,x,l in w: gmatch "([^#]+)#([^#]+)#0%-([^#]+)#([^#]+)#([^#]+)#;?" do
      local srv, dev, scn = s:match "%w+$", tonumber (d), tonumber(x)   -- short serviceId, devNo, scnNo
      if not scn_no or scn == scn_no then
        watches[#watches+1] = {srv = srv, var = v, dev = dev, scn = scn, lua = l}
      end
    end
  end
  return watches
end

-- find all the native Luup triggers (ignored/disabled by openLuup)
local function luup_triggers (scn_no)
  local triggers = {}
  local scenes = scn_no and {[scn_no] = luup.scenes[scn_no]} or luup.scenes
  for s, scn in pairs (scenes) do
    local info = scn.definition --.triggers
    for _, t in ipairs (info.triggers or {}) do
      local devNo = t.device
--      if devNo ~= 2 then    -- else ignore openLuup trigger warning
        local json = ((luup.devices[devNo] or empty).attributes or empty).device_json
        local events = (loader.static_data[json] or empty) .eventList2 or empty
        local template = events[tonumber(t.template or 0)] or empty
        local args = {}
        for i, arg in ipairs (t.arguments or empty) do args[i] = arg.value end
        local text = (template.label or empty) . text or '?'
        triggers[#triggers+1] = {scn = s, name = t.name, dev = devNo, text = text, args = args}
--      end
    end
  end
  return triggers
end


-- form to allow variable value updates
-- {table of hidden form parameters}, value to display and change
--local function editable_text (hidden, value)
--  local form = X.Form{
--    xhtml.input {class="w3-border w3-hover-border-red",type="text", size=28, 
--      name="value", value=nice(value, 99), autocomplete="off", onchange="this.form.submit()"} }
--  for n,v in pairs (hidden) do form[#form+1] = xhtml.input {hidden=1, name=n, value=v} end
--  return form
--end

-- 2020.11.17  resizable textbox
local function editable_text (hidden, value, maxlen)
  local text = nice(value, maxlen or 99)
  local _, nrows = text: gsub ("\n","\n") 
  local form = X.Form{  
    xhtml.textarea {class="w3-border w3-hover-border-red akb-resize", cols="40", rows=tostring(math.min(nrows+1,20)),
      name="value", autocomplete="off", onchange="this.form.submit()", text} }
  for n,v in pairs (hidden) do 
    form[#form+1] = X.Hidden {[n] = v} 
  end
  return form
end

-- HTML link to whisper-edit CGI
local function whisper_edit (name, folder)
  local link = name
    if folder then 
    local img = xhtml.img {height=14, width=14, alt="edit", src="icons/edit.svg"}
    link = xhtml.a {class = "w3-hover-opacity", title="edit", 
      href = table.concat {"/cgi/whisper-edit.lua?target=", folder, name, ".wsp"}, 
      target = "_blank", img}
    end
  return link or ''
end

-----------------------------

local function red (...) return xhtml.span {class = "w3-red", ...}  end
local function page_wrapper (title, ...) return xhtml.div {X.Title (title), ...} end


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
    local a = scn.definition
    a.favorite = not a.favorite
  end
end

function actions.clear_cache (p)
  local d = luup.devices[tonumber(p.dev)]
  if d then
    local v = d.variables[tonumber(p.variable)] or {name = "UNKNOWN"}
    if v then   -- empty cache by turning off and on again
      v: disableCache()
      v:  enableCache()
    end
  end
end

function actions.toggle_pause (p)
  local scene = luup.scenes[tonumber (p.scn)]
  if scene then scene: on_off() end
end

function actions.run_scene (p)
  local scene = luup.scenes[tonumber (p.scn)]
  if scene then scene: run (nil, nil, {actor = "openLuup console"}) end    -- TODO: run this asynchronously?
end

-- input from an HTML color picker
-- color parameter is hex #RRGGBB
function actions.color (_, req)
  local q = req.params        -- works for GET or POST
  local devNo = tonumber(q.dev)
  local dev = luup.devices[devNo]
  if dev then 
    local color = q.color or ''
    local r,g,b = color: match "#(%x%x)(%x%x)(%x%x)"
    r = tonumber(r, 16) or 0
    g = tonumber(g, 16) or 0
    b = tonumber(b, 16) or 0
    local w = 0
    local rgbw = table.concat ({r,g,b,w}, ',')
    -- use luup.call_action() so that child device actions are handled by parent, if necessary
    local aa,bb,j = luup.call_action (SID.color, "SetColorRGB", {newColorRGBTarget=rgbw}, devNo) 
    local _={aa,bb,j}   -- TODO: status return to messages?
  end
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
--    local v = luup.variable_get (SID.switch, "Target", devNo)
    local v = luup.variable_get (SID.switch, "Status", devNo)     -- 2024.04.09  toggle to opposite STATUS
    local target = v == '1' and '0' or '1'    -- toggle action
    -- this uses luup.call_action() so that bridged device actions are handled by VeraBridge
    local a,b,j = luup.call_action (SID.switch, "SetTarget", {newTargetValue=target}, devNo) 
    local _={a,b,j}   -- TODO: status return to messages?
  end
end

-- action=update_plugin&plugin=openLuup&update=version
function actions.update_plugin (_, req)
  local default_repository = {
      MetOffice_DataPoint = "main",     -- GitHub changed the default repository name
    }
  local q = req.params
  local v = q.version
  v = (#v > 0) and v or default_repository[q.plugin] or "master"
  requests.update_plugin ('', {Plugin=q.plugin, Version=v})
  -- actual update is asynchronous, so return is not useful
end

-- action=call_action (_, req)
function actions.call_action (_, req)
  local q = req.POST    -- it must be a post in order to loop through the params
  if q then
    local act, srv, dev = q.act, q.srv, q.dev
    q.act, q.srv, q.dev = nil, nil, nil     -- remove these and use the rest of the parameter list
--    print ("ACTION", act, srv, dev)
    -- action returns: error, message, jobNo, arguments
    local e,m,j,a = luup.call_action  (srv, act, q, tonumber (dev))
    local _ = {e,m,j,a}   -- TODO: write status return to message?
  end
end

-- delete a specific something
function actions.delete (p)
  local device = luup.devices[tonumber (p.device)]
  local scene = luup.scenes[tonumber (p.scene)]
  local defn = scene and scene.definition
  if p.rm then
    luup.rooms.delete (tonumber(p.rm))
  elseif p.dev then
    requests.device ('', {action = "delete", device = p.dev}) 
  elseif p.scn then
    scenes.delete (tonumber(p.scn))    -- 2020.01.27
  elseif p.var then
    if device then device: delete_single_var(tonumber(p.var)) end
  elseif p.trigger then
    table.remove (defn.triggers, tonumber(p.trigger))
    local new_defn = json.encode (defn)                     -- create new json definition
    requests.scene ('', {action="create", json=new_defn})   -- deals with deleting old and rebuilding triggers/timers
  elseif p.timer then
    table.remove (defn.timers, tonumber(p.timer))
    local new_defn = json.encode (defn)                     -- create new json definition
    requests.scene ('', {action="create", json=new_defn})   -- deals with deleting old and rebuilding triggers/timers
  elseif p.group then
    if p.act then
      local group = defn.groups[tonumber(p.group)]
      local actions = group.actions 
      table.remove (actions, tonumber(p.act))           -- remove just this action
    else
      table.remove (defn.groups, tonumber(p.group))     -- remove the whole delay group
    end
  elseif p.plugin and p.plugin ~= '' then
    requests.delete_plugin ('', {PluginNum = p.plugin})
  end
end

-- create a device
function actions.create_device (_,req)
  local q = req.params
  local name = q.name or ''
  if not name:match "%w" then name = "_New_Device_" end
  if q.name ~= '' and q.d_file and q.i_file then
    luup.create_device (nil, '', q.name, q.d_file, q.i_file)
  end
end

--- create or clone a scene

function actions.create_scene (_,req)
  local q = req.params
  local clone = tonumber(q.clone)
  clone = clone and luup.scenes[clone]
  local scn, name
  if clone then
    scn = clone: clone() 
    name = (clone.description or '') .. " - COPY"
  else
    scn = scenes.create {}
    name = q.name
  end
  local scnNo = scn.definition.id
  luup.scenes[scnNo] = scn            -- insert into scene table
  scn: rename(name or "_New_Scene_")  
--  p.page = "header"
--  p.scene = scnNo
end

-- create, or edit existing
function actions.create_trigger (p,req)
  local q = req.params
--  print (pretty {create_trigger={GET=p, POST=req.POST}})
  local scene = luup.scenes[tonumber (p.scene)]
  local defn = scene.definition
  local triggers = defn.triggers
  local trigger
  local svc_var = json.decode (q.svc_var or "{}")
  local svc, var = svc_var.svc, svc_var.var
  if svc and var then
    trigger = {
      name = q.name,
      lua = q.lua_code or '',
      enabled = 1,
      device = 2,             -- openLuup plugin
      template = "1",         -- this is the only action that the openLuup plugin defines
      arguments = {           -- these are the dev.svc.var parameters
        {id='1', value=q.dev},
        {id='2', value=svc},
        {id='3', value=var}}}
  end
  local tno = tonumber(q.trg) or #triggers+1    -- existing, or new
  triggers[tno] = trigger
  local new_defn = json.encode (scene.definition)
  requests.scene ('', {action="create", json=new_defn})   -- deals with deleting old and rebuilding triggers/timers
end

--[[

1=interval
    the interval tag has d / h / m for days / hours / minutes, 
    so 1h means every 1 hour, and 30m means every 30 minutes. 

2=day of week
    "days_of_week" indicates which days of the week (Sunday=0).
    
3=day of month
    "days_of_month" is a comma-separated list of the days of the month. 
    For types 2 & 3, "time" is the time. 
    If the time has a T or R at the end it means the time is relative to sunset or sunrise, 
    so -1:30:0R means 1hr 30 minutes before sunrise. 

4=absolute.
    the time has the day and time.

{
    "days_of_week":"1,2,3,4,5,6,7",
    "enabled":1,
    "id":1,
    "last_run":1623279540,
    "name":"Cinderella",
    "next_run":1623365940,
    "time":"23:59:00",
    "type":2
  }
  
--]]

-- convert args to timer format syntax
local function tformat (time, rel)
  local sign, event = rel: upper(): match "([%-%+]?)([RT]?)"   -- before/after, sunrise/sunset
  -- TODO: syntax check time field
  time = time .. ":00"   -- add seconds field
  if sign == '' and event ~= '' then time = "00:00:00" end    -- time is defined by actual sunrise/sunset
  return sign .. time .. event
end

-- create, or edit existing
function actions.create_timer (p,req)
  local q = req.params
--  print (pretty {create_timer=req.POST})
  local scene = luup.scenes[tonumber (p.scene)]
  local defn = scene.definition
  local ttype = tonumber (q.ttype)
  local timers = defn.timers
  local timer = {enabled = 1, name=q.name, type=ttype}
  local rise_or_set = {R = true, T = true} 
  if rise_or_set[q.relative] then q.time = "00:00" end    -- actual rise or set time
  local Timers = {
    function ()   -- Interval
      timer.interval = q.interval..(q.units or '')
     end,
    function ()  -- Day of Week
      local Day_of_Week = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
      local dow = {}
      for i, day in ipairs(Day_of_Week) do
        if q[day] then 
          dow[#dow+1] = i
        end
      end
      timer.days_of_week = table.concat (dow, ',')
      timer.time = tformat (q.time, q.relative)
    end,
    function ()   -- Day of Month
      timer.days_of_month = q.days
      timer.time = tformat (q.time, q.relative)
    end,
    function ()   -- Absolute
      local time_format           = "(%d%d?%:%d%d?)"
      local date_format           = "(%d%d%d%d%-%d%d?%-%d%d?)"
      local date_time_format      =  date_format .. "[Tt%s]+" .. time_format
      local d,t = q.datetime: match (date_time_format)
      timer.time = table.concat ({d, t}, ' ')
      timer.abstime = timer.time                -- special field?
    end}
  do (Timers[ttype] or tostring) () end
--  print(pretty {new_timer=timer})
  local tno = tonumber(q.tim) or #timers+1    -- existing, or new
  timer.id = tno              -- 2024.02.08  add missing timer number
  timers[tno] = timer
  local new_defn = json.encode (scene.definition)
  requests.scene ('', {action="create", json=new_defn})   -- deals with deleting old and rebuilding triggers/timers
end

--[[
{CREATE_ACTION = {
    dev = "2",
    existing = "",
    group = "1",
    names = '["Folder","MaxDays","MaxFiles","FileTypes"]',
    scn = "",
    svc_act = '{"svc":"openLuup", "act":"SendToTrash"}',
    value_1 = "fold",
    value_2 = "days",
    value_3 = "max",
    value_4 = "types"
  }}
--]]
function actions.create_action (p,req)
  local q = req.POST
--  print(pretty {CREATE_ACTION = q})
  local dno = tonumber (q.dev)
  local gno = tonumber (q.group)
  local svc_act = json.decode (q.svc_act or "{}")
  local svc, act
  if type (svc_act) == "table" then
    svc, act = svc_act.svc, svc_act.act
  end
  if dno and gno and svc and act then
    local names = json.decode (q.names) or empty
    local args = {}
    for i, name in ipairs (names) do
      args[#args+1] = {name=name, value=q["value_"..i] or ''}
    end
    local scene = luup.scenes[tonumber(p.scene)]
    local defn = scene.definition
    local group = defn.groups[gno]
    local actions = group.actions 
    local act_no = tonumber(q.existing) or #actions + 1
    actions[act_no] = {
      action = act,
      arguments = args,
      device = tostring(dno),
      service = svc}
  end
end

function actions.create_group (p, req)
  local scene = luup.scenes[tonumber(p.scene)]
  local defn = scene.definition
  local q = req.POST  
  local mm,ss = (q.delay or ''): match "(%d*):?(%d+)$"
  if mm and ss then 
    local delay = 60*mm + ss
    local groups = defn.groups
    groups[#groups+1] = {delay=delay, actions = {}}
    table.sort (groups, function (a,b) return a.delay < b.delay end)
  end
end

function actions.edit_scene_lua (p, req)
  local q = req.POST  
--  print(pretty {EDIT_SCENE_LUA = q, p =p})
  local scene = luup.scenes[tonumber (p.scene)]
  local defn = scene.definition
  defn.lua = q.lua_code or ''
  local new_defn = json.encode (scene.definition)
  requests.scene ('', {action="create", json=new_defn})   -- deals with deleting old and rebuilding triggers/timers
end

local function scene_filter (p)
  return filter_menu ({"All Scenes", "Runnable", "Paused"}, p.scn_sort, "scn_sort=")
end

local function device_sort (p)
  return filter_menu ({"Sort by Name", "Sort by Id"}, p.dev_sort, "dev_sort=")
end

local function scene_sort (p)
  return filter_menu ({"Sort by Name", "Sort by Id", "Sort by Date"}, p.dev_sort, "dev_sort=")
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
    local priority = j.priority or ''
    local n = j.logging.invocations
    local ok = scheduler.exit_state[status]
    if running then ok = not ok end
    if ok then
      jlist[#jlist+1] = {j.expiry, todate(j.expiry + 0.5), j.devNo or "system", priority, status, n, 
                          j.logging.cpu, -- cpu time in seconds, here
                          jn, j.type or '?', j.notes or ''}
    end
  end
  -----
  local columns = {'#', "date / time", "device", "priority", "status", "run", "hh:mm:ss.sss", "job #", "info", "notes"}
  local sort_function
  if running then 
    sort_function = function (a,b) return a[1] < b[1] end  -- normal sort for running jobs
  else
    sort_function = function (a,b) return a[1] > b[1] end  -- reverse sort for completed jobs
  end
  table.sort (jlist, sort_function)
  -----
  local milli = true
  local tbl = create_table_from_data (columns, jlist,
    function (row, i)
      row[1] = i
      row[5] = scheduler.error_state[row[5]] and red (state[row[5]]) or state[row[5]]
      row[7] = rhs (dhms (row[7], nil, milli))
      row[8] = rhs (row[8])
    end)
  return xhtml.div {class = "w3-responsive", page_wrapper(title, tbl) }	-- may be wide, let's scroll sideways
end

pages.running   = function (p) return jobs_tables (p, true,  "Jobs Currently Running") end
pages.completed = function (p) return jobs_tables (p, false, "Jobs Completed within last 3 minutes") end


function pages.plugins ()
  local i = 0
  local data = {}
  for n, dev in pairs (luup.devices) do
    local cpu  = dev.attributes["cpu(s)"]
    local wall = dev.attributes["wall(s)"]
    if cpu and wall then 
      i = i + 1
      local ratio = wall / (cpu + 1e-6)         -- microsecond resolution (avoid / 0)
      data[i] = {i, n, dev.status, cpu, wall, ratio, dev.description:match "%s*(.+)", dev.status_message or ''} 
    end
  end
  -----
  local columns = {'#', "device", "status", "hh:mm:ss.sss", "hh:mm:ss.sss", "wall/cpu", "name", "message"}
  local timecol = {'', '', '', rhs "(cpu)", rhs "(wall-clock)"}
  table.sort (data, function (a,b) return a[2] < b[2] end)
  -----
  local milli = true
  local one_dp = "%0.1f"
  local cpu = scheduler.system_cpu()
  local uptime = timers.timenow() - timers.loadtime
  local percent = cpu * 100 / uptime
  percent = one_dp: format (percent)
  local tbl = xhtml.table {class = "w3-small"}
  tbl.header (columns)
  tbl.header (timecol)
  for _, row in ipairs(data) do
    row[4] = rhs (dhms(row[4], nil, milli))
    row[5] = rhs (dhms(row[5], nil, milli))
    row[6] = rhs(one_dp: format (row[6]))
    tbl.row (row) 
  end
  local title = "Plugin CPU usage (%s%% system load, total uptime %s)"
  return page_wrapper(title: format (percent, dhms(uptime, true)), tbl)
end


function pages.startup ()
  local jlist = {}
  for _, b in ipairs (scheduler.startup_list) do
    local status = state[b.status] or ''
    jlist[#jlist+1] = {b.started or b.expiry, todate_ms(b.expiry + 0.5), b.devNo or "system", 
      b.priority or '', status, b.logging.cpu, b.jobNo or '', b.type or '?', b.notes or ''}
  end
  -----
  local columns = {"#", "date / time", "device", "priority", "status", "hh:mm:ss.sss", "job #", "info", "notes"}
  table.sort (jlist, function (a,b) return a[2] < b[2] end)
  -----
  local milli = true
  local tbl = xhtml.table {class = "w3-small"}
  tbl.header (columns)
  for i, row in ipairs (jlist) do
    row[1] = i
    if row[5] ~= "Done" then row[5] = red (row[5]) end
    row[6] = rhs (dhms(row[6], nil, milli))
    tbl.row (row)
  end
  local title = "Plugin Startup Jobs CPU usage (in startup order)"
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
  table.sort (W, function(a,b) return a[1] < b[1] end)
  -----
  local tbl = create_table_from_data (columns, W, function (row,i) row[1] = i end)
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
function pages.all_globals ()
  local ignore = {}
  local ignored = {"ABOUT", "_NAME", "lul_device"}
  for _, name in pairs (ignored) do ignore[name] = true end
  local function globals_in_env (env)
    local x = {}
    for n,v in pairs (env or empty) do 
      if not _G[n] and not ignore[n] and type(v) ~= "function" then x[n] = v end
    end
    return x
  end  
  
  local data = {}
  local columns = {'', "device", "variable", "value"}
  local function add_globals_to_data (x)
    for n,v in sorted (x) do
      data[#data+1] = {'','', n, tostring(v)}
    end
  end
  
  local function if_any_globals (g, link, title)
    if next(g) then 
      data[#data+1] = {link,{xhtml.strong {title}, colspan = #columns-1}}
      add_globals_to_data (g)
    end
  end
  
  -- loader.shared_environment
  local g = globals_in_env (loader.shared_environment)
  if_any_globals (g, xlink ("page=lua_globals"), "Shared environment (Startup / Shutdown / Test / Scenes...)")
  
  -- devices
  for dno,d in pairs (luup.devices) do
    local dname = devname (dno)
    local g = globals_in_env (d.environment)
    if_any_globals (g, xlink ("page=globals&device=" .. dno), dname)
  end 
  
  local tbl = create_table_from_data (nil, data)
  return page_wrapper("Plugin Globals (excluding functions)", tbl)
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

function pages.required_files ()
  local columns = {"module","version"}
  local reqs = loader.req_table
  local versions = reqs.versions
  local vs = {}
  local wanted = {"lfs", "ltn12", "md5", "mime", "socket", "ssl"}
  for _, n in pairs (wanted) do
    local v = versions[n]
    if v then vs[#vs+1] = {n, v} end
  end
  local tbl = create_table_from_data (columns, vs)
  
  local byp = {}
  local unwanted = {[0] = true, versions = true}
  for plugin, list in sorted (reqs) do
    if not unwanted[plugin] then
--      byp[#byp+1] = {{xhtml.strong {dev_or_scene_name (plugin, luup.devices)}, colspan = 2}}
      byp[#byp+1] = {{xhtml.strong {devname (plugin)}, colspan = 2}}
      for n in sorted (list) do
        byp[#byp+1] = {'', n}
      end
    end
  end
  local tbl2 = create_table_from_data (nil, byp)
  
  return page_wrapper("Required modules", 
    xhtml.h5 "Prerequisites", tbl, 
    xhtml.h5 "Required by Plugins", tbl2)
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
--      download = f.name: gsub (".lzap$",'') .. ".json",
      download = f.name,    -- 2021.11.03  Thanks @a-lurker
      f.name}
    data[#data+1] = {f.date, f.size, hyperlink} 
  end
  local tbl = create_table_from_data (columns, data)
  local backup = xhtml.div {
    X.ButtonLink {"Backup Now"; class="w3-light-green", href = "cgi-bin/cmh/backup.sh?", target="_blank"}}
  return page_wrapper("Backup directory: " .. dir, backup, tbl)
end

-- sandboxes
function pages.sandboxes ()               -- 2018.04.07
  local function format (tbl)
    local lookup = getmetatable (tbl).lookup
    local boxmsg = "[%d] %s - Private items:"
    local function devname (d) 
      return ((luup.devices[d] or empty).description or "System"): match "^%s*(.+)" 
    end
    local function sorted(x, title)
      local y = {}
      for k,v in pairs (x) do y[#y+1] = {k, tostring(v)} end
      table.sort (y, function (a,b) return a[1] < b[1] end)
      local t = xhtml.table {class="w3-small w3-hoverable w3-card w3-padding"}
      t.header {{title, colspan = 2}}
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
  
  local t = X.Container {}
  for n,v in pairs (_G) do
    local meta = ((type(v) == "table") and getmetatable(v)) or empty
    if meta.__newindex and meta.__tostring and meta.lookup then   -- not foolproof, but good enough?
      t[#t+1] = xhtml.p { n, ".sandbox"} 
      t[#t+1] = format(v)
    end
  end
  return page_wrapper ("Sandboxed system tables (by plugin)", t)
end

--------------------------------

-- 2021.03.18  analyze time gaps in log
-- 2021.03.25  highlight error lines in red (thanks @rafale77)

local function log_analysis (name)
  local n, at = 0, ''
  local max, old = 0
  local datetime = "%s %s:%s:%s"

  local mode = false
  local log               -- current list of contiguous log lines
  local logs = {}         -- list of log sections  
  local errlog = {}       -- list of just error lines

  if lfs.attributes (name) then
  
    for l in io.lines (name) do
      
      n = n + 1
      local err = l: lower(): match "%serror:?%s"
      if err then
        errlog[#errlog+1] = l
      end
      if err ~= mode then
        log = {class = err and "w3-text-red" or nil} 
        logs[#logs+1] = log
        mode = err
      end
      log[#log+1] = l

      local YMD, h,m,s = l: match "^%c*(%d+%-%d+%-%d+)%s+(%d+):(%d+):(%d+%.%d+)"
      if YMD then 
        local new = 60*(24*h+m)+s
        local dif = new - (old or new)
        if dif > max then 
          max = math.floor (dif + 0.5) 
          at = datetime: format (YMD, h,m,s)
        end
        old = new
      end
    end
    
  end
  
  return logs, n, max, at, errlog
end


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
  local logs, n, max, at, errlog = log_analysis (name)     -- 2021.03.18
  local nerr = #errlog
  if n > 0 then
    local info = "%d lines, %d error%s, max gap %ss @ %s"
    pre = xhtml.div {xhtml.span {info: format (n, nerr, nerr == 1 and '' or 's', max, at)}}
    for _, l in ipairs (logs) do
      local q = table.concat (l, '\n')
      pre[#pre + 1] = xhtml.pre {class = l.class, q}
    end
  end
  local message 
  if nerr > 0 then
    message = xhtml.pre {class = "w3-text-red", button = "w3-red", table.concat (errlog, '\n')}
  end
  local end_of_page_buttons = page_group_buttons (page)
  return page_wrapper(name, pre, xhtml.div {class="w3-container w3-row w3-margin-top",
      page_tree (page, p.previous), 
      xhtml.div {class="w3-container w3-cell", xhtml.div (end_of_page_buttons)}}),
      message
end

for i = 1,5 do pages["log." .. i] = pages.log end         -- add the older file versions
pages.startup_log = pages.log


-- socket & connections summary
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
  local t = create_table_from_data (columns, data, function (row, i) row[1] = i end)
  -----
  local c2 = {"server", "date / time", "#connects", "from IP"}
  local function connectionsTable (tbl, server, iprequests)
    local info = iprequests or {}
    info = next(info) and info or {[''] = {}} 
    for ip, req in pairs (info) do
      tbl[#tbl+1] = {server, req.date and todate(req.date) or '', req.count or 0, ip}
    end
  end
  local x = {}
  connectionsTable (x, "HTTP", server.iprequests)
  connectionsTable (x, "SMTP", smtp.iprequests)
  connectionsTable (x, "POP3", pop3.iprequests)
  connectionsTable (x, "UDP",  ioutil.udp.iprequests) 
  connectionsTable (x, "MQTT", mqtt.iprequests)
  local h2 = xhtml.h4 "Received connections"
  local t2 = create_table_from_data (c2, x)
  return page_wrapper ("Server sockets watched for incoming connections", t, h2, t2)
end

function pages.http (p)    
  local function status_number (n) if n ~= 200 then return red (n) end; return n end
  local function requestTable (requests, columns)
    local t = xhtml.table {class = "w3-small"}
    t.header (columns)
    for name, call in sorted (requests) do
      local count = call.count
      local status = call.status
      local include_zero = name: match "^id=lr_"
      if include_zero or (count and count > 0) then
        t.row {name, count or 0, status and status_number(status) or ''}
      end
    end
    if t.length() == 0 then t.row {'', "--- none ---", ''} end
    return xhtml.div {class = "w3-small", t}
  end
  
  local options = {"All Requests", "System", "User Defined", "CGI", "Files"}
  local request_type = p.type or options[1]
  local selection = sidebar (p, function () return filter_menu (options, request_type, "type=") end)
  
  local tbl = {}
  local all = request_type == options[1]
  local lu_ = request_type == options[2]   -- system request
  local lr_ = request_type == options[3]   -- user-defined request
  for n,v in pairs (server.http_handler) do
    local prefix = n: match "^lr_"
    local wanted = all or (prefix and lr_) or (not prefix and lu_)
    if wanted then tbl["id=" .. n] = v end
  end

  local cgi = request_type == options[4]
  for n,v in pairs (server.cgi_handler) do
    if all or cgi then tbl[n] = v end
  end
  
  local file = request_type == options[5]
  for n,v in pairs (server.file_handler) do
    if all or file then tbl[n] = v end
  end
  
  return page_wrapper ("HTTP Web server (port 3480)",
      selection,
      X.Panel {class="w3-rest", 
        requestTable (tbl, {"request", "#requests  ","status"}) } )
end

local function mqtt_statistics()
  local stats = {}
  local statistics = mqtt.statistics()
  for n, v in sorted (statistics) do
    local interval = n: match "(%d+)min" or '0'   -- '0', '1', '5', or '15'
    local tab = stats[interval] or {}
    stats[interval] = tab
    tab[#tab+1] = {n, commas (v)}
  end
  
  local title = {"", "load averages"}
  local totals = create_table_from_data ({}, stats['0'] or empty)

  local avgs = {}
  local t1, t5, t15 = stats['1'], stats['5'], stats['15']
  for i = 1,#t1 do
    local a1, a5, a15 = t1[i][2], t5[i][2], t15[i][2]
    local name = t1[i][1]: gsub("1min", '#')
    avgs[#avgs+1] = {name, a1, a5, a15}
  end
  local averages = create_table_from_data ({"Load Averages (per min)", "1 min", "5 min", "15 min"}, avgs)
  
  return xhtml.div {
    X.Subtitle "Server statistics: $SYS/broker/#",
    totals, averages}
end

local function mqtt_subscriptions()
  local n = 0
  local tbl = xhtml.table {class = "w3-small"}
  tbl.header {{colspan=2, "subscribers"}, "topic"}
  tbl.header {"#internal", "#external" }
  for topic, subscribers in sorted (mqtt.subscribers) do
    n = n + 1
    local internal, external = {}, {}
    for _, subs in pairs (subscribers) do
      internal[#internal+1] = subs.devNo
      external[#external+1] = (subs.client or empty) .ip
    end
    tbl.row {#internal, #external, topic}
  end
  return xhtml.div {X.Subtitle {"Subscribed topics: (", n , ')'}, tbl}
end

local function mqtt_publications()
  local n = 0
  local tbl = xhtml.table {class = "w3-small"}
  for topic in sorted (mqtt.publications) do
    n = n + 1
    tbl.row {topic}
  end
  return xhtml.div {X.Subtitle {"Published topics: (", n , ')'}, tbl}
end

local function mqtt_clients()
  local clients = {}
  for client in pairs(mqtt.clients) do
    local b = client.MQTT_connect_payload
    clients[#clients+1] = {b.ClientId, b.KeepAlive, b.WillTopic, b.WillMessage, b.WillRetain}
  end
  table.sort(clients, function(a,b) return a[1] < b[1] end)
  local title = {"ClientId", "KeepAlive (s)", "WillTopic", "WillMessage", "WillRetain"}
  local tbl = X.create_table_from_data(title, clients)
  return xhtml.div {X.Subtitle {"Connected Clients: (", #clients, ')'}, tbl}
end

local function mqtt_retained()
  local retained = {}
  for topic, message in sorted (mqtt.retained) do
    local msg = message: gsub ('%c',' ')          -- remove any non-printing chars
    retained[#retained+1] = {topic, msg}
  end
  local ret = create_table_from_data({"topic", "message"}, retained)
  return xhtml.div {X.Subtitle "Retained messages:", ret}
end

function pages.mqtt (p)
      
  local stats   = "Server Stats"
  local clients = "Clients"
  local pubs    = "Publications"
  local subs    = "Subscriptions"
  local retain  = "Retained"
  
--  local options = {stats, clients, pubs, subs, retain}
  local options = {stats, clients, subs, retain}
  
  local dispatch = {
      [stats]   = mqtt_statistics,
      [clients] = mqtt_clients,
      [pubs]    = mqtt_publications,
      [subs]    = mqtt_subscriptions,
      [retain]  = mqtt_retained,
    }
  
  local request_type = p.type or options[1]
  local selection = sidebar (p, function () return filter_menu (options, request_type, "type=") end)
  local result = (dispatch[request_type] or mqtt_statistics) ()
  
  return page_wrapper ("MQTT QoS 0 server",
      selection,
    X.Panel {class="w3-rest", result})

end

function pages.smtp (p)
  local function sortedTable (info, ok)
    local tbl = {}
    for ip, dest in sorted (info) do
      local name = devname (dest.devNo)
      if ok(ip) then  tbl[#tbl+1] = {ip, dest.count, name} end
    end
    return create_table_from_data ({"Address", "#sent", "for device"}, tbl)
  end  
  local options = {"Mailboxes", "Senders", "Blocked"}
  local request_type = p.type or options[1]
  local selection = sidebar (p, function () return filter_menu (options, request_type, "type=") end)
  
  local tbl = {}
  for email in pairs (smtp.blocked) do tbl[#tbl+1] = {email, '?'} end
  local t = create_table_from_data ({"eMail address","#attempts"}, tbl)
  
  return page_wrapper ("SMTP eMail server",
    selection,
    X.Panel {class="w3-rest", 
      X.Subtitle "Registered destination mailboxes:", 
      sortedTable (smtp.destinations, function(x) return x:match "@" end),
      X.Subtitle "Registered email sender IPs:", 
      sortedTable (smtp.destinations, function(x) return not x:match "@" end),
      X.Subtitle "Blocked senders:", t })
end

function pages.pop3 (p)
  local T = xhtml.div {}
  local header = "Mailbox '%s': %d messages, %0.1f (kB)"
  local accounts = pop3.accounts    
  
  local options = {}
  for n in sorted (accounts) do options[#options+1] = n end
  table.insert (options, 1, "All Mailboxes")
  local request_type = p.type or options[1]
  local selection = sidebar (p, function () return filter_menu (options, request_type, "type=") end)
  
  for name, folder in pairs (accounts) do
    local mbx = pop3.mailbox.open (folder)
    local total, bytes = mbx: status()
    
    local t = xhtml.table {class = "w3-small"}
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
  
  return page_wrapper ("POP3 eMail client server", 
    selection, X.Panel {class="w3-rest", T})
end

function pages.udp (p)
  local options = {"Listeners", "Destinations"}
  local request_type = p.type or options[1]
  local selection = sidebar (p, function () return filter_menu (options, request_type, "type=") end)
  ---
  local list = {}
  for port, x in sorted(ioutil.udp.listeners) do
    list[#list+1] = {port, x.count, devname (x.devNo)} 
  end
  local t0 = create_table_from_data ({"port", "#datagrams", "for device"}, list)
  -----
  list = {}
  for i, x in pairs(ioutil.udp.senders) do
    list[i] = {x.ip_and_port, devname (x.devNo)} --, x.count or 0}   -- doesn't yet count datagrams sent
  end
  table.sort (list, function (a,b) return a[1] < b[1] end)
  local t = create_table_from_data ({"ip:port", "by device"}, list)
  return page_wrapper ("UDP datagram ports", 
    selection,
    X.Panel {class="w3-rest", 
      X.Subtitle "Registered listeners", t0, 
      X.Subtitle "Datagram destinations", t})
end


function pages.images ()
  local files = get_matching_files_from ("images/", '^[^%.]+%.[^%.]+$')     -- *.*
  local data = {}
  for i,f in ipairs (files) do 
    data[#data+1] = {i, xhtml.a {target="image", href="images/" .. f.name, f.name}}
  end
  local index = create_table_from_data ({'#', "filename"}, data)
  return page_wrapper ("Image files in images/ folder",
      X.Container {class = "w3-row",
        X.Container {class = "w3-quarter", index} ,
        X.Container {class = "w3-rest", 
          xhtml.iframe {style= "border: none;", width="100%", height="500px", name="image"}},
      })
end


function pages.trash (p)
  -- empty?
  if (p.AreYouSure or '') :lower() :match "yes" then    -- empty the trash
    luup.call_action ("openLuup", "EmptyTrash", {AreYouSure = "yes"}, 2)
    local continue = X.ButtonLink {"Continue..."; selfref="page=trash"}
    return page_wrapper ("Trash folder being emptied", continue)
  end
  -- list files...
  local files = get_matching_files_from ("trash/", '^[^%.]')     -- *.* avoiding hidden files
  local data = {}
  for i,f in ipairs (files) do 
    data[#data+1] = {i, f.name, f.size}
  end
  local tbl = create_table_from_data ({'#', "filename", "size"}, data)
  local empty_trash = X.ButtonLink {"Empty Trash"; class="w3-red",
    onclick = "return confirm('Empty Trash: Are you sure?')", 
    selfref="page=trash&AreYouSure=yes"}
  return page_wrapper ("Files pending delete in trash/ folder", empty_trash, tbl)
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
  
  local folder = hist.folder ()
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
  return page_wrapper ("Data Historian statistics summary", t0)
end

function pages.cache ()
  -- find all the archived metrics
  local folder = hist.folder()
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
  t.header {"device ", "service", "#points", "value", "graph",
    {"variable (archived if checked)", title="note that the checkbox field \n is currently READONLY"}, "clear" }
  -- TODO: make cache checkbox enable on-disc archiving
  
  local prev  -- previous device (for formatting)
  for _, x in ipairs(H) do
    local v = x.v
    local finderName = hist.metrics.var2finder (v)
    local archived = archived[finderName]
    local graph, clear = '', ''
    if finderName then 
      local _,start = v:oldest()      -- get earliest entry in the cache (if any)
      if start then
        local from = timers.util.epoch2ISOdate (start + 1)    -- ensure we're AFTER the start... 
        local img = xhtml.img {height=14, width=14, alt="plot", src="icons/chart-bar-solid.svg"}
        local link = "page=graphics&target=%s&from=%s"
        graph = xhtml.a {class = "w3-hover-opacity", title="graph", 
          href= selfref (link: format (finderName, from)), img}
        clear = xhtml.a {href=selfref ("action=clear_cache&variable=", v.id + 1, "&dev=", v.dev), title="clear cache", 
--                  xhtml.img {width="18px;", height="14px;", alt="clear", src="/icons/undo-solid.svg"}}
    xhtml.img {height=14, width=14, alt="clear", src="icons/trash-alt-red.svg", class = "w3-hover-opacity"} }
      end
    end
    local h = #v.history / 2
    local dname = devname(v.dev)
    if dname ~= prev then 
      t.row { {xhtml.b {dname}, colspan = 5} }
    end
    prev = dname
    local check = archived and 1 or nil
    local tick = xhtml.input {type="checkbox", readonly=1, disabled=1, checked = check} 
    local short_service_name = v.srv: match "[^:]+$" or v.srv
    t.row {'', short_service_name, h, v.value, graph, xhtml.span {tick, ' ', v.name}, clear}
  end
  
  return page_wrapper ("Data Historian in-memory Cache", t)
end

local function database_tables ()
  local folder = hist.folder()
  
  if not folder then
    return "On-disk archiving not enabled"
  end
      
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
  
  local t = xhtml.table {class = "w3-small"}
  local t2 = xhtml.table {class = "w3-small"}
  t.header  {'', "archives", "(kB)", "fct", {"#updates", colspan=2}, "filename (node.dev.srv.var)" }
  t2.header {'', "archives", "(kB)", "fct", '', '', "filename (node.dev.srv.var)"}
  local prev
  local orphans = {}
  for _,f in ipairs (files) do 
    local devnum = f.devnum     -- openLuup device number (if present)
    local tbl = t
    if devnum == '' then
      tbl = t2
      orphans[#orphans+1] = f.name
    elseif devnum ~= prev then 
      t.row { {xhtml.strong {'[', f.devnum, '] ', f.description}, colspan = 6} }
    end
    prev = devnum
    tbl.row {'', f.links or f.retentions, f.size, f.fct, f.updates, whisper_edit (f.shortName, folder), f.shortName}
  end
  
  if t2.length() == 0 then t2.row {'', "--- none ---", ''} end
  return t, t2, orphans
end

pages.database = function (...) 
  local t, _ = database_tables() 
  return page_wrapper ("Data Historian Disk Database", t) 
end

pages.orphans = function (p) 
  local _, t, orphans = database_tables() 
  if p and p.TrashOrphans == "yes" then
    local folder = hist.folder ()
    for _, o in pairs (orphans) do
      local old, new = folder .. o, "trash/" ..o
      lfs.link (old, new)
      os.remove (old)
    end
    t = nil   -- they should all have gone (TODO: except folders... needs special handling)
  end
  local trash = xhtml.div {class = "w3-panel",
    X.ButtonLink {"Move All to Trash"; class="w3-red", 
      title="move all orphans to trash", selfref="TrashOrphans=yes", 
      onclick = "return confirm('Trash All Orphans: Are you sure?')" } }
  return page_wrapper ("Orphaned Database Files  - from non-existent devices", trash, t) 
end

pages.rules = function ()
  local t = xhtml.table {class = "w3-small"}
  local link = "https://graphite-api.readthedocs.io/en/latest/api.html#paths-and-wildcards"
  local title="click for pattern documentation"
  local plink = xhtml.a {href=link, title=title, target="_blank", "pattern (dev.shortSid.var)"}
  t.header {"#", plink, "archives", "aggregation", {"xff", title="xFilesFactor"}}
  local i = 0
  for _, r in ipairs (tables.archive_rules) do
    local ret = r.retentions: gsub (",%s*", ", ")
    for _, p in ipairs (r.patterns) do
      i = i + 1
      t.row {i, p, ret, r.aggregationMethod or "average", r.xFilesFactor or "0"}
    end
  end
  local t2 = xhtml.table {class = "w3-small"}
  t2.header {"#", "*.shortSID.* or *.*.Variable", "cache size"}
  local c = { {"OTHERWISE", devices.get_cache_size()} }
  for p, n in pairs (tables.cache_rules) do
    c[#c+1] = {p, n}
  end
  table.sort (c, function(a,b) return a[2]<b[2] or a[2]==b[2] and a[1]<b[1] end)  -- by size then name
  for k, r in ipairs(c) do 
    t2.row {k, r[1], r[2]}
  end
  return page_wrapper ("Historian Cache and Archive Rules", 
    X.Panel {
      X.Subtitle "Cache – sizes for specific services or variables", t2 ,
      xhtml.br {},
      X.Subtitle "Archives – first matching rule applies", t })
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
  t:header { '', '', rhs(H), rhs (math.floor (N/1000 + 0.5), " (kB)"), lhs "Total"}
  
  return page_wrapper ("File Server Cache", sort_menu,
   X.Panel {class = "w3-rest", t} )
end

--
-- Devices
--

local function get_display_variables (d)
  local svcs = d.services
  local vars = (svcs[SID.altui] or empty).variables or empty
  local line1, line2
  
  -- AltUI Display variables
  local dl1 = (vars.DisplayLine1 or empty) .value
  local dl2 = (vars.DisplayLine2 or empty) .value
  if dl1 or dl2 then return dl1 or '', dl2 or '' end
  
  -- common services
  local var  = {temp = "CurrentTemperature"}   -- default is CurrentLevel
  local unit = {temp = '°', humid = '%', light = " lux"}
  local function var_with_units (kind)
    local s =  svcs[SID[kind]]
    if s then 
      s = s.variables or empty
      local v = (s[var[kind] or "CurrentLevel"] or empty).value
      if v then return v .. (unit[kind] or '') end
    end
  end
  
  local temp  = var_with_units "temp"
  local humid = var_with_units "humid"
  local light = var_with_units "light"
  if temp or humid or light then 
    if humid and temp then temp = table.concat {temp, ", ", humid} end
    return xhtml.span {class="w3-large w3-text-dark-grey", temp or humid or light }
  end  
  
  return line1, line2
end

local function device_controls (d)
  local switch, slider, colour = ' ',' ', ' '
  local on_off_size = 20
  local srv = d.services[SID.switch]
  if srv then    -- we need an on/off switch
--    local Target = (srv.variables.Target or {}).value == "1" and 1 or nil
    switch = X.Form {
        X.Hidden {action = "switch", dev = d.attributes.id},
        xhtml.input {type="image", class="w3-hover-opacity", title = "on/off",
          src="/icons/power-off-solid.svg", alt='on/off', height=on_off_size, width=on_off_size}
--        html5.input {type="checkbox", class="switch", checked=Target, name="switch", onchange="this.form.submit();" }
      }
  end
  srv = not srv and d.services[SID.security]      -- don't want two!
  if srv then    -- we need an arm/disarm switch
--    local Target = (srv.variables.Target or {}).value == "1" and 1 or nil
    switch = X.Form {
        X.Hidden {action = "arm", dev = d.attributes.id},
        xhtml.input {type="image", class="w3-hover-opacity", title = "arm/disarm",
          src="/icons/power-off-solid.svg", alt='arm/disarm', height=on_off_size, width=on_off_size}  -- TODO: better arm/disarm icon
--        html5.input {type="checkbox", class="switch", checked=Target, name="switch", onchange="this.form.submit();" }
    }
  end
  srv = d.services[SID.dimming]
  if srv then    -- we need a slider
--    local LoadLevelTarget = (srv.variables.LoadLevelTarget or empty).value or 0
    local LoadLevelStatus = (srv.variables.LoadLevelStatus or empty).value or 0
    slider = X.Form {
      oninput="LoadLevelTarget.value = slider.valueAsNumber + ' %'",
        X.Hidden {action = "slider", dev = d.attributes.id},
        xhtml.output {name="LoadLevelStatus", ["for"]="slider", value=LoadLevelStatus, LoadLevelStatus .. '%'},
        xhtml.input {type="range", name="slider", onchange="this.form.submit();",
          value=LoadLevelStatus, min=0, max=100, step=1},
      }
  end
  srv = d.services[SID.color]
  if srv then    -- we need a colour picker
--    local LoadLevelTarget = (srv.variables.LoadLevelTarget or empty).value or 0
    local CurrentColor = (srv.variables.CurrentColor or empty).value or ''  -- format: "0=%d,1=%d,2=%d,3=%d" ie. wrgb
    local colors = {}
    for color, value in CurrentColor: gmatch "(%d)=(%d+)" do
      colors[color] = value
    end
    print(pretty(colors))
    local HexColor = '#'
    for color in ("123"): gmatch "%d" do       -- just RGB at the moment
      local hex = ("%02x"): format(colors[color] or 0)
      HexColor = HexColor .. hex
    end
    print("HEX", HexColor)
    colour = X.Form {
      oninput="LoadLevelTarget.value = slider.valueAsNumber + ' %'",
        X.Hidden {action = "color", dev = d.attributes.id},
        xhtml.input {type="color", name="color", onchange="this.form.submit();",
          value=HexColor},
      }
  end
  return switch, slider, colour
end

local function device_panel (self)          -- 2019.05.12
  local div, span = xhtml.div, xhtml.span
  local id = self.attributes.id
  local icon = get_device_icon (self)
  
  local top_panel do
    local flag = unicode.white_star
    if self.attributes.bookmark == "1" then flag = unicode.black_star end
    local bookmark = xhtml.a {class = "nodec w3-hover-opacity", href=selfref("action=bookmark&dev=", id), flag}
    
    local battery = (((self.services[SID.hadevice] or empty) .variables or empty) .BatteryLevel or empty) .value
    battery = battery and (battery .. '%') or ' '
    local state = self: status_get()
    -- states correspond to the scheduler job states
    -- colours to their AltUI (possibly Vera) representations
    local cs = {[0] = "-cyan", "-green", "-red", "-red", "-green", "-cyan", "-cyan", "-cyan"}
    top_panel = div {class="top-panel" .. (cs[state] or ''),
      bookmark, ' ', truncate (devname (id)), span{style="float: right;", battery }}
  end
  
  local main_panel do
    local user = user_defined_ui (self)
    local line1, line2 = get_display_variables (self)
    if user.panel then 
      main_panel = get_user_html_as_dom (user.panel (id))
    elseif line1 or line2 then
      main_panel = div {line1 or '', xhtml.br{}, line2 or ''}
    else
      local switch, slider, color = device_controls(self)
      local time = self: variable_get (SID.security, "LastTrip")
      time = time and div {class = "w3-tiny w3-display-bottomright", todate(tonumber(time.value)) or ''} or nil
      main_panel = div {
        div {class="w3-display-topright w3-padding-small", switch},
        div {class="w3-display-bottommiddle", slider},
        div {class="w3-display-topmiddle w3-padding-small", color},      -- 2024.04.09
        time}
    end
  end
  
  return div {class = "w3-small w3-margin-left w3-margin-bottom w3-round w3-border w3-card dev-panel", 
    top_panel,
    div {class = "w3-row", style="height:54px; padding:2px;", 
      div {class="w3-col", style="width:50px;", icon} , 
      div {class="w3-padding-small w3-rest w3-display-container", style="height:50px;",
       main_panel}}}
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
    local user = user_defined_ui (d)
    local t = xhtml.table {class = "w3-small"}
    local user_control
    if user.control then 
      user_control = get_user_html_as_dom (user.control (d.attributes.id))
    end
    local states = d:get_shortcodes ()
    for n,v in sorted (states) do t.row {n, nice(v)} end
    return title .. " - status and control", 
        xhtml.div {class="w3-cell", device_panel(d), xhtml.div {t}},
        xhtml.div {class = "w3-cell w3-padding-large", user_control} 
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
      attr[#attr+1] = X.Form {
        class = "w3-form w3-padding-small w3-left",
        xhtml.label {xhtml.b{n}}, 
        X.Hidden {page = "attributes", attribute = n},
        xhtml.input {class="w3-input w3-round w3-border w3-hover-border-red",type="text", size=28, 
          name="value", value = nice(v, 99), autocomplete="off", onchange="this.form.submit()"} }
    end
    return title .. " - attributes", attr
  end)
end

function pages.variables (p, req)
  local q = req.POST
  local devNo = tonumber (p.device)
  local dev = luup.devices[devNo]
  -- create new variable
  local name = q.name
  local service = q.service
  local new_value = q.value
  local id = tonumber (q.id)
  if dev and name and service and new_value then
    if name ~= '' and service ~= '' then
      luup.variable_set (service, name, new_value, devNo)
    end
  end
  -- change value of existing variable
  if dev and id and new_value then
    local var = dev.variables[id+1]   -- recall that the id starts at zero!
    if var then
      luup.variable_set (var.srv, var.name, new_value, devNo)
    end
  end
  -----
  return device_page (p, function (d, title)
    local t = xhtml.table {class = "w3-small w3-hoverable"}
    t.header {"id", "service", "history", "variable", "value", "delete"}
    -- filter by serviceId
    local All_Services = "All Services"
    local service = p.svc or All_Services
    local any_service = service == All_Services
    local info, sids = {}, {}
    local historian = hist.folder ()
    for v in sorted_by_id_or_name (p, d.variables) do
      sids[v.shortSid] = true         -- save each unique service name
      if any_service or v.shortSid == service then
        local n = v.id + 1
        -- Historian tool icons
        local history, graph, edit = ' ', ' '
        local archives, filename, filepath
        if historian then -- check existence of matching archive file
          local f = hist.metrics.var2finder(v)                      -- get finder name...
          local r = hist.reader (f)                                 -- create a reader for that name...
          archives = r.get_intervals()                              -- ...and use it to see if there are any archives
          filepath, filename = hist.metrics.finder2filepath (f)     -- ...and matching file path
        end
        if (v.history and #v.history > 2) or archives then 
--          history = xhtml.a {href=selfref ("page=cache_history&variable=", n), title="cache", 
--                  xhtml.img {width="18px;", height="18px;", alt="cache", src="/icons/calendar-alt-regular.svg"}} 
        history = xhtml.img {title="cache", 
            style="display:inline-block;", alt="cache", src="/icons/calendar-alt-regular.svg",
            class="w3-hover-opacity", height=18, width=18, 
            onclick=X.popMenu (table.concat {"view_cache&dev=",d.devNo,"&var=",n})}       
          
          graph = xhtml.a {href=selfref ("page=graphics&variable=", n), title="graph", 
                  xhtml.img {width="18px;", height="18px;", alt="graph", src="/icons/chart-bar-solid.svg"}}
          
          edit = archives and whisper_edit (filename, historian) or ' '
        end
    -- form to allow variable value updates
        local value_form = editable_text ({page="variables", id=v.id}, v.value, 999)    -- maxlength
--        local trash_can = d.device_type == "openLuup" and '' or delete_link ("var", v.id, "variable")
        local trash_can = delete_link ("var", v.id, "variable")
        local actions = xhtml.span {history, graph, edit}
        info[#info+1] = {v.id, v.srv, actions, v.name, value_form, trash_can}
      end
    end
    for _, row in ipairs (info) do 
      local serviceId = row[2]
      row[2] = {title = serviceId, row[2]: match "%w+$"}      -- add mouse-over pop-up serviceId
      row[4] = {title = serviceId, row[4]}                    -- ditto
      t.row (row) 
    end
    -- finish building the services menu
    local options = {}
    for s in pairs (sids) do options[#options+1] = s end
    table.sort (options)
    table.insert (options, 1, All_Services)
    local function service_menu () return filter_menu (options, service, "svc=") end
    -----
    local create = xhtml.button {"+ Create"; 
      class="w3-button w3-round w3-green", title="create new variable", onclick=X.popMenu "create_variable"}
    local sortmenu = sidebar (p, service_menu, device_sort)
    local rdiv = xhtml.div {sortmenu, xhtml.div {class="w3-rest w3-panel", create, t} }
    return title .. " - variables", rdiv
  end)
end

function pages.actions (p)
  return device_page (p, function (d, title)
    local devNo = d.attributes.id
    local t = xhtml.div {class = "w3-container "}
    for s,srv in sorted (d.services) do
      local service_actions = (service_data[s] or empty) .actions
      local action_index = {}         -- service actions indexed by name
      for _, act in ipairs (service_actions or empty) do
        action_index[act.name] = act.argumentList or {}
      end
      for a in sorted (srv.actions) do
        local args = xhtml.div {class="w3-container w3-cell"}
        local form = X.Form {
          X.Hidden {action = "call_action", dev = devNo, srv = s},
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
                xhtml.input {class="w3-input w3-border w3-hover-border-red", 
                  type="text", autocomplete="off", size= 40, name = v.name} }  -- 2020.03.17 no autocomplete
            end
          end
        end
      end
    end
    
--    local function service_menu () return filter_menu ({"All Services","Defined Services"},'', "svc=") end
--    local sortmenu = sidebar (p, service_menu, device_sort)
--    local rdiv = xhtml.div {sortmenu, xhtml.div {class="w3-rest w3-panel", t} }
--    return title .. " - implemented actions", rdiv

    return title .. " - implemented actions", t
  end)
end

function pages.events (p)
  return device_page (p, function (d, title)
    local e = {}
    local columns = {"id", "event / variable : (serviceId)"}
    local json_file = d.attributes.device_json
    local static_data = loader.static_data[json_file] or empty
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

-- make an HTML table with any non-standard globals defined in the given environment
local function non_standard_globals (env)
  local x = {}
  for n,v in sorted (env) do
    if not _G[n] and type(v) ~= "function" then
      x[#x+1] = {n, xhtml.pre {pretty(v)}}
    end
  end
  local t = create_table_from_data ({"name", "value"}, x)
  t.class = (t.class or '') .. " w3-hoverable"
  return t  
end

function pages.globals (p)
  return device_page (p, function (d, title)
    local t = non_standard_globals (d.environment)
    return title .. " - plugin globals (excluding functions)", xhtml.div {class="w3-row", t}
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
    local bookmarked
    if x.attributes then    -- only devices have attributes
      bookmarked = x.attributes.bookmark == '1'   -- device
    else
      bookmarked = x.definition.favorite          -- scene
    end
    return room_match or (bookmarks and bookmarked)
  end
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

local function widget_link (action, title, icon, wh)
  wh = wh or 18
  return xhtml.a {class="w3-margin-right w3-hover-opacity",
    href= selfref(action), title=title, xhtml.img {width=wh, height=wh, src=icon} }
end

-- generic scene page
local function scene_page (p, fct)
  local i = tonumber(p.scene)
  local s = luup.scenes[i]
  local title = scene_name (i) 
  fct = s and fct or function (_, t) return t .. " - no such scene" end
  return page_wrapper (fct (s, title))   -- call back with actual scene    
end

local function scene_panel (self)
  local utab = self.definition
  
  --TODO: move scene next run code to scenes module
  local id = utab.id
  local earliest_time
  for _,timer in ipairs (utab.timers or empty) do
    local next_run = timer.next_run 
    if next_run and timer.enabled == 1 then
      earliest_time = math.min (earliest_time or next_run,  next_run)
    end
  end
  local next_run = earliest_time and table.concat {unicode.clock_three, ' ', nice (earliest_time) or ''}
  local last_run = utab.last_run
  last_run = last_run and table.concat {unicode.check_mark, ' ', nice (last_run)} or ''
  
  local div = xhtml.div
  local d, woo = 28, 14
  local run = self.paused 
          and 
              xhtml.img {width=d, height=d, 
                title="scene is paused", src="icons/pause-solid-grey.svg"} 
          or
              xhtml.a {href= selfref("action=run_scene&scn=", id), class = "w3-hover-opacity",
                xhtml.img {width=d, height=d, title="run scene", src="icons/play-solid.svg"} }
  
  local w1 = widget_link ("page=header&scene="  .. id, "view/edit scene", "icons/edit.svg")
  local w2 = widget_link ("action=create_scene&clone=" .. id, "clone scene", "icons/clone.svg")
  local w3 = widget_link ("page=history&scene=" .. id, "scene history",   "icons/calendar-alt-regular.svg")
  
  local flag = utab.favorite and unicode.black_star or unicode.white_star
  local bookmark = xhtml.a {class="nodec  w3-hover-opacity", href=selfref("action=bookmark&scn=", id), flag}
  local br = xhtml.br {}
  local on_off = xhtml.a {href= selfref("action=toggle_pause&scn=", id), title="enable/disable", class="w3-hover-opacity",
      xhtml.img {width=woo, height=woo, src="icons/power-off-solid.svg"} }
  local highlight = self.paused and '' or "w3-hover-border-red"
  
  return generic_panel {
    height = 70,
    top_line = {
      left = xhtml.span {bookmark, ' ', truncate (scene_name(id))}, right = on_off},
    icon = div {class="w3-padding-small w3-display-left " .. highlight, 
        style = "border:2px solid grey; border-radius: 4px;", run },
    body = {topright = xhtml.div {last_run, br, next_run } },
    widgets = { w1, w2, w3 },
  }
end

function pages.header (p)
  return scene_page (p, function (scene, title)
    local modes = scene: mode_toggle (p.mode)     -- flip the requested mode on/off, and get new modes
    return title .. " - scene header", 
      xhtml.div {class="w3-row", 
        xhtml.div{class="w3-col", style="width:550px;", 
          X.Container {scene_panel(scene)}, 
          X.Container {class = "w3-margin-left w3-padding w3-hover-border-red w3-round w3-border",
            xhtml.h6 "Active modes (all if none selected)",
            house_mode_group (modes) }}}
  end)
end


function pages.triggers (p)
  return scene_page (p, function (scene, title)
    local h = xhtml
    local T = h.div {class = "w3-container w3-cell"}
    local id = scene.definition.id
    for i, t in ipairs (scene.definition.triggers) do
      if t.device == 2 then       -- only display openLuup variable watch triggers
        local d, woo = 28, 14
        local dominos = t.enabled == 1 and 
            h.img {width = d, height=d, title="trigger is enabled", alt="trigger", src="icons/trigger-grey.svg"}
          or 
            h.img {width=d, height=d, title="trigger is paused", alt = 'pause', src="icons/pause-solid-grey.svg"} 
        
        local on_off = xhtml.a {href= selfref("toggle=", i), title="toggle pause", 
          class= "w3-hover-opacity", xhtml.img {width=woo, height=woo, src="icons/power-off-solid.svg"} }

--        local w1 = widget_link ("page=trigger&edit=".. i, "view/edit trigger", "icons/edit.svg")
        local w1 = xhtml.img {title="view/edit trigger", src="icons/edit.svg", style="display:block; float:left;",
            class="w3-margin-right w3-hover-opacity", height=18, width=18, 
            onclick=X.popMenu (table.concat {"edit_trigger&trg=",i,"&scn=",id})}       
        
        local w2 = delete_link ("trigger", i)
        local icon =  h.div {class="w3-padding-small", style = "border:2px solid grey; border-radius: 4px;", dominos }
        local desc
          -- openLuup watch
          local args = t.arguments or empty
          local function arg(n, lbl) return h.span {lbl or '', ((args[n] or empty).value or ''): match "[^:]+$", h.br()} end
          desc = h.span {arg(1, '#'), arg(2), arg(3)}
        T[i] = generic_panel ({
          title = t,
          height = 100,
          top_line = {left =  truncate (t.name), right = on_off},
          icon = icon,
          body = {middle = desc},
          widgets = {w1, w2},
        }, "trg-panel")       
      end
    end
    local watches = altui_device_watches (id)
    for i, t in ipairs (watches) do
      
      local d = 28
      local dominos = 
          h.img {width = d, height=d, title="trigger is enabled", alt="trigger", src="icons/trigger-grey.svg"}
      local icon =  h.div {class="w3-padding-small", style = "border:2px solid grey; border-radius: 4px;", dominos }
      local desc = h.div {'#', t.dev, h.br(), t.srv, h.br(), t.var}
      T[#T+1] = generic_panel ({
        title = '',
        height = 100,
        top_line = {left = truncate ("AltUI watch #" .. tostring(i))},
        icon = icon,
        body = {middle = desc},
      }, "trg-panel")      
    end
    local create = xhtml.button {"+ Create"; 
      class="w3-button w3-round w3-green", title="create new trigger", 
          onclick=X.popMenu "edit_trigger&new=true"}
    return title .. " - scene triggers", X.Panel {create}, T
  end)
end

--[[

1=interval
    the interval tag has an h or m for hours or minutes, 
    so 1h means every 1 hour, and 30m means every 30 minutes. 

2=day of week
    "days_of_week" indicates which days of the week (Sunday=0).
    
3=day of month
    "days_of_month" is a comma-separated list of the days of the month. 
    For types 2 & 3, "time" is the time. 
    If the time has a T or R at the end it means the time is relative to sunset or sunrise, 
    so -1:30:0R means 1hr 30 minutes before sunrise. 

4=absolute.
    the time has the day and time.

{
    "days_of_week":"1,2,3,4,5,6,7",
    "enabled":1,
    "id":1,
    "last_run":1623279540,
    "name":"Cinderella",
    "next_run":1623365940,
    "time":"23:59:00",
    "type":2
  }
  
--]]

function pages.timers (p)
  return scene_page (p, function (scene, title)
    local h = xhtml
    local T = h.div {class = "w3-container w3-cell"}
    local id = scene.definition.id
    for i, t in ipairs (scene.definition.timers) do
      local next_run = table.concat {unicode.clock_three, ' ', t.abstime or nice (t.next_run) or ''}
      local info =
        t.type == 1 and t.interval or
        t.type == 2 and t.days_of_week or
        t.type == 3 and t.days_of_month or
        t.type == 4 and '' or
        "---"
      local info2 = t.time or ''
      
      local d, woo = 28, 14
      local clock = t.enabled == 1 and 
          h.img {width = d, height=d, title="timer is running", alt="timer", src="icons/clock-grey.svg"}
        or 
          h.img {width=d, height=d, title="timer is paused", src="icons/pause-solid-grey.svg"} 
      
      local on_off = xhtml.a {href= selfref("toggle=", t.id), title="toggle pause", 
        class= "w3-hover-opacity", xhtml.img {width=woo, height=woo, src="icons/power-off-solid.svg"} }
--      local w1 = widget_link ("page=timer&edit=".. t.id, "view/edit timer", "icons/edit.svg")
        local w1 = xhtml.img {title="view/edit timer", src="icons/edit.svg", style="display:block; float:left;",
            class="w3-margin-right w3-hover-opacity", height=18, width=18, 
            onclick=X.popMenu (table.concat {"edit_timer&tim=",i,"&scn=",id})}       
      
      local w2 = delete_link ("timer", t.id)
      local ttype = ({"interval", "day of week", "day of month", "absolute"}) [t.type] or '?'
      local icon =  h.div {class="w3-padding-small", style = "border:2px solid grey; border-radius: 4px;", clock }
      local desc = h.div {ttype, h.br{}, info, h.br{}, info2}
      T[i] = generic_panel ({
        title = t,
        height = 100,
        top_line = {left =  truncate (t.name), right = on_off},
        icon = icon,
        body = {middle = desc, topright = next_run},
        widgets = {w1, w2},
      }, "tim-panel")       
    end
    local create = xhtml.button {"+ Create"; 
      class="w3-button w3-round w3-green", title="create new timer", onclick=X.popMenu "edit_timer&new=true"}
    return title .. " - scene triggers", X.Panel {create}, T
  end)
end

function pages.history (p)
  return scene_page (p, function (scene, title)
    local h = {}
    for i,v in ipairs (scene.openLuup.history) do h[i] = {nice(v.at), v.by} end
    table.sort (h, function (a,b) return a[1] > b[1] end)
    local t = create_table_from_data  ({"date/time", "initiated by"}, h)
    return title .. " - scene history", t
  end)
end
 
function pages.lua (p)
  return scene_page (p, function (scene, title)
    local Lua = scene.definition.lua
    return title .. " - scene Lua", 
      xhtml.div {lua_scene_editor (Lua, 500)}
  end)
end
 
function pages.group_actions (p)
  return scene_page (p, function (scene, title)
    local h = xhtml
    local id = scene.definition.id
    local groups = h.div {class = "w3-container"}
--    local new_group = P.create_new_delay_group ()
    local new_group = xhtml.button {"+ Delay"; 
      class="w3-button w3-round w3-green", title="create new delay group", onclick=X.popMenu "create_new_delay_group"}
    for g, group in ipairs (scene.definition.groups) do
      local delay = tonumber (group.delay) or 0
--      local new_action = P.create_action_in_group (g)
      local new_action = xhtml.button {"+ Action"; class="w3-button w3-round w3-green", 
        title="create new action\nin this delay group", onclick=X.popMenu ("edit_action&new=true&group=" .. g)}

      local del_group = X.ButtonLink {"- Delay"; selfref="action=delete&group=" .. g, 
        onclick = "return confirm('Delete Delay Group (and all its actions): Are you sure?')",
        title="delete delay group\nand all actions in it", class="w3-red w3-cell w3-container"}
      local dpanels = h.div{class = "w3-panel"}
      local e = h.div {
        class = "w3-panel w3-padding w3-border-top",             
        h.div {
          xhtml.div {"Delay: ",class="w3-cell w3-cell-middle w3-container", dhms(delay)}, 
          del_group, 
          xhtml.div {new_action, class="w3-container w3-cell"}, 
          dpanels}}
      for i, a in ipairs (group.actions) do
        local desc = h.div {h.strong{a.action}}
        for _, arg in pairs(a.arguments) do
          desc[#desc+1] = h.br()
          desc[#desc+1] = h.span {arg.name, '=', arg.value}
        end
--        local w1 = widget_link ("page=action&group=" .. g .. "&edit=".. i, "view/edit action", "icons/edit.svg")
        local w1 = xhtml.img {title="view/edit action", src="icons/edit.svg", style="display:block; float:left;",
            class="w3-margin-right w3-hover-opacity", height=18, width=18, 
            onclick=X.popMenu (table.concat {"edit_action&scn=",id,"&group=",g,"&act=",i})}       
        local w2 = delete_link ("group=" .. g .. "&act", i, "action")
        local dno = tonumber (a.device)
        dpanels[i] = generic_panel ({
          title = a.action,
          height = 100,
          top_line = {left = devname (dno)},
          icon = get_device_icon (luup.devices[dno]),
          body = {middle = desc},
          widgets = {w1, w2},
        }, "act-panel")       
      end
      groups[g] = e
    end
    return title .. " - actions (in delay groups)", 
    new_group,
    groups
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
    X.Title (title or codename),  code_editor (userdata.attributes[codename], 500, "lua", false, codename) }  
  local output = xhtml.div {class="w3-half", style="padding-left:16px;", 
    X.Title "Console Output:", 
    xhtml.iframe {name="output", height="500px", width="100%", 
      style="border:1px grey; background-color:white; overflow:scroll"} }
  return xhtml.div {class="w3-row", form, output}
end

pages["lua_test"]   = function () return lua_exec ("LuaTestCode",  "Lua Test Code")    end
pages["lua_test2"]  = function () return lua_exec ("LuaTestCode2", "Lua Test Code #2") end
pages["lua_test3"]  = function () return lua_exec ("LuaTestCode3", "Lua Test Code #3") end

function pages.lua_globals ()
  local t = non_standard_globals (loader.shared_environment)
  return page_wrapper (
    "Lua Globals in Startup / Shutdown / Test / Scenes... (excluding functions)", 
    xhtml.div {class="w3-panel", t})
end

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

-- graphics page may be called with a variable number (current device), or a target, 
-- and an optional 'from' time (if absent then the earliest time in the cache is used)
function pages.graphics (p)
  
  local function finderName_from_varnum (vnum)
    local dno, vno = tonumber (p.device), tonumber (vnum)
    if vno then
      local dev = luup.devices[dno]
      if dev then 
        local v = dev.variables[vno]
        if v then
          return hist.metrics.var2finder (v)
        end
      end
    end
  end  
  
  local function cache_earliest (var)
    if not var then return end
    local _,start = var:oldest()      -- get earliest entry in the cache (if any)
    return timers.util.epoch2ISOdate ((start or 0) + 1)    -- ensure we're AFTER the start... 
  end

  -- return a button group with links to plot different archives of a variable
  local function archive_links (var, earliest)  
    local back = xhtml.a {class = "w3-button w3-round w3-green", "<– Variables",
                          href = selfref ("page=variables&device=" .. var.dev)}
    local links = xhtml.div{class = "w3-margin-left", back}
    
    local historian = hist.folder()
    if not historian then return links end
    
    local finderName = hist.metrics.var2finder (var)
    local function button (name, time)
      local link = "page=graphics&target=%s&from=%s"
      local selected = (time == p.from) or (name == "cache" and not p.from)
      local color = selected and "w3-grey" or "w3-amber"
      return X.ButtonLink {name; class = color, selfref=(link: format (finderName, time))}
    end
    
    links[2] = button ("cache", earliest)

    local path = hist.metrics.finder2filepath (finderName)
    local i = whisper.info (path)
    if i then
      local retentions = tostring(i.retentions) -- text representation of archive retentions
      for arch in retentions: gmatch "[^,]+" do
        local _, duration = arch: match "([^:]+):(.+)"                  -- rate:duration
        links[#links+1] = button (arch, '-' .. duration)
      end
--      links[#links+1] =  xhtml.a {class = "w3-button w3-round w3-red w3-margin-left", target = "_blank", "Edit",
--            href = "/cgi/whisper-edit.lua?target=" .. path}
    end
    return links 
  end
  
  local finderName = p.target or finderName_from_varnum (p.variable) 
  if not finderName then return '' end
  
  local var = hist.metrics.finder2var (finderName)
  if not var then return end
  
  local earliest = cache_earliest (var)
  local from = p.from or earliest
  local buttons = archive_links (var, earliest)
  local render = "/render?target=%s&from=%s"
  local background = p.background or "GhostWhite"
  return xhtml.div {
    buttons, xhtml.iframe {
    height = "450px", width = "96%", 
    style= "margin-left: 2%; margin-top:30px; background-color:"..background,
    src= render: format (finderName, from)} }
end

function pages.rooms_table (p, req)
  local q = req.POST
  -- create new room
  if q.name then
    luup.rooms.create (q.name)
  -- rename existing room
  elseif q.rename and q.value then
    luup.rooms.rename (q.rename, q.value)
  end
  ---
  local function room_count (tbl)
    local room = {}
    for _,x in pairs (tbl) do
      local r = x.room_num
      room[r] = (room[r] or 0) + 1
    end
    return room
  end
  local droom = room_count (luup.devices)
  local sroom = room_count (luup.scenes)
  local function dlink (room, n) return n == 0 and '' or xlink ("page=devices&room=" .. room) end
  local function slink (room, n) return n == 0 and '' or xlink ("page=scenes&room="  .. room) end
  local function link_pair (link, count)
    return xhtml.div {class="w3-display-container", style = "width: 56px;",
      link, xhtml.span {class="w3-display-right", count} }
  end
  local create = xhtml.button {"+ Create"; 
    class="w3-button w3-round w3-green", title="create new room", onclick=X.popMenu "create_room"}
  local t = xhtml.table {class = "w3-small w3-hoverable"}
  t.header {"id", "name", "#devices", "#scenes", "delete"}
  local D,S = droom[0] or 0, sroom[0] or 0
  local room = "No Room"
  t.row {0, room, link_pair (dlink (room, D), D), link_pair (slink (room, S), S)}
  -- build a table for use by the id/name sort menu routine
  local rooms = {}
  for n, v in pairs (luup.rooms) do rooms[n] = {id = n, description = v} end
  for v in sorted_by_id_or_name (p, rooms) do
    local n = v.id
    local d,s = droom[n] or 0, sroom[n] or 0
    D,S = D + d, S + s
    local room = v.description
    local editable_name = editable_text ({rename=n}, room)
    local d_name_link = link_pair (dlink (room, d), d)
    local s_name_link = link_pair (slink (room, s), s)
    t.row {n, editable_name, d_name_link, s_name_link, delete_link ("rm", n, "room")}
  end
  t.header {'',rhs "Total", rhs(D), rhs(S)}
  local sortmenu = sidebar (p, device_sort)
  local rdiv = xhtml.div {sortmenu, xhtml.div {class="w3-rest w3-panel", create, t} }
  return page_wrapper ("Rooms Table", rdiv)
end

function pages.devices_table (p, req)
  local q = req.POST
  if q.rename and q.value then
    local dev = luup.devices[tonumber(q.rename)]
    if dev then dev: rename (q.value, nil) end
  elseif q.reroom then
    local dev = luup.devices[tonumber(q.reroom)]
    if dev then dev: rename (nil, q.value) end
  end
  local create = xhtml.button {"+ Create"; 
    class="w3-button w3-round w3-green", title="create new device", onclick=X.popMenu "create_device"}
  local t = xhtml.table {class = "w3-small w3-hoverable"}
  t.header {"id", "name", "altid", '', "room", "delete"}  
  local wanted = room_wanted(p)        -- get function to filter by room  
  for d in sorted_by_id_or_name (p, luup.devices) do
    local devNo = d.attributes.id
    if wanted(d) then 
      local altid = xhtml.div {title=d.id, truncate (d.id, -22)}    -- drop off the middle of the string
      local trash_can = devNo == 2 and '' or delete_link ("dev", devNo, "device")
      local bookmark = xhtml.span{class="w3-display-right", d.attributes.bookmark == '1' and unicode.black_star or ''}
      local link = xlink ("page=control&device="..devNo)
      local current_room = luup.rooms[d.room_num] or "No Room"
      local room_selection = xselect ({reroom=devNo}, luup.rooms, current_room, {"No Room"})
      t.row {devNo, editable_text({rename=devNo}, d.description), altid,
        xhtml.div {class="w3-display-container", style="width:40px;", link, bookmark}, 
          room_selection, trash_can} 
    end
  end
  local room_nav = sidebar (p, rooms_selector, device_sort)
  local ddiv = xhtml.div {room_nav, xhtml.div {class="w3-rest w3-panel", create, t} }
  return page_wrapper ("Devices Table", ddiv)
end

function pages.scenes_table (p, req)
  local q = req.POST
  -- rename scene
  if q.rename and q.value then
    local s = luup.scenes[tonumber(q.rename)]
    if s then s: rename (q.value) end
  elseif q.reroom and q.value then
    local s = luup.scenes[tonumber(q.reroom)]
    local num = 0                       -- default is "No Room"
    for i,v in pairs (luup.rooms) do    -- convert from room name to room number
      if v == q.value then num = i break end
    end
    s: rename (nil, num)
  end
  local create = xhtml.button {"+ Create"; 
    class="w3-button w3-round w3-green", title="create new scene", onclick=X.popMenu "create_scene"}
  local scn = {}
  local wanted = room_wanted(p)        -- get function to filter by room  
  local ymdhms = "%y-%m-%d %X"
  for x in sorted_by_id_or_name (p, luup.scenes) do
    local n = x.definition.id
    if wanted(x) and paused_or_not(p, x) then 
      local favorite = xhtml.span{class="w3-display-middle", x.definition.favorite and unicode.black_star or ''}
      local paused = x.paused and 
        xhtml.img {height=14, width=14, class="w3-display-right", src="icons/pause-solid.svg"} or ''
      local link = xlink ("page=header&scene="..n)
      local current_room = luup.rooms[x.room_num] or "No Room"
      local timestamp = os.date (ymdhms, x.definition.Timestamp or 0)
      local room_selection = xselect ({reroom=n}, luup.rooms, current_room, {"No Room"})
      scn[#scn+1] = {n,  editable_text({rename=n}, x.description), 
        xhtml.div {class="w3-display-container", style="width:60px;", link, favorite, paused}, 
        room_selection, timestamp, delete_link ("scn", n, "scene")}
    end
  end
  local t = create_table_from_data ({"id", "name", '', "room", "created", "delete"}, scn)  
  t.class = "w3-small w3-hoverable"
  local room_nav = sidebar (p, rooms_selector, scene_sort, scene_filter)
  local sdiv = xhtml.div {room_nav, xhtml.div {class="w3-rest w3-panel", create, t} }
  return page_wrapper ("Scenes Table", sdiv)
end

function pages.triggers_table (p)
  
  local options = {"All Triggers", "openLuup", "AltUI", "Luup UPnP"}
  local request_type = p.type or options[1]
  local selection = sidebar (p, function () return filter_menu (options, request_type, "type=") end)
  
  local all = request_type == options[1]
  local triggers = xhtml.div {class="w3-rest w3-panel"}
  local Tluup = luup_triggers ()    -- {{scn = s, name = t.name, dev = devNo, text = text}}
    
  local Otrg = {}
  if all or request_type == options[2] then
    for _, x in ipairs (Tluup) do
      if x.dev == 2 then              -- this is an openLuup Variable Watch trigger
        local i = #Otrg + 1
        local link = xlink ("page=triggers&scene="..x.scn)
        local watch = table.concat (x.args, '.')
        Otrg[i]= {i, x.name, link, rhs(x.scn), watch}
      end
    end
    local o = create_table_from_data ({'#', "name", {colspan=2, "scene"}, "watching: device.service.variable"}, Otrg)  
    triggers[#triggers+1] = xhtml.div {xhtml.h5 "openLuup Variable Watch Triggers", o}
  end
  
  local Atrg = {}
  if all or request_type == options[3] then
    local Taltui = altui_device_watches ()    -- {srv = srv, var = v, dev = dev, scn = scn, lua = l}
    for i, x in ipairs (Taltui) do
      local link = xlink ("page=triggers&scene="..x.scn)
      Atrg[i]= {i, "AltUI watch", link, rhs(x.scn), table.concat ({x.dev, x.srv, x.var}, '.'), x.lua}
    end
    local t = create_table_from_data (
      {'#', "name", {colspan=2, "scene"}, "watching: device.service.variable", "Lua conditional"}, Atrg)  
    triggers[#triggers+1] = xhtml.div {xhtml.h5 "AltUI Variable Watch Triggers", t}   
  end
  
  local Ltrg = {}
  if all or request_type == options[4] then
    for _, x in ipairs (Tluup) do
      if x.dev ~= 2 then            -- skip the openLuup triggers
        local i = #Ltrg + 1
        local link = xlink ("page=triggers&scene="..x.scn)
        Ltrg[i]= {i, x.name, link, rhs(x.scn), rhs(x.dev), x.text}
      end
    end
    local l = create_table_from_data ({'#', "name", {colspan=2, "scene"}, "device", "description"}, Ltrg)  
    triggers[#triggers+1] = xhtml.div {xhtml.h5 "Luup UPnP Triggers (ignored by openLuup)", l}
  end
      
--  local create = X.ButtonLink {"+ Create"; selfref="page=trigger", title="create new trigger"}
--  local tdiv = xhtml.div {selection, xhtml.div {class="w3-rest w3-panel", create, triggers} }
  local tdiv = xhtml.div {selection, xhtml.div {class="w3-rest w3-panel", triggers} }
  return page_wrapper ("Triggers Table", tdiv)
end

function pages.ip_table ()
  local ips = {}
  local API = require "openLuup.api"
  for i,D in API "devices" do
    local A = D.attributes
    local ip = A.ip
    if ip and #ip > 0 then
      local link = xlink ("page=control&device="..i)
      ips[#ips+1] = {i, ip, link, A.name}
    end
  end
  table.sort (ips, function(a,b) return a[2]<b[2] end)
  local t = create_table_from_data ({'id', "IP", {colspan=2, "name"}}, ips)  
  return page_wrapper ("IP Table", t)
end

function pages.plugins_table (_, req)
  local q = req.POST
  -- if info posted then create or update plugin
  local IP2 = userdata.attributes.InstalledPlugins2
  local P = find_plugin (q.id)
  if not P then 
    P = {Devices = {}, Repository = {}, id = q.id}
    if q.id and q.id ~= '' then IP2[#IP2+1] = P end
  end
  if q.id then
    P.Title = q.title
    P.Icon = q.icon
    P.Devices = {{DeviceFileName = q.d_file, ImplFile = q.i_file}}
    local folders = {}
    for folder in (q.folders or ''): gmatch "[^,%s]+" do    -- comma or space separated list
      folders[#folders+1] = folder
    end
    P.Repository = {type = "GitHub", source = q.repository, pattern=q.pattern, folders = folders}
  end
  ---
  local t = xhtml.table {class = "w3-bordered"}
  t.header {'', "Name","Version", "Files", '', "Update", "Uninstall"}
  for _, p in ipairs (IP2) do
    local version = table.concat ({p.VersionMajor or '?', p.VersionMinor}, '.')
    local files = {}
    for _, f in ipairs (p.Files or empty) do files[#files+1] = f.SourceName end
    table.sort (files)
    local choice = {style="width:12em;", name="file", onchange="this.form.submit()", 
      xhtml.option {value='', "Files", disabled=1, selected=1}}
    for _, f in ipairs (files) do choice[#choice+1] = xhtml.option {value=f, f} end
    files = X.Form {
      X.Hidden {page = "viewer"},
      xhtml.select (choice)}
    
    local ignore = {AltAppStore = '', VeraBridge = ''}
    
    local GitHub_Mark = "https://raw.githubusercontent.com/akbooer/openLuup/development/icons/GitHub-Mark-64px.png"
    local github = xhtml.a {href="https://github.com/"  .. (p.Repository.source or ''), target="_blank", 
      xhtml.img {title="go to GitHub repository", src=GitHub_Mark, alt="GitHub", height=32, width=32} }
    
    local update = ignore[p.id] or X.Form {
      X.Hidden {action = "update_plugin", plugin = p.id},
      xhtml.div {class="w3-display-container",
        -- TODO: should the following name be "update" or "version" ???
        xhtml.input {class="w3-hover-border-red", type = "text", autocomplete="off", name="version", value=''},
        xhtml.input {class="w3-display-right", type="image", src="/icons/retweet.svg", 
          title="update", alt='', height=28, width=28} } }
    
    ignore.openLuup = ''
    local src = p.Icon or ''
    src  = src: gsub ("^/?plugins/", "http://apps.mios.com/plugins/")  -- http://apps.mios.com/plugin.php?id=...
    local icon = xhtml.img {src=src, alt="no icon", height=35, width=35}
    icon = ignore[p.id] and icon or 
      xhtml.div {icon; title="edit", onclick=X.popMenu ("plugin&plugin="..p.id)}
    local trash_can = ignore[p.id] or delete_link ("plugin", p.id)
    t.row {icon, p.Title, version, files, github, update, trash_can} 
  end
  local create = X.ButtonLink {"+ Create"; selfref="page=plugin", title="create new plugin"}
  return page_wrapper ("Plugins", create, t)
end


--
-- APP Store
--
local APPS = {}
local APP_loadtime = 0
local database_creation_time = 0

local function load_appstore ()
  local timenow = os.time()
  if #APPS > 0 and timenow < APP_loadtime + 24*60*60 then return end    -- update if older than 24 hours
  _log "loading app database..."
  local _,j = luup.inet.wget "https://raw.githubusercontent.com/akbooer/AltAppStore/data/J_AltAppStore.json"

  local apps, errmsg = json.decode (j)
  if errmsg then _log (errmsg) end
  
  if apps then
    _log "...done"
    APPS = {}
    APP_loadtime = timenow
    
    for _, a in ipairs (apps) do
      local reps = a.Repositories 
      if type(reps) == "table" then
        for _, rep in ipairs (reps) do
          if rep.type == "GitHub" then
            a.repository = rep          -- this is the GitHub repository
            a.Repositories = nil        -- remove the others
            APPS[#APPS+1] = a
            APPS[tostring(a.id)] = a    -- add index by ID
            break
          end
        end
      else
  --      print ("No Git", a.Title, tostring(reps), a.Title)
      end
    end
  end

  table.sort (APPS, function (a,b) return a.Title < b.Title end)
  database_creation_time = (APPS[1] or {}) .loadtime or 0
end

function pages.app_json (p)
  local readonly = true
  local info = json.encode (APPS[p.plugin] or empty)
  return page_wrapper ("Alt App Store - JSON definition",
      xhtml.div {code_editor (info, 500, "json", readonly)})
end

-- info parameter is non-nil in the case of an install
local function app_panel (app, info)
  local icon = (app.Icon or ''): gsub ("^/?plugins/", "http://apps.mios.com/plugins/")
--  print (app.Title, icon)
  local title = app.Description or ''
  local repository = app.repository
  local source = repository.source or ''
  local onclick = "alert ('%s')"
  icon = xhtml.img {title=title, onclick = onclick: format(title),
    src=icon, alt="no icon", height=64, width=64}
  local GitHub_Mark = "https://raw.githubusercontent.com/akbooer/openLuup/development/icons/GitHub-Mark-64px.png"
  local github = X.ButtonLink {href="https://github.com/"  .. source, target="_blank", class='',
    xhtml.img {title="go to GitHub repository", src=GitHub_Mark, alt="GitHub", height=32, width=32} }
  local jlink = X.ButtonLink {"JSON"; selfref="page=app_json&plugin=" .. app.id, title="view App Store JSON", class=''}

  -- show releases
  local choice = {style="width:12em;", name="release"} 
  local versions = repository.versions
  
  local vs = {}
  for _,x in pairs (versions) do vs[#vs+1] = tostring(x.release) end
  table.sort (vs, function(a,b) return a > b end)
  for _, release in ipairs (vs) do
    choice[#choice+1] = xhtml.option {value=release, release} 
  end

  local panel = generic_panel ({
    height = 90,
    top_line = {
      left = xhtml.span {truncate (app.Title)}, right = xhtml.select (choice)},
    icon = xhtml.div {class="w3-padding-small w3-display-left ", icon },
    body = {
      topright = info,
      bottomright = xhtml.div {jlink, github, 
        xhtml.input {class="w3-button w3-round w3-border w3-green ", type="submit", value="Install" } } },
      }, "app-panel")
  
  return X.Form {
    X.Hidden {app = app.id},
    panel}
end

function pages.app_store (p, req)
  load_appstore()
  
  local function install_app (app, release)
    local meta = {plugin = {} }
    for n,v in pairs (app) do
      if type (v) == "table" then -- for some reason the AltAppStore wrapped these to lowercase (@Vosmont??)
        meta[n: lower()] = v
      else
        meta.plugin[n] = v
      end
    end
    
    -- some more fix-ups (this really is a mess due to committee decisions!)
    meta.versions = nil
    meta.versionid = release
    meta.version = {major = "GitHub", minor = release}
    
    -- shallow copy the repository to preserve original for UI version selection
    local repository = {}
    for n,v in pairs (meta.repository) do repository[n] = v end
    repository.versions = {[release] = {release = release}}  -- others are not relevant to the install
    meta.repository = repository
    
    local metadata = json.encode (meta) 
--    print (metadata)
    
    local sid = SID.appstore
    local act = "update_plugin"
    local arg = {metadata = metadata}
    local dev
    -- find the AltAppStore plugin
    for devNo, d in pairs (luup.devices) do
      if (d.device_type == "urn:schemas-upnp-org:device:AltAppStore:1") then
        dev = devNo
        break
      end
    end
    
    -- returns: error (number), error_msg (string), job (number), arguments (table)
    local _, errmsg, _, a = luup.call_action (sid, act, arg, dev)       -- actual install
--    print ((json.encode {e,errmsg,j,a}))
    local result = json.encode (a or {ERROR = errmsg})
    _log (result)
    if errmsg then _log (errmsg) end
    
    -- NOTE: that the above action executes asynchronously and the function call
    --       returns immediately, so you CAN'T do a luup.reload() here !!
    --       (it's done at the end of the <job> part of the called action)
    return result
  end
  
  local q = req.POST
  local install = q.app   -- request to install this app
  local release = q.release
  
  -- construct letter groups index
  local a_z = {"abc", "def", "ghi", "jkl","mno", "pqrs", "tuv", "wxyz"}
  local All_Apps = "All Apps"
  local a_z_idx = {}
  local n_in_group = {}
  for _, abc in ipairs (a_z) do
    for letter in abc: gmatch "." do a_z_idx[letter] = abc end
    n_in_group[abc] = 0
  end

  local wanted = p.abc_sort
  local subset = xhtml.div{class = "w3=panel"}
  for _, app in ipairs(APPS) do
    local info
    if app.id == install then info = "INSTALLING..." .. install_app (app, release) end
    local letter = (app.Title or '') :sub(1,1) :lower()
    local grp = a_z_idx[letter]
    n_in_group[grp] = n_in_group[grp] + 1
    if wanted == All_Apps or wanted == grp then
      subset[#subset+1] = app_panel(app, info)
    end
  end
  
  local abc_menu = {xhtml.div{All_Apps, xhtml.span {class="w3-badge w3-right w3-red", #APPS} } }
  for _, abc in ipairs (a_z) do
    abc_menu[#abc_menu+1] = 
      xhtml.div{abc, xhtml.span {class="w3-badge w3-right w3-dark-grey", n_in_group[abc]} } 
  end
  
  local function service_menu () return filter_menu (abc_menu, wanted, "abc_sort=") end
  local sortmenu = sidebar (p, service_menu)
  local rdiv = xhtml.div {sortmenu, xhtml.div {class="w3-rest w3-panel", subset } }
  
  return page_wrapper ("Alt App Store (as of " .. todate(database_creation_time) .. ')', rdiv)
end

function pages.luup_files (p)
  local fnames = setmetatable ({}, {__index = function (x,a) local t={} rawset(x,a,t) return t end})
  local function add(a, f) fnames[a][#fnames[a]+1] = f end
  for f in loader.dir() do
    local letter, extension = f: match "^(%a)_.+%.(%a+)$"
    if letter then
      add ('a', f)
      add (letter: match "[DIJLS]" and letter or 'o', f)                      -- 'o' is "other"
      if letter == 'D' then add (extension == "xml" and 'x' or 'j', f) end    -- assume .json if not .xml
    end
  end
  
  local ftype = p.filetype or "All"
  local filetypes = {"All", "D_.*", "D_.xml", "D_.json",
    "I_.xml", "J_.js", "L_.lua", "S_.xml", "other"}
  local index = {'a', 'D', 'x', 'j','I', 'J', 'L', 'S', 'o'}
  
  local class = "w3-badge w3-right w3-red"
  local f_menu = {} 
  local selected = 'a'
  for i, f in ipairs (filetypes) do
    local idx = index[i]
    if f == ftype then selected = idx end
    f_menu[#f_menu+1] = 
      xhtml.div {f, xhtml.span {class=class, #fnames[idx]} } 
      class = "w3-badge w3-right w3-dark-grey"
  end
  local function file_menu () return filter_menu (f_menu, ftype, "filetype=") end
  local typemenu = sidebar (p, file_menu)
  
  fnames = fnames[selected]     -- pick the group we want
  for i, f in ipairs(fnames) do
    fnames[i] = xhtml.a {href=selfref ("page=viewer&file="..f), f}   -- single element
  end
  local n = math.floor((#fnames+1) / 2)
  for i = 1,n do
    fnames[i] = {fnames[i], fnames[i+n]}     -- two column rows
  end
  fnames[n+1] = nil
  local t = create_table_from_data ({{colspan=2, "filename (click to view)"}}, fnames)
  local rdiv = xhtml.div {typemenu, xhtml.div {class="w3-rest w3-panel", t } }
  return page_wrapper ("Luup files", rdiv)  
end

-- command line
function pages.command_line (_, req)
  local output
  local command = req.POST.command
  if command then
    local f = io.popen (command)
    if f then output = f: read "*a"
      f: close()
    end
  end
  local h = xhtml
  local window = h.div {
    X.Title {"Output: ", h.span {style="font-family:Monaco; font-size:11pt;", command} },
    h.pre {style="height: 400px; border:1px grey; background-color:white; overflow:scroll", output} }
  local form = h.form {action= selfref (), method="post",
    h.input {class="w3-button w3-round w3-green w3-margin", value="Submit", type = "submit"},
    h.input {type = "text", style="width: 80%;", name ="command", onfocus="this.select();",
      autocomplete="off", placeholder="command line", value=command, autofocus=1}}
  return X.Container {window, form}
end

-----

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
  local t = xhtml.table {class = "w3-table-all w3-cell w3-card"}
  for a,b in sorted (ABOUTopenLuup) do
    t.row { xhtml.b {a},  xhtml.pre (embedded_links(b))}
  end
  return t
end  

function pages.reload ()
  _log "Reload requested by openLuup console"
  local _,_, jno = scheduler.run_job {job = luup.reload}
  _log ("Shutdown job = " .. (jno or '?'))
  return page_wrapper "Please wait a moment while system reloads"
end

pages.reload_luup_engine = pages.reload    -- alias for top-level menu


-------------------------------------------


local a, div = xhtml.a, xhtml.div

function pages.home (p)
  -- set house mode immediately, if provided
  if p.mode then
    luup.call_action (SID.hag, "SetHouseMode", {Mode = p.mode, Now=1}, 0)
  end
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
    for _, name in ipairs (menu[2] or empty) do
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

local function page_nav (current, previous, message)
--  local onclick="document.getElementById('messages').style.display='block'" 
  local bcol = message and message.button or ''
  local messages = div (xhtml.div {class="w3-button w3-round w3-border " .. bcol, "Messages ▼ "})
  messages.onclick="ShowHide('messages')" 
--  local msg = xhtml.div {class="w3-container w3-green w3-bar", 
--    xhtml.span {onclick="this.parentElement.style.display='none'",
--      class="w3-button", "x"},
--       nice (os.time()), ' ', "Click on the X to close this panel" }
  local tabs, groupname = page_group_buttons (current)
  return X.Container {class="w3-row w3-margin-top",
      page_tree (current, previous), 
      X.Container {class="w3-cell", messages},
      X.Panel {class = "w3-border w3-hide", id="messages", message, },
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
      for _, item in ipairs (menu[2] or empty) do
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

local VERSION = luup.devices[2].services.openLuup.variables.Version.value

----------------------------------------
-- run()
--

local initialised = false

local script_text = 
  [[
  
  function ShowHide(id) {
    var x = document.getElementById(id);
    if (x.className.indexOf("w3-show") == -1) 
      {x.className += " w3-show";}
    else 
      {x.className = x.className.replace(" w3-show", "");}
    };
    
  function LoadDoc(id, req, data) {
    const xhttp = new XMLHttpRequest();
    xhttp.onload = function() {document.getElementById(id).innerHTML = this.responseText;}
    xhttp.open("POST", req);
    xhttp.send(data);
    };
    
  function popup(menu) {
    let formData = new FormData(document.forms.popupMenu);
    LoadDoc("modal_content", menu, formData);
    document.getElementById("modal").style.display="block";
    };
    
  function AceEditorSubmit(code, window) {
    var element = document.getElementById(code);
    element.value = ace.edit(window).getSession().getValue();
    element.form.submit();}

  ]]

local donate = xhtml.a {
  title = "If you like openLuup, you could DONATE to Cancer Research UK right here",
  href="https://www.justgiving.com/DataYours/", target="_blank", " [donate] "}
local forum = xhtml.a {class = "w3-text-blue",
  title = "An independent place for smart home users to share experience", 
  href=ABOUTopenLuup.FORUM, target="_blank", " [smarthome.community] "}

local cookies = READONLY {page = "about", previous = "about",      -- cookie defaults
  device = "2", scene = "1", room = "All Rooms", 
  plugin = '',    -- 2020.07.19
  abc_sort="abc", dev_sort = "Sort by Name", scn_sort = "All Scenes"}

local head_element = READONLY {  -- the <HEAD> element
    xhtml.meta {charset="utf-8", name="viewport", content="width=device-width, initial-scale=1"},
    xhtml.link {rel="stylesheet", href="w3.css"},
    xhtml.link {rel="stylesheet", href="openLuup_console.css"}}


local function noop() end
  
-- get local copy of w3.css if we haven't got one already
-- so that we can work offline if required
local function check_for_w3()
  if loader.raw_read "w3.css" then 
    _log "./www/w3.css detected"
    return
  end
  _log "downLoading w3.css..."
  local css = io.open ("www/w3.css", "wb")
  local _, err = https.request{ 
    url = "https://www.w3schools.com/w3css/4/w3.css", 
    sink = ltn12.sink.file (css),
  }
  if err == 200 then 
    _log "...saved to ./www/w3.css"
  else
    _log("ERROR loading w3.css: " .. err) 
  end
end

local function get_config()
  options = luup.attr_get "openLuup.Console" or {}   -- get configuration parameters
  local msg = "Console.%s = %s"
  for a,b in pairs(options) do
    _log (msg:format(a,b))
  end
end

local function initialise(wsapi_env)
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output
  _log "console starting..."
  check_for_w3()  
  get_config()
  _log "...console startup complete"
  initialised = true
end


function run (wsapi_env)
  
  if not initialised then initialise(wsapi_env) end
  
  local res = wsapi.response.new ()
  local req = wsapi.request.new (wsapi_env)

  script_name = req.script_name      -- save to use in links
  local h = xml.createHTMLDocument "openLuup"    -- the actual return HTML document
  local body

  local p = req.params  
  local P = capitalise (p.page or '')
  if page_groups[P] then p.page = page_groups[P][1] end     -- replace group name with first page in group
  
  for cookie in pairs (cookies) do
    if p[cookie] then 
      res: set_cookie (cookie, {value = p[cookie], SameSite="Lax"})                   -- update cookie with URL parameter
    else
      p[cookie] = req.cookies[cookie] or cookies[cookie]     -- set any missing parameters from session cookies
    end
  end
  
  -- ACTIONS
  if p.action then
   (actions[p.action] or noop) (p, req)
  end
  
  -- PAGES
  if p.page ~= p.previous then res: set_cookie ("previous", {value = p.page, SameSite = "Lax"}) end
  
  local sheet, message = pages[p.page] (p, req)
  local navigation = page_nav (p.page, p.previous, message)
  local formatted_page = div {class = "w3-container", navigation, sheet}
  
  static_menu = static_menu or dynamic_menu()    -- build the menu tree just once

  local modal = X.modal (xhtml.div {id="modal_content", h.h1 "Hello"}, "modal")   -- general pop-up use

  local script =  
    
--    xhtml.script {src = "/openLuup_console_script.js", type="text/javascript", charset="utf-8"},    -- JS util code

    h.script {script_text}

--  local popup = h.div {"MODAL", onclick=X.popup (modal), class ="w3-button"}

  body = {
    script,
    modal,
    static_menu,
    h.div {
      formatted_page,
      h.div {class="w3-footer w3-small w3-margin-top w3-border-top w3-border-grey", 
        h.p {style="padding-left:4px;", os.date "%c", ', ', VERSION, donate, forum}} }
    }
  
  h.documentElement[1]:appendChild (head_element)
    
  h.body.class = "w3-light-grey"
  h.body:appendChild (body)
  local html = tostring(h)
  res: write (html)  
  return res: finish()
end


-----
