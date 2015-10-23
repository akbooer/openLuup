local luup = require "openLuup.luup"


local function get_from_trac (rev, subdir)
  subdir = subdir or ''
  local mios = "http://code.mios.com/"
  local trac = "/trac/mios_alternate_ui/"
  local valid_extension = {
    js    = true,
    json  = true, 
    lua   = true,
    png   = true,
    xml   = true,
  }

  local url = table.concat {mios, trac, "browser/", subdir}
  --local url = "http://code.mios.com/trac/mios_alternate_ui/browser/blockly"
  local ver = ''
  if rev then ver = "?rev=" ..rev end

  local s,x = luup.inet.wget (url .. ver)
  if s ~= 0 then return end

  local files = {}
--  local pattern = table.concat {'href="', trac, "browser/", subdir, "([%w%-_/]+%.%w+)"}
  local pattern = table.concat {'href="', trac, "browser/", subdir, "([%w%-%._/]+)"}
  for fname in x: gmatch (pattern) do
    local ext = fname: match "%.(%w+)$"
    if valid_extension[ext] then
      files [#files+1] = fname
    end
  end

  local root = table.concat {mios, trac, "export/", rev, '/', subdir}
  local ok
  for _,fname in ipairs (files) do
    local b = root .. fname
    local content
    ok, content = luup.inet.wget (b)
    if ok ~= 0 then return end
    print (#content, fname)
    if fname == "J_ALTUI_uimgr.js" then
      print "patching revision number"
      content = content: gsub ("%$Revision%$", "$Revision: " .. rev .. " $")
    end
--    local f = io.open ("downloads/"..fname, 'w')
--    f: write (content)
--    f: close ()
  end
  
  return files
end


local rev = 790

-- backup existing
--os.execute "mkdir -p downloads"
--os.execute "mkdir -p backup_UI"
--os.execute "cp -f *ALTUI* backup_UI/"

-- get ALTUI and blockly sub-directory
get_from_trac (rev)
get_from_trac (rev, "blockly/")

