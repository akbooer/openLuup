local t = require "tests.luaunit"

Test_gateway = {}


-----
--
-- TEST gateway
--

luup = require "openLuup.luup"
local json = require "openLuup.json"
local g    = require "openLuup.gateway"

local SID = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"

local params = {
    DataFormat = "json",
    inUserData = json.encode {StartupCode = "-- this is where the startup code goes\n"}
  }

function Test_gateway:test_startup ()
    
  g.services[SID].actions.ModifyUserData.run ('', params)

  
  local startup = luup.attr_get "StartupCode"
  t.assertEquals (startup, "-- this is where the startup code goes\n")
  
end


---------------------

if multifile then return end
t.LuaUnit.run "-v" 

---------------------

