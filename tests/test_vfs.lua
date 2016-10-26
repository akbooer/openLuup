local t = require "tests.luaunit"

-- virtualfilesystem module tests

local vfs = require "openLuup.virtualfilesystem"


TestVFS = {}


function TestVFS:test_io ()
  local test_string = "this is only a test"

  f = vfs.open ("vfs_test", 'w')
  f:write (test_string)
  f:close ()
  
  f = vfs.open "vfs_test"
  local x = f:read ()  
  f:close ()
  t.assertEquals (x, test_string)
end

function TestVFS:test_open_for_read_fail ()
  local f, m = vfs.open "xyz"
  t.assertIsNil (f)
  t.assertIsString (m)
end

function TestVFS:test_open_for_read_ok ()
  local f, m = vfs.open "index.html"
  t.assertIsTable (f)
  t.assertIsFunction (f.read)
  t.assertIsFunction (f.close)
  t.assertIsNil (m)
end

-------------------

if multifile then return end
  
t.LuaUnit.run "-v"

print ("TOTAL number of tests run = ", N)

-------------------

