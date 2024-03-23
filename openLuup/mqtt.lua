local ABOUT = {
  NAME          = "openLuup.mqtt",
  VERSION       = "2024.03.22",
  DESCRIPTION   = "MQTT v3.1.1 QoS 0 server",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2020-2024 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2020-2024 AK Booer

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

--
-- MQTT Message Queuing Telemetry Transport for openLuup
--

-- 2021.01.31   original version
-- 2021.02.17   add login credentials
-- 2021.03.02   handle all wildcards ending with #
-- 2021.03.14   add TryPrivate flag in connection protocol for server bridging with Mosquitto (thanks @Buxton)
--              see: https://smarthome.community/topic/316/openluup-mqtt-server/74
--              and: https://mosquitto.org/man/mosquitto-conf-5.html
-- 2021.03.17   add UDP -> MQTT bridge
-- 2021.03.19   add extra parameter to register_handler() (thanks @therealdb)
--              see: https://smarthome.community/topic/316/openluup-mqtt-server/81
-- 2021.03.20   EXTRA checks with socket.select() to ensure socket is OK to send
-- 2021.03.24   EXTRA checks moved to io.server.open()

-- 2021.04.08   add subscriber for relay/nnn topic (with 0 or 1 message)
-- 2021.04.28   add subscriber for light/nnn topic (with 0-100 message)
-- 2021.04.30   add 'query' topic to force specific variable update message (after connect, for example)
-- 2021.08.16   fix null topic in publish (thanks @ArcherS)

-- 2022.11.28   use "****" for Username / Password in debug message (on suggestion of @a-lurker)
-- 2022.12.02   Fix response to QoS > 0 PUBLISH packets, thanks @Crille and @toggledbits
-- 2022.12.05   Add PUBCOMP as response to QoS 2 PUBREL
-- 2022.12.09   Improve error messages in MQTT_packet.receive()

-- 2023.12.21   Correct variable length header size to four (not three) byte (thanks @a-lurker)

-- 2024.02.09   Suppress fixed header byte read errors
-- 2024.03.09   Separate generic mqtt_lutil.lua from this server code
-- 2024.03.14   New subscriptions module in util: wildcard '+' now implemented
-- 2024.03.15   Fix retained messages for wildcard subscriptions
-- 2024.03.21   Implement KeepAlive timeout watchdog


-- see OASIS standard: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.pdf
-- Each conformance statement has been assigned a reference in the format [MQTT-x.x.x-y]

local logs      = require "openLuup.logs"
local tables    = require "openLuup.servertables"     -- for myIP and serviceIds
local ioutil    = require "openLuup.io"               -- for core server functions
local scheduler = require "openLuup.scheduler"        -- for current_device() and context_switch()
local timers    = require "openLuup.timers"           -- for client watchdog()
local util      = require "openLuup.mqtt_util"        -- MQTT utilities

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

local iprequests = {}

local SID = tables.SID

-------------------------------------------
--
-- MQTT servlet
--

local MQTT_packet = util.MQTT_packet        -- MQTT formats, etc.
local parse = util.parse                    -- Parse and process MQTT packets
local Subscriptions = util.Subscriptions    -- subscription handling

local function Server()
  
  local stats = {
        ["bytes/received"] = 0,             -- bytes received since the broker started.
        ["bytes/sent"] = 0,                 -- bytes sent since the broker started.
        ["clients/connected"] = 0,          -- currently connected clients.
        ["clients/maximum"] = 0,            -- maximum number of clients that have been connected to the broker at the same time.
        ["clients/total"] = 0,              -- active and inactive clients currently connected and registered.
        ["messages/received"] = 0,          -- messages of any type received since the broker started.
        ["messages/sent"] = 0,              -- messages of any type sent since the broker started.
        ["publish/messages/received"] = 0,  -- PUBLISH messages received since the broker started.
        ["publish/messages/sent"] = 0,      -- PUBLISH messages sent since the broker started.
        ["retained/messages/count"] = 0,    -- total number of retained messages active on the broker.
      }
  
  local subs = Subscriptions()      -- new subscription handler
  
  local retained = {}               -- table of retained messages indexed by topic
  
  local clients = {}                -- table indexed by client with last message time
  
  local function unsubscribe_client_from_topics (client, topics)
    local name = tostring(client)
    local message = "%s UNSUBSCRIBE from %s %s"
    for topic in pairs (topics) do
      subs: unsubscribe(client, topic)
      _log (message: format (client.MQTT_connect_payload.ClientId or '?', topic, name))
    end
  end

  local function close_and_unsubscribe_from_all (client, log_message)
    client: close()
    clients[client] = nil
    if log_message then _log (table.concat {log_message, ' ', tostring(client)}) end
    local name = tostring(client)
    local message = "%s UNSUBSCRIBE from ALL %s"
    subs: unsubscribe(client)               -- nil topic means ALL those subscribed by client
    _log (message: format (client.MQTT_connect_payload.ClientId or '?', name))
  end
  
  local function send_to_client (client, message)
    local ok, err = true
    local closed = client.closed            -- client.closed is created by io.server
    if not closed then
      ok, err = client: send (message)      -- don't try to send to closed socket
    end
    if closed or not ok then
      close_and_unsubscribe_from_all (client, err)
    else
      -- statistics
      stats["bytes/sent"] = stats["bytes/sent"] + #message
      stats["messages/sent"] = stats["messages/sent"]  + 1    
    end
    return ok, err
  end

  local internal_client = 0
  
  -- register an internal (openLuup), or external, subscriber to a topic
  local function subscribe(subscription)
    local topic = subscription.topic
    local client = subscription.client
    if not client then             -- numeric key for internal (since callback not unique)
      internal_client = internal_client + 1
      client = internal_client
    end
    subs: subscribe(client, topic, subscription)
    return 1
  end

  -- register an openLuup-side subscriber to a single topic
  local function register_handler (callback, topic, parameter)
    subscribe {
      callback = callback, 
      devNo = scheduler.current_device (),
      parameter = parameter,
      topic = topic,
      count = 0,
    }
    -- TODO: retrieve retained messages??
    return 1
  end

  --[[

  [MQTT-3.3.1-6]
  When a new subscription is established, the last retained message, if any, 
  on each matching topic name MUST be sent to the subscriber.

  [MQTT-3.3.1-8]
  When sending a PUBLISH Packet to a Client the Server MUST set the RETAIN flag to 1 
  if a message is sent as a result of a new subscription being made by a Client.

  [MQTT-3.3.1-9]
  It MUST set the RETAIN flag to 0 when a PUBLISH Packet is sent to a Client because it matches 
  an established subscription regardless of how the flag was set in the message it received.

  --]]

  -- subscribe as external (IP) clients (note that SUBACK will already have been sent)
  local function subscribe_client_to_topics (client, topics)
    local name = tostring(client)
    local message = "%s SUBSCRIBE to %s %s"
    for topic in pairs (topics) do
      subscribe {
        client = client, 
        topic = topic,
        count = 0,
      }
      local client_id = client.MQTT_connect_payload.ClientId or '?'
      _log (message: format (client_id, topic, name))
      
      -- send any RETAINED message for this topic
      for topic, retained_message in pairs(retained) do
        local subscribers = subs: subscribers(topic)      -- who is subscribed to this retained message... ?
        if subscribers[client] then                       -- our client is!
          local control_flags = 1 -- format message with RETAIN bit set
          local message = MQTT_packet.PUBLISH (topic, retained_message, control_flags)
          send_to_client (client, message) -- publish to external subscribers
          _log ("... sent retained topic: " .. topic)
        end
      end
    end

  end

  --[[
  [MQTT-3.3.1-5]
  If the RETAIN flag is set to 1, in a PUBLISH Packet sent by a Client to a Server, 
  the Server MUST store the Application Message and its QoS, 
  so that it can be delivered to future subscribers whose subscriptions match its topic name.

  [MQTT-3.3.1-7]
  If the Server receives a QoS 0 message with the RETAIN flag set to 1 
  it MUST discard any message previously retained for that topic. 
  It SHOULD store the new QoS 0 message as the new retained message for that topic, 
  but MAY choose to discard it at any time - if this happens there will be no retained message for that topic.

  [MQTT-3.3.1-10]
  A PUBLISH Packet with a RETAIN flag set to 1 and a payload containing zero bytes will be processed 
  as normal by the Server and sent to Clients with a subscription matching the topic name. 
  Additionally any existing retained message with the same topic name MUST be removed 
  and any future subscribers for the topic will not receive a retained message.

  [MQTT-3.3.1-11]
  A zero byte retained message MUST NOT be stored as a retained message on the Server.

  [MQTT-3.3.1-12]
  If the RETAIN flag is 0, in a PUBLISH Packet sent by a Client to a Server, 
  the Server MUST NOT store the message and MUST NOT remove or replace any existing retained message.
  --]]
  
  -- message object with formatted MQTT_packet created on demand (and then cached for multiple sends)
  local function Message (TopicName, ApplicationMessage, Retained)
    local meta = {}
    function meta:__index ()
      local msg = MQTT_packet.PUBLISH (TopicName, ApplicationMessage, Retained)
      self.MQTT_packet = msg   -- save packet so we won't be called again
      return msg
    end
    local message = {
      TopicName = TopicName, 
      ApplicationMessage = ApplicationMessage, 
      Retained = Retained}
    return setmetatable (message, meta)
  end
  
  -- deliver message to all subscribers
  local function publish (TopicName, ApplicationMessage, Retained)
    if #TopicName == 0 then return end
    
    -- handle retained topics [MQTT-3.3.1-5/7/10/11/12]
    if Retained then 
      retained[TopicName] = (#ApplicationMessage > 0) and ApplicationMessage or nil
    end
    
    -- statistics
    stats["publish/messages/received"] = stats["publish/messages/received"] + 1

    -- publish message to single subscriber
    local function publish_to_one (subscriber, message)
      local s, m = subscriber, message
      s.count = (s.count or 0) + 1
      local ok, err
      if s.callback then
        ok, err = scheduler.context_switch (s.devNo, s.callback, m.TopicName, m.ApplicationMessage, s.parameter, m.Retained)
      elseif s.client then
        ok, err = send_to_client (s.client, m.MQTT_packet) -- publish to external subscribers
        if ok then 
          stats["publish/messages/sent"] = stats["publish/messages/sent"] + 1
        end
      end
      return ok, err
    end
    
    -- publish message to all subscribers
    
    local subscribers = subs:subscribers(TopicName)
    local message = Message (TopicName, ApplicationMessage)
    
    local ok, err 
    for _, subscription in pairs (subscribers) do
      ok, err = publish_to_one (subscription, message)
      if not ok then
        _log (table.concat {"ERROR publishing application message for mqtt:", TopicName, " : ", err})
      else
--        _debug ("Successfully published: " .. TopicName)
      end
    end

  end

  return {
      stats = stats,
      retained = retained,
      clients = clients,
      
      TEST = {
          subscribed = subs.subscribed,
          published = subs.published,
        },
      
      register_handler = register_handler,      -- callback for subscribed messages
      publish = publish,                        -- publish from within openLuup
      
      send_to_client = send_to_client,          -- send to a specific client
      
      subscribe_client_to_topics = subscribe_client_to_topics,
      unsubscribe_client_from_topics = unsubscribe_client_from_topics,
      close_and_unsubscribe_from_all = close_and_unsubscribe_from_all,
    }
    
end

 
-------------------------------------------
--
-- Generic MQTT incoming message handler
--

local function reserved(message)
  return nil, "UNIMPLEMENTED packet type: " .. message.packet_type
end

local function incoming (client, credentials, server)
  
  local ack
  local pname = "RECEIVE ERROR"
  local message, errmsg = MQTT_packet.receive (client)
  
  if message then
    pname = message.packet_name
    _debug (pname, ' ', tostring(client))
    
    -- statistics
    local stats = server.stats
    stats["bytes/received"] = stats["bytes/received"] + message.length
    stats["messages/received"] = stats["messages/received"] + 1    
    
    -- analyze the message
    local topic, app_message, retain
    local process = parse[pname] or reserved
    
    -- ack is an acknowledgement package to send back to the client
    -- errmsg signals an error requiring the client connection to be closed
    -- topic may be a list for (un)subscribe, or a single topic to publish
    -- app_message is the appplication message for publication
    -- retain is true for retained messages
    ack, errmsg, topic, app_message, retain = process (message, credentials)    -- credentials used for CONNECT authorization
    
    -- send an ack if required
    if ack then
      server.send_to_client (client, ack)
--      _debug (MQTT_packet.name (ack))
    end
    
    if topic then
      
      if pname == "PUBLISH" then
        
        -- publish topic to subscribers
        server.publish (topic, app_message, retain)
        _debug("topic", topic)
      
      elseif pname == "SUBSCRIBE" then
        
        -- add any subscriber to table of topics
        server.subscribe_client_to_topics (client, topic)
        _debug("topic", (next(topic)))
       
      elseif pname == "UNSUBSCRIBE" then
        
        -- unsubscribe external (IP) clients
        server.unsubscribe_client_from_topics (client, topic)
        _debug("topic", (next(topic)))
        
      elseif pname == "CONNECT" then
        
        -- save connect payload (returned as table in topic) in client object (chiefly for accessing the ClientId)
        client.MQTT_connect_payload = topic
        _debug("client", topic.ClientId)
      end
    end
  end
  
  -- disconnect client on error
  if errmsg then
    errmsg = (#errmsg > 0) and table.concat {pname, ": ", errmsg} 
    server.close_and_unsubscribe_from_all (client, errmsg)
  end
end


-------------------------------------------
--
-- MQTT server
--

-- create additional MQTT servers (on different ports - or no port at all!)
local function new (config, server)  
  config = config or {}
  
  local credentials = {                     -- pull credentials from the config table (not used by ioutil.server)
      Username = config.Username or '',
      Password = config.Password or '',
    }
    
  server = server or Server()               -- existing, or a whole new server
  local clients = server.clients            -- table indexed by client with last message time
  
  local function servlet(client)
    return function () 
      clients[client] = os.time()           -- record time of latest client message
      incoming (client, credentials, server) 
    end
  end
  
  local port = config.Port  
  
  if port then                                            -- possible to create a purely internal MQTT 'server'
    local name = "MQTT:" .. port
    
    ioutil.server.new {
        port      = port,                                 -- incoming port
        name      = name,                                 -- server name
        backlog   = config.Backlog or 100,                -- queue length
        idletime  = config.CloseIdleSocketAfter or 120,   -- connect timeout
        servlet   = servlet,                              -- our own servlet
        connects  = iprequests,                           -- use our own table for console info
      }
 
--[[
  [MQTT-3.1.2-24]
  If the Keep Alive value is non-zero and the Server does not receive a Control Packet from the Client within 
  one and a half times the Keep Alive time period, it MUST disconnect the Network Connection to the Client 
  as if the network had failed .
--]]
    local timeout_message = "KeepAlive = %d. last seen at %s %s %s"
    local function client_watchdog()
--      _log ("client timeout watchdog: " .. name)
      local now = os.time()
      for client, time in pairs(clients) do
        local payload = client.MQTT_connect_payload
        local KeepAlive = payload.KeepAlive
--        _debug(timeout_message:format(KeepAlive, os.date("%X", time), payload.ClientId, tostring(client)))
        if KeepAlive and (os.difftime(now, time) > KeepAlive * 1.5) then
          clients[client] = nil
          _log(timeout_message:format(KeepAlive, os.date("%X - TIMEOUT -", time), payload.ClientId, tostring(client)))
          server.close_and_unsubscribe_from_all (client, "WARNING: client timeout")
        end
      end
      timers.call_delay (client_watchdog, 60, '', name .. " client watchdog")   -- call again later
    end
    
    client_watchdog()                                     -- start watching for client timeouts      
  end
    
  return {
      statistics = server.stats,
      retained = server.retained,
      clients = clients,
      
      TEST = {
          subscribed = server.TEST.subscribed,
          published = server.TEST.published,
        },
      
      -- note that these instance methods should be called with the colon syntax
      subscribe = function (_, ...) server.register_handler (...) end,     -- callback for subscribed messages
      publish = function (_, ...) server.publish (...) end,                -- publish from within openLuup
    }
end


-- start main openLuup MQTT server

local server = Server()   -- create it first

local function start (config)

  ABOUT.DEBUG = config.DEBUG 
  config.port = config.Port or 1883
  
  local new_server = new(config, server)      -- use main server, already created
  
  do -- UDP-MQTT bridge
    -- callback function is called with (port, {datagram = ..., ip = ...}, "udp")
    -- datagram format is topic/=/message
    local function UDP_MQTT_bridge (_, data)
      local topic, message = data.datagram: match "^(.-)/=/(.+)"
      if topic then 
        server.publish (topic, message) 
      end
    end
    
    if tonumber (config.Bridge_UDP) then                  -- start UDP-MQTT bridge
      ioutil.udp.register_handler (UDP_MQTT_bridge, config.Bridge_UDP)
    end
  end
  
  return new_server
end


------------------------
--
-- MQTT subscriber for Shelly-like commands
--
-- relay
--

local function mqtt_command_log (topic, message)
  _log (table.concat {"MQTT COMMAND: ", topic," = ", message})
end  
-- easy MQTT request to switch a switch
local function mqtt_relay (topic, message)
  mqtt_command_log (topic, message)
  local d = tonumber (topic: match "^relay/(%d+)")
  local n = tonumber (message)
  if d and n then 
    luup.call_action (SID.switch, "SetTarget", {newTargetValue = n}, d)
  end
end

-- easy MQTT request to change dimmer level
local function mqtt_light (topic, message)
  mqtt_command_log (topic, message)
  local d = tonumber (topic: match "^light/(%d+)")
  local n = tonumber (message)
  if d and n then 
    luup.call_action (SID.dimming, "SetLoadLevelTarget", {newLoadlevelTarget = n}, d)
  end
end

-- easy MQTT request to query a variable (forces publication of an update)
local function mqtt_query (topic, message)
  mqtt_command_log (topic, message)
  local d, s, v = message: match "^(%d+)%.([^%.]+)%.(.+)"
  d = tonumber(d)
  if d then 
    local val = luup.variable_get (SID[s] or s, v, d)
    if val then
      server.publish (table.concat ({"openLuup/update",d,s,v}, '/'), val)
    end
  end
end

do -- MQTT commands
  local register_handler = server.register_handler
  register_handler (mqtt_relay, "relay/#")
  register_handler (mqtt_light, "light/#")
  register_handler (mqtt_relay, "openLuup/relay/#")
  register_handler (mqtt_light, "openLuup/light/#")
  register_handler (mqtt_query, "openLuup/query")
end


--- return module variables and methods
return setmetatable ({
    ABOUT = ABOUT,
    
    -- constants
    myIP = tables.myIP,
    
    -- methods
    start = start,
    register_handler = server.register_handler,  -- callback for subscribed messages
    publish = server.publish,                    -- publish from within openLuup
    
    new = new,       -- create another new MQTT server
    
    -- variables
    statistics = server.stats,
    retained = server.retained,

  },{
  
  -- hide some of the more esoteric data structures, only used internally by openLuup
  
    __index = {
          
    TEST = {          -- for testing only
        packet = MQTT_packet,
        parse = parse,
        server = server,
      },
    
    iprequests  = iprequests,
    subscribers = server.TEST.subscribed,
    
  }})
