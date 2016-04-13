--
-- openLuup - check installation
local version =  "openLuup_check   2016.04.12   @akbooer"

print (version)
--
-- change search paths for Lua require and icon urls
  local cmh_lu = ";../cmh-lu/?.lua"
  package.path = package.path .. cmh_lu                               -- add /etc/cmh-lu/ to search path

local lfs = require "lfs"     -- now a fundamental part of openLuup (for transportability)

local function module_check (name)
  local mod, msg = pcall (require, name)
  if mod then 
    print (("module '%s'"): format (name))
  else
    print "-----------------------"
    print (msg: match "^(.-)%c")
    print "-----------------------"
  end
end

-- check first for all AltUI required modules
module_check "mime"
module_check "socket"
module_check "socket.http"
module_check "ssl.https"
module_check "ltn12"
module_check "dkjson"   -- AltUI needs this now.


local function exists (name)
  local f = io.open (name, 'rb')
  if f then 
    f: close() 
  else
    print ("not found: " .. name)
  end
  return f
end

local function warning (name, message)
  if not exists (name) then print (message) end
end

assert (exists "openLuup", "openLuup/ directory is missing")

local lua_files = {
    "chdev", "devices", "gateway", "http", "init", "io", "json", 
    "loader", "logs", "luup", "plugins", "requests", "rooms", "scenes", 
    "scheduler", "server", "timers", "userdata", "wsapi", "xml",
  }

local ok = true
for _,file in ipairs (lua_files) do ok = exists ("openLuup/" .. file .. ".lua") and ok end
assert (ok, "... some required installation files are missing from openLuup/ sub-directory")

warning ("icons", "...icons/ directory not found")

warning ("/var/log/cmh",  "... ALTUI will not be able to access variable and scene history")

warning ("user_data.json", "... no user_data configuration file")

-----
