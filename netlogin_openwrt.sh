#!/bin/sh

# 宁夏大学校园网 NetLogin 认证脚本（OpenWrt/ash 版本）
# 使用方法：./netlogin_openwrt.sh <服务提供商> <用户名> <密码> [action] [log_level]
if [ "$#" -lt 3 ]; then
    echo "使用方法: $0 <服务提供商> <用户名> <密码> [action] [log_level]"
    echo "action 留空表示正常运行，为 logout 时表示下线操作。"
    echo "log_level 可选值: ERROR, WARN, INFO, DEBUG。默认为 INFO。"
    exit 1
fi

service="$1"
username="$2"
password="$3"
action="${4:-}"
# 设置日志级别，默认为 INFO
log_level="${5:-INFO}"

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

log_file="/var/log/netlogin.log"
# 设置日志文件最大大小（字节），这里设置为1MB
max_log_size=$((1024 * 1024))
# 提前触发清理的阈值（80%），防止过晚触发清理导致超限
log_threshold=$((max_log_size * 8 / 10))
# 设置单条日志的最大大小估计值（字节）
max_log_entry_size=200
network_status=""

# 创建日志文件目录（如果不存在）
log_dir=$(dirname "$log_file")
if [ ! -d "$log_dir" ] && [ "$log_dir" != "." ]; then
    mkdir -p "$log_dir" 2>/dev/null || {
        # 如果无法创建目录，改用/tmp目录
        echo "警告: 无法创建目录 $log_dir, 将使用/tmp目录代替"
        log_file="/tmp/netlogin.log"
    }
fi
if ! touch "$log_file" 2>/dev/null; then
    echo "警告: 无法写入 $log_file, 将使用/tmp目录代替"
    log_file="/tmp/netlogin.log"
    touch "$log_file" 2>/dev/null || echo "警告: 无法创建日志文件，将仅输出到控制台"
fi

# 日志管理函数 - 强制清理确保不超限（兼容无stat命令的系统）
manage_log() {
    # 先进行一次sync确保获取的文件大小是最新的
    sync

    # 检查日志文件是否存在
    if [ -f "$log_file" ]; then
        # 获取当前日志文件大小（使用多种方式，确保兼容性）
        # 方法1: 尝试使用stat命令
        if command -v stat >/dev/null 2>&1; then
            current_size=$(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file" 2>/dev/null || echo "0")
        # 方法2: 使用ls -l和awk（适用于大多数系统，包括BusyBox）
        elif ls -l "$log_file" >/dev/null 2>&1; then
            current_size=$(ls -l "$log_file" 2>/dev/null | awk '{print $5}' 2>/dev/null || echo "0")
        # 方法3: 使用wc -c统计字节数（最基本的方法）
        elif command -v wc >/dev/null 2>&1; then
            current_size=$(wc -c < "$log_file" 2>/dev/null || echo "0")
        else
            # 默认假设文件可能很大，强制清理
            current_size="$max_log_size"
            echo "警告：无法获取文件大小，假定需要清理"
        fi

        # 确保current_size是有效的数字
        case "$current_size" in
            ''|*[!0-9]*) current_size="$max_log_size" ;;
        esac

        # 如果日志文件大小超过阈值（80%），提前进行清理
        if [ "$current_size" -gt "$log_threshold" ]; then
            echo "日志文件大小 ($current_size bytes) 接近或超过限制，正在清理..."

            # 强制刷新文件系统缓存，确保所有写入都已完成
            sync

            # 保留最后600行日志（更激进地清理，确保不会接近上限）
            tail -n 600 "$log_file" > "${log_file}.tmp"

            # 确保临时文件创建成功
            if [ -f "${log_file}.tmp" ]; then
                # 用cat覆盖原文件内容（不改变inode，处理被锁定的文件）
                cat "${log_file}.tmp" > "$log_file"
                rm -f "${log_file}.tmp"

                # 添加清理记录
                truncate_msg="$(date '+%Y-%m-%d %H:%M:%S') - [WARN] 日志文件已清理，保留最后700行"
                echo "$truncate_msg" >> "$log_file"
                echo "$truncate_msg"

                # 再次刷新确保写入完成
                sync
            else
                echo "警告：日志清理失败，无法创建临时文件"
            fi
        fi
    fi
}

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

    # 只有当消息的日志级别小于或等于当前设置的日志级别时才记录
    if [ "$log_level_value" -le "$current_level" ]; then
        # 先检查并管理日志大小
        manage_log

        # 生成带时间戳和日志级别的日志条目
        log_entry="$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message"

        # 再次检查文件大小，使用多种兼容方式
        if [ -f "$log_file" ]; then
            sync
            # 使用与之前相同的多种方法获取文件大小
            if command -v stat >/dev/null 2>&1; then
                current_size=$(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file" 2>/dev/null || echo "0")
            elif ls -l "$log_file" >/dev/null 2>&1; then
                current_size=$(ls -l "$log_file" 2>/dev/null | awk '{print $5}' 2>/dev/null || echo "0")
            elif command -v wc >/dev/null 2>&1; then
                current_size=$(wc -c < "$log_file" 2>/dev/null || echo "0")
            else
                current_size="$max_log_size"
            fi

            case "$current_size" in
                ''|*[!0-9]*) current_size="$max_log_size" ;;
            esac

            # 如果当前大小已经超过或接近限制，或添加此条日志后会超过限制，执行紧急清理
            if [ "$current_size" -gt "$log_threshold" ] || [ "$((current_size + ${#log_entry} + 2))" -gt "$max_log_size" ]; then
                # 更激进的清理 - 只保留400行
                echo "执行紧急日志清理... 当前大小: $current_size bytes"
                sync
                tail -n 400 "$log_file" > "${log_file}.tmp"
                cat "${log_file}.tmp" > "$log_file"
                rm -f "${log_file}.tmp"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARN] 紧急日志清理完成，减少为400行" >> "$log_file"
                sync

                # 清理后再次检查大小
                current_size=$(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file" 2>/dev/null || echo "0")
                echo "清理后日志大小: $current_size bytes（最大限制: $max_log_size bytes）"
            fi
        fi

        # 添加日志 - 使用单独命令确保写入成功
        echo "$log_entry" >> "$log_file"

        # 在控制台显示消息
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

check_connection() {
    # 登录页在已认证状态会返回 Dr.COMWebLoginID_1.htm；不依赖可能受限的校外站点。
    log_debug "检查 NetLogin 认证状态..."
    status_page=$(curl -fsS --connect-timeout 8 --max-time 15 \
        --resolve "${portal_host}:443:${portal_ip}" "https://${portal_host}/") || status_page=""
    if printf '%s' "$status_page" | grep -q 'Dr.COMWebLoginID_1.htm'; then
        log_info "网络已认证。"
        network_status="online"
        return 0
    else
        log_info "网络未认证。"
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
    # 启动前强制检查并清理日志文件大小（兼容多种系统）
    if [ -f "$log_file" ]; then
        # 使用多种方式获取文件大小，确保兼容性
        if command -v stat >/dev/null 2>&1; then
            file_size=$(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file" 2>/dev/null || echo "0")
        elif ls -l "$log_file" >/dev/null 2>&1; then
            file_size=$(ls -l "$log_file" 2>/dev/null | awk '{print $5}' 2>/dev/null || echo "0")
        elif command -v wc >/dev/null 2>&1; then
            file_size=$(wc -c < "$log_file" 2>/dev/null || echo "0")
        else
            file_size="$max_log_size"
            echo "警告：无法获取文件大小，假定需要清理"
        fi

        # 确保获取的大小是有效数字
        case "$file_size" in
            ''|*[!0-9]*) file_size="$max_log_size" ;;
        esac

        echo "启动前检查日志文件：${log_file}，大小：${file_size} bytes"

        if [ -n "$file_size" ] && [ "$file_size" -gt "$((max_log_size / 2))" ]; then
            echo "启动前执行预防性日志清理..."
            sync
            tail -n 400 "$log_file" > "${log_file}.tmp"
            cat "${log_file}.tmp" > "$log_file"
            rm -f "${log_file}.tmp"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] 启动前日志清理完成" >> "$log_file"
            sync

            # 验证清理结果（兼容多种系统）
            if command -v stat >/dev/null 2>&1; then
                new_size=$(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file" 2>/dev/null || echo "0")
            elif ls -l "$log_file" >/dev/null 2>&1; then
                new_size=$(ls -l "$log_file" 2>/dev/null | awk '{print $5}' 2>/dev/null || echo "0")
            elif command -v wc >/dev/null 2>&1; then
                new_size=$(wc -c < "$log_file" 2>/dev/null || echo "0")
            else
                new_size="未知"
            fi
            echo "清理后文件大小：${new_size} bytes"
        fi
    fi

    retry_count=0
    wait_time=60
    log_info "启动校园网认证服务，日志级别: $log_level"
    log_debug "详细日志模式已启用"

    # 进入主循环
    while true; do

        if check_connection; then
            case "${network_status}" in
                "online")
                    log_info "网络状态为在线，等待下一次检测。"
                    # 如果网络恢复，重置重试次数和等待时间
                    retry_count=0
                    wait_time=5
                    log_debug "重置重试计数器和等待时间"
                    sleep 5
                    ;;
                "offline_or_pending_auth")
                    log_info "网络离线或未认证，尝试进行认证。"
                    connect  # 调用认证函数进行认证尝试
                    ;;
            esac
        else
            log_warn "网络状态为离线，尝试重连。"
            connect
            # 使用更兼容的方式增加retry_count
            retry_count=$(($retry_count + 1))
            wait_time=$((5 + retry_count * 10))
            log_info "当前已尝试重连次数：$retry_count"
            log_info "等待时间：$wait_time 秒"
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
