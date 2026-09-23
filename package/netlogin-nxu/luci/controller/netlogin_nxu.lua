module("luci.controller.netlogin_nxu", package.seeall)

local fs = require("nixio.fs")

function index()
    if not fs.access("/etc/config/netlogin-nxu") then
        return
    end

    entry({"admin", "services", "netlogin_nxu"},
        firstchild(),
        _("NXU NetLogin"), 60).dependent = false

    entry({"admin", "services", "netlogin_nxu", "config"},
        cbi("netlogin-nxu/config"),
        _("Configuration"), 1).leaf = true

    entry({"admin", "services", "netlogin_nxu", "status"},
        call("action_status"),
        _("Status"), 10).leaf = true
end

function action_status()
    local http = require("luci.http")
    local sys = require("luci.sys")

    http.prepare_content("text/plain; charset=utf-8")
    http.write(sys.exec("/etc/init.d/netlogin-nxu status 2>/dev/null"))
end
