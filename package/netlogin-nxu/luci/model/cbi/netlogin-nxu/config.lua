local sys = require("luci.sys")

local m = Map("netlogin-nxu", translate("NXU NetLogin"),
    translate("配置校园网账号、持久登录和认证状态。密码保存在路由器的 UCI 配置中。"))

local s = m:section(NamedSection, "main", "netlogin_nxu")
s.anonymous = true
s.addremove = false

local enabled = s:option(Flag, "enabled", translate("启用服务"))
enabled.default = 0
enabled.rmempty = false
enabled.description = translate("保存后服务会按此开关运行。")

local persistent = s:option(Flag, "persistent_login", translate("持久登录"))
persistent.default = 1
persistent.rmempty = false
persistent.description = translate("持续检测网络并在断线后自动重新认证。关闭时只执行一次检查/认证。")

local service = s:option(Value, "service", translate("服务类型"))
service.default = "campus"
service.rmempty = false
service.description = translate("当前 NetLogin 页面不再区分运营商，建议保持 campus。")

local username = s:option(Value, "username", translate("账号"))
username.rmempty = false

local password = s:option(Value, "password", translate("密码"))
password.password = true
password.rmempty = false

local level = s:option(ListValue, "log_level", translate("日志级别"))
level:value("ERROR")
level:value("WARN")
level:value("INFO")
level:value("DEBUG")
level.default = "INFO"
level.rmempty = false

local interval = s:option(Value, "check_interval", translate("检测间隔（秒）"))
interval.datatype = "uinteger"
interval.default = "5"
interval.rmempty = false
interval.description = translate("建议 5 秒或更高，避免频繁请求认证页面。")

function m.on_after_commit(self)
    sys.call("/etc/init.d/netlogin-nxu restart >/dev/null 2>&1")
end

return m
