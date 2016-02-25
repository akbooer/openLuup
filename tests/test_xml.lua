local t = require "tests.luaunit"

-- XML module tests

local X = require "openLuup.xml"

local N = 0     -- total test count


local D = [[
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:altui:1</deviceType>
    <staticJson>D_ALTUI.json</staticJson> 
    <friendlyName>ALTUI</friendlyName>
    <manufacturer>Amg0</manufacturer>
    <manufacturerURL>http://www.google.fr/</manufacturerURL>
    <modelDescription>AltUI for Vera UI7</modelDescription>
    <modelName>AltUI for Vera UI7</modelName>
    <modelNumber>1</modelNumber>
    <protocol>cr</protocol>
    <handleChildren>0</handleChildren>
  <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:altui:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:altui1</serviceId>
        <controlURL>/upnp/control/ALTUI1</controlURL>
        <eventSubURL>/upnp/event/ALTUI1</eventSubURL>
        <SCPDURL>S_ALTUI.xml</SCPDURL>
      </service>
    </serviceList>
    <implementationList>
      <implementationFile>I_ALTUI.xml</implementationFile>
    </implementationList>
  </device>
</root>
]]

local I = [[
<?xml version="1.0"?>
<implementation>
  <functions>
  </functions>
  <files>L_ALTUI.lua</files>
  <startup>initstatus</startup>
  <actionList>
    <action>
   <serviceId>urn:upnp-org:serviceId:altui1</serviceId>
   <name>SetDebug</name>
    <run>
      setDebugMode(lul_device,lul_settings.newDebugMode)
    </run>
  </action>
  <action>
    <serviceId>urn:upnp-org:serviceId:altui1</serviceId>
    <name>Reset</name>
    <run>
      resetDevice(lul_device,true)
    </run>    
  </action>
  
</actionList>
</implementation>
]]


--- XML decode validity tests

local function invalid (x, y)
  N = N + 1
  local lua, msg = X.decode (x)
  t.assertIsNil (lua)
  t.assertEquals (msg, y) 
end

local function valid (x, v)
  N = N + 1
  local lua, msg = X.decode (x)
  t.assertEquals (lua, v)
  t.assertIsNil (msg) 
end


-- INVALID

TestDecodeInvalid = {}

function TestDecodeInvalid:test_decode ()
  -- invalid code just returns the original string as error message
  invalid ("rubbish", "rubbish")
  invalid ("<foo", "<foo")
  invalid ("<foo></bung>", "<foo></bung>")
end


-- VALID

TestDecodeValid = {}

function TestDecodeValid:test_decode ()
  valid ('<foo a="b">garp</foo>',  {foo="garp"})
  valid ([[
    <foo>
      <garp>bung1</garp>
      <garp>bung2</garp>
    </foo>
    ]],  {foo={garp= {"bung1","bung2"}}})
  valid ('<a>&lt;&gt;&quot;&apos;&amp;</a>', {a = [[<>"'&]]})
end


--- XML encode validity tests

local function invalid (x)
  N = N + 1
  local lua, msg = X.encode (x)
  t.assertFalse (lua)
  t.assertIsString (msg) 
end


local function valid (lua, v)
  N = N + 1
  local xml, msg = X.encode (lua)
  t.assertIsString (xml)
  t.assertEquals (xml:gsub ("%s+", ' '), v)
  t.assertIsNil (msg) 
end


-- INVALID

TestEncodeInvalid = {}

function TestEncodeInvalid:test_encode ()
  invalid "a string"
  invalid (42)
  invalid (true)
  invalid (function() end)
  invalid {"hello"}
end


-- VALID


TestEncodeValid = {}


--function TestEncodeValid:test_literals ()
--  valid (true,   "true")
--  valid (false,  "false")
--  valid (nil,    'null')
--end

function TestEncodeValid:test_numerics ()
  local Inf = "8.88e888"
  valid ({number = 42},           " <number>42</number> ")
end

function TestEncodeValid:test_strings ()
  valid ({string="easy"},       " <string>easy</string> ")
	valid ({ctrl="\n"},           " <ctrl> </ctrl> ")
  -- need to check the special conversion characters
  valid ({UTF8= "1234 UTF-8 ß$¢€"},  " <UTF8>1234 UTF-8 ß$¢€</UTF8> ")
end

function TestEncodeValid:test_tables ()
--  valid ({1, nil, 3},     '[1,null,3]')
  -- next is tricky because of sorting and pretty printing
--  valid ({ array = {1,2,3}, string = "is a str", num = 42, boolean = true},
--              '{"array":[1,2,3],"string":"is a str","num":42,"boolean":true}')
end

-- Longer round-trip file tests

local function round_trip_ok (x)
  local lua1, msg = X.decode (x)
  t.assertIsTable (lua1)
  t.assertIsNil (msg)
  local x2,msg2 = X.encode (lua1)   -- not equal to x, necessary, because of formatting and sorting
  t.assertIsString (x2)
  t.assertIsNil (msg)
  local lua2, msg3 = X.decode (x2)  -- ...so go round once again
  t.assertIsTable (lua2)
  t.assertIsNil (msg3)
  local x3,msg4 = X.encode (lua2)  
  t.assertIsString (x3)
  t.assertIsNil (msg4)
  t.assertEquals (x3, x2)           -- should be the same this time around
end

TestEncodeDecode = {}

function TestEncodeDecode:test_round_trip ()
  round_trip_ok (I)
  round_trip_ok (D)
  round_trip_ok "<a>&lt;&gt;&quot;&apos;&amp;</a>"

end
-------------------

if multifile then return end
  
t.LuaUnit.run "-v"

print ("TOTAL number of tests run = ", N)

-------------------

-- visual round-trip test 
  
print "----- encode(decode(...)) -----"
print "Round-trip XML:"
print ((X.encode(X.decode(I))))

print "-----------"
local a = [[<>"'&]]
local b = X.encode {a = a}
local c = X.decode (b)

print (a)
print (b)
print (c.a)

print 'done'