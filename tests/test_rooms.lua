local t = require "tests.luaunit"

-- openLuup.logs TESTS

local room = require "openLuup.rooms"

TestRooms = {}

function TestRooms:setUp ()
end

luup = luup or {rooms = {}, devices = {}, scenes = {}}

  
--Example: http://ip_address:3480/data_request?id=room&action=create&name=Kitchen
function TestRooms:test_room_create ()
  local name = "A curious room name"
  local n = #luup.rooms
  local r = room.create (name)
  local m = #luup.rooms
  t.assertEquals (m, n+1)
  t.assertEquals (r, m)
  t.assertEquals (luup.rooms[m], name)
end

--Example: http://ip_address:3480/data_request?id=room&action=rename&room=5&name=Garage
function TestRooms:test_room_rename ()
  local new_name = "test_room_rename"
  local r = room.create "test_room_name"
  local n = #luup.rooms
  room.rename (r,  new_name)
  local m = #luup.rooms
  t.assertEquals (m, n)
  t.assertEquals (luup.rooms[r], new_name)
end

----Example: http://ip_address:3480/data_request?id=room&action=delete&room=5
function TestRooms:test_room_delete ()
  local r = room.create "room name to be deleted"
  local n = #luup.rooms
  room.delete (r)
  local m = #luup.rooms
  t.assertEquals (m, n-1)  
  t.assertIsNil (luup.rooms[n])
end


---------------------

if multifile then return end
t.LuaUnit.run "-v" 

---------------------

