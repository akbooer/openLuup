local ABOUT = {
  NAME          = "openLuup.virtualfilesystem",
  VERSION       = "2019.07.12",
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

local json  = require "openLuup.json"             -- for JSON device file encoding
local xml   = require "openLuup.xml"              -- for XML device file encoding

-- the loader cache is preset with these files

-- the local references mean that these files will not be removed from the
-- ephemeral cache table by garbage collection
--
-- openLuup reload script files and index.html to redirect to AltUI.
-- device files for "openLuup", "AltAppStore", and "VeraBridge".
-- DataYours configuration files.

-----
-- utility functions
--

local SID = {
    AltUI = "urn:upnp-org:serviceId:altui1",
    VeraBridge = "urn:akbooer-com:serviceId:VeraBridge1",
  }


local function Display (L,T,W,H, S,V)
  return {Left = L, Top = T, Width = W, Height = H, Service = S, Variable = V,}
end

local function Label (tag, text)
  return {lang_tag = tag, text = tostring(text)}    -- tostring() forces serliaization of html5 elements
end

local function ControlGroup (G,C, L,T, D,Lab)
  return {ControlGroup = tostring(G), ControlType = C, left = tostring(L), top = tostring(T), Display = D, Label=Lab}
end

local function action (S,N, R,J)
  return {serviceId = S, name = N, run = R, job = J}
end

local function argument (N,D, R)
  return {name = N, direction = D or "in", relatedStateVariable = R}
end

-----

local openLuup_svg = (
  function (N)
    local s = xml.createSVGDocument ()
    s:appendChild {
      s.svg {height = N, width  = N,
        viewBox= table.concat ({0, 0,12, 12}, ' '),
        xmlns="http://www.w3.org/2000/svg" ,
        style="border: 0; margin: 0; background-color:#F0F0F0;",
        s.g {style = "stroke-width:3; fill:#CA6C5E;",
          s.rect (1,1, 10, 6) ,
          s.rect (3,7,  6, 3) ,
          s.rect (1,9, 10, 2)  },
        s.g {style = "stroke-width:3; fill:#F0F0F0;",
          s.rect (3,3,  6, 4),
          s.rect (5,0,  2,12)}}}
    return tostring(s)
  end) (60)

local D_openLuup_dev do
  local x = xml.createDocument ()
    x:appendChild {
      x.root {xmlns="urn:schemas-upnp-org:device-1-0",
        x.device {
          x.deviceType    "openLuup",
          x.friendlyName  "openLuup",
          x.manufacturer  "akbooer",
          x.staticJson    "D_openLuup.json",
          x.serviceList {
            x.service {x.serviceType "openLuup", x.serviceId "openLuup", x.SCPDURL "S_openLuup.xml"}},
          x.implementationList {
            x.implementationFile "I_openLuup.xml"
        }}}}
  D_openLuup_dev = tostring (x)
end

local D_openLuup_json = json.encode {
  flashicon = "https://avatars.githubusercontent.com/u/4962913",  -- not used, but here for reference
  default_icon = "openLuup.svg",
  DeviceType = "openLuup",
  Tabs = {{
      Label = Label ("tabname_control", "Control"),
			Position = "0",
			TabType = "flash",
			ControlGroup = { {id = "1",scenegroup = "1"} },
			SceneGroup = { {id = "1", top = "1.5", left = "0.25", x = "1.5",y ="2"} },

    Control = {
      ControlGroup (1, "variable", 0,0,
        Display (50,40, 75,20, SID.AltUI, "DisplayLine1")),
      ControlGroup (1, "variable", 0,1,
        Display (50,60, 75,20, SID.AltUI, "DisplayLine2")),
      ControlGroup (2, "variable", 0,3,
        Display (50,100, 75,20, "openLuup","StartTime")),
      ControlGroup (2,  "variable", 0,3,
        Display (50,120, 75,20,  "openLuup", "Version")),
      ControlGroup (2, "label", 0,4,
        Display (50,160, 75,20),
        Label ("donate", '<a href="console" target="_blank">CONSOLE interface</a>')),
      ControlGroup (2, "label", 0,4,
        Display (50,200, 75,20),
        Label ("donate", '<a href="https://www.justgiving.com/DataYours/" target="_blank">' ..
                "If you like openLuup, you could DONATE to Cancer Research UK right here</a>")),
   }}},
  eventList2 = {
    {id = 1, serviceId = "openLuup",argumentList = {},
      label = Label ("triggers_are_not_implemented", "Triggers not implemented, use Watch instead")},
    }
  }

local I_openLuup_impl do
  local x = xml.createDocument ()
  local function action (S,N, R,J)
    return x.action {x.serviceId (S), x.name (N), x.run(R), x.job (J)}
  end
    x: appendChild {
      x.implementation {
        x.files   "openLuup/L_openLuup.lua",
        x.startup "init",
        x.actionList {
          action ("openLuup", "SendToTrash", nil, "SendToTrash (lul_settings)"),
          action ("openLuup", "EmptyTrash",  nil, "EmptyTrash (lul_settings)"),
          action ("openLuup", "SetHouseMode",
            [[
              local sid = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"
              luup.call_action (sid, "SetHouseMode", lul_settings)
            ]]),
          action ("openLuup", "RunScene",                  -- added by @rafale77 --
            [[
              local sid = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"
              luup.call_action(sid, "RunScene", {SceneNum = lul_settings.SceneNum}, 0)
            ]])
        }}}
  I_openLuup_impl = tostring(x)
end

local S_openLuup_svc do
  local x = xml.createDocument ()
  local function argument (N,D, R)
    return x.argument {x.name (N), x.direction (D or "in"), x.relatedStateVariable (R)}
  end
    x: appendChild {
      x.scpd {xmlns="urn:schemas-upnp-org:service-1-0",
        x.specVersion {x.major "1", x.minor "0"},

        x.serviceStateTable {  -- added just for fun to expose these as device status
          x.stateVariable {x.name "CpuLoad",     x.shortCode "cpu_load"},
          x.stateVariable {x.name "Memory_Mb",   x.shortCode "memory_mb"},
          x.stateVariable {x.name "Uptime_Days", x.shortCode "uptime_days"}},

        x.actionList {

          x.action {x.name "SendToTrash",
            x.argumentList {
              argument "Folder",
              argument "MaxDays",
              argument "MaxFiles",
              argument "FileTypes"}},

          x.action {x.name "EmptyTrash",
            x.argumentList {
              argument "AreYouSure"}},

          x.action {x.name "SetHouseMode",
            x.argumentList {
              argument "Mode"}},

          x.action {x.name "RunScene",
            x.argumentList {
              argument "SceneNum"}},
        }}}
  S_openLuup_svc = tostring(x)
end


-----
--
-- AltAppStore device files
-- This plugin runs on Vera too, so use same device/service files as there...
-- ...rather than Lua-generated by the XML module factory methods
--

local AltAppStore_svg = (
  function (N)
    local s = xml.createSVGDocument ()
    s:appendChild {
      s.svg {height = N, width  = N,
        viewBox= table.concat ({-24,-24, 48,48}, ' '),
        xmlns="http://www.w3.org/2000/svg" ,
        style="border: 0; margin: 0; background-color:White;",
        s.g {style = "stroke-width:3; fill:PowderBlue;",      -- PowderBlue / SkyBlue
          s.rect   (-13, -7, 26, 14),
          s.circle (-13,  0, 7),
          s.circle ( 13,  0, 7),
          s.circle ( -5, -8, 9),
          s.circle (  7, -8, 6)},
        s.g {style = "stroke-width:0; fill:RoyalBlue;",   -- DarkSlateBlue
          s.polygon (
            { 3, 3, 8,  0, -8, -3, -3},
            {-5, 9, 9, 18,  9,  9, -5})}}}
    return tostring(s)
  end) (60)

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
	"default_icon": "AltAppStore.svg",
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
        <argument> <name>metadata</name> <direction>in</direction> </argument>
      </argumentList>
    </action>
	</actionList>
</scpd>
]]


-----
--
-- VeraBridge device files
--

local VeraBridge_svg = (
  function (N)
    local background = "White"
    local Grey = "#504035"  -- was "#404040"
    local mystyle = "fill:%s; stroke-width:%s; stroke:%s;"
    local s = xml.createSVGDocument ()
    s:appendChild {
      s.svg {height = N, width  = N,
        viewBox= table.concat ({-24,-24, 48,48}, ' '),
        xmlns="http://www.w3.org/2000/svg" ,
        style="border: 1; margin: 0; background-color:" .. background,
      s.g {style= mystyle:format ("none", 3, Grey),
        s.circle (0,5, 17.5),
        s.circle (0,5, 23)},
      s.g {style= mystyle: format (background, 0, background),
        s.polygon ({-24, -24, -16,0,16, 24,24}, {32,-24, -24,11,-24, -24, 32})},
      s.g {style= mystyle: format ("Green", 0, "Green"),
        s.polygon ({-8,8,0}, {-5,-5, 11})},
      s.g {style= mystyle: format (Grey, 0, Grey),
        s.polygon ({-16.5, -11, 0, 11, 16.5, 3.5,-3.5}, {-5, -5, 17, -5, -5, 20.5,20.5}) }}}
    return tostring(s)
  end) (60)

local D_VeraBridge_dev do
  local x = xml.createDocument ()
    x: appendChild {
      x.root {xmlns="urn:schemas-upnp-org:device-1-0",
        x.device {
          x.Category_Num    "1",
          x.deviceType      "VeraBridge",
          x.friendlyName    "Vera Bridge",
          x.manufacturer    "akbooer",
          x.handleChildren  "1",
          x.staticJson      "D_VeraBridge.json",
          x.serviceList {
            x.service {
              x.serviceType "urn:akbooer-com:service:VeraBridge:1",
              x.serviceId   (SID.VeraBridge),
              x.SCPDURL     "S_VeraBridge.xml"}},
          x.implementationList {
            x.implementationFile "I_VeraBridge.xml"}
          }}}
  D_VeraBridge_dev = tostring(x)
end

local D_VeraBridge_json = json.encode {
  flashicon = "http://raw.githubusercontent.com/akbooer/openLuup/master/icons/VeraBridge.png",
  default_icon = "VeraBridge.svg",
  DeviceType = "VeraBridge",
  Tabs = {{
      Label = Label ("tabname_control", "Control"),
			Position = "0",
			TabType = "flash",
			ControlGroup = { {id = "1",scenegroup = "1"} },
			SceneGroup = { {id = "1", top = "1.5", left = "0.25", x = "1.5",y ="2"} },

    Control = {
      ControlGroup (1, "variable", 0,0,
        Display (50,40, 75,20, SID.AltUI, "DisplayLine1")),
      ControlGroup (1, "variable", 0,1,
        Display (50,60, 75,20, SID.AltUI, "DisplayLine2")),
      ControlGroup (2, "variable", 0,3,
        Display (50,100, 75,20, SID.VeraBridge,"Version")),
      }}}}


local I_VeraBridge_impl do
  local x = xml.createDocument ()
  local function action (S,N, R,J)
    return x.action {x.serviceId (S), x.name (N), x.run(R), x.job (J)}
  end
    x: appendChild {
      x.implementation {
        x.files   "openLuup/L_VeraBridge.lua",
        x.startup "init",
        x.actionList {
          action (SID.VeraBridge, "GetVeraFiles",      nil, "GetVeraFiles (lul_settings)"),
          action (SID.VeraBridge, "GetVeraScenes",     nil, "GetVeraScenes (lul_settings)"),
          action (SID.VeraBridge, "RemoteVariableSet", nil, "RemoteVariableSet (lul_settings)"),
          action (SID.VeraBridge, "SetHouseMode",      nil, "SetHouseMode (lul_settings)"),
        }}}
  I_VeraBridge_impl = tostring(x)
end

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

-- Built-in device and service files

local D_BinaryLight1_xml do
  local x = xml.createDocument ()
    x: appendChild {
      x.root {xmlns="urn:schemas-upnp-org:device-1-0",
        x.specVersion {x.major "1", x.minor "0"},
        x.device {
          x.deviceType "urn:schemas-upnp-org:device:BinaryLight:1",
          x.staticJson "D_BinaryLight1.json",
          x.serviceList {
            x.service {
              x.serviceType "urn:schemas-upnp-org:service:SwitchPower:1",
              x.serviceId   "urn:upnp-org:serviceId:SwitchPower1",
              x.SCPDURL     "S_SwitchPower1.xml"},
            x.service {
              x.serviceType "urn:schemas-micasaverde-com:service:EnergyMetering:1",
              x.serviceId   "urn:micasaverde-com:serviceId:EnergyMetering1",
              x.SCPDURL     "S_EnergyMetering1.xml"},
            x.service {
              x.serviceType  "urn:schemas-micasaverde-com:service:HaDevice:1",
              x.serviceId    "urn:micasaverde-com:serviceId:HaDevice1",
              x.SCPDURL      "S_HaDevice1.xml"}
          }}}}
  D_BinaryLight1_xml = tostring(x)
end

local S_SwitchPower1_xml do
  local x = xml.createDocument ()
  local function argument (N,D, R)
    return x.argument {x.name (N), x.direction (D or "in"), x.relatedStateVariable (R)}
  end
    x: appendChild {
      x.scpd {xmlns="urn:schemas-upnp-org:service-1-0",
        x.specVersion {x.major "1", x.minor "0"},
        x.serviceStateTable {
          x.stateVariable {sendEvents="no",
            x.name "Target", x.sendEventsAttribute "no", x.dataType "boolean", x.defaultValue "0"},
          x.stateVariable {sendEvents="yes",
            x.name "Status", x.dataType "boolean", x.defaultValue "0", x.shortCode "status"}},

        x.actionList {
          x.action {x.name "SetTarget",
            x.argumentList {argument ("newTargetValue", "in", "Target")}},
          x.action {x.name "GetTarget",
            x.argumentList {argument ("RetTargetValue", "out", "Target")}},
          x.action {x.name "GetStatus",
            x.argumentList {argument ("ResultStatus", "out", "Status")}}},
      }}
  S_SwitchPower1_xml = tostring (x)
end


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

-- Security Sensor devices
local I_openLuupSecuritySensor1_xml = [[
<?xml version="1.0"?>
<implementation>
  <functions>
  local sid = "urn:micasaverde-com:serviceId:SecuritySensor1"
  function get (name)
    return (luup.variable_get (sid, name, lul_device))
  end

  function set (name, val)
    if val ~= get (name) then
      luup.variable_set (sid, name, val, lul_device)
    end
  end

  function ArmedTrippedCheck()
    if get "Armed" == "1" and get "Tripped" == "1" then
      set ("ArmedTripped", "1")
    else
      set ("ArmedTripped", "0")
    end
    if get "Tripped" == '1' then
      set ("LastTrip", os.time())
    end
  end

  function startup()
    set ("Tripped", 0)
    luup.variable_watch("ArmedTrippedCheck", sid, "Tripped", lul_device)
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

-- console menu structure
local classic_console_menus_json = [==[
{
  "comment":"JSON to define CLASSIC console menu structure",
  "menus":[
    ["openLuup",  ["About", "hr", "Parameters", "Historian", "hr", "Globals", "States"] ],
    ["Files",     ["Backups", "Images", "Database", "File Cache", "Trash"] ],
    ["Scheduler", ["Running", "Delays", "Watches", "Sockets", "Sandboxes", "Plugins"] ],
    ["Servers",   ["HTTP", "SMTP", "POP3", "UDP"] ],
    ["Logs",      ["Log", "hr", "Log.1","Log.2", "Log.3", "Log.4", "Log.5", "hr", "Startup Log"] ]
  ]
}
]==]

local default_console_menus_json = [==[
{
  "comment":"JSON to define standard console menu structure",
  "menus":[
    ["openLuup",  ["About", "hr", "System", "Historian", "Lua Code", "hr", "Utilities", "Scheduler","Servers"] ],
    ["Files",     ["Backups", "Images", "Trash"] ],
    ["Scheduler", ["Running", "Completed", "Startup", "Plugins", "Delays", "Watches"] ],
    ["Servers",   ["HTTP", "SMTP", "POP3", "UDP", "hr", "Sockets", "File Cache"] ],
    ["Logs",      ["Log", "hr", "Log.1","Log.2", "Log.3", "Log.4", "Log.5", "hr", "Startup Log"] ]
  ]
}
]==]

local altui_console_menus_json = [==[
{
  "comment":"JSON to define AltUI-style console menu structure",
  "menus":[
    ["openLuup",  ["About", "hr", "System", "Historian", "Scheduler", "Servers"] ],
    ["Devices"],
    ["Scenes"],
    ["Tables", ["Rooms Table","Plugins Table", "Devices Table", "Scenes Table", "Triggers Table"] ],
    ["Utilities", ["Reload Luup Engine", "hr", "Lua Startup","Lua Shutdown", "Lua Test",
                       "hr", "Backups", "Images", "Trash"] ],
    ["Logs",      ["Log", "hr", "Log.1","Log.2", "Log.3", "Log.4", "Log.5", "hr", "Startup Log"] ]
  ]
}
]==]


----- font-awesome
-- https://fontawesome.com/license/free

local fa = {}

fa ["pause-circle"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M256 8C119 8 8 119 8 256s111 248 248 248 248-111 248-248S393 8 256 8zm0 448c-110.5 0-200-89.5-200-200S145.5 56 256 56s200 89.5 200 200-89.5 200-200 200zm96-280v160c0 8.8-7.2 16-16 16h-48c-8.8 0-16-7.2-16-16V176c0-8.8 7.2-16 16-16h48c8.8 0 16 7.2 16 16zm-112 0v160c0 8.8-7.2 16-16 16h-48c-8.8 0-16-7.2-16-16V176c0-8.8 7.2-16 16-16h48c8.8 0 16 7.2 16 16z"/></svg>]]

fa ["play-circle"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M371.7 238l-176-107c-15.8-8.8-35.7 2.5-35.7 21v208c0 18.4 19.8 29.8 35.7 21l176-101c16.4-9.1 16.4-32.8 0-42zM504 256C504 119 393 8 256 8S8 119 8 256s111 248 248 248 248-111 248-248zm-448 0c0-110.5 89.5-200 200-200s200 89.5 200 200-89.5 200-200 200S56 366.5 56 256z"/></svg>]]

fa ["edit"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 512"><path d="M402.3 344.9l32-32c5-5 13.7-1.5 13.7 5.7V464c0 26.5-21.5 48-48 48H48c-26.5 0-48-21.5-48-48V112c0-26.5 21.5-48 48-48h273.5c7.1 0 10.7 8.6 5.7 13.7l-32 32c-1.5 1.5-3.5 2.3-5.7 2.3H48v352h352V350.5c0-2.1.8-4.1 2.3-5.6zm156.6-201.8L296.3 405.7l-90.4 10c-26.2 2.9-48.5-19.2-45.6-45.6l10-90.4L432.9 17.1c22.9-22.9 59.9-22.9 82.7 0l43.2 43.2c22.9 22.9 22.9 60 .1 82.8zM460.1 174L402 115.9 216.2 301.8l-7.3 65.3 65.3-7.3L460.1 174zm64.8-79.7l-43.2-43.2c-4.1-4.1-10.8-4.1-14.8 0L436 82l58.1 58.1 30.9-30.9c4-4.2 4-10.8-.1-14.9z"/></svg>]]

fa ["clone"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M464 0H144c-26.51 0-48 21.49-48 48v48H48c-26.51 0-48 21.49-48 48v320c0 26.51 21.49 48 48 48h320c26.51 0 48-21.49 48-48v-48h48c26.51 0 48-21.49 48-48V48c0-26.51-21.49-48-48-48zM362 464H54a6 6 0 0 1-6-6V150a6 6 0 0 1 6-6h42v224c0 26.51 21.49 48 48 48h224v42a6 6 0 0 1-6 6zm96-96H150a6 6 0 0 1-6-6V54a6 6 0 0 1 6-6h308a6 6 0 0 1 6 6v308a6 6 0 0 1-6 6z"/></svg>]]

fa ["clock"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M256 8C119 8 8 119 8 256s111 248 248 248 248-111 248-248S393 8 256 8zm0 448c-110.5 0-200-89.5-200-200S145.5 56 256 56s200 89.5 200 200-89.5 200-200 200zm61.8-104.4l-84.9-61.7c-3.1-2.3-4.9-5.9-4.9-9.7V116c0-6.6 5.4-12 12-12h32c6.6 0 12 5.4 12 12v141.7l66.8 48.6c5.4 3.9 6.5 11.4 2.6 16.8L334.6 349c-3.9 5.3-11.4 6.5-16.8 2.6z"/></svg>]]

fa["home-solid"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 512"><path d="M280.37 148.26L96 300.11V464a16 16 0 0 0 16 16l112.06-.29a16 16 0 0 0 15.92-16V368a16 16 0 0 1 16-16h64a16 16 0 0 1 16 16v95.64a16 16 0 0 0 16 16.05L464 480a16 16 0 0 0 16-16V300L295.67 148.26a12.19 12.19 0 0 0-15.3 0zM571.6 251.47L488 182.56V44.05a12 12 0 0 0-12-12h-56a12 12 0 0 0-12 12v72.61L318.47 43a48 48 0 0 0-61 0L4.34 251.47a12 12 0 0 0-1.6 16.9l25.5 31A12 12 0 0 0 45.15 301l235.22-193.74a12.19 12.19 0 0 1 15.3 0L530.9 301a12 12 0 0 0 16.9-1.6l25.5-31a12 12 0 0 0-1.7-16.93z"></path></svg>]]

fa["car-side-solid"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 512"><path d="M544 192h-16L419.22 56.02A64.025 64.025 0 0 0 369.24 32H155.33c-26.17 0-49.7 15.93-59.42 40.23L48 194.26C20.44 201.4 0 226.21 0 256v112c0 8.84 7.16 16 16 16h48c0 53.02 42.98 96 96 96s96-42.98 96-96h128c0 53.02 42.98 96 96 96s96-42.98 96-96h48c8.84 0 16-7.16 16-16v-80c0-53.02-42.98-96-96-96zM160 432c-26.47 0-48-21.53-48-48s21.53-48 48-48 48 21.53 48 48-21.53 48-48 48zm72-240H116.93l38.4-96H232v96zm48 0V96h89.24l76.8 96H280zm200 240c-26.47 0-48-21.53-48-48s21.53-48 48-48 48 21.53 48 48-21.53 48-48 48z"></path></svg>]]

fa["car-solid"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M499.99 176h-59.87l-16.64-41.6C406.38 91.63 365.57 64 319.5 64h-127c-46.06 0-86.88 27.63-103.99 70.4L71.87 176H12.01C4.2 176-1.53 183.34.37 190.91l6 24C7.7 220.25 12.5 224 18.01 224h20.07C24.65 235.73 16 252.78 16 272v48c0 16.12 6.16 30.67 16 41.93V416c0 17.67 14.33 32 32 32h32c17.67 0 32-14.33 32-32v-32h256v32c0 17.67 14.33 32 32 32h32c17.67 0 32-14.33 32-32v-54.07c9.84-11.25 16-25.8 16-41.93v-48c0-19.22-8.65-36.27-22.07-48H494c5.51 0 10.31-3.75 11.64-9.09l6-24c1.89-7.57-3.84-14.91-11.65-14.91zm-352.06-17.83c7.29-18.22 24.94-30.17 44.57-30.17h127c19.63 0 37.28 11.95 44.57 30.17L384 208H128l19.93-49.83zM96 319.8c-19.2 0-32-12.76-32-31.9S76.8 256 96 256s48 28.71 48 47.85-28.8 15.95-48 15.95zm320 0c-19.2 0-48 3.19-48-15.95S396.8 256 416 256s32 12.76 32 31.9-12.8 31.9-32 31.9z"></path></svg>]]

fa["plane-solid"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 512"><path d="M480 192H365.71L260.61 8.06A16.014 16.014 0 0 0 246.71 0h-65.5c-10.63 0-18.3 10.17-15.38 20.39L214.86 192H112l-43.2-57.6c-3.02-4.03-7.77-6.4-12.8-6.4H16.01C5.6 128-2.04 137.78.49 147.88L32 256 .49 364.12C-2.04 374.22 5.6 384 16.01 384H56c5.04 0 9.78-2.37 12.8-6.4L112 320h102.86l-49.03 171.6c-2.92 10.22 4.75 20.4 15.38 20.4h65.5c5.74 0 11.04-3.08 13.89-8.06L365.71 320H480c35.35 0 96-28.65 96-64s-60.65-64-96-64z"></path></svg>]]

fa["moon-solid"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M283.211 512c78.962 0 151.079-35.925 198.857-94.792 7.068-8.708-.639-21.43-11.562-19.35-124.203 23.654-238.262-71.576-238.262-196.954 0-72.222 38.662-138.635 101.498-174.394 9.686-5.512 7.25-20.197-3.756-22.23A258.156 258.156 0 0 0 283.211 0c-141.309 0-256 114.511-256 256 0 141.309 114.511 256 256 256z"></path></svg>]]

fa["calendar-regular"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><path fill="currentColor" d="M400 64h-48V12c0-6.6-5.4-12-12-12h-40c-6.6 0-12 5.4-12 12v52H160V12c0-6.6-5.4-12-12-12h-40c-6.6 0-12 5.4-12 12v52H48C21.5 64 0 85.5 0 112v352c0 26.5 21.5 48 48 48h352c26.5 0 48-21.5 48-48V112c0-26.5-21.5-48-48-48zm-6 400H54c-3.3 0-6-2.7-6-6V160h352v298c0 3.3-2.7 6-6 6z"></path></svg>]]

fa["calendar-alt-regular"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 448 512"><path d="M148 288h-40c-6.6 0-12-5.4-12-12v-40c0-6.6 5.4-12 12-12h40c6.6 0 12 5.4 12 12v40c0 6.6-5.4 12-12 12zm108-12v-40c0-6.6-5.4-12-12-12h-40c-6.6 0-12 5.4-12 12v40c0 6.6 5.4 12 12 12h40c6.6 0 12-5.4 12-12zm96 0v-40c0-6.6-5.4-12-12-12h-40c-6.6 0-12 5.4-12 12v40c0 6.6 5.4 12 12 12h40c6.6 0 12-5.4 12-12zm-96 96v-40c0-6.6-5.4-12-12-12h-40c-6.6 0-12 5.4-12 12v40c0 6.6 5.4 12 12 12h40c6.6 0 12-5.4 12-12zm-96 0v-40c0-6.6-5.4-12-12-12h-40c-6.6 0-12 5.4-12 12v40c0 6.6 5.4 12 12 12h40c6.6 0 12-5.4 12-12zm192 0v-40c0-6.6-5.4-12-12-12h-40c-6.6 0-12 5.4-12 12v40c0 6.6 5.4 12 12 12h40c6.6 0 12-5.4 12-12zm96-260v352c0 26.5-21.5 48-48 48H48c-26.5 0-48-21.5-48-48V112c0-26.5 21.5-48 48-48h48V12c0-6.6 5.4-12 12-12h40c6.6 0 12 5.4 12 12v52h128V12c0-6.6 5.4-12 12-12h40c6.6 0 12 5.4 12 12v52h48c26.5 0 48 21.5 48 48zm-48 346V160H48v298c0 3.3 2.7 6 6 6h340c3.3 0 6-2.7 6-6z"></path></svg>]]

fa["chart-bar-solid"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M332.8 320h38.4c6.4 0 12.8-6.4 12.8-12.8V172.8c0-6.4-6.4-12.8-12.8-12.8h-38.4c-6.4 0-12.8 6.4-12.8 12.8v134.4c0 6.4 6.4 12.8 12.8 12.8zm96 0h38.4c6.4 0 12.8-6.4 12.8-12.8V76.8c0-6.4-6.4-12.8-12.8-12.8h-38.4c-6.4 0-12.8 6.4-12.8 12.8v230.4c0 6.4 6.4 12.8 12.8 12.8zm-288 0h38.4c6.4 0 12.8-6.4 12.8-12.8v-70.4c0-6.4-6.4-12.8-12.8-12.8h-38.4c-6.4 0-12.8 6.4-12.8 12.8v70.4c0 6.4 6.4 12.8 12.8 12.8zm96 0h38.4c6.4 0 12.8-6.4 12.8-12.8V108.8c0-6.4-6.4-12.8-12.8-12.8h-38.4c-6.4 0-12.8 6.4-12.8 12.8v198.4c0 6.4 6.4 12.8 12.8 12.8zM496 384H64V80c0-8.84-7.16-16-16-16H16C7.16 64 0 71.16 0 80v336c0 17.67 14.33 32 32 32h464c8.84 0 16-7.16 16-16v-32c0-8.84-7.16-16-16-16z"></path></svg>]]

fa["retweet"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 512"><path d="M629.657 343.598L528.971 444.284c-9.373 9.372-24.568 9.372-33.941 0L394.343 343.598c-9.373-9.373-9.373-24.569 0-33.941l10.823-10.823c9.562-9.562 25.133-9.34 34.419.492L480 342.118V160H292.451a24.005 24.005 0 0 1-16.971-7.029l-16-16C244.361 121.851 255.069 96 276.451 96H520c13.255 0 24 10.745 24 24v222.118l40.416-42.792c9.285-9.831 24.856-10.054 34.419-.492l10.823 10.823c9.372 9.372 9.372 24.569-.001 33.941zm-265.138 15.431A23.999 23.999 0 0 0 347.548 352H160V169.881l40.416 42.792c9.286 9.831 24.856 10.054 34.419.491l10.822-10.822c9.373-9.373 9.373-24.569 0-33.941L144.971 67.716c-9.373-9.373-24.569-9.373-33.941 0L10.343 168.402c-9.373 9.373-9.373 24.569 0 33.941l10.822 10.822c9.562 9.562 25.133 9.34 34.419-.491L96 169.881V392c0 13.255 10.745 24 24 24h243.549c21.382 0 32.09-25.851 16.971-40.971l-16.001-16z"></path></svg>]]

fa["question-circle-solid"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M504 256c0 136.997-111.043 248-248 248S8 392.997 8 256C8 119.083 119.043 8 256 8s248 111.083 248 248zM262.655 90c-54.497 0-89.255 22.957-116.549 63.758-3.536 5.286-2.353 12.415 2.715 16.258l34.699 26.31c5.205 3.947 12.621 3.008 16.665-2.122 17.864-22.658 30.113-35.797 57.303-35.797 20.429 0 45.698 13.148 45.698 32.958 0 14.976-12.363 22.667-32.534 33.976C247.128 238.528 216 254.941 216 296v4c0 6.627 5.373 12 12 12h56c6.627 0 12-5.373 12-12v-1.333c0-28.462 83.186-29.647 83.186-106.667 0-58.002-60.165-102-116.531-102zM256 338c-25.365 0-46 20.635-46 46 0 25.364 20.635 46 46 46s46-20.636 46-46c0-25.365-20.635-46-46-46z"></path></svg>]]

fa["info-circle-solid"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M256 8C119.043 8 8 119.083 8 256c0 136.997 111.043 248 248 248s248-111.003 248-248C504 119.083 392.957 8 256 8zm0 110c23.196 0 42 18.804 42 42s-18.804 42-42 42-42-18.804-42-42 18.804-42 42-42zm56 254c0 6.627-5.373 12-12 12h-88c-6.627 0-12-5.373-12-12v-24c0-6.627 5.373-12 12-12h12v-64h-12c-6.627 0-12-5.373-12-12v-24c0-6.627 5.373-12 12-12h64c6.627 0 12 5.373 12 12v100h12c6.627 0 12 5.373 12 12v24z"></path></svg>]]

fa["power-off-solid"] = [[
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><path d="M400 54.1c63 45 104 118.6 104 201.9 0 136.8-110.8 247.7-247.5 248C120 504.3 8.2 393 8 256.4 7.9 173.1 48.9 99.3 111.8 54.2c11.7-8.3 28-4.8 35 7.7L162.6 90c5.9 10.5 3.1 23.8-6.6 31-41.5 30.8-68 79.6-68 134.9-.1 92.3 74.5 168.1 168 168.1 91.6 0 168.6-74.2 168-169.1-.3-51.8-24.7-101.8-68.1-134-9.7-7.2-12.4-20.5-6.5-30.9l15.8-28.1c7-12.4 23.2-16.1 34.8-7.8zM296 264V24c0-13.3-10.7-24-24-24h-32c-13.3 0-24 10.7-24 24v240c0 13.3 10.7 24 24 24h32c13.3 0 24-10.7 24-24z"></path></svg>]]

-----

local manifest = {

    ["icons/openLuup.svg"] = openLuup_svg,
    ["D_openLuup.xml"]  = D_openLuup_dev,
    ["D_openLuup.json"] = D_openLuup_json,
    ["I_openLuup.xml"]  = I_openLuup_impl,
    ["S_openLuup.xml"]  = S_openLuup_svc,
    ["LICENSE"] = ABOUT.LICENSE,

    ["icons/AltAppStore.svg"] = AltAppStore_svg,
    ["D_AltAppStore.xml"]  = D_AltAppStore_dev,
    ["D_AltAppStore.json"] = D_AltAppStore_json,
    ["I_AltAppStore.xml"]  = I_AltAppStore_impl,
    ["S_AltAppStore.xml"]  = S_AltAppStore_svc,

    ["icons/VeraBridge.svg"] = VeraBridge_svg,
    ["D_VeraBridge.xml"]  = D_VeraBridge_dev,
    ["D_VeraBridge.json"] = D_VeraBridge_json,
    ["I_VeraBridge.xml"]  = I_VeraBridge_impl,
    ["S_VeraBridge.xml"]  = S_VeraBridge_svc,

    ["built-in/default_console_menus.json"] = default_console_menus_json,
    ["built-in/classic_console_menus.json"] = classic_console_menus_json,
    ["built-in/altui_console_menus.json"]   = altui_console_menus_json,

    ["built-in/D_BinaryLight1.xml"] = D_BinaryLight1_xml,
    ["built-in/S_SwitchPower1.xml"] = S_SwitchPower1_xml,

    ["D_ZWay.xml"]  = D_ZWay_xml,
    ["D_ZWay.json"] = D_ZWay_json,
    ["I_ZWay.xml"]  = I_ZWay_xml,
    ["I_ZWay2.xml"] = I_ZWay2_xml,    -- TODO: remove after development
    ["I_openLuupSecuritySensor1_xml"] = I_openLuupSecuritySensor1_xml,
    ["I_openLuupCamera1.xml"]   = I_openLuupCamera1_xml,
    ["I_openLuupSecurity1.xml"] = I_openLuupSecurity1_xml,
    ["I_Dummy.xml"]             = I_Dummy_xml,

    ["index.html"]            = index_html,

    ["openLuup_reload"]       = openLuup_reload,
    ["openLuup_reload.bat"]   = openLuup_reload_bat,

    ["storage-schemas.conf"]      = storage_schemas_conf,
    ["storage-aggregation.conf"]  = storage_aggregation_conf,
    ["unknown.wsp"]               = unknown_wsp,

  }

do -- add font-awesome icon SVGs
  local name = "icons/%s.svg"
  local svg  = '<svg xmlns="http://www.w3.org/2000/svg" fill="%s">%s</svg>'
  for n,v in pairs (fa) do manifest [name: format(n)] = svg: format ("grey", v) end
end

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
    if y then
      local h = hits[filename] or {n = 0, access = 0}
      local mode, size = type(y), 0
      if mode == "string" then mode, size = "file", #y end
      return {mode = mode, size = size, permissions = "rw-rw-rw-", access = h.access, hits = h.n}
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
      return function(m) i=i+1; return m[i] end, idx, 0
    end,
  read  = function (filename) hit(filename) return manifest[filename] end,
  write = function (filename, contents) manifest[filename] = contents end,

}

-----
