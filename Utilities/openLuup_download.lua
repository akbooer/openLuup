--
-- first-time download of openLuup files from GitHub
--

local version =  "openLuup_download   2016.04.25   @akbooer"

print (version)

local https = require "ssl.https"
local ltn12 = require "ltn12"

local target = "plugins/downloads/"

print "getting latest openLuup version tar file from GitHub..."

local _, code = https.request{
  url = "https://codeload.github.com/akbooer/openLuup/tar.gz/master",
  sink = ltn12.sink.file(io.open(target .. "latest.tar.gz", "wb"))
}

if code ~= 200 then 
  print ("GitHub download failed with code " .. code)
else
  print "un-zipping download files..."
  os.execute (table.concat {"tar -x -C ", target, " -f ", target, "latest.tar.gz" })
end
 
print ("latest openLuup version downloaded to openLuup-master in directory " .. target)

-----

-- TODO: deploy to appropriate directories.
