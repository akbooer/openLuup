#!/usr/bin/env wsapi.cgi

--module(..., package.seeall)

local ABOUT = {
  NAME          = "upnp.control.hag",
  VERSION       = "2016.05.10",
  DESCRIPTION   = "a handler for redirected port  /upnp/control/hag requests",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

-- see: http://wiki.micasaverde.com/index.php/ModifyUserData

local xml       = require "openLuup.xml"
local json      = require "openLuup.json"
local luup      = require "openLuup.luup"
local userdata  = require "openLuup.userdata"

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

--[[
The request is a POST with xml
  CONTENT_LENGTH = 681,
  CONTENT_TYPE = "text/xml;charset=UTF-8",

{["s:Envelope"] = 
  {["s:Body"] = 
    {["u:ModifyUserData"] = 
      {
        DataFormat = "json",
        inUserData = "...some JSON structure..."
      }}}}

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
  local m = xml.extract(x, "s:Envelope", "s:Body", "u:ModifyUserData") [1]  -- unpack one-element list
  
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
  end
  
  return 200, headers, iterator
end

-----


