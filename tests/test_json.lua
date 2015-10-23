local t = require "luaunit"

-- JSON module tests

local msg_check = false
local warning_check = false
local invalid_check = false

J = require 'openLuup.json'
--J = require 'dkjson'

--TestDecode = require 'dk-json'

--require 'cf-json'
--TestDecode = json
--
--require 'cm-json'
--TestDecode = _G["cm-json"]

--require 'sb-json'
--TestDecode = {decode = Json.Decode, encode = Json.Encode}

--require "jf-json"
--TestDecode = JSON
--JSON:decode(raw_json_text)	-- all wrong at the moment

--function J.decode (...)
--	a,b,c,d = pcall (TestDecode.decode, ...)
--	if a then return b,d else return a,b end
--end
--
--function J.encode (...)
--	a,b,c,d = pcall (TestDecode.encode, ...)
--	if a then return b,d else return a,b end
--end
--
local N = 0

--- JSON decode validity tests

local function invalid (j)
  N = N + 1
  local lua, msg = J.decode (j)
  t.assertIsNil (lua)
  if msg_check then t.assertIsString (msg) end
end

local function warning (j, v)
  if not warning_check then return end
  N = N + 1
  local lua, msg = J.decode (j)
  t.assertEquals (lua, v)
  if msg_check then t.assertIsString (msg) end
end

local function valid (j, v)
  N = N + 1
  local lua, msg = J.decode (j)
  t.assertEquals (lua, v)
  if msg_check then t.assertIsNil (msg) end
end

-- INVALID

DecodeInvalid = {}

function DecodeInvalid:test_literals ()
  invalid "foo"
  invalid " "
--  invalid {}
--  invalid (false)
--  invalid (42)
end

function DecodeInvalid:test_numerics ()
  invalid "E"
  invalid "+"
  invalid "-"
  invalid "+4"
  invalid "+-4"
  invalid "inf"
end

function DecodeInvalid:test_strings ()
  invalid ' "no end in sight'                 -- unclosed string
  invalid ' "also no end \\'                  -- ditto
  invalid ' "wrong = \\udefg"'                -- should be numeric code
  invalid ' "looks ok but is\'nt \\\"  '
end

function DecodeInvalid:test_tables ()
  invalid '[{true}]'
  invalid '[1, , 3]'
  invalid '[1, "two":2, 3 ] '
  invalid '{"a" :1, 2}'
  invalid '[ 42 }'
  invalid '{"a": 7]'
  invalid '{"a"=7}'
end


-- WARNING

TestDecodeWarning = {}

function TestDecodeWarning:test_literals ()
	warning ("true false", true)
end

function TestDecodeWarning:test_numerics ()
	warning ("33,4" , 33)
end

function TestDecodeWarning:test_strings ()
	warning ('"two" "strings"', "two")
end

function TestDecodeWarning:test_tables ()
  warning ('{} {}', {}) 
end

-- VALID

TestDecodeValid = {}

function TestDecodeValid:test_literals ()
  valid ('true',  true)
  valid ('false', false)
  valid ('null',  nil)
end

function TestDecodeValid:test_numerics ()
  local Inf = 8.88e888      -- my Json's representation of infinity
	valid ("0",           0)
	valid ("-0",          0)
	valid ("42",          42)
	valid ("3.14159",     3.14159)
	valid ("60328.924",   60328.924)
	valid ("-7",          -7)
	valid ("3e-6",        0.000003)
	valid ("2.718E+5",    2.718E+5)
	valid ("-1e-999",     -0)
	valid ("1.0e-789",    0)
	valid ("9.99e999",    Inf)
	valid ("-1.23e+456",  -Inf)
end

function TestDecodeValid:test_strings ()
	valid ('""',                    '')
	valid ('" " ',                  ' ')
	valid ('"ok string"',           'ok string')
	valid ('" also \\" ok"',        ' also " ok')
	valid ('"Ice\\/Snow"',          'Ice/Snow')
	valid ('"Sébastien"',           'Sébastien')
	valid ('"a = \\u0061 = \097"',  'a = a = a')
	valid ('"\161\162\163"',        '\161\162\163')
	valid ('"should be ok \\\\"',   'should be ok \\')
  valid ('"1234 UTF-8 ß$¢€"',     '1234 UTF-8 ß$¢€')
	valid ('" \\" \\/ \\! \t "',     ' " / ! \t ')
	valid ('"\\c\\d\\e...\\x\\y\\z"',                 'cde...xyz')
  valid ('"quoted solidus \\/ ok?"',                'quoted solidus / ok?')
	valid ('"tricky double backslash \\\\\\\\"',      'tricky double backslash \\\\')
  valid ('"1234 UTF-8 ß$¢€"',    '1234 UTF-8 ß$¢€')
  valid ('"Система безопасности и обновлени"', "Система безопасности и обновлени") 
	end

function TestDecodeValid:test_tables ()
	valid ("[]",                {})
	valid ("[] ",               {})
	valid ("{}",                {})
	valid ("{} ",               {})
	valid (" [42] ",            {42})
	valid ("[true]",            {true})
	valid (" [[true]]",         {{true}})
	valid ("[1, 2, 3 ] ",       {1,2,3})
	valid ('[null, 1, null]',   {nil, 1, nil})
	valid ('[{}]',              {{}})
  valid ('[[],{}]',           {{},{}})
	valid ('{"a" :1, "b" : 2}',             {a=1, b=2})
	valid ('{"a":[], "b" : [] } ',          {a={}, b={}})
	valid ('{"Ice\\/Snow":"Ice\\/Snow"} ',  {["Ice/Snow"] = "Ice/Snow"})
	valid ('["one","two","three","four"] ', {"one","two","three","four"})
	valid ('["one", true, 3, false]',       {"one", true, 3, false})
end


--- JSON encode validity tests

local function invalid (j)
  N = N + 1
  local lua, msg = J.decode (j)
  t.assertIsNil (lua)
  if msg_check then t.assertIsString (msg) end
end

local function valid (lua, v)
  N = N + 1
  local json, msg = J.encode (lua)
  t.assertEquals (json, v)
  if msg_check then t.assertIsNil (msg) end
end



EncodeInvalid = {}


function EncodeInvalid:test_literals ()
  invalid (function () end)                   -- JSON can't serialise functions
end

function EncodeInvalid:test_tables ()
  local circular = {}
  circular[1] = circular  invalid {[0] = 1}
  invalid (circular)
  invalid {[function () end] = true}
  invalid {[1]='a',a=1}
end


TestEncodeValid = {}


function TestEncodeValid:test_literals ()
  valid (true,   "true")
  valid (false,  "false")
  valid (nil,    'null')
end

function TestEncodeValid:test_numerics ()
  local Inf = "8.88e888"
  valid (0,           "0")
  valid (-0,          "-0")
  valid (1,           "1")
  valid (-1,          "-1")
  valid (1.2345,      "1.2345")
  valid (1.23e45,     "1.23e+45")
  valid (-33e-33,     "-3.3e-32")
--	valid (math.huge,     Inf)
--	valid (8.88e888,      Inf)
--	valid (-math.huge,   '-'..Inf)
	valid (0/0,           "null")
end

function TestEncodeValid:test_strings ()
  valid ("easy",                '"easy"')
--	valid ("solidus / ok",        '"solidus \\/ ok"')
	valid ("double escape \\\\",  '"double escape \\\\\\\\"')
	valid ("control: \014 14",    '"control: \\u000e 14"')
  valid ( "1234 UTF-8 ß$¢€",    '"1234 UTF-8 ß$¢€"')
  valid ("Система безопасности и обновлени", '"Система безопасности и обновлени"')
--	valid ("weird:\\u0000\a\bcde\fghijklm\nopq\rs\tu\vwxy\z\3\15\123 \\ \" \' /\125" , '')
end

function TestEncodeValid:test_tables ()
--  valid ({1, nil, 3},     '[1,null,3]')
  -- next is tricky because of sorting and pretty printing
--  valid ({ array = {1,2,3}, string = "is a str", num = 42, boolean = true},
--              '{"array":[1,2,3],"string":"is a str","num":42,"boolean":true}')
end


-------------------

if invalid_check then
  TestDecodeInvalid = DecodeInvalid
  TestEncodeInvalid = EncodeInvalid
end



-------------------

if multifile then return else t.LuaUnit.run "-v" end

print ("TOTAL number of tests run = ", N)

-------------------

print '\nJSON File Tests---------------\n\n'


json_files = 
	{
		'netatmo.json',
		'dataMineConfig.json',
		'user_data.json',
	}

local t0,t1
local de,ee
local lua,json, original

for _,fn in ipairs (json_files) do
	local f = io.open ('json/'..fn,'r')
	if f then
		json = f:read ('*a')
		f: close ()
		print ('\n'..fn..': '..#json/1e3 ..' kB')
		t0 = os.clock()
		lua,de = J.decode(json)
		t1 = os.clock()
		print ('','decode time = '.. (t1-t0)*1000 ..' mS' )
		print ('','decode status = ', de or 'OK')
		t0 = os.clock()
		json, ee = J.encode(lua)
		t1 = os.clock()
		print ('','encode kB = '..#json/1000)
		print ('','encode time = '.. (t1-t0)*1000 ..' mS' )
		print ('','encode status = ', ee or 'OK')
		if not de or ee then
			l2 = J.decode (json)
			j2 = J.encode (l2)
			if j2 ~= json then print ('round trip encode/decode mismatch ['..#json..' / '..#j2..']')
				else print ('round trip encode/decode match OK ['..#json..']')
			end
			if json == j2 then print 'YES!!!' 
			end
		end
	end
end
print '\ndone'

--------------------
