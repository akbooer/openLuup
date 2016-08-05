local ABOUT = {
  NAME          = "openLuup.rooms",
  VERSION       = "2016.06.23",
  DESCRIPTION   = "room-related calls ",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
}

--
-- openLuup.rooms: the place for room-related calls 
-- which, IMHO, are missing from basic luup.xxx functionality
--

local logs    = require "openLuup.logs"

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control

--
-- ROOM
--


local function create (name, force_number) 
  local number
  if force_number then
    number = force_number
  else                -- check that room name does not already exist
    local index = {}
    for i,room_name in pairs (luup.rooms) do index[room_name] = i end
    number = index[name]
    if not number then
      number = (#luup.rooms + 1)      -- next empty slot
      _log (("creating [%d] %s"): format (number, name or '?'))
    end
  end
  luup.rooms[number] = name
  return number
  end

local function rename (number, name) 
    if number and luup.rooms[number] then
      luup.rooms[number] = name or '?'
    end
  end

local function delete (number) 
    if number and luup.rooms[number] then 
      luup.rooms[number] = nil
       _log (("deleting [%d]"): format (number))
     -- check devices for reference to deleted room no.
      for _, d in pairs (luup.devices) do
        if d.room_num == number then d.room_num = 0 end
      end
      -- check scenes for reference to deleted room no.
      for _, s in pairs (luup.scenes) do
        if s.room == number then s.rename (nil, 0) end
      end
    end
  end


return {
  ABOUT = ABOUT,
  
  create    = create,
  delete    = delete,
  rename    = rename,
  
  }