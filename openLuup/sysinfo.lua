#!/usr/bin/env wsapi.cgi

module(..., package.seeall)


ABOUT = {
  NAME          = "sysinfo.sh",
  VERSION       = "2018.07.28",
  DESCRIPTION   = "sysinfo script /etc/cmh-ludl/cgi-bin/cmh/sysinfo.sh",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2016 AK Booer

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

-- 2016.05.09  original version
-- 2018.07.28  updated to use wsapi.response library


local json      = require "openLuup.json"
local userdata  = require "openLuup.userdata"
local wsapi     = require "openLuup.wsapi"


local attr = userdata.attributes 

local original_MiOS_shell_script_returns =  -- using this, can easily insert new data
  {
    ["3g_wan_failover"] = "0",
    Server_Account = "vera-us-oem-account12.mios.com",
    Server_Autha = "vera-us-oem-autha11.mios.com",
    Server_Authd = "vera-us-oem-authd11.mios.com",
    Server_Device = "vera-us-oem-device12.mios.com",
    Server_Event = "vera-us-oem-event12.mios.com",
    Server_Firmware = "vera-us-oem-firmware12.mios.com",
    Server_Log = "vera-us-oem-log12.mios.com",
    Server_Relay = "vera-eu-oem-relay12.mios.com",
    Server_Storage = "vera-us-oem-storage12.mios.com",
    Server_Support = "vera-us-oem-ts12.mios.com",
    account = "123456",
    auth_user = "",
    ergykey = "",
    failsafe_tunnels = "0",
    firmware_version = "1.7.0",
    full_platform = "mt7620a_Luup_ui7",
    hwaddr = "aa:bb:cc:dd:ee:ff",
    installation_number = attr.PK_AccessPoint or "87654321",
    language = "1",
    manual_version = "1",
    platform = attr.model or "4Lite",       -- was "4Lite"
    radisabled = "",
    raemail = "",
    rapass = "",
    raport = "12345",
    rauser = "",
    remote_only = "1",
    secure_unit = "0",
    skin = "AltUI" or "mios",               -- was "mios"
    terminal_disabled = "0",
    timezone = "Europe|London|GMT0BST,M3.5.0/1,M10.5.0",
    ui_language = "en",
    zwave_homeid = "123456768",
    zwave_locale = "eu",
    zwave_version = "4.5"
  }


--  WSAPI Lua implementation of sysinfo.sh

local _log    -- defined from WSAPI environment as wsapi.error:write(...) in run() method.

-- global entry point called by WSAPI connector
function run (wsapi_env)
  _log = function (...) wsapi_env.error:write(...) end      -- set up the log output, note colon syntax
  
  _log "running sysinfo.sh WSAPI CGI"

  local res = wsapi.response.new ()         -- use the response library to build the response!
  
  local j, err = json.encode (original_MiOS_shell_script_returns)
  
  res:content_type "text/plain"
  res: write (j or err)                     -- return valid JSON, or error message

  return res: finish()
end

-----
