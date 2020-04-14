local ABOUT = {
  NAME          = "openLuup.json",
  VERSION       = "2020.04.14",
  DESCRIPTION   = "JSON encode/decode with unicode escapes to UTF-8 encoding and pretty-printing",
  AUTHOR        = "@akbooer",
  COPYRIGHT     = "(c) 2013-2020 AKBooer",
  DOCUMENTATION = "https://github.com/akbooer/openLuup/tree/master/Documentation",
  LICENSE       = [[
  Copyright 2013-2020 AK Booer

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

-- JSON encode/decode with full functionality including unicode escapes to UTF-8 encoding.
-- now does pretty-printing of encoded JSON strings.
  
-- 2015.04.10   allow comma before closing '}' or ']'
-- 2015.11.29   improve formatting of nested objects, cache encoded strings

-- 2016.06.19   encode "/" as "/" not "\/" in strings
-- 2016.10.18   add json.null

-- 2018.06.26   extend default max_array_length to 3000

-- 2020.04.12   streamline encode() and decode(), use cjson.decode() if installed (10x faster!)
-- 2020.04.14   provide access to both Lua and C implementations (if installed)


  local is_cj, cjson = pcall (require, "cjson")
  
  local default   = 
    {
      huge = "8.88e888",          -- representation for JSON infinity (looks like infinity symbols on their side)
      max_array_length = 3000,    -- not a coding restriction, per se, just a sanity check against, eg {[1e6] = 1}
                                  -- since arrays are enumerated from starting index 1 with every intervening 'nil' 
    }
    
  local json_null = {}            -- unique object, may be used to represent null when encoding arrays
    
  -- encode (), Lua to JSON
  local function encode (Lua)

    local buffer = {}
    local function p(x) buffer[#buffer+1] = x end   -- add item
    local function q(x) buffer[#buffer]   = x end   -- overwrite last item
        
    local function json_error (text)  error ("JSON encode error : " .. text , 0) end
    
    local value               -- forward function reference
    local depth = 1           -- for pretty printing
    local encoding = {}       -- set of tables currently being encoded (to avoid infinite self reference loop)
    
    local function null    ()    p "null"    end           --  nil
    local function boolean (x)   p (tostring(x)) end       --  true or false
    
    local function number (x)
      if x ~= x then  x = "null"                           --  NaN
      elseif x >=  math.huge then x =  default.huge        -- +infinity
      elseif x <= -math.huge then x = '-' .. tostring(default.huge) end    -- -infinity
      p (x) 
    end

    local replace = {
         ['"']  = '\\"',    -- double quote
--         ['/']  = '\\/',    -- solidus          2016.06.19
         ['\\'] = '\\\\',   -- reverse solidus
         ['\b'] = "\\b",    -- backspace  
         ['\f'] = "\\f",    -- formfeed
         ['\n'] = "\\n",    -- newline
         ['\r'] = "\\r",    -- carriage return
         ['\t'] = "\\t",    -- horizontal tab
      }

    local function new (old)
      return replace [old] or ("\\u%04x"): format (old: byte () ) 
    end
    
    local ctrl_chars = "%z\001-\031"              -- whole range of control characters
--    local old = '[' .. '"' .. '/' .. '\\' .. ctrl_chars .. ']'
    local old = table.concat {'[', '"', '\\', ctrl_chars, ']'}      -- 2016.06.19
        
--    local str_hit = {}                            -- log of cache hits
    local str_cache = {}                          -- cache storage for encoded strings
    local function string (x)
--      str_hit[x] = (str_hit[x] or 0) + 1          -- count cache hits
      str_cache[x] = str_cache[x] or                -- use cached result if available
        table.concat {'"', x:gsub (old, new), '"'}  -- deal with escapes, etc. 
      p (str_cache[x])
    end
    
    local function array (x, index)
      local items = {}
      table.sort (index)                  -- to find min and max, numeric indices guaranteed 
      local min = index[1] or 1           -- index may be zero length
      local max = index[#index] or 0      -- max less than min for empty matrix
      if min < 1                        then json_error 'array start index is less than 1' end
      if max > default.max_array_length then json_error 'array final index is too large'   end 
      p '['
      for i = 1, max do
        items[i] = value (x[i])         -- may contain nulls
        p ','
      end
      q ']'   -- overwrite last comma
    end
     
    local function object (x, index)  
      local function nl (d) return '\n'..('  '):rep (d), '\n'..('  '):rep (d-1) end
      local nl1, nl2 = '', ''
      table.sort (index)                -- nice ordering, string indices guaranteed 
      if #index > 1 then nl1, nl2 = nl(depth) end
      local nl3 = ','..nl1
      depth = depth + 1
      p '{'
      p (nl1)
      for _,j in ipairs (index) do
        string(j)
        p ':'
        value (x[j])
        p (nl3)
      end
      q (nl2)   -- overwrite last comma
      p '}'
      depth = depth - 1
    end
  
    local function object_or_array (x)
      if x == json_null then return "null" end
      local index = {}
      local only_numbers, only_strings = true, true
      if encoding[x] then json_error "table structure has self-reference" end
      encoding[x] = true
      for i in pairs (x) do
        index[#index+1] = i
        local  kind = type (i)
        if     kind == "string" then only_numbers = false
        elseif kind == "number" then only_strings = false
        else   json_error ("invalid table index type '" .. kind ..'"') end
      end
      if #index == 0 then p "[]" return end   -- special case
      if only_numbers then array (x, index) 
      elseif only_strings then object (x, index) 
      else json_error "table has mixed numeric and string indices" end
      encoding [x] = nil          -- finished encoding this structure
    end

    local lua_type  = {           -- dispatch table for different types
          table   = object_or_array,
          string  = string,
          number  = number,
          boolean = boolean,
          ["nil"] = null,
        }

    local function err(x) json_error ("can't encode type '".. type(x) .."'" ) end
    
    function value (x) (lua_type [type(x)] or err) (x) end     -- already declared local
    
    -- encode()
    
    local json
    local ok, message = pcall (value, Lua)
    if ok then json = table.concat (buffer) end
    return json, message
    
  end -- encode ()


  -- decode (json), decodes a json string, returning (value) or (value, warning_message) or (nil, error_message) 
  local function decode (json)
  
    local openbrace       = '^%s*(%{)'   -- note that all the search strings are anchored to the start
    local openbracket     = '^%s*(%[)'
    local quotemark       = '^%s*(%")'
    local endquote_or_backslash = '^([^"\\]-)(["\\])'   -- leading spaces here are part of the string
    local trailing_spaces   = '(%s*)'

    local numeric_string    = '^%s*([%-]?%d+[%.]?%d*[Ee]?[%+%-]?%d*)'
    local literal_string    = '^%s*(%a+)'
    local colon_separator   = '^%s*(:)'
    local UTF_code          = '^(%x%x%x%x)'
  
    local endbrace            = '^%s*(%})'
    local endbracket          = '^%s*(%])'
    local endbrace_or_comma   = '^%s*([%},])'
    local endbracket_or_comma = '^%s*([%],])'
    
    local valid_literal = {["true"] = true, ["false"]= false, ["null"] = json_null }    -- anything else invalid
  
    local value         -- forward definition for recursive function

    local idx = 1       -- starting character for parser
    
    -- note that inline 'if ... then ... end' calls to this are significantly faster than an 'assert' function call
    local function json_message (msg)
      local _, lineNo = json: sub(1, idx): gsub ('\n','\n')
      local before = json: sub (math.max (1,idx-20), math.max(idx-1,1))
      local after = json:sub (idx, idx+20)   -- : gsub ("%c", ' ')
      local message = "JSON decode error @[%d of %d, line: %d] %s\n   '%s   <<<HERE>>>   %s'"
      return message: format (idx, #json, lineNo+1, msg, before, after)
    end

    local function json_error (msg) error (json_message(msg), 0) end

    local function find (pattern)
      local _,b, c, d = json: find (pattern, idx)
      if b then 
        idx = b+1 
      end
      return c, d
    end   

    local function literal ()
      local c = find (literal_string) 
      return valid_literal[c] 
    end

    local function number ()
      local c = find (numeric_string) 
      return tonumber (c)
    end
    
    local function utf8 (codepoint)         -- encode as UTF-8 Basic Multilingual Plane codepoint
      local function encode (x, bits, high)
        local y = math.floor (x / 0x40)
        x = x - y * 0x40
        if y == 0 then return x + high end
        return x + 0x80, encode (y, bits/2, high/2 + 0x80)
      end
      if codepoint < 0x80 then return string.char (codepoint) end 
      return string.reverse (string.char (encode (codepoint, 0x40, 0x80))) 
    end
  
    local replace = {
        ['b']  = "\b",    -- backspace  
        ['f']  = "\f",    -- formfeed
        ['n']  = "\n",    -- newline
        ['r']  = "\r",    -- carriage return
        ['t']  = "\t",    -- horizontal tab
        -- everything else replaced by itself (aside from "\uxxxx", which is handled separately below) 
      }
    
    local function escape_replacement ()
      local c
      c = find "(.)"                    -- pick up escaped character
      if c == 'u' then                  -- special UTF hex code
        c = find (UTF_code) 
        if not c then json_error "escape \\u not followed by four hex digits" end 
        c = utf8 (tonumber (c, 16))     -- convert to UTF-8 Basic Multilingual Plane codepoint
      end
      return replace[c] or c
    end
    
    local function string ()     
      local c,t = find (quotemark)
      if not c then return end
      local str = {}
      repeat
        c,t = find (endquote_or_backslash)
        if not c then json_error "unterminated string" end
        str[#str+1] = c                           -- save the string segment
        if t == '\\' then str[#str+1] = escape_replacement () end   -- deal with escapes
      until t == '"' 
      return table.concat(str) 
    end
    
    local function array ()
      local c = find (openbracket) 
      if not c then return end
      local n = 0                     -- can't use #x because of possible nil values in x
      local x = {}
      repeat
        c = find (endbracket)
        if c then break end      -- maybe there was nothing after that last comma
        local val = value ()
        if val == nil then json_error "array value invalid" end    -- note that val == false is OK!
        if val == json_null then val = nil end
        n = n+1 
        x[n] = val
        c = find (endbracket_or_comma)
        if not c then json_error "array value terminator not ',' or ']'" end
      until c == ']'
      return x
    end
    
    local function object ()
      local c = find (openbrace) 
      if not c then return end 
      local x = {}
      repeat
        c = find (endbrace)
        if c then break end      -- maybe there was nothing after that last comma
        local name = string ()
        if not name then json_error "object name invalid" end
        if not find (colon_separator)
          then json_error (table.concat {"object name not followed by ':'", name}) end
        local val = value ()
        if val == nil then json_error "object value invalid" end
        if val == json_null then val = nil end
        x[name] = val
        c = find (endbrace_or_comma)
        if not c then json_error "object value terminator not ',' or '}'" end
      until c == '}' 
      return x
    end

    function value ()      -- already declared local 
      -- start at given character, test in order of probability
      local v = string () or object () or array () or number () or literal () 
      return v
    end

    local function parse_json ()
      if type (json) ~= "string" then json = type(json); error ("JSON input parameter is not a string", 0) end
      local warning
      local result = value ()        -- start at first character
      find (trailing_spaces) 
      if idx-1 ~= #json  then 
        warning = json_message "unexpected data after valid JSON string" 
      end
      return warning, result    
    end
    
    -- decode ()

    local _, message, Lua = pcall (parse_json)
    return Lua, message

  end  -- decode ()

  local function decode_wrapper (json)
    local ok, msg, try1, try2
    if is_cj then                          -- 2020.04.12  use cjson module, if available
      ok, try1 = pcall (cjson.decode, json)
      if ok then return try1 end
    end
    try2, msg = decode (json)
    return try2, msg or try1      -- use our message or the one from cjson error
  end

return {
  
    ABOUT = ABOUT,
    
    decode  = decode_wrapper,
    
    default = default,
    encode  = encode, 
    null    = json_null,
    
    Lua = {encode = encode, decode = decode},   -- direct access to Lua implementation
    
    C = is_cj and cjson or nil,                 -- direct access to C implementation
    
  }
