local ABOUT = {
  NAME          = "openLuup.client",
  VERSION       = "2019.10.14",
  DESCRIPTION   = "luup.inet .wget() and .request()",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
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

--
-- openLuup CLIENT -- 
--
-- supports Basic and Digest authentication over HTTP / HTTPS
--


-- 2019.07.30  split from openLuup.server
-- 2019.10.14  added start() function, called from server, to allow use of arbitrary port


local url       = require "socket.url"
local http      = require "socket.http"
local https     = require "ssl.https"
local ltn12     = require "ltn12"                       -- for wget handling
--local mime      = require "mime"                        -- for basic authorization in wget

local OKmd5,md5 = pcall (require, "md5")                -- for digest authenication (may be missing)

local logs      = require "openLuup.logs"
local tables    = require "openLuup.servertables"       -- mimetypes and status_codes
local servlet   = require "openLuup.servlet"
local wsapi     = require "openLuup.wsapi"              -- to build WSAPI request environment

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

-- CONFIGURATION DEFAULTS

local PORT -- filled in during start()
local myIP = tables.myIP

-- local functions

local parse_header = function(h)
  local r = {}
  for k,v in h: gmatch '(%w+)="?([^",]+)' do r[k:lower()] = v  end
  return r
end

local function make_digest_header(t)
  local s = {"Digest "}
  local function p(...) for _,x in ipairs {...} do s[#s+1] = x end; end
  for n, v in pairs (t) do p (n, '="', v, '"', ', ') end      -- unquote nc ???
  s[#s] = nil
  return table.concat(s)
end

local function hash(...) return md5.sumhexa(table.concat({...}, ":")) end

----------------------------------------------------
--
-- Digest authorization code inspired by: https://github.com/catwell/lua-http-digest
-- as suggested by @jswim77 here: http://forum.micasaverde.com/index.php/topic,63465.msg380840.html#msg380840
-- or, in the new Vera Community forum: https://community.getvera.com/t/openluup-cameras/198812/36
-- and prototyped by @rafale77 here: https://github.com/akbooer/openLuup/pull/11
--
-- this requires the lua-md5 module to be on the Lua path
--
local _request = function(t, Timeout)
  local URL = url.parse(t.url)
  local user, password = URL.user, URL.password     -- may or may not be present
  local scheme = URL.scheme == "https" and https or http
  scheme.TIMEOUT = Timeout or 5
  
  -- TODO: limited number of redirects
  local b, c, h = scheme.request(t)                 -- if user/password then this tries Basic authorization
  if (c == 401) and h["www-authenticate"] then      -- else try digest 
    local ht = parse_header(h["www-authenticate"])
    
    assert(ht.realm and ht.nonce, "missing realm or nonce in received WWW-Authenticate header")
    if not OKmd5 then
      return nil, "MD5 module not available for digest authorization"
    end
    if ht.qop ~= "auth" then
      return nil, string.format("unsupported qop (%s)", tostring(ht.qop))
    end
    if ht.algorithm and (ht.algorithm:lower() ~= "md5") then
      return nil, string.format("unsupported algorithm (%s)", tostring(ht.algorithm))
    end
 
    local nc, cnonce = "00000001", ("%08x"): format (os.time())
    local uri = url.build{path = URL.path, query = URL.query}
    local method = t.method or "GET"
    local response = hash(
      hash(user or '', ht.realm, password or ''),
      ht.nonce,
      nc,
      cnonce,
      "auth",
      hash(method, uri)
    )
    
    t.headers = t.headers or {}
    t.headers.authorization = make_digest_header {
      username = user,
      realm = ht.realm,
      nonce = ht.nonce,
      uri = uri,
      cnonce = cnonce,
      nc = nc,
      qop = "auth",
      algorithm = "MD5",
      response = response,
      opaque = ht.opaque,
    }
    
    b, c, h = scheme.request(t)
  end
  return b, c, h
end

local function request (x, Timeout)
  local response = {}
  local b, c, h = _request ({url = x, sink = ltn12.sink.table(response)}, Timeout)
  b = (b == 1) and table.concat(response) or b
  return b, c, h
end


----------------------------------------------------
--
-- HTTP CLIENT request (for luup.inet.wget)
--

local self_reference = {
  ["localhost"] = true,
  ["127.0.0.1"] = true, 
  ["0.0.0.0"] = true, 
  [myIP] = true,
}

--[[ see: http://wiki.micasaverde.com/index.php/Luup_Lua_extensions#function:_wget

This reads the URL and returns 3 variables: the first is a numeric error code which is 0 if successful. 
The second variable is a string containing the contents of the page. 
The third variable is the HTTP status code. 
If Timeout is specified, the function will timeout after that many seconds. 
The default value for Timeout is 5 seconds. 
If Username and Password are specified, they will be used for HTTP Basic Authentication. 

--]]

-- issue a GET request, handling local ones for port 3480 without going over HTTP
local function wget (request_URI, Timeout, Username, Password) 
  local result, status
  local responseHeaders
   
  local relative = request_URI: match "^/[^/]"    -- 2018.03.15  it's a relative URL, must be served from here
  if not relative then
    if not (request_URI: match "^%w+://") then 
      request_URI = "http://" .. request_URI      -- assume it's an external HTTP request
    end
  end
 
  local URL = url.parse (request_URI)             -- parse URL

  local self_ref = self_reference [URL.host] and URL.port == PORT  -- 2016-03-16 check for port #, thanks @reneboer
  if relative or self_ref then
    
    -- INTERNAL request
    local headers, iterator
    URL.path = URL.path:gsub ("/port_3480", '')               -- 2016.09.16, thanks @explorer 
    local wsapi_env = wsapi.make_env (URL.path, URL.query)
    status, headers, iterator = servlet.execute (wsapi_env)   -- make the request call
    result = {}
    for x in iterator do result[#result+1] = tostring(x) end  -- build the return string
    result = table.concat (result)
    
  else
    
    -- EXTERNAL request OR not port 3480 
    
    -- Username and Password parameters override either of those in the URL
    Username, Password = Username or URL.user, Password or URL.password
    URL.user, URL.password = Username, Password
    
    URL = url.build (URL)                             -- reconstruct request for external use
    _debug (URL)
    
    result, status, responseHeaders = request (URL, Timeout)
  end
  
  if not result then    -- 2019.07.30  socket library has failed somehow, fix up error and message
    result = table.concat {status or "unknown error in socket library", ": ", request_URI} 
    status = -1
  end
  
  local wget_status = status                          -- wget has a strange return code
  if status == 200 then
    wget_status = 0 
  else                                                -- 2017.05.05 add error logging
    local error_message = "WGET error status: %s, request: %s"  -- 2017.05.25 fix wget error logging format
    _log (error_message: format (status, request_URI))
  end
  -- note reversal of first two parameters order cf. http.request()
  return wget_status, result or '', status, responseHeaders
end


---------------------------------------------
--
-- TEST digest authentication
--
--[[
local pretty = require "pretty"

print(pretty {luup.inet.wget "httpbin.org/auth"})
print(pretty {luup.inet.wget ("http://foo:garp@httpbin.org/basic-auth/foo/garp")})
print(pretty {luup.inet.wget ("http://httpbin.org/basic-auth/foo/garp", 5, "foo", "garp")})
print(pretty {luup.inet.wget ("http://httpbin.org/digest-auth/auth/foo/garp", 5, "foo", "garp")})

--]]
--
---------------------------------------------

--- return module variables and methods
return {
    ABOUT = ABOUT,
    
    -- constants
    myIP = myIP,
    
    -- functions
    wget = wget,
    start = function (config) PORT = tostring(config.Port or 3480) end,    -- 2019.10.14 
    
    -- TODO: inet.request
  }

-----
