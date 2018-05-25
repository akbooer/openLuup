local t = require "tests.luaunit"

multifile = true

require "tests.test_loader"
require "tests.test_devices"
require "tests.test_gateway"
require "tests.test_luup"
require "tests.test_requests"
require "tests.test_rooms"
require "tests.test_server"
--require "tests.test_scheduler"
require "tests.test_scenes"
require "tests.test_timers"
require "tests.test_logs"
require "tests.test_json"
require "tests.test_xml"
require "tests.test_io"
require "tests.test_userdata"
require "tests.test_chdev"
require "tests.test_vfs"
require "tests.test_compression"

t.LuaUnit.run "-v" 
