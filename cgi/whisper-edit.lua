#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "whisper-edit",
  VERSION       = "2019.05.03",
  DESCRIPTION   = "Whisper database editor script cgi/whisper-edit.lua",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "",
}

-- Whisper file editor, using storage finder and WSAPI request and response libraries

-- based on 2016.07.06 whisper-editor

local whisper   = require "openLuup.whisper"
local wsapi     = require "openLuup.wsapi"        -- for request library
local html5     = require "openLuup.xml" .html5
local vfs       = require "openLuup.virtualfilesystem"


local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

-- global entry point called by WSAPI connector


local pagename = "w-edit"

-----------------------------------

local input = html5.input
local br = html5.br {}
  
local function row (time, value)
  return {os.date ("%Y-%m-%d %H:%M:%S", time), {style="background:LightGray", input {name=time, value=value}}}
end  

local function ymd (date, hour, min,sec)
  local y,m,d = (date or ''): match "(%d%d%d%d)%D(%d%d)%D(%d%d)"
  if y then
    return os.time {year=y, month=m, day=d, hour=hour, min=min, sec=sec}
  end
end


-----------------------------------
-- for future use...?
--[[

  -- find min and max times in tv array (interleaved times and values)
  -- note that a time of zero means, in fact, undefined
  local function min_max (x)
    local min,max = os.time(),x[1]
    for i = 1,#x, 2 do
      local t = x[i]
      if t > 0 then
        if t > max then max = t end
        if t < min then min = t end
      end
    end
    return min, max
  end  
  
  -- gets the timestamp of the oldest and newest datapoints in file
  local function earliest_latest (header)
    local archives = header.archives
    -- search for latest in youngest archive
    local youngest = archives[1].readall()
    local _, late = min_max (youngest)
--    early = os.time() - header['maxRetention']    -- instead, search for earliest in oldest archive
    local oldest = archives[#archives].readall()
    local early = min_max (oldest)
    if late < early then late = early end
    return Interval (early, late)
  end
--]]

-----------------------------------

function run (wsapi_env)
  
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax
  
  local req = wsapi.request.new (wsapi_env)   -- use request library to get object with useful methods
  local res = wsapi.response.new ()           -- and the response library to build the response!
  
  
  -- read the basic parameters from ETHER the GET or the POST parameters
  
  local now = os.time()
  local date = "%Y-%m-%d"
  local params = req.params
  local target = params["target"]
  local from = params["from"]
  local to = params["until"]
  from = ymd(from) and from or os.date (date, now)
  to   = ymd(to)   and to   or os.date (date, now)

  -- get the requested data
  
  local I, V, T
  local data = whisper.fetch (target, ymd(from, 0,0,0), ymd(to, 23,59,59))
  if data then
    local n = 0
    I, V, T = {}, {}, {}            -- I is index table
    for _, v,t in data:ipairs () do
      if v then                     -- only show non-nil data
        n = n + 1
        T[n] = t
        V[n] = v
        I[tostring(t)] = n      -- also index by text time (since post requests come that way)
      end
    end
  end

  -- POST processing: if valid data and updates, then make changes
  
  if V and req.method == "POST" then
    local post = req.POST
    local Tedit, Vedit = {}, {}
    for t,v in pairs (post) do            -- NB: t is a string
      local tn = tonumber (t) 
      local vn = tonumber (v)
      local idx = I[t]
      if tn and vn and V[idx] ~= vn then    -- has been edited
--        print (tn, "old: " .. V[idx], "new: " .. vn)
        Tedit[#Tedit+1] = tn
        Vedit[#Vedit+1] = vn
        V[idx] = vn                        -- update table with new value
      end
    end
    
    whisper.setAggregationMethod (target, post.aggregation, post.xFilesFactor)  -- update aggregation
    
    luup.log ("Graphite Editor - Number of edits: " .. #Vedit)
    -- whisper.update_many (path,values,timestamps, now)
    local ok = pcall (whisper.update_many, target, Vedit, Tedit, now) 
    if not ok then luup.log ("Whisper file update failed: " .. target) end
  end

  -- build the common items on the return page
  
  local t = html5.table {style="margin:20px;"}
  t: header {
    {"Target: ", title="full file path"}, 
    input {type="text", name="target", style="width:30em;", value=target}}
  t: row {
    {"from:  ", title="from start of this day"}, 
    input {type="date", name="from", value=from}}
  t: row {
    {"until: ", title="until end of this day"},
    input {type="date", name="until", value=to}}
  local read_form = html5.fieldset {style = "width:350px;",
    html5.legend {"Database Query"},
    html5.form {
      action=req.script_name, method="get",
      input {type="hidden", name="page", value=pagename},
      t,
      input {type="Submit", value="Read", style="background:HoneyDew", title="get data to edit"},
--      br,
    },
  }

  -- if there is any data, then build an editable table

  local w = ''      -- default to blank space
  if V then
    w = html5.table {style = "margin:20px;"}
    w: header {"date / time", "value"}
    for i,v in ipairs (V) do
      w: row (row (T[i], v))
    end
  end
  
  local info = whisper.info (target)
  local s = {{"aggregation:", title="function for combining samples between archives"}}
  for _, method in ipairs (whisper.aggregationTypeToMethod) do
    local checked
    if method == info.aggregationMethod then checked = '1' end
    s[#s+1] = input {type="radio", name="aggregation", value=method, checked=checked, ' '..method..' '}
  end
  
  local x = html5.table {style = "margin:20px;"}
  x: header {
    {"Archives: ",title="sample rate:time span, ..., for each resolution archive"},
    {colspan=5, tostring(info.retentions)}}
  x: row (s)
  local xff = ("%0.2f"):format (info.xFilesFactor)
  x: row {{"xFilesFactor:", title = "xff (0-1) if you don't know what this is, don't change it"}, 
    {colspan = 5, input {name="xFilesFactor", autocomplete="off", value = xff}}}
  
  local write_form = html5.fieldset {style = "width:350px;",
    html5.legend {"Database Update"},
    html5.form {
      x,
      action=req.script_name, method="post",
      input {type="hidden", name="page", value=pagename},
      input {type="hidden", name = "from", value = from},  
      input {type="hidden", name = "until", value = to},  
      input {type="hidden", name = "target", value = target},  
      input {type="Submit", value="Commit", title="write changes back to file"},
      input {type="Reset", title="clear changes to table"},
      br, br, html5.div {style="display: table;", w}
    }}
   
  
  local style = html5.style {
    vfs.read "openLuup_console.css", [[
      input[type=submit] 
        {font-size:12pt; width:6em; height:2em; border-radius: 4px; background:LavenderBlush; 
         margin:10px; border:none; cursor:pointer; float:right}
      input[type=reset]  
        {font-size:12pt; width:6em; height:2em; border-radius: 4px; background:LightYellow;
         margin:10px; border:none; cursor:pointer; float:right}
      input:hover {filter:brightness(90%)}
      input[type=text] {autocomplete:off;}
    ]]}
  local head = html5.head {html5.meta {charset="utf-8"}, html5.title {"W-Edit"}, style}
  local html = html5.document {head, html5.div {class="content", read_form, br, write_form}}
  res:write (html)

  return res:finish()
end

-----
