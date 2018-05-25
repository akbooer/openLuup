local md5sum, md5_library

do -- select MD5 library

    local ok, mod = pcall(require, "crypto")
    if ok then
        local digest = (mod.evp or mod).digest
        if digest then
            md5sum = function(str) return digest("md5", str) end
            md5_library = "crypto"
        end
    end

    if not md5sum then
        ok, mod = pcall(require, "md5")
        if ok then
            local md5 = (type(mod) == "table") and mod or _G.md5
            md5sum = md5.sumhexa or md5.digest
            if md5sum then md5_library = "md5" end
        end
    end

    if not md5sum then
        ok = pcall(require, "digest") -- last because using globals
        if ok and _G.md5 then md5sum = _G.md5.digest end
        if md5sum then md5_library = "digest" end
    end

end

assert(md5sum, "cannot find supported md5 module")

local s_http = require "socket.http"
local s_url = require "socket.url"
local ltn12 = require "ltn12"

local hash = function(...)
    return md5sum(table.concat({...}, ":"))
end

local parse_header = function(h)
    local r = {}
    for k,v in (h .. ','):gmatch("(%w+)=(.-),") do
        if v:sub(1, 1) == '"' then -- strip quotes
            r[k:lower()] = v:sub(2, -2)
        else r[k:lower()] = v end
    end
    return r
end

local make_digest_header = function(t)
    local s = {}
    local x
    for i=1,#t do
        x = t[i]
        if x.unquote then
            s[i] =  x[1] .. '=' .. x[2]
        else
            s[i] = x[1] .. '="' .. x[2] .. '"'
        end
    end
    return "Digest " .. table.concat(s, ', ')
end

local hcopy = function(t)
    local r = {}
    for k,v in pairs(t) do r[k] = v end
    return r
end

local _request = function(t)
    if not t.url then error("missing URL") end
    local url = s_url.parse(t.url)
    local user, password = url.user, url.password
    if not (user and password) then
        error("missing credentials in URL")
    end
    url.user, url.password, url.authority, url.userinfo = nil, nil, nil, nil
    t.url = s_url.build(url)
    local ghost_source
    if t.source then
        local ghost_chunks = {}
        local ghost_capture = function(x)
            if x then ghost_chunks[#ghost_chunks+1] = x end
            return x
        end
        local ghost_i = 0
        ghost_source = function()
            ghost_i = ghost_i+1
            return ghost_chunks[ghost_i]
        end
        t.source = ltn12.source.chain(t.source, ghost_capture)
    end
    local b, c, h = s_http.request(t)
    if (c == 401) and h["www-authenticate"] then
        local ht = parse_header(h["www-authenticate"])
        assert(ht.realm and ht.nonce)
        if ht.qop ~= "auth" then
            return nil, string.format("unsupported qop (%s)", tostring(ht.qop))
        end
        if ht.algorithm and (ht.algorithm:lower() ~= "md5") then
            return nil, string.format("unsupported algo (%s)", tostring(ht.algorithm))
        end
        local nc, cnonce = "00000001", string.format("%08x", os.time())
        local uri = s_url.build{path = url.path, query = url.query}
        local method = t.method or "GET"
        local response = hash(
            hash(user, ht.realm, password),
            ht.nonce,
            nc,
            cnonce,
            "auth",
            hash(method, uri)
        )
        t.headers = t.headers or {}
        local auth_header = {
            {"username", user},
            {"realm", ht.realm},
            {"nonce", ht.nonce},
            {"uri", uri},
            {"cnonce", cnonce},
            {"nc", nc, unquote=true},
            {"qop", "auth"},
            {"algorithm", "MD5"},
            {"response", response},
        }
        if ht.opaque then
            table.insert(auth_header, {"opaque", ht.opaque})
        end
        t.headers.authorization = make_digest_header(auth_header)
        if not t.headers.cookie and h["set-cookie"] then
            -- not really correct but enough for httpbin
            local cookie = (h["set-cookie"] .. ";"):match("(.-=.-)[;,]")
            if cookie then
                t.headers.cookie = "$Version: 0; " .. cookie .. ";"
            end
        end
        if t.source then t.source = ghost_source end
        b, c, h = s_http.request(t)
        return b, c, h
    else return b, c, h end
end

local request = function(x)
    local _t = type(x)
    if _t == "table" then
        return _request(hcopy(x))
    elseif _t == "string" then
        local r = {}
        local _, c, h = _request{url = x, sink = ltn12.sink.table(r)}
        return table.concat(r), c, h
    else error(string.format("unexpected type %s", _t)) end
end

return {
    md5_library = md5_library,
    request = request,
}
