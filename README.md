# 宁夏大学（NXU）校园网锐捷认证脚本

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenWrt Compatible](https://img.shields.io/badge/OpenWrt-Compatible-brightgreen.svg)](ruijie_nxu_openwrt.sh)
[![Changelog](https://img.shields.io/badge/Changelog-查看更新日志-orange.svg)](CHANGELOG.md)

一个用于宁夏大学校园网锐捷认证的 Linux 通用脚本，支持自动重连和多运营商，现已支持OpenWrt。

> [!IMPORTANT]
> ### 中卫校区 OpenWrt 用户必读
>
> 部分接入口需要先完成下文的 **中卫校区 WAN 混合 VLAN 1 配置**，WAN 才能获取 DHCP 地址。出现 WAN 长期 `pending`、能看到网关 VLAN 1 邻居却无法获取地址时，请先配置 VLAN，再运行认证脚本。

## 🚀 功能特性

* 🖥️ **通用性** - 适用于各种 Linux 系统，包括 OpenWrt/LEDE 路由器系统
* 🔄 **自动重连** - 智能监测网络状态，断线时自动尝试重新连接
* 🌐 **多运营商** - 支持校园网、中国电信、中国联通、中国移动
* 🛑 **下线支持** - 提供便捷的下线操作
* 📊 **日志管理** - 智能控制日志大小，支持不同级别的日志记录
* 🔌 **兼容性** - 提供标准 bash 版本和 OpenWrt 兼容版本

## 📋 使用说明

### 版本选择

本项目提供两个版本的脚本：

1. **标准版本** - `ruijie_nxu.sh`：适用于大多数 Linux 系统，基于 bash shell
2. **OpenWrt版本** - `ruijie_nxu_openwrt.sh`：专为 OpenWrt/LEDE 系统优化，使用 ash shell（BusyBox）

根据您的系统环境选择合适的版本：
* 如果您在普通 Linux 桌面或服务器上使用，请选择标准版本
* 如果您在 OpenWrt 路由器上使用，请选择 OpenWrt 版本

### 配置权限

首先确保脚本具有执行权限：

```bash
# 标准Linux系统
sudo chmod 755 ruijie_nxu.sh

# OpenWrt系统
chmod 755 ruijie_nxu_openwrt.sh
```

### 基本使用

脚本的基本语法如下：

```bash
# 标准Linux系统
sudo ./ruijie_nxu.sh <服务提供商> <用户名> <密码> [action] [log_level]

# OpenWrt系统
./ruijie_nxu_openwrt.sh <服务提供商> <用户名> <密码> [action] [log_level]
```

#### 参数说明

| 参数 | 说明 | 可选值 | 默认值 |
|------|------|--------|--------|
| 服务提供商 | 网络服务提供商 | campus(校园网)、chinanet(电信)、chinaunicom(联通)、chinamobile(移动) | 无(必填) |
| 用户名 | 您的上网账号 | - | 无(必填) |
| 密码 | 您的账号密码 | - | 无(必填) |
| action | 执行的操作 | 留空(正常连接)、logout(下线) | 留空 |
| log_level | 日志记录级别 | ERROR、WARN、INFO、DEBUG | INFO |

脚本会每隔 5 秒检测一次网络状态，如果检测到断线会自动尝试重连。

### 📝 使用示例

#### Linux系统使用示例

```bash
# 连接校园网
sudo ./ruijie_nxu.sh campus username password

# 连接中国电信
sudo ./ruijie_nxu.sh chinanet username password

# 使用DEBUG级别记录详细日志
sudo ./ruijie_nxu.sh campus username password "" DEBUG

# 只记录错误信息
sudo ./ruijie_nxu.sh campus username password "" ERROR

# 注销校园网连接
sudo ./ruijie_nxu.sh campus username password logout
```

#### OpenWrt系统使用示例

```bash
# 连接校园网
./ruijie_nxu_openwrt.sh campus username password

# 连接中国电信并使用INFO级别日志
./ruijie_nxu_openwrt.sh chinanet username password "" INFO

# 在后台长期运行（推荐）
/usr/bin/ruijie_nxu_openwrt.sh campus username password "" INFO &

# 注销校园网连接
./ruijie_nxu_openwrt.sh campus username password logout
```

### BleachWrt/精简OpenWrt 系统支持

对于BleachWrt等精简版OpenWrt系统：

1. **特殊适配**：脚本已针对缺少`stat`命令的系统进行了适配，可以使用`ls -l`或`wc -c`替代获取文件大小

2. **后台持续运行**：使用以下方式确保脚本在后台持续运行
   ```bash
   nohup /usr/bin/ruijie_nxu_openwrt.sh campus username password "" INFO > /dev/null 2>&1 &
   ```

3. **检查脚本运行状态**：
   ```bash
   ps | grep ruijie_nxu_openwrt | grep -v grep
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

脚本使用**强制清理**机制确保日志文件严格控制在限制范围内：
- 日志默认保存在 `/var/log/ruijie_nxu.log`（如无法访问，自动切换到 `/tmp/ruijie_nxu.log`）
- 日志文件大小严格限制在 1MB 以内，提前在达到80%时触发清理

## 📝 更新日志

查看完整的[更新日志](CHANGELOG.md)了解项目的详细变更历史。

## 💻 部署建议

### 开机自启

您可以将此脚本设置为开机自启，确保网络连接自动恢复：

#### Linux系统使用systemd (推荐)

1. 创建服务文件:

```bash
sudo nano /etc/systemd/system/ruijie-nxu.service
```

2. 添加以下内容:

```
[Unit]
Description=NXU Ruijie Network Authentication
After=network.target

[Service]
ExecStart=/bin/bash /path/to/ruijie_nxu.sh <服务提供商> <用户名> <密码> "" INFO
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
```

3. 启用并启动服务:

```bash
sudo systemctl enable ruijie-nxu.service
sudo systemctl start ruijie-nxu.service
```

#### OpenWrt系统配置

1. 将脚本上传到路由器，一般放置在 `/usr/bin/` 目录下:

```bash
scp ruijie_nxu_openwrt.sh root@192.168.1.1:/usr/bin/
```

2. 确保脚本有执行权限:

```bash
chmod 755 /usr/bin/ruijie_nxu_openwrt.sh
```

3. 编辑 `/etc/rc.local` 文件（在系统启动时运行）:

```bash
vi /etc/rc.local
```

4. 在 `exit 0` 行之前添加:

```bash
/usr/bin/ruijie_nxu_openwrt.sh <服务提供商> <用户名> <密码> "" INFO &
```

5. 保存文件并退出。这样路由器启动后就会自动运行认证脚本。

#### 中卫校区 WAN 混合 VLAN 1 配置

> [!WARNING]
> ### 先完成 WAN 配置，再运行认证脚本
>
> 本节用于中卫校区存在“DHCP 未打标签、网关回复带 VLAN 1 标签”的接入口。未完成本节配置时，认证脚本无法取得登录页，也无法完成认证。

中卫校区部分接入口的 DHCP 请求使用未标记报文，而网关的 ARP/邻居回复携带 `802.1Q VLAN 1` 标签。将 WAN 直接配置为 `eth0.1` 会使 DHCP 请求带上 VLAN 标签，无法取得租约；直接使用 `eth0` 则无法正确处理带 VLAN 1 标签的网关回复。

此场景应在上游物理口上建立启用 VLAN filtering 的桥，将未标记流量和 VLAN 1 归入同一个逻辑网络。以下示例假设逻辑接口为 `wan`、上游物理口为 `eth0`；请先确认实际名称：

```sh
uci show network | grep '=interface'
ip route show default
ip -br link
```

先备份网络配置：

```sh
cp /etc/config/network /etc/config/network.before-zhongwei-vlan
```

创建混合 VLAN WAN：

```sh
uci -q delete network.wan_vlan1
uci -q delete network.wan_bridge
uci -q delete network.wan_bridge_vlan1

uci set network.wan_bridge='device'
uci set network.wan_bridge.name='br-wan'
uci set network.wan_bridge.type='bridge'
uci set network.wan_bridge.vlan_filtering='1'
uci set network.wan_bridge.bridge_empty='1'
uci add_list network.wan_bridge.ports='eth0'

uci set network.wan_bridge_vlan1='bridge-vlan'
uci set network.wan_bridge_vlan1.device='br-wan'
uci set network.wan_bridge_vlan1.vlan='1'
uci add_list network.wan_bridge_vlan1.ports='eth0:u*'

uci set network.wan.device='br-wan.1'
uci set network.wan.proto='dhcp'
uci set network.wan.auto='1'
uci commit network
/etc/init.d/network restart
```

`eth0:u*` 将未标记 DHCP 流量归入 VLAN 1，并接收 VLAN 1 的带标签回复；从 WAN 发往上游的流量保持未标记。

验证网络状态：

```sh
ifstatus wan
ip route show default
ip neigh show dev br-wan.1
curl -sS -i --max-time 10 http://4399.com/ | sed -n '1,10p'
```

成功后，`wan` 会获得校园网 DHCP 地址和默认路由。未认证时，`4399.com` 应跳转至 `eportal/index.jsp`；认证完成后则访问真实网站。认证门户通常不响应 ICMP，因此应以 DHCP、路由、邻居表和 HTTP 请求判断状态。

如未取得 WAN 地址，恢复备份：

```sh
cp /etc/config/network.before-zhongwei-vlan /etc/config/network
/etc/init.d/network restart
```

这套桥和 VLAN 配置仅用于中卫校区。家庭 PPPoE 或普通 DHCP 应使用直接绑定物理 WAN 口的独立网络配置，不应与 `br-wan.1` 同时启用。

## 🤝 贡献

欢迎提交问题报告和功能建议！如果您想贡献代码，请提交 Pull Request。

## 📜 许可证

本项目采用 MIT 许可证 - 详情请参见 [LICENSE](LICENSE) 文件。

## 📊  常见问题与解决方案


1. **脚本无法执行 (not found)**
   - 确认脚本路径正确 `ls -la /usr/bin/ruijie_nxu_openwrt.sh`
   - 确认脚本有执行权限 `chmod 755 /usr/bin/ruijie_nxu_openwrt.sh`
   - 检查脚本第一行是否为 `#!/bin/sh`
   - 直接使用绝对路径运行 `/usr/bin/ruijie_nxu_openwrt.sh`

2. **日志文件权限问题**
   - 默认日志保存在 `/var/log/ruijie_nxu.log`，请确保此路径存在且可写
   - 如果无法创建目录，脚本会自动切换到 `/tmp/ruijie_nxu.log`
   - 如果仍有问题，可手动修改脚本中的 `log_file` 变量到其他可写位置

3. **日志管理问题**
   - 如果日志文件不断增长没有被清理，检查是否有权限执行 `tail` 和 `cat` 命令
   - 对于BleachWrt等精简系统：脚本已适配使用`ls -l`或`wc -c`替代`stat`命令
   - 确认 `/tmp` 目录有足够空间创建临时文件
   - 手动触发日志清理：`tail -n 400 /var/log/ruijie_nxu.log > /tmp/ruijie.tmp && cat /tmp/ruijie.tmp > /var/log/ruijie_nxu.log`
   - 执行 `sync` 命令确保文件系统缓存被刷新
   - 如遇顽固问题，可尝试重命名或删除日志文件：`rm /var/log/ruijie_nxu.log`，脚本会自动创建新文件

3. **curl 命令失败**
   - 确认已安装 curl: `opkg update && opkg install curl`
   - 检查基本网络连接: `ping 8.8.8.8`

4. **脚本启动后自动退出**
   - 尝试使用DEBUG级别运行，获取更多信息: 
     `./ruijie_nxu_openwrt.sh <服务提供商> <用户名> <密码> "" DEBUG`

### 检查日志

查看脚本输出日志，可以帮助排查问题：

```bash
cat /var/log/ruijie_nxu.log
```

或根据您修改后的日志路径查看对应文件。
