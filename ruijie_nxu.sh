#!/bin/bash

service="campus"  # 可修改为实际的服务提供商，如 chinanet、chinaunicom 或留空表示校园网
username="your_username"  # 修改为实际用户名
password="your_password"  # 修改为实际密码
retry_limit=99  # 重试次数

# 定义日志文件路径
log_file="/var/log/ruijie_nxu.log"

function check_connection() {
    captiveReturnCode=`curl -s -I -m 10 -o /dev/null -s -w %{http_code} http://www.google.cn/generate_204`
    if [ "${captiveReturnCode}" = "204" ]; then
        echo "你已经在线！" | tee -a "$log_file"
        return 0
    else
        echo "当前未在线，准备进行连接尝试。" | tee -a "$log_file"
        return 1
    fi
}

function logout() {
    userIndex=`curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -I http://10.10.10.181/eportal/redirectortosuccess.jsp | grep -o 'userIndex=.*'`
    logoutResult=`curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -d "${userIndex}" http://10.10.10.181/eportal/InterFace.do?method=logout`
    echo "注销结果：$logoutResult" | tee -a "$log_file"
    exit 0
}

function connect() {
    # 获取锐捷登录页面 URL
    loginPageURL=`curl -s "http://www.google.cn/generate_204" | awk -F \' '{print $2}'`

    chinamobile="%E4%B8%AD%E5%9B%BD%E7%A7%BB%E5%8A%A8"
    chinanet="%E4%B8%AD%E5%9B%BD%E7%94%B5%E4%BF%A1"
    chinaunicom="%E4%B8%AD%E5%9B%BD%E8%81%94%E9%80%9A"
    campus="%E6%A0%A1%E5%9B%AD%E7%BD%91"

    encoded_service=""

    if [ "${service}" = "chinamobile" ]; then
        echo "使用中国移动作为互联网服务提供商。" | tee -a "$log_file"
        encoded_service="${chinamobile}"
    fi

    if [ "${service}" = "chinanet" ]; then
        echo "使用中国电信作为互联网服务提供商。" | tee -a "$log_file"
        encoded_service="${chinanet}"
    fi

    if [ "${service}" = "chinaunicom" ]; then
        echo "使用中国联通作为互联网服务提供商。" | tee -a "$log_file"
        encoded_service="${chinaunicom}"
    fi

    if [ -z "${encoded_service}" ]; then
        echo "使用校园网作为互联网服务提供商。" | tee -a "$log_file"
        encoded_service="${campus}"
    fi

    loginURL=`echo ${loginPageURL} | awk -F \? '{print $1}'`
    loginURL="${loginURL/index.jsp/InterFace.do?method=login}"

    queryString=`echo ${loginPageURL} | awk -F \? '{print $2}'`
    queryString="${queryString//&/%2526}"
    queryString="${queryString//=/%253D}"

    if [ -n "${loginURL}" ]; then
        authResult=`curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -e "${loginPageURL}" -b "EPORTAL_COOKIE_USERNAME=; EPORTAL_COOKIE_PASSWORD=; EPORTAL_COOKIE_SERVER=; EPORTAL_COOKIE_SERVER_NAME=; EPORTAL_AUTO_LAND=; EPORTAL_USER_GROUP=; EPORTAL_COOKIE_OPERATORPWD=;" -d "userId=${username}&password=${password}&service=${encoded_service}&queryString=${queryString}&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" "${loginURL}"`
        echo "认证结果：$authResult" | tee -a "$log_file"
    fi

    # 判断网络连接失败的类型
    if! curl -s -I -m 10 -o /dev/null -s -w %{http_code} http://www.baidu.com; then
        if ping -c 1 8.8.8.8 > /dev/null; then
            echo "可能是目标网站问题，网络短暂波动，采用快速重试策略。" | tee -a "$log_file"
            echo "正在快速重试连接，请稍候..."
            return
        else
            echo "网络故障较为严重，切换到保守重试策略。" | tee -a "$log_file"
            echo "网络出现严重问题，正在进行深度检测和延长重试间隔，请耐心等待..."
            # 进行更全面的网络诊断操作，这里仅为示例，可以根据实际情况扩展
            echo "检查网络接口状态..." | tee -a "$log_file"
            # 添加检查网络接口状态的命令及处理逻辑
            echo "检查 DNS 解析..." | tee -a "$log_file"
            # 添加检查 DNS 解析的命令及处理逻辑
            # 延长重试间隔并增加网络检测深度
            wait_time=120 + retry_count * 20
            return
        fi
    fi
}

# 如果接收到的第一个参数是"logout"，执行注销操作
if [ "${1}" = "logout" ]; then
    logout
fi

retry_count=0

while true; do
    if check_connection; then
        echo "等待下一次检测......" | tee -a "$log_file"
    else
        connect
        ((retry_count++))
        echo "当前已尝试重连次数：$retry_count" | tee -a "$log_file"
        # 动态调整重试间隔
        wait_time=60 + retry_count * 10
        if [ $retry_count -eq $retry_limit ]; then
            echo "尝试重连达到最大次数，退出。" | tee -a "$log_file"
            echo "连接失败次数过多，无法自动连接。请检查网络设置或联系网络管理员。"
            break
        fi
    fi
    sleep $wait_time
done#!/bin/bash

service="campus"  # 可修改为实际的服务提供商，如 chinanet、chinaunicom 或留空表示校园网
username="your_username"  # 修改为实际用户名
password="your_password"  # 修改为实际密码
retry_limit=99  # 重试次数

# 定义日志文件路径
log_file="/var/log/ruijie_nxu.log"

function check_connection() {
    captiveReturnCode=`curl -s -I -m 10 -o /dev/null -s -w %{http_code} http://www.google.cn/generate_204`
    if [ "${captiveReturnCode}" = "204" ]; then
        echo "你已经在线！" | tee -a "$log_file"
        return 0
    else
        echo "当前未在线，准备进行连接尝试。" | tee -a "$log_file"
        return 1
    fi
}

function logout() {
    userIndex=`curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -I http://10.10.10.181/eportal/redirectortosuccess.jsp | grep -o 'userIndex=.*'`
    logoutResult=`curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -d "${userIndex}" http://10.10.10.181/eportal/InterFace.do?method=logout`
    echo "注销结果：$logoutResult" | tee -a "$log_file"
    exit 0
}

function connect() {
    # 获取锐捷登录页面 URL
    loginPageURL=`curl -s "http://www.google.cn/generate_204" | awk -F \' '{print $2}'`

    chinamobile="%E4%B8%AD%E5%9B%BD%E7%A7%BB%E5%8A%A8"
    chinanet="%E4%B8%AD%E5%9B%BD%E7%94%B5%E4%BF%A1"
    chinaunicom="%E4%B8%AD%E5%9B%BD%E8%81%94%E9%80%9A"
    campus="%E6%A0%A1%E5%9B%AD%E7%BD%91"

    encoded_service=""

    if [ "${service}" = "chinamobile" ]; then
        echo "使用中国移动作为互联网服务提供商。" | tee -a "$log_file"
        encoded_service="${chinamobile}"
    fi

    if [ "${service}" = "chinanet" ]; then
        echo "使用中国电信作为互联网服务提供商。" | tee -a "$log_file"
        encoded_service="${chinanet}"
    fi

    if [ "${service}" = "chinaunicom" ]; then
        echo "使用中国联通作为互联网服务提供商。" | tee -a "$log_file"
        encoded_service="${chinaunicom}"
    fi

    if [ -z "${encoded_service}" ]; then
        echo "使用校园网作为互联网服务提供商。" | tee -a "$log_file"
        encoded_service="${campus}"
    fi

    loginURL=`echo ${loginPageURL} | awk -F \? '{print $1}'`
    loginURL="${loginURL/index.jsp/InterFace.do?method=login}"

    queryString=`echo ${loginPageURL} | awk -F \? '{print $2}'`
    queryString="${queryString//&/%2526}"
    queryString="${queryString//=/%253D}"

    if [ -n "${loginURL}" ]; then
        authResult=`curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.91 Safari/537.36" -e "${loginPageURL}" -b "EPORTAL_COOKIE_USERNAME=; EPORTAL_COOKIE_PASSWORD=; EPORTAL_COOKIE_SERVER=; EPORTAL_COOKIE_SERVER_NAME=; EPORTAL_AUTO_LAND=; EPORTAL_USER_GROUP=; EPORTAL_COOKIE_OPERATORPWD=;" -d "userId=${username}&password=${password}&service=${encoded_service}&queryString=${queryString}&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false" -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8" -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" "${loginURL}"`
        echo "认证结果：$authResult" | tee -a "$log_file"
    fi

    # 判断网络连接失败的类型
    if! curl -s -I -m 10 -o /dev/null -s -w %{http_code} http://www.baidu.com; then
        if ping -c 1 8.8.8.8 > /dev/null; then
            echo "可能是目标网站问题，网络短暂波动，采用快速重试策略。" | tee -a "$log_file"
            echo "正在快速重试连接，请稍候..."
            return
        else
            echo "网络故障较为严重，切换到保守重试策略。" | tee -a "$log_file"
            echo "网络出现严重问题，正在进行深度检测和延长重试间隔，请耐心等待..."
            # 进行更全面的网络诊断操作，这里仅为示例，可以根据实际情况扩展
            echo "检查网络接口状态..." | tee -a "$log_file"
            # 添加检查网络接口状态的命令及处理逻辑
            echo "检查 DNS 解析..." | tee -a "$log_file"
            # 添加检查 DNS 解析的命令及处理逻辑
            # 延长重试间隔并增加网络检测深度
            wait_time=120 + retry_count * 20
            return
        fi
    fi
}

# 如果接收到的第一个参数是"logout"，执行注销操作
if [ "${1}" = "logout" ]; then
    logout
fi

retry_count=0

while true; do
    if check_connection; then
        echo "等待下一次检测......" | tee -a "$log_file"
    else
        connect
        ((retry_count++))
        echo "当前已尝试重连次数：$retry_count" | tee -a "$log_file"
        # 动态调整重试间隔
        wait_time=60 + retry_count * 10
        if [ $retry_count -eq $retry_limit ]; then
            echo "尝试重连达到最大次数，退出。" | tee -a "$log_file"
            echo "连接失败次数过多，无法自动连接。请检查网络设置或联系网络管理员。"
            break
        fi
    fi
    sleep $wait_time
done