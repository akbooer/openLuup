#!/usr/bin/env wsapi.cgi


module(..., package.seeall)

-- sysinfo.sh
--  2016.02.26   @akbooer

local original_MiOS_shell_script_returns = [[

{
    "installation_number" : "88801234",
    "firmware_version": "1.7.0",
    "zwave_version" : "4.5",
    "zwave_homeid" : "123456768",
    "zwave_locale" : "eu",
    "hwaddr": "aa:bb:cc:dd:ee:ff",
    "ergykey": "",
    "timezone": "Europe|London|GMT0BST,M3.5.0/1,M10.5.0",
    "Server_Device": "vera-us-oem-device12.mios.com",
    "Server_Event": "vera-us-oem-event12.mios.com",
    "Server_Relay": "vera-eu-oem-relay12.mios.com",
    "Server_Storage": "vera-us-oem-storage12.mios.com",
    "Server_Support": "vera-us-oem-ts12.mios.com",
    "Server_Log": "vera-us-oem-log12.mios.com",
    "Server_Firmware": "vera-us-oem-firmware12.mios.com",
    "Server_Event": "vera-us-oem-event12.mios.com",
    "Server_Account": "vera-us-oem-account12.mios.com",
    "Server_Autha": "vera-us-oem-autha11.mios.com",
    "Server_Authd": "vera-us-oem-authd11.mios.com",
    "rauser": "",
    "rapass": "",
    "radisabled": "",
    "raemail": "",
    "raport": "12345",
    "auth_user": "",
    "remote_only": "1",
    "terminal_disabled": "0",
    "failsafe_tunnels": "0",
    "3g_wan_failover": "0",
    "secure_unit": "0",
    "manual_version": "1",
    "platform": "4Lite",
    "full_platform": "mt7620a_Luup_ui7",
    "skin": "mios",
    "language": "1",
    "ui_language": "en",
    "account": "123456"
}
    
]]


--  WSAPI Lua implementation of sysinfo.sh

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.


-- global entry point called by WSAPI connector

--[[

The environment is a Lua table containing the CGI metavariables (at minimum the RFC3875 ones) plus any 
server-specific metainformation. It also contains an input field, a stream for the request's data, 
and an error field, a stream for the server's error log. 

The input field answers to the read([n]) method, 
where n is the number of bytes you want to read 
(or nil if you want the whole input). 

The error field answers to the write(...) method.

return values: the HTTP status code, a table with headers, and the output iterator. 

--]]

function run (wsapi_env)
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax -- 2016.02.26
  
  _log "running sysinfo.sh WSAPI CGI"

  local status, return_content  = 200, original_MiOS_shell_script_returns
  
  local headers = {["Content-Type"] = "text/plain"}
  
  local function iterator ()     -- one-shot iterator, returns content, then nil
    local x = return_content
    return_content = nil 
    return x
  end

  return status, headers, iterator
end

-----
