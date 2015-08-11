lua-resty-redis_session-module
==============================


Dependency
----------
** [lua-resty-cookie](https://github.com/cloudflare/lua-resty-cookie) **


Install
-------
    git clone https://github.com/cloudflare/lua-resty-cookie.git
    git clone https://github.com/brg-liuwei/lua-resty-redis_session.git

** assume the install path of openresty is /usr/local/openresty/ **

    cp lua-resty-cookie/lib/resty/cookie.lua /usr/local/openresty/lualib/resty/
    cp lua-resty-redis_session/lib/resty/redis_session.lua /usr/local/openresty/lualib/resty/
    
Example
-------
** set host (your browser may not support set cookie at localhost) **

** see: [http://stackoverflow.com/questions/1134290/cookies-on-localhost-with-explicit-domain](http://stackoverflow.com/questions/1134290/cookies-on-localhost-with-explicit-domain) **

    echo "127.0.0.1 www.mysite.com" | sudo tee -a /etc/hosts

** edit your nginx config file: **

    server {
        server_name www.mysite.cn; # important! CANNOT use localhost
        ...
        
        location /login {
            content_by_lua '
                ngx.header["Content-Type"] = "text/html"
                ngx.say("<html><body><a href=/start?name=xiaolaoshi&passwd=123456>Start the test</a>!</body></html>")
            ';
        }
        
        location /start {
            content_by_lua '
                ngx.header["Content-Type"] = "text/html"
                local name = ngx.var.arg_name
                local passwd = ngx.var.arg_passwd
                if not name or not passwd then
                    ngx.say("need name and passwd")
                    return
                end
        
                local session = require "resty.redis_session"
                local s = session:new(name, passwd)
                local ok, err = s:set_domain("www.mysite.cn")
                if not ok then
                    ngx.say("set domain err: ", err)
                    return
                end

                # write some infomation into s.session.data
                s.session.data.ctx = "let us test lua-resty-redis_session-module"
                if not s:save() then
                    ngx.say("save error")
                    return
                end
         
                ngx.say("<html><body>Session started. ",
                    "<a href=/test>Check if it is working</a>!</body></html>")
            ';
        }
        
        location /test {
            content_by_lua '
                ngx.header["Content-Type"] = "text/html"
                local session = require "resty.redis_session"
                local s = session:get()
                if not s then
                    return ngx.redirect("/login")
                end
                
                ngx.say("<html><body>Session was started by <strong>",
                    s.session.data.name or "Anonymous",
                    "</strong>! <p>context: ",
                    s.session.data.ctx or "not context",
                    "</p><div><p><a href=/destroy>click here to destroy session",
                    "</p></a></div></body></html>")
            ';
        }
        
        location /destroy {
            content_by_lua '
                ngx.header["Content-Type"] = "text/html"
                local session = require "resty.redis_session"
                if session:destroy() then
                    ngx.say("<html><body><div><p>clean session successfully</p>",
                        "<a href=/test>Click here to test</a></div></body></html>")
                else
                    ngx.say("<html><body>clean session failed</body></html>")
                end
            ';
        }
    }

** reload nginx **

    /usr/local/openresty/nginx/sbin/nginx -sreload -c /path/to/your/nginx.conf
