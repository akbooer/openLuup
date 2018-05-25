local t = require "tests.luaunit"

-- XML module tests

local X = require "openLuup.xml"

local N = 0     -- total test count


--- XML decode validity tests

local function invalid_decode (x, y)
  N = N + 1
  local lua = X.decode (x)
  t.assertEquals (lua, y)     -- totally invalid string is just returned unaltered (actually, unescaped)
end


-- INVALID

TestDecodeInvalid = {}

function TestDecodeInvalid:test_decode ()
  -- invalid code just returns empty table
  invalid_decode ("rubbish", {})
  invalid_decode ("<foo", {})
  invalid_decode ("<foo></bung>", {})
  invalid_decode ("&gt;", {})
end


-- VALID

TestDOMNavigation = {}

function TestDOMNavigation:test_navigation_links()
  local x = X.decode [[
  <root>
    <grandparent>
      <parent>
        <child>major</child>
        <child>minor</child>
        <child>minimus</child>
      </parent>
    </grandparent>
  </root>
  ]] .documentElement
  local p = x:getElementsByTagName "parent"
  t.assertIsTable (p)
  t.assertEquals (#p, 1)
  t.assertEquals (p[1].nodeName, "parent")
  local g = p[1].parentNode
  t.assertEquals (g.parentNode.nodeName, "root")
  t.assertIsNil (g.parentNode.parentNode)
  t.assertEquals (g.nodeName, "grandparent")
  local c = p[1].childNodes
  t.assertEquals (#c, 3)
  local min = p[1].childNodes[2]
  local maj = min.previousSibling
  local mus = min.nextSibling
  t.assertEquals (min.nodeValue, "minor")
  t.assertEquals (maj.nodeValue, "major")
  t.assertEquals (mus.nodeValue, "minimus")
  t.assertIsNil  (maj.previousSibling)
  t.assertIsNil  (mus.nextSibling)
  t.assertEquals (p[1].firstChild.nodeValue, "major")
  t.assertEquals (p[1].lastChild.nodeValue, "minimus")
end

function TestDOMNavigation:test_xpath_navigation()
  local x = X.decode [[
  <root>
    <grandparent>
      <parent>
        <child>major</child>
        <child>minor</child>
        <child>minimus</child>
      </parent>
    </grandparent>
  </root>
  ]]
  local c = x.documentElement:xpath "//grandparent/parent/child"
  
  local pretty = require "pretty"
  print (pretty(c))
  t.assertEquals (#c, 3)
  local maj = c[1]
  local min = c[2]
  local mus = c[3]
  t.assertEquals (min.nodeValue, "minor")
  t.assertEquals (maj.nodeValue, "major")
  t.assertEquals (mus.nodeValue, "minimus")
end


TestDecodeValid = {}

function TestDecodeValid:test_decode_simple ()
  local s = X.decode [[
    <foo>
      <garp>bung1</garp>
      <garp>bung2</garp>
    </foo>
    ]]
  
  t.assertIsTable (s)
  t.assertEquals (#s, 1)
  t.assertEquals (s[1].nodeName, "foo")
  local c = s[1].childNodes
  t.assertEquals (#c, 2)
  t.assertEquals (c[1].nodeName, "garp")
  t.assertEquals (c[2].nodeName, "garp")
  t.assertEquals (c[1].nodeValue, "bung1")
  t.assertEquals (c[2].nodeValue, "bung2")
 end

function TestDecodeValid:test_decode_text_node ()
  local tn = X.decode [[ <text a1='one'>  plain text  </text>]]
  t.assertEquals (tn[1].attributes.a1, "one")
  t.assertEquals (tn[1].nodeValue, "plain text")    -- note the surrounding spaces are gone
end

function TestDecodeValid:test_decode_simple_self_closing ()
  local a = X.decode "<foo/>"
  t.assertEquals (a[1].nodeName, "foo")
end

function TestDecodeValid:test_decode_self_closing ()
  local a = X.decode [[ <a at="&lt;&gt;&quot;&apos;&amp;" a2='two' /> ]]
  t.assertEquals (a[1].attributes.at, [[<>"'&]])
  t.assertEquals (a[1].attributes.a2, "two")
end

function TestDecodeValid:test_decode_attributes ()
  local a = X.decode '<a at="&lt;&gt;&quot;&apos;&amp;"></a>'
  t.assertEquals (a[1].attributes.at, [[<>"'&]])
end

function TestDecodeValid:test_decode_escapes ()
  local e = X.decode '<a>&lt;&gt;&quot;&apos;&amp;</a>'
  t.assertEquals (e[1].nodeValue, [[<>"'&]])
end

function TestDecodeValid:test_mixed_content ()
  local e = X.decode "<a> one <two/> three <four /> five</a>"
  local c = e.documentElement.childNodes
  -- note that the intervening text is ignored
  t.assertEquals (#c, 2)
  t.assertEquals (c[1].nodeName, "two")
  t.assertEquals (c[2].nodeName, "four")
end


function TestDecodeValid:test_emptytag ()
  local empty
  empty = X.decode "<foo>   </foo>"
  t.assertIsTable (empty)
  t.assertEquals (#empty, 1)
  t.assertEquals (empty[1].nodeName, "foo")
  t.assertIsNil (empty[1].nodeValue)        -- NB: empty strings have a nil value
  --
  empty = X.decode "<foo></foo> <garp></garp>"
  t.assertIsTable (empty)
  t.assertEquals (#empty, 2)
  t.assertEquals (empty[1].nodeName, "foo")
  t.assertIsNil (empty[1].nodeValue)        -- NB: empty strings have a nil value
  t.assertEquals (empty[2].nodeName, "garp")
  t.assertIsNil (empty[2].nodeValue)        -- NB: empty strings have a nil value
end

--- XML encode validity tests

local function invalid_encode (x)
  N = N + 1
  local lua, msg = X.encode (x)
  t.assertFalse (lua)
  t.assertIsString (msg) 
end


local function valid_encode (lua, v)
  N = N + 1
  local xml, msg = X.encode (lua)
  t.assertIsNil (msg) 
  t.assertIsString (xml)
  t.assertEquals (xml:gsub ("%s+", ' '), v)
end


-- INVALID

TestEncodeInvalid = {}

function TestEncodeInvalid:test_encode ()
  invalid_encode "a string"
  invalid_encode (42)
  invalid_encode (true)
  invalid_encode (function() end)
  invalid_encode {"hello"}
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
  valid_encode ({number = 42},           " <number>42</number> ")
end

function TestEncodeValid:test_strings ()
  valid_encode ({string="easy"},       " <string>easy</string> ")
	valid_encode ({ctrl="\n"},           " <ctrl> </ctrl> ")
  valid_encode ({UTF8= "1234 UTF-8 ß$¢€"},  " <UTF8>1234 UTF-8 ß$¢€</UTF8> ")
end

function TestEncodeValid:test_escapes ()
  local a = [[<>"'&]]           -- characters to be escaped
  local b,c = X.encode {escapes=a}
  t.assertIsNil (c)
  t.assertEquals (b: match "^%s*(.-)%s*$", "<escapes>&lt;&gt;&quot;&apos;&amp;</escapes>")
end

function TestEncodeValid:test_tables ()
--  valid ({foo = {1, nil, 3}},     '[1,null,3]')
-- next is tricky because of sorting and pretty printing
--  valid ({ array = {1,2,3}, string = "is a str", num = 42, boolean = true},
--              '{"array":[1,2,3],"string":"is a str","num":42,"boolean":true}')
end

-- Longer round-trip file tests

local function round_trip_ok (x)
  local lua1 = X.decode (x)
  t.assertIsTable (lua1)
  local x2,msg2 = X.encode (lua1)   -- not equal to x, necessarily, because of formatting and sorting
  t.assertIsString (x2)
  t.assertIsNil (msg2)
  local lua2, msg3 = X.decode (x2)  -- ...so go round once again
  t.assertIsTable (lua2)
  t.assertIsNil (msg3)
  local x3,msg4 = X.encode (lua2)  
  t.assertIsString (x3)
  t.assertIsNil (msg4)
  t.assertEquals (x3, x2)           -- should be the same this time around
end


local comprehensive = [[
<?xml version="1.0"?>
<test>
  <!-- this is a comment -->
  
  <!-- simple elements -->
  <simple>
    <empty_selfclosing />
    <empty_element>  </empty_element>
    <single_item> just the one </single_item>
    <multi_line>the rain...
...in Spain</multi_line>
  <escapes>&lt;&gt;&quot;&apos;&amp;</escapes>
  </simple>
  
  <!-- elements with attributes and fancy quoted values -->
  <with_attributes>
    <self_closing a="1" b='two' c = "a'b'c" d = 'd"e"f' />
    <attributes a="1" b='two' c = "a'b'c" d = 'd"e"f' ></attributes>
    <single a="single attribute"></single>
    <escaped_attr x="&amp;" y = "&gt;&lt;">escaped attributes</escaped_attr>
  </with_attributes>
  
  <!-- element with nested elements -->
  <nested_elements>
    <single_nest><x>level 1</x></single_nest>
    <normal_element>
      <a>1</a> 
      <b>two</b> 
      <c>a&apos;b&apos;c</c> 
      <d>s&quot;e&quot;f</d>
    </normal_element>
    <multiple_tags>
      <y>
        <x>one</x>
        <x>two</x>
        <x>three</x>
      </y>
    </multiple_tags>
    <multiple_tags_with_tags>
      <y> <x>one</x> </y>
      <y> <x>1</x> <x>2</x> </y>
      <y> <x>un</x> <x>deux</x> <x>trois</x> </y>
    </multiple_tags_with_tags>
    <multiple_tags_with_attr a1="A" a2 = "B">
      <x>one</x>
      <x>two</x>
      <x>three</x>
    </multiple_tags_with_attr>
  </nested_elements>
  
  <!-- element with both attributes and nested elements -->
  <nested_and_attr>
    <mixture a="1" b='two'>
      <c attr_c="&amp;">a&apos;b&apos;c</c> 
      <d>s&quot;e&quot;f</d>
    </mixture>
  </nested_and_attr>
</test>
]]


TestEncodeDecode = {}

--function TestEncodeDecode:test_round_trip ()
--  round_trip_ok (comprehensive)
--end


-------------------

if multifile then return end
  
t.LuaUnit.run "-v"

print ("TOTAL number of tests run = ", N)

-------------------

local pretty = require "pretty"

-- visual round-trip test 
  
print "-----------"
local xmlDoc = X.decode(comprehensive)
print(pretty(xmlDoc))   -- unwise to do this, since multple sibling links make it appear extensive

print "-----------"


print 'done'