-- Example startup.lua

do -- define top-level attributes required to personalise the installation  
  local attr = luup.attr_set
  
  attr ("City_description", "Oxford")
  attr ("Country_description", "UNITED KINGDOM")
  attr ("KwhPrice", "0.15")
  attr ("PK_AccessPoint", "88800127")   -- TODO: use machine serial number?
  attr ("Region_description", "England")
  attr ("TemperatureFormat", "C")
  
  attr ("currency", "£")
  attr ("date_format", "dd/mm/yy")
  attr ("latitude", "51.00")
  attr ("longitude", "-1.00")
  attr ("model", "BeagleBone Black")
  attr ("timeFormat", "24hr")
  attr ("timezone", "0")
end

do -- create rooms (strangely, there's no Luup command to do this directly)
 local function room(n) 
   luup.inet.wget ("127.0.0.1:3480/data_request?id=room&action=create&name="..n) 
 end  
  room "Upstairs"			-- these are persistent across restarts
  room "Downstairs" 
end

do -- ALTUI
  local dev = luup.create_device ('', "ALTUI", "ALTUI", "D_ALTUI.xml")
end

do -- ARDUINO      
--   local dev = luup.create_device ('', "Arduino", "Arduino", "D_Arduino1.xml")        
--   luup.ip_set ("172.16.42.21", dev)       -- your Arduino gateway IP address  
end

do -- the VERA BRIDGE !!
--   local dev = luup.create_device ('', "Vera", "Vera", "D_VeraBridge.xml")
--   luup.ip_set ("172.16.42.10", dev)         -- set remote Vera IP address
end

-- set up whatever Startup Lua code you normally need here
luup.attr_set ("StartupCode", [[

luup.log "Hello from my very own startup code"

]])

----------- 

