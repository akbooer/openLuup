-- JSON encode/decode with full functionality including unicode escapes to UTF-8 encoding.
-- now does pretty-printing of encoded JSON strings.
-- (c) 2013,2014,2015  AK Booer

  local version    = "2015.04.11 @akbooer"   
  
-- 2015.04.10 allow comma before closing '}' or ']'
  
  local default   = 
    {
      huge = "8.88e888",          -- representation for JSON infinity (looks like infinity symbols on their side)
      max_array_length = 1000,    -- not a coding restriction, per se, just a sanity check against, eg {[1e6] = 1}
                                  -- since arrays are enumerated from starting index 1 with all the intervening 'nil' values
    }
    
    
  -- encode (), Lua to JSON
  local function encode (Lua)

        
    local function json_error (text, severity)    -- raise error
      severity = severity or 'error'
      error ( ('JSON encode %s : %s '): format (severity, text) , 0 ) 
    end
    
    local value               -- forward function reference
    local depth = 1           -- for pretty printing
    local encoding = {}       -- set of tables currently being encoded (to avoid infinite self reference loop)
    
    local function null    (x)   return "null"    end       --  nil
    local function boolean (x)   return tostring(x) end       --  true or false
    
    local function number  (x)
      if x ~=  x      then return     "null"  end       --  NaN
      if x >=  math.huge  then return      default.huge   end   -- +infinity
      if x <= -math.huge  then return '-'..default.huge   end   -- -infinity
      return tostring (x) 
    end

    local replace = {
         ['"']  = '\\"',    -- double quote
         ['/']  = '\\/',    -- solidus
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
    
    local function string  (x)                -- deal with escapes, etc. 
      local control_chars   = "%z\001-\031"   -- whole range of control characters
      local old = '[' .. '"' .. '/' .. '\\' .. control_chars .. ']'
      return '"' .. x:gsub (old, new) .. '"'
    end
    
    local function array (x, index)
      local items = {}
      table.sort (index)                -- to find min and max, numeric indices guaranteed 
      local min = index[1] or 1         -- index may be zero length
      local max = index[#index] or 0    -- max less than min for empty matrix
      if min < 1                        then json_error 'array start index is less than 1' end
      if max > default.max_array_length then json_error 'array final index is too large'   end 
      for i = 1, max do
        items[i] = value (x[i])         -- may contain nulls
      end
      return '[' .. table.concat (items, ',') .. ']'
    end
     
    local function object (x, index)  
      local items, crlf = {}, ''
      table.sort (index)                -- nice ordering, string indices guaranteed 
      if #index > 1 then crlf = '\n'.. ('  '):rep(depth) end
      depth = depth + 1
      for i,j in ipairs (index) do
        items[i] = string(j) ..':'.. value (x[j])
      end
      depth = depth - 1
      return table.concat {'{', crlf, table.concat (items, ','..crlf), '}'}
    end
  
    local function object_or_array (x)
      local index, result = {}
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
      if only_numbers then result = array (x, index) 
      elseif only_strings then result = object (x, index) 
      else json_error "table has mixed numeric and string indices" end
      encoding [x] = nil          -- finished encoding this structure
      return result
    end

    local lua_type  = {           -- dispatch table for different types
          table = object_or_array,
          string  = string,
          number  = number,
          boolean = boolean,
          ["nil"] = null,
        }

    local function err(x) json_error ("can't encode type '".. type(x) .."'" ) end
    
    function value (x)            -- already declared local
      return (lua_type [type(x)] or err) (x)      
    end
    
    -- encode()
    
    local ok, message, json = pcall (function () return nil, value(Lua) end)
    return json, message
    
  end -- encode ()


  -- decode (json), decodes a json string, returning (value) or (value, warning_message) or (nil, error_message) 
  local function decode (json)
  
    local openbrace       = '^%s*(%{)%s*'   -- note that all the search strings are anchored to the start
    local openbracket     = '^%s*(%[)%s*'
    local openquote       = '^%s*%"'
    local endquote_or_backslash = '^([^"\\]-)(["\\])'
    local trailing_spaces   = '^"%s*'

    local numeric_string    = '^%s*([%-]?%d+[%.]?%d*[Ee]?[%+%-]?%d*)%s*'
    local literal_string    = '^%s*(%a+)%s*'
    local colon_separator   = '^:%s*'
    local UTF_code          = '^u(%x%x%x%x)'
  
    local endbrace            = '^%s*(%})%s*'
    local endbracket          = '^%s*(%])%s*'
    local endbrace_or_comma   = '^%s*([%},])%s*'
    local endbracket_or_comma = '^%s*([%],])%s*'
  
    local value         -- forward definition for recursive function
    
    local function json_message (text, position, severity)    -- format error or warning
      severity = severity or 'error'
      return ("JSON decode %s @[%d of %d]: %s at or near '%s'"): 
            format (severity, position, #json, text, json:sub(position,position + 20) )
    end
    
    -- note that inline 'if ... then ... end' calls to this are significantly faster than an 'assert' function call
    local function json_error (...) error ( json_message (...), 0 ) end   -- raise error
      
    
    local valid_literal = {["true"] = {true}, ["false"]= {false}, ["null"] = {nil} }    -- anything else invalid

    local function literal (i)
      local a,b,c = json:find (literal_string, i) 
      if a and valid_literal[c] then return {x = valid_literal[c][1], b = b} end
    end

    local function number (i)
      local a,b,c = json:find (numeric_string, i) 
      if a then return {x = tonumber (c), b = b} end
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
    
    local function escape_replacement (b)
      local a,c
      c = json:sub (b,b)              -- pick up escaped character
      if c == 'u' then                  -- special UTF hex code
        local i = b
        a,b,c = json:find (UTF_code, b) 
        if not a then json_error ("escape \\u not followed by four hex digits", i) end 
        c = utf8 (tonumber (c, 16))        -- convert to UTF-8 Basic Multilingual Plane codepoint
      end
      return replace[c] or c, b
    end
    
    local function string (i)     
      local a,b,c,t = json:find (openquote, i)
      if not a then return end
      local str = {}
      repeat
        local i = b+1
        a,b,c,t = json:find (endquote_or_backslash, i)
        if not a then json_error ("unterminated string", i) end
        str[#str+1] = c                           -- save the string segment
        if t == '\\' then str[#str+1], b = escape_replacement (b+1) end   -- deal with escapes
      until t == '"' 
      a,b = json: find (trailing_spaces, b) 
      return {x = table.concat(str), b = b} 
    end
    
    local function array (i)
      local a,b,c,b2 = json:find (openbracket, i) 
      if not a then return end
      local n = 0                     -- can't use #x because of possible nil values in x
      local x = {}
      while c ~= ']' do
        a,b2,c = json:find (endbracket, b+1)
        if a then b=b2 break end      -- maybe there was nothing after that last comma
        local val = value (b+1)
        if not val then json_error ("array value invalid", b+1) end
        n = n+1 
        x[n] = val.x
        a,b,c = json:find (endbracket_or_comma, val.b+1)
        if not a then json_error ("array value terminator not ',' or ']'", val.b+1) end
      end
      return {x = x, b = b}
    end
    
    local function object (i)
      local a,b,c,b2 = json:find (openbrace, i) 
      if not a then return end 
      local x = {}
      while c ~= '}' do
        a,b2,c = json:find (endbrace, b+1)
        if a then b=b2 break end      -- maybe there was nothing after that last comma
        local name = string (b+1)
        if not name then json_error ("object name invalid", b+1) end
        a,b = json:find (colon_separator, name.b+1)
        if not a then json_error ("object name not followed by ':'", name.b+1) end
        local val = value (b+1)
        if not val then json_error ("object value invalid", b+1) end
        x[name.x] = val.x
        a,b,c = json:find (endbrace_or_comma, val.b+1)
        if not c then json_error ("object value terminator not ',' or '}'", val.b+1) end
      end 
      return {x = x, b = b}
    end

    function value (i)      -- already declared local 
      return string (i) or object (i) or array (i) or number (i) or literal (i) -- start at given character, test in order of probability
          or json_error ("invalid JSON syntax", i)
    end

    local function parse_json ()
      if type (json) ~= "string" then json = type(json); json_error ("JSON input parameter is not a string", 1) end
      local warning
      local result = value (1)        -- start at first character
      if result.b ~= #json  then 
        warning = json_message ("not all of json string parsed", result.b, "warning")  
      end
      return warning, result.x    
    end
    
    -- decode ()

    local ok, message, Lua = pcall (parse_json, 1)
    return Lua, message

  end  -- decode ()

  
return {encode = encode, decode = decode, version = version, default = default}
