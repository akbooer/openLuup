local ABOUT = {
  NAME          = "openLuup.virtualfilesystem",
  VERSION       = "2018.05.31",
  DESCRIPTION   = "Virtual storage for Device, Implementation, Service XML and JSON files, and more",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2018 AK Booer

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

-- the loader cache is preset with these files

-- the local references mean that these files will not be removed from the 
-- ephemeral cache table by garbage collection 
--
-- openLuup reload script files and index.html to redirect to AltUI.
-- device files for "openLuup", "AltAppStore", and "VeraBridge". 
-- DataYours configuration files.

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

local D_openLuup_json = [[
{
  "default_icon": "https://avatars.githubusercontent.com/u/4962913",
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
      <name>Test</name>
      <run>
        luup.log "openLuup Test action called"
        luup.variable_set ("openLuup", "Test", lul_settings.TestValue, lul_device) 
        luup.log "openLuup Test action completed"
      </run>
    </action>
    
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
  <actionList>

    <action>
      <name>Test</name>
      <argumentList>
        <argument>
          <name>TestValue</name>
          <direction>in</direction>
          <relatedStateVariable>Test</relatedStateVariable>
        </argument>
        <argument>
          <name>ReturnValue</name>
          <direction>out</direction>
          <relatedStateVariable>Test</relatedStateVariable>
        </argument>
      </argumentList>
    </action>

    <action>
      <name>SendToTrash</name>
      <argumentList>
        <argument>
          <name>Folder</name>
          <direction>in</direction>
        </argument>
        <argument>
          <name>MaxDays</name>
          <direction>in</direction>
        </argument>
        <argument>
          <name>MaxFiles</name>
          <direction>in</direction>
        </argument>
        <argument>
          <name>FileTypes</name>
          <direction>in</direction>
        </argument>
      </argumentList>
    </action>
  
    <action>
      <name>EmptyTrash</name>
      <argumentList>
        <argument>
          <name>AreYouSure</name>
          <direction>in</direction>
        </argument>
      </argumentList>
    </action>
  
    <action>
      <name>SetHouseMode</name>
      <argumentList>
        <argument>
          <name>Mode</name>
          <direction>in</direction>
        </argument>
      </argumentList>
    </action>
    
    <action>    <!-- added by @rafale77 -->
      <name>RunScene</name>
      <argumentList>
        <argument>
          <name>SceneNum</name>
          <direction>in</direction>
        </argument>
      </argumentList>
    </action>

  </actionList>
</scpd>
]]

-----
--
-- AltAppStore device files
--

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
	"default_icon": "http://raw.githubusercontent.com/akbooer/AltAppStore/master/AltAppStore.png",
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
    <stateVariable sendEvents="no">
      <name>metadata</name>
      <dataType>string</dataType>
    </stateVariable>	
	</serviceStateTable>
  <actionList>
    <action>
      <name>update_plugin</name>
      <argumentList>
        <argument>
          <name>metadata</name>
          <direction>in</direction>
        </argument>
      </argumentList>
    </action>
	</actionList>
</scpd>
]]


-----
--
-- VeraBridge device files
--

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
	"default_icon": "http://raw.githubusercontent.com/akbooer/openLuup/master/icons/VeraBridge.png",
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
  			GetVeraFiles ()
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
  <actionList>
    <action> <name>GetVeraFiles</name> </action>
    <action> <name>GetVeraScenes</name> </action>
    <action>
      <name>SetHouseMode</name>
      <argumentList>
        <argument>
          <name>Mode</name>
          <direction>in</direction>
        </argument>
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
# you may need to change ‘lua’ to ‘lua5.1’ depending on your install

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
    local timeout = 30
    local child -- the motion sensor
    local smtp = require "openLuup.smtp"
    local timers = require "openLuup.timers"
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
    local function clear ()
      local now = os.time()
      local last = get "LastTrip"
      if (tonumber (last) + timeout) &lt;= (now + 1) then  -- NOTE the XML escape!
        set ("Tripped", '0')
        set ("ArmedTripped", '0')
        set ("LastTrip", now)
      end
    end
    local function openLuupCamera (ip, mail)      -- email callback
      set ("Tripped", '1')
      set ("LastTrip", os.time())
      if get "Armed" == '1' then set ("ArmedTripped", '1') end
      timers.call_delay (clear, timeout, '', "camera motion reset")
    end
    function startup (devNo)
      local smtp = require "openLuup.smtp"
      do -- install MotionSensor as child device
        local var = "urn:micasaverde-com:serviceId:SecuritySensor1,%s=%s\n"
        local statevariables = table.concat {
            var:format("Armed",1), 
            var:format("ArmedTripped", 0),
            var:format("Tripped", 0), 
            var:format("LastTrip", 0),
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

-----
--
-- DataYours schema and aggregation definitions for AltUI DataStorage Provider
--

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

[day]
pattern = \.d$
retentions = 1m:1d

[week]
pattern = \.w$
retentions = 5m:7d

[month]
pattern = \.m$
retentions = 20m:30d

[quarter]
pattern = \.q$
retentions = 1h:90d

[year]
pattern = \.y$
retentions = 6h:1y

#  2017.02.14  @akbooer
#  EXTENDED (10 year) patterns for AltUI Data Storage Provider

[1minute]
pattern = \.1m$
retentions = 1m:1d,10m:7d,1h:30d,3h:1y,1d:10y

[5minute]
pattern = \.5m$
retentions = 5m:7d,1h:30d,3h:1y,1d:10y

[10minute]
pattern = \.10m$
retentions = 10m:7d,1h:30d,3h:1y,1d:10y

[20minute]
pattern = \.20m$
retentions = 20m:30d,3h:1y,1d:10y

[1hour]
pattern = \.1h$
retentions = 1h:90d,3h:1y,1d:10y

[3hour]
pattern = \.3h$
retentions = 3h:1y,1d:10y

[6hour]
pattern = \.6h$
retentions = 6h:1y,1d:10y

[1day]
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
-- Data Historian Disk Archive - schemas and aggregations
--

local storage_schemas_json = [==[
[ " DataHistorian Whisper database:

    Storage schema (archive lists) and Aggregation methods

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
  {
    "archives": "1m:1d,10m:7d,1h:30d,3h:1y,1d:10y", 
    "patterns": "SceneActivated, Status",
  },{
    "archives": "1s:1m,1m:1d,10m:7d,1h:30d,3h:1y,1d:10y", 
    "patterns": "Tripped",
    "aggregation": "sum",
  },{
    "archives": "5m:7d,1h:30d,3h:1y,1d:10y", 
    "patterns": "openLuup, DataYours, EventWatcher",
  },{
    "archives": "10m:7d,1h:30d,3h:1y,1d:10y", 
    "aggregation": "average", 
    "xFilesFactor": 0.0, 
    "patterns": "CurrentLevel, CurrentTemperature"
  },{
    "archives": "20m:30d,3h:1y,1d:10y", 
    "patterns": "EnergyMetering",
  },{
    "archives": "1h:90d,3h:1y,1d:10y", 
    "patterns": "",
  },{
    "archives": "3h:1y,1d:10y", 
    "patterns": "",
  },{
    "archives": "6h:1y,1d:10y", 
    "patterns": "",
  },{
    "archives": "1d:10y", 
    "aggregation": "last",
    "patterns": "BatteryLevel",
  },
]
]==]

-----

local manifest = {
    
    ["D_openLuup.xml"]  = D_openLuup_dev,
    ["D_openLuup.json"] = D_openLuup_json,
    ["I_openLuup.xml"]  = I_openLuup_impl,
    ["S_openLuup.xml"]  = S_openLuup_svc,
    
    ["D_AltAppStore.xml"]  = D_AltAppStore_dev,
    ["D_AltAppStore.json"] = D_AltAppStore_json,
    ["I_AltAppStore.xml"]  = I_AltAppStore_impl,
    ["S_AltAppStore.xml"]  = S_AltAppStore_svc,
    
    ["D_VeraBridge.xml"]  = D_VeraBridge_dev,
    ["D_VeraBridge.json"] = D_VeraBridge_json,
    ["I_VeraBridge.xml"]  = I_VeraBridge_impl,
    ["S_VeraBridge.xml"]  = S_VeraBridge_svc,
    
    ["D_ZWay.xml"]  = D_ZWay_xml,
    ["D_ZWay.json"] = D_ZWay_json,
    ["I_ZWay.xml"]  = I_ZWay_xml,
    ["I_ZWay2.xml"] = I_ZWay2_xml,    -- TODO: remove after development
    
    ["I_openLuupCamera1.xml"] = I_openLuupCamera1_xml,
    
    ["index.html"]          = index_html,
    ["openLuup_reload"]     = openLuup_reload,
    ["openLuup_reload.bat"] = openLuup_reload_bat,

    ["storage-schemas.json"]      = storage_schemas_json,
    ["storage-schemas.conf"]      = storage_schemas_conf,
    ["storage-aggregation.conf"]  = storage_aggregation_conf,
    ["unknown.wsp"]               = unknown_wsp,
    
  }

-----

return {
  ABOUT = ABOUT,
  
--  manifest = setmetatable (manifest, {__mode = "kv"}),
  manifest = manifest,
  
  attributes = function (filename) 
    local y = manifest[filename]
    if type(y) == "string" then return {mode = "file", size = #y} end
  end,
  
  open = function (filename, mode)
    mode = mode or 'r'
    
    if mode: match "r" then
      if manifest[filename] then
        return {
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

  dir   = function () return next, manifest end,
  read  = function (filename) return manifest[filename] end,
  write = function (filename, contents) manifest[filename] = contents end,

}

-----


