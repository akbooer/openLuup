local ABOUT = {
  NAME          = "panels.lua",
  VERSION       = "2023.01.04",
  DESCRIPTION   = "built-in console device panel HTML functions",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2022 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-2022 AK Booer

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

Each device panel is described by a table which may define three functions, to return the panel as displayed on the device pages, the icon, and the extended panel seen of the device's control tab page.

  control   -- device control tab
  panel     -- device panel
  icon  x    -- icon

The tables are index by device type, and called with the device number as a single parameter.

Each function returns HTML - either plain text or openLuup DOM model - which defines the panel to be drawn

-- using openLuup XML module and W3.css framework

--]]

-- 2019.06.20  @akbooer
-- 2019.07.14  use new HTML constructor methods
-- 2019.11.14  move into separate file

-- 2020.05.07  add simple camera control panel showing video stream

-- 2021.01.20  add panel utility functions
-- 2021.03.05  generic Shelly control panel
-- 2021.03.17  generic sensor device (for @ArcherS)

-- 2022.06.20  fix non-string argument in todate()  (thanks @a-lurker)
-- 2022.06.30  ...another go at the above fix
-- 2022.07.31  add ShellyHomePage to Shelly scene controllers
-- 2022.11.11  prettier openLuup device control panel
-- 2022.11.27  add basic support for Zigbee2MQTT bridge
-- 2022.12.30  add link to https://dev.netatmo.com/

-- 2022.01.03  add Authorize button for Netatmo Oath2 tokens


local xml = require "openLuup.xml"
local SID = require "openLuup.servertables" .SID
local API = require "openLuup.api"

local h = xml.createHTMLDocument ()    -- for factory methods
local div = h.div
local a, p = h.a, h.p
    
local sid = SID {
    althue    = "urn:upnp-org:serviceId:althue1",
    camera    = "urn:micasaverde-com:serviceId:Camera1",
    netatmo   = "urn:akbooer-com:serviceId:Netatmo1",
    security  = "urn:micasaverde-com:serviceId:SecuritySensor1",
    weather   = "urn:upnp-micasaverde-com:serviceId:Weather1",
  }

local function tiny_date_time (epoch)
  local date_time = tonumber(epoch) and os.date ("%Y-%m-%d %H:%M:%S", epoch) or "---  00:00"
  return div {class = "w3-tiny w3-display-bottomright", date_time}  
end

local function ShellyHomePage (devNo)  
  local ip = luup.attr_get ("ip", devNo) or ''
  local src = table.concat {"http://", ip}
  return div {class = "w3-panel", h.iframe {src = src, width="500", height="300"}}
end

local panels = {

--
-- openLuup
--
  openLuup = {
    control = function(devNo) 
      local about = luup.devices[devNo].environment.ABOUT
      local forum = about.FORUM
      local donate = about.DONATE
      return div {
        div { 
          a {class = "w3-round-large w3-dark-gray w3-button w3-margin", href=forum, target="_blank", 
            h.img {alt="SmartHome Community", width=300, src= forum.."assets/uploads/system/site-logo.png?"}}},
        div { 
          a {class = "w3-round-large w3-white w3-button w3-margin w3-border", href=donate, target="_blank", 
            h.img {alt="Donate to Cancer Research", width=300, 
              src= "https://www.cancerresearchuk.org/sites/all/themes/custom/cruk/cruk-logo.svg"}}},
        }
    end},

--
-- AltHue
--

  althue = {
    panel = function (devNo)
      local v = luup.variable_get (sid.althue, "Version", devNo)
      return h.span (v or '')
    end},
  
--
-- AltUI
--
  altui = {
    panel = function (devNo)
      local v = luup.variable_get (sid.altui, "Version", devNo)
      return h.span (v or '')
    end},
    
--
-- Camera
--
  DigitalSecurityCamera = {
    control = function (devNo)
      local ip = luup.attr_get ("ip", devNo) or ''
      local stream = luup.variable_get (sid.camera, "DirectStreamingURL", devNo) or ''
      local src = table.concat {"http://", ip, stream}
      return div {class = "w3-panel", h.iframe {src = src, width="300", height="200"}}
  end},

--
-- Motion Sensor
--

--  MotionSensor = {
--    panel = function (devNo)
--      local time  = luup.variable_get (sid.security, "LastTrip", devNo)
--      return div {class = "w3-tiny w3-display-bottomright", time and todate(time) or ''}
--    end},

--
-- Netatmo
--

  Netatmo = {
    control = function ()
      local br = h.br{}
      return div {
        p "Grant plugin access to your weather station data:",
        h.form {
          action="https://api.netatmo.com/oauth2/authorize", 
          method="get",
--          enctype = "application/x-www-form-urlencoded", -- "multipart/form-data",  -- "text/plain",
          target="_blank",
          h.input {type="hidden", name="client_id", value="5200dfd21977593427000024"},
          h.input {type="hidden", name="scope", value="read_station"},
          h.input {type="hidden", name="state", value="42"},
          h.input {type="submit", value="Authorize"}
        },

--        p {class="w3-text-indigo",
--          h.a {href="https://dev.netatmo.com/", target="_blank", "dev.netatmo.com"}, 
--          },

        p "Links to reports:",
        p {class="w3-text-indigo",
          h.a {href="/data_request?id=lr_Netatmo&page=organization", target="_blank", "Device Tree"}, br,
          h.a {href="/data_request?id=lr_Netatmo&page=list", target="_blank", "Device List"}, br,
          h.a {href="/data_request?id=lr_Netatmo&page=diagnostics", target="_blank", "Diagnostics"}, br,
        }}
    end},

--
-- Power Meter
--

  PowerMeter = {
    panel = function (devNo)
      local watts = luup.variable_get (sid.energy, "Watts", devNo)
      local time  = luup.variable_get (sid.energy, "KWHReading", devNo)
      local kwh   = luup.variable_get (sid.energy, "KWH", devNo)
      return h.span {watts or '???', " Watts", h.br(), ("%0.0f"): format(kwh or 0), " kWh", h.br(), 
        tiny_date_time (time)}
    end},

--
-- SceneController
--

  SceneController = {
    panel = function (devNo)
      local time = luup.variable_get (sid.scene, "LastSceneTime", devNo)
      return tiny_date_time (time)
    end,
    control = function (devNo)
      local isShelly = luup.devices[devNo].id: match "^shelly"
      return isShelly and ShellyHomePage (devNo) or "<p>Scene Controller</p>"
    end},
    
--
-- Shellies
--
  GenericShellyDevice = {
    control = ShellyHomePage,
  },
  
    
--
-- Zigbee2MQTT
--
  Zigbee2MQTTBridge = {
    panel = function (devNo)
      local D = API[devNo]
      local time = D.hadevice.LastUpdate
      local version = D.attr.version
      return h.span {version, h.br(), tiny_date_time (time)}
    end,
  },
  
--
-- Generic Sensor
--
  GenericSensor = {
    panel = function (devNo)
      local v = luup.variable_get (sid.generic, "CurrentLevel", devNo)
      return h.span (v or '')
    end,
  },
--
-- Weather (NB. this is the device type for the DarkSkyWeather plugin)
--

  Weather = {
    control = function (devNo)  
      local class = "w3-card w3-margin w3-round w3-padding"
      
      local function items (list, prefix)
        prefix = prefix or ''
        local t = h.table {class="w3-small"}
        for _, name in ipairs (list) do 
          local v = luup.variable_get (sid.weather, prefix..name, devNo)
          t.row {name:gsub ("(%w)([A-Z])", "%1 %2"), v} 
        end
        return div {class = "w3-container", t}
      end
      
      local conditions = items {"CurrentConditions", "TodayConditions", "TomorrowConditions", "WeekConditions"}
      local current = items ({"Temperature", "Humidity", "DewPoint", "PrecipIntensity", "WindSpeed", 
              "PrecipType", "PrecipProbability", "WindBearing", "Ozone", "ApparentTemperature", "CloudCover"}, "Current")
      local today = items ({"LowTemp", "HighTemp", "Pressure"}, "Today")
      local tomorrow = items ({"LowTemp", "HighTemp", "Pressure"}, "Tomorrow")
      local time = luup.variable_get (sid.weather, "LastUpdate", devNo)
      
      return 
        div { class = "w3-row",
          div {class = class, h.h5 "General Conditions", conditions},
          div {class = "w3-half", 
            div {class = class, h.h5 (time and os.date ("At %H:%M, %d-%b-'%y", time) or '?'), current} },
          div {class = "w3-row w3-half",
            div {class = class, h.h5 "Today", today},
            div {class = class, h.h5 "Tomorrow", tomorrow} } }
    end},

--
-- ZWay
--
  ZWay = {
    control = function() return 
      div {
        h.a {class="w3-text-blue", href="/cgi/zway_cgi.lua", target="_blank",
          "Configure ZWay child devices"} }
    end},

 
}

--
-- aliases
--

panels.DoorSensor = panels.MotionSensor


return {
    device_panel = panels,
  }

