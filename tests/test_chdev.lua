
local t = require "tests.luaunit"

-- openLuup.chdev TESTS

luup = luup or {}   -- luup is not really there.

--
-- DEVICE CREATE
--
local chdev = require "openLuup.chdev"

TestChdevDevice = {}     -- low-level device tests

function TestChdevDevice:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.d0 = chdev.create {
    devNo = 0, 
    device_type = devType, 
    statevariables =
      {
        { service = "myServiceId", variable = "Variable", value = "Value" },
        { service = "anotherSvId", variable = "MoreVars", value = "pi" },
      }
    }
end

function TestChdevDevice:tearDown ()
  self.d0 = nil
end

function TestChdevDevice:test_create ()
  t.assertEquals (type (self.d0), "table")
  t.assertEquals (self.d0.device_type, self.devType)
  local d = self.d0
  
  -- check the values
  t.assertIsNumber  (d.category_num)
  t.assertIsString  (d.description) 
  t.assertIsNumber  (d.device_num_parent)
  t.assertIsString  (d.device_type) 
  t.assertIsBoolean (d.embedded)
  t.assertIsBoolean (d.hidden)
  t.assertIsString  (d.id)
  t.assertIsBoolean (d.invisible) 
  t.assertIsString  (d.ip)
  t.assertIsString  (d.mac)
  t.assertIsString  (d.pass)
  t.assertIsNumber  (d.room_num)
  t.assertIsNumber  (d.subcategory_num)
  t.assertIsString  (d.udn)  
  t.assertIsString  (d.user)    

  -- check all the methods are present:
  t.assertIsFunction (d.attr_get)
  t.assertIsFunction (d.attr_set)
  t.assertIsFunction (d.call_action)
  t.assertIsFunction (d.is_ready)
  t.assertIsFunction (d.supports_service)
  t.assertIsFunction (d.variable_set)
  t.assertIsFunction (d.variable_get)
  t.assertIsFunction (d.version_get)
  
  -- check the tables
  t.assertIsTable (d.attributes)
  t.assertIsTable (d.services)
end

function TestChdevDevice:test_create_with_file ()
  local x = chdev.create {
      devNo = 42, 
      description = "Test", 
      upnp_file = "D_VeraBridge.xml",   -- this file is preloaded in the vfs cache
    };
  t.assertIsTable (x)
  t.assertEquals (x.description, "Test")
  t.assertEquals (x.category_num, 1)
  t.assertEquals (x.device_type, "VeraBridge")
end

function TestChdevDevice:test_created_get ()    -- see if the ones defined initially are there
  --       "myServiceId,Variable=Value \n anotherSvId,MoreVars=pi"
  local a = self.d0:variable_get ("myServiceId", "Variable")
  local b = self.d0:variable_get ("anotherSvId", "MoreVars")
  t.assertEquals (a.value, "Value")
  t.assertEquals (b.value, "pi")  
end

--
-- ATTRIBUTES
--

TestChdevAttributes = {}

function TestChdevAttributes:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.d0 = chdev.create {
      devNo = 0, 
      device_type = devType
    }
end

function TestChdevAttributes:tearDown ()
  self.d0 = nil
end

function TestChdevAttributes:test_nil_get ()
  t.assertEquals (type (self.d0), "table")
  local a = self.d0:attr_get "foo"
  t.assertIsNil (a)
end


function TestChdevAttributes:test_set_get ()
  local val = "42"
  local name = "attr1"
  self.d0:attr_set (name, val)
  local a = self.d0:attr_get (name)
  t.assertEquals (a, val)
end

function TestChdevAttributes:test_multiple_set ()
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

TestChdevVariables = {}

function TestChdevVariables:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.d0 = chdev.create {
      devNo = 0, 
      device_type = devType
    }
end

function TestChdevVariables:tearDown ()
  self.d0 = nil
end

function TestChdevVariables:test_nil_get ()
  local a = self.d0:variable_get ("srv", "name")
  t.assertIsNil (a)
end

function TestChdevVariables:test_set_get ()
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


--
-- OTHER METHODS
--

TestChdevOtherMethods = {}

function TestChdevOtherMethods:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.d0 = chdev.create {
      devNo = 0, 
      device_type = devType
    }
end

function TestChdevOtherMethods:tearDown ()
  self.d0 = nil
end

function TestChdevOtherMethods:test_is_ready ()
  t.assertTrue (self.d0:is_ready())
end

function TestChdevOtherMethods:test_supports_service ()
  local srv = "aService"
  local var = "varname"
  self.d0:variable_set (srv, name, val)
  t.assertTrue  (self.d0:supports_service (srv))
  t.assertFalse (self.d0:supports_service "foo")
end

function TestChdevOtherMethods:test_version ()
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

function TestChdevOtherMethods:test_call_action ()
  local srv = "testService"
  self.d0.services[srv] = {
    actions = {
      action1 = { 
        run = function (lul_device, lul_settings) 
          return true
        end, 
      },
      action2 = { 
        job = function (lul_device, lul_settings, lul_job) 
          return 4, 0     -- job done status
        end, 
      },
    }
  }
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

function TestChdevOtherMethods:test_missing_action ()
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
  t.assertIsTable (return_arguments)
  t.assertEquals (result, 12345)
end

function TestChdevOtherMethods:test_ ()
end

--------------------

if not multifile then t.LuaUnit.run "-v" end

--------------------
