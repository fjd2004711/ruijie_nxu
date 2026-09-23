# 宁夏大学（NXU）校园网认证脚本

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-待实机验证-orange.svg)](netlogin_openwrt.sh)
[![Changelog](https://img.shields.io/badge/Changelog-查看更新日志-orange.svg)](CHANGELOG.md)

一个用于宁夏大学校园网认证的 Linux 通用脚本，支持自动重连。当前认证页使用 NetLogin 协议。

> [!WARNING]
> ### OpenWrt 版本尚未完成实机认证测试
>
> `netlogin_openwrt.sh` 已完成 BusyBox `ash` 兼容性检查，但尚未在真实 OpenWrt 校园网链路上完成“获取 DHCP 地址 → 登录 → 断线重连”的端到端验证。请先在可恢复的测试环境中使用；遇到问题请附上脱敏日志和网络状态。

## 🚀 功能特性

* 🖥️ **通用性** - 适用于各种 Linux 系统，包括 OpenWrt/LEDE 路由器系统
* 🔄 **自动重连** - 智能监测网络状态，断线时自动尝试重新连接
* 🌐 **当前认证页支持** - 适配统一认证账号登录
* 🛑 **下线支持** - 提供便捷的下线操作
* 📊 **日志管理** - 使用 OpenWrt 系统日志，支持不同级别且不会持续写入闪存
* 🔌 **兼容性** - 提供标准 bash 版本和 OpenWrt 兼容版本

## 当前验证状态

| 脚本 | 状态 |
| --- | --- |
| `netlogin.sh` | 已在 macOS 的当前统一认证页面实测登录成功。 |
| `netlogin_openwrt.sh` | 已通过 `sh -n` 语法检查，尚未完成 OpenWrt 实机登录、下线及重连测试。 |

## 📋 使用说明

### 版本选择

本项目提供两套认证协议、共四个脚本。`ruijie_nxu.sh` 与 `ruijie_nxu_openwrt.sh` 是**旧版认证系统的兼容脚本**，仅供仍使用旧认证页的接入口继续使用，不再为当前统一认证页更新。当前 `netlogin.nxu.edu.cn` 认证页请使用 NetLogin 脚本。

| 认证系统 | 标准 Linux（bash） | OpenWrt/LEDE（ash） |
| --- | --- | --- |
| 旧版认证系统（兼容保留） | `ruijie_nxu.sh` | `ruijie_nxu_openwrt.sh` |
| 当前 NetLogin 认证系统 | `netlogin.sh` | `netlogin_openwrt.sh` |

NetLogin 脚本会从 `netlogin.nxu.edu.cn` 读取当前页面配置，并使用 WAN 实际出口 IP 与 MAC 认证；密码只在运行时使用，不写入日志。当前统一认证页不再区分运营商，命令中的第一个 `service` 参数仅为兼容旧用法而保留，建议填写 `campus`。

根据您的系统环境选择合适的版本：
* 如果您在普通 Linux 桌面或服务器上使用，请选择对应的 bash 版本
* 如果您在 OpenWrt 路由器上使用，请选择对应的 OpenWrt 版本
* 看见“统一认证账号/统一认证密码”页面时，请使用 `netlogin.sh` 或 `netlogin_openwrt.sh`

### 配置权限

首先确保脚本具有执行权限：

```bash
# 标准Linux系统
sudo chmod 755 netlogin.sh

# OpenWrt系统
chmod 755 netlogin_openwrt.sh
```

### 基本使用

脚本的基本语法如下：

```bash
# 当前 NetLogin（普通 Linux / OpenWrt）
./netlogin.sh campus <用户名> <密码> [action] [log_level]
./netlogin_openwrt.sh campus <用户名> <密码> [action] [log_level]
```

#### 参数说明

| 参数 | 说明 | 可选值 | 默认值 |
|------|------|--------|--------|
| 服务提供商 | 为保持命令兼容而保留 | `campus` | 无(必填) |
| 用户名 | 您的上网账号 | - | 无(必填) |
| 密码 | 您的账号密码 | - | 无(必填) |
| action | 执行的操作 | 留空(正常连接)、logout(下线) | 留空 |
| log_level | 日志记录级别 | ERROR、WARN、INFO、DEBUG | INFO |

脚本会每隔 5 秒检测一次网络状态，如果检测到断线会自动尝试重连。

### 📝 使用示例

#### Linux系统使用示例

```bash
# 连接校园网
sudo ./netlogin.sh campus username password

# 使用DEBUG级别记录详细日志
sudo ./netlogin.sh campus username password "" DEBUG

# 只记录错误信息
sudo ./netlogin.sh campus username password "" ERROR

# 注销校园网连接
sudo ./netlogin.sh campus username password logout
```

#### OpenWrt系统使用示例

```bash
# 连接校园网
./netlogin_openwrt.sh campus username password

# 当前认证页面（netlogin.nxu.edu.cn）
./netlogin_openwrt.sh campus username password

# 在后台长期运行（推荐）
/usr/bin/netlogin_openwrt.sh campus username password "" INFO &

# 注销校园网连接
./netlogin_openwrt.sh campus username password logout
```

### BleachWrt/精简OpenWrt 系统支持

对于BleachWrt等精简版OpenWrt系统：

1. **特殊适配**：脚本已针对缺少`stat`命令的系统进行了适配，可以使用`ls -l`或`wc -c`替代获取文件大小

2. **后台持续运行**：使用以下方式确保脚本在后台持续运行
   ```bash
   nohup /usr/bin/netlogin_openwrt.sh campus username password "" INFO > /dev/null 2>&1 &
   ```

3. **检查脚本运行状态**：
   ```bash
   ps | grep netlogin_openwrt | grep -v grep
   ```

### 📊 日志级别说明

脚本支持四种日志级别，可以根据需要进行选择：

| 日志级别 | 说明 | 使用场景 |
|---------|------|---------|
| `ERROR` | 只显示致命错误信息 | 只关注可能导致程序崩溃的严重问题 |
| `WARN`  | 显示警告和错误信息 | 关注可能存在的问题和错误 |
| `INFO`  | 显示一般信息、警告和错误 | 日常使用(默认级别) |
| `DEBUG` | 显示所有详细的调试信息 | 故障排查和开发调试 |

### 📁 日志管理

OpenWrt 版本使用系统 `logd` 环形日志，不创建不断增长的 `/var/log` 文件：

```sh
logread -e ruijie-nxu
```

LuCI 中可在“状态 → 系统日志”查看带有 `ruijie-nxu` 标签的记录。日志缓冲区大小由 OpenWrt 系统配置控制，写满后会自动淘汰旧记录，不会持续占用闪存。

## 📝 更新日志

查看完整的[更新日志](CHANGELOG.md)了解项目的详细变更历史。

## 💻 部署建议

### 开机自启

您可以将此脚本设置为开机自启，确保网络连接自动恢复：

#### Linux系统使用systemd (推荐)

1. 创建服务文件:

```bash
sudo nano /etc/systemd/system/netlogin.service
```

2. 添加以下内容:

```
[Unit]
Description=NXU NetLogin Network Authentication
After=network.target

[Service]
ExecStart=/bin/bash /path/to/netlogin.sh <服务提供商> <用户名> <密码> "" INFO
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
```

3. 启用并启动服务:

```bash
sudo systemctl enable netlogin.service
sudo systemctl start netlogin.service
```

#### OpenWrt IPK/LuCI 配置

GitHub Actions 会生成两个包：

```text
netlogin-nxu_*.ipk             # 认证服务
luci-app-netlogin-nxu_*.ipk   # LuCI Web 配置和状态页面
```

安装后推荐在 LuCI 的“服务 → NXU NetLogin”中配置：

- 启用服务
- 账号和密码
- 持久登录（断线自动重连）
- 日志级别
- 网络检测间隔

保存并应用后，服务会由 `procd` 管理并在启动时自动运行。账号和密码只保存在路由器的 `/etc/config/netlogin-nxu`，仓库和 IPK 默认不包含真实凭据。

命令行安装和配置方式：

```sh
opkg install netlogin-nxu_*.ipk
opkg install luci-app-netlogin-nxu_*.ipk

uci set netlogin-nxu.main.enabled='1'
uci set netlogin-nxu.main.persistent_login='1'
uci set netlogin-nxu.main.service='campus'
uci set netlogin-nxu.main.username='你的账号'
uci set netlogin-nxu.main.password='你的密码'
uci set netlogin-nxu.main.log_level='INFO'
uci set netlogin-nxu.main.check_interval='5'
uci commit netlogin-nxu

/etc/init.d/netlogin-nxu enable
/etc/init.d/netlogin-nxu restart
/etc/init.d/netlogin-nxu status
```

如果暂时不使用 IPK，也可以手动运行 `netlogin_openwrt.sh`；不建议再把账号密码直接写入 `/etc/rc.local`。

#### OpenWrt 网络前提

认证脚本不会替路由器建立校园网链路。运行前，请先确认 WAN（有线或无线客户端模式）已经取得校园网 DHCP 地址和默认路由；未认证时也应能访问认证门户。不同校区、AP 与有线端口的 VLAN/DHCP 策略可能不同，本项目目前不提供未经实机验证的 VLAN 配置命令。

## OpenWrt 插件说明

项目已经提供 OpenWrt IPK 和 LuCI 子包。LuCI 页面负责配置账号、密码、持久登录和检测间隔；`procd` 负责开机启动、进程拉起和异常重启；`/etc/init.d/netlogin-nxu status` 显示进程状态及最近日志。

OpenWrt 版本使用 `logger -t ruijie-nxu` 写入 `logd` 环形缓冲区，不创建无限增长的日志文件。查看日志：

```sh
logread -e ruijie-nxu
```

日志缓冲区由 OpenWrt 系统统一限制，写满后自动淘汰旧记录，不会持续占用闪存。

### IPK 构建

仓库内的 `.github/workflows/build-ipk.yml` 使用 OpenWrt SDK 自动构建。推送包含脚本或 `package/netlogin-nxu/` 的提交后，Actions 会上传两个 IPK 制品；也可以在 Actions 页面手动运行。

本地构建需要与目标固件匹配的 OpenWrt SDK：

```sh
make menuconfig
make package/netlogin-nxu/compile V=s
```

核心包和 LuCI 包均为 `PKGARCH:=all`，不包含架构相关二进制；SDK 的目标架构主要用于解析 `curl`、`ca-bundle` 和 LuCI 依赖。

## 🤝 贡献

欢迎提交问题报告和功能建议！如果您想贡献代码，请提交 Pull Request。

## 📜 许可证

本项目采用 MIT 许可证 - 详情请参见 [LICENSE](LICENSE) 文件。

## 📊  常见问题与解决方案


1. **脚本无法执行 (not found)**
   - 确认脚本路径正确 `ls -la /usr/bin/netlogin_openwrt.sh`
   - 确认脚本有执行权限 `chmod 755 /usr/bin/netlogin_openwrt.sh`
   - 检查脚本第一行是否为 `#!/bin/sh`
   - 直接使用绝对路径运行 `/usr/bin/netlogin_openwrt.sh`

2. **查看 OpenWrt 日志**
   - 使用 `logread -e ruijie-nxu` 查看认证脚本日志
   - LuCI 中打开“状态 → 系统日志”查看同一批日志
   - 如需调整缓冲区大小，可检查 `uci get system.@system[0].log_size`

3. **curl 命令失败**
   - 确认已安装 curl: `opkg update && opkg install curl`
   - 检查基本网络连接: `ping 8.8.8.8`

4. **脚本启动后自动退出**
   - 尝试使用DEBUG级别运行，获取更多信息: 
     `./netlogin_openwrt.sh <服务提供商> <用户名> <密码> "" DEBUG`

### 检查日志

查看脚本输出日志，可以帮助排查问题：

```sh
logread -e ruijie-nxu
```

脚本不会修改 `/var` 的全局权限，也不要求用户手动创建日志目录。
