local ABOUT = {
  NAME          = "openLuup.virtualfilesystem",
  VERSION       = "2019.06.06",
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

local html5 = require "openLuup.xml" .html5       -- for SVG icons
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
    local s = html5.svg {height = N, width  = N,
      viewBox= table.concat ({0, 0,12, 12}, ' '),
      xmlns="http://www.w3.org/2000/svg" ,
      style="border: 0; margin: 0; background-color:#F0F0F0;" }
    local g1 = s:group {style = "stroke-width:3; fill:#CA6C5E;"}
      g1:rect (1,1, 10, 6)
      g1:rect (3,7,  6, 3)
      g1:rect (1,9, 10, 2)
    local g0 = s:group {style = "stroke-width:3; fill:#F0F0F0;"}
      g0:rect (3,3,  6, 4)
      g0:rect (5,0,  2,12)
    return tostring(s)
  end) (60)

local D_openLuup_dev = xml.encodeDocument {
  root = {_attr = {xmlns="urn:schemas-upnp-org:device-1-0"},
    device = {
      deviceType    = "openLuup",
      friendlyName  = "openLuup",
      manufacturer  = "akbooer",
      staticJson    = "D_openLuup.json",
      serviceList = {
        service = {
          {serviceType = "openLuup", serviceId = "openLuup", SCPDURL = "S_openLuup.xml"}}},
      implementationList = {
        implementationFile = "I_openLuup.xml"}
      }}}

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
        Label ("donate", html5.a {href="console", target="_blank", "CONSOLE interface"})),
      ControlGroup (2, "label", 0,4,
        Display (50,200, 75,20),
        Label ("donate", html5.a {href="https://www.justgiving.com/DataYours/", target="_blank",
                "If you like openLuup, you could DONATE to Cancer Research UK right here"}))},
   }},
--  eventList2 = {
--    {id = 1, serviceId = "openLuup",argumentList = {},
--      label = Label ("triggers_are_not_implemented", "Triggers not implemented, use Watch instead")},
--    {id=2, serviceId = "openLuup", argumentList = {}, label = Label ("openLuup", "Uptime : (openLuup)"), },
--    {id=3, serviceId = "openLuup", argumentList = {}, label = Label ("openLuup", "CPU : (openLuup)") },
--    }
  }

local I_openLuup_impl = xml.encodeDocument {
implementation = {
  files = "openLuup/L_openLuup.lua",
  startup = "init",
  actionList = {

    action = {
      action ("openLuup", "SendToTrash", nil, "SendToTrash (lul_settings)"),
      action ("openLuup", "EmptyTrash",  nil, "EmptyTrash (lul_settings)"),
      action ("openLuup", "SetHouseMode",
        [[
          local sid = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"
          luup.call_action (sid, "SetHouseMode", lul_settings)
        ]]),
      action ( "openLuup", "RunScene",                 -- added by @rafale77 --
        [[
          local sid = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"
          luup.call_action(sid, "RunScene", {SceneNum = lul_settings.SceneNum}, 0)
        ]])
    }}}}

-- TODO: move to this service file is dependent on AltUI version post-1-May-2019 to fix name tag issue
local xS_openLuup_svc = xml.encodeDocument {
  scpd = {_attr= {xmlns="urn:schemas-upnp-org:service-1-0"},
    specVersion = {major = 1, minor = 0},

    serviceStateTable = {  -- added just for fun to expose these as device status
      stateVariable = {
        {name = "CpuLoad", shortCode = "cpu_load"},
        {name = "Memory_Mb", shortCode = "memory_mb"},
        {name = "Uptime_Days", shortCode = "uptime_days"}}},

    actionList = {

      action = {
        {name = "SendToTrash",
        argumentList = {
          argument = {
            argument "Folder",
            argument "MaxDays",
            argument "MaxFiles",
            argument "FileTypes"}}},

        {name = "EmptyTrash",
        argumentList = {argument = argument "AreYouSure"}},

        {name = "SetHouseMode",
        argumentList = {argument = argument "Mode"}},

        {name = "RunScene",         -- added by @rafale77 --
        argumentList = {argument = argument "SceneNum"}}}}}}

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
-- This plugin runs on Vera too, so use same device/service files as there...
--

local AltAppStore_svg = (
  function (N)
    local s = html5.svg {height = N, width  = N,
      viewBox= table.concat ({-24,-24, 48,48}, ' '),
      xmlns="http://www.w3.org/2000/svg" ,
      style="border: 0; margin: 0; background-color:White;" }
    local c = s:group {style = "stroke-width:3; fill:PowderBlue;"}      -- PowderBlue / SkyBlue
      c: rect   (-13, -7, 26, 14)
      c: circle (-13,  0, 7)
      c: circle ( 13,  0, 7)
      c: circle ( -5, -8, 9)
      c: circle (  7, -8, 6)
    local a = s:group {style = "stroke-width:0; fill:RoyalBlue;"}   -- DarkSlateBlue
      a: polygon (
        { 3, 3, 8,  0, -8, -3, -3},
        {-5, 9, 9, 18,  9,  9, -5})
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
    local s = html5.svg {height = N, width  = N,
      viewBox= table.concat ({-24,-24, 48,48}, ' '),
      xmlns="http://www.w3.org/2000/svg" ,
      style="border: 1; margin: 0; background-color:" .. background }
    local c = s:group {style= mystyle:format ("none", 3, Grey)}
      c:  circle (0,5, 17.5)
      c:  circle (0,5, 23)
    local b = s:group {style= mystyle: format (background, 0, background)}
      b: polygon ({-24, -24, -16,0,16, 24,24}, {32,-24, -24,11,-24, -24, 32})
    local t = s:group {style= mystyle: format ("Green", 0, "Green")}
      t: polygon ({-8,8,0}, {-5,-5, 11})
    local v = s:group {style= mystyle: format (Grey, 0, Grey)}
      v: polygon ({-16.5, -11, 0, 11, 16.5, 3.5,-3.5}, {-5, -5, 17, -5, -5, 20.5,20.5})
    return tostring(s)
  end) (60)


local D_VeraBridge_dev = xml.encodeDocument {
  root = {_attr = {xmlns="urn:schemas-upnp-org:device-1-0"},
    device = {
      Category_Num    = 1,
      deviceType      = "VeraBridge",
      friendlyName    = "Vera Bridge",
      manufacturer    = "akbooer",
      handleChildren  = 1,
      staticJson      = "D_VeraBridge.json",
      serviceList = {
        service = {
          { serviceType = "urn:akbooer-com:service:VeraBridge:1",
            serviceId = SID.VeraBridge,
            SCPDURL = "S_VeraBridge.xml"}}},
      implementationList = {
        implementationFile = "I_VeraBridge.xml"}
      }}}


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


local I_VeraBridge_impl = xml.encodeDocument {
implementation = {
  files = "openLuup/L_VeraBridge.lua",
  startup = "init",
  actionList = {
    action = {
      action (SID.VeraBridge, "GetVeraFiles",      nil, "GetVeraFiles (lul_settings)"),
      action (SID.VeraBridge, "GetVeraScenes",     nil, "GetVeraScenes (lul_settings)"),
      action (SID.VeraBridge, "RemoteVariableSet", nil, "RemoteVariableSet (lul_settings)"),
      action (SID.VeraBridge, "SetHouseMode",      nil, "SetHouseMode (lul_settings)"),
    }}}}



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

local D_BinaryLight1_xml = xml.encodeDocument {
  root = {_attr = {xmlns="urn:schemas-upnp-org:device-1-0"},
    specVersion = {major=1, minor=0},
    device = {
      deviceType      = "urn:schemas-upnp-org:device:BinaryLight:1",
      staticJson      = "D_BinaryLight1.json",
      serviceList = {
        service = {
          { serviceType = "urn:schemas-upnp-org:service:SwitchPower:1",
            serviceId = "urn:upnp-org:serviceId:SwitchPower1",
            SCPDURL = "S_SwitchPower1.xml"},
          { serviceType = "urn:schemas-micasaverde-com:service:EnergyMetering:1",
            serviceId = "urn:micasaverde-com:serviceId:EnergyMetering1",
            SCPDURL = "S_EnergyMetering1.xml"},
          { serviceType = "urn:schemas-micasaverde-com:service:HaDevice:1",
            serviceId = "urn:micasaverde-com:serviceId:HaDevice1",
            SCPDURL = "S_HaDevice1.xml"}
        }}}}}


local S_SwitchPower1_xml = xml.encodeDocument {
  scpd = {_attr= {xmlns="urn:schemas-upnp-org:service-1-0"},
    specVersion = {major = 1, minor = 0},
    serviceStateTable = {
      stateVariable = {_attr = {sendEvents="no"},
        {name = "Target", sendEventsAttribute = "no", dataType="boolean", defaultValue = 0},
        {name = "Status", dataType="boolean", defaultValue = 0, shortCode = "status"}}},

    actionList = {
      action = {
        {name = "SetTarget", argumentList = {argument = {argument ("newTargetValue", "in", "Target")}}},
        {name = "GetTarget", argumentList = {argument = {argument ("RetTargetValue", "out", "Target")}}},
        {name = "GetStatus", argumentList = {argument = {argument ("ResultStatus", "out", "Status")}}},
  }}}}


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
    ["openLuup",  ["About", "hr", "System", "Historian", "hr", "Utilities", "Scheduler","Servers"] ],
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
    ["Utilities", ["Lua Startup","Lua Shutdown", "Lua Code Test",
                       "hr", "Backups", "Images", "Trash"] ],
    ["Logs",      ["Log", "hr", "Log.1","Log.2", "Log.3", "Log.4", "Log.5", "hr", "Startup Log"] ]
  ]
}
]==]


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
