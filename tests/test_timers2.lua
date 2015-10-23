
-- timer test

local target

local jobs = {
  run_action = function () print ("TARGET: ", os.date("%c", target())) end
    
}

local days
local time
local time_format       = "(%d%d?)%:(%d%d?)%:(%d%d?)"
local relative_time_format  = "([%+%-]?)" .. time_format .. "([rt]?)"

local longitude = "-1.4"
local latitude  = "51.75"


-- sunrise, sunset times given date (and lat + long as globals)
-- see: http://aa.usno.navy.mil/faq/docs/SunApprox.php
-- rise and set are nil if the sun does not rise or set on that day.
local function rise_set (date)
  local dr = math.pi / 180
  local function sin(x) return math.sin(x*dr) end
  local function cos(x) return math.cos(x*dr) end

  local function asin(x) return math.asin(x)/dr end
  local function acos(x) return math.acos(x)/dr end
  local function atan2(x,y) return math.atan2(x,y)/dr end 
  
  local t = date or os.time()
  if type (t) == "number" then t = os.date ("*t", t) end
  t = os.time {year = t.year, month = t.month, day = t.day, hour = 12}  -- approximate noon
  local J2000 = os.time {year = 2000, month=1, day=1, hour = 12}  -- Julian 2000.0 epoch
  local D = (t - J2000) / (24 * 60 * 60)                  -- days since Julian epoch "J2000.0"

  local g = (357.5291 + 0.98560028 * D) % 360             -- mean anomaly of the sun
  local q = (180 + 280.459 + 0.98564736 * D) % 360 - 180  -- mean longitude of the sun (-180..+180)
  
  local L = q + 1.915 * sin (g) + 0.0200 * sin (2*g)      -- geocentric apparent ecliptic longitude
  local e = 23.439 - 0.00000036 * D                       -- mean obliquity of the ecliptic
  local sin_L = sin(L)
  local RA = atan2 (cos(e) * sin_L, cos(L))               -- right ascension (-180..+180)
  
  local noon = t - 240*(q - RA + longitude)               -- actual noon (seconds)
--  TODO: check if this fixes DST issue ???
  noon = os.date("*t",noon)
  noon.isdst = false
  noon = os.time(noon)
--
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
  return rise, set, noon, RA, asin(sin_d)
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

 
  -- (2) day of week timer implemented as job
  -- Days is a comma separated list with the days of the week where 1=Monday and 7=Sunday. 
  -- Time is the time of day in hh:mm:ss format. 
  -- Time can also include an 'r' at the end for Sunrise or a 't' for Sunset 
  -- and the time is relative to sunrise/sunset. 
  local function day_of_week ()
    local d = {}
    local day_offset = 24 * 60 * 60
    local _,_,_,S = (time or ''): match (relative_time_format)  -- syntax check
    -- wrap day range 1-7 from Luup Monday-Sunday to Lua Sunday-Saturday
    for x in (days or ''):gmatch "(%d),?" do d[#d+1] = x % 7 + 1 end
    -- valid days and H:M:S time
    if #d > 0 and S then                    
      target = function ()
        local next_time
        -- components of current time, including "wday" (day of week)
        local now = os.time()
        local t = os.date ("*t", now)  
        -- table with zero or positive offsets to the target days
        local offset = {}
        for i,n in ipairs (d) do offset[i] = (n - t.wday - 1) % 7 + 1 end
        table.sort (offset)
        next_time = target_time (now, time)
        if next_time <= now then     -- too late!, so schedule some future day...
          next_time = target_time (now + offset[1] * day_offset, time)
        end
        return next_time 
      end
      return jobs.run_action (timer, {}, 0)
    end
  end
  
  -- (3) day of month timer implemented as job
  -- day_of_month works the same way as day_of_week except that
  -- Days is a comma separated list of days of the month, such as "15,20,30". 
  local function day_of_month ()
    local d = {}
    local day_offset = 24 * 60 * 60
    local _,_,_,S = (time or ''): match (relative_time_format)  -- syntax check
    for x in (days or ''):gmatch "(%d%d?),?" do d[#d+1] = tonumber (x) end 
    -- valid days and H:M:S time
    if #d > 0 and S then 
      target = function ()
        local next_time
        -- components of current time, including "day" (day of month) and "month" (number)
        local now = os.time()
        local t = os.date ("*t", now)  
        local days_in_month = {31, 28 or 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
        if t.year % 4 == 0 then days_in_month[2] = 29 end  -- leap year
        local month_offset = days_in_month[t.month]
        -- table with zero or positive offsets to the target days
        local offset = {}
        for i,day in ipairs (d) do offset[i] = (day - t.day - 1) % month_offset + 1 end
        table.sort (offset)
        next_time = target_time (now, time)
        if next_time <= now then     -- too late!, so schedule some future day...
          next_time = target_time (now + offset[1] * day_offset, time)
        end
        return next_time 
      end
      return jobs.run_action (timer, {}, 0)
    end
  end

days = "1,3,5"
time = "18:25:00"
print (" ----- day of week: " .. days)
day_of_week ()


days = "14,28"
time = "20:25:00"
print (" ----- day of month: " .. days)
day_of_month ()


days = "4,14,28"
time = "-1:30:00t"
print (" ----- day of month: " .. days)
day_of_month ()

print (os.date "%c")

local a,b,c,d = rise_set ()
print ("rise", os.date("%c",a))
print ("set",  os.date("%c",b))
print ("noon", os.date("%c",c))
print ("RA, Decl",d,e)

