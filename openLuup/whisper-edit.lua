#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "whisper-edit",
  VERSION       = "2019.07.15",
  DESCRIPTION   = "Whisper database editor script cgi/whisper-edit.lua",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "",
}

-- Whisper file editor, using storage finder and WSAPI request and response libraries

-- 2016.07.06  based on original whisper-editor
-- 2019.06.07  use w3.css style sheets
-- 2019.06.29  use xhtml module
-- 2019.07.15  use new xml.createHTMLDocument() factory method


local whisper = require "openLuup.whisper"
local wsapi   = require "openLuup.wsapi"        -- for request library
local xml     = require "openLuup.xml"


local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

-- global entry point called by WSAPI connector


local pagename = "w-edit"

-----------------------------------

local button_class = "w3-button w3-border w3-margin w3-round-large "

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
  local tv = whisper.fetch (target, ymd(from, 0,0,0), ymd(to, 23,59,59))
  if tv then
    local n = 0
    I, V, T = {}, {}, {}            -- I is index table
    for _, v,t in tv:ipairs () do
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

  --
  -- build the HTML page
  --
  
  local h = xml.createHTMLDocument "W-Edit"
  
  local read_form = h.div {class = "w3-card w3-margin w3-small",
    h.div {class = "w3-container w3-grey",
      h.h4 {"Database Query"}},
    h.form {class = "w3-container w3-margin-top",
      action=req.script_name, 
      method="get",
      h.input {type="hidden", name="page", value=pagename},
      h.label {"target: ", title="full file path"}, 
      h.input {class = "w3-input", type="text", name="target", value=target},
      h.label {"from:  ", title="from start of this day"}, 
      h.input {class = "w3-input", type="date", name="from", value=from},
      h.label {"until: ", title="until end of this day"},
      h.input {class = "w3-input", type="date", name="until", value=to},
      h.div {class = "w3-right-align",
        h.input {class = button_class .. "w3-pale-green",
          type="Submit", value="Read", title="get data to edit"}
        },
    },
  }

  -- if there is any data, then build an editable table
    
  local function row (time, value)
    return {os.date ("%Y-%m-%d %H:%M:%S", time), h.input {name=time, value=value}}
  end  

  local data = ''      -- default to blank space
  if V then
    data = h.table {class = "w3-table"}
    data: header {"date / time", "value"}
    for i,v in ipairs (V) do
      data: row (row (T[i], v))
    end
  end
  
  local info = whisper.info (target)
  local aggregation = {}
  for _, method in ipairs (whisper.aggregationTypeToMethod) do
    local checked
    if method == info.aggregationMethod then checked = '1' end
    aggregation[#aggregation+1] = h.label {method}
    aggregation[#aggregation+1] = h.input {type="radio", name="aggregation", value=method, checked=checked}
  end
  
  local xff = ("%0.2f"):format (info.xFilesFactor)
  
  local write_form = h.div {class = "w3-card w3-margin w3-small",
    h.div {class = "w3-container w3-grey",
      h.h4 {"Database Update"}},
    h.form {class = "w3-container w3-margin-top",
      action=req.script_name, 
      method="post",
      h.input {type="hidden", name = "page",   value = pagename},
      h.input {type="hidden", name = "from",   value = from},  
      h.input {type="hidden", name = "until",  value = to},  
      h.input {type="hidden", name = "target", value = target},  
      h.label {"archives: ",title="sample rate:time span, ..., for each resolution archive"},
      h.input {class = "w3-input", readonly=1, disabled=1, value = tostring(info.retentions)},
      h.label {"aggregation:", title="function for combining samples between archives"},
      h.div {class = "w3-white w3-padding w3-border-bottom", h.div (aggregation) },
      h.label {"xFilesFactor:", title = "xff (0-1) if you don't know what this is, don't change it"}, 
      h.input {class = "w3-input", name="xFilesFactor", autocomplete="off", value = xff},
      h.div {class = "w3-right-align",
        h.input {class = button_class .. "w3-pale-yellow", 
          type="Reset", title="clear changes to table"},
        h.input {class = button_class .. "w3-pale-red", 
          type="Submit", value="Commit", title="write changes back to file"},
      },
      h.div {class = "w3-panel w3-border w3-hover-border-red", data},
    }}
 
  h.body:appendChild {
    h.meta {charset="utf-8", name="viewport", content="width=device-width, initial-scale=1"}, 
    h.link {rel="stylesheet", href="https://www.w3schools.com/w3css/4/w3.css"},
    h.div {class = "w3-panel w3-cell", read_form, write_form}}
  
  res:write (tostring(h))

  return res:finish()
end

-----
