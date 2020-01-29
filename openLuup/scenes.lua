local ABOUT = {
  NAME          = "openLuup.scenes",
  VERSION       = "2020.01.28",
  DESCRIPTION   = "openLuup SCENES",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2020 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2013-2020 AK Booer

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

-- openLuup SCENES module

--
-- all scene-related functions 
-- see: http://wiki.micasaverde.com/index.php/Scene_Syntax for stored scene syntax
--
-- 2016.03.11   verify that scenes don't reference non-existent devices.  Thanks @delle
-- 2016.04.10   add 'running' flag for status and sdata "active" and "status" info.   Thanks @ronluna
-- 2016.04.20   make pause work
-- 2016.05.19   allow trigger data to be stored (for PLEG / RTS)
--              see: http://forum.micasaverde.com/index.php/topic,34476.msg282148.html#msg282148
-- 2016.10.29   add notes to timer jobs (changed to job.type)
-- 2016.11.01   add new_userdata_dataversion() to successful scene execution
-- 2016.11.18   add scene finisher type to final delay.

-- 2017.01.05   add lul_scene to the scope of the scene Lua (to contain the scene Id)
-- 2017.01.15   remove scene triggers which refer to missing devices (thanks @reneboer)
--              see: http://forum.micasaverde.com/index.php/topic,41249.msg306385.html#msg306385
-- 2017.07.19   allow missing Lua field for scenes
--              force userdata update after scene creation
-- 2017.07.20   add lul_timer and lul_trigger to scene Lua
--              these parameters are tables conforming to the scene syntax
--              see: http://wiki.micasaverde.com/index.php/Scene_Syntax
-- 2017.08.08   add warning message to scenes with triggers

-- 2018.01.17   add optional 2-nd return parameter 'user_finalizer' function to scene Lua (thanks @DesT)
-- 2018.01.18   add optional 3-rd return parameter 'final_delay' and also scene.prolog and epilog calls
-- 2018.01.30   cancel timer jobs on scene delete, round next scene run time, etc..
-- 2018.02.19   add log messages for scene cancellation by global and local Lua code
-- 2018.04.16   remove scene watcher callback, now redundant with scene finalizers
-- 2018.05.16   correct next run time (thanks to @rafale77 for diagnosis and suggestions)

-- 2019.04.18   syntax change to job name
-- 2019.05.10   only create scene timers job if scene not paused!
-- 2019.05.15   reinstate scene_watcher to use device states to indicate scene active
-- 2019.05.23   re-enable triggers in anticipation of "variable updated" events
-- 2019.06.10   add new openLuup structure (preserved over AltUI edits)
-- 2019.06.17   add scene history
-- 2019.07.26   add runner info to scene history
-- 2019.08.04   add scene on_off() to toggle paused
-- 2019.11.24   remove scene_watcher code (a poor implementation of the concept)

-- 2020.01.27   start implementing object-oriented scene changes
-- 2020.01.28   move openLuup structure to scene metatable


local logs      = require "openLuup.logs"
local json      = require "openLuup.json"
local timers    = require "openLuup.timers"
local loader    = require "openLuup.loader"       -- for shared_environment and compile_lua()
local scheduler = require "openLuup.scheduler"    -- simply for adding notes to the timer jobs 
local devutil   = require "openLuup.devices"      -- for new_userdata_dataversion

--  local _log() and _debug(), plus AltUI special
local _log, _debug = logs.register (ABOUT)
local _log_altui_scene  = logs.altui_scene

--[[

Whilst 'actions' and 'timers' are straight-forward, the 'trigger' functionality of Luup is severely flawed, IMHO, through the close connection to UPnP service files and .json files.  

The goal would be to have an interface like HomeSeer, with extremely intuitive syntax to define triggers and conditions.  To support this at the openLuup engine level, all trigger conditions are handled through a standard initial luup.variable_watch call - so no new infrastructure is needed - to a handler which then evaulates the condition and, if true, continues to evaluate further states required for the scene to run.

Sept 2015 - ALTUI now provides this functionality through its own variable watch callback 
which then triggers scenes if some Lua boolean expression is true
ALTUI also provides a great editor interface with the blockly module.

Apr 2016 - AltUI now provides workflow too.

--]]

local HISTORY_LENGTH = 20   -- number of points in scene history cache

-- scene-wide variables
--local watched_devices = {}      -- table of watched devices indexed by device number 

---
--- utilities
--

-- single environment for all scenes and startup code
local scene_environment = loader.shared_environment

local function jsonify (x) return (json.encode (x.definition)) or '?' end -- return JSON scene representation

local function load_lua_code (lua, id)
  local scene_lua, error_msg, code
  if lua then
    local scene_name = "scene_" .. id
    local wrapper = table.concat ({"function ", scene_name, " (lul_scene, lul_trigger, lul_timer)", lua, "end"}, '\n')  -- 2017.01.05, 2017.07.20
    local name = "scene_" .. id .. "_lua"
    code, error_msg = loader.compile_lua (wrapper, name, scene_environment) -- load, compile, instantiate
    scene_lua = (code or {}) [scene_name]
  end
  return scene_lua, error_msg
end

local function verify_all()
  for _,s in pairs(luup.scenes) do
    s: verify()
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

--[[
-- called when watched device variable changes
local function scene_watcher (devNo, service, variable, value_old, value_new)
  local device = luup.devices[devNo]
  if device then
--    _log ("device #" .. devNo, "luup.scenes.watch")
  local _,_,_,_ = service, variable, value_old, value_new   -- unused at present
    -- for each affected scene
    -- get expected state
    -- compare with current state
    -- set running flag as necessary
  end
end

-- start_watching_devices(),  possibly add new devices to watched list
local function start_watching_devices(dlist)
  for devNo in pairs(dlist) do
    if not watched_devices[devNo] then    -- need to start watching this device
      watched_devices[devNo] = devNo
      -- start device watch
      local silent = true
      local device = luup.devices[devNo]
      if device then 
        devutil.variable_watch (device, scene_watcher, nil, nil, "scene_watcher", silent) 
      end
    end
  end
end

-- called when trigger device variable changes
local function trigger_watcher (devNo, service, variable, value_old, value_new)
  local _,_,_,_,_ = devNo, service, variable, value_old, value_new   --TODO: trigger_watcher
end

-- start_watching_triggers(),  possibly add new triggers to watched list
local function start_watching_triggers(dlist)
  local _ = dlist   --TODO: start_watching_triggers
end

-- get_actioned_devices()  returns a table of devices used by a scene
local function get_actioned_devices(self)      -- 2019.05.15
  local devs = {}
  for _, group in ipairs (self.groups) do
    for _, a in ipairs (group.actions) do
      local devNo = tonumber (a.device)
      if devNo then devs[devNo] = devNo end     -- use table, rather than list, to avoid duplicates
    end
  end
  return devs
end


--]]


-- rename scene
local function scene_rename (self, name, room)  -- 2020.01.27
  devutil.new_userdata_dataversion ()
  name = tostring (name or self.description)
  room = tonumber (room or self.room_num)
  local scene = self.definition
  -- change the scene definition
  scene.name = name
  scene.room = room
  -- change the visible structure... luup is SO inconsistent with names
  self.description = name
  self.room_num = room
end

-- toggle scene pause
local function scene_on_off (self)
  devutil.new_userdata_dataversion ()
  local scene = self.definition
  if self.paused then
    scene.paused = "0"
    self.paused = false
  else
    scene.paused = "1"
    self.paused = true
  end
end

-- delete any actions which refer to non-existent devices
-- also, remove any triggers related to unknown devices
local function scene_verify (self)
  local scene = self.definition
  for _, g in ipairs (scene.groups or {}) do
    local actions = g.actions or {}
    local n = #actions 
    for i = n,1,-1 do       -- go backwards through list since it may be shortened in the process
      local a = actions[i]
      local dev = luup.devices[tonumber(a.device)]
      if not dev then
        table.remove (actions,i)
      end
    end      
  end
  -- triggers
  local triggers = scene.triggers or {}
  local n = #triggers
  for i = n,1,-1 do       -- go backwards through list since it may be shortened in the process
    local t = triggers[i]
    if t.device ~= 2 then
      t.enabled = 0         -- 2019.06.10  disable all triggers... except for openLuup watches
    end
--      if t.device == 2 or not luup.devices[t.device] then
    if not luup.devices[t.device] then
      table.remove (triggers, i)
    end
  end
end

-- stop scene (prior to deleting)
local function scene_stopper (self)
  local scene = self.definition
  self.paused = true                        -- 2018.01.30 pause the whole scene
  for _, j in ipairs ((self or {}).jobs) do scheduler.kill_job (j) end  -- 2018.01.30 cancel timers on scene
  for _, t in ipairs (scene.timers or {})   do t.enabled = 0 end        -- disable all timers...
  for _, t in ipairs (scene.triggers or {}) do t.enabled = 0 end        -- ...and triggers
end

-- run scene  
-- t is the description table of the timer or trigger initiating the run (or nil for manual call)
-- next_time is the next scheduler timer run (in the case of timers)
local function scene_runner (self, t, next_time, params)              -- called by timer, trigger, or manual run
  local prolog, epilog, user_finalizer, final_delay
  local scene = self.definition
  _debug ("scene_runner: " .. self.description)
  local actor = (params or {}) .actor or "command"
  
  local lul_trigger, lul_timer
  if t and next_time then           -- 2018.05.16  update the next scheduled time...
    t.next_run = next_time          -- ...regardless of whether or not it runs this time (thanks @rafale77)
    devutil.new_userdata_dataversion ()         -- increment version, so that display updates
  end
  if not runs_in_current_mode (scene) then 
    _log (scene.name .. " does not run in current House Mode")
    return 
  end
  if self.paused then 
    _log (scene.name .. " is currently paused")
    return 
  end
  if t then     -- we were started by a trigger or timer
    if tonumber (t.enabled) ~= 1  then 
      _log "timer disabled"
      return 
    end
    if t.device then    -- 2017.07.20 (only triggers have a device field)
      lul_trigger = t
    else
      lul_timer = t
    end
  end
  
  do      -- 2018.01.18   scene prolog and epilog calls
    local s = luup.attr_get "openLuup.Scenes" or {}
    prolog = scene_environment[s.Prolog]     -- find the global procedure reference in the scene/startup environment
    epilog = scene_environment[s.Epilog]
  end
  
  local global_ok
  if type (prolog) == "function" then 
    global_ok = prolog (scene.id, lul_trigger, lul_timer)
    if global_ok == false then
      _log (scene.name .. " prevented from running by global scene prolog Lua")
      return    -- GLOBAL cancel
    end
  end
  
  local ok, del
  if self.compiled then
    ok, user_finalizer, del = self.compiled (scene.id, lul_trigger, lul_timer)    -- 2017.01.05, 2017.07.20, 2018.01.17
    if ok == false then
      _log (scene.name .. " prevented from running by local scene Lua")
      return    -- LOCAL cancel
    end
  end
  
  final_delay = tonumber(del) or 30
  scene.last_run = os.time()                -- scene run time

  self.running = true                       -- TODO: fix the fact that this is created in the visible scene?
  devutil.new_userdata_dataversion ()               -- 2016.11.01
--  local runner = "command"
  if t then
    t.last_run = scene.last_run             -- timer or trigger specific run time
--    local t_or_t = lul_timer and "timer: " or "trigger: "
--    runner = t_or_t .. ((t.name ~= '' and t.name) or '?')
  end
  
  do -- 2019.06.17 scene history
    local so = self.openLuup
    local i = so.hipoint % HISTORY_LENGTH + 1
    so.history[i] = {at = scene.last_run, by = actor}  -- 2019.07.26  add runner info to history
    so.hipoint = i
  end --
  
--  local msg = ("scene %d, %s, initiated by %s"): format (scene.id, scene.name, runner)
  local msg = ("scene %d, %s, initiated by %s"): format (scene.id, scene.name, actor)
  _log (msg, "luup.scenes")
  _log_altui_scene (scene)                  -- log for altUI to see
  
  local max_delay = 0
  local label = "scene#" .. scene.id
  for _, group in ipairs (scene.groups) do  -- schedule the various delay groups
    local delay = tonumber (group.delay) or 0
    if delay > max_delay then max_delay = delay end
    timers.call_delay (group_runner, delay, group.actions, label .. "group delay")
  end
  
  -- finish up
  local function scene_finisher (started)                               -- called at end of scene
    if scene.last_run == started then 
      if type(user_finalizer) == "function" then user_finalizer() end   -- call the user-defined finalizer code
      self.running = false                                        -- clear running flag only if we set it
    end
    if type (epilog) == "function" then epilog (scene.id) end
  end
  
  timers.call_delay (scene_finisher, max_delay + final_delay, scene.last_run, 
    label .. " finisher")    -- say we're finished
end

-- delete a scene
local function delete (scene_no)              -- 2020.01.27
  local scene = luup.scenes[scene_no]
  if scene then 
    scene: stop()
    luup.scenes[scene_no] = nil
    devutil.new_userdata_dataversion ()       -- say something has changed
  end
end

--
-- scene.create() - returns compiled scene object given json string containing group / timers / lua / ...
--
local function create (scene_json)
  local scene, err
  if type(scene_json) == "table" then         -- it's not actually JSON
    scene = scene_json                        -- ...assume it's Lua
  else
    scene, err = json.decode (scene_json)     -- or decode the JSON
  end
  if not scene then return nil, err end
  
  local lua_code
  lua_code, err = load_lua_code (scene.lua or '', scene.id or (#luup.scenes + 1))   -- load the Lua
  if err then return nil, err end

  -- ensure VALID values for some essential variables...
    
  scene.Timestamp   = scene.Timestamp or os.time()   -- creation time stamp
  scene.favorite    = scene.favorite or false
  scene.groups      = scene.groups or {}
  scene.id          = tonumber (scene.id) or (#luup.scenes + 1)     -- given id or next one available
  scene.modeStatus  = scene.modeStatus or "0"                       -- comma separated list of enabled modes ("0" = all)
  scene.paused      = scene.paused or "0"
  scene.room        = luup.rooms[scene.room] and scene.room or 0    -- ensure room number valid
  scene.timers      = scene.timers or {}
  scene.triggers    = scene.triggers or {}
  scene.lua         = scene.lua or ''
  
  scene.triggers_operator = "OR"              -- 2019.05.24  no such thing as AND for events in openLuup
  
  -- ensure INVALID entries are removed
  scene.openLuup = nil    -- this structure now moved to metatable
  
  local luup_scene = {    -- this is the visible structure which appears in luup.scenes
      description = scene.name,
      hidden = false,
      page = 0,           -- TODO: discover what page and remote are for
      paused = tonumber (scene.paused) == 1,     -- 2016.04.30 
      remote = 0,
      room_num = scene.room,
    }
  
  local meta = {
    -- variables
    definition  = scene,    -- the decoded JSON structure which defines the scene
    compiled    = lua_code, -- the compiled Lua code for the scene
    running     = false,    -- set to true when run and reset 30 seconds [default] after last action
    jobs        = {},       -- list of jobs that scene is running (ie. timers)
    
    openLuup    = {         -- 2019.06.10 new private structure [2020.01.28 moved to metatable]
      history = {},         -- cache
      hipoint = 0,          -- cache pointer
    },
    
    -- methods
    rename      = scene_rename,
    run         = scene_runner,
    stop        = scene_stopper,
    on_off      = scene_on_off,       -- toggle pause
    verify      = scene_verify,
  }

  setmetatable (luup_scene, {__index = meta, __tostring = jsonify})
  
  luup_scene: verify()   -- check that non-existent devices are not referenced
  
  -- start the timers
  local function timer_run (timer, next_time) 
    luup_scene: run (timer, next_time, {actor= "timer: " .. (timer.name or '?')}) 
  end
  if not luup_scene.paused then      -- 2019.05.10
    local recurring = true
    local jobs = meta.jobs
    local info = "timer: '%s' for scene [%d] %s"
    for _, t in ipairs (scene.timers or {}) do
      local _,_,j,_,due = timers.call_timer (timer_run, t.type, t.time or t.interval, 
                            t.days_of_week or t.days_of_month, t, recurring)
      if j and scheduler.job_list[j] then
        local job = scheduler.job_list[j]
        local text = info: format (t.name or '?', scene.id or 0, scene.name or '?') -- 2016.10.29
        job.type = text
        t.next_run = math.floor (due)   -- 2018.01.30 scene time only deals with integers
        jobs[#jobs+1] = j               -- save the jobs we're running
      end
    end
  end
  
  devutil.new_userdata_dataversion ()               -- 2017.07.19
  
  return luup_scene
end


---- export variables and methods

return {
    ABOUT = ABOUT,
    
    -- constants
    environment   = scene_environment,      -- to be shared with startup code
    -- variables
    -- methods
    create        = create,
    delete        = delete,
    verify_all    = verify_all,
  }
