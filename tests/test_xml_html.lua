local t = require "tests.luaunit"

local pretty = require "pretty"

-- XML module tests

local x = require "openLuup.xml" 
local h = x.xhtml

TestHTML = {}

function TestHTML:test_html ()

  local tab = h.table {style = "gratuitous"}
  tab.header {"one","two"}
  tab.row {{colspan=2, "wide"}}
  tab.row {{style= "name=bold", "bold"}, "normal"}
  local html = h.html {
    h.title "testHTML",
    h.meta {xmlns = "not sure what goes here"},
    h.body {
      h.p "hello, world",
      tab
    }}

print ''
  print (h.document (html))

  print "-----"
  
  print(pretty(html))
  
end


-------------------

if multifile then return end
  
t.LuaUnit.run "-v"

print ("TOTAL number of tests run = ", N)

-- do return end
-------------------

