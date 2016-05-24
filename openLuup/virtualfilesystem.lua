local ABOUT = {
  NAME          = "openLuup.virtualfilesystem",
  VERSION       = "2016.05.24",
  DESCRIPTION   = "Virtual storage for Device, Implementation, Service XML and JSON files",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

-- the loader cache is preset with these files

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

-- TEST

local testing = [[
  a test file
]]

-----

return {
  ABOUT = ABOUT,

  manifest = {
    ["D_openLuup.xml"]  = D_openLuup_dev,
    ["D_openLuup.json"] = D_openLuup_json,
    ["I_openLuup.xml"]  = I_openLuup_impl,
    ["S_openLuup.xml"]  = S_openLuup_svc,

    ["TEST"] = testing,
  }

}

-----


