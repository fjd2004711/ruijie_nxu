#!/bin/bash

# 使用方法：./script.sh <服务提供商> <用户名> <密码> [action]
if [ "$#" -lt 3 ]; then
    echo "使用方法: $0 <服务提供商> <用户名> <密码> [action]"
    echo "action 留空表示正常运行，为 logout 时表示下线操作。"
    exit 1
fi

service="$1"
username="$2"
password="$3"
action="${4:-}"

retry_limit=99

log_file="/var/log/ruijie_nxu.log"
network_status=""

function check_connection() {
    # 尝试访问宁夏大学图书馆
    captiveReturnCode=$(curl -s -I -m 10 -o /dev/null -s -w %{http_code} https://metalib.nxu.edu.cn/space/index)
    if [ "${captiveReturnCode}" = "200" ]; then
        echo "网络在线且已认证，校内资源访问正常。"
        network_status="online"
        return 0
    else
        echo "网络离线或未认证。"
        network_status="offline_or_pending_auth"
        return 1
    fi
}

function logout() {
    userIndex=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -I http://10.10.10.181/eportal/redirectortosuccess.jsp | grep -o 'userIndex=.*')
    if [ -z "$userIndex" ]; then
        echo "无法获取 userIndex，注销失败。" | tee -a "$log_file"
        return 1
    fi
    logoutResult=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -d "${userIndex}" http://10.10.10.181/eportal/InterFace.do?method=logout)
    echo "注销结果：$logoutResult" | tee -a "$log_file"
    exit 0
}

function connect() {
    loginPageURL=$(curl -s "http://www.google.cn/generate_204")
    if [ $? -ne 0 ]; then
        echo "无法获取登录页面 URL。" | tee -a "$log_file"
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

    if [ -n "${loginURL}" ];
    then
        authResult=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -e "${loginPageURL}" -b "EPORTAL_COOKIE_USERNAME=; EPORTAL_COOKIE_PASSWORD=; EPORTAL_COOKIE_SERVER=; EPORTAL_COOKIE_SERVER_NAME=; EPORTAL_AUTO_LAND=; EPORTAL_USER_GROUP=; EPORTAL_COOKIE_OPERATORPWD=;" -d "userId=${username}&password=${password}&service=${encoded_service}&queryString=${queryString}&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" "${loginURL}")
        echo "认证结果：$authResult" | tee -a "$log_file"
    fi
}

if [ "${action}" = "logout" ]; then
    logout
else
    retry_count=0
    wait_time=60
    while true; do
        if check_connection; then
            case "${network_status}" in
                "online")
                    echo "网络状态为在线，等待下一次检测。"
                    # 如果网络恢复，重置重试次数和等待时间
                    retry_count=0
                    wait_time=5
                    sleep 5
                    ;;
                "offline_or_pending_auth")
                    echo "网络离线或未认证，尝试进行认证。"
                    connect  # 调用认证函数进行认证尝试
                    ;;
            esac
        else
            echo "网络状态为离线，尝试重连。"
            connect
            ((retry_count++))
            wait_time=$((5 + retry_count * 10))
            echo "当前已尝试重连次数：$retry_count" | tee -a "$log_file"
            echo "等待时间：$wait_time 秒" | tee -a "$log_file"
            sleep $wait_time
        fi
        if [ $retry_count -eq $retry_limit ]; then
            echo "尝试重连达到最大次数，退出。"
            echo "尝试重连达到最大次数，退出。" | tee -a "$log_file"
            break
        fi
    done
fi