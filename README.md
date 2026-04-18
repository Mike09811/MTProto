# MTProxy TLS 一键安装脚本

一键部署 Telegram MTProxy TLS 代理服务，支持绑定营销频道/群组推广。

基于 [sunpma/mtp](https://github.com/sunpma/mtp) 方案，使用预编译二进制，无需编译，支持 TLS 域名伪装。

## ✨ 功能特性

- 🚀 **一键安装** — 预编译二进制，无需编译，秒装
- 🔒 **TLS 伪装** — 伪装为正常 HTTPS 流量（默认伪装 azure.microsoft.com）
- 📢 **营销群绑定** — 支持 Proxy Tag，用户连接后展示推广频道
- 🔗 **连接链接生成** — 安装完成自动生成 `tg://` 和 `https://t.me/proxy` 链接
- 🗑️ **绿色版** — 所有文件在一个目录，卸载干净

## 📋 系统要求

- Linux 系统（Debian/Ubuntu、CentOS/RHEL、Alpine）
- x86_64 或 ARM64 架构
- root 权限

## 🚀 快速开始

### 一键安装

```bash
mkdir -p /home/mtproxy && cd /home/mtproxy
curl -fsSL https://raw.githubusercontent.com/Mike09811/MTProto/main/mtproxy_installer.sh -o mtproxy_installer.sh
bash mtproxy_installer.sh
```

### 安装完成输出示例

```
============================================================
  MTProxy TLS 安装完成
============================================================

  服务器 IP:    203.0.113.1
  连接端口:     443
  管理端口:     8888
  伪装域名:     azure.microsoft.com

  ---- 密钥信息 ----

  原始 Secret（给 @MTProxybot 用）:
    a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

  连接 Secret（含 dd 前缀）:
    dda1b2c3d4...617a7572652e6d6963726f736f66742e636f6d

  ---- 连接链接 ----

  tg://proxy?server=203.0.113.1&port=443&secret=dd...
  https://t.me/proxy?server=203.0.113.1&port=443&secret=dd...

============================================================
```

## 🔧 管理命令

```bash
cd /home/mtproxy

# 启动
bash mtproxy_installer.sh start

# 停止
bash mtproxy_installer.sh stop

# 重启
bash mtproxy_installer.sh restart

# 查看状态
bash mtproxy_installer.sh status

# 查看连接信息
bash mtproxy_installer.sh info

# 绑定营销群
bash mtproxy_installer.sh bindtag <PROXY_TAG>

# 卸载
bash mtproxy_installer.sh uninstall
```

## 📢 绑定营销群

安装完成后，用原始 Secret（32 字符那个）去 @MTProxybot 注册：

1. 打开 Telegram，搜索 **@MTProxybot**，发送 `/newproxy`
2. 输入 `服务器IP:端口`（如 `203.0.113.1:443`）
3. 输入原始 Secret（32 字符，不带 dd 前缀）
4. 选择要推广的频道/群组
5. 拿到 Proxy Tag 后执行：

```bash
cd /home/mtproxy
bash mtproxy_installer.sh bindtag 你的PROXY_TAG
```

## 🗑️ 卸载

```bash
cd /home/mtproxy
bash mtproxy_installer.sh uninstall
```

## 📁 文件结构

```
/home/mtproxy/
├── mtproxy_installer.sh    # 安装管理脚本
├── mtproto-proxy           # MTProxy 二进制文件
├── mtp_config              # 配置文件
├── secret                  # 客户端连接密钥
├── proxy-secret            # Telegram proxy-secret
├── proxy-multi.conf        # Telegram 数据中心配置
└── pid                     # 进程 PID 文件
```

## 📄 License

MIT License
