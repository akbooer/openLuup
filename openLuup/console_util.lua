local ABOUT = {
  NAME          = "utility.lua",
  VERSION       = "2023.03.04",
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
local userdata  = require "openLuup.userdata"     -- for plugin info
local timers    = require "openLuup.timers"       -- for timing Lua Test code runs
local xhtml     = xml.createHTMLDocument ()       -- factory for all HTML tags

local service_data  = loader.service_data         -- for action parameters

local empty = setmetatable ({}, {__newindex = function() error ("read-only", 2) end})

local pretty = loader.shared_environment.pretty

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
  xhtml.documentElement[1]:appendChild {  -- the <HEAD> element
    xhtml.meta {charset="utf-8", name="viewport", content="width=device-width, initial-scale=1"},
    xhtml.link {rel="stylesheet", href="w3.css"},
    xhtml.link {rel="stylesheet", href="openLuup_console.css"}}
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

-- onclick action for a button to pop up a modal dialog
-- mode = "none" or "block", default is "block" to make popup visible
function X.popup (x, mode)
  mode = mode and "none" or "block"
  local onclick = [[document.getElementById("%s").style.display="%s"]] 
  return onclick: format (x.id, mode)
end

-- onclick action for a button to pop up a menu
function X.popMenu (menu)
  local onclick=[[popup ("data_request?id=XMLHttpRequest&action=%s")]]
  return onclick: format (menu)
end

function X.modal (content, id)
  id = id or unique_id ()
  local closebtn = xhtml.span {class="w3-button w3-round-large w3-display-topright w3-xlarge", '×'}
  local modal = 
    xhtml.div {class="w3-modal", id=id,
      xhtml.div {class="w3-modal-content w3-round-large",
        xhtml.div {class="w3-container", 
          closebtn, 
          content}}}
  closebtn.onclick = X.popup (modal, "none")
  return modal
end

function X.modal_button (form, button)
  local modal = X.modal (form)
  button.onclick = X.popup (modal)
  button.class = "w3-button w3-round w3-green"
  return xhtml.div {modal, button}
end

--[[
  height = n,
  top_line {left = ..., right = ...},
  icon = icon,
  body = {middle = ..., topright = ..., bottomright = ...},
  widgets = { w1, w2, ... },
--]]
function X.generic_panel (x, panel_type)
  panel_type = panel_type or "tim-panel"
  local div = xhtml.div
  local widgets = xhtml.span {class="w3-wide"}
  for i,w in ipairs (x.widgets or empty) do widgets[i] = w end
  local class = "w3-small w3-margin-left w3-margin-bottom w3-round w3-border w3-card " .. panel_type
  return xhtml.div {class = class,
    div {class="top-panel", 
      truncate (x.top_line.left or ''), 
      xhtml.span{style="float: right;", x.top_line.right or '' } }, 
    div {class = "w3-display-container", style = table.concat {"height:", x.height, "px;"},
--          div {class="w3-padding-small w3-margin-left w3-display-left ", x.icon } , 
      div {class="w3-margin-left w3-display-left ", x.icon } , 
      div {class="w3-display-middle", x.body.middle},
      div {class="w3-padding-small w3-display-topright", x.body.topright } ,
      div {class="w3-padding-small w3-display-bottomright", x.widgets and div(x.widgets) or x.body.bottomright } 
          }  } 
end

function X.find_plugin (plugin)
  local IP2 = userdata.attributes.InstalledPlugins2
  for _, plug in ipairs (IP2) do
    if plug.id == plugin then return plug end
  end
end

local modal do
  local div, span, p = xhtml.div, xhtml.span, xhtml.p
  modal = 
    div {id="modal", class="w3-modal",
      div {class="w3-modal-content",
        div {class="w3-container",
          span {onclick="document.getElementById('modal').style.display='none'",
                    class="w3-button w3-display-topright">'x'},
          p "Some text in the Modal..",
          p "Some text in the Modal..",
        }}}
end

local function ace_editor_script (theme, language, window)
  language = language or "lua"
  window = window or "editor"
  local script = [[
  
    var editor = ace.edit("%s");
    editor.setTheme("ace/theme/%s");
    editor.session.setMode("ace/mode/%s");
    editor.session.setOptions({tabSize: 2});
    ]]
  return xhtml.script {script: format(window, theme, language)}
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
    submit_button = xhtml.input {class=button_class, type="button", 
--      onclick = "EditorSubmit()", value="Submit"}
      onclick = "AceEditorSubmit('lua_code', 'editor')", value="Submit"}
    editor = xhtml.div {
      xhtml.input {type="hidden", name="lua_code", id=id},    -- return field for the edited code
      xhtml.div {id="editor", class="w3-border", style = "width: 100%; height:"..height, code },  -- ace playground
      xhtml.script {src = ace_url, type="text/javascript", charset="utf-8"},    -- ace code
      ace_editor_script (theme, language, "editor")}
  
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

-- text editors

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

function X.lua_scene_editor (code, height)
  local editor, submit_button = edit_and_submit (code, height)    
  submit_button.class = "w3-button w3-round w3-green w3-margin"
  return xhtml.form {
      action=selfref "action=edit_scene_lua", 
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

server.add_callback_handlers {XMLHttpRequest = 
  function (_, p) return XMLHttpRequest[p.action] (p) end}

-- execute Lua Test code

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
  
--  local N = #P - 1
--  P[1] = table.concat {"--- ", N, " line", N == 1 and '' or 's', " --- ", cpu, " ms --- ", "\n"}

  local h = xml.createHTMLDocument "Console Output"
  local printed = table.concat (P)
  local _, nlines = printed:gsub ('\n',{})    -- the proper way to count lines
  local header = "––– %d line%s ––– %0.1f ms –––"
  h.body: appendChild {
    h.span {style = "background-color: AliceBlue; font-family: sans-serif;",
      header: format (nlines, nlines == 1 and '' or 's', cpu)},
    h.pre (printed) }
  return tostring (h), "text/html"
end

-------------------
--
-- Console Pop-up utilities
--


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

function XMLHttpRequest.create_variable ()
  local class = "w3-input w3-border w3-hover-border-blue"
  -- search through existing devices for all the serviceIds
  local service_list = xhtml.datalist {id= "services"}
  for _, svc in ipairs (find_all_existing_serviceIds()) do
    service_list[#service_list+1] = xhtml.option {svc}
  end
  return X.Form {class = "w3-container w3-form", 
    xhtml.h3 "Create Variable",
    xhtml.label {"Variable name"},
    xhtml.input {class=class, type="text", name="name", autocomplete="off", required=true},
    xhtml.label {"ServiceId"},
    xhtml.input {class=class, type="text", name="service", autocomplete="off", required=true, 
      list="services", value="urn:", class="w3-input"},
    service_list,
    xhtml.label {"Value"},
    xhtml.input {class=class, type="text", name="value", autocomplete="off", },
    xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Create Variable"},
  }
end

function XMLHttpRequest.create_room ()
  local form = X.Form {class = "w3-container w3-form", 
    xhtml.h3 "Create Room",
    xhtml.label {"Room name"},
    xhtml.input {class="w3-input w3-border w3-hover-border-blue", type="text", name="name", autocomplete="off", required=true},
    xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Create Room"},
  }
  return form
end

function XMLHttpRequest.create_device ()
  local form = X.Form {class = "w3-container w3-form", 
    xhtml.h3 "Create Device",
    selfref = "action=create_device", 
    xhtml.label {"Device name"},
    xhtml.input {class="w3-input w3-border w3-hover-border-blue", type="text", name="name", autocomplete="off", required=true},
    X.options ("Device file", "d_file", "^D_.-%.xml$", "D_"),
    X.options ("Implementation file", "i_file", "^I_.-%.xml$", "I_"),
    xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Create Device"},
  }
  return form
end

function XMLHttpRequest.create_scene ()
  local form = X.Form {class = "w3-container w3-form", -- name="popupMenu",
    xhtml.h3 "Create Scene",
    selfref = "action=create_scene", 
    xhtml.label {"Scene name"},
    xhtml.input {class="w3-input w3-border w3-hover-border-blue", type="text", name="name", value = '', 
      autocomplete="off", required=true},
    xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Create Scene"},
  }
  return form
end

function XMLHttpRequest.plugin (p)
  local function w(x) return xhtml.div{x, style="clear: none; float:left; width: 120px;"} end
  -- if specified plugin, then retrieve installed information
  local P = X.find_plugin (p.plugin) or empty
  ---
  local D = (P.Devices or empty) [1] or empty
  local R = P.Repository or empty
  local F = table.concat (R.folders or empty, ", ")
  ---
  local app = xhtml.div {class="w3-container",
    xhtml.h3 "Plugin",
    xhtml.form {class = "w3-form", method="post", action=selfref  "page=plugins_table", name="popupMenu",
      xhtml.div {class = "w3-container w3-grey", xhtml.h5 "Application"},
      xhtml.div {class = "w3-panel",
        X.input (w "ID", "id", P.id, "number of Vera plugin or name of openLuup plugin"),
        X.input (w "Title", "title", P.Title, "name for plugin"),
        X.input (w "Icon", "icon", P.Icon or '', "URL (relative or absolute) for .png or .svg")},
      
      xhtml.div {class = "w3-container w3-grey", xhtml.h5 "Device files"},
      xhtml.div {class = "w3-panel",
        X.options ("Device file", "d_file", "^D_.-%.xml$", D.DeviceFileName or "D_"),
        X.options ("Implementation file", "i_file", "^I_.-%.xml$", D.ImplFile or "I_")},
      
      xhtml.div {class = "w3-container w3-grey", xhtml.h5 "GitHub"},
      xhtml.div {class = "w3-panel",
        X.input (w "Repository", "repository", R.source, "eg. akbooer/openLuup"),
        X.input (w "Pattern", "pattern", R.pattern, "try: [DIJLS]_.+"),
        X.input (w "Folders", "folders", F, "blank for top-level or sub-folder name")},
    
      xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Submit"},
    }}
  return app
end

local function variable_selector (dev, SVC, VAR)
  local jtable = '{"svc":"%s", "var":"%s"}'
  local selected = dev and SVC and VAR
  local vselect = xhtml.select {class="w3-input w3-border w3-hover-border-blue", name="svc_var", required=true}
  vselect[1] = xhtml.option {"Select ...", value = '', selected=not selected or nil}
  if dev then
    for s, svc in sorted (dev.services) do
      local smatch = s == SVC
      vselect[#vselect+1] = xhtml.optgroup {label=s}
      for v in sorted (svc.variables) do
        local vmatch = v == VAR
        vselect[#vselect+1] = xhtml.option {v, value= jtable: format (s,v), selected= smatch and vmatch or nil}
      end
    end
  end 
  return vselect
end

local function device_selector (dno, onchange)
  local dev_by_room = {}
  local selected = dno
  for i, dev in sorted (luup.devices) do
    local room = dev_by_room[dev.room_num] or {}
    room[#room+1] = xhtml.option {devname(i), value=i, selected= i==dno or nil}
    dev_by_room[dev.room_num] = room
  end
  local dselect = xhtml.select {class="w3-input w3-border w3-hover-border-blue", name="dev", required=true,
    onchange=onchange}    -- recursive call
  dselect[1] = xhtml.option {"Select ...", value = '', selected=not selected}
  for i, room in sorted (dev_by_room) do
    dselect[#dselect+1] = xhtml.optgroup {label = luup.rooms[i] or "No Room"}
    for _, dev in pairs (room) do
      dselect[#dselect+1] = dev
    end
  end
  return dselect
end

local empty_trigger_code =[[
-- Lua code is function body which should return boolean
-- variable values new and old are available for use

return true

-- (no end statement is required)
]]


function XMLHttpRequest.edit_trigger (p)
--  print (pretty {edit_trigger=p}) 
  local name, scn, trg, dno, svc, var, lua
  if p.new then 
    p = {name = "New Trigger"}
  end
  name = p.name
  dno = tonumber (p.dev)
  trg = tonumber(p.trg)
  scn = tonumber (p.scn)
  if scn and trg then 
    local scene = luup.scenes[scn]
    local defn = scene.definition
    local trigger = defn.triggers[trg]
    local args = trigger.arguments
    dno = tonumber(args[1].value)
    svc = args[2].value
    var = args[3].value
    lua = trigger.lua
    name = trigger.name
  end
  local dev = luup.devices[dno]
  local form = X.Form {class = "w3-container w3-form", name="popupMenu",
    selfref = "action=create_trigger",
    target = "_parent",
    xhtml.h3 "Trigger",
    xhtml.input {type="hidden", name="trg", value=trg},   -- pass along trigger number if editing existing
    xhtml.div {class="w3-panel",
      xhtml.label "Name",
      xhtml.input {name="name", value=name, class="w3-input w3-border w3-border-hover-blue"},
      xhtml.label {"Device"},
      device_selector (dno, X.popMenu "edit_trigger"),
      xhtml.label "Variable",
      variable_selector (dev, svc, var),
      xhtml.label "Lua Code",
      xhtml.textarea {name="lua_code", rows=6,
        class="w3-monospace w3-small w3-margin-bottom",
        style = "width: 100%; resize: none;",
        lua or empty_trigger_code},   -- needs to be non-blank, for some reason
      xhtml.input {class="w3-button w3-round w3-light-blue", value="Submit", type="submit"},
      }}  
  return form
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

local relative_time = {
        {"At a certain time of day", value=''},
        {"At sunrise", value='R'},
        {"Before sunrise", value='-R'},
        {"After sunrise", value='+R'},
        {"At sunset", value='T'},
        {"Before sunset", value='-T'},
        {"After sunset", value='+T'}}
      
local interval_unit = {
        {"days", value='d'},
        {"hours", value='h'},
        {"minutes", value='m'},
        {"seconds", value=''}}

local function relative_to (p)
  local sign, event = (p.time or ''): upper(): match "([%+%-]?)[%d:]*([RT]?)"
  local signed_event = sign .. event
  -- use these values to select initial option
  local sel = xhtml.select {name = "relative", class="w3-container w3-border w3-round w3-hover-border-blue"}
  for _, rel in ipairs(relative_time) do
    local opt = xhtml.option (rel)
    opt.selected = (rel.value == signed_event) or nil
    sel[#sel+1] = opt
  end
  return sel
end

local function interval_units (p)
  local time_unit = (p.interval or ''): lower(): match "[dhm]?$"
  local sel = xhtml.select {name = "units", class="w3-container w3-border w3-round w3-hover-border-blue"}
  for _, unit in ipairs(interval_unit) do
    local opt = xhtml.option (unit)
    opt.selected = (unit.value == time_unit) or nil
    sel[#sel+1] = opt
  end
  return sel
end

local function unadorned_time(p)          -- strip modifiers from time parameter
  return (p.time or ''): match "%d+:?%d+"
end

local function unadorned_interval(p)      -- strip modifiers from interval parameter
  return (p.interval or ''): match "%d*"
end


local Timer_forms = {
  function (p)   -- Interval
    return 
      xhtml.label {"Repeat every: "; class="w3-cell", 
      xhtml.input {name = "interval", title = "enter time interval", 
        class="w3-container w3-border w3-hover-border-blue", size=8,  
        value=unadorned_interval(p), autocomplete="off", required=true},
      interval_units(p)}
  end,
  function (p)  -- Day of Week
    local Day_of_Week = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
    local day_of_week = xhtml.div {}
    for i, day in ipairs(Day_of_Week) do
      local checked = (p.days_of_week or ''): match (tostring(i))
      day_of_week:appendChild {
        xhtml.label {day: sub(1,1)},
        xhtml.input {type="checkbox", name=day, class="w3-check", checked=checked}}
    end
    local runtime = xhtml.div {class="w3-margin-top",
      xhtml.label "Run at: (hh:mm) ",
      xhtml.input {name = "time", type="time", value=unadorned_time(p), title="enter time of day"},
      relative_to (p)}
    return
      day_of_week, runtime
  end,
  function (p)   -- Day of Month
    local day_of_month = xhtml.div{
      xhtml.div {xhtml.label "Days on which to run (comma or space separated): "}, 
      xhtml.input {name="days", autocomplete="off", size=50, title="enter days of the month",
        class="w3-border w3-border-gray w3-hover-border-light-blue w3-animate-input", value= p.days_of_month or ''} }
    local runtime = xhtml.div {class="w3-margin-top",
      xhtml.label "Run at: (hh:mm) ",
      xhtml.input {name = "time", type="time", value=unadorned_time(p), title="enter time of day"},
      relative_to (p)}
    return
      day_of_month, runtime
  end,
  function (p)   -- Absolute
    return
      xhtml.label "Run once at: (date, hh:mm) ",
      xhtml.input {name = "datetime", type="datetime-local", value=p.time, title="enter date/time", required=true} 
  end}

function XMLHttpRequest.edit_timer (p)
--  print (pretty {edit_timer=p})
  local ttype, name, scn, tim
  if p.new then
    p = {ttype = 1, name = "New Timer"}
  end
  
  ttype = tonumber(p.ttype) or 1
  scn = tonumber(p.scn)
  tim = tonumber(p.tim)
  name = p.name
  
  if scn and tim then     -- copy timer info into parameter list
    local scene = luup.scenes[scn]
    local defn = scene.definition
    local timer = defn.timers[tim]
    name = timer.name
    p.time = timer.time or timer.abstime
    p.interval = timer.interval
    p.days_of_week = timer.days_of_week
    p.days_of_month = timer.days_of_month
    ttype = tonumber(timer.type)
  end
  
--    print (pretty {MODIFIED_edit_timer=p})

  local bar = xhtml.div {class="w3-bar"}
  local form
  local Ttypes = {"Interval", "Day of Week", "Day of Month", "Date/Time"}
  for i, tname in ipairs (Ttypes) do
    local colour = "w3-light-blue"
    if i == ttype then 
      colour = "w3-grey"
      form = X.Form {class = "w3-form", name="popupMenu",
        target="_parent",
        selfref = "action=create_timer",
        xhtml.h5 (tname), 
        xhtml.input {type="hidden", name="tim", value=tim},   -- pass along timer number if editing existing
        xhtml.input {type="hidden", name="ttype", value=i},
        xhtml.div {class="w3-container",
          xhtml.label "Name",
          xhtml.input {name="name", value=name, class="w3-input w3-border w3-margin-bottom"}},
        xhtml.div {class="w3-container w3-cell-row", (Timer_forms[i] or tostring) (p)},
      xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Submit"}}
    end
    bar[#bar+1] = xhtml.button {tname; class="w3-button w3-round " .. colour,
      onclick=X.popMenu ("edit_timer&ttype="..i)}  -- URL parameter overrides form
  end
      
  return xhtml.div {
    xhtml.h3 "Timer",
    bar,
    form}
end

local function get_argument_list (s, a, values)
  local service_actions = (service_data[s] or empty) .actions
  local args = xhtml.div {class="w3-panel w3-light-grey w3-padding-16"}
  local names = {}
  for _, act in ipairs (service_actions or empty) do
    if act.name == a and act.argumentList then
      for i, v in ipairs (act.argumentList) do
        if (v.direction or ''): match "in" then 
          local name = v.name
          names[#names+1] = name
          args[#args+1] = xhtml.div {class="w3-container w3-margin-bottom",
            xhtml.label {name, ": ", class="w3-container w3-third w3-right-align"}, 
            xhtml.input {name = "value_"..i, size=50, value=values[i] or '', autocomplete="off",
              class="w3-container w3-twothird w3-border w3-border-light-gray w3-hover-border-blue"}}
        end
      end
    end
  end
  if #args == 0 then 
    args[1] = xhtml.span "No parameters" 
  else
    args[#args+1] = xhtml.input {type="hidden", name="names", value=json.encode(names)}
  end
  return args
end

local function sa_json (s,a)
  local sajson = '{"svc":"%s", "act":"%s"}'   -- wrap service and action into single JSON entity
  return sajson: format (s,a)
end

local function action_selector (dno, svc_act, values, onchange)
  local dev = luup.devices[dno]
  local SVC,ACT
  if type(svc_act) == "table" then
    SVC,ACT = svc_act.svc, svc_act.act
  end
  local aselect = xhtml.select {class="w3-input w3-border w3-hover-border-blue", name="svc_act", 
    required=true, onchange=onchange}
  aselect[1] = xhtml.option {"Select ...", value='', selected=not ACT or nil}
  local aparameters = xhtml.span {}
  
  if dev then
    for s in sorted (dev.services) do
      aselect[#aselect+1] = xhtml.optgroup {label=s}
-- Note: that we can't use the device's own implemented actions, like this:
--      for a in sorted (svc.actions) do
-- ...since they may not be present (perhaps implemented by a parent or generic request) 
--    so we use the formal service data definitions
      for _, act in sorted ((service_data[s] or empty).actions or empty) do
        local a = act.name
        local selected = (s == SVC and a == ACT) or nil
        aselect[#aselect+1] = xhtml.option {a, value=sa_json(s,a), selected=selected}
        if selected then    -- add parameters
          aparameters = get_argument_list (s, a, values)
        end
      end
    end
  end
  return xhtml.div {aselect, aparameters}
end

function XMLHttpRequest.edit_action (p)
--  print (pretty {edit_action=p})
  if p.new then
    p = {scn = p.scn, group = p.group}        -- preserve scene and group, but remove anything else
  end
  local values = {}                           -- holder for existing argument values
  if p.scn and p.group and p.act then         -- existing action
    local scene = luup.scenes[tonumber(p.scn)]
    local defn = scene.definition
    local group = defn.groups[tonumber(p.group)]
    local action = group.actions[tonumber(p.act)]
    -- set parameters from existing action
    p.dev = action.device
    p.svc_act = sa_json (action.service, action.action) 
    -- action argument
    for i,a in ipairs (action.arguments or empty) do
      values[i] = a.value
    end
    p.existing = p.act
    p.act = nil   -- don't revisit this initialization code
  end
 
  local dno = tonumber(p.dev) 
  local svc_act = json.decode (p.svc_act or "{}")    -- do we have a known service action?
  local group_num = tonumber(p.group) or 1
  local form = X.Form {class="w3-container w3-form", name="popupMenu",  -- popup menu must have this name
    action = selfref "action=create_action",
    target = "_parent",
    xhtml.h3 "Action",
    xhtml.input {type="hidden", name="scn", value=p.scn},   -- pass along scene number if editing existing
    xhtml.input {type="hidden", name="group", value=group_num},   -- ditto group
    xhtml.input {type="hidden", name="existing", value=p.existing},   -- ditto existing action
    xhtml.label {"Device"},
    device_selector (dno, X.popMenu ("edit_action")),
    xhtml.label {"Action"},
    action_selector (dno, svc_act, values, X.popMenu ("edit_action")),
    xhtml.input {class="w3-button w3-round w3-light-blue w3-margin", type="submit", value="Submit"}
    }
  return form
end

-- new delay group
function XMLHttpRequest.create_new_delay_group ()
  local form = X.Form {class="w3-form", 
    selfref = "action=create_group",
    target = "_parent",
    xhtml.h3 "Create Delay Group",
    xhtml.div {class="w3-panel",
      xhtml.label {"Delay (mm:ss):"},
      xhtml.input {name="delay", type="time", value="00:00", required=true}},
    xhtml.input {type="submit", value="Submit", class="w3-button w3-round w3-light-blue w3-margin"}}
  return form
end

function XMLHttpRequest.view_cache (p)
  local dno = tonumber(p.dev)
  local vnum = tonumber(p.var)
  local d = luup.devices[dno]
  local title = devname (dno)
  local v = d and d.variables and d.variables[vnum]
  local TV = {}
  if v then
    local V,T = v:fetch (v:oldest (), os.time())    -- get the whole cache from the oldest available time
    local NT = #T
    for i, t in ipairs (T) do TV[NT-i] = {t, V[i]} end   -- reverse sort
  end
  local t = X.create_table_from_data ({"time", "value"}, TV, function (row) row[1] = nice (row[1]) end)
  local scrolling = xhtml.div {style="height:250px; width:350px; overflow:scroll;", class="w3-border w3-margin-left", t}
  return xhtml.dev {class="w3-container",
    xhtml.h3 "Cache History",
    xhtml.h4 (table.concat {title, '.', (v and v.name) or '?'}),
    xhtml.p {"size = ", #TV, " / ", v.hicache or luup.attr_get "openLuup.Historian.CacheSize" or '?', 
      class="w3-margin-left w3-small"},
    xhtml.div {class ="w3-padding", style="display:inline-block;",scrolling},
    X.Form {name ="popupMenu",
      selfref = "page=graphics",
      target = "_parent",
      xhtml.input {type="hidden", name="dev", value=dno},
      xhtml.input {type="hidden", name="var", value=vnum},
      xhtml.input {type="hidden", name="variable", value=vnum},   -- for graphics page
      xhtml.div {"Refresh", class="w3-button w3-round w3-light-blue w3-margin",
        onclick=X.popMenu "view_cache"},
      xhtml.button {"Graph", class="w3-button w3-round w3-green w3-margin",
        type="submit"},
      }}
end


return 
  function (_selfref) 
    selfref = _selfref
    return X, U
  end

-------------------
