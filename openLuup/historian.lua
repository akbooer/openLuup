local ABOUT = {
  NAME          = "openLuup.historian",
  VERSION       = "2018.05.03",
  DESCRIPTION   = "openLuup data historian",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2018 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  
  ---openLuup.historian---
  
  Copyright 2013-2018 AK Booer
  
  ---DataWhisper---
  
  This is a derivative work from the original sourcecode written in the Python language described below,
  although now extensively refactored to add a more object-oriented approach and Lua specifics.
  
  Copyright 2013-2018 AK Booer

  ---Whisper---

  Copyright 2009-Present The Graphite Development Team
  Copyright 2008 Orbitz WorldWide

  ---
  
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

--[[

Data Historian contains several modules to manipulate and plot the in-memory variable history chache
and the on-disc archive.  Industry-standard formats and APIs are used widely, and the implementation
builds on previous plugins and CGIs, most notably, DataYours (an implementation of Graphite and Whisper.) 

 - Whisper      the database
 - CarbonCache  the Whisper writer
 - GraphiteAPI  the HTTP Rest API
 
--]]


------------------------------------------------------------------------
--
-- DataWhisper, an implementation of the Whisper database API
-- 

local  CACHE_HEADERS           = true;     -- improves file access performance for read and write
--  create                  = method;   -- create a new file
--  fetch                   = method;   -- read data
--  info                    = method;   -- get file info (archive structure, etc.)
--  aggregationTypeToMethod = method;   -- 
--  aggregationMethodToType = method;   -- 
--  setAggregationMethod    = method;   -- change data aggregation method for archives in a file
--  update                  = method;   -- write a datapoint
  -- info
  _VERSION = "2014.07.31  Lua translation and refactoring  @akbooer";


-- Note that the internal round-robin indexing is done differently from the 'standard' Whisper implementation
-- because it obviates the need for reading the 'BaseInterval' from the first point in the file 
-- (so doubling the write speed.)

---
--  struct.lua - simple stub for struct methods
--  
--  only implementing a very small subset to support Whisper files.
--  uses comma separated format, not binary packing for readability
--  size impact is 3 times that of a binary pack

local struct = {version = '2014.02.13  @akbooer'}

do -- struct
  -- format: see http://docs.python.org/2/library/struct.html
  local formatCache = {}    -- fast lookup of previously requested formats
  local LuaFormat = {
    L = "%11d",             -- unsigned long, 4 bytes, 2^32 = 4,294,967,296 so 10 decimal digits, plus sign
    f = "%11.5g",           -- float,  4 bytes,  6 sig figs
    d = "%23.15g",          -- double, 8 bytes, 16 sig figs 
  } 
  -- Whisper pointformat is "!Ld"
  -- these are all comma (or now line) separated, so actual pack size is one byte larger per point.


  local function checkFormat (fmt)
    assert (fmt:match "^![%dfLd]+$", "Invalid struct format")
    local format = {}
    for i,t in fmt:gmatch "(%d?)([fLd])" do   -- format character may have numeric repeat
      for _ = 1, tonumber(i) or 1 do          -- so replicate format character
        format[#format+1] = LuaFormat[t] 
      end 
    end
    formatCache[fmt] = format   -- save result for next time
    return format
  end

  local function None (fmt)                           -- ensure None is the right field width for the format
    return (' '):rep (fmt:match "%d+" - 3) .. "nil"   
  end

  function struct.pack (fmt, ...)
    fmt = formatCache[fmt] or checkFormat (fmt)  
    local result = {}
    local args = {...}
    local f, v
    for i = 1, #fmt do           -- can't use ipairs because possibility of embedded 'nil'
      f = fmt[i]
      v = args[i]
      if v then
        result[#result+1] = f: format (args[i]) 
      else
        result[#result+1] = None (f)
      end
      result[#result+1] = ','    -- add separator
    end
    result[#result] = '\n'       -- replace final comma with new line, for readability in raw file
    return table.concat (result)
  end

  function struct.unpack (fmt, str)
    local _ = fmt  --  local fmt = formatCache[fmt] or checkFormat (fmt)  -- NOT USED
    local result = {}
    local n = 1
    for x in str:gmatch "[^,%c]+" do    -- works for 'nil' and 'nan' too
      result[n] = tonumber(x) 
      n = n + 1
    end
    return result         -- this is a list of the values in str
  end

  struct.unformatted_unpack = struct.unpack     -- ok, it's the same, but just flags the fact that it doesn't need the format

  function struct.calcsize (fmt)
    local size = 0
    fmt = checkFormat (fmt)
    for _,f in ipairs (fmt) do
      size = size + #(f: format(0)) + 1 -- extra "1" is for the separator (comma or new line)
    end
    return size
  end

end -- struct

-------

--local longFormat = "!L"
--local longSize = struct.calcsize(longFormat)
--local floatFormat = "!f"
--local floatSize = struct.calcsize(floatFormat)
--local valueFormat = "!d"
--local valueSize = struct.calcsize(valueFormat)
local pointFormat = "!Ld"
local pointSize = struct.calcsize(pointFormat)
local metadataFormat = "!2LfL"
local metadataSize = struct.calcsize(metadataFormat)
local archiveInfoFormat = "!3L"
local archiveInfoSize = struct.calcsize(archiveInfoFormat)

local function WhisperException(Exception) 
  error(Exception, 2) end    --  Base class for whisper exceptions.

--
-- __ipairs(), iterator function returning count (n) and single value/time pair (v,t) sequentially over given range
--     use like this:  for i, v,t in fetched_data:ipairs() do ... end
local function __ipairs (tvList)
  local dt = tvList.times[3]
  local t  = tvList.times[1] - dt
  local valueList = tvList.values
  local function iterator (n, i)
    i = i + 1
    t = t + dt
    if i <= n then return i, valueList[i],t end
  end
  return iterator, valueList.n or 0, 0
end


----
--
-- Storage schema (archive lists) and Aggregation methods
--
--  retentionDef = timePerPoint (resolution) and timeToStore (retention) specify lengths of time, for example:
--  units are: (s)econd, (m)inute, (h)our, (d)ay, (y)ear    (no months or weeks)
--  
--  60:1440      60 seconds per datapoint, 1440 datapoints = 1 day of retention
--  15m:8        15 minutes per datapoint, 8 datapoints = 2 hours of retention
--  1h:7d        1 hour per datapoint, 7 days of retention
--  12h:2y       12 hours per datapoint, 2 years of retention
--

local aggregationTypeToMethod = {
   'average',
   'sum',
   'last',
   'max',
   'min'
}

local aggregationMethodToType = {}  
  for k,v in ipairs (aggregationTypeToMethod) do aggregationMethodToType[v] = k end


local function aggregate (aggregationMethod, knownValues)
  local function sum (Xs) local S = 0; for i = 1,#Xs do S = S + Xs[i] end; return S end
  local function max (Xs) local M = Xs[1]; for i = 2,#Xs do M = math.max (M, Xs[i]) end; return M end
  local function min (Xs) local M = Xs[1]; for i = 2,#Xs do M = math.min (M, Xs[i]) end; return M end
  local function avg (Xs) return sum(Xs) / #Xs end
  local function last(Xs) return Xs[#Xs] end
  local function err ()   WhisperException ("Unrecognized aggregation method %s", aggregationMethod) end
  local method = {average = avg, sum = sum, last = last, max = max, min = min}
  return (method[aggregationMethod] or err) (knownValues)
end



------------
--
-- syntax and semantic check of Whisper archive specification
--
-- x = archiveSpec "1h:7d, 3h:1y"
-- x = archiveSpec {{60,3600}, {3600, 1e6}}
-- tostring (x) or print(x) returns formatted string representation
-- 
function archiveSpec (spec)

  local function validateArchiveList(archiveList)
  --  Validates an archiveList.
  --  An ArchiveList must:
  --  1. Have at least one archive config. Example: (60, 86400)
  --  2. No archive may be a duplicate of another.
  --  3. Higher precision archives' precision must evenly divide all lower precision archives' precision.
  --  4. Lower precision archives must cover larger time intervals than higher precision archives.
  --  5. Each archive must have at least enough points to consolidate to the next archive
  --
  --  Returns True or raises error exception
  
    if not archiveList or #archiveList < 1 then
      WhisperException("You must specify at least one archive configuration!") end
  
    table.sort (archiveList, function(a,b) return a[1] < b[1] end) -- #sort by precision (secondsPerPoint)
  
    for i,archive in ipairs(archiveList) do
      if i == #archiveList then
        break end
  
      local nextArchive = archiveList[i+1]
      if not (archive[1] < nextArchive[1]) then
        WhisperException( ("A Whisper database may not be configured having " ..
          "two archives with the same precision (archive%d: %s, archive%d: %s)"): format (i, archive[1], i + 1, nextArchive[1])) end
  
      if nextArchive[1] % archive[1] ~= 0 then
        WhisperException( ("Higher precision archives' precision "..
          "must evenly divide all lower precision archives' precision "..
          "(archive%d: %s, archive%d: %s)"): format (i, archive[1], i + 1, nextArchive[1])) end
  
      local retention = archive[1] * archive[2]
      local nextRetention = nextArchive[1] * nextArchive[2]
  
      if not (nextRetention > retention) then
        WhisperException( ("Lower precision archives must cover "..
          "larger time intervals than higher precision archives "..
          "(archive%d: %s seconds, archive%d: %s seconds)"): format (i, retention, i + 1, nextRetention)) end
      
      local archivePoints = archive[2]
      local pointsPerConsolidation = nextArchive[1] / archive[1]
      if not (archivePoints >= pointsPerConsolidation) then
        WhisperException( ("Each archive must have at least enough points "..
          "to consolidate to the next archive (archive%d consolidates %d of "..
          "archive%d's points but it has only %d total points)"): format (i + 1, pointsPerConsolidation, i, archivePoints)) end
    end
    return true
  end
  
  local function tostringArchiveList (archives)
    -- format an internal archive list representation as a string representation
    local ulist = { {'s', 1}, {'m', 60}, {'h', 3600}, {'d', 86400}, {'y', 86400 * 365} }
    local function timeUnit (x)
      local result = tostring(x)
      for _, u in ipairs (ulist) do
        local rem = x % u[2]
        if  rem == 0 then result = (x / u[2]) .. u[1] end
      end
      return result
    end
    local defs = {}
    for i, a in ipairs (archives) do
      defs [i] = table.concat {timeUnit(a[1]), ':', timeUnit(a[1]*a[2])}
    end
    return table.concat (defs, ',')
  end
   
  local function parseArchiveString (archiveString)   
    -- parses an archive string representation, returning an internal archive list representation
    local unit = {s = 1, m = 60, h = 3600, d = 86400, y = 86400 * 365, [''] = 1}
    local function parsePair(pair)
      local resolution, resU, retention, retU = pair: match "^(%d+)([smhdy]?):(%d+)([smhdy]?)$"  
      if not retU then error ("alist: InvalidConfiguration '" .. pair .. "'", 3) end
      local precision = resolution * unit[resU]
      local points    = retention  * unit[retU]
      if retU ~= '' then points = math.floor (points / precision) end
      return {precision, points}  
    end
    local archives = {}
    for d in archiveString: gmatch "%s*(%w+:%w+)%s*,?" do
      archives[#archives+1] = parsePair (d)
    end
    return archives
  end

  -- archiveSpec (spec)
  if type (spec) == "string" then
    spec = parseArchiveString (spec) 
  end
  validateArchiveList (spec)
  return setmetatable (spec, {__tostring = tostringArchiveList})
end

------
--
-- Archive object
--

-- archive ()
local function archive (header, offset, secondsPerPoint, points)    -- header gives access to file handle
  local retention = points * secondsPerPoint
  local size      = points * pointSize

  local function time (t,t2) t = t2 or t;  return t - (t % secondsPerPoint) end                      -- truncates time to archive's quantisation 
  local function oldest (now, now2) now = now2 or now;  return time(now) - retention + secondsPerPoint end  -- the oldest timestamp in this archive

  local function readall (_)              -- all t,v pairs in the archive 
    header.file:seek ("set",offset)
    return struct.unformatted_unpack(nil, header.file:read (points * pointSize)), points * 2 
  end      
  
  local function calc_offset (interval, interval2)  -- calculate byte offset of time interval into an archive,  @akbooer
    interval = interval2 or interval
    local  pointDistance = math.floor (interval / secondsPerPoint)
    local  pointOffset   = pointDistance        % points
    return pointOffset   * pointSize            + offset
  end
  
  local function update (_, timestamp, value)   -- write a single timestamp/value to an archive
    local fh = header.file
    local myInterval = timestamp - (timestamp % secondsPerPoint)
    local myPackedPoint = struct.pack (pointFormat, myInterval, value)
    local myOffset = calc_offset (myInterval)
    fh:seek("set", myOffset)
    fh:write(myPackedPoint)
    return
  end
  
  local function fetch (_, fromTime, untilTime) 
    --Fetch data from a single archive. Note that checks for validity of the time
    --period requested happen above this level so it's possible to wrap around the
    --archive on a read and request data older than the archive's retention
    local fh = header.file
    local fromInterval  = time (fromTime)
    local untilInterval = time (untilTime)
    local fromOffset  = calc_offset (fromInterval)                 --  determine fromOffset
    local untilOffset = calc_offset (untilInterval) + pointSize    --  determine untilOffset  @akbooer,  added pointSize
  
    -- #Read all the points in the interval(s)
    -- @akbooer:  refactored to avoid string concatenation of the two (potentially quite large) parts of the read
    fh:seek("set", fromOffset)
    local seriesStrings = {}
    if fromOffset < untilOffset then  -- #We don't wrap around the archive
      seriesStrings[1] = fh:read(untilOffset - fromOffset)
    else  -- #We do wrap around the archive, so we need two reads
      local archiveEnd = offset + size
      seriesStrings[1] = fh:read(archiveEnd - fromOffset)
      fh:seek("set", offset)
      seriesStrings[2] = fh:read(untilOffset - offset) 
    end
  
  --  #And finally we construct a list of values 
    local valueList = {} 
    local currentInterval = fromInterval
    local step = secondsPerPoint
  
    local n = 0
    for _, seriesString in ipairs (seriesStrings) do
    -- #Now we unpack the series data we just read (anything faster than unpack?)
    -- @akbooer: Yes! since we're using CSV files, no format string is required on read
    -- if you want to revert to a standard struct package, then uncomment the following three lines
      local points = #seriesString / pointSize
  --    local byteOrder,pointTypes = pointFormat:sub(1,1) ,pointFormat:sub(2,-1)
  --    local seriesFormat = byteOrder .. (pointTypes: rep (points))
  --    local unpackedSeries = struct.unpack(seriesFormat, seriesString) 
      local unpackedSeries = struct.unformatted_unpack(nil, seriesString) 
    
      local j = 0
      for _ = 1, points do 
        n = n + 1
        j = j + 1
        local pointTime = unpackedSeries[j]
        j = j + 1
        if pointTime == currentInterval then
          local pointValue = unpackedSeries[j]
          valueList[n] = pointValue          -- @akbooer: can't use #valueList because of possible nils
        end
        currentInterval = currentInterval + step
      end
    end
    valueList.n = n     -- add "n", the number of elements (just like table.pack in Lua v5.2)
    
    return valueList, {fromInterval,untilInterval,step}   -- valueList, timeInfo
  end

  -- archive()         @akbooer,  object-oriented extras...
  return {
    read            = fetch,                -- all archive fetches
    write           = update,               -- all archive updates (single point)
    calc_offset     = calc_offset,          -- byte offset of time into file (for seek)
    time            = time,                 -- truncates time to archive's quantisation
    oldest          = oldest,               -- the oldest timestamp in this archive
    readall         = readall,              -- all t,v pairs in the archive  
    size            = size,
    points          = points,
    retention       = retention,  
    secondsPerPoint = secondsPerPoint,
  }
    
end


----
--
-- Whisper file structure
--

--[[
 Here is the basic layout of a whisper data file

 File = Header,Data
 Header = Metadata,ArchiveInfo+
   Metadata = aggregationType,maxRetention,xFilesFactor,archiveCount
   ArchiveInfo = Offset,SecondsPerPoint,Points
 Data = Archive+
   Archive = Point+
     Point = timestamp,value
--]]

local function header (metadata)
  -- create new header object given metadata array

  local function tostringHeader (h)
    return table.concat {tostring (h.retentions), ' [', h.xFilesFactor, '] ', h.aggregationMethod}
  end

  local function retentions (self)    -- construct archive list and return as archiveSpec with "tostring" metatable
    local alist = {}
    for _,a in ipairs (self) do table.insert (alist, {a.secondsPerPoint, a.points}) end
    return archiveSpec (alist)    
  end
    
  local function addArchive (self, unpackedArchiveInfo)
    -- add archive given unpackedArchiveInfo
    local offset          = unpackedArchiveInfo[1]
    local secondsPerPoint = unpackedArchiveInfo[2]
    local points          = unpackedArchiveInfo[3]
    local archiveInfo     = archive (self, offset, secondsPerPoint, points)
    table.insert (self.archives, archiveInfo)
  end

  local function propagate(self, timestamp, higher, lower)  -- @akbooer,  refactored to use archive:read and archive:write
    -- propagate data to lower archive using aggregation function
    local aggregationMethod = self.aggregationMethod
    local xff = self.xFilesFactor
  
    local lowerIntervalStart  = lower: time(timestamp)
    local higherIntervalStart = lowerIntervalStart
    local higherIntervalEnd   = higherIntervalStart + lower.secondsPerPoint - higher.secondsPerPoint
  
    local neighborValues = higher:read (higherIntervalStart, higherIntervalEnd)
  
  --  #Propagate aggregateValue to propagate from neighborValues if we have enough known points
    local n = neighborValues.n
    local knownValues = {}
    for i = 1,n do knownValues [#knownValues+1] = neighborValues[i] end   -- [v for v in neighborValues if v is not None]
    local ok = (#knownValues / n) >= xff
  
    if ok then                                                             -- #we have enough data to propagate a value!
      local aggregateValue = aggregate(aggregationMethod, knownValues)
      lower:write (lowerIntervalStart, aggregateValue)
    end
    return ok
  end
 
  local function update(self, value, timestamp, now)
    local now = now or os.time() 
    timestamp = math.floor(timestamp or now)
  
    local diff = now - timestamp    
    if not ((diff < self.maxRetention) and diff >= 0) then
      WhisperException("Timestamp not covered by any archives in this database.")
    end 
    local archive
    local archives = self.archives
    local lowerArchives = {}
    for i,arch in ipairs(archives) do -- #Find the highest-precision archive that covers timestamp
      archive = arch
      if archive.retention >= diff then
        for j = i+1, #archives do
          lowerArchives[#lowerArchives+1] = archives[j] end   -- #We'll pass on the update to these lower precision archives later
        break
      end
    end
  --  #First we update the highest-precision archive
    local myInterval = archive: time (timestamp)
    archive:write (myInterval, value)
  --  #Now we propagate the update to lower-precision archives
    local higher = archive
    for _, lower in ipairs (lowerArchives) do
      if not propagate(self, myInterval, higher, lower) then
        break
      end
      higher = lower
    end
  end
  
  local function fetch(self, fromTime, untilTime, now)
  --  Here we try and be flexible and return as much data as we can.
  --  If the range of data is from too far in the past or fully in the future, we
  --  return nothing
    now = now or os.time()
    untilTime = untilTime or now
  
    local archives = self.archives
    local lastArchive = archives[#archives]
    local oldestTime = lastArchive:oldest (now) 
    if fromTime > untilTime then
      WhisperException(("Invalid time interval: from time '%d' is after until time '%d'"): format (fromTime, untilTime))
    end
  
    if fromTime  > now then return nil end                      -- Range is in the future 
    if untilTime < oldestTime then return nil end               -- Range is back beyond retention 
    if fromTime  < oldestTime then fromTime = oldestTime end    -- Range is partially beyond retention, adjust
    if untilTime > now then untilTime = now end                 -- Range is partially in the future, adjust
  
    local archive
    for _,arch in ipairs (archives) do
      archive = arch
      local achiveOldest = archive:oldest (now)
      if achiveOldest <= fromTime then break end
    end
    local valueList, timeInfo = archive:read (fromTime, untilTime)
    return {times = timeInfo, values = valueList, ipairs = __ipairs}    -- wrap in a table with iterator function for convenience
  end

  local self = {
    aggregationMethod = aggregationTypeToMethod[metadata[1]] or 'average', 
    maxRetention = metadata[2],
    xFilesFactor = metadata[3],
    archiveCount = metadata[4],
    archives     = {retentions = retentions},     -- add method for retrieving archiveSpec
    -- @akbooer,  header extras (not stored in file) ...
    file       = nil,                      -- file handle filled in later on each file open
    addArchive = addArchive,
    update     = update,
    fetch      = fetch,
  }
  
  return setmetatable (self, {__tostring = tostringHeader})
end

--
-- Header I/O
--

local function  __writeHeader (fh,archiveList,xFilesFactor,aggregationMethod)
  -- write a file header, returning total number of points in ALL the archives
  local archiveList     = archiveSpec (archiveList) 
  local lastArchive     = archiveList[#archiveList]           -- HAS to be the longest duration
  local maxRetention    = lastArchive[1] * lastArchive[2]
  local aggregationType = aggregationMethodToType[aggregationMethod] or 1
  local packedMetadata  = struct.pack (metadataFormat, aggregationType, maxRetention, xFilesFactor, #archiveList)
  fh:seek ("set", 0)
  fh:write(packedMetadata)

  local archiveOffsetPointer = metadataSize + (archiveInfoSize * #archiveList)      -- = headerSize
  local totalPoints = 0
  for _,a in ipairs(archiveList) do
    local secondsPerPoint,points = a[1], a[2]
    local archiveInfo = struct.pack (archiveInfoFormat, archiveOffsetPointer, secondsPerPoint, points)
    fh:write(archiveInfo)
    totalPoints = totalPoints + points
    archiveOffsetPointer = archiveOffsetPointer + (points * pointSize)
  end
  return totalPoints  
end

local function __readHeader(fh, path)
  fh:seek("set", 0)
  local packedMetadata = fh:read(metadataSize)
  local metadata = struct.unpack(metadataFormat,packedMetadata) 
  if #metadata ~= 4 then    --    metadata = {aggregationType,maxRetention,xFilesFactor,archiveCount}
    WhisperException (("Unable to read header from '%s'") : format (path or '?')) end
 
  local self = header (metadata)

  for i = 1, self.archiveCount do
    local packedArchiveInfo   = fh:read(archiveInfoSize)
    local unpackedArchiveInfo = struct.unpack(archiveInfoFormat,packedArchiveInfo) 
    if #unpackedArchiveInfo ~= 3 then      -- archiveInfo = {offset,secondsPerPoint,points}
      WhisperException (("Unable to read archive %d metadata from '%s'"): format (i, path or '?')) end

    self:addArchive (unpackedArchiveInfo)
  end
  self.retentions = self.archives:retentions()      -- pre-compute retentions list with text representation (it's just useful)
  
  return self
end


-------
--
-- Basic open / info / create / update / fetch operations
--

local __headerCache = {}    -- header cache used to save re-reading file headers often

local function __file_open (path, mode, fct, silent)
  -- open a file and return modified handle, or optionally raise error if unable to do so
  local result
  local file = io.open (path, mode)
  if file then
    local header = __headerCache[path] or __readHeader (file, path) 
    if CACHE_HEADERS then __headerCache[path] = header end         -- save info for next time
    header.file = file    -- save real file handle for archive read/write methods
    result = fct (header)
    header.file = nil     -- discard out of date file handle
    file: close ()
  elseif not silent then
    WhisperException (("unable to open Whisper file '%s'"): format (path or '---none---') )
  end
  return result
end

--
--  Global methods 
--

function info (path)   -- this is, in fact, __readHeader for the outside world
  -- info(path), path is a string
  -- failure is not an error, since we may use this to check for file existence too
  local  header = __headerCache[path] or __file_open(path,'rb', function (header) return header end, true)   
  return header   
end

function create (path,archiveList,xFilesFactor,aggregationMethod)
  -- path is a string
  -- archiveList is a list of archives, each of which is of the form (secondsPerPoint,numberOfPoints)
  -- OR a string of the form "10s:1m,1m:1h,1d:1y"  (@akbooer)
  -- xFilesFactor specifies the fraction of data points in a propagation interval that must have known values for a propagation to occur
  -- aggregationMethod specifies the function to use when propogating data (see 'whisper.aggregationMethods')
  
  archiveList = archiveSpec (archiveList) 
  local fh = io.open(path,'wb')
  if fh then
    local remaining = __writeHeader (fh,archiveList,xFilesFactor or 0.5,aggregationMethod or 'average')
    local chunksize = 1024    -- size in points (with CSV, then bytesize = 36 * 1024)
    local zeroes = struct.pack (pointFormat, 0,0):rep (chunksize)
    while remaining > chunksize do
      fh:write (zeroes)
      remaining = remaining - chunksize
    end
    fh:write (zeroes:sub(1,remaining * pointSize))
    fh:close ()
  else
     WhisperException ("Cannot create file '%s'", path)
  end
  __headerCache[path] = nil    -- invalidate any cached info for this file 
 end

function update (path,value,timestamp, now)
  --path is a string
  --value is a float
  --timestamp is either an int or float
  return __file_open(path,'r+b', function (header) return header: update(value, timestamp, now) end)
end

function fetch (path,fromTime,untilTime,now)
  -- path is a string
  -- fromTime is an epoch time
  -- untilTime is also an epoch time, but defaults to now.
  -- Returns a tuple of (timeInfo, valueList)  (@akbooer:  actually, for Lua, a table is better - includes iterator)
  -- where timeInfo is itself a tuple of (fromTime, untilTime, step)
  -- Returns nil if no data can be returned
  return __file_open(path,'rb', function (header) return header: fetch(fromTime, untilTime, now) end)
end

--  @akbooer,  refactored to use __readHeader and __writeHeader
function setAggregationMethod (path, aggregationMethod, xFilesFactor)  
  -- path is a string
  -- aggregationMethod (string) specifies the method to use when propagating data (see ``whisper.aggregationMethods``)
  -- xFilesFactor specifies the fraction of data points in a propagation interval that must have known values for a propagation to occur.  
  -- If None, the existing xFilesFactor in path will not be changed
  __file_open(path,'r+b', function (header)
    local newAggregationType = aggregationMethodToType[aggregationMethod] 
    if not newAggregationType then
      WhisperException( ("Unrecognized aggregation method: %s"): format (aggregationMethod) ) end
    __writeHeader (header.file,header.retentions,xFilesFactor or header.xFilesFactor,aggregationMethod)  -- #use specified xFilesFactor or retain old value    
  end) 
  __headerCache[path] = nil    -- invalidate any cached info for this file 
  return aggregationMethod
end

--------
