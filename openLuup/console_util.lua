local ABOUT = {
  NAME          = "utility.lua",
  VERSION       = "2023.02.21",
  DESCRIPTION   = "utilities for openLuup console",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-present AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-present AK Booer

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

local _ = ABOUT

-- General utilities, XHTML, Pop-ups

local lfs       = require "lfs"
local json      = require "openLuup.json"
local xml       = require "openLuup.xml"          -- for HTML constructors
local luup      = require "openLuup.luup"
local loader    = require "openLuup.loader"       -- for loader.dir()
local server    = require "openLuup.server"       -- request handler

local xhtml     = xml.createHTMLDocument ()       -- factory for all HTML tags

local service_data  = loader.service_data         -- for action parameters

local empty = setmetatable ({}, {__newindex = function() error ("read-only", 2) end})

-------------------
--
-- General utilities
--


local function todate (epoch) return os.date ("%Y-%m-%d %H:%M:%S", epoch) end

local function todate_ms (epoch) return ("%s.%03d"): format (todate (epoch),  math.floor(1000*(epoch % 1))) end

-- truncate to given length
-- if maxlength is negative, truncate the middle of the string
local function truncate (s, maxlength)
  s = s or "?????"
  maxlength = maxlength or 22
  if maxlength < 0 then
    maxlength = math.floor (maxlength / -2)
    local nc = string.rep('.', maxlength)
    local pattern = "^(%s)(..-)(%s)$"
    s = s: gsub(pattern: format(nc,nc), "%1...%3")
  else
    if #s > maxlength then s = s: sub(1, maxlength) .. "..." end
  end
  return s
end


-- formats a value nicely
local function nice (x, maxlength)
  local s = tostring (x)
  local number = tonumber(s)
  if number and number > 1234567890 and number < 2^31 then s = todate (number) end
  return truncate (s, maxlength or 50)
end

-- add thousands comma to numbers
local ThousandsSeparator = luup.attr_get "ThousandsSeparator" or ','
local function commas (n, ...)
  local a, b = tostring (n or 0): match "(%d-)(%d?%d?%d)$"
  return a ~= '' and commas (a, b, ...) or table.concat ({b, ...}, ThousandsSeparator)
end


-- dhms()  converts seconds to hours, minutes, seconds [, milliseconds] for display
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
  x = x or {}
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

local function dev_or_scene_name (d, tbl)
  d = tonumber(d) or 0
  local name = (tbl[d] or empty).description or 'system'
  name = name: match "^%s*(.+)" or "???"
  local number = table.concat {'[', d, '] '}
  return number .. name
end

local function devname (d) return dev_or_scene_name (d, luup.devices) end

local function scene_name (d) return dev_or_scene_name (d, luup.scenes) end

local function missing_index_metatable (name)
  return {__index = function(_, tag) 
    return function() 
      return table.concat {"No such ", name, ": '",  tag or "? [not specified]", "'"} 
      end
    end}
  end

local U = {
    todate = todate,
    todate_ms = todate_ms,
    truncate = truncate,
    nice = nice,
    commas = commas,
    dhms = dhms,
    sorted = sorted,
    mapFiles = mapFiles,
    get_matching_files_from = get_matching_files_from,
    devname = devname,
    scene_name = scene_name,
    missing_index_metatable = missing_index_metatable
  }

-------------------
--
-- XHTML utilities
--


local selfref     -- set on initialization

local X = {
    Title = xhtml.h4,
    Subtitle = xhtml.h5,
  }

-- HTML document with W3.CSS stylesheet
function X.createW3Document (title)
  local xhtml = xml.createHTMLDocument (title)
  xhtml.body:appendChild {
    xhtml.meta {charset="utf-8", name="viewport", content="width=device-width, initial-scale=1"}, 
    xhtml.link {rel="stylesheet", href="https://www.w3schools.com/w3css/4/w3.css"}}
  return xhtml
end

function X.Container (p)
  p.class = "w3-container " .. (p.class or '')
  return xhtml.div (p)
end

function X.Panel (p)
  p.class = "w3-panel " .. (p.class or '')
  return xhtml.div (p)
end

function X.ButtonLink (p)
  p.class = "w3-button w3-round " .. (p.class or "w3-green")
  if p.selfref then
    p.href = selfref (p.selfref)
    p.selfref = nil
  end
  return xhtml.a (p)
end

function X.Icon (p)
  local size = p.height or p.width or 42
  p.height = p.height or size
  p.width  = p.width  or size 
  return xhtml.img (p)
end

function X.Form (p)
  if p.selfref then
    p.action = selfref (p.selfref)
    p.selfref = nil
  end
  p.action = p.action or selfref ()
  p.method = p.method or "post"
  return xhtml.form (p)
end

-- NB: arguments are name-value pairs, NOT HTML attributes!
--     so handles multiple items {a=one, b=two, ...}
function X.Hidden (args)
  local hidden = xhtml.div {}
  for n, v in pairs (args) do   -- order of iteration doesn't matter since values are hidden from view
    hidden[#hidden+1] = xhtml.input {name = n, value = v, hidden = 1}
  end
  return hidden
end

-- make a drop-down selection for things
function X.select (hidden, options, selected, presets)
  local sorted = {}
  for _,v in pairs (options or empty) do sorted[#sorted+1]  = v end
  table.sort (sorted)
  local choices = xhtml.select {style="width:12em;", name="value", onchange="this.form.submit()"} 
  local function choice(x) 
    local select = x == selected and 1 or nil
    choices[#choices+1] = xhtml.option {selected = select, x} 
  end
  for _,v in ipairs (presets or empty) do choice(v) end
  for _,v in ipairs (sorted) do choice(v) end
  local form = X.Form {choices}
  for n,v in pairs (hidden or empty) do form[#form+1] = 
    X.Hidden {[n] = v}
  end
  return form
end


-- create an option list for certain file types
function X.options (label_text, name, pattern, value)
  local listname = name .. "_options"
  local label = xhtml.label {label_text}
  local input = xhtml.input {list=listname, name=name, value=value, class="w3-input"}
  local datalist = xhtml.datalist {id= listname}
  for file in loader.dir (pattern) do
    datalist[#datalist+1] = xhtml.option {value=file}
  end
  return xhtml.div {label, input, datalist}
end

-- make a link to go somewhere
function X.link (link) 
  return xhtml.span {style ="text-align:right", xhtml.a {href= selfref (link),  title="link",
    xhtml.img {height=14, width=14, class="w3-hover-opacity", alt="goto", src="icons/link-solid.svg"}}}
end

function X.input (label, name, value, title)
  return xhtml.div {title = title,
    xhtml.label (label), 
    xhtml.input {name = name or label: lower(), 
      class="w3-border w3-border-light-gray w3-hover-border-red", size=50,  value=value or ''} }
end

-- make a link to delete a specific something, providing a 'confirm' box
-- e.g. delete_link ("room", 42)
function X.delete_link (what, which, whither)
  return xhtml.a {
    title = "delete " .. (whither or what),
    href = selfref (table.concat {"action=delete&", what, '=', which}), 
    onclick = table.concat {"return confirm('Delete ", whither or what, " #", which, ": Are you sure?')"}, 
    xhtml.img {height=14, width=14, alt="delete", src="icons/trash-alt-red.svg", class = "w3-hover-opacity"} }
end

function X.rhs (text) return {text, style="text-align:right"} end

function X.lhs (text) return {text, style="text-align:left" } end

function X.get_user_html_as_dom (html)
  if type(html) == "string" then             -- otherwise assume it's a DOM (or nil)
    local x = xml.decode (html)
    html = x.documentElement
  end
  return html
end

-- make a simple HTML table from data
function X.create_table_from_data (columns, data, formatter)
  local tbl = xhtml.table {class="w3-small"}
  tbl.header (columns)
  for i,row in ipairs (data) do 
    if formatter then formatter (row, i) end  -- pass the formatter both current row and row number
    tbl.row (row) 
  end
  if #data == 0 then tbl.row {"--- none ---"} end
  return tbl
end

-- create a unique id  string
local function unique_id ()
  return "id" .. tostring {} : match "%w+$"
end

local xtimes = json.decode '["\\u00D7"]' [1]    -- multiplication sign (for close boxes)

-- onclick action for a button to pop up a model dialog
-- mode = "none" or "block", default is "block" to make popup visible
function X.popup (x, mode)
  mode = mode and "none" or "block"
  local onclick = [[document.getElementById("%s").style.display="%s"]] 
  return onclick : format (x.id, mode)
end

function X.modal (content)
  local closebtn = xhtml.span {class="w3-button w3-round-large w3-display-topright w3-xlarge", xtimes}
  local id = unique_id ()
  local modal = 
    xhtml.div {class="w3-modal", id=id,
      xhtml.div {class="w3-modal-content w3-round-large",
        xhtml.div {class="w3-container", closebtn, content}}}
  closebtn.onclick = X.popup (modal, "none")
  return modal
end

function X.modal_button (form, button)
  local modal = X.modal (form)
  button.onclick = X.popup (modal)
  button.class = "w3-button w3-round w3-green"
  return xhtml.div {modal, button}
end

  
local function ace_editor_script (theme, language)
  local script = [[
  
    var editor = ace.edit("editor");
    editor.setTheme("ace/theme/%s");
    editor.session.setMode("ace/mode/%s");
    editor.session.setOptions({tabSize: 2});
    function EditorSubmit() {
      var element = document.getElementById("lua_code");
      element.value = ace.edit("editor").getSession().getValue();
      element.form.submit();}
      
    ]]
  return xhtml.script {script: format(theme, language)}
end
 
-- code editor using ACE Javascript or plain textbox
-- returns editor window and submit button for inclusion in a form
local function edit_and_submit (code, height, language)
  if not code or code == '' then code = ' ' end   -- ensure non-empty code div
  language = language or "lua"
  height = (height or "500") .. "px;"
  local button_class = "w3-button w3-round w3-light-blue w3-margin"
  local id = "lua_code"
  local editor, submit_button
  local options = luup.attr_get "openLuup.Console" or {}   -- get configuration parameters
  local ace_url = options.Ace_URL
  local theme = options.EditorTheme
  
  if ace_url ~= '' then
    submit_button = xhtml.input {class=button_class, type="button", onclick = "EditorSubmit()", value="Submit"}
    editor = xhtml.div {
      xhtml.input {type="hidden", name="lua_code", id=id},    -- return field for the edited code
      xhtml.div {id="editor", class="w3-border", style = "width: 100%; height:"..height, code },  -- ace playground
      xhtml.script {src = ace_url, type="text/javascript", charset="utf-8"},    -- ace code
      ace_editor_script (theme, language)}
  
  else  -- use plain old textarea for editing
    submit_button = xhtml.input {class=button_class, value="Submit", type = "submit"}
    editor = xhtml.div {
        xhtml.textarea {name="lua_code", id=id, 
          class="w3-monospace w3-small",
          style = table.concat {
            "width: 100%; resize: none; height:", height},
--            "font-family:Monaco, Menlo, Ubuntu Mono, Consolas, ", 
--                        "source-code-pro, monospace; font-size:9pt; line-height: 1.3;"},
          code}}  
  end
  return editor, submit_button
end

-- text editor
function X.code_editor (code, height, language, readonly, codename)
  codename = codename or ' '
  local editor, submit_button = edit_and_submit (code, height, language)    
  if readonly then 
    submit_button = nil      -- can't change anything if you can't submit
  else
    submit_button.class = "w3-button w3-round w3-green w3-margin"
  end
  
  return xhtml.form {
      action="/data_request?id=XMLHttpRequest&action=submit_lua&codename=" .. codename, 
      target="output", 
      method="post",
      editor, 
      submit_button}
  
end

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
X.XMLHttpRequest = XMLHttpRequest

server.add_callback_handlers {XMLHttpRequest = 
  function (_, p) return XMLHttpRequest[p.action] (p) end}


-------------------
--
-- Console Pop-up utilities
--

local P = {}

-- create new variable

local function find_all_existing_serviceIds ()
  local services, svc = {}, {}
  for _, dev in pairs (luup.devices) do
    for srv in pairs (dev.services) do services[srv] = true end
  end
  services.openLuup = nil   -- don't want to offer this as an option
  for srv in pairs (services) do svc[#svc+1] = srv end
  table.sort (svc)
  return (svc)
end 

local function create_variable ()
  local class = "w3-input w3-border w3-hover-border-blue"
  -- search through existing devices for all the serviceIds
  local service_list = xhtml.datalist {id= "services"}
  for _, svc in ipairs (find_all_existing_serviceIds()) do
    service_list[#service_list+1] = xhtml.option {svc}
  end
  return X.Form {class = "w3-container w3-form", 
    xhtml.h3 "Create Variable",
    xhtml.label {"Variable name"},
    xhtml.input {class=class, type="text", name="name", autocomplete="off", },
    xhtml.label {"ServiceId"},
    xhtml.input {class=class, type="text", name="service", autocomplete="off", 
      list="services", value="urn:", class="w3-input"},
    service_list,
    xhtml.label {"Value"},
    xhtml.input {class=class, type="text", name="value", autocomplete="off", },
    xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Create Variable"},
  }
end

function P.create_variable ()
  return X.modal_button (
    create_variable(),
    xhtml.button {"+ Create"; title="create new variable"})
end

function P.create_room ()
  local form = X.Form {class = "w3-container w3-form", 
    xhtml.h3 "Create Room",
    xhtml.label {"Room name"},
    xhtml.input {class="w3-input w3-border w3-hover-border-blue", type="text", name="name", autocomplete="off", },
    xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Create Room"},
  }
  return X.modal_button (
    form,
    xhtml.button {"+ Create"; title="create new room"})
end

function P.create_device ()
  local form = X.Form {class = "w3-container w3-form", 
    xhtml.h3 "Create Device",
    selfref = "action=create_device", 
    xhtml.label {"Device name"},
    xhtml.input {class="w3-input w3-border w3-hover-border-blue", type="text", name="name", autocomplete="off", },
    X.options ("Device file", "d_file", "^D_.-%.xml$", "D_"),
    X.options ("Implementation file", "i_file", "^I_.-%.xml$", "I_"),
    xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Create Device"},
  }
  return X.modal_button (
    form,
    xhtml.button {"+ Create"; title="create new device"})
end

function P.create_scene ()
  local form = X.Form {class = "w3-container w3-form", 
    xhtml.h3 "Create Scene",
    selfref = "action=create_scene", 
    xhtml.label {"Scene name"},
    xhtml.input {class="w3-input w3-border w3-hover-border-blue", type="text", name="name", value = '', autocomplete="off", },
    xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Create Scene"},
  }
  return X.modal_button (
    form,
    xhtml.button {"+ Create"; title="create new scene"}) 
end

-- this menu selector returns a complete web page,
-- so needs to use its own local xhtml document
function XMLHttpRequest.var_menu (p)
  local xhtml = X.createW3Document ()
  local dno = tonumber (p.dev)
  local dev = luup.devices[dno]
  local json = '{"svc":"%s", "var":"%s"}'
  local vselect = xhtml.select {class="w3-input w3-border w3-hover-border-blue", name="svc_var", required=true}
  vselect[1] = xhtml.option {"Select ...", value = '', selected=true}
  if dev then
    for s, svc in sorted (dev.services) do
      vselect[#vselect+1] = xhtml.optgroup {label=s}
      for v in sorted (svc.variables) do
        vselect[#vselect+1] = xhtml.option {v, value= json: format (s,v)}
      end
    end
  end 
  xhtml.body:appendChild {
    X.Form {class = "w3-form", target="_parent",
      selfref = "action=create_trigger",
      xhtml.input {hidden=1, name="name", value=p.name} ,
      xhtml.input {hidden=1, name="dev", value=dno or 0} ,
      vselect,
      xhtml.div {xhtml.label "Lua Code"},
      edit_and_submit ('', 140)}}
   return tostring(xhtml)
end

local function device_selector ()
  local dev_by_room = {}
  for i, dev in sorted (luup.devices) do
    local room = dev_by_room[dev.room_num] or {}
    room[#room+1] = xhtml.option {devname(i), value=i}
    dev_by_room[dev.room_num] = room
  end
  local dselect = xhtml.select {class="w3-input w3-border w3-hover-border-blue", name="dev", onchange="this.form.submit()"}
  dselect[1] = xhtml.option {"Select ...", value = '', selected=true}
  for i, room in sorted (dev_by_room) do
    dselect[#dselect+1] = xhtml.optgroup {label = luup.rooms[i] or "No Room"}
    for _, dev in pairs (room) do
      dselect[#dselect+1] = dev
    end
  end
  return dselect
end

function P.create_trigger ()    
  local var_menu_url = "/data_request?id=XMLHttpRequest&action=var_menu"
  local form = X.Form {class = "w3-container w3-form", 
    action = var_menu_url,
    target = "var_menu",
    xhtml.h3 "Trigger",
    xhtml.label "Name",
    xhtml.input {name="name", value="New Trigger", class="w3-input w3-border w3-border-hover-blue"},
    xhtml.label {"Device"},
    device_selector (),
    xhtml.label {"Variable"},
    xhtml.iframe {name = "var_menu", width="100%", height=270, class = "w3-border-0",    -- variable form
      src = var_menu_url,      -- load this menu initially
    }}
  return X.modal_button (
    form,
    xhtml.button {"+ Create"; title="create new trigger"})
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

local timer_menu_url = "/data_request?id=XMLHttpRequest&action=timer_menu"

-- this menu selector returns a complete web page,
-- so needs to use its own local xhtml document
function XMLHttpRequest.timer_menu (p)
  local Forms = {
    function ()   -- Interval
      return 
        xhtml.label {"Repeat every: "; class="w3-cell", 
        xhtml.input {name = "interval", title = "enter time interval", 
          class="w3-container w3-border w3-hover-border-blue", size=8,  value='', required=true},
        xhtml.select {name = "units", class="w3-container w3-border w3-round w3-hover-border-blue", 
          xhtml.option {"days", value='d'},
          xhtml.option {"hours", value='h'},
          xhtml.option {"minutes", value='m'},
          xhtml.option {"seconds", value=''}}}
    end,
    function ()  -- Day of Week
      local day_of_week = xhtml.div {}
      for day in ("Mon Tue Wed Thu Fri Sat Sun"): gmatch "%a+" do
        day_of_week:appendChild {
          xhtml.label {day: sub(1,1)},
          xhtml.input {type="checkbox", name=day, class="w3-check"}}
      end
      local runtime = xhtml.div {class="w3-margin-top",
        xhtml.label "Run at: ",
        xhtml.input {name = "time", type="time", title="enter time of day", required=true}}
      return
        day_of_week, runtime
    end,
    function ()   -- Day of Month
      local day_of_month = xhtml.div{
        xhtml.div {xhtml.label "Days on which to run (comma or space separated): "}, 
        xhtml.input {name="days", autocomplete="off", size=50,
          class="w3-border w3-border-gray w3-hover-border-light-blue w3-animate-input", value= ''} }
      local runtime = xhtml.div {class="w3-margin-top",
        xhtml.label "Run at: ",
        xhtml.input {name = "time", type="time", title="enter days of the month", required=true}}
      return
        day_of_month, runtime
    end,
    function ()   -- Absolute
      return
        xhtml.label "Run once at: ",
        xhtml.input {name = "datetime", type="datetime-local", title="enter date/time", required=true} 
    end}
  
  local xhtml = X.createW3Document ()
  local Ttypes = {"Interval", "Day of Week", "Day of Month", "Date/Time"}
  local ttype = p.ttype or Ttypes[1]
  local bar = xhtml.div {class="w3-bar"}
  local form
  for i, t in ipairs (Ttypes) do
    local selected = t == ttype 
    local colour = "w3-light-blue"
    if selected then 
      colour = "w3-grey"
      form = X.Form {class = "w3-form", target="_parent",
        selfref = "action=create_timer",
        xhtml.h5 (Ttypes[i]), 
        xhtml.div {class="w3-container",
          xhtml.label "Name",
          xhtml.input {name="name", value="New Timer", class="w3-input w3-border w3-margin-bottom"}},
        xhtml.input {type="hidden", name="ttype", value=i},
        xhtml.div {class="w3-container w3-cell-row", (Forms[i] or tostring) ()},
      xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Submit"}}
    end
    bar[#bar+1] = X.ButtonLink {t; class=colour, href = timer_menu_url .. "&ttype=" .. t}
  end
  local timer_selector = bar
      
  xhtml.body:appendChild {
    xhtml.h3 "Timer",
    timer_selector,
    form}
  return tostring (xhtml)
end
    
function P.create_timer ()
  return X.modal_button (
    xhtml.iframe {name = "timer_menu", width="100%", height=380, class = "w3-border-0",    -- timer frame
      src = timer_menu_url},      -- load this menu initially
    xhtml.button {"+ Create"; title="create new timer"})
end

-- this menu selector returns a complete web page,
-- so needs to use its own local xhtml document
function XMLHttpRequest.t_menu (p)
  local xhtml = X.createW3Document ()
  local dno = tonumber (p.dev)
  local dev = luup.devices[dno]
  local json = '{"svc":"%s", "act":"%s"}'
  local aselect = xhtml.select {class="w3-input w3-border w3-hover-border-blue", name="svc_act", 
    onchange="this.form.submit()"}
  aselect[1] = xhtml.option {"Select ...", value = '', selected=true}
  if dev then
    for s, svc in sorted (dev.services) do
      aselect[#aselect+1] = xhtml.optgroup {label=s}
      for v in sorted (svc.actions) do
        aselect[#aselect+1] = xhtml.option {v, value= json: format (s,v)}
      end
    end
  end
  xhtml.body:appendChild {
    X.Form {class = "w3-form", target="_parent",
      selfref = "action=create_action",
      xhtml.input {hidden=1, name="dev", value=dno or 0} ,
      aselect,
    }}
   return tostring(xhtml)
end

local function get_argument_list (s, a)
  local service_actions = (service_data[s] or empty) .actions
  local args = xhtml.div {class="w3-panel w3-light-grey w3-padding-16"}
  for _, act in ipairs (service_actions or empty) do
    if act.name == a and act.argumentList then
      for _, v in ipairs (act.argumentList) do
        if (v.direction or ''): match "in" then 
          local name = v.name
          args[#args+1] = xhtml.div {class="w3-container w3-margin-bottom",
            xhtml.label {name, ": ", class="w3-container w3-third w3-right-align"}, 
            xhtml.input {name = name, size=50, value='', autocomplete="off",
              class="w3-container w3-twothird w3-border w3-border-light-gray w3-hover-border-blue"}}
        end
      end
    end
  end
  return args
end

local act_menu_url = "/data_request?id=XMLHttpRequest&action=act_menu"

-- this menu selector returns a complete web page,
-- so needs to use its own local xhtml document

function XMLHttpRequest.act_menu (p)
  local xhtml = X.createW3Document ()
  local dno = tonumber (p.dev)
  local dev = luup.devices[dno]
  local svc_act = json.decode (p.svc_act or "{}")    -- do we have a known service action?
  local SVC,ACT
  if type(svc_act) == "table" then
    SVC,ACT = svc_act.svc, svc_act.act
  end
  local sajson = '{"svc":"%s", "act":"%s"}'
  local aselect = xhtml.select {class="w3-input w3-border w3-hover-border-blue", name="svc_act", 
    required=true, onchange="this.form.submit()"}
  aselect[1] = xhtml.option {"Select ...", value='', selected=not ACT or nil}
  local aparameters = xhtml.span {}
  
  if dev then
    for s, svc in sorted (dev.services) do
      aselect[#aselect+1] = xhtml.optgroup {label=s}
      for a in sorted (svc.actions) do
        local selected = s == SVC and a == ACT
        aselect[#aselect+1] = xhtml.option {a, value= sajson: format (s,a), selected=selected or nil}
        if selected then    -- add parameters
          aparameters = get_argument_list (s, a)
        end
      end
    end
  end
  
  xhtml.body:appendChild {
    X.Form {class = "w3-form", 
      action = act_menu_url,
      xhtml.input {hidden=1, name="dev", value=dno or 0} ,
      xhtml.input {name="group", value=p.group, hidden=1},
      aselect,
      aparameters,
      xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Submit",
        formaction=selfref "action=create_action", formtarget="_parent"}
      }}
   return tostring(xhtml)
end

function P.create_action_in_group (group_num)
  local frame_name = "var_menu_" .. group_num
  local form = X.Form {class = "w3-container w3-form", 
    action = act_menu_url,
    target = frame_name,
    xhtml.h3 "Action",
    xhtml.input {name="group", value=group_num, hidden=1},
    xhtml.label {"Device"},
    device_selector (),
    xhtml.label {"Action"},
    xhtml.iframe {name = frame_name, width="100%", height=440, class = "w3-border-0",    -- variable form
      src = act_menu_url,      -- load this menu initially
    }}
  return X.modal_button (
    form,
    xhtml.button {"+ Action"; class="w3-container", title="create new action\nin this delay group"})
end

-- new delay group
function P.create_new_delay_group ()
  local form = X.Form {class = "w3-form", 
    selfref = "action=create_group",
    target = "_parent",
    xhtml.h3 "Create Delay Group",
    xhtml.div {class="w3-panel",
      xhtml.label {"Delay (mm:ss):"},
      xhtml.input {name="delay", type="time", required=true}},
    xhtml.input {type="submit", value="Submit", class="w3-button w3-round w3-light-blue w3-margin"}}
  return X.modal_button (
    form,
    xhtml.button {"+ Delay"; class="w3-container", title="create new delay group"})
end

return 
  function (_selfref) 
    selfref = _selfref
    return X, U, P
  end

-------------------
