local t = require "tests.luaunit"

-- Device Files module tests

local userdata  = require "openLuup.userdata"

TestUserData = {}

function TestUserData:test_save_load ()
  -- test save
--  local scene = {user_table = function () return {a=1, b= 2, c = "42"} end}
--  local x = {rooms = {"room1", nil, "room3"}, scenes = {scene}}
--  local ok, msg = userdata.save (x, "tests/data/testuserdata.json")
--  t.assertTrue (ok)
--  t.assertIsNil (msg)
  
  --test_load
  
--  local x, msg = userdata.load "tests/testuserdata.json"
--  t.assertIsNil (msg)
--  t.assertIsTable (x)
--  t.assertIsTable (x.scenes)
--  t.assertIsTable (x.rooms)
--  t.assertEquals (#x.rooms, 2)
--  t.assertEquals (x.rooms[2].name, "room3")
--  t.assertEquals (x.scenes[1].c, "42")
end


-------------------

if multifile then return end

t.LuaUnit.run "-v" 

-------------------
