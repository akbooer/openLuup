local version = "XML  2015.10.21  @akbooer"

--
-- Routines to read Device / Service / Implementation XML files
--
-- general xml reader: this is just good enough to read device and implementation .xml files
-- doesn't cope with XML attributes or empty elements: <tag />
--
-- TODO: proper XML parser rather than nasty hack?
-- TODO: escape special characters in encode and decode
--
-- gsub ("&(%w+);", {lt = '<', gt = '>', quot = '"', apos = "'", amp = '&'})

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


local function xml2Lua (info)
  local msg
  local xml = {}
  local result = info
  for a,b in (info or ''): gmatch "<(%a+)>(.-)</%1>" do   -- find matching opening and closing tags
    local x,y = xml2Lua (b)                               -- get the value of the contents
    xml[a] = xml[a] or {}                                 -- if this tag doesn't exist, start a list of values
    xml[a][#xml[a]+1] = x or y   -- add new value to the list (might be table x, or just text y)
    result = xml
  end 
  if type (result) == "table" then
    for a,b in pairs (result) do                  -- go through the contents
      if #b == 1 then result[a] = b[1] end        -- collapse one-element lists to simple items
    end
  else
    msg = result    -- in case of failure, simply return whole string as 'error message'
    result = nil    -- ...and nil for xml result
  end
  return result, msg
end

local xml_cache = setmetatable ({}, {__mode = 'kv'})    -- "weak" table
local reads, hits = 0,0

local function xml_read (self, filename)
  filename = filename or self     -- allow dot or colon syntax
  local xml = xml_cache[filename]
  reads = reads + 1
  hits = hits + 1
  if not xml then
    hits = hits - 1
    local f = io.open (filename or self) 
    if f then 
      xml = f: read "*a"
      f: close ()  
      xml_cache[filename] = xml   -- save in cache
    end
  end
--  print ("xml", filename, hits, reads)
  return xml2Lua(xml)
end

local function Lua2xml (Lua, wrapper)
  local xml = {}        -- or perhaps    {'<?xml version="1.0"?>\n'}
  local function p(x)
    if type (x) ~= "table" then x = {x} end
    for _, y in ipairs (x) do xml[#xml+1] = y end
  end
  
  local function value (x, name, depth)
    local function spc ()  p ((' '):rep (2*depth)) end
    local function atag () spc() ; p {'<', name,'>'} end
    local function ztag () p {'</',name:match "^[^%s]+",'>\n'} end
    local function str (x) atag() ; p(tostring(x): gsub("%s+", ' ')) ; ztag() end
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
  extract = extract,
  xml2Lua = xml2Lua, 
  decode  = xml2Lua, 
  read    = xml_read, 
  Lua2xml = Lua2xml,
  encode  = Lua2xml,
  version = version,
}

