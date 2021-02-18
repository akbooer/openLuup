local ABOUT = {
  NAME          = "openLuup.mqtt",
  VERSION       = "2021.02.17",
  DESCRIPTION   = "MQTT QoS 0 server",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2020-2021 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2020-2021 AK Booer

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


-- see OASIS standard: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.pdf
-- Each conformance statement has been assigned a reference in the format [MQTT-x.x.x-y]

local logs      = require "openLuup.logs"
local tables    = require "openLuup.servertables"     -- for myIP
local ioutil    = require "openLuup.io"               -- for core server functions
local scheduler = require "openLuup.scheduler"
--local socket    = require "socket"

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

local iprequests = {}

local credentials = {
    Username = '',        -- possibly modified by start()
    Password = '',
  }

local subscribers = {}    -- list of subscribers, indexed by topic

local function unsubscribe_client_from_topic (client, topic)
  local name = tostring(client)
  local message = "Unsubscribed from %s %s"
  local subs = subscribers[topic] 
  if not subs then return end
  for i = #subs, 1, -1 do
    if subs[i] == client then 
      table.remove (subs, i)
      _log (message: format (topic, name))
    end
  end
end

local function close_and_unsubscribe_from_all (client, log_message)
  client: close()
  if log_message then _log (table.concat {log_message, ' ', tostring(client)}) end
  for topic in pairs (subscribers) do
    unsubscribe_client_from_topic (client, topic)
  end
end

-------------------------------------------
--
-- MQTT servlet
--

--[[
  Structure of an MQTT Control Packet:
    Fixed header, present in all MQTT Control Packets 
    Variable header, present in some MQTT Control Packets 
    Payload, present in some MQTT Control Packets
--]]

-- control packet names: an ordered list, 1 - 15.
local packet_name = {
    "CONNECT", "CONNACK", "PUBLISH", 
    "PUBACK", "PUBREC", "PUBREL", "PUBCOMP", 
    "SUBSCRIBE", "SUBACK", "UNSUBSCRIBE", "UNSUBACK", 
    "PINGREQ", "PINGRESP",
    "DISCONNECT"
  }

-- packet type
local ptype = {}
for i, name in ipairs (packet_name) do
  ptype[name] = i
end


-- split flag char into individual boolean bits (default is 8 bits)
local function parse_flags (x, n)
  n = n or 8
  if type(x) == "string" then x = x:byte() end    -- convert to number
  local bits = {}
  for i = n,1,-1 do
    local b = x % 2
    x = (x - b) / 2
    bits[i] = b 
  end
  return bits
end

local function parse_packet_type (header)
  -- byte 1: MQTT Control Packet type / Flags specific to each MQTT Control Packet type
  local a = string.byte (header)
  local nibble = 0x10
  local packet_type = math.floor (a / nibble)
  local flags = parse_flags (a % nibble, 4)
  return packet_type, flags
end

local function bytes2word (bytes)
  local msb, lsb = bytes: byte (1, 2)
  return msb * 0x100 + lsb
end

-- return 16-bit word as a two-byte string
local function word2bytes (word)
  word = word % 0x10000
  local msb = math.floor (word / 0x100)
  local lsb = word % 0x100
  return string.char (msb, lsb)
end

local function read_word (msg)
  return bytes2word (msg: read_bytes (2))
end

-- prepend a string (assumed UTF-8) with its length
local function encode_utf8 (txt)
  local length = word2bytes (#txt)
  return length .. txt
end

-- read string from message
local function read_utf8 (msg)
  local n = msg: read_word ()      -- length of this string
  return msg: read_bytes (n)
end

-- read next n bytes from message
local function read_bytes (msg, n)
  local i = msg.ptr + 1
  local j = msg.ptr + n
  local b = msg.body
  if #b >= j then
    msg.ptr = j
    return b: sub (i,j)
  end
end
  
-- prepare message for transmission
local function encode_message (packet_type, control_flags, variable_header, payload)
  variable_header = variable_header or ''
  payload = payload or ''
  packet_type = ptype[packet_type] or packet_type   -- convert to number if string type
  local length = #variable_header + #payload
  
  local nibble = 0x10
  local byte1 = (packet_type % nibble) * nibble + (control_flags % nibble)
  local bytes = {string.char (byte1)}       -- first part of fixed header
  repeat
    local encodedByte = length % 128
    length = math.floor (length / 128)
    -- if there are more data to encode, set the top bit of this byte 
    bytes[#bytes+1] = string.char (encodedByte + (length > 0 and 128 or 0))
  until length == 0
  local fixed_header = table.concat (bytes)
  
  return table.concat {fixed_header, variable_header, payload}
end


-- receive returns result or throws error
local function receive (client)
  local function try_read (length)    
--    luup.log ("TRY_READ: " .. length)
    local ok, err = client: receive(length)
    if not ok then
      close_and_unsubscribe_from_all (client, err)
    end
    return ok, err
  end
  
  local fixed_header_byte1 = try_read(1)
  local packet_type, control_flags = parse_packet_type (fixed_header_byte1)

  local length = 0
  for i = 0, 2 do                   -- maximum of 3 bytes encode remaining length, LSB first
    local b = try_read(1)
    b = b: byte()
    local n = b % 128               -- seven significant bits
    length = length + n * 128 ^ i
    if b < 128 then break end
  end
  
  local body = (length > 0) and try_read(length) or ''
  
  return {
      packet_type   = packet_type,
      control_flags = control_flags,
      body          = body,           -- may include variable header and payload
      ptr           = 0,              -- pointer to parse position in body
      read_bytes    = read_bytes,
      read_word     = read_word,
      read_string   = read_utf8,
    }
end

-- register an internal (openLuup), or external, subscriber to a topic
-- wildcards not (yet) implemented
local function subscribe(subscription)
  local topic = subscription.topic
  local subs = subscribers[topic] or {}
  subscribers[topic] = subs
  subs[#subs+1] = subscription
  return 1
end

local function send_to_client (client, message)
  local ok, err = client: send (message)
  if not ok then
    close_and_unsubscribe_from_all (client, err)
  end
  return ok, err
end

-- publish to MQTT client socket (with QoS = 0)
local function publish (client, TopicName, ApplicationMessage)
  
  -- FIXED HEADER
  local packet_type = "PUBLISH"
  local control_flags = 0               -- QoS = 0
  
  -- VARIABLE HEADER
  local variable_header = encode_utf8 (TopicName)   -- No packetId, since QoS = 0
  
  -- PAYLOAD
  local payload = ApplicationMessage
  
  local message = encode_message (packet_type, control_flags, variable_header, payload)
  local ok, err = send_to_client (client, message)
  
  return ok, err
end

-- register an openLuup-side subscriber to a topic
local function register_handler (callback, topic)
  subscribe {
        callback = callback, 
        devNo = scheduler.current_device (),
        topic = topic,
        count = 0,
      }
  return 1
end

-- publish message to all subscribers
local function publish_to_all (subscribers, TopicName, ApplicationMessage)
  for _, subscriber in ipairs (subscribers or {}) do
    local s = subscriber
    s.count = (s.count or 0) + 1
    local ok, err
    if s.callback then
      ok, err = scheduler.context_switch (s.devNo, s.callback, TopicName, ApplicationMessage)
    elseif s.client then
      ok, err = publish (s.client, TopicName, ApplicationMessage) -- publish to external subscribers
    end

    if not ok then
      _log (table.concat {"ERROR publishing application message for mqtt:", TopicName, " : ", err})
    else
--      _log ("Successfully published: " .. TopicName)
    end
  end
end

-- deliver message to all subscribers
local function deliver (TopicName, ApplicationMessage)
--  _log ("TopicName: " .. TopicName)
--  _log ("ApplicationMessage: ".. (ApplicationMessage or ''))
  
  publish_to_all (subscribers[TopicName], TopicName, ApplicationMessage)    -- topic subscribers
  
  publish_to_all (subscribers['#'], TopicName, ApplicationMessage)          -- wildcards
  
end

local send = {}       -- only implement functionality required by server

function send.CONNECT () end          -- client only

--[[
    MQTT Connection Return Codes
    [0] = "Connection Accepted",
    [1] = "Connection Refused, unacceptable protocol version",
    [2] = "Connection Refused, identifier rejected",
    [3] = "Connection Refused, Server unavailable",
    [4] = "Connection Refused, bad user name or password",
    [5] = "Connection Refused, not authorized",
--]]
function send.CONNACK (client, ConnectReturnCode)
  -- If CONNECT validation is successful the Server MUST acknowledge the CONNECT Packet 
  -- with a CONNACK Packet containing a zero return code [MQTT-3.1.4-4]     
  -- If the Server does not have stored Session state, it MUST set Session Present to 0 in the CONNACK packet [MQTT-3.2.2-3]
  local packet_type, control_flags = "CONNACK", 0 
  
  local SessionPresent = 0                      -- QoS 0 means that there will be no Session State
  ConnectReturnCode = ConnectReturnCode or 0
  local variable_header = string.char (SessionPresent, ConnectReturnCode)
  
  local connack = encode_message (packet_type, control_flags, variable_header)    -- connack has no payload
  send_to_client (client, connack)
  
  -- If a server sends a CONNACK packet containing a non-zero return code it MUST then close the Network Connection [MQTT-3.2.2-5]
  if ConnectReturnCode ~= 0 then
    _log (table.concat {"Closing client connect, return code: ", ConnectReturnCode, ' ', tostring(client)})
    client: close()
  end
end

function send.PUBLISH () end

function send.PUBACK ()  end          -- not implemented (only required for QoS > 0)
function send.PUBREC ()  end          -- ditto
function send.PUBREL ()  end          -- ditto
function send.PUBCOMP () end          -- ditto

function send.SUBSCRIBE () end        -- client only

function send.SUBACK (client, QoS_list, msb, lsb) 
  -- When the Server receives a SUBSCRIBE Packet from a Client, the Server MUST respond with a SUBACK Packet [MQTT-3.8.4-1]
  -- The SUBACK Packet MUST have the same Packet Identifier as the SUBSCRIBE Packet that it is acknowledging [MQTT-3.8.4-2]
  local control_flags = 0
  local variable_header = string.char (msb, lsb)      -- PacketID
  local payload = QoS_list
  local suback = encode_message ("SUBACK", control_flags, variable_header, payload)
  send_to_client (client, suback)
end

function send.UNSUBSCRIBE () end      -- client only

function send.UNSUBACK () end

function send.PINGREQ () end          -- client only

function send.PINGRESP (client) 
  -- The Server MUST send a PINGRESP Packet in response to a PINGREQ packet [MQTT-3.12.4-1]
  local pingresp = string.char (13 * 0x10, 0)
  send_to_client (client, pingresp)
end

function send.DISCONNECT () end      -- client only

local rcv = {}


function rcv.DISCONNECT(client)
  -- After sending a DISCONNECT Packet the Client MUST close the Network Connection [MQTT-3.14.4-1]
  close_and_unsubscribe_from_all (client, "Disconnect received from client")
end

function rcv.CONNECT(client, message)
  --  the first Packet sent from the Client to the Server MUST be a CONNECT Packet [MQTT-3.1.0-1]    
  
  -- VARIABLE HEADER
  
  -- If the protocol name is incorrect the Server MAY disconnect the Client
  local ProtocolName = message: read_string()                     -- bytes 1-6
  if ProtocolName ~= "MQTT" then 
    close_and_unsubscribe_from_all (client, "Unknown protocol name: '" .. ProtocolName .. "'") 
    return 
  end
  
  -- protocol level should be 4 for MQTT 3.1.1
  local protocol_level = message: read_bytes (1) : byte()         -- byte 7
  if protocol_level ~= 4 then 
    close_and_unsubscribe_from_all (client, "Protocol level is not 3.1.1") 
    return 
  end
  
  local connect_flags = parse_flags (message: read_bytes(1))      -- byte 8
  
  local KeepAlive, Username, Password, 
          WillRetain, WillQoSmsb, WillQoSlsb, WillFlag,
          Clean, Reserved, WillQoS
  
  KeepAlive = message: read_word()                                -- bytes 9-10
  
  Username, Password, 
          WillRetain, WillQoSmsb, WillQoSlsb, WillFlag, 
          Clean, Reserved
            = unpack (connect_flags)
  WillQoS = 2 * WillQoSmsb + WillQoSlsb
  
  -- If invalid flags are received, the receiver MUST close the Network Connection [MQTT-2.2.2-2]
  -- The Server MUST validate that the reserved flag in the CONNECT Control Packet is set to zero 
  -- and disconnect the Client if it is not zero.[MQTT-3.1.2-3]
  if Reserved ~= 0 then   
    close_and_unsubscribe_from_all (client, "Reserved flag is not zero") 
    return 
  end
  
  -- PAYLOAD
  
  local ConnectReturnCode = 0                       -- default to success
  local ClientId, WillTopic, WillMessage
  
  ClientId    = message: read_string()              -- always present
  
  WillTopic   = WillFlag == 1 and message: read_string() or ''
  WillMessage = WillFlag == 1 and message: read_string() or ''
  Username    = Username == 1 and message: read_string() or ''
  Password    = Password == 1 and message: read_string() or ''
  
-- If the User Name Flag is set to 0, a user name MUST NOT be present in the payload [MQTT-3.1.2-18]
-- If the User Name Flag is set to 1, a user name MUST be present in the payload [MQTT-3.1.2-19]
-- If the Password Flag is set to 0, a password MUST NOT be present in the payload [MQTT-3.1.2-20]
-- If the Password Flag is set to 1, a password MUST be present in the payload [MQTT-3.1.2-21]

-- These fields, if present, MUST appear in the order 
--   Client Identifier, Will Topic, Will Message, User Name, Password [MQTT-3.1.3-1]

-- The Client Identifier (ClientId) MUST be present and MUST be the first field in the CONNECT packet payload [MQTT-3.1.3-3]
  _debug ("ClientId: " .. ClientId)
  _debug ("WillTopic: " .. WillTopic)
  _debug ("WillMessage: " .. WillMessage)
  _debug ("UserName: " .. Username)
  _debug ("Password: " .. Password)
  
  -- ACKNOWLEDGEMENT

  if Username ~= credentials.Username 
  or Password ~= credentials.Password then
    ConnectReturnCode = 4                   -- "Connection Refused, bad user name or password"
  end

  send.CONNACK (client, ConnectReturnCode)
end

function rcv.CONNACK()
  -- don't expect to receive a connack, since we don't connect to a server
end

function rcv.PUBLISH(_, message)
  
  local flags = message.control_flags
  local DUP, QoSmsb, QoSlsb, RETAIN
  DUP, QoSmsb, QoSlsb, RETAIN = unpack (flags)
  local QoS = 2 * QoSmsb + QoSlsb
  
  -- VARIABLE HEADER
  
  -- The Topic Name MUST be present as the first field in the PUBLISH Packet Variable header [MQTT-3.3.2-1]
  local TopicName = message: read_string ()
  
  -- PUBLISH (in cases where QoS > 0) Control Packets MUST contain a non-zero 16-bit Packet Identifier [MQTT-2.3.1-1]
  -- A PUBLISH Packet MUST NOT contain a Packet Identifier if its QoS value is set to 0 [MQTT-2.3.1-5]
  local PacketId        -- packet identifier
  if QoS > 0 then
    PacketId = message: read_word()
  end
  
  -- PAYLOAD
  
  local ApplicationMessage = message.body: sub(message.ptr + 1, -1)      -- remaining part of body
  deliver (TopicName, ApplicationMessage)
end

function rcv.PINGREQ (client)
  -- The Server MUST send a PINGRESP Packet in response to a PINGREQ packet [MQTT-3.12.4-1]
  send.PINGRESP (client)
end

function rcv.PINGRESP ()
  -- unlikely, since we don't send PINGREQ
end

function rcv.SUBSCRIBE (client, message)   
  -- Bits 3,2,1 and 0 of the fixed header of the SUBSCRIBE Control Packet are reserved 
  -- and MUST be set to 0,0,1 and 0 respectively [MQTT-3.8.1-1]
  local Reserved  = table.concat (message.control_flags) 
  if Reserved ~= "0010" then
    close_and_unsubscribe_from_all (client, "Unexpected reserved flag bits: " .. Reserved)
    return
  end
  
  -- VARIABLE HEADER
  
  -- SUBSCRIBE Control Packets MUST contain a non-zero 16-bit Packet Identifier [MQTT-2.3.1-1]
  local bytes = message: read_bytes (2)
  local msb, lsb = bytes: byte (1, 2)
  local PacketId
  PacketId = msb * 0x100 + lsb
  _debug ("Packet Id: " .. PacketId)
  
  -- PAYLOAD
  
  local topics = {}
  repeat
    local topic = message: read_string()
    topics[#topics+1] =topic
    _debug ("Topic: " .. topic)
    local RequestedQoS
    RequestedQoS = message: read_bytes(1) :byte()
--      _log ("Requested QoS: " .. RequestedQoS)
  until message.ptr >= #message.body
  
  -- The payload of a SUBSCRIBE packet MUST contain at least one Topic Filter / QoS pair [MQTT-3.8.3-3]
  if #topics == 0 then
    close_and_unsubscribe_from_all (client, "No topics found in SUBSCRIBE payload")
    return
  end
  
  -- subscribe as external (IP) clients
  for _, topic in ipairs (topics) do
    subscribe {
      client = client, 
      topic = topic,
      count = 0,
      }
  end
  
  -- ACKNOWLEDGEMENT
  -- When the Server receives a SUBSCRIBE Packet from a Client, the Server MUST respond with a SUBACK Packet [MQTT-3.8.4-1]
  -- The SUBACK Packet MUST have the same Packet Identifier as the SUBSCRIBE Packet that it is acknowledging [MQTT-3.8.4-2]
  local nt = #topics
  local QoS_list = string.char(0): rep (nt)
  send.SUBACK (client, QoS_list, msb, lsb)
end

  
local function start (config)

  local function reserved(_, message)
    _log ("UNIMPLEMENTED packet type: " .. message.packet_type)
    _log (message.body)
  end
  
  local function MQTTservlet (client)
     -- incoming() is called by the io.server when there is data to read
    local function incoming ()
      local message = receive (client)
      local pname = packet_name[message.packet_type] or "RESERVED"
      _debug (table.concat {pname, ' ', tostring(client)})
      local fct = rcv[pname]
      do (fct or reserved) (client, message) end
    end
    return incoming
  end

  
  -- start()
  ABOUT.DEBUG = config.DEBUG 
  credentials.Username = config.Username or ''
  credentials.Password = config.Password or ''
  
  -- returned server object has stop method, but we'll not be using it
  local port = config.Port or 1883
  return ioutil.server.new {
      port      = port,                                 -- incoming port
      name      = "MQTT:" .. port,                      -- server name
      backlog   = config.Backlog or 32,                 -- queue length
      idletime  = config.CloseIdleSocketAfter or 120,   -- connect timeout
      servlet   = MQTTservlet,                          -- our own servlet
      connects  = iprequests,                           -- use our own table for info
    }
  
end


--- return module variables and methods
return {
    ABOUT = ABOUT,
    
    TEST = {          -- for testing only
      bytes2word  = bytes2word,
      encode_utf8 = encode_utf8,
      encode_message = encode_message,
    },
    
    -- constants
    myIP = tables.myIP,
    
    -- methods
    start = start,
    register_handler = register_handler,              -- callback for subscribed messages
    publish = deliver,                                -- publish from within openLuup

    -- variables
    iprequests  = iprequests,
    subscribers = subscribers,

}