local ABOUT = {
  NAME          = "openLuup.rooms",
  VERSION       = "2016.04.30",
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
local json    = require "openLuup.json"

--  local log
local function _log (msg, name) logs.send (msg, name or ABOUT.NAME) end

logs.banner (ABOUT)   -- for version control

--
-- ROOM
--
--Example: http://ip_address:3480/data_request?id=room&action=create&name=Kitchen
--Example: http://ip_address:3480/data_request?id=room&action=rename&room=5&name=Garage
--Example: http://ip_address:3480/data_request?id=room&action=delete&room=5

--This creates, renames, or deletes a room depending on the action. 
--To rename or delete a room you must pass the room id for the with room=N.
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

local function load (filename)
  local result, message
  local f = io.open (filename, 'r')
  if f then
    local room_json = f: read "*a"
    f: close ()
    local rooms = {}
    rooms, message = json.decode (room_json)
    if type (rooms) == "table" then
      result = {}
      for _,x in ipairs (rooms) do result[x.id or '?'] = x.name end
    end
  else
    message = "unable to open file: " .. (filename or '?')
  end
  return result, message
end

local function save (filename)
  local result, message
  local f = io.open (filename, 'w')
  if f then
    local rooms = {}
    for i, name in pairs (luup.rooms) do 
      rooms[#rooms+1] = {id = i, name = name}
    end
    local room_json = json.encode (rooms)
    f: write (room_json)
    f: close ()
    result = true
  else
    message = "unable to open file: " .. (filename or '?')
  end
  return result, message
end

return {
  ABOUT = ABOUT,
  
  create    = create,
  delete    = delete,
  rename    = rename,
  -- file I/O
  load      = load,
  save      = save,
  
  }