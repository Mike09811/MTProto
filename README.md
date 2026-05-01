# MTProxy TLS 一键安装脚本

一键部署 Telegram MTProxy TLS 代理服务，支持绑定营销频道/群组推广。

基于 [telemt](https://github.com/telemt/telemt)（Rust 实现），预编译二进制，无需编译，支持 FakeTLS 域名伪装 + 营销群推广。

## ✨ 功能特性

- 🚀 **一键安装** — 预编译二进制，无需编译，秒装
- 🔒 **TLS 伪装** — FakeTLS 伪装为正常 HTTPS 流量（默认伪装 cloudflare.com）
- 📢 **营销群绑定** — 支持 Proxy Tag，用户连接后展示推广频道（✅ Rust 版确认支持）
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
  MTProxy 安装完成 (telemt / Rust)
============================================================

  服务器 IP:    203.0.113.1
  连接端口:     443
  伪装域名:     cloudflare.com

  ---- 密钥信息 ----

  原始 Secret（给 @MTProxybot 注册用）:
    a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

  连接 Secret（含 ee 前缀，给客户端用）:
    eea1b2c3d4...636c6f7564666c6172652e636f6d

  ---- 连接链接 ----

  tg://proxy?server=203.0.113.1&port=443&secret=ee...
  https://t.me/proxy?server=203.0.113.1&port=443&secret=ee...

============================================================
```

## 🔧 管理命令

```bash
cd /home/mtproxy

# 查看状态
systemctl status telemt

# 重启
systemctl restart telemt

# 查看日志
journalctl -u telemt -f

# 查看连接信息
bash mtproxy_installer.sh info

# 绑定营销群
bash mtproxy_installer.sh bindtag <PROXY_TAG>

# 卸载
bash mtproxy_installer.sh uninstall
```

## 📢 绑定营销群

安装完成后，用原始 Secret（32 字符 hex）去 @MTProxybot 注册：

1. 打开 Telegram，搜索 **@MTProxybot**，发送 `/newproxy`
2. 输入 `服务器IP:端口`（如 `203.0.113.1:443`）
3. 输入原始 Secret（32 字符纯 hex，不含 ee 前缀）
4. 选择要推广的频道/群组
5. 拿到 Proxy Tag 后执行：

```bash
cd /home/mtproxy
bash mtproxy_installer.sh bindtag 你的PROXY_TAG
```

> **注意：** @MTProxybot 给的链接不会生效，请使用安装脚本输出的 `tg://` 链接（包含 `ee` 前缀和域名 hex）。

## 🗑️ 卸载

```bash
cd /home/mtproxy
bash mtproxy_installer.sh uninstall
```

## 📁 文件结构

```
/home/mtproxy/
├── mtproxy_installer.sh    # 安装管理脚本
├── telemt                  # MTProxy 二进制文件 (Rust)
├── config.toml             # telemt 配置文件
└── info                    # 连接信息
```

## 📄 License

MIT License
