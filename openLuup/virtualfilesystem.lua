local ABOUT = {
  NAME          = "openLuup.virtualfilesystem",
  VERSION       = "2016.06.28",
  DESCRIPTION   = "Virtual storage for Device, Implementation, Service XML and JSON files, and more",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

-- the loader cache is preset with these files

-- the local references mean that these files will not be removed from the 
-- ephemeral cache table by garbage collection 
--
-- device files for "openLuup", "AltAppStore", and "VeraBridge". 
-- this also provides the files for some unit tests
--

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
      <name>GetStats</name>
      <run>
      -- note that there's no code, but the action has return parameters (see service file)
      </run>
    </action>
  
  <actionList>
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
      <name>GetStats</name>
      <argumentList>
        <argument>
          <name>CPU</name>
          <direction>out</direction>
          <relatedStateVariable>CpuLoad_Hours</relatedStateVariable>
        </argument>
        <argument>
          <name>Memory</name>
          <direction>out</direction>
          <relatedStateVariable>Memory_Mb</relatedStateVariable>
        </argument>
        <argument>
          <name>Uptime</name>
          <direction>out</direction>
          <relatedStateVariable>Uptime_Days</relatedStateVariable>
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
    <modelName>1</modelName>
    <modelNumber>1</modelNumber>
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
		},
		{
			"Label": {
				"lang_tag": "advanced",
				"text": "Advanced"
			},
			"Position": "1",
			"TabType": "javascript",
			"ScriptName": "shared.js",
			"Function": "advanced_device"
		},
	],
	"DeviceType": "urn:schemas-upnp-org:device:AltAppStore:1"
}
]]

local I_AltAppStore_impl = [[
<?xml version="1.0"?>
<implementation>
  <files>L_AltAppStore.lua</files>
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
    <modelName>v2.0</modelName>
    <modelNumber>1</modelNumber>
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

-- TODO: switch to icons/ directory once this release is in the master branch
local D_VeraBridge_json = [[
{
	"default_icon": "http://raw.githubusercontent.com/akbooer/openLuup/master/VeraBridge/VeraBridge.png",
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
  <files>L_VeraBridge.lua</files>
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
    <action>
      <name>GetVeraFiles</name>
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
    
    ["index.html"]          = index_html,
    ["openLuup_reload"]     = openLuup_reload,
    ["openLuup_reload.bat"] = openLuup_reload_bat,

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
  
  dir   = function () return next, manifest end,
  read  = function (filename) return manifest[filename] end,
  write = function (filename, contents) manifest[filename] = contents end,

  open  = function (filename)
            return {
              read  = function () return manifest[filename] end,
              write = function (_, contents) manifest[filename] = contents end,
              close = function () filename = nil end,
            }
          end,
}

-----


