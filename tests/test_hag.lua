local t = require "tests.luaunit"

Test_hag = {}


-----
--
-- TEST upnp.control.hag WSAPI CGI
--

local luup = require "openLuup.luup"
local hag = require "openLuup.hag"

local content = [[
<s:Envelope xmlns:s='http://schemas.xmlsoap.org/soap/envelope/' s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/'>   
<s:Body>      
<u:ModifyUserData xmlns:u='urn:schemas-micasaverde-org:service:HomeAutomationGateway:1'>
<inUserData>
{
&quot;devices&quot;:{},
&quot;scenes&quot;:{},
&quot;sections&quot;:{},
&quot;rooms&quot;:{},
&quot;InstalledPlugins&quot;:[],
&quot;PluginSettings&quot;:[],
&quot;users&quot;:{},
&quot;StartupCode&quot;:
&quot;-- this is where the startup code goes\n&quot;}
</inUserData>
<DataFormat>json</DataFormat>      
</u:ModifyUserData>   
</s:Body>
</s:Envelope>
]]

function Test_hag:test_startup ()
    
  local status,headers,iterator = hag.run {
      error = {write = function (_, ...) print (...) end},
      input = {read  = function () return content end}, 
    }

  local content = iterator()
  t.assertEquals (status, 200)
  t.assertIsTable (headers)
  t.assertEquals (content, "OK")
  
  local startup = luup.attr_get "StartupCode"
  t.assertEquals (startup, "-- this is where the startup code goes\n")
  
end


---------------------

if multifile then return end
t.LuaUnit.run "-v" 

---------------------

