local ABOUT = {
  NAME          = "openLuup.timers",
  VERSION       = "2016.11.13",
  DESCRIPTION   = "all time-related functions (aside from the scheduler itself)",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2016 AK Booer

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

-- openLuup TIMERS modules
-- TIMER related API
-- all time-related functions (aside from the scheduler itself)
-- see: http://aa.usno.navy.mil/faq/docs/SunApprox.php for sun position calculation

-- 2016.04.14  @explorer: Added timezone offset to the rise_set return value 
-- 2016.10.13  add TEST structure with useful hooks for testing
-- 2016.10.21  change DST handling method
-- 2016.11.05  add gmt_offset see thread http://forum.micasaverde.com/index.php/topic,40035.0.html
--             with thanks to @jswim788 and @logread
-- 2016.11.07  added return argument 'due' for scene timers
-- 2016.11.13  refactor day-of-week and day-of-month timers (fixing old bug?)

--
-- The days of the week start on Monday (as in Luup) not Sunday (as in standard Lua.) 
-- The function callbacks are actual functions, not named globals.
-- The data parameter can also be any type, not just string
--
-- NB: earth coordinates (latitude & longitude) are picked up from the global luup variables

local scheduler = require "openLuup.scheduler"
local socket    = require "socket"
-- constants

local loadtime  = os.time()
local time_format           = "(%d%d?)%:(%d%d?)%:(%d%d?)"
local date_format           = "(%d%d%d%d)%-(%d%d?)%-(%d%d?)"
local date_time_format      =  date_format .. "%s+" .. time_format
local relative_time_format  = "([%+%-]?)" .. time_format .. "([rt]?)"

-- utility function, string time to unix epoch
-- time should be in the format: "yyyy-mm-dd hh:mm:ss"
local function time2unix (time)
  local epoch
  local y,m,d,H,M,S = (time or ''): match (date_time_format)
  if S then 
    epoch = os.time {year=y, month=m, day=d, hour=H, min=M, sec=S}
  end
  return epoch
end


-- function: sleep
-- parameters: number of milliseconds
-- returns: none
--
-- Sleeps a certain number of milliseconds
-- NB: doesn't use CPU cycles, but does block the whole process...  not advised!!
local function sleep (milliseconds)
  socket.sleep ((tonumber (milliseconds) or 0)/1000)      -- wait a bit
end

-- returns timezone offset in seconds
local function time_zone()
  local now = os.time()
  return os.difftime(now, os.time(os.date("!*t", now)))
end

-- sunrise, sunset times given date (and lat + long as globals)
-- see: http://aa.usno.navy.mil/faq/docs/SunApprox.php
-- rise and set are nil if the sun does not rise or set on that day.
local function rise_set (date, latitude, longitude)
  
  -- earth coordinates
  latitude  = latitude  or luup.latitude
  longitude = longitude or luup.longitude

  local dr = math.pi / 180
  local function sin(x) return math.sin(x*dr) end
  local function cos(x) return math.cos(x*dr) end

  local function asin(x) return math.asin(x)/dr end
  local function acos(x) return math.acos(x)/dr end
  local function atan2(x,y) return math.atan2(x,y)/dr end 
  
  local t = date or os.time()
  if type (t) ~= "table" then t = os.date ("*t", t) end
  t = os.time {year = t.year, month = t.month, day = t.day, hour = 12, isdst = false}  -- approximate noon
  local J2000 = os.time {year = 2000, month=1, day=1, hour = 12}  -- Julian 2000.0 epoch
  local D = (t - J2000) / (24 * 60 * 60)                  -- days since Julian epoch "J2000.0"

  local g = (357.5291 + 0.98560028 * D) % 360             -- mean anomaly of the sun
  local q = (180 + 280.459 + 0.98564736 * D) % 360 - 180  -- mean longitude of the sun (-180..+180)
  
  local L = q + 1.915 * sin (g) + 0.0200 * sin (2*g)      -- geocentric apparent ecliptic longitude
  local e = 23.439 - 0.00000036 * D                       -- mean obliquity of the ecliptic
  local sin_L = sin(L)
  local RA = atan2 (cos(e) * sin_L, cos(L))               -- right ascension (-180..+180)
  
  local noon = t - 240*(q - RA + longitude)               -- actual noon (seconds)
  
  local sin_d = sin(e) * sin_L                            -- declination (sine of)
  local cos_d = cos(asin(sin_d))
  local sin_p = sin(latitude)
  local cos_p = cos(latitude)

  local rise, set
  local cos_w = (sin(-0.83) - sin_p * sin_d) / (cos_p * cos_d)
  if math.abs(cos_w) <= 1 then
    local hour_angle = acos (cos_w) * 240                 -- hour angle (seconds)
    rise = noon - hour_angle
    set  = noon + hour_angle 
  end
  
  local tz = time_zone()
  return rise + tz, set + tz, noon + tz
end

-- function: sunset / sunrise
-- parameters: none
-- returns: The NEXT sunset / sunrise in a Unix timestamp (i.e. the number of seconds since 1/1/1970 in UTC time). 
-- You can do a diff with os.time to see how long it will be for the next event. 
-- luup.sunset-os.time is the number of seconds before the next sunset. 
-- Be sure the location and timezone are properly set or the sunset/sunrise will be wrong.

local function sunrise_sunset ()
  local day = 24 * 60 * 60
  local now = os.time()
  local today_rise, today_set = rise_set (now)
  local tomorrow_rise, tomorrow_set = rise_set (now + day)
  local rise, set = today_rise, today_set
  if now > rise then rise = tomorrow_rise end
  if now > set  then set  = tomorrow_set  end
  return rise, set
end

local function sunrise ()
  local rise = sunrise_sunset ()
  return rise
end

local function sunset ()
  local _, set = sunrise_sunset ()
  return set
end

-- function: is_night
-- parameters: none
-- returns: true if it's before sunrise or after sunset, false otherwise.
local function is_night ()
  local now = os.time()
  local rise, set = rise_set (now)     -- today's times  
  return now < rise or now > set
end

-- target_time()  given a Unix time representing a date, and a time string 
-- (which may be relative to sunrise/sunset on that day) return the actual Unix time.
-- eg. target_time ({year=t, month=m, day=d}, "-2:30:00r")
local function target_time (date, time)
  local t
  local sign,H,M,S,rt = (time or ''): match (relative_time_format) -- syntax checked previously
  if type (date) == "number" then date = os.date ("*t", date) end
  if rt == '' then                           -- absolute time
    t = os.time {year=date.year, month=date.month, day=date.day, hour=H, min=M, sec=S}
  else                                      -- relative to sunrise/sunset
    local offset = (H * 60 + M) * 60 + S
    local rise,set = rise_set {year=date.year, month=date.month, day=date.day,}
    local event = (rise + set) / 2          -- noon, but should never be this
    if rt == 'r' then event = rise end
    if rt == 't' then event = set  end
    if sign == '-' then offset = -offset end
    t = event + offset
  end
  return t
end

-- given a list of day offsets, and a time specification (possibly relative to sun rise/set)
-- find the NEXT event time that can be scheduled.  This works for day-of-week or day-of-month timers.
-- blocksize depends on the type of timer, being 7 (days) for a DOW timer, or number of days in month for DOM.
local function next_scheduled_time (offset, time, blocksize)
  local day_offset = 24 * 60 * 60
  table.sort (offset)
  local now = os.time ()
  local target_day = offset[1] * day_offset
  local next_time = target_time (now + target_day, time)
  if next_time <= now then     -- too late!, so schedule some future day...
    if #offset > 1 then 
      target_day = offset[2] * day_offset   -- simply move to the next one
    else
      target_day = blocksize * day_offset -- only one day scheduled, so move to next week/month
    end
    next_time = target_time (now + target_day, time)
  end
  return next_time 
end

-- function: call_delay
-- parameters: function_name (string), seconds (number), data (string)
-- returns: result (number)
--
-- The function will be called in seconds seconds (the second parameter), with the data parameter.
-- The function returns 0 if successful. 
local function call_delay (fct, seconds, data)
  scheduler.add_to_delay_list (fct, seconds, data) 
  return 0
end

-- function: call_timer
-- parameters: function to call, type (number), time (string), days (string), data [, recurring]
-- if recurring is true then types 1,2 and 3 reschedule themselves (used by scenes)
-- returns: result (number)
--
-- The function will be called in seconds seconds (the second parameter), with the data parameter.
-- Returns 0 if successful. 
-- NOTE: that in the event of the timer creating a job (rather than a delay) then the
-- returned parameters are: error (number), error_msg (string), job (number), arguments (table)
--
-- Type is 1=Interval timer, 2=Day of week timer, 3=Day of month timer, 4=Absolute timer. 
-- For a day of week timer, Days is a comma separated list with the days of the week where 1=Monday and 7=Sunday. 
-- Time is the time of day in hh:mm:ss format. 
-- Time can also include an 'r' at the end for Sunrise or a 't' for Sunset and the time is relative to sunrise/sunset. 
-- For example: Days="3,5" Time="20:30:00" means your function will be called on the next Wed or Fri at 8:30pm. 
-- Days="1,7" Time="-3:00:00r" means your function will be called on the next Monday or Sunday 3 hours before sunrise. 
-- Day of month works the same way except Days is a comma separated list of days of the month, such as "15,20,30". 
--
local function call_timer (fct, timer_type, time, days, data, recurring)
  local first_time = true
  time = (tostring(time or '')): lower ()
  local target           -- fwd ref to function which calculates target time of next call
  
  -- NB: all timers (except absolute) can be implemented as jobs which timeout and get re-run
  -- scene timers would have to run this way, but simple luup call_timers are one-shot, sadly.
  -- the timeout period is the time difference between now and target time
  -- as returned by the function target() which is local to each timer type.
  local timer = { 
      job = function() 
        local next_time = target()
        if not first_time then
          pcall (fct, data, next_time)    -- make the call, ignore any errors
        end
        first_time = false
        return scheduler.state.WaitingToStart, next_time - socket.gettime()    -- calculate delta time
      end
    }

  -- used to start all timers
  -- returns: error (number), error_msg (string), job (number), arguments (table)
  -- and additional argument 'due', being the first scheduled time (used by scene timers)
  local function start_timer ()
    local due = target ()
    local e,m,j,a
    if recurring then
      e,m,j,a = scheduler.run_job (timer, {}, 0)      -- this starts a recurring job
    else
      e = call_delay (fct, due - socket.gettime(), data)        -- this is one-shot
    end
    return e,m,j,a, math.floor (due)  -- 2016.11.07 scene time only deals with integers
  end
  
  -- (1) interval timer
  -- to avoid time drift, schedule on base time plus multiples of the delay
  -- For an interval timer, days is not used, and 
  -- Time should be a number of seconds, minutes, or hours using an optional 'h' or 'm' suffix. 
  -- Example: 30=call in 30 seconds, 5m=call in 5 minutes, 2h=call in 2 hours. 
  local function interval ()
    local multiplier = {[''] = 1, m = 60, h = 3600}
    local v,u = time: match "(%d+)([hm]?)"
    if u then
      local base = os.time()
      local increment = v * multiplier[u]
      target = function () base = base + increment return base end
      return start_timer () 
    end
  end
  

  -- (2) day of week timer implemented as job
  -- Days is a comma separated list with the days of the week where 1=Monday and 7=Sunday. 
  -- Time is the time of day in hh:mm:ss format. 
  -- Time can also include an 'r' at the end for Sunrise or a 't' for Sunset 
  -- and the time is relative to sunrise/sunset. 
  local function day_of_week ()
    local d = {}
    local _,_,_,S = (time or ''): match (relative_time_format)  -- syntax check
    -- wrap day range 1-7 from Luup Monday-Sunday to Lua Sunday-Saturday
    for x in (days or ''):gmatch "(%d),?" do d[#d+1] = x % 7 + 1 end
    -- valid days and H:M:S time
    if #d > 0 and S then   
      target = function ()
        -- components of current time, including "wday" (day of week)
        local t = os.date "*t"  
        -- table with zero or positive offsets to the target days
        local offset = {}
        for i,n in ipairs (d) do offset[i] = (n - t.wday - 1) % 7 + 1 end
        return next_scheduled_time (offset, time, 7) 
      end
      return start_timer () 
    end
  end
  
  -- (3) day of month timer implemented as job
  -- day_of_month works the same way as day_of_week except that
  -- Days is a comma separated list of days of the month, such as "15,20,30". 
  local function day_of_month ()
    local d = {}
    local _,_,_,S = (time or ''): match (relative_time_format)  -- syntax check
    for x in (days or ''):gmatch "(%d%d?),?" do d[#d+1] = tonumber (x) end 
    -- valid days and H:M:S time
    if #d > 0 and S then 
      target = function ()
        -- components of current time, including "day" (day of month) and "month" (number)
        local t = os.date "*t"  
        local days_in_month = {31, 28 or 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
        if t.year % 4 == 0 then days_in_month[2] = 29 end  -- leap year
        local month_offset = days_in_month[t.month]
        -- table with zero or positive offsets to the target days
        local offset = {}
        for i,day in ipairs (d) do offset[i] = (day - t.day - 1) % month_offset + 1 end
        return next_scheduled_time (offset, time, month_offset) 
      end
      return start_timer () 
    end
  end

  -- (4) absolute timer implemented using delay (one-shot only)
  -- Days is not used, and Time should be in the format: "yyyy-mm-dd hh:mm:ss"
  local function absolute ()
    local epoch = time2unix (time)
    if epoch then
      return call_delay (fct, epoch - socket.gettime(), data)  -- this is one-shot
    end
  end
  
  -- call_timer()
  local run_timer = {interval, day_of_week, day_of_month, absolute}
  local dispatch = run_timer[timer_type or 0] or function () end
  return dispatch ()
end

--
-- CPU clock()
--
-- The system call os.clock() is a 32-bit integer which is incremented every microsecond 
-- and so overflows for long-running programs.  So need to count each wrap-around.
-- The reset value may return to 0 or -22147.483648, depending on the operating system

local  prev    = 0            -- previous cpu usage
local  offset  = 0            -- calculated value
local  click   = 2^31 * 1e-6  -- overflow increment

local function cpu_clock ()
  local this = os.clock ()
  if this < prev then 
    offset = offset + click
    if this < 0 then offset = offset + click end
  end
  prev = this
  return this + offset
end
  
local function timenow ()
  return socket.gettime()
end

-- see: http://lua-users.org/wiki/TimeZone
local function gmt_offset ()
  local now = os.time()
  local localdate = os.date("!*t", now)
  return os.difftime(now, os.time(localdate)) / 3600
end

---- return methods

return {
  ABOUT = ABOUT,
  TEST = {
    next_scheduled_time = next_scheduled_time,
    rise_set            = rise_set,
    target_time         = target_time,
    time2unix           = time2unix,
  },
  
  cpu_clock   = cpu_clock,
  gmt_offset  = gmt_offset,
  sleep       = sleep,
  sunrise     = sunrise,
  sunset      = sunset,
  timenow     = timenow,
  is_night    = is_night,
  call_delay  = call_delay,
  call_timer  = call_timer,
  -- constants
  loadtime    = loadtime,
}

----
