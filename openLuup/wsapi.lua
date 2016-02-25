local _NAME = "openLuup.wsapi"
local revisionDate = "2016.02.25"
local banner = "    version " .. revisionDate .. "  @akbooer"

-- This module implements a WSAPI application connector for the openLuup port 3480 server.
--
-- see: http://keplerproject.github.io/wsapi/
-- and: http://keplerproject.github.io/wsapi/license.html
-- and: https://github.com/keplerproject/wsapi
-- and: http://keplerproject.github.io/wsapi/manual.html

-- The use of WSAPI concepts for handling openLuup CGI requests was itself inspired by @vosmont,
-- see: http://forum.micasaverde.com/index.php/topic,36189.0.html
-- 2016.02.18

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

local loader  = require "openLuup.loader"
local logs    = require "openLuup.logs"


-- utilities

local cache = {}       -- cache for compiled CGIs

--  local log
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control

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
  local file = script: match ".(.+)"      -- ignore leading '/'
  local f = io.open (file) 
  if not f then 
    return dummy_app (404, "file not found: " .. (script or '?')) 
  end
  local line = f: read "*l"
  
  -- looking for first line of "#!/usr/bin/env wsapi.cgi" for WSAPI application
  local code
  if not line:match "^%s*#!/usr/bin/env%s+wsapi.cgi%s*$" then 
    return dummy_app (501, "file is not a WSAPI application: " .. (script or '?')) 
  end
  code = f:read "*a"
  f: close ()
    
  -- compile and load
  local a, error_msg = loadstring (code, script)    -- load it
  if not a or error_msg then
    return dummy_app (500, error_msg)               -- 'internal server error'
  end
  local lua_env = loader.new_environment (script)   -- use new environment
  setfenv (a, lua_env)                              -- Lua 5.1 specific function environment handling
  a, error_msg = pcall(a)                           -- instantiate it
  if not a then
    return dummy_app (500, error_msg)               -- 'internal server error'
  end
  
  -- find application entry point
  local runner = (lua_env or {}).run
  if (not runner) or (type (runner) ~= "function") then
    return dummy_app (500, "can't find WSAPI application entry point")         -- 'internal server error'
  end

  return runner   -- success! return the entry point to the WSAPI application
end
  
-- dispatch is called to execute the CGI
-- and build the return results
local function dispatch (env)
  local script = env["SCRIPT_NAME"]
  cache[script] = cache[script] or build (script) 
  
  -- guaranteed to be something executable here, even it it's a dummy with error message
  
  -- three return values: the HTTP status code, a table with headers, and the output iterator.
  local status, headers, iterator = cache[script] (env)
  
  -- TODO: return all three parameters... requires further changes to openLuup.server
  -- print (pretty {script = script, status = status, headers = headers, iterator = iterator})
  local h = {}
  for a,b in pairs (headers) do     -- force header names to lower case
    h[a:lower()] = b
  end
  
  local result = {}
  for output in iterator do result[#result+1] = output end
  result = table.concat (result) 
--  print ("result: ", result)
  return result, h["content-type"]
  
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
--]]
-- cgi is called by the server when it receives a CGI request
local function cgi (URL, headers, post_content) 
  local meta = {
    __index = function () return '' end;  -- return the empty string instead of nil for undefined metavariables
  }
  
  local ptr = 1
  local input = {
    read =  
      function (n) 
        n = n or #post_content
        local start, finish = ptr, ptr + n - 1
        ptr = ptr + n
        return post_content:sub (start, finish)
      end
  }
  
  local error = {
    write = function (...) 
      _log (table.concat ({URL.path or '?', ':', ...}, ' '), "openLuup.wsapi.cgi") 
    end;
  }
  
  local env = {   -- the WSAPI standard (and CGI) is upper case for these metavariables
    ["CONTENT_LENGTH"]  = #post_content,
    ["CONTENT_TYPE"]    = headers["Content-Type"] or '',
    ["REMOTE_HOST"]     = headers ["Host"],
    ["SCRIPT_NAME"]     = URL.path,
    ["PATH_INFO"]       = '/',
    ["QUERY_STRING"]    = URL.query,
    -- methods
    input = input,
    error = error,
  }
  
  local wsapi_env = setmetatable (env, meta)
  
-- Only TWO return values: the full output and content-type (for luup)
  return dispatch (wsapi_env)
end

return {
    cgi   = cgi,                    -- called by the server to process a CGI request
    test  = {build = build},        -- access to 'build' for testing
  }
  
-----
