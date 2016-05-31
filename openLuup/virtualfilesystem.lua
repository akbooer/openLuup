local ABOUT = {
  NAME          = "openLuup.virtualfilesystem",
  VERSION       = "2016.05.31",
  DESCRIPTION   = "Virtual storage for Device, Implementation, Service XML and JSON files",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

-- the loader cache is preset with these files

-- the local references mean that these files will not be removed from the 
-- ephemeral cache table by garbage collection 
--
-- device files for "openLuup" (aka. Extensions)
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
  "default_icon": "https:\/\/avatars.githubusercontent.com\/u\/4962913",
  "DeviceType": "openLuup"
}
]]

local I_openLuup_impl = [[
<?xml version="1.0"?>
<implementation>
  <files>openLuup/extensions.lua</files>
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

-- TEST

local testing = [[
a test file
]]

-----

local manifest = {
    ["D_openLuup.xml"]  = D_openLuup_dev,
    ["D_openLuup.json"] = D_openLuup_json,
    ["I_openLuup.xml"]  = I_openLuup_impl,
    ["S_openLuup.xml"]  = S_openLuup_svc,
    
    ["index.html"]          = index_html,
    ["openLuup_reload"]     = openLuup_reload,
    ["openLuup_reload.bat"] = openLuup_reload_bat,

    ["TEST"] = testing,
  }

-----

return {
  ABOUT = ABOUT,
  
--  manifest = setmetatable (manifest, {__mode = "kv"}),
  manifest = manifest,
  
  attributes = function (filename) 
    local y = manifest[filename]
    if type(y) == "string" then return {type = "file", size = #y} end
  end,
  
  dir   = function () return next, manifest end,
  read  = function (filename) return manifest[filename] end,
  write = function (filename, contents) manifest[filename] = contents end,

  open  = function (filename)
            return {
              read  = function () return manifest[filename] end,
              write = function (contents) manifest[filename] = contents end,
              close = function () end,
            }
          end,
}

-----


