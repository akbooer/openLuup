local t = require "tests.luaunit"

--
-- LZAP compression tests
-- @akbooer, May 2016
--

local socket  = require "socket"
local timer   = socket.gettime

local C = require "openLuup.compression"
local codec = C.codec

TestCodec = {}


function TestCodec:test_simple ()
  local c = codec.new "abc"
  t.assertIsFunction (c.encode)
  t.assertIsFunction (c.decode)
  t.assertEquals (c.symbols, 3^2)

  c = codec.new "0123456789"        -- '.new' syntax, or...
  t.assertEquals (c.symbols, 1e2)

  c = codec ()                      -- ...direct call syntax, either will work
  t.assertEquals (c.symbols, 256^2)
end
  
function TestCodec:test_json ()
  local j = codec (codec.json)
  t.assertEquals (j.symbols, 92^2)
  t.assertEquals (table.concat (j.alphabet), codec.json)  -- compare separate byte codes to expected string
  local x = {0,1,2,3,4,5}
  local y = j.encode (x)
  t.assertEquals (y, "  ! # $ % & ")    -- these are the first codes for this codec
  local z = j.decode (y)
  t.assertItemsEquals (z, x)
end
 
function TestCodec:test_json_header ()
  local j = codec (codec.json, "HEADER")
  t.assertEquals (j.symbols, 92^2)
  t.assertEquals (table.concat (j.alphabet), codec.json)  -- compare separate byte codes to expected string
  local x = {0,1,2,3,4,5}
  local y = j.encode (x)
  t.assertEquals (y, "HEADER  ! # $ % & ")    -- the header, then the first codes for this codec
  local z = j.decode (y)
  t.assertItemsEquals (z, x)
end


function TestCodec:test_header ()
  local j = codec (nil, "TEST Header")
  t.assertEquals (j.symbols, 256^2)
  local x = {0,1,2,3,4,5}
  local y = j.encode (x)
  local z = j.decode (y)
  t.assertItemsEquals (z, x)
end
 
function TestCodec:test_full ()
  local j = codec ()
  t.assertEquals (j.symbols, 256^2)
  local x = {0,1,2,3,4,5}
  local y = j.encode (x)
  local z = j.decode (y)
  t.assertItemsEquals (z, x)
end

function TestCodec:test_full2 ()
  local j = codec (codec.full)
  t.assertEquals (j.symbols, 256^2)
  local x = {0,1,2,3,4,5}
  local y = j.encode (x)
  local z = j.decode (y)
  t.assertItemsEquals (z, x)
end
 
function TestCodec:test_null ()
  local j = codec (codec.null)
  t.assertEquals (j.symbols, 2^53)
  local x = {0,1,2,3,4,5}
  local y = j.encode (x)
  local z = j.decode (y)
  t.assertItemsEquals (z, x)
end
 
function TestCodec:test_null2 ()
  local j = codec.null      -- alternative way to specify null codec
  t.assertEquals (j.symbols, 2^53)
  local x = {0,1,2,3,4,5}
  local y = j.encode (x)
  local z = j.decode (y)
  t.assertItemsEquals (z, x)
end


TestLZAP = {}

function TestLZAP:test_simple ()
  local lzap = C.lzap
  local text = [[The rain in Spain stays mainly in the plain]] 
  local a = lzap.encode (text)        -- no codes, so returns array of codewords
  t.assertIsTable (a)
  local b = lzap.decode (a) 
  t.assertEquals (b, text)
end

function TestLZAP:test_yabba ()
  local lzap = C.lzap
  local text = [[yabbadabbadabbadoo]] -- another common test string
  local a = lzap.encode (text)        -- no codes, so returns array of codewords
  t.assertIsTable (a)
  local b = lzap.decode (a) 
  t.assertEquals (b, text)
end

function TestLZAP:test_unicode ()
  local lzap = C.lzap
  local text = [[Система ß$¢€]]
  local a = lzap.encode (text)        -- no codes, so returns array of codewords
  t.assertIsTable (a)
  local b = lzap.decode (a) 
  t.assertEquals (b, text)
end

function TestLZAP:test_common_failure ()
  local lzap = C.lzap
  local text = [[aaaaaaaaaaaaaaaaaa]] -- some implementations have a well-known bug
  local a = lzap.encode (text)        -- no codes, so returns array of codewords
  t.assertIsTable (a)
  local b = lzap.decode (a) 
  t.assertEquals (b, text)
end


-- encode/decode round trip with 256 code alphabet codec
function TestLZAP:test_with_codec ()
  local c = codec ()                  -- full-width codec
  local lzap = C.lzap
  local text = [[sir sid eastman easily teases sea sick seals]] 
  local a = lzap.encode (text, c)        -- codec returns single string of byte-pairs
  t.assertIsString (a)
  local b = lzap.decode (a, c) 
  t.assertEquals (b, text)
end

-- encode/decode round trip with JSON alphabet codec
function TestLZAP:test_with_json_codec ()
  local text = [[
The rain it raineth on the just 
And also on the unjust fella;
But chiefly on the just, because
The unjust hath the just’s umbrella.
]]
  text = text: rep(250) 
  local c = codec (codec.json)        -- JSON string codec
  local lzap = C.lzap
  local a = lzap.encode (text, c)        -- codec returns single string of byte-pairs
  t.assertIsString (a)
  local ratio = #text / #a
  t.assertTrue (ratio > 25)    -- should achieve better than 25:1 compression!
  local b = lzap.decode (a, c) 
  t.assertEquals (b, text)
end

-- file I/O

ExtraTests = {}

-- reads, compresses, and writes file, adding .lzo extension
local function test_file (name, comp, codec, outname)
  outname = (outname or name) .. ".lzap"
  local f = io.open (name)
  if not f then error "can't open file" end
  local text = f: read "*a"
  f: close()
  local t0 = timer ()
  local coded = comp.encode (text, codec)
  local t1 = timer()
  local decoded = comp.decode (coded, codec)
  local t2 = timer()
  t.assertEquals (decoded, text)
  local time = "%0.3f, %0.3f (seconds)"
  local ratio = "%0.1f"
  print ('','['..#text..']',name)
  print ('','['..#coded..']', outname)
  print ('',"compression ratio: " .. ratio: format (#text / #coded) ..
                ", times:"..time:format (t1-t0,t2-t1))
  f = io.open (outname, 'wb')
  f: write (coded)
  f: close ()
end


function ExtraTests:test_user_data_json ()
  local name = "user_data.json"
  local comp = C.lzap
  local c = codec (codec.json)
  test_file (name, comp, c, "tests/data/" .. name ..".JSON")
end

function ExtraTests:test_user_data_bin ()
  local name = "user_data.json"
  local comp = C.lzap
  local c = codec ()      -- binary codec
  test_file (name, comp, c, "tests/data/" .. name ..".BINARY")
end


-------------------

if multifile then return end
  
t.LuaUnit.run "-v"

-- extra here
print "extra..."

local N = 0
for a,b in pairs (ExtraTests) do
  print (a)
  b()
  N = N + 1
  print "OK\n"
end

print (N .. " additional tests passed successfully")

-------------------


-----
