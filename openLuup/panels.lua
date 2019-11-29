local ABOUT = {
  NAME          = "panels.lua",
  VERSION       = "2019.11.29",
  DESCRIPTION   = "built-in console device panel HTML functions",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2019 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-2019 AK Booer

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

local xml = require "openLuup.xml"

local h = xml.createHTMLDocument ()    -- for factory methods
local div = h.div

local sid = {
    altui     = "urn:upnp-org:serviceId:altui1",
    energy    = "urn:micasaverde-com:serviceId:EnergyMetering1",
    netatmo   = "urn:akbooer-com:serviceId:Netatmo1",
    scene     = "urn:micasaverde-com:serviceId:SceneController1",
    security  = "urn:micasaverde-com:serviceId:SecuritySensor1",
  }
  
local function todate (epoch) return os.date ("%Y-%m-%d %H:%M:%S", epoch) end

local panels = {

--
-- openLuup
--
  openLuup = {
    control = function() return 
      '<div><a class="w3-text-blue", href="https://www.justgiving.com/DataYours/" target="_blank">' ..
        "If you like openLuup, you could DONATE to Cancer Research UK right here</a>" ..
        "<p>...or from the link in the page footer below</p></div>" 
    end},

--
--
-- AltHue
--

  alhue = {
    panel = function ()
      return "<span>ALTHUE panel coming shortly</span>"
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
-- Motion Sensor
--

  MotionSensor = {
    panel = function (devNo)
      local time  = luup.variable_get (sid.security, "LastTrip", devNo)
      return div {class = "w3-tiny w3-display-bottomright", time and todate(time) or ''}
    end},

--
-- Netatmo
--

  Netatmo = {
    control = function ()
      return "<p>Netatmo controls</p>"
    end},

--
-- Power Meter
--

  PowerMeter = {
    panel = function (devNo)
      local watts = luup.variable_get (sid.energy, "Watts", devNo)
      local time  = luup.variable_get (sid.energy, "KWHReading", devNo)
      local kwh   = luup.variable_get (sid.energy, "KWH", devNo)
      return h.span {watts or '???', " Watts", h.br(), kwh or '???', " kWh", h.br(), 
        div {class = "w3-tiny w3-display-bottomright", time and todate(time) or "---  00:00"}}
    end},

--
-- SceneController
--

  SceneController = {
    panel = function (devNo)
      local time = luup.variable_get (sid.scene, "LastSceneTime", devNo)
      return h.span (time and todate(time) or '')
    end,
    control = function ()
      return "<p>Scene Controller displays</p>"
    end},
    
--
-- Weather (NB. this is the device type for the DarkSkyWeather plugin)
--

  Weather = {
    control = function (devNo)  
      local sid = "urn:upnp-micasaverde-com:serviceId:Weather1"
      local class = "w3-card w3-margin w3-round w3-padding"
      
      local function items (list)
        local t = h.table {class="w3-small"}
        for _, name in ipairs (list) do 
          local v = luup.variable_get (sid, name, devNo)
          t.row {name:gsub ("(%w)([A-Z])", "%1 %2"), v} 
        end
        return t
      end
      
      local conditions = items {"CurrentConditions", "TodayConditions", "TomorrowConditions", "WeekConditions"}
      local current = items {"CurrentTemperature", "CurrentHumidity", "CurrentDewPoint", "PrecipIntensity", "WindSpeed", 
                "PrecipType", "PrecipProbability", "WindBearing", "Ozone", "ApparentTemperature", "CurrentCloudCover"}
      local today = items {"TodayLowTemp", "TodayHighTemp", "TodayPressure"}
      local tomorrow = items {"TomorrowLowTemp", "TomorrowHighTemp", "TomorrowPressure"}
      
      return 
        div { class = "w3-row",
          div {class = class, h.h5 "General Conditions", conditions},
          div {class = "w3-half", 
            div {class = class, h.h5 "Now", current} },
          div {class = "w3-row w3-half",
            div {class = class, h.h5 "Today", today},
            div {class = class, h.h5 "Tomorrow", tomorrow} } }
    end},
 
}

--
-- aliases
--

panels.DoorSensor = panels.MotionSensor


return panels

