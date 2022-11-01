local VERSION = "2022.11.01"

-- mimetypes
-- 2016/04/14
-- thanks to @explorer for suggesting a separate file

-- these entries are used to determine the response type of HTML
-- file transfer requests using the file extension code
-- syntax is extension = "return type",
-- feel free to add what you need

-- 2016.07.14  added status_codes for server response
-- 2016.10.17  added CGI prefixes and aliases
-- 2016.11.17  change location of graphite_cgi to openLuup folder
-- 2016.11.18  added CGI console.lua

-- 2018.02.19  added directory aliases (for file access requests)
-- 2018.03.06  added SMTP status codes
-- 2018.03.09  added myIP, moved from openLuup.server
-- 2018.03.15  updated SMTP reply codes according to RFC 5321
-- 2018.04.14  removed upnp/ from CGI directories and HAG module...
--              ["upnp/control/hag"] = "openLuup/hag.lua", --- DEPRECATED, Feb 2018 ---
-- 2018.06.12  added Data Historian Disk Archive Whisper schemas and aggregations
-- 2018.08.20  added *Time* to nocache rules
-- 2018.12.31  start to add retentions, xFF and aggregation to Historian archive_rules
 
-- 2019.04.08  added image/svg+xml to mimetypes
-- 2019.04.18  remove historian in-memory cache rules (now implemented in devices module)
-- 2019.06.11  cache control definitions moved here from servlet module

-- 2021.01.31  MQTT codes added
-- 2021.03.20  DEV and SID codes added
-- 2021.05.10  add Tasmota-style Historian archive rules for Temperature, Humidity, Battery (thanks @Buxton, @ArcherS)
-- 2021.05.12  archive_rules now standalone, so include retentions and aggregation and xff (no .conf file references)
-- 2021.05.14  add cgi/whisper-edit.lua to CGI aliases (and include in baseline directory)
-- 2021.05.18  add cache _rules for historian in-memory cache

-- 2022.10.24  add Historian rules for Shelly H&T T/H max/min

-- http://forums.coronalabs.com/topic/21105-found-undocumented-way-to-get-your-devices-ip-address-from-lua-socket/

local socket  = require "socket"
local xml     = require "openLuup.xml"


local function myIP ()    
  local mySocket = socket.udp ()
  mySocket:setpeername ("42.42.42.42", "424242")  -- arbitrary IP and PORT
  local ip = mySocket:getsockname () 
  mySocket: close()
  return ip or "127.0.0.1"
end


local mimetypes = {
  css  = "text/css", 
  gif  = "image/gif",
  html = "text/html", 
  htm  = "text/html", 
  ico  = "image/x-icon",
  jpeg = "image/jpeg",
  jpg  = "image/jpeg",
  js   = "application/javascript",
  json = "application/json",
  mid  = "audio/mid",
  mp3  = "audio/mpeg",
  png  = "image/png",
  svg  = "image/svg+xml",
  txt  = "text/plain",
  wav  = "audio/wav",
  xml  = "application/xml",
}


-- HTTP status codes (from wsapi.common)
local status_codes = {
   [100] = "Continue",
   [101] = "Switching Protocols",
   [200] = "OK",
   [201] = "Created",
   [202] = "Accepted",
   [203] = "Non-Authoritative Information",
   [204] = "No Content",
   [205] = "Reset Content",
   [206] = "Partial Content",
   [300] = "Multiple Choices",
   [301] = "Moved Permanently",
   [302] = "Found",
   [303] = "See Other",
   [304] = "Not Modified",
   [305] = "Use Proxy",
   [307] = "Temporary Redirect",
   [400] = "Bad Request",
   [401] = "Unauthorized",
   [402] = "Payment Required",
   [403] = "Forbidden",
   [404] = "Not Found",
   [405] = "Method Not Allowed",
   [406] = "Not Acceptable",
   [407] = "Proxy Authentication Required",
   [408] = "Request Time-out",
   [409] = "Conflict",
   [410] = "Gone",
   [411] = "Length Required",
   [412] = "Precondition Failed",
   [413] = "Request Entity Too Large",
   [414] = "Request-URI Too Large",
   [415] = "Unsupported Media Type",
   [416] = "Requested range not satisfiable",
   [417] = "Expectation Failed",
   [500] = "Internal Server Error",
   [501] = "Not Implemented",
   [502] = "Bad Gateway",
   [503] = "Service Unavailable",
   [504] = "Gateway Time-out",
   [505] = "HTTP Version not supported",
}


-- see: https://www.iana.org/assignments/smtp-enhanced-status-codes/smtp-enhanced-status-codes.xhtml
local smtp_codes = {
  [211] = "System status, or system help reply",
  [214] = "Help message",
  [220] = "%s Service ready",                                               -- <domain>
  [221] = "%s Service closing transmission channel",                        -- <domain>
  [235] = "Authentication successful",
  [250] = "OK",      -- Requested mail action okay
  [251] = "User not local; will forward to <%s>",                             -- <forward-path>
  [252] = "Cannot VRFY user, but will accept message and attempt delivery",
  [334] = "%s",                                                             -- AUTH challenge (in base64)
  [354] = "Start mail input; end with <CRLF>.<CRLF>",
  [421] = "%s Service not available, closing transmission channel",         -- <domain>
  [450] = "Requested mail action not taken: mailbox <%s> unavailable",        -- <mailbox>
  [451] = "Requested action aborted: local error in processing",
  [452] = "Requested action not taken: insufficient system storage",
  [455] = "Server unable to accommodate parameters",
  [500] = "Syntax error, command <%s> unrecognized",                           -- <command>
  [501] = "Syntax error in parameters or arguments <%s>",
  [502] = "Command <%s> not implemented",                                      -- <command>
  [503] = "Bad sequence of commands",
  [504] = "Command parameter <%s> not implemented",
  [521] = "Host does not accept mail",
  [550] = "Requested action not taken: <%s> unavailable",                       -- <mailbox>
  [551] = "User not local; please try <%s>",                                   -- <forward-path>
  [552] = "Requested mail action aborted: exceeded storage allocation",
  [553] = "Requested action not taken: mailbox name not allowed",
  [554] = "Transaction failed",
  [555] = "MAIL FROM/RCPT TO parameters not recognized or not implemented",
  [556] = "Domain does not accept mail",
}

-- MQTT Connection Return Codes
local mqtt_codes = {
  [0] = "Connection Accepted",
  [1] = "Connection Refused, unacceptable protocol version",
  [2] = "Connection Refused, identifier rejected",
  [3] = "Connection Refused, Server unavailable",
  [4] = "Connection Refused, bad user name or password",
  [5] = "Connection Refused, not authorized",
}


-- CGI prefixes: HTTP requests with any of these path roots are treated as CGIs
local cgi_prefix = {
    "cgi",          -- standard CGI directory
    "cgi-bin",      -- ditto
    
    "console",      -- openLuup console interface
    "openLuup",     -- console alias
    
    "dashboard",    -- for graphite_api
    "metrics",      -- ditto
    "render",       -- ditto
        
    "ZWaveAPI",     -- Z-Wave.me Advanced API (requires Z-Way plugin)
    "ZAutomation",  -- Z-Wave.me Virtual Device API
  }

-- CGI aliases: any matching full CGI path is redirected accordingly

local graphite_cgi  = "openLuup/graphite_cgi.lua"

local cgi_alias = setmetatable ({
    
    ["cgi/whisper-edit.lua"]      = "openLuup/whisper-edit.lua",
    ["cgi-bin/cmh/backup.sh"]     = "openLuup/backup.lua",
    ["cgi-bin/cmh/sysinfo.sh"]    = "openLuup/sysinfo.lua",
    ["console"]                   = "openLuup/console.lua",
    ["openLuup"]                  = "openLuup/console.lua",
    
    -- graphite_api support
    ["metrics"]             = graphite_cgi,
    ["metrics/find"]        = graphite_cgi,
    ["metrics/expand"]      = graphite_cgi,
    ["metrics/index.json"]  = graphite_cgi,
    ["render"]              = graphite_cgi,
  },
  
  { __index = function (_, path)
--      -- TODO: REMOVE special handling of Zway requests (all directed to same handler)
    if path: match "^ZWaveAPI"
      or path: match "^ZAutomation" then
        return "cgi/zway_cgi.lua"
      end
    end
  })

-- Directory redirect aliases

local dir_alias = {
    ["cmh/skins/default/img/devices/device_states/"] = "icons/",  -- redirect UI7 icon requests
    ["cmh/skins/default/icons/"] = "icons/",                      -- redirect UI5 icon requests
    ["cmh/skins/default/img/icons/"] = "icons/" ,                 -- 2017.11.14 
  }
 
-- cache retentions (used by file servlet)
local cache_control = {                 -- 2019.05.14  max-age in seconds indexed by filetype
  png = 3600, 
  svg = 3600, 
  css = 3600, 
  ico = 3600, 
  xml = 3600,
}

-- Data Historian Disk Archive rules
--
-- pattern: matches deviceNo.shortServiceId.variable
-- NB: device ignored, and FULL shortSID OR VARIABLE name only

local cache_rules = {
  -- services to OMIT from cache
    "*.ZWaveDevice1.*", 
    "*.ZWaveNetwork1.*",
  -- variables ditto
    "*.*.Configured", 
    "*.*.CommFailure",
  }
  
-- Data Historian Disk Archive rules
--
-- pattern: matches deviceNo.shortServiceId.variable
-- this is independent of the Carbon storage-schema rule configuration files
-- patterns are searched in order, and first match is used

local archive_rules = {
    {
      retentions = "1s:1m,1m:1d,10m:7d,1h:30d,3h:1y,1d:10y",
      patterns = {"*.*.Tripped"},
      xFilesFactor = 0,
      aggregationMethod = "max",
    },{
      patterns = {"*.*.Status"},
      retentions = "1m:1d,10m:7d,1h:30d,3h:1y,1d:10y",
    },{
      patterns = {"*.*{openLuup,DataYours,EventWatcher}*.*"},
      retentions = "5m:7d,1h:30d,3h:1y,1d:10y",
    },{
      patterns = {
        "*.*.Current*",                   -- temperature, humidity, generic sensors, setpoint...
        "*.*.{Temperature,Humidity}",     -- Tasmota-style
        },
    },{
      patterns = {"*.*.MaxTemp"},                    -- special for H&T max/min values
      retentions = "10m:1d,1d:10y",
      aggregationMethod = "max",
    },{
      patterns = {"*.*.MinTemp"},                    -- special for H&T max/min values
      retentions = "10m:1d,1d:10y",
      aggregationMethod = "min",
    },{
      patterns = {"*.*EnergyMetering*.{KWH,Watts,kWh24, Voltage, Current}"},
      retentions = "20m:30d,3h:1y,1d:10y",
    },{
      patterns = {},
      retentions = "1h:90d,3h:1y,1d:10y",
    },{
      patterns = {},
      retentions = "3h:1y,1d:10y",
    },{
      patterns = {},
      retentions = "6h:1y,1d:10y",
    },{
      patterns = {"*.*.{BatteryLevel, Battery}"},   -- Vera and Tasmota versions
      retentions = "1d:10y",
    },
  }


-- Device types and ServiceIds
--
-- usage:
--   local DEV = tables.DEV {foo = "urn:...", garp = "urn:..."}    -- optionally, extend default table with local references
--
local meta = {
  __call = function (self, args)
    return setmetatable (args, {__index = self})
  end}

local DEV = setmetatable ({
    light       = "D_BinaryLight1.xml",
    dimmer      = "D_DimmableLight1.xml",
    thermos     = "D_HVAC_ZoneThermostat1.xml",
    motion      = "D_MotionSensor1.xml",
    controller  = "D_SceneController1.xml",
    combo       = "D_ComboDevice1.xml",
    rgb         = "D_DimmableRGBLight1.xml",
    temperature = "D_TemperatureSensor1.xml",
    humidity    = "D_HumiditySensor1.xml",
  }, meta)

local SID = setmetatable ({
    
    -- Short SIDs (as used by Historian / Grafana)
    altui1                  = "urn:upnp-org:serviceId:altui1",
    AltAppStore1            = "urn:upnp-org:serviceId:AltAppStore1",
    Dimming1                = "urn:upnp-org:serviceId:Dimming1",
    EnergyMetering1         = "urn:micasaverde-com:serviceId:EnergyMetering1",
    HaDevice1               = "urn:micasaverde-com:serviceId:HaDevice1",
    HomeAutomationGateway1  = "urn:micasaverde-com:serviceId:HomeAutomationGateway1",
    HumiditySensor1         = "urn:micasaverde-com:serviceId:HumiditySensor1",
    LightSensor1            = "urn:micasaverde-com:serviceId:LightSensor1",
    SwitchPower1            = "urn:upnp-org:serviceId:SwitchPower1",                          
    SecuritySensor1         = "urn:micasaverde-com:serviceId:SecuritySensor1",
    SceneController1        = "urn:micasaverde-com:serviceId:SceneController1",
    TemperatureSensor1      = "urn:upnp-org:serviceId:TemperatureSensor1",
    ZWaveDevice1            = "urn:micasaverde-com:serviceId:ZWaveDevice1",
    
    -- Very Short SIDs
    altui     = "urn:upnp-org:serviceId:altui1",
    appstore  = "urn:upnp-org:serviceId:AltAppStore1",
    dimming   = "urn:upnp-org:serviceId:Dimming1",
    energy    = "urn:micasaverde-com:serviceId:EnergyMetering1",
    hadevice  = "urn:micasaverde-com:serviceId:HaDevice1",
    hag       = "urn:micasaverde-com:serviceId:HomeAutomationGateway1",
    humid     = "urn:micasaverde-com:serviceId:HumiditySensor1",
    light     = "urn:micasaverde-com:serviceId:LightSensor1",
    switch    = "urn:upnp-org:serviceId:SwitchPower1",                          
    security  = "urn:micasaverde-com:serviceId:SecuritySensor1",
    scene     = "urn:micasaverde-com:serviceId:SceneController1",
    temp      = "urn:upnp-org:serviceId:TemperatureSensor1",
    zwave     = "urn:micasaverde-com:serviceId:ZWaveDevice1",
  
  }, meta)

-----
--
-- device/service file synthesis utilities
--


-- synthesize SCPDURL and serviceType from serviceId 
local function svc_synth (sid)
  local serviceType = "urn:schemas-%s:service:%s:%s"
  local serviceFile = "S_%s.xml"

  local id1, id2 = sid: match "urn:(.-):serviceId:(.+)"
  if not id1 then 
    return serviceFile: format(sid), sid    -- special handling for openLuup no-nonsence SID
  end
  local id3 = id2: match "%D+%d?"
  local sfile = serviceFile: format (id3)
  
  local id4,idn = id3: match "^([%a_]+)(%d?)$"
  local stype = serviceType: format(id1,id4,idn)
  return sfile, stype
end

-- synthesize XML device file
local function Device (d)
  local x = xml.createDocument ()
  local dev = {}
  local special = {implementationList = true, serviceList = true, serviceIds = true}
  for n,v in pairs (d) do
    if not special[n] then
      dev[#dev+1] = x[n] (v)
    end
  end
  if d.serviceIds then 
    local slist = {}
    for i, sid in ipairs (d.serviceIds) do
      local SCPDURL, serviceType = svc_synth (sid)
      slist[i] = x.service {x.serviceType (serviceType), x.serviceId (sid), x.SCPDURL(SCPDURL)}
    end
    dev[#dev+1] = x.serviceList (slist)
  end
  if d.serviceList then 
    local slist = {}
    for i, s in ipairs (d.serviceList) do
      slist[i] = x.service {x.serviceType (s[1]), x.serviceId (s[2]), x.SCPDURL(s[3])}
    end
    dev[#dev+1] = x.serviceList (slist)
  end
  if d.implementationList then
    local flist = {}
    for i,f in ipairs (d.implementationList) do
      flist[i] = x.implementationFile (f)
    end
    dev[#dev+1] = x.implementationList (flist)
  end
  x: appendChild {
    x.root {xmlns="urn:schemas-upnp-org:device-1-0",
      x.specVersion {x.major "1", x.minor "0", x.minimus "auto-generated"},
      x.device (dev)
        }}
  return tostring (x)
end



-----
return {
  
    VERSION = VERSION,
    
    DEV = DEV,
    SID = SID,
    
    myIP            = myIP (),
    cgi_prefix      = cgi_prefix,
    cgi_alias       = cgi_alias,
    dir_alias       = dir_alias,
    mimetypes       = mimetypes,
    smtp_codes      = smtp_codes,         -- SMTP
    status_codes    = status_codes,       -- HTTP
    mqtt_codes      = mqtt_codes,         -- MQTT
    cache_control   = cache_control,      -- for file servlet
    archive_rules   = archive_rules,      -- for historian disk archives
    cache_rules     = cache_rules,        -- for in-memory historian cache
    
    -- utilities
    
    Device = Device,
    
  }
  
-----
