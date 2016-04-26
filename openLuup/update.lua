local _NAME = "openLuup.update"
local revisionDate = "2016.04.25"
local banner = "   version " .. revisionDate .. "  @akbooer"

--
-- update plugins from GitHub repository
--
-- note that these routines only update the files in the plugins/downloads directory,
-- they don't copy them to the /etc/cmh-ludl/ directory.

-- 2016.03.15  created
-- 2016.04.25  make generic form for use with openLuup / AltUI / anything else

local https     = require "ssl.https"
local ltn12     = require "ltn12"
local mime      = require "mime"
local lfs       = require "lfs"

local userdata  = require "openLuup.userdata"
local json      = require "openLuup.json"
local logs      = require "openLuup.logs"

--  local log
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control

https.TIMEOUT = 5

local pathSeparator = package.config:sub(1,1)   -- thanks to @vosmont for this Windows/Unix discriminator
                            -- although since lfs (luafilesystem) accepts '/' or '\', it's not necessary

-- utilities

-- map function to array (using ipairs iterator)
local function imap(x,f) 
  for _,y in ipairs (x) do f(y) end
  return x 
end

-- set attributes, possibly decoding if required
local function set_attr (ver, info)
  if info then
    local u = mime.unb64(info)  
    ver = json.decode(u) or {} 
  end
  for i,j in pairs (ver) do userdata.attributes[i] = j end
end

-- get and decode GitHub url
local function git_request (request)
  local decoded, errmsg
  local response = https.request (request)
  if response then 
    decoded, errmsg = json.decode (response)
  else
    errmsg = response
  end
  return decoded, errmsg
end

-------------------------
--
--  new() - factory function for individual plugin update from GitHub
--
--  parameters:
--    archive = "akbooer/openLuup",           -- GitHub repository
--    target  = "plugins/downloads/openLuup"  -- target directory for files and subdirectories
--

local function new (archive, target) 
  
  -- ensure the download directories exist!
  local function directory_check (subdirectories)
    local function pathcheck (fullpath)
      local _,msg = lfs.mkdir (fullpath)
      _log (table.concat ({"checking directory", fullpath, ':', msg or "File created"}, ' '))
    end
    -- check or create path to the target root directory
    local path = {}
    for dir in target:gmatch "(%w+)" do
      path[#path+1] = dir
      pathcheck (table.concat(path, pathSeparator))
    end
    -- check or create subdirectories
    for _,subdir in ipairs (subdirectories) do
      pathcheck (target .. subdir)
    end
  end

  -- return a table of tagged releases, indexed by name, 
  -- with GitHub structure including commit info
  local function get_tags ()
    _log "getting release versions from GitHub..."
    local tags
    local Ftag_request  = "https://api.github.com/repos/%s/tags"
    local resp, errmsg = git_request (Ftag_request: format (archive))
    if resp then 
      tags = {} 
      imap (resp, function(x) tags[x.name] = x end);
    else
      _log (errmsg)
    end
    return tags, errmsg
  end
  
  -- find the tag of the newest released version
  local function latest_version ()
    local tags = {}
    local t, errmsg = get_tags ()
    if not t then return nil, errmsg end
    for v in pairs (t) do tags[#tags+1] = v end
    table.sort (tags)
    _log (table.concat (tags, ', '))
    local latest = tags[#tags]
    return latest
  end
  
  -- get specific parts of tagged release
  local function get_release (v, subdirectories, pattern)
    local ok = true
    directory_check (subdirectories)
    _log ("getting contents of version: " .. v)

    -- x is a GitHub descriptor with name, path, etc...
    local function get_file (x)
      local wanted = (x.type == "file") and (x.name):match (pattern or '.') 
      if not wanted then return end
      local fname = table.concat {target, pathSeparator, x.path}  -- use this if you want subdirectory structure
--      local fname = table.concat {target, pathSeparator, x.name}  -- ...or this to collapse all to target directory
      _log (fname)
  
      local _, code = https.request{
          url = x.download_url,
          sink = ltn12.sink.file(io.open(fname, 'w'))
        }
      
      if code ~= 200 then ok = false end
    end
    
    local function get_subdirectory (d)
      _log ("...getting subdirectory: " .. d)
      local Fcontents = "https://api.github.com/repos/%s/contents"
      local request = table.concat {Fcontents: format (archive),d , "?ref=", v}
      local resp, errmsg = git_request (request)
      if resp then
        imap (resp, get_file)
      else
        ok = false
        _log (errmsg)
      end
    end
    
    imap (subdirectories, get_subdirectory)    -- get the bits we want
    if not ok then return nil, "error reading release contents from GitHub" end
    
    return ok
  end

  -- alternative way to get latest release using tar file and os.execute() to unzip
  local function get_latest_tarfile ()
    local ok, msg
    _log "getting latest version tar file from GitHub..."
    
    local _, code = https.request{
      url = "https://codeload.github.com/" .. archive .. "/tar.gz/master",
      sink = ltn12.sink.file(io.open(target .. "/latest.tar.gz", "wb"))
    }
    if code ~= 200 then 
      msg = "GitHub download failed with code " .. code
    else    
      _log "un-zipping download files..."
      os.execute (table.concat {"tar -x -C ", target, "/ -f ", target, "/latest.tar.gz" })
      msg =  "latest version downloaded to " .. target
      ok = true
    end
    _log (msg)
    return ok, msg
  end

  return {
    get_tags = get_tags,
    get_release = get_release,
    get_latest_tarfile = get_latest_tarfile,
    latest_version = latest_version,
  }
end

--
-------------------------

----------------
--
-- specific updaters
--

-- openLuup

local openLuup_updater = new ("akbooer/openLuup", "plugins/downloads/openLuup")


-- load specified (or latest) version 
function openLuup_updater.get_version (v)
  v  = v or "master"
  local subdirectories = {    -- these are the bits of the repository that we want
    "/openLuup",
    "/openLuupExtensions",
    "/Utilities",
    "/VeraBridge",
  }
  local ok = openLuup_updater.get_release (v, subdirectories)
--  local ok = openLuup_updater.get_release (v, subdirectories, "xml.lua")    -- TODO: remove
  if ok then 
    set_attr {GitHubVersion = v}
    return v 
  end
end

-- AltUI

local AltUI_updater = new ("amg0/ALTUI", "plugins/downloads/altui")

-- load specified (or latest) version 
function AltUI_updater.get_version (v)
  local subdirectories = {    -- these are the bits of the repository that we want
    '',           -- root
    "/blockly",
  }
  local ok = AltUI_updater.get_release (v, subdirectories, "ALTUI")
--  local ok = AltUI_updater.get_release (v, subdirectories, "D_ALTUI.json")    -- TODO: remove
  if ok then 
    return v 
  end
end


----------------
--
-- TEST
--
--_log = print

-- test openLuup access

--local ov = openLuup_updater.latest_version ()
--local ow = openLuup_updater.get_version ()
--print (ov, ow)

---- test AltUI access

--local av = AltUI_updater.latest_version ()
--local aw = AltUI_updater.get_version (av)
--print (av,aw)
--AltUI_updater.get_latest_tarfile ()

-----

return {
  new = new,                -- factory function
  set_attr = set_attr,      -- utility function
  
  -- pre-defined updaters
  
  openLuup = openLuup_updater,
  AltUI = AltUI_updater,  
}

-----


