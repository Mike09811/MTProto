# MTProto Proxy 一键安装脚本

一键部署 Telegram MTProto Proxy 代理服务，支持绑定营销频道/群组推广。

## ✨ 功能特性

- 🚀 **一键安装** — 全自动编译安装，无需手动操作
- 📢 **营销群绑定** — 支持 Proxy Tag，用户连接后自动展示推广频道
- 🔄 **自动更新** — 每天自动更新 Telegram 配置文件，保持服务稳定
- 🖥️ **多系统支持** — Debian/Ubuntu、CentOS/RHEL/Fedora、Alpine Linux
- ⚙️ **systemd 管理** — 开机自启、崩溃自动重启
- 🔗 **连接链接生成** — 安装完成自动生成 `tg://` 和 `https://t.me/proxy` 链接
- 🗑️ **一键卸载** — 完整清理所有文件和配置

## 📋 系统要求

| 系统 | 版本 |
|------|------|
| Debian | 9+ |
| Ubuntu | 18.04+ |
| CentOS | 7+ |
| RHEL / Rocky / Alma | 8+ |
| Fedora | 30+ |
| Alpine | 3.10+ |

- 需要 **root** 权限
- 需要可访问 GitHub 和 Telegram 服务器的网络环境

## 🚀 快速开始

### 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mike09811/MTProto/main/mtproxy_installer.sh)
```

或者手动下载后运行：

```bash
wget https://raw.githubusercontent.com/Mike09811/MTProto/main/mtproxy_installer.sh
chmod +x mtproxy_installer.sh
sudo bash mtproxy_installer.sh
```

### 安装过程

脚本会自动完成以下步骤：

1. 检测系统环境并安装编译依赖
2. 从 Telegram 官方仓库克隆并编译 MTProxy
3. 生成客户端连接密钥（Secret）
4. 下载 Telegram 代理配置文件
5. **提示输入 Proxy Tag**（绑定营销群，可跳过）
6. **提示输入监听端口**（默认 443）
7. 创建 systemd 服务并启动
8. 配置每日自动更新任务
9. 显示连接信息和链接

### 安装完成输出示例

```
============================================================
  MTProxy 安装完成
============================================================

  服务器 IP:    203.0.113.1
  监听端口:     443
  Secret:       a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6

  营销群绑定:   ✅ 已启用
  Proxy Tag:    abc123def456...

  ---- 连接链接 ----

  tg://proxy?server=203.0.113.1&port=443&secret=a1b2c3d4...

  https://t.me/proxy?server=203.0.113.1&port=443&secret=a1b2c3d4...

============================================================
```

## 📢 营销群绑定说明

通过绑定营销频道，所有通过你的代理连接 Telegram 的用户都会在聊天列表顶部看到你推广的频道/群组。

### 获取 Proxy Tag

1. 打开 Telegram，搜索 **@MTProxybot**
2. 发送 `/newproxy`
3. 机器人会提示 `Please send me its address in the format host:port`
4. 回复你的 **服务器IP:端口**，例如 `203.0.113.1:443`
5. 机器人会让你选择要推广的频道/群组
6. 完成后机器人返回一串十六进制字符，即 **Proxy Tag**
7. 在安装脚本提示时输入该 Tag

> 如果暂时不需要绑定营销群，安装时直接按回车跳过即可。

## 🔧 服务管理

```bash
# 启动服务
systemctl start mtproxy

# 停止服务
systemctl stop mtproxy

# 重启服务
systemctl restart mtproxy

# 查看状态
systemctl status mtproxy

# 查看日志
journalctl -u mtproxy -f
```

## 🗑️ 卸载

```bash
sudo bash mtproxy_installer.sh uninstall
```

卸载会清理以下内容：
- MTProxy 可执行文件
- 配置目录 `/etc/mtproxy/`
- systemd 服务文件
- 自动更新脚本和 cron 任务
- 编译临时文件

## 📁 文件结构

```
/usr/local/bin/mtproto-proxy          # MTProxy 可执行文件
/etc/mtproxy/                          # 配置目录
├── secret                             # 客户端连接密钥
├── proxy-secret                       # Telegram proxy-secret
├── proxy-multi.conf                   # Telegram 数据中心配置
└── proxy_tag                          # 营销群 Proxy Tag（可选）
/etc/systemd/system/mtproxy.service    # systemd 服务文件
/usr/local/bin/mtproxy_update.sh       # 自动更新脚本
```

## 🔄 自动更新

安装完成后会自动配置 cron 定时任务，每天凌晨 3:00 自动从 Telegram 服务器更新 `proxy-secret` 和 `proxy-multi.conf` 配置文件。

- 更新成功后自动重启服务
- 更新失败时自动回滚到旧配置
- 更新日志记录在 `/var/log/mtproxy_update.log`

## ❓ 常见问题

### 端口被占用

```bash
# 查看端口占用
ss -tlnp | grep 443

# 安装时选择其他端口即可
```

### 服务启动失败

```bash
# 查看详细日志
journalctl -u mtproxy --no-pager -n 50

# 检查配置文件
ls -la /etc/mtproxy/
```

### 无法连接

- 确认服务器防火墙已放行对应端口
- 确认安全组（云服务器）已放行对应端口
- 检查服务是否正常运行：`systemctl status mtproxy`

## 📄 License

MIT License
