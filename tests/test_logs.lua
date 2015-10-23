local t = require "luaunit"

-- openLuup.logs TESTS

local log = require "openLuup.logs"

TestLogs = {}

function TestLogs:setUp ()
end

function TestLogs:test_openLuup_log ()
  local log = log.openLuup_logger {name = "tests/Test.log", versions = 3, lines =20}.send
  for i = 1,50 do
    log (i)
  end
end


function TestLogs:test_altui_slog ()
  local alt = log.altui_logger {name = "tests/TestALT.log", lines =20}
  local slog = alt.scene
  
  local scn = {id = 42, name = "foo"}         -- log a scene running
  local s = slog (scn)
  log.altui_scene (scn)     -- check it works to the real location too
  
  local scene = "%d*\t(%d*/%d*/%d*%s%d*:%d*:%d*.%d*).*Scene::RunScene running %d+ (.*) <.*"
  local a,b = s: match (scene)
  t.assertIsString (a)
  t.assertIsString (b)
  t.assertEquals (b, "foo")
end

function TestLogs:test_altui_vlog ()
  local alt = log.altui_logger {name = "tests/TestALT.log", lines =20}
  local vlog = alt.variable

  local var = {dev = 42, srv = "myService", name = "foo", old = nil, value = 123, watchers = {1,2,3}}
  local v = vlog (var)
  log.altui_variable (var)     -- check it works to the real location too
  
  -- first 'grep' pass:
  local n = v:match "Device_Variable::m_szValue_set device: 42.*;1m(.+)\027"
  t.assertEquals (n, "foo")
  
  -- second 'JavaScript' pass:
  local variable = "%d*\t(%d*/%d*%/%d*%s%d*:%d*:%d*.%d*).*was: (.*) now: (.*) #.*"
  local a,b,c = v: match (variable)
  t.assertIsString (a)
  t.assertIsString (b)
  t.assertIsString (c)
  t.assertEquals (b, "MISSING")
  t.assertEquals (c, "123")
end


function TestLogs:test_ ()
end


---------------------

if multifile then return end
t.LuaUnit.run "-v" 

---------------------

