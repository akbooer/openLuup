local t = require "luaunit"

-- openLuup.scenes TESTS

luup = require "openLuup.luup"

local l = require "openLuup.loader"
local s = require "openLuup.scenes"
local j = require "openLuup.json"


local example_scene = {
  id = 1,
  name = "Example Scene",
  room = 0,
  groups = {
    {
      delay = 0,
      actions = {
        {
          action = "ToggleState",
          arguments = {               -- NB. these are name/value pairs NOT {name=value, ...}
            {name = "param1", value = "42"},
            {name = "param2", value = "77"},
          },
          device = "94",   -- why this is a string, I have NO idea
          service ="urn:micasaverde-com:serviceId:HaDevice1",
        },
      },
    },
  },
  timers = {
    {
      enabled = 1,
      id = 1,
      interval = "5m",        -- this is actually the "time" parameter in timer calls
      name = "Five minutes",
      type = 1,
    } , 
    {
      enabled = 1,
      id = 2,
      interval = "10",        -- this is actually the "time" parameter in timer calls
      name = "Ten Seconds",
      type = 1,
    } , 
  },
  lua =   -- this HAS to be a string for external tools to work.
  [[
    luup.log "hello from Example Scene"
  ]],   
}
  
local json_example = j.encode (example_scene)

TestScenes = {}

function TestScenes:setUp ()
end

function TestScenes:test_scene_create ()
  local sc, err = s.create (example_scene)    -- works with Lua or JSON scene definition
  t.assertIsNil (err)
  t.assertIsTable (sc)
  t.assertIsFunction (sc.run)
  local trig = {enabled = 1, name = "test trigger"}
  sc.run (trig)
  t.assertIsNumber (trig.last_run)    -- check that last run time has been inserted
  t.assertEquals (sc.last_run, trig.last_run)
end

function TestScenes:test_scene_stop ()
  local sc, err = s.create (json_example)
  for _,tim in pairs (sc.timers) do
    t.assertEquals (tim.enabled, 1)     -- check all enabled
  end
  sc:stop()
  for _,tim in pairs (sc.timers) do
    t.assertEquals (tim.enabled, 0)     -- check all disabled
  end
end

function TestScenes:test_scene_list ()
  local sc, err = s.create (json_example)
  local list = tostring (sc)
  t.assertIsString (list)
end

function TestScenes:test_scene_rename ()
  local sc, err = s.create (json_example)
  local nn,nr = "New Name", 3
  sc.rename (nn, nr)
  t.assertEquals (sc.name, nn)
  t.assertEquals (sc.room, nr)
  t.assertEquals (sc.description, nn)
  t.assertEquals (sc.room_num, nr)
end

function TestScenes:test_scene_lua ()
  local lua_scene = {
    id = 41,
    name = "lua_scene",
    lua = [[
      luup.log ("HELLO from " .. _NAME )
      for i in pairs (_G) do luup.log (i) end 
    ]]
  } 
  local sc, err = s.create (lua_scene)    -- works with Lua or JSON scene definition
  t.assertIsString (sc.lua)
  sc.run()
end

function TestScenes:test_multiple_scene_lua ()
  local lua_scene_42 = {
    id = 42,
    name = "lua_scene_multi1",
    lua = [[
      scene_global = 42
      luup.log "HELLO from 42"
      luup.log ("scene global = " .. scene_global)
   ]]
  } 
  local lua_scene_43 = {
    id = 43,
    name = "lua_scene_multi2",
    lua = [[
      scene_global = (scene_global or 0) + 1
      luup.log  "HELLO from 43"
      luup.log ("scene global = " .. scene_global)
    ]]
  } 
  local sc42,err42 = s.create (lua_scene_42) 
  local sc43,err43 = s.create (lua_scene_43)    -- works with Lua or JSON scene definition
  t.assertIsString (sc42.lua)
  t.assertIsString (sc43.lua)
  t.assertIsNil (err42)
  t.assertIsNil (err43)
  sc42.run()
  sc43.run()      -- check that they talk to one another
  t.assertEquals (s.environment.scene_global, 43)
end

function TestScenes:test_ ()
  
end

---------------------

if multifile then return end
t.LuaUnit.run "-v" 

---------------------

local sc, err = s.create (json_example)

print (tostring(sc))
