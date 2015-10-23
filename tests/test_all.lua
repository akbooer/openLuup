local t = require "luaunit"

multifile = true

require "tests.test_loader"
require "tests.test_devices"
require "tests.test_luup"
require "tests.test_requests"
require "tests.test_rooms"
require "tests.test_scheduler"
require "tests.test_scenes"
require "tests.test_timers"
require "tests.test_logs"
require "tests.test_json"
require "tests.test_xml"
require "tests.test_io"
require "tests.test_userdata"


t.LuaUnit.run "-v" 
