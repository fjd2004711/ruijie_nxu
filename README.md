<div align="center">

# NXU NetLogin

**宁夏大学校园网认证 · 自动重连 · OpenWrt / iStoreOS**

支持当前 `netlogin.nxu.edu.cn` 统一认证门户，为 macOS、Linux 和路由器提供自动认证与连接监测。

[![Release](https://img.shields.io/github/v/release/fjd2004711/ruijie_nxu?color=6366f1&cacheSeconds=300&v=1.2.0)](https://github.com/fjd2004711/ruijie_nxu/releases/latest)
[![Build IPK](https://github.com/fjd2004711/ruijie_nxu/actions/workflows/build-ipk.yml/badge.svg?branch=main&event=push&v=1.2.0)](https://github.com/fjd2004711/ruijie_nxu/actions/workflows/build-ipk.yml)
[![OpenWrt](https://img.shields.io/badge/OpenWrt%20%2F%20iStoreOS-24.10-2563eb)](#实测状态)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

[下载 IPK](https://github.com/fjd2004711/ruijie_nxu/releases/latest) · [快速安装](#快速安装) · [界面预览](#界面预览) · [更新日志](CHANGELOG.md)

</div>

## 功能亮点

| 功能 | 说明 |
| --- | --- |
| 自动认证与重连 | 默认每 5 秒检查门户在线状态；失败时逐步退避，最长等待 120 秒。 |
| 账号切换 | 门户在线账号与配置不一致时，先注销（解绑）再用配置账号登录；需先关闭无感知认证。 |
| 失败保护 | 连续被服务器拒绝登录达到上限（默认 5 次）后暂停重试，避免密码错误导致账号被锁定。 |
| 状态与操作 | LuCI 状态页显示在线时长、已用流量（单位可选），并提供「立即认证」和「注销」按钮。 |
| 出口识别 | 优先使用门户看到的 IP / MAC，兼容 NAT 后的电脑与路由器 WAN。 |
| 精简固件适配 | 缺少 `base64` 时使用纯 `awk` 编码，保留 BusyBox ash 兼容性。 |
| LuCI 状态页 | 认证进程、校园网连接和持久登录分别展示，支持彩色日志与实时刷新。 |
| 有界日志 | 同时写入系统日志和 `/tmp` 下的有界日志文件（约 300 行，不占闪存），连续重复的告警只记一次。 |
| HTTPS 认证 | 认证请求直接连接校园网门户，绕过环境代理并保留证书校验。 |

## 界面预览

### 运行状态

连接状态一目了然。认证日志突出成功与告警信息，切换“全部日志”可查看调试记录。

<p align="center">
  <img src="docs/images/status.png" alt="NXU NetLogin 运行状态与彩色认证日志" width="100%" />
</p>

### 插件配置

在 LuCI 中设置服务开关、持久登录、账号密码、日志级别和检测间隔。

<p align="center">
  <img src="docs/images/configuration.png" alt="NXU NetLogin 插件配置页面，账号已遮盖" width="760" />
</p>

## 使用前必读：关闭无感知认证

校园网的「无感知认证」（MAC 绑定）会让门户按终端 MAC 自动放行已绑定的账号。开启后，路由器注销或更换账号时，门户会立刻用**旧账号**重新放行，表现为：

- 在插件里改了账号，认证后在线的仍然是原来的账号；
- 点「注销」后很快又自动在线，或者注销并解绑返回成功但会话没有下线；
- 日志出现「门户当前在线账号与配置的账号不一致」「注销后门户仍显示在线，疑似被无感知认证/MAC 绑定自动重新登录」。

**使用本插件前，请先关闭无感知认证并解除路由器 MAC 的绑定：**

1. 打开校园网自助服务系统 <https://netself.nxu.edu.cn/Self/dashboard>，用账号登录。
2. 在终端 / MAC 管理相关菜单中关闭「无感知认证」，并解除路由器 WAN 口 MAC 的绑定（菜单名称可能随学校系统版本略有不同）。
3. 也可以在 <https://netlogin.nxu.edu.cn/> 登录成功页面的「终端在线表」里，点击对应终端的「解除绑定」。
4. 想换账号时，请对**原账号**执行上述操作，再在插件里改成新账号。

关闭后无需其他设置：插件检测到在线账号与配置不一致时，会先注销再用配置的账号登录。

## 快速安装

### OpenWrt / iStoreOS：推荐 IPK

1. **先按上文关闭无感知认证。** 然后从 [最新 Release](https://github.com/fjd2004711/ruijie_nxu/releases/latest) 的附件中直接下载 `netlogin-nxu_*.ipk`（附件是原始 IPK，不是压缩包；请不要从 Actions 页面下载制品 zip）。
2. 在 LuCI 软件包页面上传并安装，或通过 SSH 执行：

   ```sh
   opkg install /tmp/netlogin-nxu_*.ipk
   ```

3. 打开 **服务 → NXU NetLogin → 插件设置**（部分已缓存的菜单显示为“配置”）。
4. 填写校园网账号和密码，开启“启用服务”和“持久登录”，保存并应用。
5. 在 **运行状态** 页面确认认证进程“运行中”、校园网连接“已认证”。

安装包包含认证脚本、`procd` 服务和 LuCI 页面，架构标记为 `all`。依赖由 `opkg` 安装，包括 `curl`、`ca-bundle`、`uci`、`luci-base` 和 `luci-compat`。

账号密码保存在路由器的 `/etc/config/netlogin-nxu`，该文件权限为 `600`。升级保留已有配置；仓库及发布包使用空账号配置。

### macOS / Linux：直接运行脚本

下载 [netlogin.sh](netlogin.sh)，使用系统 Bash 运行：

```sh
chmod +x netlogin.sh

# 持续运行，断线后自动重连
./netlogin.sh campus '你的账号' '你的密码'

# 单次检查或认证，完成后退出
./netlogin.sh campus '你的账号' '你的密码' once

# 注销校园网连接
./netlogin.sh campus '你的账号' '你的密码' logout
```

需要详细日志时，在操作参数后指定 `DEBUG`：

```sh
./netlogin.sh campus '你的账号' '你的密码' '' DEBUG
```

> 运行前，电脑或路由器的校园网出口应已取得 DHCP 地址和默认路由，并能访问认证门户。

## 命令行与服务管理

### 参数说明

```text
./netlogin.sh         campus <账号> <密码> [操作] [日志级别]
./netlogin_openwrt.sh campus <账号> <密码> [操作] [日志级别]
```

| 参数 | 可选值 | 默认行为 |
| --- | --- | --- |
| 服务类型 | `campus` | 为兼容旧命令保留，当前统一认证页使用校园网账号。 |
| 操作 | 留空、`once`、`logout` | 留空时持续监测并自动重连。 |
| 日志级别 | `ERROR`、`WARN`、`INFO`、`DEBUG` | `INFO`。 |
| 连续失败上限 | 数字，`0` 为不限制 | `5`。连续被服务器拒绝登录达到次数后暂停自动重试，防止密码错误导致账号被锁定；在 LuCI 点击「立即认证」或重启服务后恢复。 |

### OpenWrt 服务

```sh
# 从 UCI 配置启动认证服务
/etc/init.d/netlogin-nxu restart

# 查看进程状态及最近日志
/etc/init.d/netlogin-nxu status

# 启用开机启动
/etc/init.d/netlogin-nxu enable

# 查看校园网认证日志
logread -e ruijie-nxu
```

命令行配置：

```sh
uci set netlogin-nxu.main.enabled='1'
uci set netlogin-nxu.main.persistent_login='1'
uci set netlogin-nxu.main.service='campus'
uci set netlogin-nxu.main.username='你的账号'
uci set netlogin-nxu.main.password='你的密码'
uci set netlogin-nxu.main.log_level='INFO'
uci set netlogin-nxu.main.check_interval='5'
uci set netlogin-nxu.main.max_failures='5'
uci commit netlogin-nxu
/etc/init.d/netlogin-nxu restart
```

“持久登录”关闭时，脚本只执行一次检查或认证。LuCI 的“清空显示”只清除当前页面已显示的记录，系统日志仍可用于排查。

## 实测状态

2026-10-07 的验证环境与结果：

| 项目 | 环境 | 结果 |
| --- | --- | --- |
| `netlogin.sh` | macOS / 系统 Bash | 实际发送认证请求，服务器确认在线；NAT 出口识别和状态检测通过。 |
| `netlogin_openwrt.sh` | iStoreOS 24.10.6 / BusyBox ash | 登录成功，日志确认断线后自动认证恢复。 |
| LuCI | iStoreOS 24.10.6 / Argon | 状态读取、日志切换、自动刷新、暂停、清空显示和复制通过。 |
| IPK 升级 | `1.1.3-r2`，同一路由器 | 本地包实机安装成功，账号配置保留，安装文件与仓库一致。 |
| 回归检查 | Bash / POSIX sh | 7 项检查通过，覆盖编码回退、终端信息、状态判断与错误处理。 |

本次未进行路由器重启测试；其他固件的端到端验证待补充。

## 常见问题

**服务器提示“校验密码长度失败”**

先升级最新版本。旧版在精简固件缺少 `base64` 时可能发送空编码；新版自动回退到 `awk`，并在缺少必要命令时明确报错。

**换了账号，认证后在线的还是旧账号 / 注销后马上又自动在线**

这是校园网「无感知认证」（MAC 绑定）造成的，见上文「使用前必读」。先在自助服务中关闭无感知认证并解除路由器 MAC 的绑定，再换账号。

**注销后访问不了认证门户**

注销后，旧的 WAN 地址有时无法再访问门户。点「立即认证」时脚本发现门户不可达，会自动释放并重新获取 WAN 地址（`ifdown/ifup`），门户一可达就立即登录；守护进程也会这样处理（手动注销后保持离线，不重拉）。仍无法恢复时，请不要重启，先在路由器上执行：

```sh
ip -4 addr show br-wan.1; ip -4 route get 10.10.129.197
logread -e ruijie-nxu | tail -30
```

**状态页显示的已用流量单位不对**

门户没有标明流量单位。在「插件设置 → 流量单位」中切换（KB / 4 字节 / 字节 / MB），对照校园网自助服务里的数值选择；状态页流量处悬停可看到门户原始值。

**macOS 下载后解压出来的不是 IPK**

IPK 本身是 gzip 压缩的归档，macOS 的归档实用工具会把从 Actions 下载的制品 zip 里的 `.ipk` 再解压一层。请从 [Release](https://github.com/fjd2004711/ruijie_nxu/releases/latest) 的附件直接下载 `.ipk`；如果仍被自动解压，可在终端用 `curl -LO <附件链接>` 下载，或在 Safari 设置中关闭「下载后打开“安全”文件」。需要从制品 zip 取文件时，用 `unzip netlogin-nxu-ipk.zip` 或 `gh run download <运行编号> -n netlogin-nxu-ipk`，不要双击。

**进程运行，但校园网未认证**

查看认证日志。进程状态与门户在线状态分别检测；DHCP、路由、账号状态和门户响应都可能影响认证。

**能打开状态页，配置页无法加载**

确认已安装 `luci-compat`，它提供 Lua 页面需要的兼容组件。最新 IPK 已声明该依赖。

**macOS 日志写在哪里？**

默认使用 `/var/log/netlogin.log`，当前用户无写入权限时回退到 `/tmp/netlogin.log`。

## 开发与构建

凭据无关的本地检查：

```sh
python3 -m unittest discover -s tests
bash -n netlogin.sh
sh -n netlogin_openwrt.sh
```

[GitHub Actions](https://github.com/fjd2004711/ruijie_nxu/actions/workflows/build-ipk.yml) 使用 OpenWrt 24.10.2 x86/64 SDK 构建一个包含 LuCI 的 IPK；SDK 目标用于解析依赖，包本身不含架构相关二进制。工作流先执行语法和回归检查，再上传 `netlogin-nxu-ipk` 制品；推送 `v*` 标签时还会自动创建 Release，附件包含 IPK、两个脚本和 `SHA256SUMS`，发布说明取自 `CHANGELOG.md` 中对应版本的条目。

在匹配的 OpenWrt SDK 中手动构建：

```sh
make package/netlogin-nxu/compile V=s
```

## 旧认证系统

仍使用旧锐捷认证页的接入口，可使用兼容保留的脚本：

| 协议 | Bash | OpenWrt / ash |
| --- | --- | --- |
| 当前 NetLogin | [netlogin.sh](netlogin.sh) | [netlogin_openwrt.sh](netlogin_openwrt.sh) |
| 旧版锐捷 | [ruijie_nxu.sh](ruijie_nxu.sh) | [ruijie_nxu_openwrt.sh](ruijie_nxu_openwrt.sh) |

当前统一认证门户请使用 NetLogin 版本。

## 许可证

[Apache License 2.0](LICENSE)
