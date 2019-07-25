local t = require "tests.luaunit"

local _, pretty = pcall (require, "pretty")

-- Device Files module tests

local loader  = require "openLuup.loader"
local xml = loader.xml

local vfs = require "openLuup.virtualfilesystem"       -- for some test files
--local cmh_lu = ";../cmh-lu/?.lua"
--if not package.path:match (cmh_lu) then
--  package.path = package.path .. cmh_lu                   -- add /etc/cmh-lu/ to search path
--end

local function noop () end

luup = {
    call_timer = noop,
    log = function (...) print ('\n', ...) end,
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
    <empty> </empty>
    <empty2 />
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
    <settings>
        <protocol>cr</protocol>
    </settings>
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

-- specifically to test an <incoming> tag WITHOUT <lua>...</lua> tags
-- I really do think that this is incorrect.
local I2 = [[
<?xml version="1.0"?>
<implementation>
  <settings>
    <protocol>cr</protocol>
  </settings>
  <files>
  L_Weather.lua
  </files>
  <!-- really think that this should have nested lua tag -->
  <incoming>
      debug("Incoming, really?")
  </incoming>
  <startup>startup</startup>
  <actionList>
    <action>
      <serviceId>urn:upnp-micasaverde-com:serviceId:Weather1</serviceId>
      <name>SetUnitsMetric</name>
      <run>
        luup.variable_set(WEATHER_SERVICE, "Metric", "1", lul_device)
      </run>
    </action>
    </actionList>
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


function TestDeviceFile:test_very_empty ()
  local D = [[
  <root xmlns="urn:schemas-upnp-org:device-1-0">
    <device />
  </root>
  ]]
  local dev_xml = xml.decode (D)
  local d = loader.parse_device_xml (dev_xml) 
  t.assertIsTable (d.service_list)
  t.assertItemsEquals (d.service_list, {})
end

function TestDeviceFile:test_empty_lists ()
  local D = [[
  <root xmlns="urn:schemas-upnp-org:device-1-0">
    <device>
       <serviceList />
      <implementationList />
     </device>
  </root>
  ]]
  local dev_xml = xml.decode (D)
  local d = loader.parse_device_xml (dev_xml) 
  t.assertIsTable (d.service_list)
  t.assertItemsEquals (d.service_list, {})
  t.assertIsNil (d.impl_file)
end


function TestDeviceFile:test_empty_srv_and_ifile ()
  local D = [[
  <root xmlns="urn:schemas-upnp-org:device-1-0">
    <device>
       <serviceList>
        <service />
      </serviceList>
      <implementationList>
        <implementationFile />
      </implementationList>
    </device>
  </root>
  ]]
  local dev_xml = xml.decode (D)
  local d = loader.parse_device_xml (dev_xml) 
  t.assertIsTable (d.service_list)
  t.assertItemsEquals (#d.service_list, 1)
  t.assertItemsEquals (d.service_list[1], {})
  t.assertEquals (d.impl_file, '')              -- old decoder gave nil
end

function TestDeviceFile:test_empty_srv_and_ifile2 ()
  local D = [[
  <root xmlns="urn:schemas-upnp-org:device-1-0">
    <device>
       <serviceList>
        <service>
          
        </service>
      </serviceList>
      <implementationList>
        <implementationFile></implementationFile>
      </implementationList>
    </device>
  </root>
  ]]
  local dev_xml = xml.decode (D)
  local d = loader.parse_device_xml (dev_xml) 
  t.assertIsTable (d.service_list)
  t.assertItemsEquals (#d.service_list, 1)
  t.assertItemsEquals (d.service_list[1], {})
  t.assertEquals (d.impl_file, '')              -- old decoder gave nil
end


function TestDeviceFile:test_simple ()
  local D = [[
  <root xmlns="urn:schemas-upnp-org:device-1-0">
    <device>
      <friendlyName>ALTUI</friendlyName>
      <category_num>42</category_num>
      <subcategory_num>123</subcategory_num>
      <manufacturer>Amg0</manufacturer>
      <manufacturerURL>http://www.google.fr/</manufacturerURL>
      <modelDescription>AltUI for Vera UI7</modelDescription>
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
  local dev_xml = xml.decode (D)
  local d = loader.parse_device_xml (dev_xml) 
  t.assertIsTable (d.service_list)
  t.assertEquals (#d.service_list, 1)
  t.assertItemsEquals (d.service_list[1], 
    {
      serviceType = "urn:schemas-upnp-org:service:altui:1",
      serviceId = "urn:upnp-org:serviceId:altui1",
      controlURL = "/upnp/control/ALTUI1",
      eventSubURL = "/upnp/event/ALTUI1",
      SCPDURL = "S_ALTUI.xml",
    })
  t.assertEquals (d.impl_file, "I_ALTUI.xml")
  t.assertEquals (d.category_num, 42)
  t.assertEquals (d.subcategory_num, 123)
end


function TestDeviceFile:test_upnp_file ()
  local dev_xml = xml.decode (D)
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
  local dev_xml = xml.decode (D2)
  local d = loader.parse_device_xml (dev_xml) 
  t.assertEquals (d.device_type, "urn:schemas-upnp-org:device:altui:1")
  t.assertEquals (d.json_file, "D_ALTUI.json")
  t.assertEquals (d.impl_file, "I_ALTUI.xml")
  t.assertEquals (d.protocol, "cr")
  t.assertEquals (d.handle_children, "1")
  t.assertIsTable (d.service_list)
  t.assertEquals (#d.service_list, 2)
  local s1 = d.service_list[1]
  t.assertEquals (s1.serviceType, "urn:schemas-upnp-org:service:altui:1")
  t.assertEquals (s1.serviceId,   "urn:upnp-org:serviceId:altui1")
  local s2 = d.service_list[2]
  t.assertEquals (s2.serviceType, "urn:schemas-upnp-org:service:altui:1")
  t.assertEquals (s2.serviceId,   "urn:upnp-org:serviceId:altui2")
end


TestImplementationFile = {}



local Idemo = [[
<?xml version="1.0"?>
<implementation>
    <settings>
        <protocol>cr</protocol>
    </settings>
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


function TestImplementationFile:test_very_empty ()
  local I = [[
  <implementation />
  ]]
  local impl_xml = xml.decode (I)
  local i = loader.parse_impl_xml (impl_xml) 
  t.assertIsNil (i.handle_children)
  t.assertIsNil (i.protocol)
  t.assertIsString (i.source_code)
  t.assertIsNil (i.startup)
  t.assertIsString (i.files)
  t.assertEquals (i.files, '')
  t.assertIsString (i.actions)
end

function TestImplementationFile:test_empty_lists ()
  local I = [[
<implementation>
  <settings />
  <functions />
  <files />
  <startup />
  <actionList />
  <incoming />
</implementation>
  ]]
  local impl_xml = xml.decode (I)
  local i = loader.parse_impl_xml (impl_xml) 
  t.assertIsNil (i.handle_children)
  t.assertIsNil (i.protocol)
  t.assertIsString (i.source_code)
--  t.assertIsNil (i.startup)
  t.assertEquals (i.startup, '')              -- old decoder gave nil
  t.assertIsString (i.files)
  t.assertEquals (i.files, '')
  t.assertIsString (i.actions)
end


function TestImplementationFile:test_empty_actionList ()
  local I = [[
<implementation>
  <settings><protocol>cr</protocol></settings>
  <functions>function defined_in_tag () end</functions>
  <files>L_ALTUI.lua</files>
  <startup>initstatus</startup>
  <actionList />
  <incoming>
    <lua>
      return "INCOMING!!"
    </lua>
  </incoming>
</implementation>
  ]]
  local impl_xml = xml.decode (I)
  local i = loader.parse_impl_xml (impl_xml) 
  t.assertIsNil (i.handle_children)
  t.assertEquals (i.protocol, "cr")
  t.assertIsString (i.source_code)
  t.assertEquals (i.startup, "initstatus")
  t.assertEquals (i.files, "L_ALTUI.lua")
  t.assertIsString (i.actions)
end

function TestImplementationFile:test_empty_action ()
  local I = [[
<implementation>
  <settings><protocol>cr</protocol></settings>
  <functions>function defined_in_tag () end</functions>
  <files>L_ALTUI.lua</files>
  <startup>initstatus</startup>
  <actionList>
    <action />
  </actionList>
  <incoming>
    <lua>
      return "INCOMING!!"
    </lua>
  </incoming>
</implementation>
  ]]
  local impl_xml = xml.decode (I)
  local i = loader.parse_impl_xml (impl_xml) 
  t.assertIsNil (i.handle_children)
  t.assertEquals (i.protocol, "cr")
  t.assertIsString (i.source_code)
  t.assertEquals (i.startup, "initstatus")
  t.assertEquals (i.files, "L_ALTUI.lua")
  t.assertIsString (i.actions)
end


function TestImplementationFile:test_simple ()
  local I = [[
<implementation>
  <settings><protocol>cr</protocol></settings>
  <functions>function defined_in_tag () end</functions>
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
  local impl_xml = xml.decode (I)
  local i = loader.parse_impl_xml (impl_xml) 
  t.assertIsNil (i.handle_children)
  t.assertEquals (i.protocol, "cr")
  t.assertIsString (i.source_code)
  t.assertEquals (i.startup, "initstatus")
  t.assertEquals (i.files, "L_ALTUI.lua")
  t.assertIsString (i.actions)
  t.assertStrContains (i.actions, "SetDebug")
  t.assertStrContains (i.actions, "urn:upnp-org:serviceId:altui1")
  t.assertStrContains (i.actions, "Reset")
  t.assertStrContains (i.actions, "test")
  t.assertStrContains (i.actions, "SetDebug")
  local _, srvIds = i.actions: gsub ("serviceId = ", '')
  t.assertEquals (srvIds, 3)
  local _, names = i.actions: gsub ("name = ", '')
  t.assertEquals (names, 3)
  local _, tables = i.actions: gsub ("%b{}", '')
  t.assertEquals (names, 3)
end



function TestImplementationFile:test_impl_file ()
  local impl_xml = xml.decode (I)
  local i = loader.parse_impl_xml (impl_xml, I) 
  t.assertEquals (i.startup, "initstatus")      
  local a, error_msg = loadstring (i.source_code, i.module_name)  -- load it
  local ENV = new_env()
  t.assertIsFunction (a)
  t.assertIsNil (error_msg)
  setfenv (a, ENV)
  if a then a, error_msg = pcall(a) end                 -- instantiate it
  t.assertIsNil (error_msg)
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
  t.assertEquals (i.protocol, "cr")
  t.assertIsFunction (code._openLuup_INCOMING_)
  t.assertEquals (code._openLuup_INCOMING_ (), "INCOMING!!")
end

-- look closely at <incoming> tag ... no embedded <lua> tag!!
function TestImplementationFile:test_impl_2 ()
  local impl_xml = xml.decode (I2)
  local i = loader.parse_impl_xml (impl_xml, I2) 
  t.assertEquals (i.startup, "startup")
  t.assertEquals (i.files, "L_Weather.lua")
  t.assertEquals (i.protocol, "cr")
  t.assertEquals (i.incoming, nil)   -- [[debug("Incoming, really?")]])
  -- compile code
  local a, error_msg = loadstring (i.source_code, i.module_name)  -- load it
  local ENV = new_env()
  t.assertIsFunction (a)
  t.assertIsNil (error_msg)
  setfenv (a, ENV)
  if a then a, error_msg = pcall(a) end                 -- instantiate it
  t.assertIsNil (error_msg)
  local code = ENV
  -- single action: SetUnitsMetric
  local acts = code._openLuup_ACTIONS_
  t.assertIsTable (acts)
  t.assertEquals (#acts, 1)
  t.assertEquals (acts[1].name, "SetUnitsMetric")
  t.assertEquals (acts[1].serviceId, "urn:upnp-micasaverde-com:serviceId:Weather1")
end


function TestImplementationFile:test_impl_openLuup ()
  local I = vfs.read "I_openLuup.xml"
  local impl_xml = xml.decode (I)
  local i = loader.parse_impl_xml (impl_xml, I) 
  t.assertIsString (i.startup)
  t.assertEquals (i.startup, "init")
  local a, error_msg = loadstring (i.source_code, i.module_name)  -- load it
  t.assertIsFunction (a)
  t.assertIsNil (error_msg)
  local ENV = new_env()
  setfenv (a, ENV)
  if a then a, error_msg = pcall(a) end                 -- instantiate it
  t.assertIsNil (error_msg)
  local code = ENV
  local acts = code._openLuup_ACTIONS_
  t.assertIsFunction (code[i.startup])   
end


TestServiceFile = {}


function TestServiceFile:test_very_empty ()
local S = [[
<scpd xmlns="urn:schemas-upnp-org:service-1-0" />
]]
  local svc_xml = xml.decode (S)
  local s = loader.parse_service_xml (svc_xml) 
  t.assertIsTable (s.actions)
  t.assertItemsEquals (s.actions, {})
  t.assertIsTable (s.returns)
  t.assertItemsEquals (s.returns, {})
  t.assertIsTable (s.short_codes)
  t.assertItemsEquals (s.short_codes, {})
  t.assertIsTable (s.variables)
  t.assertItemsEquals (s.variables, {})
end

function TestServiceFile:test_empty ()
local S = [[
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
	<serviceStateTable />
  <actionList />
</scpd>  
  
]]
  local svc_xml = xml.decode (S)
  local s = loader.parse_service_xml (svc_xml) 
  t.assertIsTable (s.actions)
  t.assertItemsEquals (s.actions, {})
  t.assertIsTable (s.returns)
  t.assertItemsEquals (s.returns, {})
  t.assertIsTable (s.short_codes)
  t.assertItemsEquals (s.short_codes, {})
  t.assertIsTable (s.variables)
  t.assertItemsEquals (s.variables, {})
end

function TestServiceFile:test_empty_var_and_act ()
local S = [[
<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
	<serviceStateTable>
    <stateVariable />	
	</serviceStateTable>
  <actionList>
     <action />
 	</actionList>
</scpd>
]]
  local svc_xml = xml.decode (S)
  local s = loader.parse_service_xml (svc_xml) 
  t.assertIsTable (s.actions)
  t.assertItemsEquals (s.actions, {})
  t.assertIsTable (s.returns)
  t.assertItemsEquals (s.returns, {})
  t.assertIsTable (s.short_codes)
  t.assertItemsEquals (s.short_codes, {})
  t.assertIsTable (s.variables)
  t.assertItemsEquals (s.variables, {})
end
  
function TestServiceFile:test_simple ()
local S = [[
<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
	<serviceStateTable>
    <stateVariable sendEvents="no">
      <name>var1</name>
      <dataType>string</dataType>
      <shortCode>shortVarName</shortCode>
    </stateVariable>	
	</serviceStateTable>
  <actionList>
     <action>
      <name>act1</name>
      <argumentList>
        <argument>
          <name>input</name>
          <direction>in</direction>
        </argument>
      </argumentList>
    </action>  
    <action>
    <name>act_two</name>
      <argumentList>
        <argument>
          <name>output</name>
          <direction>out</direction>
          <relatedStateVariable>DevVar</relatedStateVariable>
        </argument>
      </argumentList> 
    </action>
	</actionList>
</scpd>
]]
  local svc_xml = xml.decode (S)
  local s = loader.parse_service_xml (svc_xml) 
  t.assertIsTable (s.actions)
  t.assertEquals (#s.actions, 2)
  
  local a1 = s.actions[1]
  t.assertEquals (a1.name, "act1")
  t.assertEquals (#a1.argumentList, 1)
  local arg1 = a1.argumentList[1]
  t.assertEquals (arg1.name, "input")
  t.assertEquals (arg1.direction, "in")
  
  local a2 = s.actions[2]
  t.assertEquals (a2.name, "act_two")
  t.assertEquals (#a2.argumentList, 1)
  local arg2_1 = a2.argumentList[1]
  t.assertEquals (arg2_1.name, "output")
  t.assertEquals (arg2_1.direction, "out")
  
  t.assertIsTable (s.returns)
  t.assertItemsEquals (s.returns, {{output = "DevVar"}})
  t.assertIsTable (s.short_codes)
  t.assertItemsEquals (s.short_codes, {var1 = "shortVarName"})
  t.assertIsTable (s.variables)
  t.assertItemsEquals (#s.variables, 1)
  t.assertItemsEquals (s.variables[1], {name="var1", shortCode="shortVarName", dataType="string"})
end
  
function TestServiceFile:test_long_srv_file ()
  local svc_xml = xml.decode (S)
  local s = loader.parse_service_xml (svc_xml) 
  t.assertIsTable (s.actions)      
  t.assertIsTable (s.returns)      
  t.assertIsTable (s.variables)   
  t.assertIsTable (s.short_codes) 
  t.assertEquals (#s.actions, 11)
  t.assertTrue (#s.returns == 0)
  t.assertEquals (#s.variables, 23)
  t.assertTrue (#s.short_codes == 0)
  -- actions
  for i,a in ipairs (s.actions) do
    local argument = a.argumentList.argument
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



local Scomment = [[
<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion>
      <major>1</major>
      <minor>0</minor>
  </specVersion>
	<serviceStateTable>
    <stateVariable sendEvents="no">
      <name>metadata</name>
      <dataType>string</dataType>
    </stateVariable>	
	</serviceStateTable>
  <actionList>
     <action>
<!--      <name>update_plugin</name>
      <argumentList>
        <argument>
          <name>metadata</name>
          <direction>in</direction>
        </argument>
      </argumentList>
    </action>  
    <action>
    <name>update_plugin</name>
      <argumentList>
        <argument>
          <name>metadata</name>
          <direction>in</direction>
        </argument>
      </argumentList> -->
    </action>
	</actionList>
</scpd>
]]


TestServiceFileComments = {}

function TestServiceFileComments:test_comments ()
  local a = loader.parse_service_xml (xml.decode(Scomment))
  t.assertIsTable (a)
  t.assertIsTable (a.actions)
  t.assertEquals (#a.actions, 0)
end



-------------------

if multifile then return end

t.LuaUnit.run "-v" 

-------------------


do return end

-------------------


local lfs = require "lfs"
local N = 0

local function test_files (dir, pattern, reader, compile)
  for fname in lfs.dir (dir) do
    if fname: match (pattern) then
      N = N + 1
      print (N, dir .. fname, "-----")
      local lua, msg = reader (dir .. fname)
      if not lua then print (msg) end
--      print (pretty(lua))
      if compile and lua.source_code then
        local env,err = loader.compile_lua (lua.source_code, fname)
        if not env then print(err) end
      end
    end
  end
end

test_files ("./", "^S_.*%.xml$", loader.read_service)
test_files ("./files/", "^S_.*%.xml$", loader.read_service)

test_files ("./", "^D_.*%.xml$", loader.read_device)
test_files ("./files/", "^D_.*%.xml$", loader.read_device)

test_files ("./", "^I_.*%.xml$", loader.read_impl)
test_files ("./files/", "^I_.*%.xml$", loader.read_impl, false) -- or true to test compile

-----
