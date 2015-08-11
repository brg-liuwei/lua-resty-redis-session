local json = require "cjson"
local redis = require "resty.redis"
local cookie = require "resty.cookie" -- https://github.com/cloudflare/lua-resty-cookie.git
local string = require "resty.string"

local ok, new_tab = pcall(require, "table.new")
if not ok then
    new_tab = function (narr, nrec)
        return {}
    end
end


local _M = new_tab(0, 64)

local mt = { __index = _M }

local function get_redis_conn(...)
    local red = redis:new()
    red:set_timeout(1000)
    local n = select('#')
    if n == 2 then
        red:connect(select(1, ...))
    elseif n == 1 then
        -- default port is 6379
        -- TODO: support UNIX path, eg: red:connect("unix:/path/to/redis.sock")
        red:connect(select(1, ...), 6379)
    else
        -- default ip is "127.0.0.1"
        red:connect("127.0.0.1", 6379)
    end
    return red
end

function _M.new(self, username, salt) 
    local session = {
        id = string.to_hex(ngx.hmac_sha1(salt, tostring(ngx.time()) .. username)),
        created = ngx.time(),
        domain = nil,
        data = { -- add user data here
            username = username,
        },
    }
    return setmetatable({ session = session }, mt)
end

-- domain should look like www.examplesite.com
-- notice: 'localhost' is an illegal domain name, see:
-- http://stackoverflow.com/questions/1134290/cookies-on-localhost-with-explicit-domain
function _M.set_domain(self, domain)
    local session = self.session
    if not session then
        return false, "session is not initialized"
    end
    session.domain = domain
    return true, ""
end

function _M.save(self, ...)
    local session = self.session
    if not session then
        ngx.log(ngx.ERR, "[session save] session not initialized")
        return false
    end

    if not session.domain then
        ngx.log(ngx.ERR, "[session save] need to set domain first")
        return false
    end

    local red = get_redis_conn(...)
    -- TODO: compress
    -- TODO: calc time interval and re-generate cookie
    local buf = json.encode(session)
    local ok, err = red:set(session.id, buf)
    if not ok then
        ngx.log(ngx.ERR, "[session save] redis set err: ", err)
        return false
    end

    local ok, err = red:expire(session.id, 3600)
    if not ok then
        ngx.log(ngx.ERR, "[session save] redis expire err: ", err)
        return false
    end

    red:set_keepalive(10000, 100)

    local ck, err = cookie:new()
    if not ck then
        ngx.log(ngx.ERR, "[session save] lua-resty-cookie new err: ", err)
        return false
    end

    local ok, err = ck:set({
        key = "42", -- HAHA, do you know what does forty-two mean?
        value = session.id,
        path = "/",
        domain = session.domain,
        httponly = true,
        -- secure = true, -- if use https, let secure = true
        expires = "Mon, 02 Mar 2024 05:06:07 GMT",
        max_age = 1000,
    })
    if not ok then
        ngx.log(ngx.ERR, "[session save] lua-resty-cookie set err: ", err)
        return false
    end

    return true
end

function _M.get(self, ...)
    local ck, err = cookie:new()
    if not ck then
        ngx.log(ngx.ERR, "[session get] lua-resty-cookie new err: ", err)
        return nil
    end

    local id, err = ck:get("42")
    if not id then
        ngx.log(ngx.ERR, "[session get] cookie get err: ", err)
        return nil
    end

    ngx.log(ngx.ERR, "get session id: ", id)

    local red = get_redis_conn(...)
    local res, err = red:get(id)
    if not res then
        ngx.log(ngx.ERR, "[session get] redis get id: ", id, " err: ", err) 
        return nil
    elseif res == ngx.null then
        ngx.log(ngx.ERR, "[session get] redis get id: ", id, " null") 
        local ok, err = red:ping()
        if ok then
            red:set_keepalive(10000, 100)
        end
        return nil
    end
    red:set_keepalive(10000, 100)
    local ok, s = pcall(json.decode, res)
    if not ok then
        ngx.log(ngx.ERR, "[session get] decode err. res: ", res)
        return nil
    end
    self.session = s
    return self
end

function _M.destroy(self, ...)
    self.session = {}
    local ck, err = cookie:new()
    if not ck then
        ngx.log(ngx.ERR, "[session destroy] lua-resty-cookie new err: ", err)
        return true
    end

    local id, err = ck:get("42")
    if not id then
        ngx.log(ngx.ERR, "[session destroy] cookie get err: ", err)
        return true
    end

    local red = get_redis_conn(...)
    local ok, err = red:del(id)
    if not ok then
        ngx.log(ngx.ERR, "[session destroy] redis destroy id: ", id, " err: ", err) 
        local ok, err = red:ping()
        if ok then
            red:set_keepalive(10000, 100)
        end
        return false
    end
    red:set_keepalive(10000, 100)
    return true
end

return _M
