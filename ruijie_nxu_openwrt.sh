#!/bin/sh

# 使用方法：./script.sh <服务提供商> <用户名> <密码> [action] [log_level]
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

log_file="/var/log/ruijie_nxu.log"
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
        log_file="/tmp/ruijie_nxu.log"
    }
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
    # 尝试访问宁夏大学图书馆
    captiveReturnCode=$(curl -s -I -m 10 -o /dev/null -s -w %{http_code} https://metalib.nxu.edu.cn/space/index)
    if [ "${captiveReturnCode}" = "200" ]; then
        log_info "网络在线且已认证，校内资源访问正常。"
        network_status="online"
        return 0
    else
        log_info "网络离线或未认证。"
        network_status="offline_or_pending_auth"
        return 1
    fi
}

logout() {
    userIndex=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -I http://10.10.10.181/eportal/redirectortosuccess.jsp | grep -o 'userIndex=.*')
    if [ -z "$userIndex" ]; then
        log_error "无法获取 userIndex，注销失败。"
        return 1
    fi
    logoutResult=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -d "${userIndex}" http://10.10.10.181/eportal/InterFace.do?method=logout)
    log_info "注销结果：$logoutResult"
    exit 0
}

connect() {
    loginPageURL=$(curl -s "http://4399.com/")
    if [ $? -ne 0 ]; then
        log_error "无法获取登录页面 URL。"
        return 1
    fi
    loginPageURL=$(echo "$loginPageURL" | awk -F \' '{print $2}')

    chinamobile="%E4%B8%AD%E5%9B%BD%E7%A7%BB%E5%8A%A8"
    chinanet="%E4%B8%AD%E5%9B%BD%E7%94%B5%E4%BF%A1"
    chinaunicom="%E4%B8%AD%E5%9B%BD%E8%81%94%E9%80%9A"
    campus="%E6%A0%A1%E5%9B%AD%E7%BD%91"

    encoded_service=""

    if [ "${service}" = "chinamobile" ]; then
        encoded_service="${chinamobile}"
    fi

    if [ "${service}" = "chinanet" ]; then
        encoded_service="${chinanet}"
    fi

    if [ "${service}" = "chinaunicom" ]; then
        encoded_service="${chinaunicom}"
    fi

    if [ -z "${encoded_service}" ]; then
        encoded_service="${campus}"
    fi

    loginURL=$(echo "${loginPageURL}" | awk -F \? '{print $1}')
    loginURL="${loginURL/index.jsp/InterFace.do?method=login}"

    queryString=$(echo "${loginPageURL}" | awk -F \? '{print $2}')
    queryString="${queryString//&/%2526}"
    queryString="${queryString//=/%253D}"
    
    if [ -n "${loginURL}" ]; then
        log_debug "尝试连接: ${loginURL}"
        authResult=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -e "${loginPageURL}" -b "EPORTAL_COOKIE_USERNAME=; EPORTAL_COOKIE_PASSWORD=; EPORTAL_COOKIE_SERVER=; EPORTAL_COOKIE_SERVER_NAME=; EPORTAL_AUTO_LAND=; EPORTAL_USER_GROUP=; EPORTAL_COOKIE_OPERATORPWD=;" -d "userId=${username}&password=${password}&service=${encoded_service}&queryString=${queryString}&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" "${loginURL}")
        log_info "认证结果：$authResult"
    fi
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
