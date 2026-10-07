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

function action_data()
    local http = require("luci.http")
    local sys = require("luci.sys")
    local uci = require("luci.model.uci").cursor()
    local status = sys.exec("curl -4 --noproxy '*' -fsS --connect-timeout 2 --max-time 3 --resolve netlogin.nxu.edu.cn:443:10.10.129.197 'https://netlogin.nxu.edu.cn/drcom/chkstatus?callback=dr1' 2>/dev/null")
    local result = status:match('"result"%s*:%s*(%d+)%s*[,}]')
    local logs = sys.exec("logread -e ruijie-nxu 2>/dev/null | tail -n 300")
    local processes = process_count()
    http.header("Cache-Control", "no-store")
    http.prepare_content("application/json")
    http.write_json({
        running = processes > 0,
        processes = processes,
        enabled = uci:get("netlogin-nxu", "main", "enabled") == "1",
        persistent = uci:get("netlogin-nxu", "main", "persistent_login") ~= "0",
        interval = tonumber(uci:get("netlogin-nxu", "main", "check_interval")) or 5,
        network = result == "1" and "online" or (result == "0" and "offline" or "unknown"),
        logs = logs:sub(-131072),
        updated = os.date("%H:%M:%S")
    })
end
