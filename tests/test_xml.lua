local t = require "tests.luaunit"

-- XML module tests

local X = require "openLuup.xml"

local N = 0     -- total test count


--- XML decode validity tests

local function invalid_decode (x, y)
  N = N + 1
  local lua = X.decode (x) .documentElement
  t.assertEquals (lua, nil)
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
  t.assertEquals (p[1][0], "parent")
  local c = p[1]
  t.assertEquals (#c, 3)
  t.assertEquals (p[1].firstChild[1], "major")
  t.assertEquals (p[1].lastChild[1], "minimus")
  local min = p[1][2]
--  local maj = min.previousSibling
--  local mus = min.nextSibling
--  t.assertEquals (min[1], "minor")
--  t.assertEquals (maj[1], "major")
--  t.assertEquals (mus[1], "minimus")
--  t.assertIsNil  (maj.previousSibling)
--  t.assertIsNil  (mus.nextSibling)
--  local g = p[1][-1]
--  t.assertEquals (g[-1][0], "root")
--  t.assertIsNil (g[-1][-1])
--  t.assertEquals (g[0], "grandparent")
end

function TestDOMNavigation:test_xpath_navigation()
  local d = X.decode [[
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
  local c = d.xpath (d.documentElement, "//grandparent/parent/child")
  
  t.assertEquals (#c, 3)
  local maj = c[1]
  local min = c[2]
  local mus = c[3]
  t.assertEquals (min[1], "minor")
  t.assertEquals (maj[1], "major")
  t.assertEquals (mus[1], "minimus")
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
  t.assertEquals (s[1][0], "foo")
  local c = s[1]
  t.assertEquals (#c, 2)
  t.assertEquals (c[1][0], "garp")
  t.assertEquals (c[2][0], "garp")
  t.assertEquals (c[1][1], "bung1")
  t.assertEquals (c[2][1], "bung2")
 end

function TestDecodeValid:test_decode_text_node ()
  local tn = X.decode [[ <text a1='one'>  plain text  </text>]]
  t.assertEquals (tn[1].a1, "one")
  t.assertEquals (tn[1][1], "plain text")    -- note the surrounding spaces are gone
end

function TestDecodeValid:test_decode_simple_self_closing ()
  local a = X.decode "<foo/>"
  t.assertEquals (a[1][0], "foo")
end

function TestDecodeValid:test_decode_self_closing ()
  local a = X.decode [[ <a at="&lt;&gt;&quot;&apos;&amp;" a2='two' /> ]]
  t.assertEquals (a[1].at, [[<>"'&]])
  t.assertEquals (a[1].a2, "two")
end

function TestDecodeValid:test_decode_attributes ()
  local a = X.decode '<a at="&lt;&gt;&quot;&apos;&amp;"></a>'
  t.assertEquals (a[1].at, [[<>"'&]])
end

function TestDecodeValid:test_decode_escapes ()
  local e = X.decode '<a>&lt;&gt;&quot;&apos;&amp;</a>'
  t.assertEquals (e[1][1], [[<>"'&]])
end

function TestDecodeValid:test_mixed_content ()
  local e = X.decode "<a> one <two/> three <four /> five</a>"
  local c = e.documentElement
  -- note that the intervening text is ignored
  t.assertEquals (#c, 2)
  t.assertEquals (c[1][0], "two")
  t.assertEquals (c[2][0], "four")
end


function TestDecodeValid:test_emptytag ()
  local empty
  empty = X.decode "<foo>   </foo>"
  t.assertIsTable (empty)
  t.assertEquals (#empty, 1)
  t.assertEquals (empty[1][0], "foo")
  t.assertEquals (empty[1][1], '')
  --
  empty = X.decode "<foo></foo> <garp></garp>"
  t.assertIsTable (empty)
  t.assertEquals (#empty, 1)
  t.assertEquals (empty[1][0], "foo")
  t.assertEquals (empty[1][1], '')
  t.assertEquals (empty[1][1], '')
end

--- XML encode validity tests

local function valid_encode (lua, v)
  N = N + 1
  local n,m = next (lua)
  local xml = tostring (X.TEST.createElement (n,{m}))
  t.assertIsString (xml)
  t.assertEquals (xml:gsub ("%s+", ' '), v)
end



-- VALID


TestEncodeValid = {}


function TestEncodeValid:test_literals ()
  valid_encode ({["true"] = true},   "<true>true</true> ")
  valid_encode ({["false"] = false},  "<false>false</false> ")
  valid_encode ({["nil"] = nil},    "</> ")
end

function TestEncodeValid:test_numerics ()
  local Inf = "8.88e888"
  valid_encode ({number = 42},           "<number>42</number> ")
end

function TestEncodeValid:test_strings ()
  valid_encode ({string="easy"},       "<string>easy</string> ")
	valid_encode ({ctrl="\n"},           "<ctrl> </ctrl> ")
  valid_encode ({UTF8= "1234 UTF-8 ß$¢€"},  "<UTF8>1234 UTF-8 ß$¢€</UTF8> ")
end

function TestEncodeValid:test_escapes ()
  local a = [[<>"'&]]           -- characters to be escaped
  valid_encode ({escapes=a}, "<escapes>&lt;&gt;&quot;&apos;&amp;</escapes> ")
end

-- Longer round-trip file tests

local function round_trip_ok (x)
  local lua1 = X.decode (x)
  t.assertIsTable (lua1)
  local x2 = tostring (lua1.documentElement)   -- not equal to x, necessarily, because of formatting and sorting
  t.assertIsString (x2)
  local lua2 = X.decode (x2)  -- ...so go round once again
  t.assertIsTable (lua2)
  local x3,msg4 = tostring (lua2.documentElement)  
  t.assertIsString (x3)
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

TestSameNestedTags = {}         -- 2019.04.30  arising from loader error in service files

function TestSameNestedTags:test_same_tags ()
  local x = [[
  <top>
    <middle>
      <nest>
        <name>Nested</name>
      </nest>
      <name>Middle</name>
    </middle>
    <name>Name</name>
  </top>
  ]]
  
  local d = X.decode (x)
  local top = d.documentElement 
  t.assertEquals (top.nodeName, "top")   
  for act in d.xpathIterator (top, "//middle") do
    for _,x in ipairs (act) do 
      end
  end
end



TestEncodeDecode = {}

function TestEncodeDecode:test_round_trip ()
--  round_trip_ok (comprehensive)
end

-------------------

if multifile then return end
  
t.LuaUnit.run "-v"

print ("TOTAL number of tests run = ", N)

--do return end
-------------------

local decode = X.decode
-- TEST

local x = "<a><b><c /><d /><e /></b><b><f /><g /><h /></b></a>"
local d = decode(x)
local y = d.documentElement


for z in  d.nextNode (y, function (x, p) return p == "/a/b" end) do 
  print (z[0], #z)
end

print "---- xpath"

local w = d.xpath (y, "//b" )
for _,z in ipairs(w) do
  print (z[0], #z)
end

print "---- xpathIterator"

for z in d.xpathIterator (y, "//b/*") do
  print (z[0], #z)
end


print "---- xpathIterator"

for z in d.xpathIterator (y, "//*/f") do
  print (z[0], #z)
end

----]]
---------------------

--local pretty = require "pretty"

---- visual round-trip test 
  
--print "-----------"
--local xmlDoc = X.decode(comprehensive)
----print(pretty(xmlDoc))   -- unwise to do this, since multiple sibling links make it appear extensive

--print "-----------"


--local a = X.simplify (xmlDoc.documentElement)
--print(pretty(a))

--print (X.encode (a, "decoded-simplified"))

--print 'done'

----
--[==[
local comprehensive = [[
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
    <attrs a="1" b='two' c = "a'b'c" d = 'd"e"f' ></attrs>
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

--]==] 
---
--local pretty = require "pretty"

--local d = decode (comprehensive)
----print (pretty(d))

----local s = _serialize (d.documentElement, {"hello, world"})
--local s = d.documentElement

--print (s)

--print "---"

--print (pretty {
--    nodeName = s[0],
--    textcontent = s[1],
--    attributes = s,
--    nchild = #s,
--  })

--print "---"
----print (pretty(s))


--for n in s:nextNode () do
--  print ('',n[0])
--end
--print "---"

--local function filter (x,p) print (p) return true end

--for n in s:nextNode (filter) do
--end
--print "---"
