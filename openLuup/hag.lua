#!/usr/bin/env wsapi.cgi

--module(..., package.seeall)

local ABOUT = {
  NAME          = "upnp.control.hag",
  VERSION       = "2016.06.09",
  DESCRIPTION   = "a handler for redirected port_49451 /upnp/control/hag requests",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

-- see: http://wiki.micasaverde.com/index.php/ModifyUserData

-- 2016.06.05  add scene processing (for AltUI long scene POST requests)
-- 2016.06.09  make 'run' a local function and export module table explicitly

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

local function run(wsapi_env)
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

return {
  ABOUT = ABOUT,
  run = run,
}

-----


