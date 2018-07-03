#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

ABOUT = {
  NAME          = "graphite_cgi",
  VERSION       = "2018.07.03",
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
-- 2018.06.12  remove dependency on DataGraphiteAPI
-- 2018.06.23  add Historian.DataYours parameter to override DataYours finder
-- 2018.06.26  add Google Charts module for SVG rendering
-- 2018.07.03  add alias(), aliasByMetric(), aliasByNode() to /render?target=... syntax


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

local url       = require "socket.url"
local luup      = require "openLuup.luup"
local json      = require "openLuup.json"

local historian = require "openLuup.historian"
local timers    = require "openLuup.timers"

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
  if time then return relativeTime (time) or timers.util.ISOdate2epoch (time) end
end


-----------------------------------
--
-- GoogleCharts API
--

local function Gviz ()

  ----------
  --
  -- This Lua package is an API to a subset of the google.visualization javascript library.
  -- see: https://google-developers.appspot.com/chart/interactive/docs/index
  -- 

  -- 2016.07.01   Google Charts API changes broke old code!

  local version = "2016.07.01  @akbooer"

  local key
  local quote, equote, nowt = "'", '', 'null' 
  local old = "[\"'\\\b\f\n\r\t]"
  local new = { ['"']  = '\\"', ["'"]="\\'", ['\b']="\\b", ['\f']="\\f", ['\n']="\\n", ['\r']="\\r", ['\t']="\\t"}

--  local string_char = string.char

  local function null     ( ) return nowt end 
  local function user     (x) return x () end 
  local function boolean  (x) return tostring (x) end
  local function number   (x) return tostring (x) or nowt end
  local function string   (x, sep) 
    sep = sep or quote
    x = tostring(x)
    return table.concat {sep, x: gsub (old, new), sep} 
  end

  -- toJScr() convert Lua data structures to JavaScript
  local function toJScr (Lua)
    local lua_type    
    local function value (x) return lua_type [type (x)] (x) end
    local function array (x, X) for i = 1, #x do X[i] = value (x[i]) end; return '['..table.concat(X,',')..']' end
    local function object (x, X) for i,j in pairs (x) do X[#X+1] = string(i, equote)..':'..value (j) end; return '{'..table.concat(X,',')..'}'; end
    local function object_or_array (x) if #x > 0 then return array (x, {}) else return object (x, {}) end; end
    lua_type = {table = object_or_array, string = string, number = number, boolean = boolean, ["nil"] = null, ["function"] = user}  
    return value (Lua)
  end

  -- DataTable (), fundamental data type for charts
  local function DataTable ()
    local cols, rows = {}, {}

    local function formatDate    (x) return table.concat {"new Date (", x*1e3, ")"} end
    local function formatTime    (x) local t = os.date ("*t", x); return table.concat {"[", t.hour, ",", t.min, ",", t.sec, "]"} end

    local format = {boolean = boolean, string = string, number = number, 
            date = formatDate, datetime = formatDate, timeofday = formatTime}

    local function getNumberOfColumns () return #cols end
    local function getNumberOfRows () return #rows end
    local function addRow (row) rows[#rows+1] = row end -- should clone?
    local function addRows (rows) for _,row in ipairs (rows) do addRow (row) end; end
    local function addColumn (tableOrType, label, id) 
      local info = {}
      if type (tableOrType) ~= "table" 
        then info = {type = tableOrType, label = label, id = id}  -- make a table, or...
        else for i,j in pairs (tableOrType) do info[i] = j end    -- ...make a copy
      end
      if format[info.type] 
        then cols[#cols+1] = info 
        else error (("unsupported column type '%s' in DataTable"): format (info.type or '?'), 2) end
    end
    local function setValue (row, col, value) rows[row][col] = value end

    local function sort (col) -- unlike JavaScript, we start column number at 1 in Lua
      local desc = false
      local function ascending  (a,b) return a[col] < b[col] end  -- TODO: cope with tables (formats and properties)
      local function descending (a,b) return a[col] > b[col] end
      if type (col) == "table" then
        desc = col.desc or desc
        col = col.column
      end
      if desc 
        then table.sort (rows, descending)
        else table.sort (rows, ascending)
      end
    end
    
    
    local function toJavaScript (buffer)
      local b = buffer or {}
      local function p (x) b[#b+1] = x end
      local formatter = {}
      for i,col in ipairs (cols) do formatter[i] = format[col.type] end
      p "\n{cols: "; p (toJScr (cols))
      p ",\nrows: [\n"
      for n,row in ipairs (rows) do
        if n > 1 then p ',\n' end
        p "{c:["
        for i,f in ipairs (formatter) do 
          if i > 1 then p ',' end
          p '{v: '
          local v = row[i] or nowt
          if type(v) == "table" then
            p (f(v.v))
            p ', f: '
            p (string(v.f))
          elseif v == nowt then 
            p (nowt) 
          else
            p (f(v))
          end 
          p '}'
        end
        p "]}"
      end
      p "]\n}"
      if not buffer then return table.concat (b) end
    end

    return  {toJScr = toJavaScript, addColumn = addColumn, addRow = addRow, addRows = addRows,  
            getNumberOfColumns = getNumberOfColumns, getNumberOfRows = getNumberOfRows, 
            setValue = setValue, sort = sort}
  end

  -- JavaScript() concatentate string buffers and macros into valid script
  local function JavaScript(S)
    local b= {}
    for _, x in ipairs (S) do
       if type (x) == "function" then x(b) else b[#b+1] = x end
       b[#b+1] = '\n' 
    end
    return table.concat (b)
   end  

  -- ChartWrapper ()
  local function ChartWrapper (this)
    this = this or {}
    local function draw (extras)  
      extras = extras or ''
      local t = os.clock ()       
      local id   = this.containerId  or "gVizDiv"
      local opts = {options = this.options or {}, chartType = this.chartType, containerId = id}

      local html = JavaScript {[[
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>
    <script type="text/javascript" src="https://www.google.com/jsapi"></script>
    <script type="text/javascript">
      google.charts.load('current', {'packages':['corechart', 'table', 'treemap']});
      google.charts.setOnLoadCallback(gViz);
      function gViz() {
          var w = new google.visualization.ChartWrapper(]], toJScr (opts), [[);
          var data = new google.visualization.DataTable(]], this.dataTable.toJScr, [[);
          w.setDataTable(data);
          w.draw();]],
          extras, [[
        }
    </script>
  </head>
  <body><div id=]], toJScr(id), [[></div></body>
</html>
]]}
      t = (os.clock() - t) * 1e3
      if luup then luup.log (
        ("visualization: %s(%dx%d) %dkB in %dmS"): format (this.chartType,  
                this.dataTable.getNumberOfRows(), this.dataTable.getNumberOfColumns(), 
                math.floor(#html/1e3 + 0.5), math.floor(t+0.5) )) end
      return html
    end 

    return {
      draw = draw,
      setOptions    = function (x) this.options = x   end,
      setChartType  = function (x) this.chartType = x   end,
      setContainerId  = function (x) this.containerId = x end,
      setDataTable  = function (x) this.dataTable = x   end,
      }
  end

  -- Chart (), generic Chart object
  local function Chart (chartType)
    local this = ChartWrapper {chartType = chartType}
    local function draw (dataTable, options, extras, head, body)  
      this.setDataTable (dataTable)
      this.setOptions (options)
      return this.draw (extras, head, body)
    end 
    return {draw = draw}
  end

  -- Methods

  return {

    Version      = version,

    Chart        = Chart,
    DataTable    = DataTable,
    ChartWrapper = ChartWrapper,
    setKey       = function (x) key = x end,
    Table        = function () return Chart "Table"         end,
    Gauge        = function () return Chart "Gauge"         end,
    TreeMap      = function () return Chart "TreeMap"       end,
    BarChart     = function () return Chart "BarChart"      end,
    LineChart    = function () return Chart "LineChart"     end,
    ColumnChart  = function () return Chart "ColumnChart"   end,
    AreaChart    = function () return Chart "AreaChart"     end,
    PieChart     = function () return Chart "PieChart"      end,
    ScatterChart = function () return Chart "ScatterChart"  end,
    OrgChart     = function () return Chart "OrgChart"      end,
  }

end

local gviz = Gviz()   -- create an instance of the Google Charts API

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
/metrics/find?format=treejson&query=collectd.*

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

TODO: aliases...


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

aliasSub(seriesList, search, replace)

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
      arg: gsub ("[^%(%),]+", function (x) args[#args+1] = x end) -- pull out the arguments
      targetSpec = table.remove (args,1)   -- replace t with actual target spec
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
--  SVG render using Google Charts

-- plotting options - just a subset of the full Graphite Webapp set
-- see: http://graphite.readthedocs.org/en/latest/render_api.html
--
-- hideLegend:  [false] If set to true, the legend is not drawn. If set to false, the legend is drawn. 
-- areaMode:    none, all, [not done: first, stacked]
-- vtitle:      y-axis title
-- yMin/yMax:   y-axis upper limit
-- graphType:   line is default, but options includee: BarChart, ColumnChart, ... (not PieChart)
-- drawNullAs:  (a small deviation from the Graphite Web App syntax)
--   null:      keep them null
--   zero:      make them zero
--   hold:      hold on to previous value
--

local function svgRender (_, p)
  -- An empty response is just sufficient for Grafana to recognise that a 
  -- graphite_api server is available, thereafter it uses its own rendering.
  --  return "[]", 200, {["Content-Type"] = "application/json"}
  -- note: this svg format does not include Graphite's embedded metadata object
  
  local data = gviz.DataTable ()
  data.addColumn('datetime', 'Time');
  local m, n = 0, 0

  -- modes, etc...
  local mode, nulls, zero, hold, stair, slope, connect
  mode, nulls = "staircase", "hold"
  stair   = (mode == "staircase")
  slope   = (mode == "slope")
  connect = (mode == "connected")
  hold    = (nulls == "hold")
  zero    = (nulls == "zero") and 0
  _debug (table.concat {"drawing mode: ", mode, ", draw nulls as: ", nulls})
  
  -- fetch the data
  local row = {}   -- rows indexed by time
  for name, tv in target (p).next() do
    n = n + 1
    if n == 1 then     
      -- do first-time setup
    end
    data.addColumn('number', name);        
    local current, previous
    for _, v,t in tv:ipairs() do
      row[t] = row[t] or {t}                        -- create the row if it doesn't exist
      current = v or (hold and previous) or zero    -- special treatment for nil
      row[t][n+1] = current                         -- fill in the column
      previous = current
    end
  end
  
  -- sort the time axes  
  local index = {}
  for t in pairs(row) do index[#index+1] = t end    -- list all the time values
  table.sort(index)                                 -- sort them
  m = #index
  
  -- construct the data rows for plotting  
  local previous
  for _,t in ipairs(index) do
    if stair and previous then
      local extra = {}
      for a,b in pairs (previous) do extra[a] = b end   -- duplicate previous
      extra[1] = t                                      -- change the time
      data.addRow (extra)
    end
    data.addRow (row[t])
    previous = row[t]
  end
  
  -- add the options  
  local legend = "none"
  if not p.hideLegend then legend = 'bottom' end
  local title = p.title
  local opt = {
    title = title, 
    height = p.height or 500, 
    width = p.width, 
    legend = legend, 
    interpolateNulls = connect, 
    backgroundColor = p.bgcolor
  }  

  local clip, vtitle
  if p.yMax or p.yMin then clip = {max = p.yMax, min = p.yMin} end
  if p.vtitle then vtitle = p.vtitle: gsub ('+',' ') end
  opt.vAxis = {title = vtitle, viewWindow = clip }
--  opt.crosshair = {trigger="selection", orientation = "vertical"}       -- or trigger = "focus"

  local chartType = "LineChart"
  if p.areaMode and (p.areaMode ~= "none") then chartType = "AreaChart" end
  chartType = p.graphType or chartType    -- specified value overrides defaults
  local cpu = timers.cpu_clock ()
  local chart = gviz.Chart (chartType)
  local status = chart.draw (data, opt)
  cpu = timers.cpu_clock () - cpu
  local render = "render: CPU = %.3f mS for %dx%d=%d points"
  _debug (render: format (cpu*1e3, n, m, n*m))
  return status, 200, {["Content-Type"] = "text/html"}
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

  local function unknown (env)
    return "Not Implemented: " .. env.SCRIPT_NAME, 501
  end
  
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
    if (DATAMINE_DIR ~= '') then
      Finders[#Finders + 1] = finders.datamine.DataMineFinder (config)
    end
  end
  
  storage = Store (Finders)    --  instead of DataYours graphite_api.storage.Store()

-----
