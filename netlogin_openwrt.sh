#!/bin/sh

# 宁夏大学校园网 NetLogin 认证脚本（OpenWrt/ash 版本）
# 命令行：./netlogin_openwrt.sh <服务提供商> <用户名> <密码> [action] [log_level]
# 服务模式：./netlogin_openwrt.sh --uci
uci_get() {
    uci_value=$(uci -q get "$1" 2>/dev/null) || uci_value=""
    if [ -n "$uci_value" ]; then
        printf '%s\n' "$uci_value"
    else
        printf '%s\n' "$2"
    fi
}

if [ "$1" = "--uci" ]; then
    if ! command -v uci >/dev/null 2>&1; then
        echo "错误：--uci 模式需要 OpenWrt 的 uci 命令。" >&2
        exit 1
    fi
    service=$(uci_get netlogin-nxu.main.service campus)
    username=$(uci_get netlogin-nxu.main.username "")
    password=$(uci_get netlogin-nxu.main.password "")
    action=""
    log_level=$(uci_get netlogin-nxu.main.log_level INFO)
    persistent_login=$(uci_get netlogin-nxu.main.persistent_login 1)
    check_interval=$(uci_get netlogin-nxu.main.check_interval 5)
else
    if [ "$#" -lt 3 ]; then
        echo "使用方法: $0 <服务提供商> <用户名> <密码> [action] [log_level]"
        echo "或使用 OpenWrt 配置模式: $0 --uci"
        exit 1
    fi
    service="$1"
    username="$2"
    password="$3"
    action="${4:-}"
    log_level="${5:-INFO}"
    persistent_login=1
    check_interval=5
fi

if [ -z "$username" ] || [ -z "$password" ]; then
    echo "错误：未配置校园网账号或密码。" >&2
    exit 1
fi

case "$persistent_login" in
    0|1) ;;
    *) persistent_login=1 ;;
esac

case "$check_interval" in
    ''|*[!0-9]|0) check_interval=5 ;;
esac

# 日志级别枚举（数值越小，级别越高）
# ash 不支持关联数组，使用简单的数值代替
ERROR_LEVEL=0
WARN_LEVEL=1
INFO_LEVEL=2
DEBUG_LEVEL=3

# 获取当前设置的日志级别对应的数值
current_level=$INFO_LEVEL
case "$log_level" in
    ERROR)
        current_level=$ERROR_LEVEL
        ;;
    WARN)
        current_level=$WARN_LEVEL
        ;;
    INFO)
        current_level=$INFO_LEVEL
        ;;
    DEBUG)
        current_level=$DEBUG_LEVEL
        ;;
    *)
        echo "无效的日志级别: $log_level"
        echo "有效的日志级别: ERROR, WARN, INFO, DEBUG"
        log_level="INFO"
        echo "使用默认日志级别: $log_level"
        current_level=$INFO_LEVEL
        ;;
esac

retry_limit=99

network_status=""

# 记录日志的函数
# 用法: log_message <级别> <消息>
log_message() {
    level=$1
    message=$2
    log_level_value=3  # 默认为DEBUG级别

    case "$level" in
        ERROR)
            log_level_value=$ERROR_LEVEL
            ;;
        WARN)
            log_level_value=$WARN_LEVEL
            ;;
        INFO)
            log_level_value=$INFO_LEVEL
            ;;
        DEBUG)
            log_level_value=$DEBUG_LEVEL
            ;;
    esac

    # 只有当消息的日志级别小于或等于当前设置的日志级别时才记录。
    # OpenWrt 的 logd 使用有界环形缓冲区，不写入不断增长的日志文件。
    if [ "$log_level_value" -le "$current_level" ]; then
        priority="info"
        case "$level" in
            ERROR) priority="err" ;;
            WARN) priority="warning" ;;
            DEBUG) priority="debug" ;;
        esac

        if command -v logger >/dev/null 2>&1; then
            logger -t ruijie-nxu -p "user.$priority" "$message" 2>/dev/null
        fi
        echo "[$level] $message"
    fi
}

# 便捷的日志函数
log_error() {
    log_message "ERROR" "$1"
}

log_warn() {
    log_message "WARN" "$1"
}

log_info() {
    log_message "INFO" "$1"
}

log_debug() {
    log_message "DEBUG" "$1"
}

# 只在网络状态发生变化时记录一次，避免轮询期间重复刷屏。
last_log_state=""
log_state() {
    state="$1"
    level="$2"
    message="$3"
    [ "$last_log_state" = "$state" ] && return
    last_log_state="$state"
    log_message "$level" "$message"
}

check_connection() {
    # 登录页在已认证状态会返回 Dr.COMWebLoginID_1.htm；不依赖可能受限的校外站点。
    log_debug "检查 NetLogin 认证状态..."
    status_page=$(curl -fsS --connect-timeout 8 --max-time 15 \
        --resolve "${portal_host}:443:${portal_ip}" "https://${portal_host}/") || status_page=""
    if printf '%s' "$status_page" | grep -q 'Dr.COMWebLoginID_1.htm'; then
        network_status="online"
        return 0
    else
        network_status="offline_or_pending_auth"
        return 1
    fi
}

# NetLogin 当前认证接口（2026-09）
portal_host="netlogin.nxu.edu.cn"
portal_ip="${PORTAL_IP:-10.10.129.197}"
portal_port="804"
portal_api="https://${portal_host}:${portal_port}/eportal/portal"
user_agent="Mozilla/5.0 (OpenWrt; Linux) AppleWebKit/537.36 Chrome/122 Safari/537.36"

base64_no_wrap() {
    printf '%s' "$1" | base64 | tr -d '\r\n'
}

# 当前页面开启了 Dr.COM 的参数异或编码。只使用 BusyBox ash 支持的 POSIX 写法。
portal_key_from_ip() {
    value="$1"
    key=0
    index=1
    while [ "$index" -le "${#value}" ]; do
        char=$(printf '%s' "$value" | cut -c "$index")
        code=$(LC_CTYPE=C printf '%d' "'$char")
        key=$((key ^ code))
        index=$((index + 1))
    done
    printf '%d' "$key"
}

portal_encrypt() {
    value="$1"
    output=""
    index=1
    while [ "$index" -le "${#value}" ]; do
        char=$(printf '%s' "$value" | cut -c "$index")
        code=$(LC_CTYPE=C printf '%d' "'$char")
        encoded=$(printf '%02x' "$((code ^ portal_key))")
        output="${output}${encoded}"
        index=$((index + 1))
    done
    printf '%s' "$output"
}

# 从到认证服务器的路由中获取实际出口 IP 与接口，避免误用 LAN 地址。
get_terminal_info() {
    if command -v ip >/dev/null 2>&1; then
        route=$(ip route get "$portal_ip" 2>/dev/null)
        terminal_ip=$(printf '%s\n' "$route" | sed -n 's/.* src \([^ ]*\).*/\1/p' | head -n 1)
        terminal_if=$(printf '%s\n' "$route" | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n 1)
    else
        route=$(route -n get "$portal_ip" 2>/dev/null)
        terminal_if=$(printf '%s\n' "$route" | awk '/interface:/{print $2; exit}')
        terminal_ip=$(ipconfig getifaddr "$terminal_if" 2>/dev/null)
    fi
    terminal_mac=""
    if [ -n "$terminal_if" ] && [ -r "/sys/class/net/${terminal_if}/address" ]; then
        terminal_mac=$(tr -d ':' < "/sys/class/net/${terminal_if}/address")
    elif [ -n "$terminal_if" ]; then
        terminal_mac=$(ifconfig "$terminal_if" 2>/dev/null | awk '/ether/{print $2; exit}' | tr -d ':')
    fi
    if [ -z "$terminal_ip" ]; then
        log_error "校园网出口尚未获得 IPv4 地址；请先检查 WAN DHCP/VLAN 配置。"
        return 1
    fi
    if [ -z "$terminal_mac" ]; then
        log_error "无法读取出口接口 MAC 地址。"
        return 1
    fi
    return 0
}

# 当前认证页每次会下发 program/page 索引；认证请求必须带回这两个值。
load_portal_config() {
    ip64=$(base64_no_wrap "$terminal_ip")
    portal_config=$(curl -fsS --connect-timeout 8 --max-time 15 -A "$user_agent" \
        --resolve "${portal_host}:${portal_port}:${portal_ip}" -G "${portal_api}/page/loadConfig" \
        --data-urlencode "program_index=" \
        --data-urlencode "wlan_vlan_id=1" \
        --data-urlencode "wlan_user_ip=${ip64}" \
        --data-urlencode "wlan_user_ipv6=" \
        --data-urlencode "wlan_user_ssid=" \
        --data-urlencode "wlan_user_areaid=" \
        --data-urlencode "wlan_ac_ip=" \
        --data-urlencode "wlan_ap_mac=" \
        --data-urlencode "gw_id=" \
        --data-urlencode "callback=dr1" \
        --data-urlencode "jsVersion=4.X") || return 1
    portal_program=$(printf '%s' "$portal_config" | sed -n 's/.*"program_index":"\([^"]*\)".*/\1/p' | head -n 1)
    portal_page=$(printf '%s' "$portal_config" | sed -n 's/.*"page_index":"\([^"]*\)".*/\1/p' | head -n 1)
    [ -n "$portal_program" ] && [ -n "$portal_page" ]
}

logout() {
    if ! get_terminal_info || ! load_portal_config; then
        log_error "无法获取新版认证页面配置，注销失败。"
        return 1
    fi
    logoutResult=$(curl -fsS --connect-timeout 8 --max-time 15 -A "$user_agent" \
        --resolve "${portal_host}:${portal_port}:${portal_ip}" -G "${portal_api}/logout" \
        --data-urlencode "program_index=${portal_program}" \
        --data-urlencode "page_index=${portal_page}" \
        --data-urlencode "callback=dr1" \
        --data-urlencode "jsVersion=4.X") || {
        log_error "注销请求未完成。"
        return 1
    }
    if printf '%s' "$logoutResult" | grep -qE '"result"[[:space:]]*:[[:space:]]*(1|"ok")'; then
        log_info "注销成功。"
    else
        log_warn "注销请求已发送，但服务器未确认成功。"
    fi
    exit 0
}

connect() {
    if ! get_terminal_info; then
        log_error "无法获取到认证服务器的出口 IP 或网卡 MAC。"
        return 1
    fi
    if ! load_portal_config; then
        log_error "无法读取 NetLogin 页面配置。"
        return 1
    fi
    [ "$service" != "campus" ] && log_debug "新版认证页不再区分运营商，忽略 service=${service}。"
    user64=$(base64_no_wrap "$username")
    pass64=$(base64_no_wrap "$password")
    portal_key=$(portal_key_from_ip "$terminal_ip")
    # 以下字段与认证页的原生 JavaScript 保持一致；不要删减空字段。
    authResponse=$(curl -sS --connect-timeout 8 --max-time 15 -A "$user_agent" \
        --resolve "${portal_host}:${portal_port}:${portal_ip}" -w '\n%{http_code}' -G "${portal_api}/login" \
        --data-urlencode "login_method=$(portal_encrypt '1')" \
        --data-urlencode "is_base64encode=$(portal_encrypt '1')" \
        --data-urlencode "user_account=$(portal_encrypt "$user64")" \
        --data-urlencode "user_password=$(portal_encrypt "$pass64")" \
        --data-urlencode "wlan_user_ip=$(portal_encrypt "$terminal_ip")" \
        --data-urlencode "wlan_user_ipv6=" \
        --data-urlencode "wlan_user_mac=$(portal_encrypt "$terminal_mac")" \
        --data-urlencode "wlan_vlan_id=$(portal_encrypt '1')" \
        --data-urlencode "wlan_ac_ip=" \
        --data-urlencode "wlan_ac_name=" \
        --data-urlencode "authex_enable=" \
        --data-urlencode "uuid=" \
        --data-urlencode "terminal_type=$(portal_encrypt '1')" \
        --data-urlencode "lang=$(portal_encrypt 'zh')" \
        --data-urlencode "user_agent=$(portal_encrypt "$user_agent")" \
        --data-urlencode "enable_r3=$(portal_encrypt '0')" \
        --data-urlencode "mac_type=$(portal_encrypt '0')" \
        --data-urlencode "rcn=" \
        --data-urlencode "operate=$(portal_encrypt 'portal_login')" \
        --data-urlencode "business_type=$(portal_encrypt '1')" \
        --data-urlencode "program_index=$(portal_encrypt "$portal_program")" \
        --data-urlencode "page_index=$(portal_encrypt "$portal_page")" \
        --data-urlencode "callback=$(portal_encrypt 'dr1')" \
        --data-urlencode "jsVersion=$(portal_encrypt '4.X')" \
        --data-urlencode "encrypt=1" \
        --data-urlencode "v=$(date +%s)" \
        --data-urlencode "lang=zh") || {
        log_error "认证请求传输失败。"
        return 1
    }
    authStatus=$(printf '%s\n' "$authResponse" | tail -n 1)
    authResult=$(printf '%s\n' "$authResponse" | sed '$d')
    log_debug "认证响应：HTTP ${authStatus:-未知}，内容 ${#authResult} 字节。"
    if [ "$authStatus" != "200" ]; then
        log_error "认证服务器返回 HTTP ${authStatus:-未知错误}。"
        return 1
    fi
    if printf '%s' "$authResult" | grep -qE '"result"[[:space:]]*:[[:space:]]*(1|"ok")'; then
        log_info "认证成功。"
        return 0
    fi
    if printf '%s' "$authResult" | grep -qE '"ret_code"[[:space:]]*:[[:space:]]*2'; then
        log_info "终端已在线。"
        return 0
    fi
    log_warn "认证未成功；服务器未返回成功状态。"
    return 1
}


if [ "${action}" = "logout" ]; then
    logout
else
    retry_count=0
    wait_time=60
    log_info "启动校园网认证服务，日志级别: $log_level"
    log_debug "详细日志模式已启用"

    if [ "$persistent_login" != "1" ]; then
        log_info "持久登录已关闭，执行一次认证检查。"
        if check_connection; then
            log_state "connection-online" INFO "网络已认证。"
            exit 0
        fi
        connect
        exit $?
    fi

    # 进入主循环
    while true; do

        if check_connection; then
            case "${network_status}" in
                "online")
                    log_state "connection-online" INFO "网络已认证，等待下一次检测。"
                    # 如果网络恢复，重置重试次数和等待时间
                    retry_count=0
                    wait_time=5
                    log_debug "重置重试计数器和等待时间"
                    sleep "$check_interval"
                    ;;
                "offline_or_pending_auth")
                    log_info "网络离线或未认证，尝试进行认证。"
                    connect  # 调用认证函数进行认证尝试
                    ;;
            esac
        else
            log_state "connection-offline" WARN "网络未认证或不可达，尝试重连。"
            connect
            # 使用更兼容的方式增加retry_count
            retry_count=$(($retry_count + 1))
            wait_time=$((check_interval + retry_count * 10))
            log_debug "当前已尝试重连次数：$retry_count，等待时间：$wait_time 秒"
            sleep $wait_time
        fi

        if [ $retry_count -eq $retry_limit ]; then
            log_error "尝试重连达到最大次数，退出。"
            break
        fi
    done

    # 退出前记录日志
    log_info "认证进程退出"
fi
