#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "graphite_cgi",
  VERSION       = "2018.06.11",
  DESCRIPTION   = "WSAPI CGI interface to Graphite-API",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2018 AK Booer

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

-- 2016.02.10  translated from Python original... see below
-- 2016.10.10  check for blank Whisper or dataMine directories in storage_find
-- 2016.10.20  add context parameter to treejson response (thanks @ronluna)
-- 2016.10.24  ensure DataYours instance is the LOCAL one!!

-- 2018.06.02  modifications to include openLuup's Data Historian
-- 2018.06.03  use timer module utility functions
-- 2018.06.05  round json render time to 1 second (no need for more in Grafana)
-- 2018.06.10  return error if no target for /render


-- CGI implementation of Graphite API

--[[

Graphite_API 

  "Graphite-web, without the interface. Just the rendering HTTP API.
   This is a minimalistic API server that replicates the behavior of Graphite-web."

see:
  https://github.com/brutasse/graphite-api
  https://github.com/brutasse/graphite-api/blob/master/README.rst

with great documentation at:
  http://graphite-api.readthedocs.org/en/latest/
  
  "Graphite-API is an alternative to Graphite-web, without any built-in dashboard. 
   Its role is solely to fetch metrics from a time-series database (whisper, cyanite, etc.)
   and rendering graphs or JSON data out of these time series. 
   
   It is meant to be consumed by any of the numerous Graphite dashboard applications."
   

Originally written in Python, I've converted some parts of it into Lua with slight tweaks 
to interface to the DataYours implementation of Carbon / Graphite.

It provides sophisticated searches of the database and the opportunity to link to additional databases.
I've written a finder specifically for the dataMine database, to replace the existing dmDB server.

@akbooer,  February 2016

--]]

local url     = require "socket.url"
local luup    = require "openLuup.luup"
local json    = require "openLuup.json"

local historian     = require "openLuup.historian"
local timers        = require "openLuup.timers"

local isGraphite, graphite_api  = pcall (require, "L_DataGraphiteAPI")  -- only present if DataYours there
local isFinders,  finders       = pcall (require, "L_DataFinders")


local storage   -- this will be the master storage finder
                -- federating Whisper and dataMine databases (and possibly others)

local _log      -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local LOCAL_DATA_DIR      -- location of Whisper database
local DATAMINE_DIR        -- location of DataMine database


--
-- TIME functions


--TODO: Graphite format times

local function relativeTime  (time, now)     -- Graphite Render URL syntax, relative to current or given time
  local number, unit = time: match "^%-(%d*)(%w+)"
  if number == '' then number = 1 end
  local duration = {s = 1, min = 60, h = 3600, d = 86400, w = 86400 * 7, mon = 86400 * 30, y = 86400 * 365}
  if not (unit and duration[unit]) then return end      -- must start with "-" and have a unit specifier
  now = now or os.time()
  return now - number * duration[unit] * 0.998    -- so that a week-long archive (for example) fits into now - week 
end

local function getTime (time)                        -- convert relative or ISO 8601 times as necessary
  if time then return relativeTime (time) or timers.util.ISOdate2epoch (time) end
end


-----------------------------------

local function jsonify(data, status, headers, jsonp)
  status = status or 200
  headers = headers or {}

  local body, errmsg = json.encode (data)
  body = body or json.encode {errors = {json = errmsg or "Unknown error"}} or 
          '{"errors":{"json": "Unknown error"}}'
  if jsonp then
      headers['Content-Type'] = 'text/javascript'
      body = ('%s(%s)'):format(jsonp, body)
  else
      headers['Content-Type'] = 'application/json'
  end
  return body, status, headers
end


-----------------------------------

--[[
The Metrics API

These API endpoints are useful for finding and listing metrics available in the system.
/metrics/find

Finds metrics under a given path. Other alias: /metrics.

Example:

GET /metrics/find?query=collectd.*

{"metrics": [{
    "is_leaf": 0,
    "name": "db01",
    "path": "collectd.db01."
}, {
    "is_leaf": 1,
    "name": "foo",
    "path": "collectd.foo"
}]}

GET /metrics/find/?format=treejson&query=stats.gauges.*

gives:

[{"leaf": 0, "context": {}, "text": "echo_server", 
     "expandable": 1, "id": "stats.gauges.echo_server", "allowChildren": 1},
 {"leaf": 0, "context": {}, "text": "vamsi", 
     "expandable": 1, "id": "stats.gauges.vamsi", "allowChildren": 1},
 {"leaf": 0, "context": {}, "text": "vamsi-server",
     "expandable": 1, "id": "stats.gauges.vamsi-server", "allowChildren": 1}
]

GET /metrics/find/?query=*
[{"text": "DEV", "expandable": 1, "leaf": 0, "id": "DEV", "allowChildren": 1},yadda...


Parameters:

query (mandatory)
    The query to search for.
format
    The output format to use. Can be completer (default) [AKB: docs are WRONG!] or treejson.
wildcards (0 or 1)
    Whether to add a wildcard result at the end or no. Default: 0.
from
    Epoch timestamp from which to consider metrics.
until
    Epoch timestamp until which to consider metrics.
jsonp (optional)
    Wraps the response in a JSONP callback.

/metrics/expand

Expands the given query with matching paths.

Parameters:

query (mandatory)
    The metrics query. Can be specified multiple times.
groupByExpr (0 or 1)
    Whether to return a flat list of results or group them by query. Default: 0.
leavesOnly (0 or 1)
    Whether to only return leaves or both branches and leaves. Default: 0
jsonp (optional)
    Wraps the response in a JSONP callback.

/metrics/index.json

Walks the metrics tree and returns every metric found as a sorted JSON array.

Parameters:

jsonp (optional)
    Wraps the response in a jsonp callback.

Example:

GET /metrics/index.json

[
    "collectd.host1.load.longterm",
    "collectd.host1.load.midterm",
    "collectd.host1.load.shortterm"
]


--]]

local function unknown (env)
  return "Not Implemented: " .. env.SCRIPT_NAME, 501
end

-- format: The output format to use. Can be completer or treejson [default]
  -- 2016.10.20 resolved doubt as to which IS the default!  Grafana needs treejson, it IS treejson

local function treejson (i)
  return {
    allowChildren = i.is_leaf and 0 or 1,
    expandable = i.is_leaf and 0 or 1,
    leaf = i.is_leaf and 1 or 0,
    id = i.path,
    text = i.name,
    context = {},   -- seems to be required, but don't know what it does!
    }
end

local function completer (i)
  return {
    is_leaf = i.is_leaf and 1 or 0,
    path = i.path .. (i.is_leaf and '' or '.'),
    name = i.name,
    }
end

local function metrics_find (_, p)
  local metrics, errors = {}, {}

  local query = p.query
  if not query then
      errors['query'] = 'this parameter is required.'
  end
  if next (errors) then
      return jsonify({errors = errors}, 400, nil, p.jsonp)
  end
  
  local formatter
  local format_options = {completer = completer, treejson = treejson}
  formatter = format_options[p.format or ''] or treejson  -- 2016.10.20  change default format
  
  for i in storage.find (query) do metrics[#metrics+1] = formatter (i) end
  
  if formatter == completer then metrics = {metrics = metrics} end    -- 2016.10.20
  return jsonify (metrics, 200,  nil, p.jsonp)
end

local function metrics_expand (_, p)
  local metrics, errors = {}, {}
  local leavesAndBranches = not (p.leavesOnly == "1")
  local query = p.query
  if not query then
      errors['query'] = 'this parameter is required.'
  end
  if next (errors) then
      return jsonify({errors = errors}, 400, nil, p.jsonp)
  end
  for i in storage.find (query) do
    if i.is_leaf or leavesAndBranches then
      local path = i.path
      metrics[#metrics+1] = path .. (i.is_leaf and '' or '.')
    end
  end
  return jsonify ({results = metrics}, 200, nil, p.jsonp)

end

local function metrics_index (_, p)
  local index = {}
  local search = '*'
  repeat
    local branch = false
    for i in storage.find (search) do
      if i.is_leaf then
        index[#index+1] = i.path
      else
        branch = true
      end
    end
    search = search .. ".*"
  until not branch
  table.sort (index)
  return jsonify (index, 200, nil, p.jsonp)
end

-----------------------------------

--[[

Graphing Metrics

To begin graphing specific metrics, pass one or more target parameters and specify a time window for the graph via from / until.
target

The target parameter specifies a path identifying one or several metrics, optionally with functions acting on those metrics.

--]]

-- rendering functions for non-graphics formats

local function csvRender (_, p)
  -- this is the csv format that the Graphite Render URL API uses:
  --
  -- entries,2011-07-28 01:53:28,1.0
  -- ...
  -- entries,2011-07-28 01:53:30,3.0
  --
  local data = {}
  for _,target in ipairs (p.target) do
    for node in storage.find (target) do 
      if node.is_leaf then
        local tv = node.fetch (p["from"], p["until"])  
        for i, v,t in tv:ipairs() do
          data[i] = ("%s,%s,%s"): format (node.path, os.date("%Y-%m-%d %H:%M:%S",t), tostring(v) )
        end
      end
    end
  end
  return table.concat (data, '\n'), 200, {["Content-Type"] = "text/plain"}
end


local function jsonRender (_, p)
  -- this is the json format that the Graphite Render URL API uses
  --[{
  --  "target": "entries",
  --  "datapoints": [
  --    [1.0, 1311836008],
  --    ...
  --    [6.0, 1311836012]
  --  ]
  --}]
  
  if ABOUT.DEBUG then _log ("RENDER: ", (json.encode(p))) end
  
  local data = {'[',''}
  for _,target in ipairs (p.target) do
    for node in storage.find (target) do
      if node.is_leaf then
        local tv = node.fetch (p["from"], p["until"])  
        data[#data+1] = '{'
        data[#data+1] = '  "target": "'.. node.path ..'",'
        data[#data+1] = '  "datapoints": ['
        for i, v,t in tv:ipairs() do
          data[#data+1] = table.concat {'  [', v or 'null', ', ', math.floor(t), ']', ','}
        end
        data[#data] = data[#data]: gsub(',$','')    -- 2018.06.05  remove final comma, if present
        data[#data+1] = '  ]'
        data[#data+1] = '}'
      end
      data[#data+1] = ','
    end
  end
  data[#data] = ']'   -- overwrite final comma
  return table.concat (data, '\n'), 200, {["Content-Type"] = "application/json"}
end

local function svgRender ()
  -- The empty response is just sufficient for Grafana to recognise that a 
  -- graphite_api server is available, thereafter it uses its own rendering.
  return "[]", 200, {["Content-Type"] = "application/json"}
end

-----------------------------------


local function render (env, p)

  local errors = {}           -- 2018.06.10 return error if no target for /render
  local target = p.target
  if not p.target then
      errors['query'] = 'this parameter is required.'
  end
  if next (errors) then
      return jsonify({errors = errors}, 400, nil, p.jsonp)
  end

  local now = os.time()
  p["from"]  = getTime (p["from"])  or now - 24*60*60  -- default to 24 hours ago
  p["until"] = getTime (p["until"]) or now
  
  local format = p.format or "svg"
  local reportStyle = {csv = csvRender, svg = svgRender, json = jsonRender}
  return (reportStyle[format] or svgRender) (env, p, storage)
end


-- dispatch table

  -- graphite_cgi support
local dispatch = {
  ["/metrics"]             = metrics_find,
  ["/metrics/find"]        = metrics_find,
  ["/metrics/expand"]      = metrics_expand,
  ["/metrics/index.json"]  = metrics_index,
  ["/render"]              = render,
}

--[[
Here is the general behavior of the API:

When parameters are missing or wrong, an HTTP 400 response is returned with the detailed errors in the response body.

Request parameters can be passed via:
    JSON data in the request body (application/json content-type).
    Form data in the request body (application/www-form-urlencoded content-type).
    Querystring parameters.

You can pass some parameters by querystring and others by json/form data if you want to. Parameters are looked up in the order above, meaning that if a parameter is present in both the form data and the querystring, only the one from the querystring is taken into account.

URLs are given without a trailing slash but adding a trailing slash is fine for all API calls.

Parameters are case-sensitive.

--]]


-- convert HTTP GET or POST content into query parameters
local function parse_parameters (query)
  local p = {}
  for n,v in (query or ''): gmatch "([%w_]+)=([^&]*)" do       -- parameters separated by unescaped "&"
    if v ~= '' then 
      local val = p[n] or {}
      val[#val+1] = url.unescape(v)                  -- now can unescape parameter values
      p[n] = val
    end
  end
  return p
end

local function get_parameters (env)
  
  local query = env.QUERY_STRING
  local p,p2
  
  p = parse_parameters (query)
  
  if env.REQUEST_METHOD == "POST" then 
    local content = env.input:read ()
 
    if env.CONTENT_TYPE: find ("www-form-urlencoded", 1, true) then   -- 2017.02.21, plain text search
      p2 = parse_parameters (content)
    
    elseif env.CONTENT_TYPE == "application/json" then
      p2 = json.decode (content)
    end
    
  end

  for name,value in pairs (p2 or {}) do
    p[name] = p[name] or value          -- don't override existing value
  end
  
  for name,value in pairs (p) do
    if #value == 1 then p[name] = value[1] end    -- convert single instances to scalar values
  end
  
  if type (p.target) ~= "table" then p.target= {p.target} end -- target is ALWAYS an array

  return p
end

-----------------------------------
--
-- global entry point called by WSAPI connector
--

function run (wsapi_env)
  
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax
  
  local p = get_parameters (wsapi_env)
  
  local script = wsapi_env.SCRIPT_NAME
  script = script: match "^(.-)/?$"      -- ignore trailing '/'
  
  local handler = dispatch[script] or unknown
  local ok, return_content, status, headers = pcall (handler, wsapi_env, p)  
  if not ok then
    status = 500
    headers = {}
  end
  
  local function iterator ()     -- one-shot iterator, returns content, then nil
    local x = return_content
    return_content = nil 
    return x
  end

  return status or 500, headers or {}, iterator
end


-----------------------------------

-- STARTUP


-- find LOCAL_DATA_DIR and DATAMINE_DIR in the DataYours device
local function find_whisper_database ()
  local dy = {
    type = "urn:akbooer-com:device:DataYours:1",
    sid  = "urn:akbooer-com:serviceId:DataYours1",
  }
  local LOCAL_DATA_DIR, DATAMINE_DIR
  for i,d in pairs (luup.devices) do
    if d.device_type == dy.type 
    and d.device_num_parent == 0 then  -- 2016.10.24
      LOCAL_DATA_DIR = luup.variable_get (dy.sid, "LOCAL_DATA_DIR", i)
      DATAMINE_DIR = luup.variable_get (dy.sid, "DATAMINE_DIR", i)
      break
    end
  end
  return LOCAL_DATA_DIR, DATAMINE_DIR
end


local function storage_find (ROOT, MINE)
    
  local config = {
    
    whisper = {
      directories = {ROOT},
    },
    
    datamine = {
      directories = {MINE} ,
      maxpoints = 2000,
      vera = "Vera-00000000",
    },
    
  }
  
  local Finders = {}
  Finders[#Finders + 1] = (ROOT ~= '') and finders.whisper.WhisperFinder   (config) or nil
  Finders[#Finders + 1] = (MINE ~= '') and finders.datamine.DataMineFinder (config) or nil
  Finders[#Finders + 1] = historian.finder (config)  -- 2018.06.02  Data Historian's own finder
  
  return graphite_api.storage.Store (Finders)
end


LOCAL_DATA_DIR, DATAMINE_DIR = find_whisper_database ()

storage = storage_find (LOCAL_DATA_DIR, DATAMINE_DIR)

-----
