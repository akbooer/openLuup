#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

local ABOUT = {
  NAME          = "upnp.control.hag",
  VERSION       = "2018.01.27",
  DESCRIPTION   = "a handler for redirected port_49451 /upnp/control/hag requests",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-2018 AK Booer

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

-- see: http://wiki.micasaverde.com/index.php/ModifyUserData

-- 2016.06.05  add scene processing (for AltUI long scene POST requests)
-- 2016.07.06  correct calling syntax for wsapi_env.input:read ()

-- 2018.01.24   see note at end of code regarding call syntax changes...

local xml       = require "openLuup.xml"
local json      = require "openLuup.json"
local luup      = require "openLuup.luup"
local scenes    = require "openLuup.scenes"

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
  
  local content = wsapi_env.input:read ()       -- 2016.07.06
  local x = xml.decode(content)
  local m = xml.extract(x, "s:Envelope", "s:Body", "u:ModifyUserData") [1] or {}  -- unpack one-element list
  
  if m.DataFormat == "json" and m.inUserData then
    local j,msg = json.decode (m.inUserData)
    if not j then 
      response = msg 
      _log (msg)
    else
      
      -- Startup
      
      if j.StartupCode then
        luup.attr_set ("StartupCode", j.StartupCode)
        _log "modified StartupCode"
      end
      
      -- Scenes
      
      if j.scenes then                                -- 2016.06.05
        for name, scene in pairs (j.scenes) do
          local id = tonumber (scene.id)
          if id >= 1e6 then scene.id = nil end        -- remove bogus scene number
          local new_scene, msg = scenes.create (scene)
          id = tonumber (scene.id)                    -- may have changed
          if id and new_scene then
            luup.scenes[id] = new_scene               -- slot into scenes table
            _log ("modified scene #" .. id)
          else
            response = msg
            _log (msg)
            break
          end
        end
      end
      
      -- also devices, sections, rooms, users...
      
    end
    
  else    -- not yet implemented
    _log (content)
  end
  
  return 200, headers, iterator
end

-----

-- NB: following info from @amg0, 24-Jan-2018

--[[

I looked at UI7 behavior and it replaces it by a JSON call to HomeAutomation device, action ModifyUserData

so basically I have to replace OLD CODE

return $.ajax({
					url: "/port_49451/upnp/control/hag",
					type: "POST",
					dataType: "text",
					contentType: "text/xml;charset=UTF-8",
					processData: false,
					data:  xml,
					headers: {
						"SOAPACTION":'"urn:schemas-micasaverde-org:service:HomeAutomationGateway:1#ModifyUserData"'
					},
				})

by NEW CODE
				return $.ajax({
					url: "/port_3480/data_request",
					type: "POST",
					contentType: "application/x-www-form-urlencoded; charset=UTF-8",
					data:  {
						id:'lu_action',
						serviceId:'urn:micasaverde-com:serviceId:HomeAutomationGateway1',
						action:'ModifyUserData',
						DataFormat:'json',
						inUserData: JSON.stringify(target)
					}
				})


This is used for very large scene for instance where the other method ( GET ) is not appropriate or some other functionality ( plugin flags modification , etc ... )

you may have an impact on openluup

--]]


