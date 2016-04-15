local version = "XML  2016.04.15  @akbooer"

--
-- Routines to read Device / Service / Implementation XML files
--
-- general xml reader: this is just good enough to read device and implementation .xml files
-- doesn't cope with XML attributes or empty elements: <tag />
--
-- DOES cope with comments (thanks @vosmont)

-- TODO: proper XML parser rather than nasty hack?
--

-- 2016.02.22  skip XML attributes but still parse element
-- 2016.02.23  remove reader and caching, rename encode/decode 
-- 2016.02.24  escape special characters in encode and decode
-- 2016.04.14  @explorer expanded tags to alpha-numerics and underscores
-- 2016.04.15  fix attribute skipping (got lost in previous edit)

-- XML:extract ("name", "subname", "subsubname", ...)
-- return named part or empty list
local function extract (self, name, name2, ...)
  local x = (self or {}) [name]
  if x then 
    if name2 then
      return extract (x, name2, ...) 
    else
      if type(x) == "table" and #x == 0 then x = {x} end   -- make it a one element list
      return x
    end
  end
  return {}   -- always return something
end


local function decode (info)
  local msg
  local xml = {}
  -- remove such like: <!-- This is a comment -->,  thanks @vosmont
  -- see: http://forum.micasaverde.com/index.php/topic,34572.0.html
  if info then info = info: gsub ("<!%-%-.-%-%->", '') end
  --
  local result = info
  for a,b in (info or ''): gmatch "<([%w_]+).->(.-)</%1>" do   -- find matching opening and closing tags
    local x,y = decode (b)                                -- get the value of the contents
    xml[a] = xml[a] or {}                                 -- if this tag doesn't exist, start a list of values
    xml[a][#xml[a]+1] = x or y   -- add new value to the list (might be table x, or just text y)
    result = xml
  end 
  if type (result) == "table" then
    for a,b in pairs (result) do                  -- go through the contents
      if #b == 1 then result[a] = b[1] end        -- collapse one-element lists to simple items
    end
  else
    if result then   -- in case of failure, simply return whole string as 'error message'
      msg = result: gsub ("&(%w+);", {lt = '<', gt = '>', quot = '"', apos = "'", amp = '&'})
    end
    result = nil    -- ...and nil for xml result
  end
  return result, msg
end


local function encode (Lua, wrapper)
  local xml = {}        -- or perhaps    {'<?xml version="1.0"?>\n'}
  local function p(x)
    if type (x) ~= "table" then x = {x} end
    for _, y in ipairs (x) do xml[#xml+1] = y end
  end
  
  local function value (x, name, depth)
    local gsub = {['<'] = "&lt;", ['>'] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;", ['&'] = "&amp;"}
    local function spc ()  p ((' '):rep (2*depth)) end
    local function atag () spc() ; p {'<', name,'>'} end
    local function ztag () p {'</',name:match "^[^%s]+",'>\n'} end
    local function str (x) atag() ; p(tostring(x): gsub("%s+", ' '): gsub ([=[[<>"'&]]=], gsub)) ; ztag() end
    local function err (x) error ("xml: unsupported data type "..type (x)) end
    local function tbl (x)
      local y
      if #x == 0 then y = {x} else y = x end
      for i, z in ipairs (y) do
        i = {}
        for a in pairs (z) do i[#i+1] = a end
        table.sort (i, function (a,b) return tostring(a) < tostring (b) end)
        if name then atag() ; p '\n' end
        for _,a in ipairs (i) do value(z[a], a, depth+1) end
        if name then spc() ; ztag() end
      end
    end
    
    depth = depth or 0
    local dispatch = {table = tbl, string = str, number = str}
    return (dispatch [type(x)] or err) (x)
  end
  -- wrapper parameter allows outer level of tags (with attributes)
  local ok, msg = pcall (value, Lua, wrapper) 
  if ok then ok = table.concat (xml) end
  return ok, msg
end


return {
  
  -- constants
  version = version,
  
  -- methods
  
  extract = extract,
  decode  = decode, 
  encode  = encode,
}

