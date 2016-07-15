-- mimetypes
-- 2016/04/14
-- thanks to @explorer for suggesting a separate file

-- these entries are used to determine the response type of HTML
-- file transfer requests using the file extension code
-- syntax is extension = "return type",
-- feel free to add what you need

-- 2016.07.14  added status_codes for server response

local mimetypes = {
  css  = "text/css", 
  gif  = "image/gif",
  html = "text/html", 
  htm  = "text/html", 
  ico  = "image/x-icon",
  jpeg = "image/jpeg",
  jpg  = "image/jpeg",
  js   = "application/javascript",
  json = "application/json",
  mid  = "audio/mid",
  mp3  = "audio/mpeg",
  png  = "image/png",
  txt  = "text/plain",
  wav  = "audio/wav",
  xml  = "application/xml",
}


-- HTTP status codes (from wsapi.common)
local status_codes = {
   [100] = "Continue",
   [101] = "Switching Protocols",
   [200] = "OK",
   [201] = "Created",
   [202] = "Accepted",
   [203] = "Non-Authoritative Information",
   [204] = "No Content",
   [205] = "Reset Content",
   [206] = "Partial Content",
   [300] = "Multiple Choices",
   [301] = "Moved Permanently",
   [302] = "Found",
   [303] = "See Other",
   [304] = "Not Modified",
   [305] = "Use Proxy",
   [307] = "Temporary Redirect",
   [400] = "Bad Request",
   [401] = "Unauthorized",
   [402] = "Payment Required",
   [403] = "Forbidden",
   [404] = "Not Found",
   [405] = "Method Not Allowed",
   [406] = "Not Acceptable",
   [407] = "Proxy Authentication Required",
   [408] = "Request Time-out",
   [409] = "Conflict",
   [410] = "Gone",
   [411] = "Length Required",
   [412] = "Precondition Failed",
   [413] = "Request Entity Too Large",
   [414] = "Request-URI Too Large",
   [415] = "Unsupported Media Type",
   [416] = "Requested range not satisfiable",
   [417] = "Expectation Failed",
   [500] = "Internal Server Error",
   [501] = "Not Implemented",
   [502] = "Bad Gateway",
   [503] = "Service Unavailable",
   [504] = "Gateway Time-out",
   [505] = "HTTP Version not supported",
}

return {
    mimetypes     = mimetypes,
    status_codes  = status_codes,
  }
  
-----
