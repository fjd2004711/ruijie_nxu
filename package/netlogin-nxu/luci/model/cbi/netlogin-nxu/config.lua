local m = Map("netlogin-nxu", translate("NXU NetLogin"),
    translate("配置校园网账号、持久登录和认证状态。密码保存在路由器的 UCI 配置中。"))

local s = m:section(NamedSection, "main", "netlogin_nxu")
s.anonymous = true
s.addremove = false
s:tab("account", translate("账号与服务"))
s:tab("policy", translate("运行策略"))
s:tab("display", translate("显示与日志"))

-- 醒目的使用前提示：无感知认证（MAC 绑定）开启时，注销或换账号会被旧账号立即重新登录。
local notice = s:taboption("account", DummyValue, "_notice")
notice.rawhtml = true
notice.value = [[<style>
.cbi-value:has(.nxu-notice)>.cbi-value-title{display:none}
.cbi-value:has(.nxu-notice)>.cbi-value-field{width:100%;margin:0;padding:0}
.nxu-notice{display:flex;gap:14px;align-items:flex-start;max-width:820px;padding:16px 20px;border-radius:14px;border:1px solid rgba(245,158,11,.45);background:linear-gradient(135deg,rgba(251,191,36,.16),rgba(245,158,11,.07));color:inherit}
.nxu-notice-icon{width:36px;height:36px;border-radius:10px;flex-shrink:0;display:grid;place-items:center;background:#f59e0b;color:#fff;font-weight:800;font-size:19px}
.nxu-notice b{display:block;font-size:15px;line-height:1.5;margin-bottom:4px}
.nxu-notice p{margin:0;font-size:13.5px;line-height:1.75;opacity:.85}
.nxu-notice a{color:#d97706;font-weight:600;text-decoration:underline;text-underline-offset:2px}
.cbi-tabmenu{margin-top:6px}
.cbi-value-description{font-size:12.5px;opacity:.7;line-height:1.6}
</style>
<div class="nxu-notice"><div class="nxu-notice-icon">!</div><div><b>使用前必读：请先关闭「无感知认证」（MAC 绑定）</b><p>否则注销或更换账号后，会被旧账号立即重新登录，表现为「改了账号还是旧账号在线」。请登录 <a href="https://netself.nxu.edu.cn/Self/dashboard" target="_blank" rel="noopener">校园网自助服务</a>，关闭无感知认证并解除路由器 MAC 的绑定；也可在认证门户登录成功页的「终端在线表」中点击「解除绑定」。</p></div></div>]]

local enabled = s:taboption("account", Flag, "enabled", translate("启用服务"))
enabled.default = 0
enabled.rmempty = false
enabled.description = translate("保存后服务会按此开关运行。")

local persistent = s:taboption("account", Flag, "persistent_login", translate("持久登录"))
persistent.default = 1
persistent.rmempty = false
persistent.description = translate("持续检测网络并在断线后自动重新认证。关闭时只执行一次检查/认证。")

local service = s:taboption("account", Value, "service", translate("服务类型"))
service.default = "campus"
service.rmempty = false
service.description = translate("当前 NetLogin 页面不再区分运营商，建议保持 campus。")

local username = s:taboption("account", Value, "username", translate("账号"))
username.rmempty = false

local password = s:taboption("account", Value, "password", translate("密码"))
password.password = true
password.rmempty = false

local level = s:taboption("display", ListValue, "log_level", translate("日志级别"))
level:value("ERROR")
level:value("WARN")
level:value("INFO")
level:value("DEBUG")
level.default = "INFO"
level.rmempty = false

local interval = s:taboption("policy", Value, "check_interval", translate("检测间隔（秒）"))
interval.datatype = "uinteger"
interval.default = "5"
interval.rmempty = false
interval.description = translate("建议 5 秒或更高，避免频繁请求认证页面。")

local failures = s:taboption("policy", Value, "max_failures", translate("连续失败上限"))
failures.datatype = "uinteger"
failures.default = "5"
failures.rmempty = false
failures.description = translate("连续被服务器拒绝登录达到此次数后暂停自动重试，避免密码错误导致账号被锁定；填 0 表示不限制。")

local unit = s:taboption("display", ListValue, "flow_unit", translate("流量单位"))
unit:value("kb", translate("KB（1 单位 = 1024 字节，Dr.COM 惯例）"))
unit:value("word", translate("4 字节（1 单位 = 4 字节）"))
unit:value("byte", translate("字节"))
unit:value("mb", translate("MB"))
unit.default = "kb"
unit.rmempty = false
unit.description = translate("门户返回的已用流量未标明单位。若状态页显示的流量与校园网自助服务里的数值相差悬殊，请切换此项；状态页流量旁的原始数值可用于对照。")

function m.on_after_commit(self)
    -- 后台重启：不阻塞页面。重启时守护进程会补上被中断的 WAN 操作并释放互斥锁；
    -- 正在进行的手动认证/注销不受影响（新旧进程通过互斥锁串行）。
    sys.call("(/etc/init.d/netlogin-nxu restart >/dev/null 2>&1 &)")
end

return m
