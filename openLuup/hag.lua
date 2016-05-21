#!/usr/bin/env wsapi.cgi

--module(..., package.seeall)

local ABOUT = {
  NAME          = "upnp.control.hag",
  VERSION       = "2016.05.15",
  DESCRIPTION   = "a handler for redirected port_49451 /upnp/control/hag requests",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

-- see: http://wiki.micasaverde.com/index.php/ModifyUserData

local xml       = require "openLuup.xml"
local json      = require "openLuup.json"
local luup      = require "openLuup.luup"

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

--[[
The request is a POST with xml
  CONTENT_LENGTH = 681,
  CONTENT_TYPE = "text/xml;charset=UTF-8",

<s:envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
	<s:body>	
    <u:modifyuserdata xmlns:u="urn:schemas-micasaverde-org:service:HomeAutomationGateway:1">		
      <inuserdata>{...some JSON structure...}</inuserdata>
      <DataFormat>json</DataFormat>
    </u:modifyuserdata>
	</s:body>
</s:envelope>

JSON structure contains:
{
  InstalledPlugins = {},
  PluginSettings = {},
  StartupCode = "...",
  devices = {},
  rooms = {},
  scenes = {},
  sections = {},
  users = {}
}

--]]

function run(wsapi_env)
  local response = "OK"
  local headers = { ["Content-type"] = "text/plain" }
  
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax
  
  local function iterator()   -- one-shot 'iterator', returns response, then nil
    local x = response
    response = nil
    return x
  end
  
  local content = wsapi_env.input.read ()
  local x = xml.decode(content)
  local m = xml.extract(x, "s:Envelope", "s:Body", "u:ModifyUserData") [1] or {}  -- unpack one-element list
  
  if m.DataFormat == "json" and m.inUserData then
    local j,msg = json.decode (m.inUserData)
    if not j then 
      response = msg 
      _log (msg)
    else
      
      if j.StartupCode then
        luup.attr_set ("StartupCode", j.StartupCode)
        _log "modified StartupCode"
      end
      
    end
    
  else    -- not yet implemented
    _log (content)
  end
  
  return 200, headers, iterator
end

-----


