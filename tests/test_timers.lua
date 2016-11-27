local t = require "tests.luaunit"

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

TestTimersOther = {}


-- see: http://forum.micasaverde.com/index.php/topic,38818.0.html
-- the error is:
--   "We are monday 09:00, and the scheduled is for tuesday 10:00.
--    As 10:00 > 09:00, it won't add the offset, and schedule will be on monday 10:00."
function TestTimersOther:test_vosmont_DoW ()
  -- Type 2=Day of week timer. 
  -- Days is a comma separated list with the days of the week where 1=Monday and 7=Sunday. 
  -- Time is the time of day in hh:mm:ss format. 
  do return end -- TODO: fix this - it may fail incorrectly!
  -- **********************
  local ok, due
  local function fct () end
  local function dt(t) return os.date ("%c", t) end

  local now = os.time ()
  local hence = now + 25 * 60 * 60    -- one hour and one day later   
  local thence = os.date ("%H:%M:%S", hence)
  ok,_,_,_,due = timers.call_timer (fct, 2, thence, "2,3,4,5,6,7", {"DoW @vosmont: " .. thence})    -- shouldn't fail
  t.assertEquals (ok, 0)
  local expected = now + 25 * 60 * 60
  t.assertIsNumber (due)
  t.assertEquals (dt(due), dt(expected))    -- check the right time
end

TestRiseSet = {}


function TestRiseSet:test_sunrise ()
  local s = timers.sunrise ()
  local now = os.time()
  t.assertTrue (s > now)                -- later than now...
  t.assertTrue (s < now + 24*60*60)     -- ...but earlier than this time tomorrow
end

function TestRiseSet:test_sunset ()
  local s = timers.sunset ()
  local now = os.time()
  t.assertTrue (s > now)                -- later than now...
  t.assertTrue (s < now + 24*60*60)     -- ...but earlier than this time tomorrow
end

local function datetime (...)
  local x = {"-----"}
  for _,t in ipairs {...} do
    x[#x+1] = os.date ("%c", t)
  end
  return table.concat (x, "\n   ")
end

function TestRiseSet:test_rise_set ()
  -- London, Greenwich
  local latitude = 51.5
  local longitude = 0
  local date, sunrise
  print "\n----------"
  local rs = timers.TEST.rise_set
  
  date = {
    {year = 1980, month = 1,  day = 1},
    {year = 2000, month = 6,  day = 11},
    {year = 2016, month = 10, day = 21},
  }
  
  sunrise = {   -- all in UTC
    {year = 1980, month = 1,  day = 1,  hour = 8, min = 6,  isdst = false},
    {year = 2000, month = 6,  day = 11, hour = 3, min = 43, isdst = false},
    {year = 2016, month = 10, day = 21, hour = 6, min = 35, isdst = false},
  }
  
  for i,d in ipairs (date) do
    local r,s,n = rs(d, latitude, longitude)
    print (os.difftime (r, os.time(sunrise[i])))
    print (datetime(r,s,n))
  end

  print "----------"
 
  -- San Francisco
  latitude = 37 + 46/60
  longitude = - (122 + 26/60)
  
  sunrise = {   -- all in UTC
    {year = 1980, month = 1,  day = 1,  hour = 8 + 7, min = 25, isdst = false},
    {year = 2000, month = 6,  day = 11, hour = 3 + 9, min = 47, isdst = false},
    {year = 2016, month = 10, day = 21, hour = 6 + 8, min = 25, isdst = false}, --?????
  }
  
  for i,d in ipairs (date) do
    local r,s,n = rs(d, latitude, longitude)
    print (os.difftime (r, os.time(sunrise[i])))
    print (datetime(r,s,n))
  end


end

--------------------

if not multifile then t.LuaUnit.run "-v" end

--------------------
