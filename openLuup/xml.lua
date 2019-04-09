local ABOUT = {
  NAME          = "openLuup.xml",
  VERSION       = "2019.04.06",
  DESCRIPTION   = "XML utilities (HTML5, SVG) and DOM-style parser",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2019 AK Booer

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
]]
}


------------------
--
-- XML module
--
-- decode()  a basic XML DOM paser
-- encode()  XML representation of a simple Lua structure... not the inverse of decode()
--


-- 2018.05.08  COMPLETE REWRITE - using DOM-style parser
-- 2018.07.07  handle multiple string values in encode(), add compatible simplify()

-- 2019.03.22  add HTML5 and SVG encoding
-- 2019.04.03  fix svg:rect() coordinate attribute names
-- 2019.04.06  add any unknown HTML5 tag as a new element


--[[

This is a replacement for an earlier module (~February 2015) which sought to represent XML
directly in a simple Lua table structure, suitable for UPnP device/service/implementation files.

With increasing number of bespoke XML files by plugin developers, this showed inadequacies:
-- 2015.11.03  cope with comments (thanks @vosmont and @a-lurker)
-- see: http://forum.micasaverde.com/index.php/topic,34572.0.html
-- 2016.04.14  @explorer expanded tags to alpha-numerics and underscores
-- 2018.04.22  remove spaces at each end of comments (part of issue highlighted by @a-lurker)
-- see: http://forum.micasaverde.com/index.php/topic,53871.msg379551.html#msg379551
-- and: http://forum.micasaverde.com/index.php/topic,53871.msg379790.html#msg379790

Many thanks to those who helped to point out (and fix) some of these problems.

However, it's clear that more robustness is needed at this most fundamental level,
and the 'todo' comment in the original version was always "proper XML parser rather than nasty hack?"
...now finally been addressed with a complete rewrite, offering a DOM-style parser.

Whilst not a fully validating parser, this Domain Object Model (DOM) version 
attempts to follow much of the spirit of the WWW3 standards: 
 
 https://www.w3.org/TR/REC-DOM-Level-1/level-one-core.html
 https://www.w3.org/TR/DOM-Level-2-Core/core.html
 https://www.w3.org/TR/DOM-Level-2-Traversal-Range/traversal.html
 http://w3schools.sinsixx.com/dom/dom_methods.asp.htm

Features include:
  - ignores processing instructions, comments, and CDATA
  - expands self-closing tags
  - reads and saves attributes
  - element relationship links:
    - parentNode, firstChild, lastChild,
    - previousSibling, nextSibling
  - some navigation routines: 
    - nextNode(), including optional filter function
    - getElementsByTagName() 
  - basic XPath searching: 
    - xpath(), 
    - xpathIterator()
  - .documentElement field of the model accesses the root XML document element

In a break from the WWW3 standard, text is NOT stored in a child text element, 
but in the .nodeValue attribute of the element itself.  It seemed much easier this way.

--]]


-- this single metatable is attached to every node element to provide navigation methods
local meta = {__index = {

    -- nextNode()  in-order search of tree elements, with optional filter
    -- https://www.w3.org/TR/DOM-Level-2-Traversal-Range/traversal.html#Iterator-overview
    nextNode = function (self, filter)
      local function in_order (x, path)
        path = path .. '/'
        for _, y in ipairs(x.childNodes or {}) do
          local path = path .. y.nodeName
          if not filter or filter(y, path) then coroutine.yield (y) end
          in_order (y, path)
        end
      end
      -- use coroutines to turn the above recursive function into an iterator
      local path = '/' .. self.nodeName       -- added for xpath functionality
      return coroutine.wrap (function () return in_order (self, path) end)
    end,

    -- getElementsByTagName()  in-order search by name (or wildcard '*') 
    -- https://www.w3.org/TR/REC-DOM-Level-1/level-one-core.html#ID-BBACDC08
    getElementsByTagName = function (self, name)
      local elements = {}
      local filter = name and name ~= '*' and function (x) return x.nodeName == name end
      for x in self:nextNode (filter) do elements[#elements+1] = x end
      return elements
    end,

    -- xpath() and xpathIterator()
    -- see: https://www.w3.org/TR/xpath-10/
    -- see: https://docs.python.org/2/library/xml.etree.elementtree.html#xpath-support
    -- see: http://code.mios.com/trac/mios_genericutils/wiki/XPath          
    -- only the abbreviated syntax expressions /a/b/c, //b/c, //b/*, /a/b/text() are implemented
    xpathIterator = function (self, path)
      local func                                                -- set 1 if /text() function call present
      local function fct(f) func = f return '' end
      local function node (_, p) return p: match (path) end                  -- normal nodes
      local function text (e, p) return e.nodeValue and p: match (path) end  -- text nodes
      local filter = {node=node, text=text}
      
      path = path: gsub ("^//", '/' .. self.nodeName .. '/')    -- fix the full path name
      path = path: gsub ("/(%w+)%(%)$", fct)                    -- remove /fct(), but note presence
      path = path: gsub ('*', "[^/]+")                          -- wildcard works within each level only
      path = table.concat {'^', path, '$'}                      -- match the WHOLE path
      
      return self:nextNode (filter [func] or node)
    end,
    
    -- xpath() uses xpathIterator() to return a list of elements
    xpath = function (self, path)
      local elements = {}
      for x in self:xpathIterator (path) do elements[#elements+1] = x end
      return elements
    end,

  }
}



-- retrieve the root XML document element and optionally check that it matches name and namespace
-- NOTE that documentElement (not this function) is also a hidden field of the entire DOM model
local function documentElement (xml, name, namespace)
  
  local valid = type(xml) == "table" and xml.documentElement
  if not valid then error ("not an XML DOM", 2) end
  
  local root = xml.documentElement
  if name and root.nodeName ~= name then error ("XML root element name is not: " .. name, 2) end
      
  local ns = root.attributes.xmlns or ''
  if namespace and ns ~= namespace then
    error (table.concat {"XML file namespace '" , ns, "' does not match: '", namespace, "'"}, 2)
  end

  return root
end


local escape do
  local fwd = {['<'] = "&lt;", ['>'] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;", ['&'] = "&amp;"}
  escape = function (x) return (x: gsub ([=[[<>"'&]]=], fwd)) end
end


local unescape do
  local rev = {lt = '<', gt = '>', quot = '"', apos = "'", amp = '&'}
  unescape = function (x) return (x: gsub ("&(%w+);", rev)) end
end



-- decode()  basic DOM model
local function decode (xml)
  -- tag must start with a letter or underscore, 
  -- and can contain letters, digits, hyphens, underscores, and period.
  local tagname       = "([%a_][%w:_%-%.]*)"
  local elem_pair     = "%s*<" .. tagname .."(.-)>%s*(.-)%s*</%1>%s*" -- <name attributes> body </name>
  local attr_pair     = tagname.."%s*=%s*"..[[(['"])(.-)%2]]          -- including: x="a'b'c" y = 'd"e"f'
  local self_closing  = "%s*<" .. tagname .."([^<>]*)/>%s*"           -- <name attributes />
  local cdata         = "%s*<!%[CDATA%[.-%]%]>%s*"                    -- <![CDATA[ ... ]]>
  local comment       = "%s*<!%-%-.-%-%->%s*"                         -- <!-- comments -->
  
-- simple DOM parser
-- note that the relationship navigation links are commented out for the time being
  local function parse (text, parent)
    local xml = {}
--    local previousSibling
    for n,a,b in (text or ''): gmatch (elem_pair) do                  -- find matching opening and closing tags
      local at = {}
      for k,_,v in a: gmatch (attr_pair) do at[k] = unescape (v) end  -- get the attributes
      local element = {
        nodeName = n, 
--        parentNode = parent,                                          -- navigation links
--        previousSibling = previousSibling,
        attributes = at}
      local children = parse (b, element)                             -- get the children
      if #children == 0 and #b > 0 then                               -- no children, empty strings are nil
        element.nodeValue = unescape(b)                               -- plain text element
      end
--      element.firstChild = children[1]
--      element.lastChild  = children[#children]
      element.childNodes = children
      xml[#xml+1] = setmetatable (element, meta)                      -- add the metamethods
--      if previousSibling then                                         -- sort out the siblings
--        previousSibling.nextSibling = element
--      end
--      previousSibling = element
    end 
   return xml 
  end

  -- decode ()
  if xml then                                             -- do one-off substitutions
    xml = xml: gsub (cdata, '')                           -- remove CDATA
    xml = xml: gsub (comment, '')                         -- remove comments
    xml = xml: gsub (self_closing, "<%1%2></%1>")         -- expand self-closing tags
    local document = parse (xml)
    return setmetatable (document, {__index = {documentElement = document[1]}})
  end
  
end

----------------------------------------------------
--
-- encode(), input argument should be a table, optional wrapper gives name tag to whole structure
-- Note that this function is NOT the inverse of decode() but operates on simple Lua tables
-- to produce an adequate XML representation of request responses which are usually sent as JSON.
-- It should, however, work on the output of simplify() (see below)
-- TODO: handle attributes correctly from simplify()
local function encode (Lua, wrapper)
  local xml = {}        -- or perhaps    {'<?xml version="1.0"?>\n'}
  local function p(x)
    if type (x) ~= "table" then x = {x} end
    for _, y in ipairs (x) do xml[#xml+1] = y end
  end
  
  local function value (x, name, depth)
    local function spc ()  p ((' '):rep (2*depth)) end
    local function ztag () p {'</',name:match "^[^%s]+",'>\n'} end
    local function attr (x) for a,b in pairs(x or {}) do p {' ', a, '="', escape(b), '"'} end end
    local function atag (x) spc() ; p {'<', name}; attr(x); p '>' end
    local function str (x) atag() ; p(escape (tostring(x): gsub("%s+", ' '))) ; ztag() end
    local function err (x) error ("xml: unsupported data type "..type (x)) end
    local function tbl (x)
      local y
      if #x == 0 then y = {x} else y = x end
      for _, z in ipairs (y) do
        if type(z) == "string" then atag(z)    -- 2018.07.07 handle multiple string values
        else
          if name then atag(z._attr) ; p '\n' end
          local i = {}
          for a in pairs (z) do if a ~= "_attr" then i[#i+1] = a end end
          table.sort (i, function (a,b) return tostring(a) < tostring (b) end)
          for _,a in ipairs (i) do value(z[a], a, depth+1) end
          if name then spc() ; ztag() end
        end
      end
    end
    
    local dispatch = {table = tbl, string = str, number = str}
    return (dispatch [type(x)] or err) (x)
  end
  
  -- encode(), wrapper parameter allows outer level of tags (with attributes)
  local ok, msg = pcall (value, Lua, wrapper, 0) 
  if ok then ok = table.concat (xml) end
  return ok, msg
end


-- simplify(), this yields a structure which can be encoded into XML
-- attributes on non-structured (string-only) elements are ignored
local function simplify (x)
  local children = {}
  local function item (k,v)
    local x = children[k] or {}
    x[#x+1] = v
    children[k] = x
  end
  for _,y in ipairs (x.childNodes or {}) do
    item (y.nodeName, y.nodeValue or simplify(y))  -- what about attrs of node with nodeValue ???
  end
  for k,v in pairs (children) do
    if #v == 1 then
      if v._attr then 
        -- problem here
      else
        v = v[1]       -- un-nest single element lists
        if (type(v) == "table") and not next(v) then v = '' end   -- replace empty list with empty string        
      end
    children[k] = v
    end
  end
  if next(x.attributes) then children._attr = x.attributes end
  return children
end


----------------------------------------------------
--
-- 2019.03.22  encode Lua table as HTML element
-- named items are attributes, list is contents (possibly other elements)
-- element()
--
local function element (name, contents)
    
  local self = {}
  for n,v in pairs (contents or {}) do self[n] = v end    -- shallow copy of contents
    
  local function _serialize (self, stream, depth)

    local function is_element (v) return type (v) == "table" and v._serialize end
    
    stream = stream or {}
    depth = depth or 0
    local space = ' '
    
    local function p(x) 
      local s = stream
      local t = type (x)
      if t ~= "table" or is_element (x) then
        s[#s+1] = x 
      else
        for _,v in ipairs (x) do s[#s+1] = v end
      end
    end
    
    p {'\n', space: rep (depth), '<', name}
    for n,v in pairs (self) do 
      if type (n) == "string" then p {' ', n, '="', v, '"'} end
    end
    if #self == 0 then
      p '/>'
    else
      p '>'
      for _,v in ipairs (self) do
        if is_element (v) then v: _serialize (stream, depth+1) else p (v) end
      end
      p {'</', name, '>'}
    end
    return stream
  end
  
  local meta
  meta = {
    __index = {
      _name = name,
      _serialize = _serialize,
    },
    __tostring = function (self) return table.concat (self:_serialize ()) end,
  }
  
  meta.__index._method = meta.__index     -- usage:  function svg._method:my_method(...) ... end 

  return setmetatable (self, meta)

end


----------------------------------------------------
--
-- 2019.03.22  HTML and SVG
--

local html5 = setmetatable ({},
  {__index = function (self, tag)    -- 2019.04.06  just add any unknown tag as a new element...
    local fct = function(contents) return element(tag, contents) end
    rawset (self, tag, fct)
    return fct
  end})
  
--
-- tables
--

function html5.table (attr)
  
  local tbl = element ("table", attr)
  
  local rows = 0
  
  local function make_row (typ, r)
    local items = {}
    for _, x in ipairs (r or {}) do
      local y
      if type(x) ~= "table" or x._name then
        y = element (typ, {x})
      else
        y = element (typ, x)  -- else it's got some attributes
      end
      items[#items+1] = y 
    end
    local tr = element ("tr", items)
    tbl[#tbl+1] = tr
    return tr
  end
      
  -- add specific constructors and other methods
  -- note that these can be called with colon (:) or dot (.) notation for compatibility
  
  function tbl._method.header (h1, h2) return make_row ("th", h2 or h1) end  
  function tbl._method.row (r1, r2)    rows = rows + 1; return make_row ("td", r2 or r1) end
  function tbl._method.length ()        return rows end
  
  return tbl
end

--
-- SVG: Scalable Vector Graphics
--

local function add_svg_functions (svg)
    
  local function add_props (s, props)
    for n,v in pairs (props or {}) do s[n] = v end
    return s
  end
  
  local function add_to (p, e)
    p[#p+1] = e
    return e
  end
  
  local function coords (xs,ys)
    local poly = {}
    local coord = "%0.1f,%0.1f "
    for i , x in ipairs(xs) do
      poly[i] = coord: format(x, ys[i])
    end
    return table.concat (poly)
  end
  
  function svg._method:polyline (xs,ys, props)
    return add_to (self, element ("polyline", add_props ({points=coords (xs,ys)}, props)))
  end
  
  function svg._method:polygon (xs,ys, props)
    return add_to (self, element ("polygon", add_props ({points=coords (xs,ys)}, props)))
  end
  
  function svg._method:rect (x,y, width,height, props)
    return add_to (self, element ("rect", add_props ({x = x, y = y, width = width, height = height}, props)))
  end
  
  svg._method.rectangle = svg._method.rect   -- add method alias
  
  -- circle
  function svg._method:circle (cx,cy, radius, props)
    return add_to (self, element ("circle", add_props ({cx = cx, cy = cy, r = radius}, props)))
  end
  
  -- ellipse
  
  -- line
  function svg._method:line (x1,y1, x2,y2, props)
    return add_to (self, element ("line", add_props ({x1 = x1, y1 = y1, x2 = x2, y2 = y2}, props)))
  end
  
  -- path
  
  -- text
  function svg._method:text (x,y, txt)
    if type (txt) == "string," then txt = {txt} end
    return add_to (self, element ("text", add_props ({x = x, y = y}, txt)))
  end
  
  -- group
  function svg._method:group (attr)  
    local g = element ("g", attr)  
    add_svg_functions(g)
    return g
  end
  
  svg._method.g = svg._method.group   -- add method alias
  
  -- not automatically added to SVG element
  function svg._method:title (attr)
    return element ("title", attr)
  end
  
end


function html5.svg (attr)    
  local svg = element ("svg", attr)  
  add_svg_functions(svg)
  return svg
end

function html5.document (contents)
  local doc = element ("html", contents)
  return table.concat (doc:_serialize {"<!DOCTYPE html>"})
end

-------------------------------------


return {
    
    -- XML
    
    escape    = escape,
    unescape  = unescape,
    
    decode    = decode, 
    encode    = encode,
    simplify  = simplify,
    
    documentElement = documentElement,
    
    -- 2019.03.22   HTML5 and SVG
    
    html5 = html5,

  }

-----
