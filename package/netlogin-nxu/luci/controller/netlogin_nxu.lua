module("luci.controller.netlogin_nxu", package.seeall)

local fs = require("nixio.fs")

function index()
    if not fs.access("/etc/config/netlogin-nxu") then return end

    entry({"admin", "services", "netlogin_nxu"}, firstchild(),
        _("NXU NetLogin"), 60).dependent = false
    entry({"admin", "services", "netlogin_nxu", "status"},
        template("netlogin-nxu/status"), _("运行状态"), 1).leaf = true
    entry({"admin", "services", "netlogin_nxu", "config"},
        cbi("netlogin-nxu/config"), _("插件设置"), 10).leaf = true
    entry({"admin", "services", "netlogin_nxu", "data"},
        call("action_data"), nil).leaf = true
    entry({"admin", "services", "netlogin_nxu", "login"},
        call("action_login"), nil).leaf = true
    entry({"admin", "services", "netlogin_nxu", "logout"},
        call("action_logout"), nil).leaf = true
end

-- Match an exact argument, never return the command line (it may contain credentials).
local function process_count()
    local count = 0
    for pid in fs.dir("/proc") do
        if pid:match("^%d+$") then
            local command = fs.readfile("/proc/" .. pid .. "/cmdline") or ""
            for argument in command:gmatch("[^%z]+") do
                if argument == "/usr/bin/netlogin_openwrt.sh" then
                    count = count + 1
                    break
                end
            end
        end
    end
    return count
end

-- 仅接受带有效令牌的 POST，防止跨站请求触发登录或注销。
local function run_action(argument)
    local http = require("luci.http")
    local dispatcher = require("luci.dispatcher")
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    if http.getenv("REQUEST_METHOD") ~= "POST" or
        http.formvalue("token") ~= dispatcher.context.authtoken then
        http.status(403, "Forbidden")
        http.write_json({ ok = false })
        return
    end
    -- 注销后需要等待会话下线并重新获取 WAN 地址，可能超过 uhttpd 的脚本超时，所以放到后台执行，
    -- 进度在运行日志里查看。
    require("luci.sys").call("(/usr/bin/netlogin_openwrt.sh --uci " .. argument .. " >/dev/null 2>&1 &)")
    http.write_json({ ok = true, started = true })
end

function action_login() run_action("once") end

function action_logout() run_action("logout") end

function action_data()
    local http = require("luci.http")
    local sys = require("luci.sys")
    local uci = require("luci.model.uci").cursor()
    local status = sys.exec("curl -4 --noproxy '*' -fsS --connect-timeout 2 --max-time 3 --resolve netlogin.nxu.edu.cn:443:10.10.129.197 'https://netlogin.nxu.edu.cn/drcom/chkstatus?callback=dr1' 2>/dev/null")
    local result = status:match('"result"%s*:%s*(%d+)%s*[,}]')
    -- 门户状态里的 time 为累计在线分钟数（可能跨多次登录），flow 为累计已用流量（单位见 flow_unit 设置）；
    -- 带引号匹配，避免误取 oltime/olflow。仅在线时有意义。
    local minutes = result == "1" and tonumber(status:match('"time"%s*:%s*(%d+)')) or nil
    local flow = result == "1" and tonumber(status:match('"flow"%s*:%s*(%d+)')) or nil
    local login_time = result == "1" and status:match('"stime"%s*:%s*"(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d)"') or nil
    -- 门户未说明 flow 的单位，交给用户按实际情况选择（默认 KB）。
    local unit_bytes = ({ kb = 1024, mb = 1048576, word = 4, byte = 1 })[uci:get("netlogin-nxu", "main", "flow_unit") or "kb"] or 1024
    local logs = sys.exec("tail -n 300 /tmp/netlogin-nxu.log 2>/dev/null")
    if logs == "" then
        logs = sys.exec("logread -e ruijie-nxu 2>/dev/null | tail -n 300")
    end
    local processes = process_count()
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({
        running = processes > 0,
        paused = (fs.readfile("/tmp/netlogin-nxu.paused") or ""):match("^%s*(%a+)") or false,
        processes = processes,
        enabled = uci:get("netlogin-nxu", "main", "enabled") == "1",
        persistent = uci:get("netlogin-nxu", "main", "persistent_login") ~= "0",
        interval = tonumber(uci:get("netlogin-nxu", "main", "check_interval")) or 5,
        network = result == "1" and "online" or (result == "0" and "offline" or "unknown"),
        logs = logs:sub(-131072),
        online_minutes = minutes,
        login_time = login_time,
        flow = flow,
        flow_unit_bytes = unit_bytes,
        updated = os.date("%H:%M:%S")
    })
end
