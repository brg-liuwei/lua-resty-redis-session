lua-resty-redis-session-module
==============================

概述
----
春哥的**[openresty](http://openresty.org/)**可以用来快速开发非常高性能的**Restful API**服务，同理，openresty亦可用于构建Web服务。较之于API而言，Web服务需要考虑用户会话(session)的管理。目前openresty尚未发布官方的session管理模块，github上的[https://github.com/bungle/lua-resty-session](https://github.com/bungle/lua-resty-session)模块实现了会话管理，其实现是基于**SecuritySession**（谢谢[肖老师](https://github.com/xiaoq08)告诉我这个名词）协议，把会话信息全部存放在cookie中，当会话信息足够多时，这样做是比较耗费带宽的。而实现会话管理的另一个方法就是把会话信息存放在服务端，在cookie中带上全局唯一的会话id。本模块就是根据这个思想，把session信息存放在redis中，把会话id存放在cookie中，根据session-id，去redis中查询session信息。


包依赖
----------
除去openresty中自带的官方包，本模块还依赖于cloudflare开源的**[lua-resty-cookie](https://github.com/cloudflare/lua-resty-cookie)**模块进行cookie操作。


安装
-------
    git clone https://github.com/cloudflare/lua-resty-cookie.git
    git clone https://github.com/brg-liuwei/lua-resty-redis_session.git

**我们假设你的openresty的安装路径是 /usr/local/openresty/**

    cp lua-resty-cookie/lib/resty/cookie.lua /usr/local/openresty/lualib/resty/
    cp lua-resty-redis_session/lib/resty/redis_session.lua /usr/local/openresty/lualib/resty/

一言以敝之，就是下载好本模块和lua-resty-cookie的代码，把对应的lua文件拷贝到resty目录即可（当然，你也可以采用建立软链接或者在nginx配置文件中设置lua path等方式）
    
使用示例
--------
如果是在本地测试，需要自己配一个host，该host必须是类似于**www.mysite.com**的形式，要至少有两个点才行。因为如果访问的url domain不是域名的格式，浏览器可能会忽略掉Set-Cookie指令，因此如果使用localhost来测试，是不会成功的。这个问题具体可见： **[http://stackoverflow.com/questions/1134290/cookies-on-localhost-with-explicit-domain](http://stackoverflow.com/questions/1134290/cookies-on-localhost-with-explicit-domain)**

    echo "127.0.0.1 www.mysite.com" | sudo tee -a /etc/hosts

**下面是个nginx配置文件的示例**

    server {
        server_name www.mysite.cn; # 注意，这里指定你配置的域名
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
                    s.session.data.username or "Anonymous",
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

**重启nginx**

    /usr/local/openresty/nginx/sbin/nginx -sreload -c /path/to/your/nginx.conf
