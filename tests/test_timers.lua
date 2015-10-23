local t = require "luaunit"

-- openLuup TIMER tests

--
--
local timers = require "openLuup.timers"

luup = luup or {}
luup.latitude = 51.75
luup.longitude = -1.4

TestTimers = {}     -- timer tests

function TestTimers:setUp ()
end

function TestTimers:tearDown ()
end

-- basics

function TestTimers:test_methods_present ()
  t.assertIsFunction (timers.sleep)
  t.assertIsFunction (timers.sunrise)
  t.assertIsFunction (timers.sunset)
  t.assertIsFunction (timers.is_night)
  t.assertIsFunction (timers.call_delay)
  t.assertIsFunction (timers.call_timer)
end

-- individual functions

function TestTimers:test_sleep ()
  timers.sleep (2000)                   -- two seconds delay
end

function TestTimers:test_sunrise ()
  local s = timers.sunrise ()
  local now = os.time()
  t.assertTrue (s > now)                -- later than now...
  t.assertTrue (s < now + 24*60*60)     -- ...but earlier than this time tomorrow
end

function TestTimers:test_sunset ()
  local s = timers.sunset ()
  local now = os.time()
  t.assertTrue (s > now)                -- later than now...
  t.assertTrue (s < now + 24*60*60)     -- ...but earlier than this time tomorrow
end

function TestTimers:test_night()
  t.assertIsBoolean (timers.is_night())
end

function TestTimers:test_delay()
  local function fct () end
  timers.call_delay (fct, 42, {"some data", test = 123})
end

function TestTimers:test_invalid_timer()
  -- Type is 1=Interval timer, 2=Day of week timer, 3=Day of month timer, 4=Absolute timer. 
  -- call_timer (fct, type, time, days, data)
  local ok
  local function fct () end
  ok = timers.call_timer (fct, 42, "5m", nil, "some string data")  
  t.assertNotEquals (ok, 0)
end


function TestTimers:test_interval_timer()
  -- Type is 1=Interval timer. 
  -- For an interval timer, days is not used, and 
  -- Time should be a number of seconds, minutes, or hours using an optional 'h' or 'm' suffix. 
  local ok
  local function fct () end
  ok = timers.call_timer (fct, 1, "5m", nil, "some string data")    -- shouldn't fail
  t.assertEquals (ok, 0)
end


function TestTimers:test_day_of_week_timer()
  -- Type 2=Day of week timer. 
  -- Days is a comma separated list with the days of the week where 1=Monday and 7=Sunday. 
  -- Time is the time of day in hh:mm:ss format. 
  -- Time can also include an 'r' at the end for Sunrise or a 't' for Sunset 
  -- and the time is relative to sunrise/sunset. 
  local ok
  local function fct () end
  ok = timers.call_timer (fct, 2, "12:00:00", "1,3,5", {"some data"})    -- shouldn't fail
  t.assertEquals (ok, 0)
end

function TestTimers:test_day_of_month_timer()
  -- Type 3=Day of month timer.
  -- Day of month works the same way except 
  -- Days is a comma separated list of days of the month, such as "15,20,30". 
  local ok
  local function fct () end
  ok = timers.call_timer (fct, 3, "13:14:15", "14,28", "some string data")    -- shouldn't fail
  t.assertEquals (ok, 0)
end

function TestTimers:test_absolute_timer()
  -- Type 4=Absolute timer. 
  -- absolute timer implemented using delay (one-shot only)
  -- Days is not used, and Time should be in the format: "yyyy-mm-dd hh:mm:ss"
  local ok
  local function fct () end
  ok = timers.call_timer (fct, 4, "2015-08-18 06:00:00", nil, "some string data")    -- shouldn't fail
  t.assertEquals (ok, 0)
end


function TestTimers:test_sun_relative()
  -- Type 4=Absolute timer. 
  -- absolute timer implemented using delay (one-shot only)
  -- Days is not used, and Time should be in the format: "yyyy-mm-dd hh:mm:ss"
  local ok
  local function fct () end
  ok = timers.call_timer (fct, 3, "-01:30:00r", "14,28", "some string data")    -- shouldn't fail
  t.assertEquals (ok, 0)
end



--------------------

if not multifile then t.LuaUnit.run "-v" end

--------------------
