-- first-time download and install of openLuup files from GitHub

local lua = "lua5.1"     -- change this to "lua" if required

local x = os.execute
local p = print

p "openLuup_install   2016.06.08   @akbooer"

local http  = require "socket.http"
local https = require "ssl.https"
local ltn12 = require "ltn12"

p "getting latest openLuup version tar file from GitHub..."

local _, code = https.request{
  url = "https://codeload.github.com/akbooer/openLuup/tar.gz/master",
  sink = ltn12.sink.file(io.open("latest.tar.gz", "wb"))
}

assert (code == 200, "GitHub download failed with code " .. code)
  
p "un-zipping download files..."

x "tar -xf latest.tar.gz" 
x "mv openLuup-master/openLuup/ ."
x "rm -r openLuup-master/"
   
p "getting dkjson.lua..."
_, code = http.request{
    url = "http://dkolf.de/src/dkjson-lua.fsl/raw/dkjson.lua?name=16cbc26080996d9da827df42cb0844a25518eeb3",
    sink = ltn12.sink.file(io.open("dkjson.lua", "wb"))
  }

assert (code == 200, "GitHub download failed with code " .. code)

p "initialising..."

local o = require "openLuup.plugins"
o.add_ancillary_files ()

x "chmod a+x openLuup_reload"

local s= require "openLuup.server"
local ip = s.myIP or "openLuupIP"

p "downloading and installing AltUI..."
x (lua .. " openLuup/init.lua altui") 

x "./openLuup_reload &"
p "openLuup downloaded, installed, and running..."
p ("visit http://" .. ip .. ":3480 to start using the system")

-----
