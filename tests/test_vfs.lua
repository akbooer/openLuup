local t = require "tests.luaunit"

-- virtualfilesystem module tests

local vfs = require "openLuup.virtualfilesystem"


TestVFS = {}


function TestVFS.test_io ()
  local test_string = "this is only a test"
  local f = vfs.open "vfs_test"
  local no = f:read ()
  t.assertNil (no)
  f:close ()
  
  f = vfs.open "vfs_test"
  f:write (test_string)
  f:close ()
  
  f = vfs.open "vfs_test"
  local x = f:read ()  
  f:close ()
  t.assertEquals (x, test_string)
end


-------------------

if multifile then return end
  
t.LuaUnit.run "-v"

print ("TOTAL number of tests run = ", N)

-------------------

