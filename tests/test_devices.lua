
local t = require "tests.luaunit"

-- openLuup.device TESTS

--
-- DEVICE CREATE
--
local d = require "openLuup.devices"

TestDevice = {}     -- low-level device tests

function TestDevice:setUp ()
  self.d0 = d.new (0)
  self.d0:variable_set ("myServiceId","Variable", "Value")
  self.d0:variable_set ("anotherSvId","MoreVars", "pi")
end

function TestDevice:tearDown ()
  self.d0 = nil
end

function TestDevice:test_new ()
  t.assertEquals (type (self.d0), "table")
  local d = self.d0
 
  -- check all the methods are present:
  t.assertIsFunction (d.attr_get)
  t.assertIsFunction (d.attr_set)
  
  t.assertIsFunction (d.action_set)
  t.assertIsFunction (d.call_action)
  t.assertIsFunction (d.variable_set)
  t.assertIsFunction (d.variable_get)
  t.assertIsFunction (d.version_get)
  
  -- check the tables
  t.assertIsTable (d.attributes)
  t.assertIsTable (d.services)
end


function TestDevice:test_created_get ()    -- see if the ones defined initially are there
  local a = self.d0:variable_get ("myServiceId", "Variable")
  local b = self.d0:variable_get ("anotherSvId", "MoreVars")
  t.assertEquals (a.value, "Value")
  t.assertEquals (b.value, "pi")  
end

--
-- ATTRIBUTES
--

TestAttributes = {}

function TestAttributes:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.d0 = d.new (0)
end

function TestAttributes:tearDown ()
  self.d0 = nil
end

function TestAttributes:test_nil_get ()
  t.assertEquals (type (self.d0), "table")
  local a = self.d0:attr_get "foo"
  t.assertIsNil (a)
end


function TestAttributes:test_set_get ()
  local val = "42"
  local name = "attr1"
  self.d0:attr_set (name, val)
  local a = self.d0:attr_get (name)
  t.assertEquals (a, val)
end

function TestAttributes:test_numeric_set_get ()
  local val = 1234
  local name = "attr1"
  self.d0:attr_set (name, val)
  local a = self.d0:attr_get (name)
  t.assertEquals (type(a), "number")
  t.assertEquals (a, val)
end

function TestAttributes:test_multiple_set ()
  local val1 = "42"
  local val2 = "BBB"
  local name1 = "attr1"
  local name2 = "attr2"
  local tab = {[name1] = val1, [name2] = val2}
  self.d0:attr_set (tab)
  local a1 = self.d0:attr_get (name1)
  local a2 = self.d0:attr_get (name2)
  t.assertEquals (a1, val1)
  t.assertEquals (a2, val2)
end


--
-- VARIABLES
--

TestVariables = {}

function TestVariables:setUp ()
  self.d0 = d.new (0)
end

function TestVariables:tearDown ()
  self.d0 = nil
end

function TestVariables:test_nil_get ()
  local a = self.d0:variable_get ("srv", "name")
  t.assertIsNil (a)
end

function TestVariables:test_set_get ()
  local val = "42"
  local srv = "myService"
  local name = "var1"
  self.d0:variable_set (srv, name, val)
  local a = self.d0:variable_get (srv, name)
  t.assertEquals (a.value, val)
  t.assertEquals (a.name, name)
  t.assertEquals (a.old, "EMPTY")
  t.assertEquals (a.srv, srv)
  t.assertEquals (a.dev, 0)
  t.assertIsNumber (a.version)
  t.assertIsNumber (a.time)
end


function TestVariables:test_watch ()
  local val = "42"
  local srv = "myService"
  local name = "var1"
  self.d0:variable_set (srv, name, val)
  local v = d.variable_watch (self.d0, my_watch, srv, name) 
  local a = self.d0:variable_get (srv, name)
  t.assertEquals (a.value, val)
  t.assertEquals (a.name, name)
  t.assertEquals (a.old, "EMPTY")
  t.assertNotNil (a.version)
  t.assertNotNil (a.time)
  local v = d.variable_watch (self.d0, my_watch, srv, "foo")   -- wrong variable
  t.assertNil (v)
  local v = d.variable_watch (self.d0, my_watch, "foo", name)  -- wrong service
  t.assertNil (v)
end

function my_watch ()
  -- won't actually be called since scheduler is not running
end

--
-- OTHER METHODS
--

TestOtherMethods = {}

function TestOtherMethods:setUp ()
  self.d0 = d.new (0)
end

function TestOtherMethods:tearDown ()
  self.d0 = nil
end

function TestOtherMethods:test_version ()
  local v1 = self.d0:version_get ()
  t.assertIsNumber (v1)
  local val = "42"
  local srv = "myService"
  local name = "var1"
  local var = self.d0:variable_set (srv, name, val)   -- change a variable
  local v2 = self.d0:version_get ()  
  t.assertTrue (v2 > v1)                              -- check version number increments
  t.assertEquals (var.version, v2)                    -- and that variable has same version
 end

--
-- ACTIONS
--

TestDeviceActions = {}

function TestDeviceActions:setUp ()
  self.d0 = d.new (0)

-- add an action or two
--

local action1 = {
        run = function (lul_device, lul_settings) 
          return true
        end, 
      }

local action2 = {
        job = function (lul_device, lul_settings, lul_job) 
          return 4, 0     -- job done status
        end, 
      }
 
self.d0:action_set ( "testService", "action1", action1)
self.d0:action_set ( "testService", "action2", action2)

end

function TestDeviceActions:tearDown ()
  self.d0 = nil
end

function TestDeviceActions:test_call_action ()
  local srv = "testService"
  local error, error_msg, jobNo, return_arguments = self.d0:call_action (srv, "action1", {})
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertEquals (jobNo, 0)     -- this is a <run> tag, no job
  t.assertIsTable (return_arguments)

  error, error_msg, jobNo, return_arguments = self.d0:call_action (srv, "action2", {})
  t.assertEquals (error, 0)
  t.assertIsNumber (jobNo)
  t.assertNotEquals (jobNo, 0)     -- this is a <job> tag, so job number returned
  t.assertIsTable (return_arguments)
end

function TestDeviceActions:test_missing_action_handler ()
  local result
  local function missing ()
    return { 
      run = function (lul_device, lul_settings) 
        result = lul_settings.value
        return true
      end 
    }
  end
  self.d0:action_callback (missing)
  local error, error_msg, jobNo, return_arguments = self.d0:call_action ("garp", "foo", {value=12345})
  t.assertEquals (error, 0)
  t.assertEquals (error_msg, '')
  t.assertEquals (jobNo, 0)
  t.assertIsTable (return_arguments)
  t.assertEquals (result, 12345)
end

function TestDeviceActions:test_missing_service ()
  local e,m,j,a = self.d0:call_action ("foo", "garp", {}, 4321)
  t.assertEquals (e, 401)
  t.assertEquals (m, "Invalid Service")
  t.assertEquals (j, 0)
  t.assertIsTable (a)
end

function TestDeviceActions:test_missing_action ()
  local e,m,j,a = self.d0:call_action ("testService", "garp", {}, 4321)
  t.assertEquals (e, 501)
  t.assertEquals (m, "No implementation")
  t.assertEquals (j, 0)
  t.assertIsTable (a)
end

--------------------

if not multifile then t.LuaUnit.run "-v" end

--------------------
