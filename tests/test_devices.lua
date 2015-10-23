
local t = require "luaunit"

-- openLuup.device TESTS

--
-- DEVICE CREATE
--
local d = require "openLuup.devices"

TestDevice = {}     -- low-level device tests

function TestDevice:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
-- create (devNo, device_type, internal_id, description, upnp_file, upnp_impl, ip, mac, hidden, invisible, parent, room, pluginnum, statevariables, ...)
  self.d0 = d.create (0, devType, 
    internal_id, description, upnp_file, upnp_impl, ip, mac, hidden, invisible, parent, room, pluginnum,
    [[
      myServiceId,Variable=Value
      anotherSvId,MoreVars=pi
    ]]
  )
end

function TestDevice:tearDown ()
  self.d0 = nil
end

----devices[0] = d0
--devices[1] = d.create (1, '', '', "ZWave", "D_ZWaveNetwork.xml", nil, nil, nil, nil, invisible)
--devices[2] = d.create (2, '', '', "_SceneController", "D_SceneController1.xml", nil, nil, nil, nil, invisible)

--devices[3] = d.create (3, '', "DataYours", "DataYours", "D_DataYours7.xml")        -- create the device
--devices[4] = d.create (4, '', "Arduino", "Arduino", "D_Arduino1.xml")        -- create the device

function TestDevice:test_create ()
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
  t.assertIsNil     (d.udn)               -- we don't do UDNs
  t.assertIsString  (d.user)    

  -- check all the methods are present:
  t.assertIsFunction (d.attr_get)
  t.assertIsFunction (d.attr_set)
  t.assertIsFunction (d.call_action)
  t.assertIsFunction (d.is_ready)
  t.assertIsFunction (d.supports_service)
  t.assertIsFunction (d.variable_set)
  t.assertIsFunction (d.variable_get)
  t.assertIsFunction (d.variable_watch)
  t.assertIsFunction (d.version_get)
  
  -- check the tables
--  t.assertIsTable (d.variables)
  t.assertIsTable (d.attributes)
--  t.assertIsTable (d.actions)
  t.assertIsTable (d.services)
end

function TestDevice:test_create_with_file ()
-- create (devNo, device_type, internal_id, description, upnp_file, upnp_impl, ip, mac, hidden, invisible, parent, room, pluginnum, statevariables, ...)
  local x = d.create (42, '', '', "Test", "D_Test.xml")
  t.assertIsTable (x)
end

function TestDevice:test_created_get ()    -- see if the ones defined initially are there
  --       "myServiceId,Variable=Value \n anotherSvId,MoreVars=pi"
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
  self.d0 = d.create (0, devType)
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
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.d0 = d.create (0, devType)
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
  local v = self.d0:variable_watch (my_watch, srv, name) 
  local a = self.d0:variable_get (srv, name)
  t.assertEquals (a.value, val)
  t.assertEquals (a.name, name)
  t.assertEquals (a.old, "EMPTY")
  t.assertNotNil (a.version)
  t.assertNotNil (a.time)
  local v = self.d0:variable_watch (my_watch, srv, "foo")   -- wrong variable
  t.assertNil (v)
  local v = self.d0:variable_watch (my_watch, "foo", name)  -- wrong service
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
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.d0 = d.create (0, devType)
end

function TestOtherMethods:tearDown ()
  self.d0 = nil
end

function TestOtherMethods:test_is_ready ()
  t.assertTrue (self.d0:is_ready())
end

function TestOtherMethods:test_supports_service ()
  local srv = "aService"
  local var = "varname"
  self.d0:variable_set (srv, name, val)
  t.assertTrue  (self.d0:supports_service (srv))
  t.assertFalse (self.d0:supports_service "foo")
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

function TestOtherMethods:test_call_action ()
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

function TestOtherMethods:test_missing_action ()
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

function TestOtherMethods:test_ ()
end

--------------------

if not multifile then t.LuaUnit.run "-v" end

--------------------
