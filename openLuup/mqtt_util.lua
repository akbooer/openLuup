local ABOUT = {
  NAME          = "openLuup.mqtt_util",
  VERSION       = "2024.04.14",
  DESCRIPTION   = "MQTT v3.1.1 utilities",
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

-- 2024.03.08  separate into separate file from MQTT server
-- 2024.03.17  fix PUBLISH check for illegal characters in topic
-- 2024.04.14  add $SYS/broker/load/# statistics


-- see OASIS standard: http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.pdf
-- Each conformance statement has been assigned a reference in the format [MQTT-x.x.x-y]


local function _debug(...) if ABOUT.DEBUG then print(os.date "%X:", ...) end; end

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
--    if not fixed_header_byte1 then return nil, "(Fixed Header byte) " .. err end
    if not fixed_header_byte1 then return nil, '' end     -- suppress error message

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
    
    local SessionPresent = 0                          -- Persistent Clients not supported, so no Session State
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

--[[

  All parse functions return these (possibly nil) parameters:
      ack, errmsg, topic, app_message, retain

    -- ack is an acknowledgement package to send back to the client
    -- errmsg signals an error requiring the client connection to be closed
    -- topic may be a list for (un)subscribe, or a single topic to publish
    -- app_message is the appplication message for publication
    -- retain is true for retained messages

--]]

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
      ClientId    = ClientId,
      WillTopic   = WillTopic,
      WillMessage = WillMessage,
      WillRetain  = WillRetain == 1,
      UserName    = Username,
      Password    = Password,
      TryPrivate  = TryPrivate,        -- 2021.03.14
      KeepAlive   = KeepAlive,
    }
  
  _debug ("ClientId: ",     ClientId)
  _debug ("WillTopic: ",    WillTopic)
  _debug ("WillMessage: ",  WillMessage)
  _debug ("KeepAlive",      KeepAlive)
  
  if #Username > 0 then _debug ("UserName: ", "****") end       -- or Username
  if #Password > 0 then _debug ("Password: ", "****") end       -- or Password
  
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
  if TopicName: match "[%#%+%$%z]" then           -- also disallow ordinary client from using '$'
    return nil, "PUBLISH topic contains wildcard, '$', or null): " .. TopicName
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
-- MQTT subscriptions
--

--[[
  Usage: 
  
    local subs = Subscriptions()          -- create new subscriptions directory
    
    subs: subscribe(client1, topic1)
    subs: subscribe(client1, topic2)
    subs: subscribe(client2, topic1)
    subs: subscribe(client2, topic3)
    
    local subscribers = subs:subscribers(topic)   -- returns table of subscribers to this topic
    
    subs: unsubscribe(client2, topic1)
    
--]]

-- create new directory of subscriptions
local function Subscriptions()

  local subscribed = {}           -- clients indexed by subscribed topics (including wildcards)
  local published  = {}           -- matching clients indexed by published topics (no wildcards)

  -- cache the conversion of a subscribed topic into a Lua search string
  local cache_meta = {}
  function cache_meta:__index(topic)
    local pattern =  '^' .. topic:gsub('%+', "[^/]+"):gsub('%-', "%%%-"):gsub("/?#$", ".*") .. '$'
    _debug("cache", topic, pattern)
    self[topic] = pattern
    return pattern
  end

  -- cache valid publish topic names
  local publish_meta = {}
  function publish_meta:__index(topic)
    --TODO: validate publish topic name
  end

  --cache valid subscriber topic names
  local subscribe_meta = {}
  function subscribe_meta:__index(topic)
    --TODO: validate subscribe topic name
  end

  local search_pattern  = setmetatable ({}, cache_meta)
  local valid_sub_topic = setmetatable ({}, subscribe_meta)
  local valid_pub_topic = setmetatable ({}, publish_meta)

  -- The Server MUST NOT match Topic Filters starting with a wildcard character (# or +) 
  -- with Topic Names beginning with a $ character [MQTT-4.7.2-1]
  local wildcard = {['#'] = true, ['+'] = true}
  
  local function name_matches_subscription(name, subscription)
    local dollar = name: sub(1,1) == '$'
    if dollar                -- happens only very rarely, if ever
      and wildcard[subscription: sub(1,1)] then
        return false
    end
    return name: match (search_pattern[subscription])
  end
  
  -- remove invalid clients from published topic list, but retain topic name
  -- internal function only used by (un)subscribe
  local function purge(topic)
    for pub in pairs(published) do
      if name_matches_subscription (pub, topic) then
        published[pub] = false
      end
    end
  end
  
  -- subscribe client to topic, with optional subscription information
  local function subscribe(self, client, topic, subscription)
    local s = subscribed[topic] or {}       -- create new topic if necessary
    subscribed[topic] = s
    s[client] = subscription or true
    purge(topic)                            -- invalidate any matching published topic
  end

  -- unsubscribe client, if topic is nil then unsubscribe from all current subscriptions
  local function unsubscribe(self, client, topic)
    local topics = topic and {topic} or subscribed
    for topic in pairs(topics) do
      local s = subscribed[topic]
      if s then s[client] = nil end
      purge(topic)                          -- invalidate any matching published topic
    end
  end

  -- which subscribed clients match this published topic?
  local function matching_subs(topic)
    local subs = {}
    -- find matching subscriptions
    for subscription, clients in pairs(subscribed) do
      if name_matches_subscription(topic, subscription) then
        subs[#subs+1] = clients
      end
    end
    return subs
  end
  
  -- which subscribers match this published topic
  -- note that pubs[] is the cache for this 
  local function subscribers(self, topic)
    local subs = published[topic]
    if not subs then           -- need to (re)build index
      subs = {}
      _debug("rebuilding published index: ", topic)
      -- find matching subscriptions
      for _, s in ipairs(matching_subs(topic)) do
        for client, subscription in pairs(s) do
          subs[client] = subscription
        end
      end
    end
    published [topic] = subs
    return subs
  end



  return {
    
    -- tables
      subscribed = subscribed,
      published  = published,
     
    -- methods   
      subscribe   = subscribe,
      unsubscribe = unsubscribe,
      subscribers = subscribers,        -- returns table of subscribers to topic
      
      valid_pub_topic = valid_pub_topic,
      valid_sub_topic = valid_sub_topic,
     }
end



-------------------------------------------
--
-- MQTT broker statistics
-- see: https://mosquitto.org/man/mosquitto-8.html
--

--[[

$SYS/broker/bytes/received          total number of bytes received since the broker started.
$SYS/broker/bytes/sent              total number of bytes sent since the broker started.

$SYS/broker/clients/connected       number of currently connected clients.
$SYS/broker/clients/maximum         maximum number of clients that have been connected to the broker at the same time.
$SYS/broker/clients/total           total number of active and inactive clients currently connected and registered on the broker

  $SYS/broker/load/#

    The following group of topics all represent time averages. 
    The value returned represents some quantity for 1 minute, averaged over 1, 5 or 15 minutes.
    The final "+" of the hierarchy can be 1min, 5min or 15min. 

$SYS/broker/load/connections/+        moving average of the number of CONNECT packets received by the broker
$SYS/broker/load/bytes/received/+     moving average of the number of bytes received by the broker
$SYS/broker/load/bytes/sent/+         moving average of the number of bytes sent by the broker
$SYS/broker/load/messages/received/+  moving average of the number of all types of MQTT messages received by the broker
$SYS/broker/load/messages/sent/+      moving average of the number of all types of MQTT messages sent by the broker
$SYS/broker/load/publish/received/+   moving average of the number of publish messages received by the broker
$SYS/broker/load/publish/sent/+       moving average of the number of publish messages sent by the broker
$SYS/broker/load/sockets/+            moving average of the number of socket connections opened to the broker

$SYS/broker/messages/received         total number of messages of any type received since the broker started.
$SYS/broker/messages/sent             total number of messages of any type sent since the broker started.

$SYS/broker/publish/messages/received total number of PUBLISH messages received since the broker started.
$SYS/broker/publish/messages/sent     total number of PUBLISH messages sent since the broker started.

$SYS/broker/retained messages/count   total number of retained messages active on the broker.
$SYS/broker/store/messages/bytes      number of bytes currently held by (retained) message payloads in the message store

$SYS/broker/subscriptions/count       total number of subscriptions active on the broker.

$SYS/broker/version                   version of the broker. Static.

--]]


local function Statistics ()              -- create a new statistics table
  
  local stats = {
    ["clients/connected"] = 0,          -- currently connected clients.
    ["clients/maximum"] = 0,            -- maximum number of clients that have been connected to the broker at the same time.
    ["clients/total"] = 0,              -- active and inactive clients currently connected and registered.
    ["retained/messages/count"] = 0,    -- total number of retained messages active on the broker.
  }
  
  local averaged = {
    "bytes/received",                   -- bytes received since the broker started.
    "bytes/sent",                       -- bytes sent since the broker started.
    "messages/received",                -- messages of any type received since the broker started.
    "messages/sent",                    -- messages of any type sent since the broker started.
    "publish/messages/received",        -- PUBLISH messages received since the broker started.
    "publish/messages/sent",            -- PUBLISH messages sent since the broker started.
  }
  
  local past = {} 
  local old = {}                          -- old value of metrics
  
  local meta = {}

  local function average(x, n)
    local total= 0
    for i = 1, n do
      total = total + (x[i] or 0)
    end
    return math.floor(total / n + 0.5)
  end
  
  -- this is called once every minute
  function meta:load_average()          -- update statistics table with $SYS/broker/load/# averages
    local load_avg = {}
    local prefix = "load/"
    
    for _, stat in ipairs(averaged) do
      local value = stats[stat]
      -- update the current value histories
      local diff = value - (old[stat] or 0)   -- store the differences
      old[stat] = value                       -- save the new (old) value
      local prev = past[stat]
      table.insert(prev, 1, diff)             -- insert at start
      prev[16] = nil                          -- truncate to 15 elements
    
      -- calculate 1, 5, and 15 minute averages
      local avg_name = prefix .. stat      
      stats[avg_name ..  "/1min"] = diff
      stats[avg_name ..  "/5min"] = average(prev,  5)
      stats[avg_name .. "/15min"] = average(prev, 15)
    end
    
    return load_avg
  end
  
  -- initialise the averaged stats
  for _, stat in ipairs(averaged) do 
    stats[stat] = 0 
    past[stat] = {}                      -- 15 minute histories of averaged stats
  end    
  
  return setmetatable(stats, {__index = meta})    -- hide load_average call
end

return {
  
    MQTT_packet = MQTT_packet,          -- packet creation
    parse = parse,                      -- packet parsing
    
    Subscriptions = Subscriptions,      -- subscription handling
    Statistics = Statistics,
  }
