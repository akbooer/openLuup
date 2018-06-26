local ABOUT = {
  NAME          = "openLuup.xml",
  VERSION       = "2018.05.15",
  DESCRIPTION   = "XML DOM-style parser",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2018 AK Booer

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


-- 2018.05.08  COMPLETE REWRITE - using DOM-style parser


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


-- encode(), input argument should be a table, optional wrapper gives name tag to whole structure
-- Note that this function is NOT the inverse of decode() but operates on simple Lua tables
-- to produce an adequate XML representation of request responses which are usually sent as JSON.
local function encode (Lua, wrapper)
  local xml = {}        -- or perhaps    {'<?xml version="1.0"?>\n'}
  local function p(x)
    if type (x) ~= "table" then x = {x} end
    for _, y in ipairs (x) do xml[#xml+1] = y end
  end
  
  local function value (x, name, depth)
    local function spc ()  p ((' '):rep (2*depth)) end
    local function atag () spc() ; p {'<', name,'>'} end
    local function ztag () p {'</',name:match "^[^%s]+",'>\n'} end
    local function str (x) atag() ; p(escape (tostring(x): gsub("%s+", ' '))) ; ztag() end
    local function err (x) error ("xml: unsupported data type "..type (x)) end
    local function tbl (x)
      local y
      if #x == 0 then y = {x} else y = x end
      for _, z in ipairs (y) do
        local i = {}
        for a in pairs (z) do i[#i+1] = a end
        table.sort (i, function (a,b) return tostring(a) < tostring (b) end)
        if name then atag() ; p '\n' end
        for _,a in ipairs (i) do value(z[a], a, depth+1) end
        if name then spc() ; ztag() end
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


return {
    
    escape    = escape,
    unescape  = unescape,
    
    decode    = decode, 
    encode    = encode,
    
    documentElement = documentElement,
    
  }

-----
