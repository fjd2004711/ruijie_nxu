# 📝 宁夏大学校园网锐捷认证脚本更新日志

本文档记录了宁夏大学校园网锐捷认证脚本的所有重要更新和变更。

## 2025-06-25 

- 🔧 **精简OpenWrt系统兼容性提升**
  - 针对BleachWrt等精简系统（缺少`stat`命令）进行特殊适配
  - 增加多种获取文件大小的方法（`ls -l`、`wc -c`等）
  - 提供更全面的后台运行指南
  - 添加运行状态检查方法

- 🛠️ **健壮性提升**
  - 添加日志路径自动切换机制，无写权限时自动迁移到/tmp
  - 检测并解决临时文件创建失败的情况
  - 优化日志清理策略，确保有效控制大小

## 2025-06-24

- ✨ **OpenWrt 兼容版本**
  - 新增 OpenWrt/LEDE 系统专用脚本
  - 移除 bash 特有功能，使用 ash/BusyBox 兼容语法
  - 适配路由器环境，实现在路由器上自动认证

- ✨ **日志管理功能**
  - 设置了日志文件大小限制（默认1MB）
  - 超过限制时，自动保留最新的日志记录
  - 为所有日志添加了时间戳

- 🔄 **日志等级系统**
  - 支持四种日志级别：ERROR、WARN、INFO、DEBUG
  - 可通过命令行参数指定日志级别
  - 按照日志级别智能过滤输出内容

## 2024-10-15

- 🐛 修复了 OpenWrt 下网络状态异常的问题
  - 采用校内图书馆资源访问测试来判断认证状态

## 2024-10-14

- ⚙️ **参数优化**：从硬编码修改为命令行参数获取
- 🔍 **状态检测**：优化网络状态检测机制
- 🔄 **重连策略**：网络中断时，逐步增加重连间隔时间
- 📊 **日志系统**：优化脚本日志输出
