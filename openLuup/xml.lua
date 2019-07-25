local ABOUT = {
  NAME          = "openLuup.xml",
  VERSION       = "2019.07.18",
  DESCRIPTION   = "XML utilities (HTML, SVG) and DOM-style parser/serializer",
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
-- XML module  XML utilities (HTML, SVG) and DOM-style parser/serializer
--

-- 2018.05.08  COMPLETE REWRITE - using DOM-style parser

-- 2019.03.22  add HTML5 and SVG encoding
-- 2019.04.03  fix svg:rect() coordinate attribute names
-- 2019.04.06  add any unknown HTML5 tag as a new element
-- 2019.04.30  add preamble parameter to xml.encode() for encodeDocument()

-- 2019.07.14  ANOTHER SIGNIFICANT REWRITE 
--                to share serializer, parser, and Node methods between XML, HTML, and SVG
--                and provide new factory methods for XML, HTML, and SVG documents


--[[

This is an updated replacement for an earlier module (~February 2015) which sought to represent XML
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

Whilst not a fully validating parser, this Domain Object Model (DOM) version has its own
Lua-style of DOM, but provides meta variables and methods which attempt to follow much of 
the spirit of the WWW3 standards: 
 
  https://www.w3.org/TR/REC-DOM-Level-1/level-one-core.html
  https://www.w3.org/TR/DOM-Level-2-Core/core.html
  https://www.w3.org/TR/2004/REC-DOM-Level-3-Core-20040407/
  https://www.w3.org/TR/DOM-Level-2-Traversal-Range/traversal.html

Features include:
  - ignores processing instructions, comments, and CDATA
  - expands self-closing tags
  - handles attributes
  - element relationship links:
    - parentNode, firstChild, lastChild,
    - TODO: previousSibling, nextSibling
  - some navigation routines: 
    - nextNode(), including optional filter function
    - getElementsByTagName() 
  - basic XPath searching: 
    - xpath(), 
    - xpathIterator()
  - .documentElement field of the model accesses the root XML document element

The underlying model is a simple Lua table, with children in succesive elements and attributes as named index entries. Metamethods are provided to simulteNode interface with the following Lua substitutions:

    metamethods     x[-3]     -- specific to individual elements
    x.ownerDocument x[-2]     -- may not be present
    x.parentNode    x[-1]     -- may not be present
    x.nodeName      x[0]      -- this is the only DOM element used in _serialize() / _parse()
    x.attributes.y  x.y       -- for non-numeric 'y'
    x.firstChild    x[1]
    x.lastChild     x[#x]     -- n-th child is x[n]

Note that zero or negative indices do not appear in the Lua ipairs() iterator, or length operator.
Structure can be navigated with simple Lua table handling.

In a break from the WWW3 standard, a Text Node is simply a string 
(as the child of an Element Node), not a different type of Node.
In fact, Element is the only node type with W3 standard-like features (ignoring the document itself.)

--]]

-- XML/HTML special character escapes

local escape do
  local fwd = {['<'] = "&lt;", ['>'] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;", ['&'] = "&amp;"}
  escape = function (x) return (x: gsub ('[<>"'.."'&]", fwd)) end
end

local unescape do
  local rev = {lt = '<', gt = '>', quot = '"', apos = "'", amp = '&'}
  unescape = function (x) return (x: gsub ("&(%w+);", rev)) end
end

-- basic DOM element node

local NodeMeta = {}     -- NB: real metamethods will be added later!
                        -- parse / serialize do not access any metamethods

local function createElement (name, contents)    -- TODO: flatten tables (DocumentFragments) ?
  if not contents or type (contents) == "string" then contents = {contents} end
  local self = setmetatable ({[0] = name}, NodeMeta)
  for n,v in pairs (contents) do self[n] = v end          -- shallow copy of contents
  return self
end


---------------------------------------------------------------
--
-- Core serialize & parse routines
--
-- see: https://www.w3.org/TR/DOM-Parsing/

-- this serialize method works on the basic xml domain object model
local function _serialize (self, stream, depth)
  local space = ' '
  depth = depth or 0
  stream = stream or {}
  local function p(...) for _, x in ipairs {...} do stream[#stream+1] = x end; end
  
  local name = self[0]
  if #stream ~= 0 then p ('\n') end   -- don't start with a blank line
  p (space: rep (depth), '<', name)
  for n,v in pairs (self) do 
    if type (n) == "string" then p (' ', n, '="', escape(tostring(v)), '"') end   -- attributes
  end
  if #self == 0                                                         -- no children, ...
  or (#self == 1 and type(self[1]) == "string" and #self[1] == 0) then  -- TODO: ???...or only string node value
    p '/>'
  else          -- child nodes
    p '>'
    for _,v in ipairs (self) do
      if type (v) == "table" and v[0] then 
        _serialize (v, stream, depth+1) 
      else 
        if name == "script" then p (tostring(v)) else p (escape(tostring(v))) end -- should be HTML-only
      end
    end
    p ('</', name, '>')
  end
  if depth == 0 then p '\n' end  -- add new line at end
  return stream
end

-- _parse(), creates a DOM model.  The inverse of _serialize()
local function _parse (xml)
  -- tag must start with a letter or underscore, 
  -- and can contain letters, digits, hyphens, underscores, and period.
  local tagname       = "([%a_][%w:_%-%.]*)"
  local elem_pair     = "%s*<" .. tagname .."(.-)>%s*(.-)%s*</%1>%s*" -- <name attributes> body </name>
  local attr_pair     = tagname.."%s*=%s*"..[[(['"])(.-)%2]]          -- including: x="a'b'c" y = 'd"e"f'
  local self_closing  = "%s*<" .. tagname .."([^<>]*)/>%s*"           -- <name attributes />
  local cdata         = "%s*<!%[CDATA%[.-%]%]>%s*"                    -- <![CDATA[ ... ]]>
  local comment       = "%s*<!%-%-.-%-%->%s*"                         -- <!-- comments -->

  local function parse (text, pop)
    for n,a,b in (text or ''): gmatch (elem_pair) do                      -- find opening/closing tags
      local element = createElement ()                                    -- new element
      element[0] = n                                                      -- add name
--      element[-1] = pop                                                 -- add parent link
      pop[#pop+1] = element                                               -- add it to the parent
      for k,_,v in a: gmatch (attr_pair) do element[k] = unescape (v) end  -- get the attributes
      parse (b, element)                                                   -- get the children, or...
      element[1] = element[1] or unescape(b)                               -- ... plain text element
    end 
  end

  local document = {}
  if xml then                                           -- do one-off substitutions
    xml = xml :gsub (cdata, '')                         -- remove CDATA
              :gsub (comment, '')                       -- remove comments
              :gsub (self_closing, "<%1%2></%1>")       -- expand self-closing tags
    parse (xml, document)
  end  
  return (unpack or table.unpack) (document)    -- separate return parameters for individual root elements
                                                -- an XML document can have only one root element.
end


---------------------------------------------------------------
--
--    The following is all just decoration, really, which seeks to emulate
--    at least some of the W3 standard for DOM models.
--    
--    See: https://www.w3.org/TR/2004/REC-DOM-Level-3-Core-20040407/core.html
--   
--    Additionally, there are factory methods for XML, HTML, and SVG documents, with convenience methods.
--

-- in-order traversal of DOM tree with callback parameters (node, XPath) 
local function in_order (node, callback, path)
  path = table.concat {path or '', '/', node[0]}
  callback (node, path)         -- start with the root node
  for _, child in ipairs(node) do
    if type (child) == "table" then in_order (child, callback, path) end    -- walk the tree
  end
end

---------------------------------------------------------------
--
-- Node / Element
--
-- interface Node {}
--

-- NODE ATTRIBUTES

local NodeAttributes = {}    -- to be embedded in an __index() function to simulate missing attributes

  function NodeAttributes:nodeName   () return self[0]  end   -- reserved location in this object model
  function NodeAttributes:tagName    () return self[0]  end   -- actually, an alias from the Element interface
  function NodeAttributes:nodeValue  () end;                  -- NB: for Element nodes this is nil
  function NodeAttributes:nodeType   () return 1 end          -- we only have one type: Element (+ Text & Document!)
  function NodeAttributes:parentNode () return self[-1] end   -- reserved negative table index
  function NodeAttributes:childNodes () return type(self[1])~="string" and self or {} end -- only numerical indices
  function NodeAttributes:firstChild () return self[1]      end
  function NodeAttributes:lastChild  () return self[#self]  end  -- last numerical index

--  readonly attribute Node             previousSibling;  (TBD)
--  readonly attribute Node             nextSibling;      (TBD)
  
  function NodeAttributes:attributes ()     -- NB: this is static, not 'LIVE'
    local a = {}
    for n,v in pairs(self) do 
      if type(n) == "string" then a[n]=v end 
    end
    return a 
  end 
  
  function NodeAttributes:ownerDocument () return self[-2] end
  -- [-3] reserved for individual element metatable
  -- [-4] and beyond, reserved  TODO: allocate user-defined Node table?
  function NodeAttributes:textContent() return type(self[1])=="string" and #self[1]>0 and self[1] or '' end 

-- NODE METHODS

local NodeMethods = {}

  -- document fragments are represented as lists of elements appendChild {a,b,c}
  function NodeMethods:appendChild (c)
    if rawget (c,0) then c = {c} end  -- if no nodeName, then assume it's a document fragment
    for _, x in ipairs (c) do
      self[#self+1] = x
    end
    return c  -- strictly, this should be an empty document fragment, if a fragment was the input argument
  end

  function NodeMethods:hasChildNodes() return #self > 0 end

  -- getElementsByTagName()  in-order search by name (or wildcard '*') 
  -- https://www.w3.org/TR/REC-DOM-Level-1/level-one-core.html#ID-BBACDC08
  -- actually, a method from the Element interface
  function NodeMethods:getElementsByTagName (name)
    local E = {}
    local function nofilt (n) E[#E+1] = n end
    local function filter (n) if n[0] == name then E[#E+1] = n end; end
    in_order (self, name and name ~= '*' and filter or nofilt)
    return E
  end
  
--  NOT implemented...
--  Node               insertBefore(in Node newChild, in Node refChild)
--  Node               replaceChild(in Node newChild, in Node oldChild)
--  Node               removeChild(in Node oldChild)
--  Node               cloneNode(in boolean deep)
  
-- add above attributes and methods simulating some conventional DOM mode features.
-- note that this may conflict with any element attributes which have 'reserved' names!!
NodeMeta.__index = function (x,n)
      if NodeAttributes[n] then return NodeAttributes[n](x) end  -- return pseudo-attribute method
      return (rawget (x,-3) or {}) [n]               -- try the element-specific metatable at [-3] ...
        or NodeMethods[n]                            -- ...or use Node methods
    end

NodeMeta.__tostring = function (self) return table.concat (_serialize(self)) end

---------------------------------------------------------------
--
-- Document / DocumentTraversal

-- DOCUMENT METHODS

--  NOT implemented...
--  Node               adoptNode(in boolean deep)
--  Node               importNode(in boolean deep)

local DocumentMethods = {
    -- add key Node/Element methods to the document (in the W3 standard, it IS a Node)
    appendChild = NodeMethods.appendChild,                    -- used to attach the root element
    getElementsByTagName = function (self, name)
      local root = self.documentElement
      if not root then return {} end                          -- may be no root there, return empty list
      return NodeMethods.getElementsByTagName (root, name)    -- apply to the root element
    end,
  }

--[[ note from: https://www.w3.org/TR/DOM-Level-2-Traversal-Range/traversal.html#Iterator-overview

"A NodeIterator may be active while the data structure it navigates is being edited, so an iterator must behave gracefully in the face of change. Additions and removals in the underlying data structure do not invalidate a NodeIterator"

NB: THIS IS NOT THE CASE HERE, since structures are navigated by Lua iterators!

--]] 

  -- nextNode()  in-order search of tree elements, with optional filter
  -- https://www.w3.org/TR/DOM-Level-2-Traversal-Range/traversal.html#Iterator-overview
  -- optional filter(element, path) returns true if element is to be included.
  -- a method from the DocumentTraversal interface
  -- this version returns only Element nodes (not text nodes, which are strings)
  -- and is shorthand for:  document.createNodeIterator(node, SHOW_ELEMENT, filter).nextNode()
  -- uses coroutines to turn the in_order() callback into an iterator
  function DocumentMethods.nextNode (node, filter)
    local function each_node (n, path)
      if not filter or filter(n, path) then coroutine.yield (n) end     -- start with the root node
    end
    return coroutine.wrap (function () return in_order (node, each_node) end)
  end

  -- xpath() and xpathIterator()
  -- see: https://www.w3.org/TR/xpath-10/
  -- see: https://docs.python.org/2/library/xml.etree.elementtree.html#xpath-support
  -- see: http://code.mios.com/trac/mios_genericutils/wiki/XPath          
  -- only the abbreviated syntax expressions like  /a/b/c, //b/c, //b/* are implemented
  
  -- utility function to create a filter for a specific XPath starting at given node
  local function createXPathfilter (node, path)
    path = path :gsub ("^//", '/' .. node[0] .. '/')            -- fix the full path name
--              :gsub ("/(%w+)%(%)$", fct)                      -- remove /fct(), but note presence
                :gsub ('*', "[^/]+")                            -- wildcard works within each level only
    path = table.concat {'^', path, '$'}                        -- match the WHOLE path
    return function (_,p) return p: match (path) end
  end
    
  -- xpathIterator (node, path)
  -- a bit like nextNode() but matching an XPath rather than a nodeName... 
  function DocumentMethods.xpathIterator (node, path)
    local filter = createXPathfilter (node, path)
    return DocumentMethods.nextNode (node, filter)  -- ...in fact, it uses nextNode() !
  end

  -- xpath() returns a list of elements which match the given XPath
  -- a bit like getElementsByTagName(), but using XPath expressions
  function DocumentMethods.xpath (node, path)
    local E = {}
    local xfilter = createXPathfilter (node, path)
    local function filter (n, p) if xfilter(n, p) then E[#E+1] = n end; end
    in_order (node, filter)
    return E
  end


-- add above methods to documents through a metatable function
local docMeta = {
  __tostring = function(self) return table.concat(_serialize(self[1], {rawget (self, "preamble") })) end,
  __index = function (self, tag)    -- just add any unknown tag as a new element...
    local de = rawget (self, 1)
    if tag == "documentElement" then return de end  -- can be nil!
    if de and de[0]:lower() == "html" then          -- HTML specific attributes
      -- see: https://www.w3.org/TR/DOM-Level-2/html.html#ID-26809268
      if tag == "title" then return de[1][1][1] end  
      if tag == "body"  then return de[2] end
      if tag == "forms" then return de[2]: getElementsByTagName "form" end
    end
    local fct = function(contents) return self.createElement(tag, contents) end  -- specific to document type
    rawset (self, tag, fct)
    return fct
  end}

---------------------------------------------------------------
--
-- XML
--

local function createDocument  ()
  local d = {[0] = "#document"}                                                 -- the document node
  d.createElement = createElement                                           -- ...a way to make new elements
  d.preamble = '<?xml version="1.0"?>'
  for n,v in pairs (DocumentMethods) do d[n] = v end                  -- add useful methods
  return setmetatable (d, docMeta)           -- add the meta function for creating elements
end

-- returns decoded text as a full document model
local function decode (xml)
  local root = _parse (xml) 
  local d = createDocument ()                 -- TODO: use the root name for correct document type?
  if root then d:appendChild (root)  end      -- add the real node tree
  return d
end

---------------------------------------------------------------
--
-- HTML
--

local HtmlConvenience = {}      -- HTML document convenience methods

function HtmlConvenience.table (attr)
  
  local rows = 0
  local tbl = createElement ("table", attr)
  
  local function make_row (typ, r)
    local items = {}
    for _, x in ipairs (r or {}) do
      local y
      if type(x) ~= "table" or x[0] then    -- x[0] has element name
        y = createElement (typ, {x})
      else
        y = createElement (typ, x)  -- else it's got some attributes
      end
      items[#items+1] = y 
    end
    local tr = createElement ("tr", items)
    tbl[#tbl+1] = tr
    return tr
  end
  
  -- convenience methods for headers and rows
  -- note that these can be called with colon (:) or dot (.) notation for compatibility
  
  local function header (h1, h2) return make_row ("th", h2 or h1) end  
  local function row (r1, r2)    rows = rows + 1; return make_row ("td", r2 or r1) end
  local function length ()       return rows end
  
  rawset (tbl,-3, {header = header, row = row, length = length})   -- add specific metamethods to table element
  
  return tbl
end


-- differences between HTML and XML:
-- case-insensitive tag names, a finite but very large number of possible tags
-- this implementation allows ANY tag name (folded to lowercase) in the same way that XML does.
-- document is created with HTML, HEAD, TITLE, and BODY elements
-- and attributes to get/set TITLE and BODY contents
-- see: https://www.w3.org/TR/DOM-Level-2/html.html#ID-HTML-DOM
local function createHTMLDocument  (title)
  local d = {[0] = "#document"}                                                 -- the document node
  d.createElement = function (tag, xxx) return createElement(tag:lower(), xxx) end  -- force lowercase
  d.preamble = "<!DOCTYPE html>"
  for n,v in pairs (DocumentMethods) do d[n] = v end                  -- add useful methods
  for n,v in pairs (HtmlConvenience) do d[n] = v end                  -- add convenience methods
  local doc = setmetatable (d, docMeta)           -- add the meta function for creating elements
  -- add the additional HTML elements to the basic document
  doc:appendChild {
    doc.html {
      doc.head {doc.title (title)},
      doc.body ' '}}
  -- remove newly-created functions for title and body, since they are, in fact, HTML document attributes
  doc.title = nil   
  doc.body = nil
  return doc
end

---------------------------------------------------------------
--
-- SVG: Scalable Vector Graphics
--
 
local function add_props (s, props)
  for n,v in pairs (props or {}) do s[n] = v end
  return s
end

local function coords (xs,ys)
  local poly = {}
  local coord = "%0.1f,%0.1f "
  for i , x in ipairs(xs) do
    poly[i] = coord: format(x, ys[i])
  end
  return table.concat (poly)
end

local SvgConvenience = {}

function SvgConvenience.polyline (xs,ys, props)
  return createElement ("polyline", add_props ({points=coords (xs,ys)}, props))
end

function SvgConvenience.polygon (xs,ys, props)
  return createElement ("polygon", add_props ({points=coords (xs,ys)}, props))
end

function SvgConvenience.rect (x,y, width,height, props)
  return createElement ("rect", add_props ({x = x, y = y, width = width, height = height}, props))
end

-- circle
function SvgConvenience.circle (cx,cy, radius, props)
  return createElement ("circle", add_props ({cx = cx, cy = cy, r = radius}, props))
end

-- ellipse
function SvgConvenience.ellipse (cx,cy, rx, ry, props)
  return createElement ("ellipse", add_props ({cx = cx, cy = cy, rx = rx, ry = ry}, props))
end

-- line
function SvgConvenience.line (x1,y1, x2,y2, props)
  return createElement ("line", add_props ({x1 = x1, y1 = y1, x2 = x2, y2 = y2}, props))
end

-- path
function SvgConvenience.path (d, props)
  return createElement ("path", add_props ({d = d}, props))
end

-- text
function SvgConvenience.text (x,y, txt)
  if type (txt) == "string" then txt = {txt} end
  return createElement ("text", add_props ({x = x, y = y}, txt))
end

function SvgConvenience.title (txt)    -- required for mouseover popup
  if type (txt) == "string" then txt = {txt} end
  return createElement ("title", txt)
end

function SvgConvenience.g (txt)    -- required SVG root element!
  if type (txt) == "string" then txt = {txt} end
  return createElement ("g", txt)
end

function SvgConvenience.svg (txt)    -- required SVG root element!
  if type (txt) == "string" then txt = {txt} end
  return createElement ("svg", txt)
end


-- differences between SVG and HTML / XML:
-- document root element should have "svg" tag
-- and xmlns="http://www.w3.org/2000/svg"
-- VERY limited set of tags (this implementation flags illegal/unknown tags by raising an error)
local function createSVGDocument ()
  local d = {[0] = "#document"}                                                 -- the document node
  d.createElement = function (tag) error ("SVG: illegal tagName: " .. (tag or '?'), 2) end
  for n,v in pairs (DocumentMethods) do d[n] = v end                  -- add useful methods
  for n,v in pairs (SvgConvenience) do d[n] = v end                  -- add convenience methods
  return setmetatable (d, docMeta)           -- add the meta function for creating elements
end


-------------------------------------

return {
    
    TEST = {createElement = createElement},       -- for testing only
    
    -- XML
    
    escape   = escape,
    unescape = unescape,
    
    decode = decode, 
    
    -- 2019.07.11  create instances of Document interface for XML, HTML, and SVG
    
    createDocument     = createDocument,        -- generic XML document
    createHTMLDocument = createHTMLDocument,    -- HTML document with convenience methods
    createSVGDocument  = createSVGDocument,     -- SVG document with convenience methods

  }

-----