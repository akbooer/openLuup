local ABOUT = {
  NAME          = "openLuup.mqtt",
  VERSION       = "2023.12.21",
  DESCRIPTION   = "MQTT v3.1.1 QoS 0 server",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2020-2022 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  DEBUG         = false,
  LICENSE       = [[
  Copyright 2020-2022 AK Booer

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

-- see OASIS standard: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.pdf
-- Each conformance statement has been assigned a reference in the format [MQTT-x.x.x-y]

local logs      = require "openLuup.logs"
local tables    = require "openLuup.servertables"     -- for myIP and serviceIds
local ioutil    = require "openLuup.io"               -- for core server functions
local scheduler = require "openLuup.scheduler"        -- for current_device() and context_switch()

--  local _log() and _debug()
local _log, _debug = logs.register (ABOUT)

local iprequests = {}

local SID = tables.SID

-------------------------------------------
--
-- MQTT servlet
--

local MQTT_packet = {}

--[[
  Structure of an MQTT Control Packet:
    Fixed header, present in all MQTT Control Packets 
    Variable header, present in some MQTT Control Packets 
    Payload, present in some MQTT Control Packets
--]]

do -- MQTT Packet methods

  -- control packet names: an ordered list, 1 - 15.
  local pname = {
      "CONNECT", "CONNACK", 
      "PUBLISH", "PUBACK", "PUBREC", "PUBREL", "PUBCOMP", 
      "SUBSCRIBE", "SUBACK", "UNSUBSCRIBE", "UNSUBACK", 
      "PINGREQ", "PINGRESP",
      "DISCONNECT"
    }

  -- packet type
  local ptype = {}
  for i, name in ipairs (pname) do
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

  local function read_flag_byte (msg)
      return parse_flags (msg: read_bytes(1))      -- byte 8
  end
  
  local function read_word (msg)
    return bytes2word (msg: read_bytes (2))
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

  -- return 16-bit word as a two-byte string
  local function word2bytes (word)
    word = word % 0x10000
    local msb = math.floor (word / 0x100)
    local lsb = word % 0x100
    return string.char (msb, lsb)
  end

  -- prepend a string (assumed UTF-8) with its length
  local function encode_utf8 (txt)
    local length = word2bytes (#txt)
    return length .. txt
  end
    
  -- encode for transmission
  local function encode (packet_type, control_flags, variable_header, payload)
    variable_header = variable_header or ''
    control_flags = control_flags or 0
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

  local function encode_ack (packet_type, packet_id, payload) 
    -- generic acknowledgement
    local control_flags = 0
    local variable_header = packet_id and word2bytes (packet_id) or nil
    return encode (packet_type, control_flags, variable_header, payload)
   end

  -- receive returns messsage object, or error message
  function MQTT_packet.receive (client)
    
    local fixed_header_byte1, err = client: receive (1)
    if not fixed_header_byte1 then return nil, "(Fixed Header byte) " .. err end

    local nb = 1
    local length = 0
    for i = 0, 3 do                   -- maximum of 4 bytes encode remaining length, LSB first (2023.12.21 thanks @a-lurker)
      local b, err = client: receive (1)
      if not b then return nil, "(Remaining Length bytes) " .. err end
      nb = nb + 1
      b = b: byte()
      local n = b % 128               -- seven significant bits
      length = length + n * 128 ^ i
      if b < 128 then break end
    end
    
    local body = ''
    if length > 0 then
      body, err = (length > 0) and client: receive (length)
      if not body then return nil, "(Message body) " .. err end
      nb = nb + length
    end
    
    local packet_type, control_flags = parse_packet_type (fixed_header_byte1)
    local pname = pname[packet_type] or "RESERVED"
    
    return 
      {
        -- variables
        length          = nb,             -- byte count for statistics
        packet_type     = packet_type,
        control_flags   = control_flags,
        body            = body,           -- may include variable header and payload
        ptr             = 0,              -- pointer to parse position in body
        packet_name     = pname,          -- string name of packet type
        -- methods
        read_bytes      = read_bytes,
        read_flag_byte  = read_flag_byte, -- converting octet to 8 separate flag bits
        read_word       = read_word,
        read_string     = read_utf8,
      }

  end

  -------------------------------------------
  --
  -- Construct MQTT packets
  --


  function MQTT_packet.CONNECT (credentials)               -- CLIENT ONLY
    
    local C = credentials
    
    -- VARIABLE HEADER
    
    local ProtocolName = encode_utf8 "MQTT"                 -- bytes 1-6
    local ProtocolLevel = string.char(4)                    -- byte 7, set to 4 for MQTT 3.1.1
    
    local Username = C.Username and 1 or 0
    local Password = C.Password and 1 or 0
    local WillRetain = 0
    local WillQoSmsb, WillQoSlsb = 0, 0
    local WillFlag = C.WillTopic and C.WillMessage and 1 or 0
    local Clean = 1
    local Reserved = 0

    local ConnectFlags =                                    -- byte 8
      {Username, Password, WillRetain, WillQoSmsb, WillQoSlsb, WillFlag, Clean, Reserved}
    ConnectFlags = string.char(tonumber(table.concat(ConnectFlags), 2))
     
    local KeepAlive = word2bytes (C.KeepAlive or 0)         -- bytes 9-10
    
    local variable_header = table.concat {ProtocolName, ProtocolLevel, ConnectFlags, KeepAlive}
    
    -- PAYLOAD
    
    local ClientId    = encode_utf8 (C.ClientId or '')
    local WillTopic   = WillFlag == 1 and encode_utf8 (C.WillTopic)   or ''
    local WillMessage = WillFlag == 1 and encode_utf8 (C.WillMessage) or ''
    Username          = Username == 1 and encode_utf8 (C.Username)    or ''
    Password          = Password == 1 and encode_utf8 (C.Password)    or ''
    
    local payload = table.concat {ClientId, WillTopic, WillMessage, Username, Password}
    
    local control_flags = 0
    return encode ("CONNECT", control_flags, variable_header, payload)
  end
  
  function MQTT_packet.CONNACK (ConnectReturnCode)
    local control_flags = 0 
    
    local SessionPresent = 0                          -- QoS 0 means that there will be no Session State
    ConnectReturnCode = ConnectReturnCode or 0
    local variable_header = string.char (SessionPresent, ConnectReturnCode)
    
    return encode ("CONNACK", control_flags, variable_header)
  end

  function MQTT_packet.PUBLISH (TopicName, ApplicationMessage, control_flags) 
    -- publish to MQTT client socket (with QoS = 0)
    
    -- FIXED HEADER
    local packet_type = "PUBLISH"
    control_flags = control_flags or 0                -- default: DUP = 0, QoS = 0, RETAIN = 0
    
    -- VARIABLE HEADER
    local variable_header = encode_utf8 (TopicName)   -- No packetId, since QoS = 0
    
    -- PAYLOAD
    local payload = ApplicationMessage
    
    local publish = encode (packet_type, control_flags, variable_header, payload)
    return publish
  end
 
  function MQTT_packet.PUBACK (PacketId)              -- response to QoS 1 PUBLISH
    return encode_ack ("PUBACK", PacketId)
   end
  
  function MQTT_packet.PUBREC (PacketId)              -- 1st response to QoS 2 PUBLISH
    return encode_ack ("PUBREC", PacketId)
  end
  
  function MQTT_packet.PUBREL ()  end                 -- not implemented, we only ever send QoS 0
  
  function MQTT_packet.PUBCOMP (PacketId)             -- 2nd response to QoS 2 PUBREL         
    return encode_ack ("PUBCOMP", PacketId)
  end

  function MQTT_packet.SUBSCRIBE () end               -- client only

  function MQTT_packet.SUBACK (PacketId, QoS_list) 
    -- When the Server receives a SUBSCRIBE Packet from a Client, the Server MUST respond with a SUBACK Packet [MQTT-3.8.4-1]
    -- The SUBACK Packet MUST have the same Packet Identifier as the SUBSCRIBE Packet that it is acknowledging [MQTT-3.8.4-2]
    return encode_ack ("SUBACK", PacketId, QoS_list)
  end

  function MQTT_packet.UNSUBSCRIBE () end             -- client only

  function MQTT_packet.UNSUBACK (PacketId)
    return encode_ack ("UNSUBACK", PacketId)
  end

  function MQTT_packet.PINGREQ () end                 -- client only

  local pingresp = encode_ack "PINGRESP" 

  function MQTT_packet.PINGRESP () 
    -- The Server MUST send a PINGRESP Packet in response to a PINGREQ packet [MQTT-3.12.4-1]
    return pingresp
  end

  function MQTT_packet.DISCONNECT () end              -- client only

  function MQTT_packet.name (packet)                  -- utility method, only used for debug logging
    local packet_type = parse_packet_type (packet: sub(1,1))
    return pname[packet_type] or packet_type
  end
  
end


-------------------------------------------
--
-- Parse and process MQTT packets
--

local parse = {}


function parse.DISCONNECT()
  -- After sending a DISCONNECT Packet the Client MUST close the Network Connection [MQTT-3.14.4-1]
  return nil, "Disconnected from client"
end

function parse.CONNECT(message, credentials)
  --  the first Packet sent from the Client to the Server MUST be a CONNECT Packet [MQTT-3.1.0-1]    
  
  -- VARIABLE HEADER
  
  -- If the protocol name is incorrect the Server MAY disconnect the Client
  local ProtocolName = message: read_string()                     -- bytes 1-6
  if ProtocolName ~= "MQTT" then 
    return nil, "Unknown protocol name: '" .. ProtocolName .. "'"
  end
  
  -- protocol level should be 4 for MQTT 3.1.1
  local protocol_level = message: read_bytes (1) : byte()         -- byte 7
  
  local TryPrivate = math.floor (protocol_level / 128)            -- 2021.03.14 mask off bit #7 used by Mosquitto
  protocol_level = protocol_level % 128  
  if protocol_level ~= 4 then 
    return nil, "Protocol level is not 3.1.1"
  end
  
  local connect_flags = message: read_flag_byte()                 -- byte 8
  
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
    return nil, "Reserved flag is not zero" 
  end
  
  -- PAYLOAD
  
  local ConnectReturnCode = 0                       -- default to success
  local ClientId, WillTopic, WillMessage
  
  -- These fields, if present, MUST appear in the order 
  --   Client Identifier, Will Topic, Will Message, User Name, Password [MQTT-3.1.3-1]
  -- The Client Identifier (ClientId) MUST be present and MUST be the first field in the CONNECT packet payload [MQTT-3.1.3-3]
  ClientId    = message: read_string() 
  
  -- If the User Name Flag is set to 0, a user name MUST NOT be present in the payload [MQTT-3.1.2-18]
  -- If the User Name Flag is set to 1, a user name MUST be present in the payload [MQTT-3.1.2-19]
  -- If the Password Flag is set to 0, a password MUST NOT be present in the payload [MQTT-3.1.2-20]
  -- If the Password Flag is set to 1, a password MUST be present in the payload [MQTT-3.1.2-21]
  WillTopic   = WillFlag == 1 and message: read_string() or nil
  WillMessage = WillFlag == 1 and message: read_string() or nil
  Username    = Username == 1 and message: read_string() or ''
  Password    = Password == 1 and message: read_string() or ''
  
  local payload = {
      ClientId = ClientId,
      WillTopic = WillTopic,
      WillMessage = WillMessage,
      UserName = Username,
      Password = Password,
      TryPrivate = TryPrivate,        -- 2021.03.14
      KeepAlive = KeepAlive,
    }
  
  _debug ("ClientId: ",     ClientId)
  _debug ("WillTopic: ",    WillTopic)
  _debug ("WillMessage: ",  WillMessage)
  _debug ("UserName: ",     "****")       -- or Username
  _debug ("Password: ",     "****")       -- or Password
  
  -- ACKNOWLEDGEMENT
  -- If CONNECT validation is successful the Server MUST acknowledge the CONNECT Packet 
  -- with a CONNACK Packet containing a zero return code [MQTT-3.1.4-4]     
  -- If the Server does not have stored Session state, it MUST set Session Present to 0 in the CONNACK packet [MQTT-3.2.2-3]
  --[[
      MQTT Connection Return Codes
      [0] = "Connection Accepted",
      [1] = "Connection Refused, unacceptable protocol version",
      [2] = "Connection Refused, identifier rejected",
      [3] = "Connection Refused, Server unavailable",
      [4] = "Connection Refused, bad user name or password",
      [5] = "Connection Refused, not authorized",
  --]]

  if Username ~= credentials.Username 
  or Password ~= credentials.Password then
    ConnectReturnCode = 4                   -- "Connection Refused, bad user name or password"
  end

  local connack = MQTT_packet.CONNACK (ConnectReturnCode)
  
  -- If a server sends a CONNACK packet containing a non-zero return code it MUST then close the Network Connection [MQTT-3.2.2-5]
  local err
  if ConnectReturnCode ~= 0 then
    err = "Closing client connect, return code: " .. ConnectReturnCode
  end
  return connack, err, payload
end

function parse.CONNACK()
  -- don't expect to receive a connack, since we don't connect to a server
end

function parse.PUBLISH(message)
  
  local flags = message.control_flags
  local DUP, QoSmsb, QoSlsb, RETAIN
  DUP, QoSmsb, QoSlsb, RETAIN = unpack (flags)
  local QoS = 2 * QoSmsb + QoSlsb
  RETAIN = RETAIN == 1
  
  -- VARIABLE HEADER
  
  -- The Topic Name MUST be present as the first field in the PUBLISH Packet Variable header [MQTT-3.3.2-1]
  local TopicName = message: read_string () or ''   -- 2021.08.16 (thanks @ArcherS)
  -- All Topic Names and Topic Filters MUST be at least one character long [MQTT-4.7.3-1]
  if #TopicName == 0 then
    return nil, "PUBLISH topic MUST be at least one character long"
  end
  -- The Topic Name in the PUBLISH Packet MUST NOT contain wildcard characters [MQTT-3.3.2-2]
  -- Topic Names and Topic Filters MUST NOT include the null character (Unicode U+0000) [MQTT-4.7.3-2]
  if TopicName: match "%#%+%$%z" then           -- also disallow ordinary client from using '$'
    return nil, "PUBLISH topic contains wildcard (or null): " .. TopicName
  end
  
  -- PUBLISH (in cases where QoS > 0) Control Packets MUST contain a non-zero 16-bit Packet Identifier [MQTT-2.3.1-1]
  -- A PUBLISH Packet MUST NOT contain a Packet Identifier if its QoS value is set to 0 [MQTT-2.3.1-5]
  local PacketId        -- packet identifier
  if QoS > 0 then
    PacketId = message: read_word()
  end
  
  -- PAYLOAD
  
  local ApplicationMessage = message.body: sub(message.ptr + 1, -1)      -- remaining part of body
  
  -- ACKNOWLEDGEMENT
  -- The receiver of a PUBLISH Packet MUST respond according to Table 3.4 - Expected Publish Packet
  --   response as determined by the QoS in the PUBLISH packet [MQTT-3.3.4-1]
  --[[
        Table 3.4 - Expected Publish Packet response
        QoS Level Expected Response
        QoS 0 None
        QoS 1 PUBACK Packet 
        QoS 2 PUBREC Packet
--]]
  local ack    -- None for QoS 0
  
  -- 2022.12.02  Fix response to QoS > 0 packets, thanks @Crille and @toggledbits
  if QoS == 1 then
    ack = MQTT_packet.PUBACK (PacketId)
  elseif QoS == 2 then
    ack = MQTT_packet.PUBREC (PacketId)
  end
  
  return ack, nil, TopicName, ApplicationMessage, RETAIN
end

function parse.PUBREL (message)
  -- Bits 3,2,1 and 0 of the fixed header in the PUBREL Control Packet are reserved 
  -- and MUST be set to 0,0,1 and 0 respectively.
  -- The Server MUST treat any other value as malformed and close the Network Connection [MQTT-3.6.1-1].
  local Reserved  = table.concat (message.control_flags) 
  if Reserved ~= "0010" then
    return nil, "Unexpected reserved flag bits in PUBREL: " .. Reserved
  end
  local PacketId = message: read_word()
  local ack = MQTT_packet.PUBCOMP (PacketId)
  return ack
end

function parse.PINGREQ ()
  -- The Server MUST send a PINGRESP Packet in response to a PINGREQ packet [MQTT-3.12.4-1]
  local pingresp = MQTT_packet.PINGRESP ()
  return pingresp
end

function parse.PINGRESP ()
  -- unlikely, since we don't send PINGREQ
end

function parse.SUBSCRIBE (message)   
  -- Bits 3,2,1 and 0 of the fixed header of the SUBSCRIBE Control Packet are reserved 
  -- and MUST be set to 0,0,1 and 0 respectively [MQTT-3.8.1-1]
  local Reserved  = table.concat (message.control_flags) 
  if Reserved ~= "0010" then
    return nil, "Unexpected reserved flag bits in SUBSCRIBE: " .. Reserved
  end
  
  -- VARIABLE HEADER
  
  -- SUBSCRIBE Control Packets MUST contain a non-zero 16-bit Packet Identifier [MQTT-2.3.1-1]
  local PacketId = message: read_word()
  local pid = "Packet Id: 0x%04x"
  _debug (pid: format (PacketId))
  
  -- PAYLOAD
  
  local topics = {}
  local nt = 0
  repeat
    local topic = message: read_string()
    topics[topic] = topic
    _debug ("Topic: ", topic)
    nt = nt + 1
    local RequestedQoS
    RequestedQoS = message: read_bytes(1) :byte()
--      _log ("Requested QoS: " .. RequestedQoS)
  until message.ptr >= #message.body
  
  -- The payload of a SUBSCRIBE packet MUST contain at least one Topic Filter / QoS pair [MQTT-3.8.3-3]
  if nt == 0 then
    return nil, "No topics found in SUBSCRIBE payload"
  end
  
  -- ACKNOWLEDGEMENT
  -- When the Server receives a SUBSCRIBE Packet from a Client, the Server MUST respond with a SUBACK Packet [MQTT-3.8.4-1]
  -- The SUBACK Packet MUST have the same Packet Identifier as the SUBSCRIBE Packet that it is acknowledging [MQTT-3.8.4-2]
  -- The SUBACK Packet sent by the Server to the Client MUST contain a return code for each Topic Filter/QoS pair. 
  --   This return code MUST either show the maximum QoS that was granted for that Subscription 
  --   or indicate that the subscription failed [MQTT-3.8.4-5]
  -- The Server might grant a lower maximum QoS than the subscriber requested. 
  --   The QoS of Payload Messages sent in response to a Subscription MUST be the minimum of the QoS 
  --   of the originally published message and the maximum QoS granted by the Server [MQTT-3.8.4-6]
  
  local QoS_list = string.char(0): rep (nt)   -- regardless of RequestedQoS, we're using QoS = 0 for everything
  local suback = MQTT_packet.SUBACK (PacketId, QoS_list)
  return suback, nil, topics
end

function parse.UNSUBSCRIBE (message)
  -- Bits 3,2,1 and 0 of the fixed header of the UNSUBSCRIBE Control Packet are reserved 
  -- and MUST be set to 0,0,1 and 0 respectively [MQTT-3.10.1-1]
  local Reserved  = table.concat (message.control_flags) 
  if Reserved ~= "0010" then
    return nil, "Unexpected reserved flag bits: " .. Reserved
  end
  
  -- VARIABLE HEADER
  
  local PacketId = message: read_word()
  local pid = "Packet Id: 0x%04x"
  _debug (pid: format (PacketId))
  
  -- PAYLOAD
  
  local topics = {}
  local nt = 0
  repeat
    local topic = message: read_string()
    topics[topic] = topic
    _debug ("Topic: " .. topic)
    nt = nt + 1
  until message.ptr >= #message.body
 
  --  The Payload of an UNSUBSCRIBE packet MUST contain at least one Topic Filter. 
  --  An UNSUBSCRIBE packet with no payload is a protocol violation [MQTT-3.10.3-2]
  if nt == 0 then
    return nil, "No topics found in UNSUBSCRIBE payload"
  end
  
  -- ACKNOWLEDGEMENT
  -- The Server MUST respond to an UNSUBSUBCRIBE request by sending an UNSUBACK packet. 
  -- The UNSUBACK Packet MUST have the same Packet Identifier as the UNSUBSCRIBE Packet [MQTT-3.10.4-4]
  local unsuback = MQTT_packet.UNSUBACK (PacketId)
  return unsuback, nil, topics
end


-------------------------------------------
--
-- Subscriptions
--

local subscriptions = {} do
  
  -- meta methods
  -- these have to be in the metatable because we don't want their names to appear in the subscriptions list
  local methods = {}
    
  local function new_metatable ()
    local meta = {
      wildcards = {}, 
      retained = {},                        -- retained messages indexed by topic
      stats = {
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
      },
    }
    
    for n,v in pairs (methods) do   -- add methods
      meta[n] = v
    end
    
    return {__index = meta}
  end
  
  function methods: unsubscribe_client_from_topics (client, topics)
    local name = tostring(client)
    local message = "%s UNSUBSCRIBE from %s %s"
    for topic in pairs (topics) do
      local subs = self[topic] 
      if subs and subs[client] then
        subs[client] = nil
        _log (message: format (client.MQTT_connect_payload.ClientId or '?', topic, name))
      end
    end
  end

  function methods: close_and_unsubscribe_from_all (client, log_message)
    client: close()
    if log_message then _log (table.concat {log_message, ' ', tostring(client)}) end
    self: unsubscribe_client_from_topics (client, self)     -- self is a table of all topics!
  end

  -- register an internal (openLuup), or external, subscriber to a topic
  function methods: subscribe(subscription)
    local topic = subscription.topic
    self.wildcards[topic] = topic: match "^(.-)#$" or nil   -- save it in the special table if it's a wildcard
    local subs = self[topic] or {}
    local key = subscription.client or (#subs + 1)    -- use numeric key for internal (since callback not unique)
    self[topic] = subs
    subs[key] = subscription
    return 1
  end

  -- register an openLuup-side subscriber to a single topic
  function methods: register_handler (callback, topic, parameter)
    self: subscribe {
      callback = callback, 
      devNo = scheduler.current_device (),
      parameter = parameter,
      topic = topic,
      count = 0,
    }
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
  function methods: subscribe_client_to_topics (client, topics)
    local name = tostring(client)
    local message = "%s SUBSCRIBE to %s %s"
    for topic in pairs (topics) do
      self: subscribe {
        client = client, 
        topic = topic,
        count = 0,
      }
      _log (message: format (client.MQTT_connect_payload.ClientId or '?', topic, name))
      
      -- send any RETAINED message for this topic
      local retained_message = self.retained[topic]
      if retained_message then
        local control_flags = 1 -- format message with RETAIN bit set
        local message = MQTT_packet.PUBLISH (topic, retained_message, control_flags)
        self: send_to_client (client, message) -- publish to external subscribers
      end
    end
    
    
    -- TODO: wildcard topics
--    for wildcard, pattern in pairs (self.wildcards) do
--      if TopicName: sub(1, #pattern) == pattern then
--      end
--    end
    

  end
  
  function methods: send_to_client (client, message)
    local ok, err = true
    local closed = client.closed            -- client.closed is created by io.server
    if not closed then
      ok, err = client: send (message)      -- don't try to send to closed socket
    end
    if closed or not ok then
      self: close_and_unsubscribe_from_all (client, err)
    else
      -- statistics
      local stats = self.stats
      stats["bytes/sent"] = stats["bytes/sent"] + #message
      stats["messages/sent"] = stats["messages/sent"]  + 1    
    end
    return ok, err
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
  function methods: publish (TopicName, ApplicationMessage, Retained)
    
    -- handle retained topics [MQTT-3.3.1-5/7/10/11/12]
    if Retained then 
      self.retained[TopicName] = (#ApplicationMessage > 0) and ApplicationMessage or nil
    end
    
    -- statistics
    local stats = self.stats
    stats["publish/messages/received"] = stats["publish/messages/received"] + 1

    -- publish message to single subscriber
    local function publish_to_one (subscriber, message)
      local s, m = subscriber, message
      s.count = (s.count or 0) + 1
      local ok, err
      if s.callback then
        ok, err = scheduler.context_switch (s.devNo, s.callback, m.TopicName, m.ApplicationMessage, s.parameter, m.Retained)
      elseif s.client then
        ok, err = self: send_to_client (s.client, m.MQTT_packet) -- publish to external subscribers
        if ok then 
          stats["publish/messages/sent"] = stats["publish/messages/sent"] + 1
        end
      end
      return ok, err
    end
    
    -- publish message to all subscribers
    local function publish_to_all (subscribers, TopicName, ApplicationMessage)
      local message = Message (TopicName, ApplicationMessage)
      local ok, err 
      for _, subscriber in pairs (subscribers) do
        ok, err = publish_to_one (subscriber, message)
        if not ok then
          _log (table.concat {"ERROR publishing application message for mqtt:", TopicName, " : ", err})
        else
    --      _log ("Successfully published: " .. TopicName)
        end
      end
    end
    if #TopicName == 0 then return end
    
    -- simple topic match
    local subscribers = self[TopicName]
    if subscribers then
      publish_to_all (subscribers, TopicName, ApplicationMessage)     -- topic subscribers
    end
    
    -- TODO: '+' wildcards
    -- wildcards ending in '#'
    local dollar = TopicName: sub(1,1) == '$'
    for wildcard, pattern in pairs (self.wildcards) do
      if TopicName: sub(1, #pattern) == pattern then
        -- The Server MUST NOT match Topic Filters starting with a wildcard character (# or +) 
        -- with Topic Names beginning with a $ character [MQTT-4.7.2-1]
        if not (dollar and wildcard == '#') then
          subscribers = self[wildcard]
          if subscribers then
            publish_to_all (subscribers, TopicName, ApplicationMessage)
          end
        end
      end
    end
  end
  
  -- note that each subscription has a separate metatable, but shares the __index table of methods
  -- wildcard subscriptions are held in the metatable.wildcards table
  
  function methods.new ()
    return setmetatable ({}, new_metatable())    -- list of subscribers, indexed by topic
  end

  setmetatable (subscriptions, new_metatable())
  
end

-------------------------------------------
--
-- Generic MQTT incoming message handler
--

local function reserved(message)
  return nil, "UNIMPLEMENTED packet type: " .. message.packet_type
end

local function incoming (client, credentials, subscriptions)
  
  local ack
  local pname = "RECEIVE ERROR"
  local message, errmsg = MQTT_packet.receive (client)
  
  if message then
    pname = message.packet_name
    _debug (pname, ' ', tostring(client))
    
    -- statistics
    local stats = subscriptions.stats
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
      subscriptions: send_to_client (client, ack)
      _debug (MQTT_packet.name (ack), "ack")
    end
    
    if topic then
      
      if app_message then
        
        -- publish topic to subscribers
        subscriptions: publish (topic, app_message, retain)
      
      elseif pname == "SUBSCRIBE" then
        
        -- add any subscriber to table of topics
        subscriptions: subscribe_client_to_topics (client, topic)
        
      elseif pname == "UNSUBSCRIBE" then
        
        -- unsubscribe external (IP) clients
        subscriptions: unsubscribe_client_from_topics (client, topic)
        
      elseif pname == "CONNECT" then
        
        -- save connect payload in client object (chiefly for accessing the ClientId)
        client.MQTT_connect_payload = topic
      end
    end
  end
  
  -- disconnect client on error
  if errmsg then
    subscriptions: close_and_unsubscribe_from_all (client, table.concat {pname, ": ", errmsg or '?'})
  end
end

-------------------------------------------
--
-- MQTT server
--

-- create additional MQTT servers (on different ports - or no port at all!)
local function new (config)
  config = config or {}
  
  local credentials = {                                 -- pull credentials from the config table (not used by ioutil.server)
      Username = config.Username or '',
      Password = config.Password or '',
    }
  
  local subscribers = subscriptions.new ()              -- a whole new list of subscribers
  
  local function servlet(client)
    return function () incoming (client, credentials, subscribers) end
  end
  
  local port = config.Port
  if port then                                            -- possible to create a purely internal MQTT 'server'
    ioutil.server.new {
        port      = port,                                 -- incoming port
        name      = "MQTT:" .. port,                      -- server name
        backlog   = config.Backlog or 100,                -- queue length
        idletime  = config.CloseIdleSocketAfter or 120,   -- connect timeout
        servlet   = servlet,                              -- our own servlet
      }
  end
  
  return {
      statistics = subscribers.stats,
      retained = subscribers.retained,
      -- note that these instance methods should be called with the colon syntax
      subscribe = function (_, ...) subscribers: register_handler (...) end,     -- callback for subscribed messages
      publish = function (_, ...) subscribers: publish (...) end,                -- publish from within openLuup
    }
end


-- start main openLuup MQTT server
local function start (config)

  ABOUT.DEBUG = config.DEBUG 
  
  local credentials = {
      Username = config.Username or '',
      Password = config.Password or '',
    }

  -- callback function is called with (port, {datagram = ..., ip = ...}, "udp")
  -- datagram format is topic/=/message
  local function UDP_MQTT_bridge (_, data)
    local topic, message = data.datagram: match "^(.-)/=/(.+)"
    if topic then 
      subscriptions: publish (topic, message) 
    end

  end
  
  if tonumber (config.Bridge_UDP) then                  -- start UDP-MQTT bridge
    ioutil.udp.register_handler (UDP_MQTT_bridge, config.Bridge_UDP)
  end
  
  local function MQTTservlet (client)
    return function () incoming (client, credentials, subscriptions) end
  end 
  
  -- returned server object has stop method, but we'll not be using it
  local port = config.Port or 1883
  return ioutil.server.new {
      port      = port,                                 -- incoming port
      name      = "MQTT:" .. port,                      -- server name
      backlog   = config.Backlog or 100,                -- queue length
      idletime  = config.CloseIdleSocketAfter or 120,   -- connect timeout
      servlet   = MQTTservlet,                          -- our own servlet
      connects  = iprequests,                           -- use our own table for console info
    }
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
      subscriptions: publish (table.concat ({"openLuup/update",d,s,v}, '/'), val)
    end
  end
end

do -- MQTT commands
  subscriptions: register_handler (mqtt_relay, "relay/#")
  subscriptions: register_handler (mqtt_light, "light/#")
  subscriptions: register_handler (mqtt_relay, "openLuup/relay/#")
  subscriptions: register_handler (mqtt_light, "openLuup/light/#")
  subscriptions: register_handler (mqtt_query, "openLuup/query")
end


--- return module variables and methods
return setmetatable ({
    ABOUT = ABOUT,
    
    -- constants
    myIP = tables.myIP,
    
    -- methods
    start = start,
    register_handler = function (...) subscriptions: register_handler (...) end,  -- callback for subscribed messages
    publish = function (...) subscriptions: publish (...) end,                    -- publish from within openLuup
    
    new = new,       -- create another new MQTT server
    
    -- variables
    statistics = subscriptions.stats,
    retained = subscriptions.retained,

  },{
  
  -- hide some of the more esoteric data structures, only used internally by openLuup
  
    __index = {
          
    TEST = {          -- for testing only
        packet = MQTT_packet,
        parse = parse,
      },
    
    iprequests  = iprequests,
    subscribers = subscriptions,
    
  }})
