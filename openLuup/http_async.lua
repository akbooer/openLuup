module ("http_async", package.seeall)

ABOUT = {
  NAME          = "http_async",
  VERSION       = "2021.03.25",
  DESCRIPTION   = "Asynchronous HTTP(S) request for Vera and openLuup",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2018-19",
  DOCUMENTATION = "https://community.getvera.com/t/openluup-asynchronous-i-o/206267/6",
}

----------------------------------------------------
--
-- ASYNCHRONOUS http_async.request()
--
--
-- Much of the utility code here is lifted from the high-level routines of the socket.http module
-- but split into two parts for sending the request and then reading the response in a callback handler.
-- proxy and redirects are not supported (neither are they for ssl requests)
--
-- The conversion from an integrated openLuup method to a stand-alone module simply required
-- the implementation of a proxy scheduler with two methods to watch/unwatch the socket in use.
-- There are several ways to do this, a simple call_delay() loop is used here but, in the end,
-- an action call using a <job> tag might be preferable.
--
-- The body of async_request() is totally unchanged from the openLuup version.
-- 2019.05.10, in fact, this whole module IS now the openLuup version (as well as the Vera one)
--
-- In order to get this working for HTTPS requests, I've had to include the complete LuaSec https module.
-- This is wrapped as a function and has an additional async_request method, but is otherwise
-- essentially unaltered from the version at https://github.com/brunoos/luasec/blob/master/src/https.lua

-- 2019.05.07  @akbooer extracted from openLuup to convert to stand-alone module for use in Vera
-- 2019.05.07  add pcall to protect code from error in user callback handler
-- 2019.05.08  allow user create function (for https, etc.)
-- 2019.05.09  incorporated code from LuaSec
-- 2019.05.10  modified to work on either Vera (using proxy scheduler) or openLuup


local url     = require "socket.url"
local http    = require "socket.http"
local ltn12   = require "ltn12"
local socket  = require "socket"


----------------------------------------------------
--
-- this is proxy for the openLuup scheduler routines not available in Vera
-- socket watch/unwatch
--

local function scheduler_proxy ()
  local NAME = "_Async_HTTP_Request"
  local POLL_RATE = 1
  local socket_list = {}    -- indexed by socket
    
  local function check_socket ()
    local list = {}
    for sock in pairs (socket_list) do list[#list+1] = sock end  
    local recvt = socket.select (list, nil, 0)  -- check for any incoming data
    for _,sock in ipairs (recvt) do
      local callback = socket_list[sock]
      if callback then 
        local ok, err = pcall (callback, sock) 
        if not ok then luup.log ("http_async.request ERROR: " .. (err or '?')) end
      end
    end
    luup.call_delay (NAME, POLL_RATE, '')
  end

  local function socket_watch (sock, callback_handler) 
    socket_list[sock] = callback_handler
  end

  local function socket_unwatch (sock)       -- immediately stop watching for incoming
    socket_list[sock] = nil
  end

  _G[NAME] = check_socket; check_socket()

  return {
    socket_watch = socket_watch,
    socket_unwatch = socket_unwatch,
    }
end -- of scheduler_proxy module

local _, scheduler = pcall (require, "openLuup.scheduler")
if type(scheduler) ~= "table" then      -- luup_require can't find openLuup.scheduler
  scheduler = scheduler_proxy () 
  luup.log "openLuup.scheduler proxy module used as alternative"
end

----------------------------------------------------
--
-- LuaSocket.http.request
--
--[[
LuaSocket 2.0.2 license
Copyright (c) 2004-2007 Diego Nehab

Permission is hereby granted, free  of charge, to any person obtaining
a  copy  of this  software  and  associated documentation  files  (the
"Software"), to  deal in  the Software without  restriction, including
without limitation  the rights to  use, copy, modify,  merge, publish,
distribute, sublicense,  and/or sell  copies of  the Software,  and to
permit persons to whom the Software  is furnished to do so, subject to
the following conditions:

The  above  copyright  notice  and this  permission  notice  shall  be
included in all copies or substantial portions of the Software.

THE  SOFTWARE IS  PROVIDED  "AS  IS", WITHOUT  WARRANTY  OF ANY  KIND,
EXPRESS OR  IMPLIED, INCLUDING  BUT NOT LIMITED  TO THE  WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT  SHALL THE AUTHORS OR COPYRIGHT HOLDERS  BE LIABLE FOR ANY
CLAIM, DAMAGES OR  OTHER LIABILITY, WHETHER IN AN  ACTION OF CONTRACT,
TORT OR  OTHERWISE, ARISING  FROM, OUT  OF OR  IN CONNECTION  WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]

local function LuaSocket_http ()

  ----------------------------------------------------
  --
  -- async_request (u, b, callback) or (u, callback) where 'u' may table or string
  --

  local function async_http_request (u, b, callback)
    local simple_string   -- used to concatenate responses of 'simple' string-type url requests
    local base = _G

    -- create() function returns a proxy socket which mirrors all the actual socket methods
    -- but intercepts the close() function to remove the socket from the scheduler list when done.
      local function create_proxy_socket ()
        local create = (type (u) == "table" and u.create) or socket.tcp     -- 2019.05.08  allow user create (for https)
        local sock = create ()
        return setmetatable ({
            close = function (self)
                scheduler.socket_unwatch (self)       -- immediately stop watching for incoming
                return sock: close ()
              end
            },{
            __index = function (s, f) 
              s[f] = function (_, ...) return sock[f] (sock, ...) end
              return s[f]  -- it's there now, so no need to recreate it in future
            end,
            __tostring = function () return "async-" .. tostring(sock) end,   -- cosmetic for console
            })
      end

    local function adjusturi(reqt)
        local u = reqt
        -- if there is a proxy, we need the full url. otherwise, just a part.
    --    if not reqt.proxy and not _M.PROXY then
            u = {
               path = socket.try(reqt.path, "invalid path 'nil'"),
               params = reqt.params,
               query = reqt.query,
               fragment = reqt.fragment
            }
    --    end
        return url.build(u)
    end

    local function shouldreceivebody(reqt, code)
        if reqt.method == "HEAD" then return nil end
        if code == 204 or code == 304 then return nil end
        if code >= 100 and code < 200 then return nil end
        return 1
    end

    local function adjustheaders(reqt)
        -- default headers
        local host = string.gsub(reqt.authority, "^.-@", "")
        local lower = {
            ["user-agent"] = "openLuup_USERAGENT",
            ["host"] = host,
            ["connection"] = "close, TE",
            ["te"] = "trailers"
        }
        -- if we have authentication information, pass it along
    --    if reqt.user and reqt.password then
    --        lower["authorization"] = 
    --            "Basic " ..  (mime.b64(reqt.user .. ":" .. reqt.password))
    --    end
        -- if we have proxy authentication information, pass it along
    --    local proxy = reqt.proxy or _M.PROXY
    --    if proxy then
    --        proxy = url.parse(proxy)
    --        if proxy.user and proxy.password then
    --            lower["proxy-authorization"] = 
    --                "Basic " ..  (mime.b64(proxy.user .. ":" .. proxy.password))
    --        end
    --    end
        -- override with user headers
        for i,v in base.pairs(reqt.headers or lower) do
            lower[string.lower(i)] = v
        end
        return lower
    end

    -- default url parts
    local default = {
        host = "",
        port = 80,
        path ="/",
        scheme = "http"
    }

    local function adjustrequest(reqt)
        -- parse url if provided
        local nreqt = reqt.url and url.parse(reqt.url, default) or {}
        -- explicit components override url
        for i,v in base.pairs(reqt) do nreqt[i] = v end
        if nreqt.port == "" then nreqt.port = 80 end
        socket.try(nreqt.host and nreqt.host ~= "", 
            "invalid host '" .. base.tostring(nreqt.host) .. "'")
        -- compute uri if user hasn't overriden
        nreqt.uri = reqt.uri or adjusturi(nreqt)
        -- adjust headers in request
        nreqt.headers = adjustheaders(nreqt)
        -- ajust host and port if there is a proxy
    --    nreqt.host, nreqt.port = adjustproxy(nreqt)
        return nreqt
    end

    local function trequest(reqt)
      local nreqt = adjustrequest(reqt)
      if nreqt.proxy then
        return nil, "proxy not supported"
      elseif url.redirect then
        return nil, "redirect not supported"
      end

      local old
      old, http.TIMEOUT = http.TIMEOUT, 75    -- replace current http module global timeout
      local h = http.open(nreqt.host, nreqt.port, create_proxy_socket)
      http.TIMEOUT = old                            -- restore after opening (it's the only time it's used)

    -- send request line and headers
      local ok1, err1 = h:sendrequestline(nreqt.method, nreqt.uri)
      local ok2, err2 = h:sendheaders(nreqt.headers)
      local ok3, err3 = 1
      -- if there is a body, send it
      if nreqt.source then
          ok3, err3 = h:sendbody(nreqt.headers, nreqt.source, nreqt.step) 
      end
      local ok, err = ok1 and ok2 and ok3, err1 or err2 or err3
      
      -------------------------------------------
      --
      -- this handler is called when the socket receives data (or times out)
      local function callback_handler ()
        local code, status = h:receivestatusline()
        -- if it is an HTTP/0.9 server, simply get the body and we are done
        if not code then
            h:receive09body(status, nreqt.sink, nreqt.step)
            return 1, 200
        end
        local headers
        -- ignore any 100-continue messages
        while code == 100 do 
            headers = h:receiveheaders()
            code, status = h:receivestatusline()
        end
        headers = h:receiveheaders()
        -- at this point we should have a honest reply from the server
        -- we can't redirect if we already used the source, so we report the error 
    --    if shouldredirect(nreqt, code, headers) and not nreqt.source then
    --        h:close()
    --        return tredirect(reqt, headers.location)
    --    end
        -- here we are finally done
        if shouldreceivebody(nreqt, code) then
            h:receivebody(headers, nreqt.sink, nreqt.step)
        end
        h:close()
        -- if it was a simple request, return the string response, else just 1
        callback (simple_string and table.concat (simple_string) or 1, code, headers, status)
      end
      --
      -------------------------------------------
      
      -- could include nreqt.host
      if ok then scheduler.socket_watch (h.c, callback_handler, nil, nreqt.scheme: upper()) end    -- TODO: username parameter
      return ok, err
    end


    -- async_request (u, b, callback) or (u, callback) where 'u' may table or string
    -- cope with optional body parameter for 'simple' string request
    if not callback then callback, b = b, nil end
    if type (callback) ~= "function" then return nil, "callback parameter is missing'" end

    local reqt = u
    if type(u) == "string" then 
      simple_string = {}
      reqt = {
          url = u,
          sink = ltn12.sink.table(simple_string)
      }
      if b then
          reqt.source = ltn12.source.string(b)
          reqt.headers = {
              ["content-length"] = string.len(b),
              ["content-type"] = "application/x-www-form-urlencoded"
          }
          reqt.method = "POST"
      end
    end

    return trequest(reqt) -- note that this is just a (status, error return) and not the response!
  end

  --------------------------------------------------------------------------------
  -- Export module
  --
  
  return {async_http_request = socket.protect (async_http_request)}

end

----------------------------------------------------

--[[
LuaSec 0.4 license
Copyright (C) 2006-2009 Bruno Silvestre, PUC-Rio

Permission is hereby granted, free  of charge, to any person obtaining
a  copy  of this  software  and  associated  documentation files  (the
"Software"), to  deal in  the Software without  restriction, including
without limitation  the rights to  use, copy, modify,  merge, publish,
distribute,  sublicense, and/or sell  copies of  the Software,  and to
permit persons to whom the Software  is furnished to do so, subject to
the following conditions:

The  above  copyright  notice  and  this permission  notice  shall  be
included in all copies or substantial portions of the Software.

THE  SOFTWARE IS  PROVIDED  "AS  IS", WITHOUT  WARRANTY  OF ANY  KIND,
EXPRESS OR  IMPLIED, INCLUDING  BUT NOT LIMITED  TO THE  WARRANTIES OF
MERCHANTABILITY,    FITNESS    FOR    A   PARTICULAR    PURPOSE    AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE,  ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]

local function LuaSec_https ()
  ----------------------------------------------------------------------------
  -- LuaSec 1.0
  -- Copyright (C) 2009-2021 PUC-Rio
  --
  -- Author: Pablo Musa
  -- Author: Tomas Guisasola
  ---------------------------------------------------------------------------

  local socket = require("socket")
  local ssl    = require("ssl")
  local ltn12  = require("ltn12")
  local http   = require("socket.http")
  local url    = require("socket.url")

  local ahttp  = LuaSocket_http()

  local try    = socket.try

--  module("ssl.https")
  --
  -- Module
  --
  local _M = {
    _VERSION   = "1.0",
    _COPYRIGHT = "LuaSec 1.0 - Copyright (C) 2009-2021 PUC-Rio",
    PORT       = 443,
    TIMEOUT    = 60
  }

-- TLS configuration
  local cfg = {
    protocol = "any",
    options  = {"all", "no_sslv2", "no_sslv3", "no_tlsv1"},
    verify   = "none",
  }

  --------------------------------------------------------------------
  -- Auxiliar Functions
  --------------------------------------------------------------------

  -- Insert default HTTPS port.
  local function default_https_port(u)
     return url.build(url.parse(u, {port = _M.PORT}))
  end

  -- Convert an URL to a table according to Luasocket needs.
  local function urlstring_totable(url, body, result_table)
     url = {
        url = default_https_port(url),
        method = body and "POST" or "GET",
        sink = ltn12.sink.table(result_table)
     }
     if body then
        url.source = ltn12.source.string(body)
        url.headers = {
           ["content-length"] = #body,
           ["content-type"] = "application/x-www-form-urlencoded",
        }
     end
     return url
  end

  -- Forward calls to the real connection object.
  local function reg(conn)
     local mt = getmetatable(conn.sock).__index
     for name, method in pairs(mt) do
        if type(method) == "function" then
           conn[name] = function (self, ...)
                           return method(self.sock, ...)
                        end
        end
     end
  end

  -- Return a function which performs the SSL/TLS connection.
  local function tcp(params)
     params = params or {}
     -- Default settings
     for k, v in pairs(cfg) do 
        params[k] = params[k] or v
     end
     -- Force client mode
     params.mode = "client"
     -- 'create' function for LuaSocket
     return function ()
        local conn = {}
        conn.sock = try(socket.tcp())
        local st = getmetatable(conn.sock).__index.settimeout
        function conn:settimeout(...)
           return st(self.sock, _M.TIMEOUT)
        end
        -- Replace TCP's connection function
        function conn:connect(host, port)
           try(self.sock:connect(host, port))
           self.sock = try(ssl.wrap(self.sock, params))
           self.sock:sni(host)
           self.sock:settimeout(_M.TIMEOUT)
           try(self.sock:dohandshake())
           reg(self, getmetatable(self.sock))
           return 1
        end
        return conn
    end
  end

  --------------------------------------------------------------------
  -- Main Function
  --------------------------------------------------------------------

  -- Make a HTTP request over secure connection.  This function receives
  --  the same parameters of LuaSocket's HTTP module (except 'proxy' and
  --  'redirect') plus LuaSec parameters.
  --
  -- @param url mandatory (string or table)
  -- @param body optional (string)
  -- @return (string if url == string or 1), code, headers, status
  --
  local function request(url, body)
    local result_table = {}
    local stringrequest = type(url) == "string"
    if stringrequest then
      url = urlstring_totable(url, body, result_table)
    else
      url.url = default_https_port(url.url)
    end
    if http.PROXY or url.proxy then
      return nil, "proxy not supported"
    elseif url.redirect then
      return nil, "redirect not supported"
    elseif url.create then
      return nil, "create function not permitted"
    end
    -- New 'create' function to establish a secure connection
    url.create = tcp(url)
    local res, code, headers, status = http.request(url)
    if res and stringrequest then
      return table.concat(result_table), code, headers, status
    end
    return res, code, headers, status
  end

  -- 2019.05.08  @akbooer asynchronous HTTPS using existing HTTP async call
  local function async_https_request(url, body, callback)   -- extra callback parameter
    if not callback then callback, body = body, nil end       -- put it in the right place
    local result_table = {}
    local stringrequest = type(url) == "string"
    if stringrequest then
      url = urlstring_totable(url, body, result_table)
    else
      url.url = default_https_port(url.url)
    end
    if http.PROXY or url.proxy then
      return nil, "proxy not supported"
    elseif url.redirect then
      return nil, "redirect not supported"
    elseif url.create then
      return nil, "create function not permitted"
    end
    -- New 'create' function to establish a secure connection
    url.create = tcp(url)
    -- local callback to restore string request return
    local function https_callback (res, ...)
      if res and stringrequest then res = table.concat(result_table) end
      callback (res, ...)     -- user supplied callback
    end
    return ahttp.async_http_request (url, https_callback)
  end

  --------------------------------------------------------------------------------
  -- Export module
  --

  _M.async_https_request = socket.protect (async_https_request)    -- 2019.05.08  @akbooer
  _M.request = request
  _M.tcp = tcp

  return _M

end

----------------------------------------------------

local ahttps = LuaSec_https()
local ahttp  = LuaSocket_http()

function request (u, ...)       -- global name for luup.require() to work
  local scheme = u
  if type (u) == "table" then scheme = u.url end
  local is_https = scheme: lower() : match "^https"
  if is_https then 
    scheme = ahttps.async_https_request
  else
    scheme = ahttp.async_http_request
  end
  return scheme (u, ...)
end

return {request = request}      -- return table for ordinary Lua require() to work

-----
-- TEST
--
-- local http_async = require "http_async"

--local function request_callback (response, code, headers, statusline)
--  luup.log ("CALLBACK status code: " .. (code or '?'))
--  luup.log ("CALLBACK output length: " .. #(response or ''))
--end

--local ok, err = http_async.request ("http://example.com", request_callback)
--luup.log ("async_request, status: " .. ok .. ", " .. (err or ''))

-----


