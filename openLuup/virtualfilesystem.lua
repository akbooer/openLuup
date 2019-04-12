local ABOUT = {
  NAME          = "openLuup.virtualfilesystem",
  VERSION       = "2019.04.09",
  DESCRIPTION   = "Virtual storage for Device, Implementation, Service XML and JSON files, and more",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2019 AK Booer

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
]]
}

local mime = require "mime"     -- for base64 decoding

-- the loader cache is preset with these files

-- the local references mean that these files will not be removed from the 
-- ephemeral cache table by garbage collection 
--
-- openLuup reload script files and index.html to redirect to AltUI.
-- device files for "openLuup", "AltAppStore", and "VeraBridge". 
-- DataYours configuration files.

local openLuup_svg = [[
<svg width="60px" height="60px" viewBox="0 0 12 12" xmlns="http://www.w3.org/2000/svg" style="border: 0; margin: 0; background-color:#F0F0F0;">
 <g style="stroke-width:3; fill:#CA6C5E;">
  <rect y="1" x="1" height="6" width="10"/>
  <rect y="7" x="3" height="3" width="6"/>
  <rect y="9" x="1" height="2" width="10"/></g>
 <g style="stroke-width:3; fill:#F0F0F0;">
  <rect y="3" x="3" height="4" width="6"/>
  <rect y="0" x="5" height="12" width="2"/></g></svg>
]]

local D_openLuup_dev = [[
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>openLuup</deviceType>
    <friendlyName>openLuup</friendlyName>
    <manufacturer>akbooer</manufacturer>
    <staticJson>D_openLuup.json</staticJson>
    <serviceList>
      <service>
        <serviceType>openLuup</serviceType>
        <serviceId>openLuup</serviceId>
        <SCPDURL>S_openLuup.xml</SCPDURL>
      </service>
    </serviceList>
    <implementationList>
      <implementationFile>I_openLuup.xml</implementationFile>
    </implementationList>
  </device>
</root>
]]

--  "default_icon": "https://avatars.githubusercontent.com/u/4962913",
local D_openLuup_json = [[
{
  "default_icon": "openLuup.svg",
	"Tabs": [
		{
			"Label": {
				"lang_tag": "tabname_control",
				"text": "Control"
			},
			"Position": "0",
			"TabType": "flash",
			"ControlGroup":[
				{
					"id": "1",
					"scenegroup": "1"
				}
			],
			"SceneGroup":[
				{
					"id": "1",
					"top": "1.5",
					"left": "0.25",
					"x": "1.5",
					"y": "2"
				}
			],
			"Control": [
				{
					"ControlGroup":"1",
					"ControlType": "variable",
					"top": "0",
					"left": "0",
					"Display": {
						"Service": "urn:upnp-org:serviceId:altui1",
						"Variable": "DisplayLine1",
						"Top": 40,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"1",
					"ControlType": "variable",
					"top": "1",
					"left": "0",
					"Display": {
						"Service": "urn:upnp-org:serviceId:altui1",
						"Variable": "DisplayLine2",
						"Top": 60,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"2",
					"ControlType": "variable",
					"top": "3",
					"left": "0",
					"Display": {
						"Service": "openLuup",
						"Variable": "StartTime",
						"Top": 100,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"2",
					"ControlType": "variable",
					"top": "3",
					"left": "0",
					"Display": {
						"Service": "openLuup",
						"Variable": "Version",
						"Top": 120,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"2",
					"ControlType": "label",
					"top": "4",
					"left": "0",
					"Label": {
						"lang_tag": "donate",
						"text": "<a href='console' target='_blank'>CONSOLE interface</a>"
					},
					"Display": {
						"Top": 160,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"2",
					"ControlType": "label",
					"top": "4",
					"left": "0",
					"Label": {
						"lang_tag": "donate",
						"text": "<a href='https:\/\/www.justgiving.com\/DataYours\/' target='_blank'>If you like openLuup, you could DONATE to Cancer Research UK right here</a>"
					},
					"Display": {
						"Top": 200,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				}
			]
		}
  ],
  "eventList2": [
    {
      "id": 1,
      "label": {
        "lang_tag": "triggers_are_not_implemented",
        "text": "Triggers not implemented, use Watch instead"
      },
      "serviceId": "openLuup",
      "argumentList": []
    }
  ],
  "DeviceType": "openLuup"
}
]]

local I_openLuup_impl = [[
<?xml version="1.0"?>
<implementation>
  <files>openLuup/L_openLuup.lua</files>
  <startup>init</startup>
  <actionList>
    
    <action>
      <serviceId>openLuup</serviceId>
      <name>SendToTrash</name>
      <job>
        SendToTrash (lul_settings)
      </job>
    </action>
    
    <action>
      <serviceId>openLuup</serviceId>
      <name>EmptyTrash</name>
      <job>
        EmptyTrash (lul_settings)
      </job>
    </action>
    
    <action>
      <serviceId>openLuup</serviceId>
      <name>SetHouseMode</name>
      <run>
        local sid = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"
        luup.call_action (sid, "SetHouseMode", lul_settings)
      </run>
    </action>

    <action>    <!-- added by @rafale77 -->
      <serviceId>openLuup</serviceId>
      <name>RunScene</name>
      <run>
        local sid = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"
        luup.call_action(sid, "RunScene", {SceneNum = lul_settings.SceneNum}, 0)
      </run>
    </action>
  
  </actionList>
</implementation>
]]

local S_openLuup_svc = [[
<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  
 	<serviceStateTable>  <!-- added just for fun to expose these as device status -->
    <stateVariable> <name>CpuLoad</name> <shortCode>cpu_load</shortCode> </stateVariable>	
    <stateVariable> <name>Memory_Mb</name> <shortCode>memory_mb</shortCode> </stateVariable>	
    <stateVariable> <name>Uptime_Days</name> <shortCode>uptime_days</shortCode> </stateVariable>	
	</serviceStateTable>
  
  <actionList>

    <action>
      <name>SendToTrash</name>
      <argumentList>
        <argument> <name>Folder</name> <direction>in</direction> </argument>
        <argument> <name>MaxDays</name> <direction>in</direction> </argument>
        <argument> <name>MaxFiles</name> <direction>in</direction> </argument>
        <argument> <name>FileTypes</name> <direction>in</direction>
        </argument>
      </argumentList>
    </action>
  
    <action>
      <name>EmptyTrash</name>
      <argumentList>
        <argument> <name>AreYouSure</name> <direction>in</direction> </argument>
      </argumentList>
    </action>
  
    <action>
      <name>SetHouseMode</name>
      <argumentList>
        <argument> <name>Mode</name> <direction>in</direction> </argument>
      </argumentList>
    </action>
    
    <action>    <!-- added by @rafale77 -->
      <name>RunScene</name>
      <argumentList>
        <argument> <name>SceneNum</name> <direction>in</direction> </argument>
      </argumentList>
    </action>

  </actionList>
</scpd>
]]

-----
--
-- AltAppStore device files
--

local AltAppStore_png = mime.unb64 [[
iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAABmJLR0QA/wD/AP+gvaeTAAADRElEQVRoge2YTWhUVxTHfye+aYJo
QerXTpPGQrupi4DdyFAIxkwiMXSlixaxAW1rIBq6ysKFS0OLogguXIjfaKI4BpzQJjFdCIUi2BJoMoFCA9VgJB84zEzecWEq8ubN
OPe+N6OL91uee+45/3Pvu+e9dyEiIiIiIgBiO3F8QtdmanMHQDpU+RTYCDxDeaw1ejufj11IbJP58KT6Y1XA/an8PhH9mVeiizGr
Kt27Pnau2EkrjxrTCal0rk9EL1NaPMB6Eb2cSuf67KSVh9EOrKz8JdN5IrKvud65mprOfgEcwZU4wkbgKegDFznb0hAbM4n5Ona5
juMTuvbFB/lJ3r7yfjwFGQTtKuqhcm7d3KrupibJmQR2ynXM1OYOoGIjHmBDSfEAoofm1i0DHDYJbHAGpMMksBWih4bTuZ0mU8ou
QJXPzBWZ46p+Z+Jv0oU+MtRihSCV2QGBRXM5FgibzdxLMDyV+URxekTc3YpsDSDLlCWBSSAJzqnmBvmvmGPRAlLp7A8gJ4HaSig0
YFFEuprrnat+g74FpKayhxE5a5vxxLH7vva+/l22IVVE9vsVUXAGhqZfbEXkJ9tMFUJU9fxwWjd5BwoKcHC6efePjR9rlPwRr7Gw
CymtVZFjgUC71+bXRrdUQYsVCg1em18B2SposUW9Br8C/q6CEFvSXoNfAYNVEGLLXa+hsAuJcwaYrYocMxZc1zntNRYU8GW9PBfY
Dxj9WFQYFZGulkZ54h3w/ZhrboilXJfdwEzFpb2dhZVf0mt+g0W/RlsaY79k6pxtovq9KkPABFDxa5IVFoE/gBOu6zQWEw8B7oVK
Ee9MFrQ7gNGBttDzGV+rvG8EXpF4Z7IfOGqVXLV/ZLC9N0j+wDswOpDoRbloMfX6yPbffwyaP4RHSHQ2tvQtynC5MxRGV2fka44f
dwNnDxrgf3a03vuwrk7HgM9Le+qfy1l2jifb58LIG9ohfjiUmM8v5xMo/5Rw+3fZ0URY4iHkLvTbnY4ZV6UV8BM4X4PbNn5jT6kC
jQm9jT64nfhLhb1A5g1zVmr0q18H9jwKO19F3gNjt9rGVPkGcAEV1YMjN9vLPuTvDfHOZE+8M9nzrnVEREREVI6XP436aXY3NrkA
AAAASUVORK5CYII=]]

local D_AltAppStore_dev = [[
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:AltAppStore:1</deviceType>
    <friendlyName>Alternate App Store</friendlyName>
    <manufacturer></manufacturer>
    <manufacturerURL></manufacturerURL>
    <modelDescription>AltUI App Store</modelDescription>
    <modelName></modelName>
    <modelNumber></modelNumber>
    <Category_Num>1</Category_Num>
    <UDN></UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AltAppStore:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:AltAppStore1</serviceId>
        <SCPDURL>S_AltAppStore.xml</SCPDURL>
      </service>
    </serviceList>
		<staticJson>D_AltAppStore.json</staticJson>
    <implementationList>
      <implementationFile>I_AltAppStore.xml</implementationFile>
    </implementationList>
  </device>
</root>
]]

local D_AltAppStore_json = [[
{
	"flashicon": "http://raw.githubusercontent.com/akbooer/AltAppStore/master/AltAppStore.png",
	"default_icon": "AltAppStore.png",
	"x": "2",
	"y": "3",
	"Tabs": [
		{
			"Label": {
				"lang_tag": "tabname_control",
				"text": "Control"
			},
			"Position": "0",
			"TabType": "flash",
			"ControlGroup":[
				{
					"id": "1",
					"scenegroup": "1"
				}
			],
			"SceneGroup":[
				{
					"id": "1",
					"top": "1.5",
					"left": "0.25",
					"x": "1.5",
					"y": "2"
				}
			],
			"Control": [
				{
					"ControlGroup":"1",
					"ControlType": "variable",
					"top": "0",
					"left": "0",
					"Display": {
						"Service": "urn:upnp-org:serviceId:altui1",
						"Variable": "DisplayLine1",
						"Top": 40,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"1",
					"ControlType": "variable",
					"top": "1",
					"left": "0",
					"Display": {
						"Service": "urn:upnp-org:serviceId:altui1",
						"Variable": "DisplayLine2",
						"Top": 60,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"2",
					"ControlType": "variable",
					"top": "3",
					"left": "0",
					"Display": {
						"Service": "urn:upnp-org:serviceId:AltAppStore1",
						"Variable": "Version",
						"Top": 100,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"2",
					"ControlType": "label",
					"top": "4",
					"left": "0",
					"Label": {
						"lang_tag": "icons8",
						"text": "<a href='https://icons8.com/license/' target='_blank'>icon by icons8</a>"
					},
					"Display": {
						"Top": 120,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				}
			]
		}
  ],
	"DeviceType": "urn:schemas-upnp-org:device:AltAppStore:1"
}
]]

local I_AltAppStore_impl = [[
<?xml version="1.0"?>
<implementation>
  <files>openLuup/L_AltAppStore.lua</files>
  <startup>AltAppStore_init</startup>
  <actionList>
    <action>
  		<serviceId>urn:upnp-org:serviceId:AltAppStore1</serviceId>
  		<name>update_plugin</name>
  		<run>
  			-- lul_device, lul_settings
        return update_plugin_run (lul_settings)
  		</run>
  		<job>
  			return update_plugin_job (lul_settings)
  		</job>
    </action>
  </actionList>
</implementation>
]]

local S_AltAppStore_svc = [[
<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion>
      <major>1</major>
      <minor>0</minor>
  </specVersion>
	<serviceStateTable>
    <stateVariable sendEvents="no"> <name>metadata</name> <dataType>string</dataType> </stateVariable>	
	</serviceStateTable>
  <actionList>
    <action>
      <name>update_plugin</name>
      <argumentList>
        <argument <name>metadata</name> <direction>in</direction> </argument>
      </argumentList>
    </action>
	</actionList>
</scpd>
]]


-----
--
-- VeraBridge device files
--

-- http://raw.githubusercontent.com/akbooer/openLuup/master/icons/VeraBridge.png
local VeraBridge_png = mime.unb64 [[
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]]

local D_VeraBridge_dev = [[
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>VeraBridge</deviceType>
    <friendlyName>Vera Bridge</friendlyName>
    <manufacturer>akbooer</manufacturer>
    <manufacturerURL></manufacturerURL>
    <modelDescription>Vera Bridge for openLuup</modelDescription>
    <modelName>VeraBridge</modelName>
    <modelNumber>3</modelNumber>
    <handleChildren>1</handleChildren>
    <Category_Num>1</Category_Num>
    <UDN></UDN>
    <serviceList>
      <service>
        <serviceType>urn:akbooer-com:service:VeraBridge:1</serviceType>
        <serviceId>urn:akbooer-com:serviceId:VeraBridge1</serviceId>
        <SCPDURL>S_VeraBridge.xml</SCPDURL>
      </service>
    </serviceList>
		<staticJson>D_VeraBridge.json</staticJson>
    <implementationList>
      <implementationFile>I_VeraBridge.xml</implementationFile>
    </implementationList>
  </device>
</root>
]]


local D_VeraBridge_json = [[
{
	"default_icon": "VeraBridge.png",
	"Tabs": [
		{
			"Label": {
				"lang_tag": "tabname_control",
				"text": "Control"
			},
			"Position": "0",
			"TabType": "flash",
			"ControlGroup":[
				{
					"id": "1",
					"scenegroup": "1"
				}
			],
			"SceneGroup":[
				{
					"id": "1",
					"top": "1.5",
					"left": "0.25",
					"x": "1.5",
					"y": "2"
				}
			],
			"Control": [
				{
					"ControlGroup":"1",
					"ControlType": "variable",
					"top": "0",
					"left": "0",
					"Display": {
						"Service": "urn:upnp-org:serviceId:altui1",
						"Variable": "DisplayLine1",
						"Top": 40,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"1",
					"ControlType": "variable",
					"top": "1",
					"left": "0",
					"Display": {
						"Service": "urn:upnp-org:serviceId:altui1",
						"Variable": "DisplayLine2",
						"Top": 60,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"2",
					"ControlType": "variable",
					"top": "3",
					"left": "0",
					"Display": {
						"Service": "urn:akbooer-com:serviceId:VeraBridge1",
						"Variable": "Version",
						"Top": 100,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				}
			]
		}
  ],
	"DeviceType": "VeraBridge"
}
]]

local I_VeraBridge_impl = [[
<?xml version="1.0"?>
<implementation>
  <files>openLuup/L_VeraBridge.lua</files>
  <startup>init</startup>
  <actionList>
    
    <action>
  		<serviceId>urn:akbooer-com:serviceId:VeraBridge1</serviceId>
  		<name>GetVeraFiles</name>
  		<job>
  			GetVeraFiles (lul_settings)
  			return 4,0
  		</job>
    </action>
    
    <action>
  		<serviceId>urn:akbooer-com:serviceId:VeraBridge1</serviceId>
  		<name>GetVeraScenes</name>
  		<job>
  			GetVeraScenes ()
  			return 4,0
  		</job>
    </action>
    
    <action>
  		<serviceId>urn:akbooer-com:serviceId:VeraBridge1</serviceId>
  		<name>RemoteVariableSet</name>
  		<job>
  			RemoteVariableSet (lul_settings)
  			return 4,0
  		</job>
    </action>
    
    <action>
      <!-- added here to allow scenes to access this as an action (Device 0 is not visible) -->
  		<serviceId>urn:akbooer-com:serviceId:VeraBridge1</serviceId>
  		<name>SetHouseMode</name>
  		<job>
  			SetHouseMode (lul_settings)
  			return 4,0
  		</job>
    </action>
  
  </actionList>
</implementation>
]]

local S_VeraBridge_svc = [[
<?xml version="1.0"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
 
 	<serviceStateTable>  <!-- added just for fun to expose these as device status -->
    <stateVariable> <name>LoadTime</name> <shortCode>loadtime</shortCode> </stateVariable>	
    <stateVariable> <name>LastUpdate</name> <shortCode>lastupdate</shortCode> </stateVariable>	
    <stateVariable> <name>HouseMode</name> <shortCode>housemode</shortCode> </stateVariable>	
	</serviceStateTable>
  <actionList>
    
    <action>
      <name>GetVeraFiles</name> 
      <argumentList> <argument> <name>Files</name> <direction>in</direction> </argument> </argumentList>
    </action>
    
    <action> <name>GetVeraScenes</name> </action>
    
<!-- by analogy to this request...
  /data_request?id=variableset&DeviceNum=6&serviceId=urn:micasaverde-com:serviceId:DoorLock1&Variable=Status&Value=
-->>
    <action>
      <name>RemoteVariableSet</name>
      <argumentList>
        <argument> <name>RemoteDevice</name> <direction>in</direction> </argument>
        <argument> <name>RemoteServiceId</name> <direction>in</direction> </argument>
        <argument> <name>RemoteVariable</name> <direction>in</direction> </argument>
        <argument> <name>Value</name> <direction>in</direction> </argument>
      </argumentList>
    </action>
    
    <action>
      <name>SetHouseMode</name>
      <argumentList>
        <argument> <name>Mode</name> <direction>in</direction> </argument>
      </argumentList>
    </action>

  </actionList>
</scpd>
]]


-----

-- Default values for installed plugins

-----

-- other install files

local index_html = [[
<!DOCTYPE html>
<html>
  <head>
    <!-- HTML meta refresh URL redirection -->
    <meta http-equiv="refresh" content="0; url=/data_request?id=lr_ALTUI_Handler&command=home#">
  </head>
</html>
]]

local openLuup_reload = [[
#!/bin/sh
#
# reload loop for openLuup
# @akbooer, Aug 2015
# you may need to change ‘lua5.1’ to ‘lua’ depending on your install

lua5.1 openLuup/init.lua $1

while [ $? -eq 42 ]
do
   lua5.1 openLuup/init.lua
done
]]

local openLuup_reload_bat = [[
@ECHO OFF
SETLOCAL
SET LUA_DEV=D:\devhome\app\LuaDist\bin
SET CURRENT_PATH=%~dp0
ECHO Start openLuup from "%CURRENT_PATH%"
ECHO.
CD %CURRENT_PATH%
"%LUA_DEV%\lua" openLuup\init.lua %1

:loop
IF NOT %ERRORLEVEL% == 42 GOTO exit
"%LUA_DEV%\lua" openLuup\init.lua
GOTO loop

:exit
]]


-----
--
-- Z-Way support
--
local D_ZWay_xml = [[
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:akbooer-com:device:ZWay:1</deviceType>
    <friendlyName>ZWay Network Interface</friendlyName>
    <manufacturer>akbooer</manufacturer>
    <manufacturerURL></manufacturerURL>
    <modelDescription>ZWay Network</modelDescription>
    <modelName></modelName>
    <modelNumber></modelNumber>
    <serviceList>
      <service>
        <serviceType>urn:schemas-micasaverde-org:service:ZWaveNetwork:1</serviceType>
        <serviceId>urn:micasaverde-com:serviceId:ZWaveNetwork1</serviceId>
        <controlURL>/upnp/control/ZWaveNetwork1</controlURL>
        <eventSubURL>/upnp/event/ZWaveNetwork1</eventSubURL>
        <SCPDURL>S_ZWaveNetwork1.xml</SCPDURL>
      </service>
    </serviceList>
    <implementationList>
      <implementationFile>I_ZWay.xml</implementationFile>
    </implementationList>
		<staticJson>D_ZWay.json</staticJson>
  </device>
</root>
]]


local D_ZWay_json = [[
{
  "default_icon": "http://raw.githubusercontent.com/akbooer/Z-Way/master/icons/Z-Wave.me.png",
	"Tabs": [
		{
			"Label": {
				"lang_tag": "tabname_control",
				"text": "Control"
			},
			"Position": "0",
			"TabType": "flash",
			"ControlGroup":[
				{
					"id": "1",
					"scenegroup": "1"
				}
			],
			"SceneGroup":[
				{
					"id": "1",
					"top": "1.5",
					"left": "0.25",
					"x": "1.5",
					"y": "2"
				}
			],
			"Control": [
				{
					"ControlGroup":"1",
					"ControlType": "variable",
					"top": "0",
					"left": "0",
					"Display": {
						"Service": "urn:upnp-org:serviceId:altui1",
						"Variable": "DisplayLine1",
						"Top": 40,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"1",
					"ControlType": "variable",
					"top": "1",
					"left": "0",
					"Display": {
						"Service": "urn:upnp-org:serviceId:altui1",
						"Variable": "DisplayLine2",
						"Top": 60,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				},
				{
					"ControlGroup":"2",
					"ControlType": "variable",
					"top": "3",
					"left": "0",
					"Display": {
						"Service": "urn:akbooer-com:serviceId:ZWay1",
						"Variable": "Version",
						"Top": 100,
						"Left": 50,
						"Width": 75,
						"Height": 20
					}
				}
			]
		}
  ],
  "DeviceType": "urn:akbooer-com:device:ZWay:1"
}
]]

local I_ZWay_xml = [[
<?xml version="1.0"?>
<implementation>
  <functions>
    local M = require "L_ZWay"
    ABOUT = M.ABOUT   -- make this global (for InstalledPlugins version update)
    function startup (...)
      return M.init (...)
    end
  </functions>
  <startup>startup</startup>
</implementation>
]]

-- testing new ZWay implementation
local I_ZWay2_xml = [[
<?xml version="1.0"?>
<implementation>
  <handleChildren>1</handleChildren>
  <functions>
    local M = require "L_ZWay2"
    ABOUT = M.ABOUT   -- make this global (for InstalledPlugins version update)
    function startup (...)
      return M.init (...)
    end
  </functions>
  <startup>startup</startup>
</implementation>
]]

-- Camera with child Motion Detector triggered by email
local I_openLuupCamera1_xml = [[
<?xml version="1.0"?>
<implementation>
  <handleChildren>1</handleChildren>
  <functions>
    TIMEOUT = 30    -- global, so can be changed externally
    local child -- the motion sensor
    local smtp = require "openLuup.smtp"
    local requests = require "openLuup.requests"
    local sid = "urn:micasaverde-com:serviceId:SecuritySensor1"
    function get (name)
      return (luup.variable_get (sid, name, child))
    end
    function set (name, val)
      if val ~= get (name) then
        luup.variable_set (sid, name, val, child)
      end
    end
    function archive (p)
      requests.archive_video ("archive_video", p)
    end
    local function openLuupCamera (ip, mail)      -- email callback
      set ("Tripped", '1')
    end
    function startup (devNo)
      do -- install MotionSensor as child device
        local var = "urn:micasaverde-com:serviceId:SecuritySensor1,%s=%s\n"
        local statevariables = table.concat {
            var:format("Armed",1), 
            var:format("ArmedTripped", 0),
            var:format("Tripped", 0), 
            var:format("LastTrip", 0),
            var:format("AutoUntrip", TIMEOUT),   -- default timeout
          }
        local ptr = luup.chdev.start (devNo)
        local altid = "openLuupCamera"
        local description = luup.devices[devNo].description .." Motion Sensor"
        local device_type = "urn:schemas-micasaverde-com:device:MotionSensor:1"
        local upnp_file = "D_MotionSensor1.xml"
        local upnp_impl = ''
        luup.chdev.append (devNo, ptr, altid, description, device_type, upnp_file, upnp_impl, statevariables)
        luup.chdev.sync (devNo, ptr)  
      end
      for dnum,d in pairs (luup.devices) do
        if d.device_num_parent == devNo then
          child = dnum
          luup.attr_set ("subcategory_num", 3, child)  -- motion detector subtype
        end
      end
      local ip = luup.attr_get ("ip", devNo)
      ip = (ip or ''): match "%d+%.%d+%.%d+%.%d+"
      if ip then
        smtp.register_handler (openLuupCamera, ip)     -- receive mail from camera IP
      end
      return true, "OK", "I_openLuupCamera1"
    end
  </functions>
  <actionList>
    
    <action>
  		<serviceId>urn:micasaverde-com:serviceId:SecuritySensor1</serviceId>
      <name>SetArmed</name>
      <run>
        set ("Armed", lul_settings.newArmedValue)
      </run>
    </action>
    
    <action>
      <serviceId>urn:micasaverde-com:serviceId:Camera1</serviceId>
      <name>ArchiveVideo</name>
      <job>
        local p = lul_settings
        archive {cam = lul_device, Format = p.Format, Duration = p.Duration}
      </job>
    </action>
  
  </actionList>
  <startup>startup</startup>
</implementation>
]]

local I_openLuupSecurity1_xml = [[
<?xml version="1.0"?>
<implementation>
  <functions>
    function startup (...)
    end
  </functions>
  <actionList>
    
    <action>
  		<serviceId>urn:micasaverde-com:serviceId:SecuritySensor1</serviceId>
      <name>SetArmed</name>
      <run>
        local sid = "urn:micasaverde-com:serviceId:SecuritySensor1"
        luup.variable_set (sid, "Armed", lul_settings.newArmedValue or 0, lul_device)
      </run>
    </action>
  
  </actionList>
  <startup>startup</startup>
</implementation>
]]

local I_Dummy_xml = [[
<?xml version="1.0"?>
  <implementation />
]]

-----
--
-- DataYours schema and aggregation definitions for AltUI DataStorage Provider
--

--[[

    retentionDef = timePerPoint (resolution) and timeToStore (retention) specify lengths of time, for example:
    units are: (s)econd, (m)inute, (h)our, (d)ay, (y)ear    (no months or weeks)
      
      60:1440      60 seconds per datapoint, 1440 datapoints = 1 day of retention
      15m:8        15 minutes per datapoint, 8 datapoints = 2 hours of retention
      1h:7d        1 hour per datapoint, 7 days of retention
      12h:2y       12 hours per datapoint, 2 years of retention

    An ArchiveList must:
        1. Have at least one archive config. Example: (60, 86400)
        2. No archive may be a duplicate of another.
        3. Higher precision archives' precision must evenly divide all lower precision archives' precision.
        4. Lower precision archives must cover larger time intervals than higher precision archives.
        5. Each archive must have at least enough points to consolidate to the next archive

    Aggregation types are: 'average', 'sum', 'last', 'max', 'min'
    XFilesFactor is a float: 0.0 - 1.0

    see: http://graphite.readthedocs.io/en/latest/whisper.html",

--]]

local storage_schemas_conf = [[
#
# Schema definitions for Whisper files. Entries are scanned in order,
# and first match wins. This file is read whenever a file create is required.
#
#  [name]  (used in log reporting)
#  pattern = regex 
#  retentions = timePerPoint:timeToStore, timePerPoint:timeToStore, ...

#  2016.01.24  @akbooer
#  basic patterns for AltUI Data Storage Provider
#  names are DURATION of single archive

[for_1d]
pattern = \.d$
retentions = 1m:1d

[for_7d]
pattern = \.w$
retentions = 5m:7d

[for_30d]
pattern = \.m$
retentions = 20m:30d

[for_90d]
pattern = \.q$
retentions = 1h:90d

[for_1y]
pattern = \.y$
retentions = 6h:1y

[for_10y]
pattern = \.y$
retentions = 1d:10y

#  2017.02.14  @akbooer
#  EXTENDED (10 year) patterns for AltUI Data Storage Provider
#  names are SAMPLE RATES, with multiple archives aggregated at various rates for 10 years

[every_1s]        # used for security sensors, etc.
pattern = \.1s$
retentions = 1s:1m,1m:1d,10m:7d,1h:30d,3h:1y,1d:10y
[every_1m]
pattern = \.1m$
retentions = 1m:1d,10m:7d,1h:30d,3h:1y,1d:10y

[every_5m]
pattern = \.5m$
retentions = 5m:7d,1h:30d,3h:1y,1d:10y

[every_10m]
pattern = \.10m$
retentions = 10m:7d,1h:30d,3h:1y,1d:10y

[every_20m]
pattern = \.20m$
retentions = 20m:30d,3h:1y,1d:10y

[every_1h]
pattern = \.1h$
retentions = 1h:90d,3h:1y,1d:10y

[every_3h]
pattern = \.3h$
retentions = 3h:1y,1d:10y

[every_6h]
pattern = \.6h$
retentions = 6h:1y,1d:10y

[every_1d]
pattern = \.1d$
retentions = 1d:10y

]]

local storage_aggregation_conf = [[
#
#Aggregation methods for whisper files. Entries are scanned in order,
# and first match wins. This file is read whenever a file create is required.
#
#  [name]
#  pattern = <regex>    
#  xFilesFactor = <float between 0 and 1>
#  aggregationMethod = <average|sum|last|max|min>
#
#  name: Arbitrary unique name for the rule
#  pattern: Regex pattern to match against the metric name
#  xFilesFactor: Ratio of valid data points required for aggregation to the next retention to occur
#  aggregationMethod: function to apply to data points for aggregation
#
#  2014.02.22  @akbooer

#
[maxima]
pattern = [Mm]ax
xFilesFactor = 0
aggregationMethod = maximum

#
[minima]
pattern = [Mm]in
xFilesFactor = 0
aggregationMethod = minimum

#
[otherwise]
pattern = .
xFilesFactor = 0
aggregationMethod = average

]]

local unknown_wsp = [[
          1,      86400,        0.5,          1
         84,      86400,          1
          0,                      0
]]

--
-- Style sheets for console web pages
--

local console_css = [[

  /* Style sheets for console web pages */
  
  *    { box-sizing:border-box; margin:0px; padding:0px; }
  html { width:100%; height:100%; overflow:hidden; border:none 0px; }
  body { font-family:Arial; background:LightGray; width:100%; height:100%; overflow:hidden; padding-top:60px; }
  
  .menu { position:absolute; top:0px; width:100%; height:60px; }
  .content { width:100%; height:100%; overflow:scroll; padding:4px; }
  
  .dropbtn {
    background-color: Sienna;
    color: white;
    padding: 16px;
    font-size: 16px;
    line-height:18px;
    vertical-align:middle;
    border: none;
    cursor: pointer;
  }

  .dropdown {
    position: relative;
    display: inline-block;
  }

  .dropdown-content {
    display: none;
    position: absolute;
    background-color: Sienna;
    min-width: 160px;
    border-top:1px solid Gray;
    box-shadow: 0px 8px 16px 0px rgba(0,0,0,0.5);
  }

  .dropdown-content a {
    color: white;
    padding: 12px 16px;
    text-decoration: none;
    display: block;
  }

  .dropdown-content a:hover {background-color: SaddleBrown}

  .dropdown:hover .dropdown-content {
    display: block;
  }

  .dropdown:hover .dropbtn {
    background-color: SaddleBrown;
  }
  
  pre {margin-top: 20px;}
  footer {margin-top: 20px; margin-bottom: 20px; }
  
  table {table-layout:fixed; font-size:10pt; font-family: "Arial", "Helvetica", "sans-serif"; margin-top:20px}
  th,td {width:1px; white-space:nowrap; padding: 0 15px 0 15px;}
  th {background: DarkGray; color:Black;}
  tr:nth-child(even) {background: LightGray;}
  tr:nth-child(odd)  {background: Silver;}

]]

local graphite_css = [[
  .bar {cursor: crosshair; }
  .bar:hover, .bar:focus {fill: DarkGray; }
  rect {fill:LightSteelBlue; stroke-width:3px; stroke:LightSteelBlue; }
]]


-----

local manifest = {
    
    ["icons/openLuup.svg"] = openLuup_svg,
    ["D_openLuup.xml"]  = D_openLuup_dev,
    ["D_openLuup.json"] = D_openLuup_json,
    ["I_openLuup.xml"]  = I_openLuup_impl,
    ["S_openLuup.xml"]  = S_openLuup_svc,
    
    ["icons/AltAppStore.png"] = AltAppStore_png,
    ["D_AltAppStore.xml"]  = D_AltAppStore_dev,
    ["D_AltAppStore.json"] = D_AltAppStore_json,
    ["I_AltAppStore.xml"]  = I_AltAppStore_impl,
    ["S_AltAppStore.xml"]  = S_AltAppStore_svc,
    
    ["icons/VeraBridge.png"] = VeraBridge_png,
    ["D_VeraBridge.xml"]  = D_VeraBridge_dev,
    ["D_VeraBridge.json"] = D_VeraBridge_json,
    ["I_VeraBridge.xml"]  = I_VeraBridge_impl,
    ["S_VeraBridge.xml"]  = S_VeraBridge_svc,
    
    ["D_ZWay.xml"]  = D_ZWay_xml,
    ["D_ZWay.json"] = D_ZWay_json,
    ["I_ZWay.xml"]  = I_ZWay_xml,
    ["I_ZWay2.xml"] = I_ZWay2_xml,    -- TODO: remove after development
    
    ["I_openLuupCamera1.xml"]   = I_openLuupCamera1_xml,
    ["I_openLuupSecurity1.xml"] = I_openLuupSecurity1_xml,
    ["I_Dummy.xml"]             = I_Dummy_xml,
    
    ["index.html"]            = index_html,
    ["openLuup_console.css"]  = console_css,
    ["openLuup_graphite.css"]  = graphite_css,
    
    ["openLuup_reload"]       = openLuup_reload,
    ["openLuup_reload.bat"]   = openLuup_reload_bat,

    ["storage-schemas.conf"]      = storage_schemas_conf,
    ["storage-aggregation.conf"]  = storage_aggregation_conf,
    ["unknown.wsp"]               = unknown_wsp,
    
  }

-----

local hits = {}     -- cache hit count
local function hit (filename)
  local info =  hits[filename] or {n = 0}
  info.n = info.n + 1
  info.access = os.time ()
  hits[filename] = info
end

return {
  ABOUT = ABOUT,
  
--  manifest = setmetatable (manifest, {__mode = "kv"}),
  manifest = manifest,
  
  attributes = function (filename) 
    local y = manifest[filename]
    local h = hits[filename] or {n = 0, access = 0}
    if type(y) == "string" then 
      return {mode = "file", size = #y, permissions = "rw-rw-rw-", access = h.access, hits = h.n} 
    end
  end,
  
  open = function (filename, mode)
    mode = mode or 'r'
    
    local function readline ()
      for line in manifest[filename]:gmatch "%C*" do coroutine.yield (line) end
    end
    
    if mode: match 'r' then
      if manifest[filename] then
        hit (filename)
        return {
          lines = function () return coroutine.wrap (readline) end,
          read  = function () return manifest[filename] end,
          close = function () filename = nil end,
        }
      else
        return nil, "file not found:" .. (filename or '')
      end
    end
    
    if mode: match "w" then
      return {
        write = function (_, contents) manifest[filename] = contents end,
        close = function () filename = nil end,
      }
    end
    
    return nil, "unknown mode for vfs.open: " .. mode
  end,

  dir = function () 
      local idx = {}
      for n in pairs (manifest) do idx[#idx+1] = n end
      table.sort (idx)
      local i = 0
      return function(m) i=i+1; return m[i], i end, idx, 0
    end,
  read  = function (filename) hit(filename) return manifest[filename] end,
  write = function (filename, contents) manifest[filename] = contents end,

}

-----


