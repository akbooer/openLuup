#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "graphite_cgi",
  VERSION       = "2019.08.12",
  DESCRIPTION   = "WSAPI CGI implementation of Graphite-API",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2019 AK Booer

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
-- 2018.06.12  remove dependency on DataGraphiteAPI
-- 2018.06.23  add Historian.DataYours parameter to override DataYours finder
-- 2018.06.26  add Google Charts module for SVG rendering
-- 2018.07.03  add alias(), aliasByMetric(), aliasByNode() to /render?target=... syntax

-- 2019.02.08  debug from/until times
-- 2019.03.22  abandon Google Charts in favour of simple SVG, that works offline
-- 2019.04.03  add "startup" as valid time option (for console historian plots)
-- 2019.04.07  add yMin, yMax, title, vtitle, options to SVG render
-- 2019.04.26  return "No Data" SVG when target parameter absent (default Graphite behaviour)
-- 2019.06.06  remove reference to external CSS
-- 2019.07.14  use new HTML and SVG constructors
-- 2019.08.12  use WSAPI request library to decode parameters


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


local luup      = require "openLuup.luup"
local json      = require "openLuup.json"
local historian = require "openLuup.historian"
local timers    = require "openLuup.timers"
local xml       = require "openLuup.xml"
local wsapi     = require "openLuup.wsapi"                -- for request and response libraries


local isFinders, finders = pcall (require, "L_DataFinders")  -- only present if DataYours there


local storage   -- this will be the master storage finder
                -- federating Whisper and dataMine databases (and possibly others)

local _log      -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

local function _debug (msg)
  if ABOUT.DEBUG then _log (msg) end
end

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
  if time == "startup" then return timers.loadtime end    -- 2019.04.03
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
--
-- The Metrics API
--
-- These API endpoints are useful for finding and listing metrics available in the system.
--

-- format: The output format to use. Can be completer or treejson [default]

--[[
/metrics/find/?format=treejson&query=stats.gauges.*

    [{"leaf": 0, "context": {}, "text": "echo_server", 
         "expandable": 1, "id": "stats.gauges.echo_server", "allowChildren": 1},
     {"leaf": 0, "context": {}, "text": "vamsi", 
         "expandable": 1, "id": "stats.gauges.vamsi", "allowChildren": 1},
     {"leaf": 0, "context": {}, "text": "vamsi-server",
         "expandable": 1, "id": "stats.gauges.vamsi-server", "allowChildren": 1}
    ]

--]]
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

--[[
/metrics/find?format=completer&query=collectd.*

    {"metrics": [{
        "is_leaf": 0,
        "name": "db01",
        "path": "collectd.db01."
    }, {
        "is_leaf": 1,
        "name": "foo",
        "path": "collectd.foo"
    }]}

--]]
local function completer (i)
  return {
    is_leaf = i.is_leaf and 1 or 0,
    path = i.path .. (i.is_leaf and '' or '.'),
    name = i.name,
    }
end

--[[
/metrics/find/?query=*    - Finds metrics under a given path.
/metrics?query=*          - Other alias.

Parameters:

  query (mandatory)     - The query to search for.
  format                - The output format. Can be completer or treejson (default).
  wildcards (0 or 1)    - Whether to add a wildcard result at the end or no. Default: 0.
  from                  - Epoch timestamp from which to consider metrics.
  until                 - Epoch timestamp until which to consider metrics.
  jsonp (optional)      - Wraps the response in a JSONP callback.

--]]
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

--[[
/metrics/expand   - Expands the given query with matching paths.

Parameters:

  query (mandatory)     - The metrics query. Can be specified multiple times.
  groupByExpr (0 or 1)  - Whether to return a flat list of results or group them by query. Default: 0.
  leavesOnly (0 or 1)   - Whether to only return leaves or both branches and leaves. Default: 0
  jsonp (optional)      -Wraps the response in a JSONP callback.

--]]
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

--[[
/metrics/index.json   - Walks the metrics tree and returns every metric found as a sorted JSON array.

Parameters:
  jsonp (optional)      - Wraps the response in a jsonp callback.

Example:
  GET /metrics/index.json

    [
        "collectd.host1.load.longterm",
        "collectd.host1.load.midterm",
        "collectd.host1.load.shortterm"
    ]
--]]
local function metrics_index_json (_, p)
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

--[[

Aliases...


alias(seriesList, newName)

    Takes one metric or a wildcard seriesList and a string in quotes. 
    Prints the string instead of the metric name in the legend.

    &target=alias(Sales.widgets.largeBlue,"Large Blue Widgets")

aliasByMetric(seriesList)

    Takes a seriesList and applies an alias derived from the base metric name.

    &target=aliasByMetric(carbon.agents.graphite.creates)

aliasByNode(seriesList, *nodes)

    Takes a seriesList and applies an alias derived from one or more “node” portion/s of the target name. 
    Node indices are 0 indexed.

    &target=aliasByNode(ganglia.*.cpu.load5,1)

TODO: aliasSub(seriesList, search, replace)

    Runs series names through a regex search/replace.

    &target=aliasSub(ip.*TCP*,"^.*TCP(\d+)","\1")

--]]


local function target (p)

  local function noalias (t) return t end
  
  local function alias (t, args) return ((args[1] or t): gsub ('"','')) end -- remove surrounding quotes

  local function aliasByMetric (t)
    return t: match "%.([^%.]+)$"
  end

  local function aliasByNode (t, args)
    local parts = {}
    local alias = {}
    t: gsub ("[^%.]+", function (x) parts[#parts+1] = x end)
    for i, part in ipairs (args) do alias[i] = parts[part+1] or '?'end
    return table.concat (alias, '.')
  end

  local aliasType = {alias = alias, aliasByMetric = aliasByMetric, aliasByNode = aliasByNode}
  
  -- separate possible function call from actual target spec
  local function parse (targetSpec)
    local fct,arg = targetSpec: match "(%w+)(%b())"
    local args = {}
    if fct then 
      -- Bad news:  some arguments contain commas, eg. {a,b}
      local arg2 = arg: gsub("%b{}", function (x) return (x: gsub(',','|')) end)  -- replace {a,b} with {a|b}
      arg2: gsub ("[^%(%),]+", function (x) args[#args+1] = x end) -- pull out the arguments
      targetSpec = table.remove (args,1)   -- replace t with actual target spec
      targetSpec = targetSpec: gsub ('|',',')   -- reinstate commas
    end
    local function nameof(x) return (aliasType[fct] or noalias) (x, args) end
    return targetSpec, nameof
  end
    
  local function nextTarget ()
    for _,targetSpec in ipairs (p.target) do
      local target, nameof = parse (targetSpec)
      for node in storage.find (target) do 
        if node.is_leaf then
          local tv = node.fetch (p["from"], p["until"])
          coroutine.yield (nameof(node.path), tv)
        end
      end
    end
  end
  
  return {next = function () return coroutine.wrap (nextTarget) end}

end


local function csvRender (_, p)
  -- this is the csv format that the Graphite Render URL API uses:
  --
  -- entries,2011-07-28 01:53:28,1.0
  -- ...
  -- entries,2011-07-28 01:53:30,3.0
  --
  local data = {}
  for name, tv in target (p).next() do
    for _, v,t in tv:ipairs() do
      data[#data+1] = ("%s,%s,%s"): format (name, os.date("%Y-%m-%d %H:%M:%S",t), tostring(v) )
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
  
  -- the data structure is not very complex, and it's far more efficient to generate this directly
  -- than first building a Lua table and then converting it to JSON.  So that's what this does.
  local data = {'[',''}
  for name, tv in target (p).next() do
    data[#data+1] = '{'
    data[#data+1] = '  "target": "'.. name ..'",'
    data[#data+1] = '  "datapoints": ['
    for _, v,t in tv:ipairs() do
      data[#data+1] = table.concat {'  [', v or 'null', ', ', math.floor(t), ']', ','}
    end
    data[#data] = data[#data]: gsub(',$','')    -- 2018.06.05  remove final comma, if present
    data[#data+1] = '  ]'
    data[#data+1] = '}'
    data[#data+1] = ','
  end
  data[#data] = ']'   -- overwrite final comma
  return table.concat (data, '\n'), 200, {["Content-Type"] = "application/json"}
end


-----------------------------------
--

local function makeYaxis(yMin, yMax, ticks)
--[[
  converted from PHP here: http://code.i-harness.com/en/q/4fc17
  
  // This routine creates the Y axis values for a graph.
  //
  // Calculate Min amd Max graphical labels and graph
  // increments.  The number of ticks defaults to
  // 10 which is the SUGGESTED value.  Any tick value
  // entered is used as a suggested value which is
  // adjusted to be a 'pretty' value.
  //
  // Output will be an array of the Y axis values that
  // encompass the Y values.
--]]

  ticks = ticks or 10
  ticks = math.max (2, ticks - 2)   -- Adjust ticks if needed

--  // If yMin and yMax are identical, then
--  // adjust the yMin and yMax values to actually
--  // make a graph. Also avoids division by zero errors.
  if(yMin == yMax) then
    yMin = yMin - 10;   -- some small value
    yMax = yMax + 10;   --some small value
  end
  
  local range = yMax - yMin    -- Determine Range
  local tempStep = range/ticks    -- Get raw step value

--  // Calculate pretty step value
  local mag = math.floor(math.log10(tempStep));
  local magPow = math.pow(10,mag);
  local magMsd = math.floor(tempStep/magPow + 0.5);
  local stepSize = magMsd*magPow;

--  // build Y label array.
--  // Lower and upper bounds calculations
  local lb = stepSize * math.floor(yMin/stepSize);
  local ub = stepSize * math.ceil((yMax/stepSize));
--  // Build array
  local result = {}
  for val = lb, ub, stepSize do
    result[#result+1] = val;
  end
  return result;
end


-----------------------------------
--
--  SVG render

-- plotting options - just a subset of the full Graphite Webapp set
-- see: http://graphite.readthedocs.org/en/latest/render_api.html
--
-- title:       plot title
-- height/width plot size
-- vtitle:      y-axis title
-- yMin/yMax:   y-axis lower/upper limit
-- bgcolor:     background colour
-- areaAlpha:   opacity of area fill
-- &colorList=green,yellow,orange,red,purple,#DECAFF
--]]


local function svgRender (_, p)
  --  return "[]", 200, {["Content-Type"] = "application/json"}
  -- An empty response is just sufficient for Grafana to recognise that a 
  -- graphite_api server is available, thereafter it uses its own rendering.
  -- but we can do better with a simple SVG plot.
  -- note: this svg format does not include Graphite's embedded metadata object
  local Xscale, Yscale = 10000, 1000    -- SVG viewport scale
  
  -- scale tv structure given array 0-1 to min/max of series
  local function scale (tv)
    local V, T = {}, {}
    local vmin, vmax
    local fmin, fmax = math.min, math.max
    
    for _,v,t in tv:ipairs() do
      if v then
        T[#T+1] = t
        V[#V+1] = v
        vmax = fmax (vmax or v, v)
        vmin = fmin (vmin or v, v)
      end
    end
    
    if #T < 2 then return end
    vmax = math.ceil (p.yMax or vmax)
    vmin = math.floor (p.yMin or vmin)
    
    local v = makeYaxis(vmin, vmax, 5)
    if vmin < v[1]  then table.insert (v, 1, vmin) end
    if vmax > v[#v] then table.insert (v, vmax) end
    V.ticks, vmin, vmax = v, v[1], v[#v]
    
    local tmin, tmax = T[1], T[#T]      -- times are sorted, so we know where to find min and max
    if tmin == tmax then tmax = tmax + 1 end
    if vmin == vmax then vmax = vmax + 1 end
    
    T.scale = Xscale / (tmax - tmin)
    V.scale = Yscale / (vmax - vmin)
     
    T.min, T.max = tmin, tmax
    V.min, V.max = vmin, vmax
    return T, V
  end
    
  -- fetch the data
  
  local svgs = {}   -- separate SVGs for multiple plots
  
  local function timeformat (epoch)
    local t = os.date ("%d %b '%y, %X", epoch):gsub ("^0", '')
    return t
  end
  
  -- get the convenience factory methods for HTML and SVG
  local h = xml.createHTMLDocument "Graphics"
  local s = xml.createSVGDocument {}

  local function new_plot ()
    return s.svg {
        height = p.height or "300px", 
        width = p.width or "90%",
        viewBox = table.concat ({0, -Yscale/10, Xscale, 1.1 * Yscale}, ' '),
        preserveAspectRatio = "none",
        style ="border: none; margin-left: 5%; margin-right: 5%;",
      }
  end
  
  local function no_data (svg)
    svg:appendChild (s.text (2000, Yscale/2, {"No Data",     -- TODO: move to external style sheet?
          style = "font-size:180pt; fill:Crimson; font-family:Arial; transform:scale(2,1)"} ) )   
  end
  
  for name, tv in target (p).next() do
    
    local T, V = scale (tv)
    local svg = new_plot ()
    if not T then
      no_data (svg)   
    else
      -- construct the data rows for plotting  
      local d = {}    -- i.e. s.createDocumentFragment ()
         
      local floor = math.floor
      
      local Tscale, Vscale = T.scale, V.scale
      local Tmin, Vmin = T.min, V.min
      local T1, V1 = T[1], V[1]
      local T1_label = timeformat (T1)
      local t1, v1 = floor ((T1-Tmin) * Tscale), floor((V1-Vmin) * Vscale)
      for i = 2,#T do
        local T2, V2 = T[i], V[i]
        local t2, v2 = floor ((T2-Tmin) * Tscale), floor((V2-Vmin) * Vscale)
        local T2_label = timeformat (T2)
        local V3 = V1 + 5e-4
        local popup = s.title {T1_label, ' - ', T2_label, '\n', name, ": ", (V3 - V3 % 0.001)}
        d[#d+1] = s.rect (t1, Yscale-v1, t2-t1, v1, {class="bar", popup})
                          t1, v1, T1, V1, T1_label = t2, v2, T2, V2, T2_label
      end
      
      -- add the axes
      for _,y in ipairs (V.ticks) do
        -- need to scale
        local v = Yscale - floor((y-Vmin) * Vscale)
        d[#d+1] = s.line (0, v, Xscale, v, {style = "stroke:Grey; stroke-width:2"})
        d[#d+1] = s.text (0, v, {dy="-0.2em", style = "font-size:48pt; fill:Grey; font-family:Arial; transform:scale(2,1)", y})
      end
      local left  = h.span {style="float:left",  timeformat (T.min)}
      local right = h.span {style="float:right", timeformat (T.max)}
      local hscale = h.p {style="margin-left: 5%; margin-right: 5%; color:Grey; font-family:Arial; ", 
                  left, right, h.br ()}
      svg:appendChild (d)
      svg = h.div {p.vtitle or '', svg, h.br(), hscale}
    end
    
    svgs[#svgs+1] = h.div {h.h4 {p.title or name, style="font-family: Arial;"}, svg}
  end
  
  if #svgs == 0 then          -- 2019.04.26
    local svg = new_plot ()
    no_data (svg)
    svgs[1] = svg
  end
  
-- add the options    
  local cpu = timers.cpu_clock ()
  
  h.documentElement[1]:appendChild {    -- append to <HEAD>
        h.meta {charset="utf-8"},
        h.style {[[
    .bar {cursor: crosshair; }
    .bar:hover, .bar:focus {fill: DarkGray; }
    rect {fill:Grey; stroke-width:3px; stroke:Grey; }
  ]]}}

  h.body:appendChild (svgs)

  local doc = tostring (h)
  
  cpu = timers.cpu_clock () - cpu

  local render = "render: CPU = %.3f ms"
  _debug (render: format (cpu*1e3))
  return doc, 200, {["Content-Type"] = "text/html"}
end

-----------------------------------


local function render (env, p)

  local errors = {}           -- 2018.06.10 return error if no target for /render
  if not p.target then
      errors['query'] = 'this parameter is required.'
  end
  if next (errors) then
      return jsonify({errors = errors}, 400, nil, p.jsonp)
  end

  local now = os.time()
  local pfrom  = p["from"]
  local puntil =  p["until"]
  p["from"]  = getTime (pfrom)  or now - 24*60*60  -- default to 24 hours ago
  p["until"] = getTime (puntil) or now
  
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
  ["/metrics/index.json"]  = metrics_index_json,
  ["/render"]              = render,
}

--[[
Here is the general behavior of the API:

When parameters are missing or wrong, an HTTP 400 response is returned with the detailed errors in the response body.

Request parameters can be passed via:
    JSON data in the request body (application/json content-type).
    Form data in the request body (application/www-form-urlencoded content-type).
    Querystring parameters.

You can pass some parameters by querystring and others by json/form data if you want to. 
Parameters are looked up in the order above, meaning that if a parameter is present in both the form data and the querystring, 
only the one from the querystring is taken into account.

URLs are given without a trailing slash but adding a trailing slash is fine for all API calls.

Parameters are case-sensitive.

--]]

-----------------------------------
--
-- global entry point called by WSAPI connector
--

function run (wsapi_env)
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax
  local req = wsapi.request.new (wsapi_env)
  local p = req.GET
  local p2 = req.POST
  
  if wsapi_env.CONTENT_TYPE == "application/json" then
    local content = wsapi_env.input:read ()
    p2 = json.decode (content)    
  end

  for name,value in pairs (p2 or {}) do p[name] = p[name] or value end    -- don't override existing value  
  if type (p.target) ~= "table" then p.target= {p.target} end             -- target is ALWAYS an array
  
  local script = wsapi_env.SCRIPT_NAME
  script = script: match "^(.-)/?$"      -- ignore trailing '/'
  
  local handler = dispatch[script] or function () return "Not Implemented: " .. script, 501 end

  local _, response, status, headers = pcall (handler, wsapi_env, p)  
  
  return status or 500, headers or {}, function () local x = response; response = nil; return x end
end


-----------------------------------
--
-- STARTUP
--

  -- Store()
  -- low-functionality version of Graphite API Store module
  -- assumes no identical paths from any of the finders (they all have their own branches) 
  local function Store (finders)
    local function find (pattern)
      for _,finder in ipairs (finders) do
        for node in finder.find_nodes {pattern = pattern} do    -- minimal FindQuery structure
          coroutine.yield (node)
        end
      end
    end
    -- Store()
    return {find =     -- find is an iterator which yields nodes
        function(x) 
          return coroutine.wrap (function() find(x) end)
        end
      }
  end


  -- find LOCAL_DATA_DIR and DATAMINE_DIR in the DataYours device
  local LOCAL_DATA_DIR, DATAMINE_DIR
  local dy = {
    type = "urn:akbooer-com:device:DataYours:1",
    sid  = "urn:akbooer-com:serviceId:DataYours1",
  }
  for i,d in pairs (luup.devices) do
    if d.device_type == dy.type 
    and d.device_num_parent == 0 then  -- 2016.10.24
      LOCAL_DATA_DIR = luup.variable_get (dy.sid, "LOCAL_DATA_DIR", i)
      DATAMINE_DIR = luup.variable_get (dy.sid, "DATAMINE_DIR", i)
      break
    end
  end

  -- get historian config
  local history = luup.attr_get "openLuup.Historian" or {}

  -- create a configuration for the various finders  
  local config = {
    whisper = {
      directories = {LOCAL_DATA_DIR},
    },
    datamine = {
      directories = {DATAMINE_DIR} ,
      maxpoints = 2000,
      vera = "Vera-00000000",
    },
    historian = history,
  }
  
  local Finders = {historian.finder (config) }     -- 2018.06.02  Data Historian's own finder

  if isFinders then   -- if DataYours is installed, then add its finders if not already handled
    if not history.DataYours and (LOCAL_DATA_DIR ~= '') then
      Finders[#Finders + 1] = finders.whisper.WhisperFinder (config)
    end
    if not history.DataMine and (DATAMINE_DIR ~= '') then
      Finders[#Finders + 1] = finders.datamine.DataMineFinder (config)
    end
  end
  
  storage = Store (Finders)    --  instead of DataYours graphite_api.storage.Store()

-----
