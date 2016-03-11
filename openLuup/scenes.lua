local _NAME = "openLuup.scenes"
local revisionDate = "2016.03.11"
local banner = "   version " .. revisionDate .. "  @akbooer"


-- openLuup SCENES module

--
-- all scene-related functions 
-- see: http://wiki.micasaverde.com/index.php/Scene_Syntax for stored scene syntax
--
-- 2016.103.11   verify that scenes don't reference non-existent devices.  Thanks @delle
--

--local socket    = require "socket"         -- socket library needed to access time in millisecond resolution
local logs      = require "openLuup.logs"
local json      = require "openLuup.json"
local timers    = require "openLuup.timers"
local loader    = require "openLuup.loader"

--  local logs
local function _log (msg, name) logs.send (msg, name or _NAME) end
_log (banner, _NAME)   -- for version control
local _log_altui_scene  = logs.altui_scene

--[[

Whilst 'actions' and 'timers' are straight-forward, the 'trigger' functionality of Luup is severely flawed, IMHO, through the close connection to UPnP service files and .json files.  

The goal would be to have an interface like HomeSeer, with extremely intuitive syntax to define triggers and conditions.  To support this at the openLuup engine level, all trigger conditions are handled through a standard initial luup.variable_watch call - so no new infrastructure is needed - to a handler which then evaulates the condition and, if true, continues to evaluate further states required for the scene to run.

Sept 2015 - ALTUI now provides this functionality through its own variable watch callback 
which then triggers scenes if some Lua boolean expression is true
ALTUI also provides a great editor interface with the blockly module.

--]]

---
--- utilities
--

-- single environment for all scenes and startup code
local scene_environment = loader.shared_environment

local function load_lua_code (lua, id)
  local scene_lua, error_msg, code
  if lua then
    local scene_name = "scene_" .. id
    local wrapper = table.concat ({"function ", scene_name, " ()", lua, "end"}, '\n')
    local name = "scene_" .. id .. "_lua"
    code, error_msg = loader.compile_lua (wrapper, name, scene_environment) -- load, compile, instantiate
    scene_lua = (code or {}) [scene_name]
  end
  return scene_lua, error_msg
end

local function verify_all()
  for _,s in pairs(luup.scenes) do
    s.verify()
  end
end

-- run all the actions in one delay group
local function group_runner (actions)
  for _, a in ipairs (actions) do
    local args = {}
    for _, arg in pairs(a.arguments) do   -- fix parameters handling.  Thanks @delle !
      args[arg.name] = arg.value
    end
    luup.call_action (a.service, a.action, args, tonumber (a.device))
  end
end

-- return true if scene can run in current house mode
local function runs_in_current_mode (scene)
  local modeStatus = scene.modeStatus
  local currentMode = luup.attr_get "Mode"
  return (modeStatus == "0") or modeStatus:match (currentMode)
end



-- scene.create() - returns compiled scene object given json string containing group / timers / lua / ...
local function create (scene_json)
  local scene, lua_code, luup_scene
  
  local function scene_runner (t, next_time)              -- called by timer, trigger, or manual run
    if not runs_in_current_mode (scene) then 
      _log (scene.name .. " does not run in current House Mode")
      return 
    end
    if luup_scene.paused then 
      _log (scene.name .. " is currently paused")
      return 
    end
    if t and tonumber (t.enabled) ~= 1  then 
      _log "timer disabled"
      return 
    end   -- timer or trigger disabled
    local ok = not lua_code or lua_code ()
    if ok ~= false then
      scene.last_run = os.time()                -- scene run time
      local runner = "command"
      if t then
        t.last_run = scene.last_run             -- timer or trigger specific run time
        t.next_run = next_time                  -- only non-nil for timers
        runner = (t.name ~= '' and t.name) or '?'
      end
      local msg = ("scene %d, %s, initiated by %s"): format (scene.id, scene.name, runner)
      _log (msg, "luup.scenes")
      _log_altui_scene (scene)                  -- log for altUI to see
      for _, group in ipairs (scene.groups) do  -- schedule the various delay groups
        timers.call_delay (group_runner, tonumber (group.delay) or 0, group.actions)
      end
    end
  end
  
  local function scene_stopper ()
    -- TODO: cancel timers on scene delete, etc..?
    -- can't easily kill the timer jobs, but can disable all timers and triggers
    for _, t in ipairs (scene.timers or {}) do
      t.enabled = 0
    end
    for _, t in ipairs (scene.triggers or {}) do
      t.enabled = 0
    end
  end

  local function scene_rename (name, room)
    scene.name = name or scene.name
    scene.room = room or scene.room
    luup_scene.description = scene.name     -- luup is SO inconsistent with names!
    luup_scene.room_num = scene.room
  end

  local function user_table ()          -- used by user_data request
    return scene
  end

  -- delete any actions which refer to non-existent devices
  local function verify ()
    for _, g in ipairs (scene.groups or {}) do
      local actions = g.actions or {}
      local n = #actions 
      for i = n,1,-1 do       -- go backwards through list since it may be shortened in the process
        local a = actions[i]
        if not luup.devices[tonumber(a.device)] then
          table.remove (actions,i)
        end
      end
    end
  end

  --create ()
  local scn, err
  if type(scene_json) == "table" then         -- it's not actually JSON
    scn = scene_json                        -- ...assume it's Lua
  else
    scn, err = json.decode (scene_json)     -- or decode the JSON
  end
  if not scn then return nil, err end
  
  lua_code, err = load_lua_code (scn.lua, scn.id or (#luup.scenes + 1))   -- load the Lua
  if err then return nil, err end
  
--[[
  scene should be something like
    {
      id        = 42,
      name      = "title",
      room      = 3,
      groups    = {...},
      triggers  = {...},
      timers    = {...},
      lua       = "....",
    }
--]]

  scene = {
    Timestamp   = scn.Timestamp or os.time(),    -- creation time stamp
    favorite    = scn.favorite or false,
    groups      = scn.groups or {},
    id          = tonumber (scn.id) or (#luup.scenes + 1),  -- given id or next one available
    modeStatus  = scn.modeStatus or "0",          -- comma separated list of enabled modes ("0" = all)
    lua         = scn.lua,
    name        = scn.name,
    room        = tonumber (scn.room) or 0,       -- TODO: ensure room number valid
    timers      = scn.timers or {},
    triggers    = {},                             -- expunge these
  }
  
  verify()   -- check that non-existent devices are not referenced
  
  local methods = {
    rename      = scene_rename,
    run         = scene_runner,
    stop        = scene_stopper,
    user_table  = user_table,
    verify      = verify,
  }
  
  luup_scene = {
      description = scene.name,
      hidden = false,
      page = 0,           -- TODO: discover what page and remote are for
      paused = false,
      remote = 0,
      room_num = scene.room,
    }
   
  -- start the timers
  local recurring = true
  for _, t in ipairs (scene.timers or {}) do
    timers.call_timer (scene_runner, t.type, t.time or t.interval, 
                          t.days_of_week or t.days_of_month, t, recurring)
  end

-- luup.scenes contains all the scenes in the system as a table indexed by the scene number. 
  return setmetatable (luup_scene, {
      __index = methods, 
      __tostring = function () return json.encode (user_table()) or '?' end,
    })
end

---- export variables and methods

return {
    -- constants
    version       = banner,
    environment   = scene_environment,      -- to be shared with startup code
    -- variables
    -- methods
    create        = create,
    verify_all    = verify_all,
  }
