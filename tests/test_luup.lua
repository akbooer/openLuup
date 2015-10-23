
local t = require "luaunit"

-- openLuup.device TESTS

--
-- DEVICE CREATE
--
luup = require "openLuup.luup"
local d = require "openLuup.devices"

TestLuup = {}     -- luup tests

function TestLuup:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.devNo = luup.create_device (devType)   -- minimal device description!!
  self.d = luup.devices[self.devNo]
end

function TestLuup:tearDown ()
--  luup.devices[self.devNo] = nil    -- actually, it should just increment the device number
end

-- basics

function TestLuup:test_basic_types ()
  t.assertIsFunction (luup.attr_get)     
  t.assertIsFunction (luup.attr_set)     
  t.assertIsFunction (luup.call_action)     
  t.assertIsFunction (luup.call_delay)     
  t.assertIsFunction (luup.call_timer)     
  t.assertIsTable (luup.chdev)     
  t.assertIsString (luup.city)     
  t.assertIsFunction (luup.create_device)     
  t.assertIsFunction (luup.device_supports_service)     
  t.assertIsTable (luup.devices)     
  t.assertIsFunction (luup.devices_by_service)     
  t.assertIsString (luup.event_server)     
  t.assertIsString (luup.event_server_backup)     
  t.assertIsString (luup.hw_key)     
  t.assertIsTable (luup.inet)     
  t.assertIsTable (luup.io)     
  t.assertIsFunction (luup.ip_set)     
  t.assertIsTable (luup.ir)     
  t.assertIsFunction (luup.is_night)     
  t.assertIsFunction (luup.is_ready)     
  t.assertIsTable (luup.job)     
  t.assertIsFunction (luup.job_watch)     
  t.assertIsNumber (luup.latitude)     
  t.assertIsFunction (luup.log)     
  t.assertIsNumber (luup.longitude)     
  t.assertIsFunction (luup.mac_set)     
  t.assertIsNumber (luup.pk_accesspoint)     
  t.assertIsString (luup.ra_server)     
  t.assertIsString (luup.ra_server_backup)     
  t.assertIsFunction (luup.register_handler)     
  t.assertIsFunction (luup.reload)            -- avoid calling this during unit testing!!
--  t.assertIsFunction (luup.require)         -- don't know what this is  
  t.assertIsTable (luup.rooms)     
  t.assertIsTable (luup.scenes)     
  t.assertIsFunction (luup.set_failure)     
  t.assertIsFunction (luup.sleep)     
  t.assertIsFunction (luup.sunrise)     
  t.assertIsFunction (luup.sunset)     
  t.assertIsFunction (luup.task)     
  t.assertIsString (luup.timezone)     
  t.assertIsFunction (luup.variable_get)     
  t.assertIsFunction (luup.variable_set)     
  t.assertIsFunction (luup.variable_watch)     
  t.assertIsString (luup.version)     
  t.assertIsNumber (luup.version_branch)     
  t.assertIsNumber (luup.version_major)     
  t.assertIsNumber (luup.version_minor)     
--  t.assertIsTable (luup.xj)                 -- don't know what this is either 

end  

--
-- ATTRIBUTES
--

TestLuupAttributes = {}


function TestLuupAttributes:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.devNo = luup.create_device (devType)   -- minimal device description!!
  self.d = luup.devices[self.devNo]
end

function TestLuupAttributes:tearDown ()
end

function TestLuupAttributes:test_nil_get ()
  local a = luup.attr_get ("foo", self.devNo)
  t.assertIsNil (a)
  local b = luup.attr_get ("name", 888)   -- non-existent device
  t.assertIsNil (a)
  local b = luup.attr_get ("name", 0)     -- device ZERO
  t.assertIsNil (a)
end


function TestLuupAttributes:test_set_get ()
  local val = "42"
  local name = "attr1"
  luup.attr_set (name, val, self.devNo)
  local a = luup.attr_get (name, self.devNo)
  t.assertEquals (a, val)
end

function TestLuupAttributes:test_set_get_0 ()
  local val = "42"
  local name = "attr1"
  luup.attr_set (name, val)
  local a = luup.attr_get (name)
  t.assertEquals (a, val)
end

function TestLuupAttributes:test_ip_set ()
  local ip = "172.16.42.42"
  luup.ip_set (ip, self.devNo)
  local a = luup.attr_get ("ip", self.devNo)
  t.assertEquals (a, ip)
end

function TestLuupAttributes:test_mac_set ()
  local mac = "11:22:33:44:55"
  luup.mac_set (mac, self.devNo)
  local a = luup.attr_get ("mac", self.devNo)
  t.assertEquals (a, mac)
end

-- these special top-level attributes also exist as luup.XXX variables!!!
function TestLuupAttributes:test_special_attributes ()
  local lat  = "latitude"
  local long = "longitude"
  local la,lo = luup.attr_get (lat), luup.attr_get (long)
  local new_lat, new_long = 65.4321, -1.2345
  luup.attr_set (lat,  new_lat)
  luup.attr_set (long, new_long)
  local la2,lo2 = luup.attr_get (lat), luup.attr_get (long)
  t.assertEquals (la2, tostring(new_lat))
  t.assertEquals (lo2, tostring(new_long))
  local la3, lo3 = luup.latitude, luup.longitude
  t.assertEquals (la3, new_lat)
  t.assertEquals (lo3, new_long)
  -- now put them back to what they were
  luup.attr_set (lat,  la)
  luup.attr_set (long, lo)
end


-- these special top-level attributes also exist as luup.XXX variables!!!
function TestLuupAttributes:test_more_special_attributes ()
  local pk = luup.attr_get "PK_AccessPoint"
  local pk2 = luup.pk_accesspoint
  t.assertIsString (pk)
  t.assertIsNumber (pk2)
  t.assertEquals (pk2, tonumber(pk))
  luup.attr_set ("PK_AccessPoint", 42)
  t.assertEquals (luup.pk_accesspoint, 42)
  t.assertEquals (luup.attr_get "PK_AccessPoint", "42")
  luup.attr_set ("PK_AccessPoint", pk)
  t.assertEquals (luup.pk_accesspoint, tonumber(pk))
end

function TestLuupAttributes:test_ ()
  t.assertEquals (a, mac)
end


--
-- VARIABLES
--

TestLuupVariables = {}

function TestLuupVariables:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.devNo = luup.create_device (devType)   -- minimal device description!!
  self.d = luup.devices[self.devNo]
end

function TestLuupVariables:tearDown ()
end

function TestLuupVariables:test_nil_get ()
  local a = luup.variable_get ("srv", "name", self.devNo)
  t.assertIsNil (a)
  local b = luup.variable_get ("srv", "name", 888)                -- non-existent device
  t.assertIsNil (b)
  local c = luup.variable_get ("srv", "wrong_name", self.devNo)   -- non-existent variable
  t.assertIsNil (c)
  local d = luup.variable_get ("wrong_srv", "name", self.devNo)   -- non-existent service
  t.assertIsNil (d)
  local z = luup.variable_get ("srv", "name", 0)                  -- device ZERO
  t.assertIsNil (z)
end

function TestLuupVariables:test_set_get ()
  local val = "42"
  local srv = "myService"
  local name = "var1"
  luup.variable_set (srv, name, val, self.devNo)
  local value, time = luup.variable_get (srv, name, self.devNo)
  t.assertEquals (value, val)
  t.assertAlmostEquals (time, os.time(), 1)    -- check the time is right too
end

function TestLuupVariables:test_set_device_0 ()
  local val = "42"
  local srv = "myService"
  local name = "var1"
  luup.variable_set (srv, name, val, 0)
  local value, time = luup.variable_get (srv, name, 0)
  t.assertNil (value)
  t.assertNil (time)  
  end


function TestLuupVariables:test_watch ()
  local val = "42"
  local srv = "myService"
  local name = "var1"
  luup.variable_set (srv, name, val, self.devNo)
  luup.variable_watch ("my_watch", srv, name, self.devNo)   -- not a real test, since no callback
  -- but delve into the devices structure and check that all is as it should be...
  local var = luup.devices[self.devNo]:variable_get(srv, name)
  t.assertEquals (#var.watchers, 1)
  t.assertEquals (var.watchers[1].callback, my_watch)
  t.assertEquals (var.dev, self.devNo)
  t.assertEquals (var.srv, srv)
end

function my_watch ()
  -- won't actually be called since scheduler is not running
 error "should never be called"
end

--
-- OTHER METHODS
--

TestOtherLuupMethods = {}

function TestOtherLuupMethods:setUp ()
  local devType = "urn:schemas-micasaverde-com:device:HomeAutomationGateway:1"
  self.devType = devType
  self.devNo = luup.create_device (devType)   -- minimal device description!!
  self.d = luup.devices[self.devNo]
end

function TestOtherLuupMethods:tearDown ()
end

function TestOtherLuupMethods:test_supports_service ()
  local val = "42"
  local srv = "myService"
  local name = "var1"
  t.assertFalse (luup.device_supports_service (srv, self.devNo))
  luup.variable_set (srv, name, val, self.devNo)
  t.assertTrue (luup.device_supports_service (srv, self.devNo))
end

function TestOtherLuupMethods:test_is_ready ()
  t.assertTrue (luup.is_ready(self.devNo))
end

function TestOtherLuupMethods:test_inet_wget ()
  local status,result = luup.inet.wget "http://google.com"
  t.assertEquals (status, 0)
  t.assertIsString (result)
  t.assertStrContains (result, "<html")
  t.assertStrContains (result, "google")
  end

-- sorry, can't test thatwithout system reload!!
--function TestOtherLuupMethods:test_chdev ()
--  local chId = "childId"
--  local ptr = luup.chdev.start (self.devNo)
--  luup.chdev.append (self.devNo, ptr, chId, "Child Device", "urn:micasaverde-org:device:SerialPort:1")
--  luup.chdev.sync (self.devNo, ptr)
--  -- now find it...
--  local chDevNo
--  for devNo, d in pairs (luup.devices) do
--    if d.id == chId then chDevNo = devNo end
--  end
--  t.assertEquals (chDevNo, self.devNo + 1)    -- assume it's the next numbered device
--  t.assertEquals (luup.devices[chDevNo].device_num_parent, self.devNo)
--end


function TestOtherLuupMethods:test_version ()
  local v1 = self.d:version_get ()       -- this is the device version (not luup accessible?)
  t.assertIsNumber (v1)
  local val = "42"
  local srv = "myService"
  local name = "var1"
  local var = luup.variable_set (srv, name, val, self.devNo)   -- change a variable
  local v2 = self.d:version_get ()  
  t.assertTrue (v2 > v1)                         -- check version number increments
 end


function TestOtherLuupMethods:test_action () 
  local srv="urn:micasaverde-com:serviceId:HomeAutomationGateway1"
  local act = "SetHouseMode"
  local par = {Mode="2"}

  local error, error_msg, job, arguments = luup.call_action (srv, act, par, 0)
  
end

function TestOtherLuupMethods:test_action_0 ()    -- test on device 0
  local srv="urn:micasaverde-com:serviceId:HomeAutomationGateway1"
  local act = "SetHouseMode"
  local par = {Mode="2"}

  local error, error_msg, job, arguments = luup.call_action (srv, act, par, 0)
  t.assertEquals (error, 0)
--  t.assertIsNil (error_msg)   -- perhaps should be string?
  t.assertEquals(job, 0)
  t.assertIsTable (arguments)
  local mode = luup.attr_get "Mode"
  t.assertEquals (mode, "2")  

  local error, error_msg, job, arguments = luup.call_action (srv, act, {Mode = "1"}, 0)
  t.assertEquals (error, 0)
--  t.assertIsNil (error_msg)   -- perhaps should be string?
  t.assertEquals(job, 0)
  t.assertIsTable (arguments)
  local mode = luup.attr_get "Mode"
  t.assertEquals (mode, "1")  

end


function TestOtherLuupMethods:test_missing_action ()
  local result
  local function missing ()
    return { 
      run = function (lul_device, lul_settings) 
        result = lul_settings.value
        return true
      end 
    }
  end
  self.d:action_callback (missing)
  local error, error_msg, jobNo, ret_args = luup.call_action ("garp", "foo", {value=12345}, self.devNo)
  t.assertEquals (error, 0)
  t.assertIsTable (ret_args)
  t.assertEquals (result, 12345)
end


function TestOtherLuupMethods:test_sleep ()  
  luup.sleep (2000)   -- time in milliseconds
end


function TestOtherLuupMethods:test_ ()   
end
--------------------

if not multifile then t.LuaUnit.run "-v" end

--------------------
