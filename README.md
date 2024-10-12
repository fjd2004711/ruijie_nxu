对于宁夏大学（NXU）校园网锐捷认证的 Linux 通用登录脚本

## 使用方法

### 配置文件

首先将脚本文件放在 `/usr/bin/` 目录下，配置 `ruijie_nxu.sh` 文件中的学号，运营商等信息。

```
[network]
service=campus      # 或者 chinanet、chinaunicom 等。
username=your_username      # 学号
password=your_password      # 密码
retry_limit=3       # 重连次数限制
wait_time=60        # 每次尝试之间的等待时间（单位：秒）
```

- service：运营商，校园网（campus），中国电信（chinanet），中国联通（chinaunicom），中国移动（chinamobile）。

由于笔者没有运营商相关账号，因此无法测试脚本运行，仅测试了校园网。


> 注意：以下所有命令均以 `root` 用户运行。

### 配置权限


首先确保具有运行权限，并且给脚本以及配置文件添加权限。

在文件所在目录下执行：

```
chmod 777 ruijie_nxu.sh
```

### 运行脚本

```
./ruijie_nxu.sh
```

程序会间隔 60s 检测一次在线状态，如果离线会自动重新连接。

### 下线

```
./ruijie_nxu.sh logout
```
