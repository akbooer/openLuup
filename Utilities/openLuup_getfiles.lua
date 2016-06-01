-- getfiles
--
-- copy relevant files from remote Vera
--
-- 2015-11-17   @akbooer
-- 2015-12-08   use socket.http rather than luup.inet.wget
-- 2016-03-07   use 'wb' in io.write() for Windows compatibilty (thanks @vosmont and @scyto)
-- 2016-05-31   correct return prameter in http.request call

local http  = require "socket.http"
local url   = require "socket.url"
local lfs   = require "lfs"

local code = [[

local function get_dir (dir)
  local x = io.popen ("ls -1 " .. dir)
  if x then
    local y = x:read "*a"
    x:close ()
    return y
  end
end

local function put_dir (file, text)
  local f = io.open (file, 'w')
  if f then
    f:write (text)
    f: close ()
  end
end

local d = get_dir "%s"
if d then 
  put_dir ("/www/directory.txt", d)
end

]]

print "openLuup_getfiles - utility to get device and icon files from remote Vera"

io.write "Remote Vera IP: "
local ip = io.read ()
assert (ip: match "^%d+%.%d+%.%d+%.%d+$", "invalid IP address syntax")

local function get_directory (path)
  local template = "http://%s:3480/data_request?id=action" ..
                    "&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1" ..
                    "&action=RunLua&Code=%s"
  local request = template:format (ip, url.escape (code: format(path)))

  local info, status = http.request (request)
  assert (status == 200, "error creating remote directory listing")

  info, status = http.request ("http://" .. ip .. "/directory.txt")
  assert (status == 200, "error reading remote directory listing")
  return info
end

local function get_files_from (path, dest, url_prefix)
  dest = dest or '.'
  url_prefix = url_prefix or ":3480/"
  local info = get_directory (path)
  for x in info: gmatch "%C+" do
    local status
    local fname = x:gsub ("%.lzo",'')   -- remove unwanted extension for compressed files
    info, status = http.request ("http://" .. ip .. url_prefix .. fname)
    if status == 200 then
      print (#info, fname)
      
      local f = io.open (dest .. '/' .. fname, 'wb')
      f:write (info)
      f:close ()
    else
      print ("error", fname)
    end
  end
end

-- device, service, lua, json, files...
lfs.mkdir "files"
get_files_from ("/etc/cmh-ludl/", "files", ":3480/")
get_files_from ("/etc/cmh-lu/", "files", ":3480/")

-- icons
lfs.mkdir "icons"

-- UI7
get_files_from ("/www/cmh/skins/default/img/devices/device_states/", 
  "icons", "/cmh/skins/default/img/devices/device_states/")

-- UI5
--get_files_from ("/www/cmh/skins/default/icons/", "icons", "/cmh/skins/default/icons/")

-----




