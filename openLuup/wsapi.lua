local ABOUT = {
  NAME          = "openLuup.wsapi",
  VERSION       = "2023.02.10",
  DESCRIPTION   = "a WSAPI application connector for the openLuup port 3480 server",
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
  
  -----
  
This module also contains the WSAPI request and response libraries from the Kepler project
see: https://keplerproject.github.io/wsapi/libraries.html

Copyright © 2007-2014 Kepler Project.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

]]
}

-- This module implements a WSAPI (Web Server API) application connector for the openLuup port 3480 server.
--
-- see: http://keplerproject.github.io/wsapi/
-- and: http://keplerproject.github.io/wsapi/license.html
-- and: https://github.com/keplerproject/wsapi
-- and: http://keplerproject.github.io/wsapi/manual.html

-- The use of WSAPI concepts for handling openLuup CGI requests was itself inspired by @vosmont,
-- see: http://forum.micasaverde.com/index.php/topic,36189.0.html
-- 2016.02.18

-- 2016.02.26  add self parameter to input.read(), seems to be called from wsapi.request with colon syntax
--             ...also util.lua shows that the same is true for the error.write(...) function.
-- 2016.05.30  look in specified places for some missing CGI files 
-- 2016.07.05  use "require" for WSAPI files with a .lua extension (enables easy debugging)
-- 2016.07.06  add 'method' to WSAPI server call for REQUEST_METHOD metavariable
-- 2016.07.14  change cgi() parameter to request object
-- 2016.07.15  three-parameters WSAPI return: status, headers, iterator
-- 2016.10.17  use CGI aliases from external servertables module

-- 2017.01.12  remove leading colon from REMOTE_PORT metavariable value

-- 2018.07.14  improve error handling when calling CGI
-- 2018.07.20  add the Kepler project request and response libraries
-- 2018.07.27  export the util module with url_encode() and url_decode()

-- 2019.05.06  improve CGI .lua log message
-- 2019.07.17  include complete WSAPI util module rather than socket.url (to decode '+' signs correctly)
-- 2019.07.28  create global make_env(), used by HTTP server to include in request objects

-- 2023.02.10  @akbooer added SameSite cookie attribute

--[[

Writing WSAPI connectors

A WSAPI connector builds the environment from information passed by the web server and calls a WSAPI application,
sending the response back to the web server. The first thing a connector needs is a way to specify which application to run,
and this is highly connector specific. Most connectors receive the application entry point as a parameter 
(but WSAPI provides special applications called generic launchers as a convenience).

The environment is a Lua table containing the CGI metavariables (at minimum the RFC3875 ones) plus any server-specific 
metainformation. It also contains an input field, a stream for the request's data, and an error field, a stream for the 
server's error log. The input field answers to the read([n]) method, where n is the number of bytes you want to read 
(or nil if you want the whole input). The error field answers to the write(...) method.

The environment should return the empty string instead of nil for undefined metavariables, and the PATH_INFO variable should
return "/" even if the path is empty. Behavior among the connectors should be uniform: SCRIPT_NAME should hold the URI up
to the part where you identify which application you are serving, if applicable (again, this is highly connector specific),
while PATH_INFO should hold the rest of the URL.

After building the environment the connector calls the application passing the environment to it, and collecting three
return values: the HTTP status code, a table with headers, and the output iterator. The connector sends the status and 
headers right away to the server, as WSAPI does not guarantee any buffering itself. After that it begins calling the
iterator and sending output to the server until it returns nil.

The connectors are careful to treat errors gracefully: if they occur before sending the status and headers they return an 
"Error 500" page instead, if they occur while iterating over the response they append the error message to the response.

--]]

local loader  = require "openLuup.loader"       -- to create new environment in which to execute CGI script 
local logs    = require "openLuup.logs"         -- used for wsapi_env.error:write()
local tables  = require "openLuup.servertables" -- used for CGI aliases

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control

-- utilities

local cache = {}       -- cache for compiled CGIs

-- return a dummy WSAPI app with error code and message
local function dummy_app (status, message)
  local function iterator ()     -- one-shot iterator, returns message, then nil
    local x = message
    message = nil 
    return x
  end
  local function run ()   -- dummy app entry point
    return 
        status, 
        { ["Content-Type"] = "text/plain" },
        iterator
  end
  _log (message)
  return run    -- return the entry point
end

-- build makes an application function for the connector
local function build (script)
  local file = script
  -- CGI aliases: any matching full CGI path is redirected
  local alternative = tables.cgi_alias[file]     -- 2016.05.30 and 2016.10.17
  if alternative then
    _log (table.concat {"using ", alternative, " for ", file})
    file = alternative
  end
  
  local f = io.open (file) 
  if not f then 
    return dummy_app (404, "file not found: " .. (file or '?')) 
  end
  local line = f: read "*l"
  
  -- looking for first line of "#!/usr/bin/env wsapi.cgi" for WSAPI application
  local code
  if not line:match "^%s*#!/usr/bin/env%s+wsapi.cgi%s*$" then 
    return dummy_app (501, "file is not a WSAPI application: " .. (script or '?')) 
  end
  
  -- if it has a .lua extension, then we can use 'require' and this means that
  -- it can be easily debugged because the file is recognised by the IDE
  
  local lua_env
  local lua_file = file: match "(.*)%.lua$"
  if lua_file then
    _log ("using REQUIRE to load CGI " .. file)
    f: close ()                               -- don't need it open
    lua_file = lua_file: gsub ('/','.')       -- replace path separators with periods, for require path
    lua_env = require (lua_file)
    if type(lua_env) ~= "table" then
      _log ("error - require failed: " .. lua_file)
      lua_env = nil
    end
    
  else
    -- do it the hard way...
    code = f:read "*a"
    f: close ()
      
    -- compile and load
    local a, error_msg = loadstring (code, script)    -- load it
    if not a or error_msg then
      return dummy_app (500, error_msg)               -- 'internal server error'
    end
    lua_env = loader.new_environment (script)         -- use new environment
    setfenv (a, lua_env)                              -- Lua 5.1 specific function environment handling
    a, error_msg = pcall(a)                           -- instantiate it
    if not a then
      return dummy_app (500, error_msg)               -- 'internal server error'
    end
  end
  
  -- find application entry point
  local runner = (lua_env or {}).run
  if (not runner) or (type (runner) ~= "function") then
    return dummy_app (500, "can't find WSAPI application entry point")         -- 'internal server error'
  end

  return runner   -- success! return the entry point to the WSAPI application
end


--[[
  see: http://www.ietf.org/rfc/rfc3875

  meta-variable-name = "AUTH_TYPE" | "CONTENT_LENGTH" |
                       "CONTENT_TYPE" | "GATEWAY_INTERFACE" |
                       "PATH_INFO" | "PATH_TRANSLATED" |
                       "QUERY_STRING" | "REMOTE_ADDR" |
                       "REMOTE_HOST" | "REMOTE_IDENT" |
                       "REMOTE_USER" | "REQUEST_METHOD" |
                       "SCRIPT_NAME" | "SERVER_NAME" |
                       "SERVER_PORT" | "SERVER_PROTOCOL" |
                       "SERVER_SOFTWARE" | scheme |
                       protocol-var-name | extension-var-name

also: http://www.cgi101.com/book/ch3/text.html

DOCUMENT_ROOT 	The root directory of your server
HTTP_COOKIE 	  The visitor's cookie, if one is set
HTTP_HOST 	    The hostname of the page being attempted
HTTP_REFERER 	  The URL of the page that called your program
HTTP_USER_AGENT The browser type of the visitor
HTTPS 	        "on" if the program is being called through a secure server
PATH 	          The system path your server is running under
QUERY_STRING 	  The query string (see GET, below)
REMOTE_ADDR 	  The IP address of the visitor
REMOTE_HOST 	  The hostname of the visitor (if your server has reverse-name-lookups on; else this is the IP address again)
REMOTE_PORT 	  The port the visitor is connected to on the web server
REMOTE_USER 	  The visitor's username (for .htaccess-protected pages)
REQUEST_METHOD 	GET or POST
REQUEST_URI 	  The interpreted pathname of the requested document or CGI (relative to the document root)
SCRIPT_FILENAME The full pathname of the current CGI
SCRIPT_NAME 	  The interpreted pathname of the current CGI (relative to the document root)
SERVER_ADMIN 	  The email address for your server's webmaster
SERVER_NAME 	  Your server's fully qualified domain name (e.g. www.cgi101.com)
SERVER_PORT 	  The port number your server is listening on
SERVER_SOFTWARE The server software you're using (e.g. Apache 1.3)

--]]

-- build a WSAPI environment from parameters:
--      url.path, url.query , {headers}, post_content_string, method_string, http_version_string 
-- only the first parameter is required
local function make_env (path, query, headers, post_content, method, http_version)
  headers = headers or {}
  post_content = post_content or ''
  
  local meta = {
    __index = function () return '' end;  -- return the empty string instead of nil for undefined metavariables
  }
  
  local ptr = 1
  local input = {
    read =  
      function (self, n) 
        n = tonumber (n) or #post_content
        local start, finish = ptr, ptr + n - 1
        ptr = ptr + n
        return post_content:sub (start, finish)
      end
  }
  
  local error = {
    write = function (self, ...) 
      local msg = {path or '?', ':', ...}
      for i, m in ipairs(msg) do msg[i] = tostring(m) end             -- ensure everything is a string
      _log (table.concat (msg, ' '), "openLuup.wsapi.cgi") 
    end;
  }
  
  local env = {   -- the WSAPI standard (and CGI) is upper case for these metavariables
    
    TEST = {headers = headers},     -- so that test CGIs (or unit tests) can examine all the headers
    
    -- note that the metatable will return an empty string for any undefined environment parameters
    ["CONTENT_LENGTH"]  = #post_content,
    ["CONTENT_TYPE"]    = headers["Content-Type"],
    ["HTTP_USER_AGENT"] = headers["User-Agent"],
    ["HTTP_COOKIE"]     = headers["Cookie"],
    ["REMOTE_HOST"]     = headers ["Host"],
    ["REMOTE_PORT"]     = (headers ["Host"] or ''): match ":(%d+)$",
    ["REQUEST_METHOD"]  = method or "GET",
    ["SCRIPT_NAME"]     = path,
    ["SERVER_PROTOCOL"] = http_version or "HTTP/1.1",
    ["PATH_INFO"]       = '/',
    ["QUERY_STRING"]    = query,
  
    -- methods
    input = input,
    error = error,
  }
  
  return setmetatable (env, meta)
end

-- cgi is called by the server when it receives a GET or POST CGI request
local function cgi (wsapi_env)       -- 2019.07.28  now called with a pre-built environment!
  local script = wsapi_env.SCRIPT_NAME  
  
  script = script: match "^/?(.-)/?$"      -- ignore leading and trailing '/'
  
  cache[script] = cache[script] or build (script) 
  
  -- guaranteed to be something executable here, even if it's a dummy with error message
  -- three return values: the HTTP status code, a table with headers, and the output iterator.
  
  -- catch any error during CGI execution
  -- it's essential to return from here with SOME kind of HTML page,
  -- so the usual error catch-all in the scheduler context switching is not sufficient.
  -- Errors during response iteration are caught by the HTTP servlet. 

  local ok, status, responseHeaders, iterator = pcall (cache[script], wsapi_env)
  
  if not ok then
    local message = status
    _log ("ERROR: " .. message)
    status = 500    -- Internal server error
    responseHeaders = { ["Content-Type"] = "text/plain" }
    iterator = function () local x = message; message = nil; return x end
  end

  return status, responseHeaders, iterator
end


------------------------------------------------------
--
-- The original WSAPI has a number of additional libraries
-- see: https://keplerproject.github.io/wsapi/libraries.html
-- here, the request, response, and util libraries are included.
-- use in a CGI file like this:
--    local wsapi = require "openLuup.wsapi" 
--    local req = wsapi.request.new(wsapi_env)
--    local res = wsapi.response.new([status, headers])


------------------------------------------------------

--
-- utility library, this is the verbatim keplerproject code 
-- see: https://github.com/keplerproject/wsapi/blob/master/src/wsapi/util.lua
--
--[[

wsapi.util.url_encode(s) - encodes s according to RFC2396

wsapi.util.url_decode(s) - decodes s according to RFC2396

wsapi.util.sanitize(text) - sanitizes all HTML tags in text, replacing < and > with the corresponding entity codes

wsapi.util.not_empty(s) - returns true if s is not nil or the empty string

wsapi.util.getopt(arg, options) - POSIX style command line argument parser, arg contains the command line arguments in a standard table, options is a string with the letters that expect string values. Returns a table with the options that have been passed and their values

wsapi.util.make_env_get(qs) - makes a mock WSAPI environment with GET method and qs as the query string

wsapi.util.make_env_post(pd, type, qs) - makes a mock WSAPI environment with POST method and pd as the postdata, type as the encoding (x-www-form-urlenconded default), and qs as the query string

wsapi.util.make_rewindable(wsapi_env) - wraps wsapi_env in a new environment that lets you process the POST data more than once. This new environment's input object has a rewind method that you can call to allow you to read the POST data again.

--]]

local function _M_util ()
  
  local _M = {}

  ----------------------------------------------------------------------------
  -- Decode an URL-encoded string (see RFC 2396)
  ----------------------------------------------------------------------------
  function _M.url_decode(str)
    if not str then return nil end
    str = string.gsub (str, "+", " ")
    str = string.gsub (str, "%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
    str = string.gsub (str, "\r\n", "\n")
    return str
  end

  ----------------------------------------------------------------------------
  -- URL-encode a string (see RFC 2396)
  ----------------------------------------------------------------------------
  function _M.url_encode(str)
    if not str then return nil end
    str = string.gsub (str, "\n", "\r\n")
    str = string.gsub (str, "([^%w ])",
          function (c) return string.format ("%%%02X", string.byte(c)) end)
    str = string.gsub (str, " ", "+")
    return str
  end

  ----------------------------------------------------------------------------
  -- Sanitizes all HTML tags
  ----------------------------------------------------------------------------
  function _M.sanitize(text)
     return text:gsub(">", "&gt;"):gsub("<", "&lt;")
  end

  ----------------------------------------------------------------------------
  -- Checks whether s is not nil or the empty string
  ----------------------------------------------------------------------------
  function _M.not_empty(s)
    if s and s ~= "" then return s else return nil end
  end

  ----------------------------------------------------------------------------
  -- Wraps the WSAPI environment to make the input rewindable, so you
  -- can parse postdata more than once, call wsapi_env.input:rewind()
  ----------------------------------------------------------------------------
  function _M.make_rewindable(wsapi_env)
     local new_env = { input = { position = 1, contents = "" } }
     function new_env.input:read(size)
        local left = #self.contents - self.position + 1
        local s
        if left < size then
           self.contents = self.contents .. wsapi_env.input:read(size - left)
           s = self.contents:sub(self.position)
           self.position = #self.contents + 1
        else
           s = self.contents:sub(self.position, self.position + size)
           self.position = self.position + size
        end
        if s == "" then return nil else return s end
     end
     function new_env.input:rewind()
        self.position = 1
     end
     return setmetatable(new_env, { __index = wsapi_env, __newindex = wsapi_env })
  end

  ----------------------------------------------------------------------------
  -- getopt, POSIX style command line argument parser
  -- param arg contains the command line arguments in a standard table.
  -- param options is a string with the letters that expect string values.
  -- returns a table where associated keys are true, nil, or a string value.
  -- The following example styles are supported
  --   -a one  ==> opts["a"]=="one"
  --   -bone   ==> opts["b"]=="one"
  --   -c      ==> opts["c"]==true
  --   --c=one ==> opts["c"]=="one"
  --   -cdaone ==> opts["c"]==true opts["d"]==true opts["a"]=="one"
  -- note POSIX demands the parser ends at the first non option
  --      this behavior isn't implemented.
  ----------------------------------------------------------------------------
  function _M.getopt( arg, options )
    local tab, args = {}, {}
    local k = 1
    while k <= #arg do
      local v = arg[k]
      if string.sub( v, 1, 2) == "--" then
        local x = string.find( v, "=", 1, true )
        if x then tab[ string.sub( v, 3, x-1 ) ] = string.sub( v, x+1 )
        else      tab[ string.sub( v, 3 ) ] = true
        end
        k = k + 1
      elseif string.sub( v, 1, 1 ) == "-" then
        local y = 2
        local l = #v
        local jopt
        local next = 1
        while ( y <= l ) do
          jopt = string.sub( v, y, y )
          if string.find( options, jopt, 1, true ) then
            if y < l then
              tab[ jopt ] = string.sub( v, y+1 )
              y = l
            else
              tab[ jopt ] = arg[ k + 1 ]
              next = 2
            end
          else
            tab[ jopt ] = true
          end
          y = y + 1
        end
        k = k + next
      else
        args[#args + 1] = v
        k = k + 1
      end
    end
    return tab, args
  end

  ----------------------------------------------------------------------------
  -- Makes a mock WSAPI environment with GET method and the provided
  -- query string
  ----------------------------------------------------------------------------
  function _M.make_env_get(qs)
    return {
      REQUEST_METHOD = "GET",
      QUERY_STRING = qs or "",
      CONTENT_LENGTH = 0,
      PATH_INFO = "/",
      SCRIPT_NAME = "",
      CONTENT_TYPE = "x-www-form-urlencoded",
      input = {
        read = function () return nil end
      },
      error = {
        messages = {},
        write = function (self, msg)
          self.messages[#self.messages+1] = msg
        end
      }
    }
  end

  ----------------------------------------------------------------------------
  -- Makes a mock WSAPI environment with POST method and the provided
  -- postdata, type (x-www-form-urlenconded default) and query string
  ----------------------------------------------------------------------------
  function _M.make_env_post(pd, type, qs)
    pd = pd or ""
    return {
      REQUEST_METHOD = "POST",
      QUERY_STRING = qs or "",
      CONTENT_LENGTH = #pd,
      PATH_INFO = "/",
      CONTENT_TYPE = type or "x-www-form-urlencoded",
      SCRIPT_NAME = "",
      input = {
        post_data = pd,
        current = 1,
        read = function (self, len)
          if self.current > #self.post_data then return nil end
          local s = self.post_data:sub(self.current, len)
          self.current = self.current + len
          return s
        end
      },
      error = {
        messages = {},
        write = function (self, msg)
          self.messages[#self.messages+1] = msg
        end
      }
    }
  end

  function _M.loadfile(filename, env)
    if _VERSION ~= "Lua 5.1" then
      return loadfile(filename, "bt", env)
    else
      local f, err = loadfile(filename)
      if not f then
        return nil, err
      end
      setfenv(f, env)
      return f
    end
  end

  return _M

end

local util = _M_util ()  -- create version for the following to access

----------
--
-- request library, this is the verbatim keplerproject code 
-- see: https://github.com/keplerproject/wsapi/blob/master/src/wsapi/request.lua
--
--[[

wsapi.request.new(wsapi_env, [options]) - creates a new request object wrapping wsapi_env; options is an (optional) table of extra options for the request; the delay_post option tells wsapi.request to not process POST data on creation, the overwrite option tells WSAPI to overwrite input parameters with the same name instead of collecting them in a list, and the mk_app option passes the mk application that created the request object, used in some of the methods

req:parse_post() - processed the POST data in case the processing was delayed by passing delay_post = true on creation of the request

req:qd_encode(tab) - encodes tab as a query string

req:route_link(route, tab, ...) - creates a link to mk route route, encoding tab as the query string and passing extra arguments to the link builder of the route

req:link_<route>(tab, ...) - same as req:route_link(route, tab, ...)

req:link(uri, tab) - makes an internal application link to the specified resource uri, with tab encoded as a query string. For example, if the app is addressed by /foo/bar.lua then req:link("/baz", { id = 2 }) returns "/foo/bar.lua/baz?id=2"

req:static_link(uri, tab) - as req:link, but builds a link external to the application. In the previous example it would return "/foo/baz?id=2"

req:absolute_link(url, tab) - just encodes tab as a query string and appends it to url. Use it to make non-decorated links

req:empty(s) - returns true if s is nil or a blank string, false otherwise

req:empty_param(name) - same as req:empty(req.params[name])

req.GET - table with GET parameters of request

req.POST - table with POST parameters of request

req.method - request method (usually "GET" or "POST")

req.path_info - PATH_INFO metavariable

req.script_name - SCRIPT_NAME metavariable

req.doc_root - DOCUMENT_ROOT metavariable

req.env - the original WSAPI environment

req.app_path - the path of the WSAPI application currently running

req.query_string - unparsed query string

req.params - union of req.GET and req.POST, built on demand

req.cookies[name] - gets value of a cookie from browser

--]]

local function _M_request ()
  
--  local util = require"wsapi.util"

  local _M = {}

  local function split_filename(path)
    local name_patt = "[/\\]?([^/\\]+)$"
    return (string.match(path, name_patt))
  end

  local function insert_field (tab, name, value, overwrite)
    if overwrite or not tab[name] then
      tab[name] = value
    else
      local t = type (tab[name])
      if t == "table" then
        table.insert (tab[name], value)
      else
        tab[name] = { tab[name], value }
      end
    end
  end

  local function parse_qs(qs, tab, overwrite)
    tab = tab or {}
    if type(qs) == "string" then
      local url_decode = util.url_decode
      for key, val in string.gmatch(qs, "([^&=]+)=([^&=]*)&?") do
        insert_field(tab, url_decode(key), url_decode(val), overwrite)
      end
    elseif qs then
      error("WSAPI Request error: invalid query string")
    end
    return tab
  end

  local function get_boundary(content_type)
    local boundary = string.match(content_type, "boundary%=(.-)$")
    return "--" .. tostring(boundary)
  end

  local function break_headers(header_data)
    local headers = {}
    for type, val in string.gmatch(header_data, '([^%c%s:]+):%s+([^\n]+)') do
      type = string.lower(type)
      headers[type] = val
    end
    return headers
  end

  local function read_field_headers(input, pos)
    local EOH = "\r\n\r\n"
    local s, e = string.find(input, EOH, pos, true)
    if s then
      return break_headers(string.sub(input, pos, s-1)), e+1
    else return nil, pos end
  end

  local function get_field_names(headers)
    local disp_header = headers["content-disposition"] or ""
    local attrs = {}
    for attr, val in string.gmatch(disp_header, ';%s*([^%s=]+)="(.-)"') do
      attrs[attr] = val
    end
    return attrs.name, attrs.filename and split_filename(attrs.filename)
  end

  local function read_field_contents(input, boundary, pos)
    local boundaryline = "\r\n" .. boundary
    local s, e = string.find(input, boundaryline, pos, true)
    if s then
      return string.sub(input, pos, s-1), s-pos, e+1
    else return nil, 0, pos end
  end

  local function file_value(file_contents, file_name, file_size, headers)
    local value = { contents = file_contents, name = file_name,
      size = file_size }
    for h, v in pairs(headers) do
      if h ~= "content-disposition" then
        value[h] = v
      end
    end
    return value
  end

  local function fields(input, boundary)
    local state, _ = { }
    _, state.pos = string.find(input, boundary, 1, true)
    state.pos = state.pos + 1
    return function (state, _)
       local headers, name, file_name, value, size
       headers, state.pos = read_field_headers(input, state.pos)
       if headers then
         name, file_name = get_field_names(headers)
         if file_name then
           value, size, state.pos = read_field_contents(input, boundary,
              state.pos)
           value = file_value(value, file_name, size, headers)
         else
           value, size, state.pos = read_field_contents(input, boundary,
              state.pos)
         end
       end
       return name, value
     end, state
  end

  local function parse_multipart_data(input, input_type, tab, overwrite)
    tab = tab or {}
    local boundary = get_boundary(input_type)
    for name, value in fields(input, boundary) do
      insert_field(tab, name, value, overwrite)
    end
    return tab
  end

  local function parse_post_data(wsapi_env, tab, overwrite)
    tab = tab or {}
    local input_type = wsapi_env.CONTENT_TYPE
    if string.find(input_type, "x-www-form-urlencoded", 1, true) then
      local length = tonumber(wsapi_env.CONTENT_LENGTH) or 0
      parse_qs(wsapi_env.input:read(length) or "", tab, overwrite)
    elseif string.find(input_type, "multipart/form-data", 1, true) then
      local length = tonumber(wsapi_env.CONTENT_LENGTH) or 0
      if length > 0 then
         parse_multipart_data(wsapi_env.input:read(length) or "", input_type, tab, overwrite)
      end
    else
      local length = tonumber(wsapi_env.CONTENT_LENGTH) or 0
      tab.post_data = wsapi_env.input:read(length) or ""
    end
    return tab
  end

  _M.methods = {}

  local methods = _M.methods

  function methods.__index(tab, name)
    local func
    if methods[name] then
      func = methods[name]
    else
      local route_name = name:match("link_([%w_]+)")
      if route_name then
        func = function (self, query, ...)
           return tab:route_link(route_name, query, ...)
         end
      end
    end
    tab[name] = func
    return func
  end

  function methods:qs_encode(query, url)
    local parts = {}
    for k, v in pairs(query or {}) do
      parts[#parts+1] = k .. "=" .. util.url_encode(v)
    end
    if #parts > 0 then
      return (url and (url .. "?") or "") .. table.concat(parts, "&")
    else
      return (url and url or "")
    end
  end

  function methods:route_link(route, query, ...)
    local builder = self.mk_app["link_" .. route]
    if builder then
      local uri = builder(self.mk_app, self.env, ...)
      local qs = self:qs_encode(query)
      return uri .. (qs ~= "" and ("?"..qs) or "")
    else
      error("there is no route named " .. route)
    end
  end

  function methods:link(url, query)
    local prefix = (self.mk_app and self.mk_app.prefix) or self.script_name
--    local uri = prefix .. url
    local qs = self:qs_encode(query)
    return prefix .. url .. (qs ~= "" and ("?"..qs) or "")
  end

  function methods:absolute_link(url, query)
    local qs = self:qs_encode(query)
    return url .. (qs ~= "" and ("?"..qs) or "")
  end

  function methods:static_link(url)
    local prefix = (self.mk_app and self.mk_app.prefix) or self.script_name
    local is_script = prefix:match("(%.%w+)$")
    if not is_script then return self:link(url) end
    local vpath = prefix:match("(.*)/") or ""
    return vpath .. url
  end

  function methods:empty(s)
    return not s or string.match(s, "^%s*$")
  end

  function methods:empty_param(param)
    return self:empty(self.params[param])
  end

  function _M.new(wsapi_env, options)
    options = options or {}
    local req = {
      GET          = {},
      POST         = {},
      method       = wsapi_env.REQUEST_METHOD,
      path_info    = wsapi_env.PATH_INFO,
      query_string = wsapi_env.QUERY_STRING,
      script_name  = wsapi_env.SCRIPT_NAME,
      env          = wsapi_env,
      mk_app       = options.mk_app,
      doc_root     = wsapi_env.DOCUMENT_ROOT,
      app_path     = wsapi_env.APP_PATH
    }
    parse_qs(wsapi_env.QUERY_STRING, req.GET, options.overwrite)
    if options.delay_post then
      req.parse_post = function (self)
        parse_post_data(wsapi_env, self.POST, options.overwrite)
        self.parse_post = function () return nil, "postdata already parsed" end
        return self.POST
      end
    else
      parse_post_data(wsapi_env, req.POST, options.overwrite)
      req.parse_post = function () return nil, "postdata already parsed" end
    end
    req.params = {}
    setmetatable(req.params, { __index = function (tab, name)
      local var = req.GET[name] or req.POST[name]
      rawset(tab, name, var)
      return var
    end})
    req.cookies = {}
    local cookies = string.gsub(";" .. (wsapi_env.HTTP_COOKIE or "") .. ";",
              "%s*;%s*", ";")
    setmetatable(req.cookies, { __index = function (tab, name)
      name = name
      local pattern = ";" .. name ..
        "=(.-);"
      local cookie = string.match(cookies, pattern)
      cookie = util.url_decode(cookie)
      rawset(tab, name, cookie)
      return cookie
    end})
    return setmetatable(req, methods)
  end

  return _M

end


----------
--
-- response library, this is the verbatim keplerproject code 
-- see: https://github.com/keplerproject/wsapi/blob/master/src/wsapi/response.lua
--

--[[

wsapi.response.new([status, headers]) - creates a new response object, optionally setting an initial status code and header table. If a Content-Type was not passed in the initial header table then sets it as "text/html". The default status code is 200

res.status - status code to be returned to server

res.headers - table with headers to be returned to server

res:content_type(mime) - sets the Content-Type header to mime

res:write(...) - adds the arguments to the body, flattening an argument if it is a table

res:set_cookie(name, value) - sets the value of a cookie, value can be either a string or a table with fields value, expires (expiration date), domain, path, and secure. All fields except value are optional

res:delete_cookie(name, path) - tells the browser to erase a cookie, with an optional path

res:delete_cookie(name, path) - tells the browser to erase a cookie, with an optional path and domain

res:redirect(url) - sets status and headers for a redirect response to url, and returns a WSAPI response that does the redirect

res:forward(uri) - sets the PATH_INFO metavariable to uri (if not nil) and returns a mk FORWARD response to tell mk to keep trying to find a request handler

res:finish() - finishes response, returning status, headers and an iterator for the body

--]]

local function _M_response ()
  
--  local util = require"wsapi.util"

  local date = os.date
  local format = string.format

  local _M = {}

  local methods = {}
  methods.__index = methods

  _M.methods = methods

  local unpack = table.unpack or unpack

  function methods:write(...)
    for _, s in ipairs{ ... } do
      if type(s) == "table" then
        self:write(unpack(s))
      elseif s then
        local s = tostring(s)
        self.body[#self.body+1] = s
        self.length = self.length + #s
      end
    end
  end

  function methods:forward(url)
    self.env.PATH_INFO = url or self.env.PATH_INFO
    return "MK_FORWARD"
  end

  function methods:finish()
    self.headers["Content-Length"] = self.length
    return self.status, self.headers, coroutine.wrap(function ()
      for _, s in ipairs(self.body) do
       coroutine.yield(s)
      end
    end)
  end

  local function optional (what, name)
    if name ~= nil and name ~= "" then
      return format("; %s=%s", what, name)
    else
      return ""
    end
  end

  local function optional_flag(what, isset)
    if isset then
      return format("; %s", what)
    end
    return ""
  end

  local function make_cookie(name, value)
    local options = {}
    local t
    if type(value) == "table" then
      options = value
      value = value.value
    end
    local cookie = name .. "=" .. util.url_encode(value)
    if options.expires then
      t = date("!%A, %d-%b-%Y %H:%M:%S GMT", options.expires)
      cookie = cookie .. optional("expires", t)
    end
    if options.max_age then
      t = date("!%A, %d-%b-%Y %H:%M:%S GMT", options.max_age)
      cookie = cookie .. optional("Max-Age", t)
    end
    cookie = cookie .. optional("path", options.path)
    cookie = cookie .. optional("domain", options.domain)
    cookie = cookie .. optional("SameSite", options.SameSite)     -- 2023.02.10 @akbooer added SameSite cookie attribute
    cookie = cookie .. optional_flag("secure", options.secure)
    cookie = cookie .. optional_flag("HttpOnly", options.httponly)
    return cookie
  end

  function methods:set_cookie(name, value)
    local cookie = self.headers["Set-Cookie"]
    if type(cookie) == "table" then
      table.insert(self.headers["Set-Cookie"], make_cookie(name, value))
    elseif type(cookie) == "string" then
      self.headers["Set-Cookie"] = { cookie, make_cookie(name, value) }
    else
      self.headers["Set-Cookie"] = make_cookie(name, value)
    end
  end

  function methods:delete_cookie(name, path, domain)
    self:set_cookie(name, { value =  "xxx", expires = 1, path = path, domain = domain })
  end

  function methods:redirect(url)
    self.status = 302
    self.headers["Location"] = url
    self.body = {}
    return self:finish()
  end

  function methods:content_type(type)
    self.headers["Content-Type"] = type
  end

  function _M.new(status, headers)
    status = status or 200
    headers = headers or {}
    if not headers["Content-Type"] then
      headers["Content-Type"] = "text/html"
    end
    return setmetatable({ status = status, headers = headers, body = {}, length = 0 }, methods)
  end

  return _M

end


----------

return {
    ABOUT = ABOUT,
    TEST  = {build = build},        -- access to 'build' for testing
     
    cgi       = cgi,                -- called by the server to process a CGI request
    make_env  = make_env,           -- create wsapi_env from basic HTTP request
    
    -- modules
    
    util      =  util,              -- already instantiated
    request   = _M_request (),
    response  = _M_response (),
    
  }
  
-----
