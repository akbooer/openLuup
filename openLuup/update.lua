local _NAME = "openLuup.update"
local revisionDate = "2016.03.15"
local banner = "   version " .. revisionDate .. "  @akbooer"

--
-- update openLuup file from GitHub repository
--

-- 2016.03.15  created

local https   = require "ssl.https"
local ltn12   = require "ltn12"
local lfs     = require "lfs"

local logs    = require "openLuup.logs"

--  local log
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control


local function get_latest (p)
  _log "getting latest openLuup version from GitHub..."
  
  local resp, code, h, s = https.request{
    method = "GET",
    url = "https://codeload.github.com/akbooer/openLuup/tar.gz/master",
    sink = ltn12.sink.file(io.open("plugins/downloads/openLuup/latest.tar.gz", "wb"))
  }

  local msg
  if code ~= 200 then 
    msg = "GitHub download failed with code " .. code
  else
    _log "un-zipping download files..."
    os.execute "tar -x -C plugins/downloads/openLuup/ -f plugins/downloads/openLuup/latest.tar.gz" 
    msg =  "latest version downloaded to plugins/downloads/openLuup/..."
  end

  _log (msg)
  return msg, "text/plain"
  
end

-- ensure the download directory exists!
lfs.mkdir "plugins/"
lfs.mkdir "plugins/downloads/"
lfs.mkdir "plugins/downloads/openLuup/"

return {
    get_latest = get_latest,
  }

-----


