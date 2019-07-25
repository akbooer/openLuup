-- test Whisper database

local whisper = require "L_DataWhisper"

whisper.debugOn = true
whisper.CACHE_HEADERS = true

VERIFY = true
-- utilities


local function array_equality (a,b)
  if #a ~= #b then return end
  for i = 1,#a do
    if a[i] ~= b[i] then return end
  end
  return true
  end

if not print then print = function (...) AKB.log (table.concat ({...}, ' ')) end; end

-- tests

local function test_2 ()    -- one element store!
  local name = "test-2"
  print (name)
  local db = (name..".wsp")
  os.remove (db)
  print "create:"
  whisper.create (db, {{1,1}}, 0, "last") -- check binary retentions syntax
  print ('',whisper.info (db))
  local input = {42} 
  print "write"
  local start = 1e9 
  local T = start
    whisper.update (db, input[1], T, T)
  
  print "read"
  local tv = whisper.fetch (db, 0, nil, T)
  for i, v,t in tv:ipairs ()  do
    print (i, t,v)
  end
  if VERIFY then assert (array_equality (tv.values,input), name .. ": input ~= output") end

  print ''
end

local function test_1 ()
  local name = "test-1"
  print (name)
  local db = (name..".wsp")
  local retentions = "1:2"
  os.remove (db)
  print "create"
  whisper.create (db, {{1,2}}, 0, "last") -- check binary retentions too
  print ('',whisper.info (db))
 
  local input = {1,2} 
  print "write"
  local start = 1e9 
  local T
  for i = 1,#input do
    T = start + i - 1
    whisper.update (db, input[i], T, T)
  end
  
  print "read"
  local tv = whisper.fetch (db, 0, nil, T)
  for i, v,t in tv:ipairs ()  do
    print (i, t,v)
  end
  if VERIFY then assert (array_equality (tv.values,input), name .. ": input ~= output") end

  print ''
end


local function test0 ()   -- single archive
  local name = "test0"
  print (name)
  local db = (name..".wsp")
  local retentions = "1s:5"
  os.remove (db)
  print "create"
  whisper.create (db, retentions, 0, "last")
  print ('',whisper.info (db))
 
  local input = {1,2,3,4,5} 
  print "write"
  local start = 1e9 +3
  local T
  for i = 1,#input do
    T = start + i - 1
    whisper.update (db, input[i], T, T)
  end
  
  print "read"
  local tv = whisper.fetch (db, 0, nil, T)
  for i, v,t in tv:ipairs ()  do
    print (i, t,v)
  end
  if VERIFY then assert (array_equality (tv.values,input), name .. ": input ~= output") end
  
  print "exra point"
  T = T + 1
  whisper.update (db, 6, T,T)
  tv = whisper.fetch (db, 0, nil, T)
  for i, v,t in tv:ipairs ()  do
    print (i, t,v)
  end
  if VERIFY then assert (array_equality (tv.values,{2,3,4,5,6}), name ..": input ~= output") end
  print ''
end


local function test1 ()   -- multiple archives
  local name = "test1"
  print (name)
  local db = (name..".wsp")
  local retentions = "1:2,2:3,4:3"
  os.remove (db)
  print "create"
  whisper.create (db, retentions, 0, "sum")
  print ('',whisper.info (db))
 
  local input = {1,2,3, 4, 5,6} 
--  local input = {1,nil,3,nil,5} 
  local verify = {2, 4, 6}

  print "write"
  local start = 1e9
  local t = start
-- single point - written OK to multiple archives ??

    whisper.update (db, 42, t, t)
    local a = whisper.fetch (db, t,t,t) -- get current point
    assert (a.values[1] == 42, "current archive incorrect")
    local b = whisper.fetch (db, t-3,t,t) -- get current point
    for n, v,t in b:ipairs() do
      print (n, t,v)
    end
--    assert (b.values[1] == 42, "previous archive incorrect")
    
--

  for i = 1,#input do
    t = start + i - 1
    whisper.update (db, input[i], t, t)
  end
  
  print "read"
  local tv = whisper.fetch (db, 0, nil, t)
  for i, v,t in tv:ipairs ()  do
    print (i, t,v)
  end
--  if VERIFY then assert (array_equality (tv.values,verify), name .. ": input ~= output") end
  print ''
end


local function test2 ()
  print "test2"
  local db = "test2.wsp"
  local retentions = "1:2, 2:3, 6:10"

  os.remove (db)
  print "create"
  whisper.create (db, retentions, 0, "sum")
 
  local info = whisper.info (db)
  print ('info:', info)
  print ("archives: ", tostring(info.retentions))
  print "write"
  local start = 1e9 
  local t
  for i = 1,30 do
    t = start + i - 1
    whisper.update (db, 1, t, t)
  end
  
  print "read first archive"
  local verify = {1,1}
  local tv = whisper.fetch (db, t-1,t, t)
  for i, v,t in tv:ipairs ()  do
    print (i, t,v)
  end
  if VERIFY then assert (array_equality (tv.values,verify), "test 2, archive 1: input ~= output") end

  print "read last archive"
  local verify = {6,6,6,6,6,6,6,6,6,6}
  local tv = whisper.fetch (db, 0, nil, t)
  for i, v,t in tv:ipairs ()  do
    print (i, t,v)
  end
--  if VERIFY then assert (tv.values[2] == verify[2], "test 2, archive 2: input ~= output") end
  print ''
end


local function test3 ()   -- write performance
  print "test3"
  local db = "test3.wsp"
  local retentions = "10m:7d,1h:30d,3h:1y,1d:10y"
  local retentions = "1:1h"
--  local retentions = "1s:1m,1m:1d,5m:7d,1h:90d,6h:1y,1d:5y"
  os.remove (db)
  print "create"
  print ("retentions: "..retentions)
  whisper.create (db, retentions, 0, "sum")
  print (whisper.info (db))
  print "write"
  local t1 = os.time()
  local c1 = os.clock()
  local start = 1e9 
  local t
  local N = 60*60
  for i = 1,N do
    t = start + i - 1
    whisper.update (db, i, t, t)
  end
  local t2 = os.time()
  local c2 = os.clock()
  local cpu_time = math.floor((c2-c1)*1e3)
  print ("elapsed time = ".. (t2-t1)..' S')
  print ("cpu time =     ".. cpu_time..' mS')
  print ("time / point = ".. math.floor (1e3*cpu_time/N) .. ' µS')
  print ''
end



-- TESTS

print "starting tests..."
test_2()
test_1()
test0()
test1()
test2()

whisper.debugOn = false

test3()

--local battery = "1d:1y"
--local power   = "20m:30d,3h:1y,1d:10y"
--local THLG    = "10m:7d,1h:30d,3h:1y,1d:10y"
--local SECU    = "1s:1m,1m:1d,5m:7d,1h:90d,6h:1y"

print 'done'

x =    "1200:2160, 10800:2920, 86400:3650, 1:1000000"
--print ( whisper.archiveSpec (x))

