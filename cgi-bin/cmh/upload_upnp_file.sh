#!/usr/bin/env wsapi.cgi

module(..., package.seeall)

-- @vosmont's implementation of /cgi-bin/cmh/upload_upnp_file.sh
-- converted to WSAPI application by @akbooer
-- see: http://keplerproject.github.io/wsapi/manual.html
--
-- 2016.02.18  extract vosmont's modification from openLuup.server and make into WSAPI app
--

local _log    -- defined from WSAPI environment as error.write(...) in run() method.

-- create the file
local function upload_file (URL)
  local file, status, result
  local path = "" -- should use a specific folder for security reason ?
  local fileName, fileContent = URL.upnp_file_1_name, URL.upnp_file_1
  if fileName and fileContent then 
    file = io.open(path .. fileName, "w") 
  end
  fileName = fileName or '?'
  if (file == nil) then
    _log ("File '" .. path .. fileName .. "' cannot be created")
     result = "KO"
     status = 400   -- Bad Request.
  else
    file:write(fileContent)
    file:close()
    _log ("File '" .. path .. fileName .. "' has been written")
    result = "OK"
    status = 201    -- Created. The request has been fulfilled and resulted in a new resource being created
  end
  return status, result .. "|" .. fileName, "text/html"
end
 
-- gets headers in multipart content
local function read_part_headers (content, pos)
	local EOH = "\r\n\r\n"
	local i, j = string.find(content, EOH, pos, true)
	if i then
		local header_data = string.sub(content, pos, j - 1)
		local headers = {}
		for type, val in string.gmatch(header_data, '([^%c%s:]+):%s+([^\n]+)') do
			headers[type] = val
		end
		return headers, j + 1
	else
		return nil, pos
	end
end

-- gets fields in multipart headers
local function get_field_names(headers)
	local disp_header = headers["Content-Disposition"] or ""
	local attrs = {}
	for attr, val in string.gmatch(disp_header, ';%s*([^%s=]+)="(.-)"') do
		attrs[attr] = val
	end
	return attrs.name, attrs.filename and string.match(attrs.filename, "[/\\]?([^/\\]+)$")
end

-- gets the data in multipart content
local function read_field_content(content, boundary, pos)
	local i, j = string.find(content, "\r\n" .. boundary, pos, true)
	if i then
		return string.sub(content, pos, i - 1), j + 1
	else
		return nil, pos
	end
end


-- global entry point called by WSAPI connector

--[[

The environment is a Lua table containing the CGI metavariables (at minimum the RFC3875 ones) plus any 
server-specific metainformation. It also contains an input field, a stream for the request's data, 
and an error field, a stream for the server's error log. 

The input field answers to the read([n]) method, 
where n is the number of bytes you want to read 
(or nil if you want the whole input). 

The error field answers to the write(...) method.

return values: the HTTP status code, a table with headers, and the output iterator. 

--]]

function run (wsapi_env)
  _log = wsapi_env.error.write     -- set up the log output
  
	-- vosmont : add upload file management
  -- inspired from https://github.com/keplerproject/wsapi
  local URL = {}
  
  -- get POST content, 
  local post_content = wsapi_env.input.read()
  
  local content_type = wsapi_env["CONTENT_TYPE"]
  
  -- get uploaded file
  if string.find(content_type, "multipart/form-data", 1, true) then
    local boundary = "--" .. string.match(content_type, "boundary%=(.-)$")
    -- get all the parts
    local pos = 1
    local _, part_headers, name, value
    _, pos = string.find(post_content, boundary, 1, true)
    pos = pos + 1
    part_headers, pos = read_part_headers(post_content, pos)
    while (part_headers) do
      --_log ("HTTP POST request multipart headers : " .. json.encode(part_headers))
      name, _ = get_field_names(part_headers) -- do not use "file_name" in Vera implementation of uploading files
      value, pos = read_field_content(post_content, boundary, pos)
      URL[name] = value
      -- prepare next multipart scan
      part_headers, pos = read_part_headers(post_content, pos)
    end
  end
  --_log ("HTTP POST request content : " .. post_content)
  --_log ("HTTP POST request content : " .. json.encode(URL))

  local status, return_content, return_content_type = upload_file (URL)
  
  local headers = {["Content-Type"] = return_content_type}
  
  local function iterator ()     -- one-shot iterator, returns content, then nil
    local x = return_content
    return_content = nil 
    return x
  end

  return status, headers, iterator
end

-----
