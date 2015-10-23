local t = require "luaunit"

-- Device Files module tests

local loader  = require "openLuup.loader"
local xml = require "openLuup.xml"

local function noop () end

luup = {
    call_timer = noop,
    log = print,
    set_failure = noop,   
  }

-- create a new environment for device code
local function new_env ()
  local env =  {}
  for a,b in pairs (_G) do env[a] = b end
  env.module = function () end              -- noop for 'module'
  env._G = env                              -- this IS the global environment
  return env
end

local D = [[
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:altui:1</deviceType>
    <staticJson>D_ALTUI.json</staticJson> 
    <friendlyName>ALTUI</friendlyName>
    <manufacturer>Amg0</manufacturer>
    <manufacturerURL>http://www.google.fr/</manufacturerURL>
    <modelDescription>AltUI for Vera UI7</modelDescription>
    <modelName>AltUI for Vera UI7</modelName>
    <modelNumber>1</modelNumber>
    <protocol>cr</protocol>
    <handleChildren>0</handleChildren>
  <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:altui:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:altui1</serviceId>
        <controlURL>/upnp/control/ALTUI1</controlURL>
        <eventSubURL>/upnp/event/ALTUI1</eventSubURL>
        <SCPDURL>S_ALTUI.xml</SCPDURL>
      </service>
    </serviceList>
    <implementationList>
      <implementationFile>I_ALTUI.xml</implementationFile>
    </implementationList>
  </device>
</root>
]]

-- add a second service
local D2 = [[       
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:altui:1</deviceType>
    <staticJson>D_ALTUI.json</staticJson> 
    <friendlyName>ALTUI</friendlyName>
    <manufacturer>Amg0</manufacturer>
    <manufacturerURL>http://www.google.fr/</manufacturerURL>
    <modelDescription>AltUI for Vera UI7</modelDescription>
    <modelName>AltUI for Vera UI7</modelName>
    <modelNumber>1</modelNumber>
    <protocol>cr</protocol>
    <handleChildren>1</handleChildren>
  <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:altui:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:altui1</serviceId>
        <controlURL>/upnp/control/ALTUI1</controlURL>
        <eventSubURL>/upnp/event/ALTUI1</eventSubURL>
        <SCPDURL>S_ALTUI.xml</SCPDURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:altui:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:altui2</serviceId>
        <controlURL>/upnp/control/ALTUI2</controlURL>
        <eventSubURL>/upnp/event/ALTUI2</eventSubURL>
        <SCPDURL>S_ALTUI.xml</SCPDURL>
      </service>
    </serviceList>
    <implementationList>
      <implementationFile>I_ALTUI.xml</implementationFile>
    </implementationList>
  </device>
</root>
]]

local I = [[
<?xml version="1.0"?>
<implementation>
  <functions>
  function defined_in_tag () end
  </functions>
  <files>L_ALTUI.lua</files>
  <startup>initstatus</startup>
  <actionList>
    <action>
   <serviceId>urn:upnp-org:serviceId:altui1</serviceId>
   <name>SetDebug</name>
    <run>
      setDebugMode(lul_device,lul_settings.newDebugMode)
    </run>
  </action>
  <action>
    <serviceId>urn:upnp-org:serviceId:altui1</serviceId>
    <name>Reset</name>
    <run>
      resetDevice(lul_device,true)
    </run>    
  </action>
  <action>
    <serviceId>service</serviceId>
    <name>test</name>
    <run>
      return 42
    </run>    
  </action>  
</actionList>
  <incoming>
    <lua>
      return "INCOMING!!"
    </lua>
  </incoming>
</implementation>
]]

local S = [[
<?xml version="1.0" encoding="utf-8"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
	<specVersion>
		<major>1</major>
		<minor>0</minor>
	</specVersion>
	<serviceStateTable>
		<!-- Main variables -->
		<stateVariable>
			<name>DeviceType</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>string</dataType>
		</stateVariable>
		<stateVariable>
			<name>Configured</name>
			<sendEventsAttribute>true</sendEventsAttribute>
			<dataType>boolean</dataType>
			<defaultValue>0</defaultValue>
			<shortCode>configured</shortCode>
		</stateVariable>
		<stateVariable>
			<name>Color</name>
			<sendEventsAttribute>yes</sendEventsAttribute>
			<dataType>string</dataType>
			<defaultValue>#0000000000</defaultValue>
			<shortCode>color</shortCode>
		</stateVariable>
		<stateVariable>
			<name>Message</name>
			<sendEventsAttribute>yes</sendEventsAttribute>
			<dataType>string</dataType>
			<shortCode>message</shortCode>
		</stateVariable>
		<!-- Specific variables -->
		<stateVariable>
			<name>DeviceId</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>ui2</dataType>
			<defaultValue>0</defaultValue>
		</stateVariable>
		<stateVariable>
			<name>DeviceIP</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>String</dataType>
		</stateVariable>
		<stateVariable>
			<name>DevicePort</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>String</dataType>
		</stateVariable>
		<!-- Color aliases -->
		<stateVariable>
			<name>AliasRed</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>string</dataType>
			<defaultValue>e2</defaultValue>
			<shortCode>aliasred</shortCode>
		</stateVariable>
		<stateVariable>
			<name>AliasGreen</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>string</dataType>
			<defaultValue>e3</defaultValue>
			<shortCode>aliasgreen</shortCode>
		</stateVariable>
		<stateVariable>
			<name>AliasBlue</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>string</dataType>
			<defaultValue>e4</defaultValue>
			<shortCode>aliasblue</shortCode>
		</stateVariable>
		<stateVariable>
			<name>AliasWhite</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>string</dataType>
			<defaultValue>e5</defaultValue>
			<shortCode>aliaswhite</shortCode>
		</stateVariable>
		<!-- Color dimmers -->
		<stateVariable>
			<name>DeviceIdRed</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>ui2</dataType>
			<shortCode>deviceidred</shortCode>
		</stateVariable>
		<stateVariable>
			<name>DeviceIdGreen</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>ui2</dataType>
			<shortCode>deviceidgreen</shortCode>
		</stateVariable>
		<stateVariable>
			<name>DeviceIdBlue</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>ui2</dataType>
			<shortCode>deviceidblue</shortCode>
		</stateVariable>
		<stateVariable>
			<name>DeviceIdWarmWhite</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>ui2</dataType>
			<shortCode>deviceidwarmwhite</shortCode>
		</stateVariable>
		<stateVariable>
			<name>DeviceIdCoolWhite</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>ui2</dataType>
			<shortCode>deviceidcoolwhite</shortCode>
		</stateVariable>
		<!-- Arguments -->
		<stateVariable>
			<name>A_ARG_TYPE_Target</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>boolean</dataType>
			<defaultValue>0</defaultValue>
		</stateVariable>
		<stateVariable>
			<name>A_ARG_TYPE_Status</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>boolean</dataType>
			<defaultValue>0</defaultValue>
		</stateVariable>
		<stateVariable>
			<name>A_ARG_TYPE_programId</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>ui1</dataType>
			<defaultValue>0</defaultValue>
		</stateVariable>
		<stateVariable>
			<name>A_ARG_TYPE_programName</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>string</dataType>
		</stateVariable>
		<stateVariable>
			<name>A_ARG_TYPE_transitionDuration</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>string</dataType>
		</stateVariable>
		<stateVariable>
			<name>A_ARG_TYPE_transitionNbSteps</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>string</dataType>
		</stateVariable>
		<!-- Trick of the dummy argument for computed return -->
		<stateVariable>
			<name>LastResult</name>
			<sendEventsAttribute>no</sendEventsAttribute>
			<dataType>string</dataType>
			<shortCode>lastresult</shortCode>
		</stateVariable>
	</serviceStateTable>
	<actionList>
		<!-- Parameters -->
		<action>
			<name>GetRGBDeviceTypes</name>
			<argumentList>
				<argument>
					<name>retRGBDeviceTypes</name>
					<direction>out</direction>
					<relatedStateVariable>LastResult</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
		<!-- Status -->
		<action>
			<!-- DEPRECATED -->
			<name>SetTarget</name>
			<argumentList>
				<argument>
					<name>newTargetValue</name>
					<direction>in</direction>
					<relatedStateVariable>A_ARG_TYPE_Target</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
			<!-- DEPRECATED -->
		<action>
			<name>GetTarget</name>
			<argumentList>
				<argument>
					<name>retTargetValue</name>
					<direction>out</direction>
					<relatedStateVariable>A_ARG_TYPE_Target</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
			<!-- DEPRECATED -->
		<action>
			<name>GetStatus</name>
			<argumentList>
				<argument>
					<name>ResultStatus</name>
					<direction>out</direction>
					<relatedStateVariable>A_ARG_TYPE_Status</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
		<!-- Color -->
		<action>
			<!-- DEPRECATED -->
			<name>SetColor</name>
			<argumentList>
				<argument>
					<name>newColor</name>
					<direction>in</direction>
					<relatedStateVariable>Color</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
		<action>
			<name>SetColorTarget</name>
			<argumentList>
				<argument>
					<name>newColorTargetValue</name>
					<direction>in</direction>
					<relatedStateVariable>Color</relatedStateVariable>
				</argument>
				<argument>
					<name>transitionDuration</name>
					<direction>in</direction>
					<relatedStateVariable>A_ARG_TYPE_transitionDuration</relatedStateVariable>
				</argument>
				<argument>
					<name>transitionNbSteps</name>
					<direction>in</direction>
					<relatedStateVariable>A_ARG_TYPE_transitionNbSteps</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
		<action>
			<name>GetColor</name>
			<argumentList>
				<argument>
					<name>retColorValue</name>
					<direction>out</direction>
					<relatedStateVariable>Color</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
		<action>
			<name>GetColorChannelNames</name>
			<argumentList>
				<argument>
					<name>retColorChannelNames</name>
					<direction>out</direction>
					<relatedStateVariable>LastResult</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
		<!-- Animation -->
		<action>
			<name>StartAnimationProgram</name>
			<argumentList>
				<argument>
					<name>programId</name>
					<direction>in</direction>
					<relatedStateVariable>A_ARG_TYPE_programId</relatedStateVariable>
				</argument>
				<argument>
					<name>programName</name>
					<direction>in</direction>
					<relatedStateVariable>A_ARG_TYPE_programName</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
		<action>
			<name>StopAnimationProgram</name>
			<argumentList>
			</argumentList>
		</action>
		<action>
			<name>GetAnimationProgramNames</name>
			<argumentList>
				<argument>
					<name>retAnimationProgramNames</name>
					<direction>out</direction>
					<relatedStateVariable>LastResult</relatedStateVariable>
				</argument>
			</argumentList>
		</action>
	</actionList>
</scpd>

]]


TestDeviceFile = {}

function TestDeviceFile:test_upnp_file ()
  local dev_xml = xml.xml2Lua (D)
  local d = loader.parse_device_xml (dev_xml) 
  t.assertEquals (d.device_type, "urn:schemas-upnp-org:device:altui:1")
  t.assertEquals (d.json_file, "D_ALTUI.json")
  t.assertEquals (d.impl_file, "I_ALTUI.xml")
  t.assertIsTable (d.service_list)
  t.assertEquals (#d.service_list, 1)
  t.assertEquals (d.handle_children, "0")
  local s = d.service_list[1]
  t.assertEquals (s.serviceType, "urn:schemas-upnp-org:service:altui:1")
  t.assertEquals (s.serviceId,   "urn:upnp-org:serviceId:altui1")
end


function TestDeviceFile:test_upnp_file2 ()
  local dev_xml = xml.xml2Lua (D2)
  local d = loader.parse_device_xml (dev_xml) 
  t.assertEquals (d.device_type, "urn:schemas-upnp-org:device:altui:1")
  t.assertEquals (d.json_file, "D_ALTUI.json")
  t.assertEquals (d.impl_file, "I_ALTUI.xml")
  t.assertEquals (d.handle_children, "1")
  t.assertIsTable (d.service_list)
  t.assertEquals (#d.service_list, 2)
  local s = d.service_list[1]
  t.assertEquals (s.serviceType, "urn:schemas-upnp-org:service:altui:1")
  t.assertEquals (s.serviceId,   "urn:upnp-org:serviceId:altui1")
  local s = d.service_list[2]
  t.assertEquals (s.serviceType, "urn:schemas-upnp-org:service:altui:1")
  t.assertEquals (s.serviceId,   "urn:upnp-org:serviceId:altui2")
end


TestImplementationFile = {}

function TestImplementationFile:test_impl_file ()
  local impl_xml = xml.xml2Lua (I)
  local i = loader.parse_impl_xml (impl_xml) 
  t.assertEquals (i.startup, "initstatus")      
  local a, error_msg = loadstring (i.source_code, i.module_name)  -- load it
  local ENV = new_env()
  t.assertIsFunction (a)
  t.assertIsNil (error_msg)
  setfenv (a, ENV)
  if a then a, error_msg = pcall(a) end                 -- instantiate it
  local code = ENV
  local acts = code._openLuup_ACTIONS_
  t.assertIsTable (acts)
  t.assertEquals (#acts, 3)
  t.assertEquals (acts[1].name, "SetDebug")
  t.assertEquals (acts[2].name, "Reset")
  t.assertEquals (acts[2].serviceId, "urn:upnp-org:serviceId:altui1")
  t.assertEquals (acts[3].name, "test")
  t.assertEquals (acts[3].serviceId, "service")
  t.assertEquals (acts[3].run(), 42)
  t.assertIsFunction (code._openLuup_INCOMING_)
  t.assertEquals (code._openLuup_INCOMING_ (), "INCOMING!!")
end


function TestImplementationFile:test_impl_2 ()
  local i = loader.read_impl "I_Test.xml"
  t.assertIsString (i.startup)
  t.assertEquals (i.startup, "testStartup")
  local a, error_msg = loadstring (i.source_code, i.module_name)  -- load it
  t.assertIsFunction (a)
  t.assertIsNil (error_msg)
  local ENV = new_env()
  setfenv (a, ENV)
  if a then a, error_msg = pcall(a) end                 -- instantiate it
  local code = ENV
  local acts = code._openLuup_ACTIONS_
  t.assertIsTable (acts)
  t.assertEquals (#acts, 6)
  t.assertIsFunction (code[i.startup])   
end

function TestImplementationFile:test_impl_DataYours ()
  local i = loader.read_impl "I_DataYours7.xml"
  t.assertIsString (i.startup)
  t.assertEquals (i.startup, "Startup")
  local a, error_msg = loadstring (i.source_code, i.module_name)  -- load it
  t.assertIsFunction (a)
  t.assertIsNil (error_msg)
  local ENV = new_env()
  setfenv (a, ENV)
  if a then a, error_msg = pcall(a) end                 -- instantiate it
  local code = ENV
end


TestServiceFile = {}

function TestServiceFile:test_srv_file ()
  local svc_xml = xml.xml2Lua (S)
  local s = loader.parse_service_xml (svc_xml) 
  t.assertIsTable (s.actions)      
  t.assertIsTable (s.returns)      
  t.assertIsTable (s.variables)   
  -- actions
  for i,a in ipairs (s.actions) do
    local argument = xml.extract (a, "argumentList", "argument")
    t.assertIsString (a.name)
    for j,k in ipairs (argument or {}) do
      t.assertIsString (k.direction)
      t.assertTrue (k.direction == "in" or k.direction == "out")
      t.assertIsString (k.name)
      t.assertIsString (k.relatedStateVariable)
    end
  end
  -- variables
  for i,v in ipairs (s.variables) do
    t.assertIsString (v.dataType)
    t.assertIsString (v.sendEventsAttribute)
    t.assertIsString (v.name)
  end
  -- return parameters
  for name,ret in pairs (s.returns) do
    t.assertIsString (name)
    t.assertIsTable (ret)
  end
end

TestCompiler = {}

function TestCompiler:test_new_environment ()
  local name = "test_env"
  local x = loader.new_environment (name)
  t.assertIsTable (x)
  t.assertEquals (x._NAME, name)
  t.assertEquals (x._G._NAME, name)   -- ... and in the self-reference environment global
--  t.assertEquals (x.luup, luup)     -- luup not now there by default
  t.assertIsNil (x.arg)               -- make sure command line arguments are absent
end

function TestCompiler:test_compile_ok ()
  local ok,err = loader.compile_lua " function foo () return 42 end"
  t.assertIsNil (err)
  t.assertIsTable (ok)
  t.assertEquals (ok.foo(), 42)
end

function TestCompiler:test_compile_error ()
  local ok,err = loader.compile_lua (" function  return 42 end", "test_error")
  t.assertIsNil (ok)
  t.assertIsString (err)
end


-------------------

if multifile then return end

t.LuaUnit.run "-v" 

-------------------

require "pretty"

local s = loader.read_service "S_SwitchPower1.xml"
--s = df.parse_service_xml (xml.xml2Lua (S))

print "--------"

print(pretty(s.returns))

print "--------"

print "actions"
for i,a in ipairs (s.actions) do
  local argument = xml.extract (a, "argumentList", "argument")
  print (a.name)
  for j,k in ipairs (argument or {}) do
    print ('',k.direction, k.name .. ' = ' .. k.relatedStateVariable)
  end
end

print "variables"
for i,v in ipairs (s.variables) do
  print (i, v.dataType, v.sendEventsAttribute, v.name)
end

