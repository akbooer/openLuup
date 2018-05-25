
local t = require "tests.luaunit"

-- openLuup.server TESTS for:
--
--  basic utilities,
--  wget client (both internal and external HTTP(s) requests),
--  the three main request types:
--    1) files
--    2) Luup data_request?id=...
--    3) CGIs implementented with Lua WSAPI
--

local s  = require "openLuup.http"
local s2 = require "openLuup.servlet"

local json = require "openLuup.json"


TestServerUtilities = {}

function TestServerUtilities:test_methodlist ()
  t.assertIsFunction (s.add_callback_handlers)
  t.assertIsFunction (s.wget)
  t.assertIsFunction (s.start)
end

function TestServerUtilities:test_myip ()
  local ip = s.myIP
  t.assertIsString (ip)
  local syntax = "%d+%.%d+%.%d+%.%d+"
  t.assertTrue (ip: match (syntax))
end

function TestServerUtilities:test_CamelCaps ()
  local cc = s.TEST.CamelCaps
  local h = "a-REALLY-Strange-hEADER-12345-isnt-it"
  local H = "A-Really-Strange-Header-12345-Isnt-It"
  t.assertEquals (cc(h), H)
end

function TestServerUtilities:test_content_iterator ()
  local content = "abc123"
  local mc = s.TEST.make_content
  local mi = s2.TEST.make_iterator
  local i = mi (content)
  t.assertIsFunction (i)        -- this is the iterator function
  local c = i()
  t.assertIsString (c)          -- this is the recovered content
  t.assertEquals (c, content)
  local c2 = i()                -- there should be no more...
  t.assertIsNil (c2)
end

function TestServerUtilities:test_request_object ()
  local ro = s.TEST.request_object
  local u = "http://127.0.0.1:3480/data_request?id=testing&p1=abc&p2=123"
  local o = ro(u)
  
  local correct = {
    URL = {
      authority = "127.0.0.1:3480",
      host = "127.0.0.1",
      path = "/data_request",
      port = "3480",
      query = "id=testing&p1=abc&p2=123",
      scheme = "http"
    },
    handler = s.TEST.data_request,
    headers = {},
    http_version = "HTTP/1.1",
    internal = true,
    method = "GET",
    parameters = {
        id = "testing",
        p1 = "abc",
        p2 = "123"
      },
    path_list={"data_request", is_absolute=1},
    post_content = ""
    }

  o.request_start = nil   -- can't know what this will be
  t.assertItemsEquals (o, correct)
end

TestServerRequests = {}


function TestServerRequests:test_http_file ()
  local hf = s2.TEST.http_file
  local ro = s.TEST.request_object
  local ob = ro "http:localhost:3480/index.html"
  local s,h,i = hf (ob)
  t.assertIsNumber (s)
  t.assertIsTable (h)
  t.assertIsFunction (i)
  local f = i()
  t.assertIsString (f)
  t.assertEquals (h["Content-Type"], "text/html")
end

function TestServerRequests:test_http_file_not_found ()
  local hf = s2.TEST.http_file
  local ro = s.TEST.request_object
  local s,h,i = hf (ro "http:localhost:3480/qwertyuiop")
  t.assertIsNumber (s)
  t.assertIsTable (h)
  t.assertIsFunction (i)
  local f = i()
  t.assertIsString (f)
  t.assertEquals (f, "file not found:qwertyuiop")
  t.assertEquals (s, 404)
end

function TestServerRequests:test_data_request ()
  local dr = s2.TEST.data_request
  local ro = s.TEST.request_object
  -- special TEST request returns JSON-encoded handler parameter list
  local ob = ro "http://127.0.0.1:3480/data_request?id=TEST&p1=abc&p2=123"
  local s,h,i = dr (ob)
  t.assertIsNumber (s)
  t.assertIsTable (h)
  t.assertIsFunction (i)
  t.assertEquals (s, 200)                                   -- check the status
  t.assertEquals (h["Content-Type"], "application/json")    -- check the content type header
  local f = i()                                             -- this is the content iterator
  t.assertIsString (f)
  local p = json.decode (f)   -- decode the list and check the parameters!
  t.assertEquals (p[1], "TEST")
  t.assertIsTable (p[2])
  t.assertEquals (p[2].p1, "abc")
  t.assertEquals (p[2].p2, "123")
end

function TestServerRequests:test_wsapi_cgi ()
  local cg = s2.TEST.wsapi_cgi
  local ro = s.TEST.request_object
  local u = "http://0.0.0.0:3480/cgi-bin/cmh/sysinfo.sh"    -- CGI requests are handled by WSAPI
  local o = ro(u)
  local s,h,i = cg (o)
  t.assertIsNumber (s)
  t.assertIsTable (h)
  t.assertIsFunction (i)
  local f = i()
  t.assertIsString (f)
  t.assertEquals (h["Content-Type"], "text/plain")
 end

TestServerResponses = {}


function TestServerResponses:test_response_simple ()
  local re = s.TEST.http_response
  local mi = s2.TEST.make_iterator
  local status = 200
  local content = "Test content"
  local headers = {
    ["Content-Length"] = #content,
    ["Content-Type"] = "text/plain",
  }
--  headers, response, chunked = http_response (status, headers, iterator)
  local h,r,c = re (status, headers, mi (content))
  t.assertIsString (h)
  t.assertIsString (r)
  t.assertFalse (c)
  t.assertNotNil (h:match "%C\r\n\r\n$")    -- headers should end with blank line
  t.assertEquals (r, content)
end


function TestServerResponses:test_response_chunked ()
  local re = s.TEST.http_response
  local mi = s2.TEST.make_iterator
  local status = 200
  local content = "Test content"
  local headers = {
--    ["Content-Length"] = #content,      -- no content lengths signal chunked
    ["Content-Type"] = "text/plain",
  }
--  headers, response, chunked = http_response (status, headers, iterator)
  local h,r,c = re (status, headers, mi (content))
  t.assertIsString (h)
  t.assertIsString (r)
  t.assertTrue (c)
  t.assertNotNil (h:match "%C\r\n\r\n$")    -- headers should end with blank line
  t.assertEquals (r, content)
end


TestServerWGET = {}


function TestServerWGET:test_internal ()    -- same as data_request?id=TEST above, but using WGET API
  local wget = s.wget
  -- special TEST request returns JSON-encoded handler parameter list
  local status,r = wget "http://localhost:3480/data_request?id=TEST&p1=abc&p2=123"
  t.assertIsNumber (status)
  t.assertIsString (r)
  t.assertEquals (status, 0)                -- check the status
  local p = json.decode (r)                 -- decode the list and check the parameters!
  t.assertEquals (p[1], "TEST")
  t.assertIsTable (p[2])
  t.assertEquals (p[2].p1, "abc")
  t.assertEquals (p[2].p2, "123")
end

function TestServerWGET:test_external_http ()
  local wget = s.wget
  local status,r = wget "http://www.google.com"
  t.assertEquals (status,0)
  t.assertIsString (r)
  t.assertTrue (r: match "^<!doctype html>")    -- check start and end of HTML
  t.assertTrue (r: match "</html>%c*$")
end

function TestServerWGET:test_external_https ()
  local wget = s.wget
  local status,r = wget "https://www.google.com"
--  t.assertIsNumber (status)
  t.assertIsString (r)
end

--------------------

if not multifile then t.LuaUnit.run "-v" end

--------------------
