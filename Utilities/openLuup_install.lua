-- first-time download and install of openLuup files from GitHub

-- 2018.02.17  add local ./www/ directory
-- 2018.08.05  use servertables for myIP  (thanks @samunders)
-- 2018.08.10  add parameter for install branch (thanks @vwout)

-- 2019.02.12  fix tslv1_2 protocol error


local lua = "lua5.1"     -- change this to "lua" if required

local x = os.execute
local p = print
local branch = arg[1] or "master"

p "openLuup_install   2019.02.12   @akbooer"

local http  = require "socket.http"
local https = require "ssl.https"
local ltn12 = require "ltn12"
local lfs   = require "lfs"

p ("getting openLuup version tar file from GitHub branch " .. branch .. "...")

local _, code = https.request{
  url = "https://codeload.github.com/akbooer/openLuup/tar.gz/" .. branch,
  sink = ltn12.sink.file(io.open("latest.tar.gz", "wb"))
}

assert (code == 200, "GitHub download failed with code " .. code)
  
p "un-zipping download files..."

x "tar -xf latest.tar.gz" 
x ("mv openLuup-" .. branch .. "/openLuup/ .")
x ("rm -r openLuup-" .. branch .. "/")
   
p "getting dkjson.lua..."
_, code = http.request{
    url = "http://dkolf.de/src/dkjson-lua.fsl/raw/dkjson.lua?name=16cbc26080996d9da827df42cb0844a25518eeb3",
    sink = ltn12.sink.file(io.open("dkjson.lua", "wb")),
    protocol = "tlsv1_2",
  }

assert (code == 200, "GitHub download failed with code " .. code)

p "creating required files and folders"
lfs.mkdir "www"
lfs.mkdir "files"
lfs.mkdir "icons"
lfs.mkdir "backup"    -- thanks @a-lurker

local vfs = require "openLuup.virtualfilesystem"

local function add_vfs_file (name)  
  local f = io.open (name, "wb")
  f: write (vfs.read (name))
  f: close ()
end

add_vfs_file "index.html"

local reload = "openLuup_reload"
local pathSeparator = package.config:sub(1,1)   -- thanks to @vosmont for this Windows/Unix discriminator
if pathSeparator ~= '/' then reload = reload .. ".bat" end   -- Windows version

add_vfs_file (reload)

p "initialising..."

x "chmod a+x openLuup_reload"

local s= require "openLuup.servertables"
local ip = s.myIP or "openLuupIP"

p "downloading and installing AltUI..."
x (lua .. " openLuup/init.lua altui") 

x "./openLuup_reload &"
p "openLuup downloaded, installed, and running..."
p ("visit http://" .. ip .. ":3480 to start using the system")

-----
