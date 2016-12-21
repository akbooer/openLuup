local ABOUT = {
  NAME          = "openLuup.compression",
  VERSION       = "2016.06.30",
  DESCRIPTION   = "Data compression using LZAP",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2016 AKBooer",
  DOCUMENTATION = "http://read.pudn.com/downloads167/ebook/769449/dataCompress.pdf",
  LICENSE       = [[
  Copyright 2016 AK Booer

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


-- CODEC

--[[

This codec module does bi-directional translations of integer arrays of codewords <---> little-endian byte strings.
Maximum word count is determined by the code alphabet used by the byte stream (fixed at two bytes per word.)
If invoked without a parameter, the code alphabet is the full 0x00 - 0xFF range per byte, giving 16-bits per word.

An alternative pre-defined alphabet is provided by the module: the json_alphabet, being the 92 non-escaped JSON
string characters (some ambiguity about the '/' character, so that is excluded.)  Using this alphabet ensures 
a coded byte stream which may be used as a directly coded JSON string with no escaped expansions, but limits
the available codes to 92 * 92 = 8464 (cf. 65536 for the full byte range.)

--]]

--note that ASCII printable characters are 0x20 - 0x7E (0x7F is 'delete')
--note that XML quoted characters are: < > " ' &
--note that JSON quoted printable characters are: " \ /  (or possibly not /)

local unescaped_JSON_alphabet =
  [==[ !#$%&'()*+,-.0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~]==]

local full_alphabet = ''    -- empty string forces full-width alphabet

-- null encoder (returns words, not byte string)
local null_codec =                 
  {
    alphabet = {},
    symbols = 2^53,   -- note that 2^53 is the highest integer that a 64-bit IEEE floating-point number can represent
    
    encode = function (x) return x end, 
    decode = function (x) return x end, 
  }

-- optional header is prefix to encoded byte stream
-- error raised if not found at start of decode byte stream
local function codec (code_alphabet, header) 
  if code_alphabet == null_codec then return null_codec end
  header = header or ''
  if not code_alphabet or code_alphabet == full_alphabet then   -- use two full-width bytes to represent a word
    code_alphabet = {}
    for i = 0, 0xFF do code_alphabet[i+1] = string.char (i) end
    code_alphabet = table.concat (code_alphabet)
  end
  
  local LSB, MSB = {}, {}   -- lookup table to convert characters to lsb/msb numeric values
  local alpha = {}          -- breaks the alphabet into separate characters
  local i, base = 0, #code_alphabet
  for c in code_alphabet: gmatch "." do 
    LSB[c] = i            -- NB: the first code represents ZERO!
    MSB[c] = base * i 
    i = i + 1
    alpha[i] = c
  end

  -- encodes a word array into byte-pair string
  local function encode (words)
    local bytes = {header}
    local base = #code_alphabet
    for _, word in ipairs (words) do
      local lsb = word % base + 1
      local msb = math.floor (word / base) + 1
      bytes[#bytes+1] = alpha[lsb]
      bytes[#bytes+1] = alpha[msb]
    end
    return table.concat(bytes)
  end
  
  -- converts an array of little-endian byte-pairs into words
  local function decode (bytes)
    local words = {}
    assert (bytes: sub(1,#header) == header, "byte stream header mismatch")
    for n = #header+1, #bytes, 2 do
      local lsb = bytes:sub (n,n)
      local m = n+1
      local msb = bytes:sub (m,m)
      words[#words+1] = MSB[msb] + LSB[lsb]
    end
    return words
  end
  
  return {
    alphabet = alpha,              -- byte code alphabet as an array of characters
    symbols  = (#alpha) ^2,        -- number of possible symbols in byte-pair code
    
    encode  = encode,
    decode  = decode,
  }

end

-- DICTIONARY
-- No re-cycling of dictionary entries is currently used.

local function dictionary (max_size)    -- bi-directional lookup
  
  local dict = {}
  local N                   -- dictionary length  
  local MAX_WORD =  128     -- a good compromise
  
  local function add (prev, word)
    local both = (prev .. word): sub(1, MAX_WORD)
    if N + #both > max_size then return end
    for i = #prev+1 ,#both do
      local x = both:sub(1,i)
      if not dict[x] then
        N = N + 1
        dict[x] = N
        dict[N] = x
      end
    end
  end
  
  -- initialise dictionary with all possible byte-codes
  N = 256  
  for i = 1,N do 
    local c = string.char(i-1)
    dict[c] = i
    dict[i] = c
  end

  return {
    add     = add,
    lookup  = function (x) return dict[x] end,
    }
end

--
-- LZAP compression 
--
  
-- compession algorithm
local function encode (text, codec, dict)
  codec = codec or null_codec
  dict = dictionary (codec.symbols)
  
  local add = dict.add
  local lookup = dict.lookup
  local prev, word = ''
  local code = {}
  
  local m = 1
  for n = 1,#text do
--    if n % 1e4 == 0 then print (("%6d %0.1f%%"): format (n,1e2*#code/n)) end  -- monitor compression rate
    local new = text: sub(m,n)
    if not lookup (new) then
      code[#code+1] = lookup (word)
      add (prev, word) 
      prev = word
      new = new: sub(-1,-1)
      m = n
    end
    word = new
  end
  code[#code+1] = lookup (word)
  return codec.encode (code)              -- turn code words into byte string
end

-- decompression
local function decode (code, codec, dict)
  codec = codec or null_codec
  code = codec.decode (code)              -- turn byte string into code words
  dict = dictionary (codec.symbols)
  
  local add = dict.add
  local lookup = dict.lookup
  local prev, word = ''
  local text = {}
  
  for n = 1, #code do 
    word = lookup (code[n]) 
    add (prev, word)
    text[#text+1] = word
    prev = word
  end
  return table.concat (text)
end


-----

return {
    ABOUT = ABOUT,
    
    codec = setmetatable ({                 -- this syntax allows both codec() and codec.new() calls
        json = unescaped_JSON_alphabet,     -- also enables parameter self-reference: codec(codec.json)
        full = full_alphabet,               -- full two-byte alphabet: codec (codec.full)
        null = null_codec,
        new = codec,
      },{__call = function (_, ...) return codec (...) end}),
  
    dictionary = dictionary,
    
    lzap = {
      encode = encode,
      decode = decode,
    },
  }
  
-----
