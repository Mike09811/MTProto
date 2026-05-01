#!/bin/bash
#
# MTProxy TLS 一键安装脚本
# 基于 telemt (Rust) — 支持 FakeTLS + 营销群推广
# https://github.com/telemt/telemt
#
# 用法:
#   安装: bash mtproxy_installer.sh
#   卸载: bash mtproxy_installer.sh uninstall
#   绑定营销群: bash mtproxy_installer.sh bindtag <PROXY_TAG>
#   查看信息: bash mtproxy_installer.sh info
#

# ============================================================
# 全局变量
# ============================================================
WORK_DIR="/home/mtproxy"
BINARY_FILE="${WORK_DIR}/telemt"
CONFIG_FILE="${WORK_DIR}/config.toml"
INFO_FILE="${WORK_DIR}/info"
SERVICE_NAME="telemt"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

TELEMT_VERSION="3.4.10"
DEFAULT_PORT=443
DEFAULT_DOMAIN="cloudflare.com"

# ============================================================
# 日志函数
# ============================================================
log_info() { echo -e "\033[32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[31m[ERROR]\033[0m $1" >&2; }

# ============================================================
# 检测 root
# ============================================================
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "请以 root 用户运行此脚本"
        exit 1
    fi
}

# ============================================================
# 获取服务器 IP
# ============================================================
get_server_ip() {
    curl -sf4 https://api.ipify.org || curl -sf4 https://ifconfig.me || curl -sf4 https://icanhazip.com
}

# ============================================================
# 下载 telemt 二进制
# ============================================================
download_telemt() {
    log_info "下载 telemt v${TELEMT_VERSION}..."

    local arch
    arch=$(uname -m)
    local filename=""

    case "$arch" in
        x86_64|amd64)  filename="telemt-x86_64-linux-gnu.tar.gz" ;;
        aarch64|arm64) filename="telemt-aarch64-linux-gnu.tar.gz" ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac

    local url="https://github.com/telemt/telemt/releases/download/${TELEMT_VERSION}/${filename}"
    local tmp_archive="${WORK_DIR}/${filename}"

    if ! curl -sfL "$url" -o "$tmp_archive"; then
        log_error "下载失败: $url"
        exit 1
    fi

    if ! tar -xzf "$tmp_archive" -C "$WORK_DIR"; then
        log_error "解压失败: $tmp_archive"
        rm -f "$tmp_archive"
        exit 1
    fi

    rm -f "$tmp_archive"

    if [[ ! -f "$BINARY_FILE" ]]; then
        log_error "二进制文件未找到，解压内容: $(ls -la "$WORK_DIR")"
        exit 1
    fi

    chmod +x "$BINARY_FILE"
    log_info "telemt 下载完成"
}

# ============================================================
# 生成 Secret
# ============================================================
generate_secret() {
    openssl rand -hex 16 2>/dev/null || {
        head -c 16 /dev/urandom | xxd -ps
    }
}

# ============================================================
# 安装
# ============================================================
do_install() {
    check_root

    if [[ -f "$CONFIG_FILE" ]]; then
        log_error "MTProxy 已安装，如需重新安装请先卸载: bash $0 uninstall"
        exit 1
    fi

    log_info "开始安装 MTProxy (telemt/Rust)..."

    # 安装依赖
    if command -v apt-get &>/dev/null; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl xxd >/dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y curl vim-common >/dev/null 2>&1
    fi

    mkdir -p "$WORK_DIR"

    # 下载 telemt
    download_telemt

    # 获取 IP
    local server_ip
    server_ip=$(get_server_ip)
    if [[ -z "$server_ip" ]]; then
        log_error "无法获取服务器公网 IP"
        exit 1
    fi

    # 生成 Secret (32 位 hex，给 @MTProxybot 注册用)
    local raw_secret
    raw_secret=$(generate_secret)

    # 计算域名 hex
    local domain_hex
    domain_hex=$(echo -n "$DEFAULT_DOMAIN" | xxd -ps 2>/dev/null || echo -n "$DEFAULT_DOMAIN" | od -An -tx1 | tr -d ' \n')

    # 完整连接 Secret: ee + 32hex + domain_hex
    local secret="ee${raw_secret}${domain_hex}"

    log_info "Secret: $raw_secret"

    # 写入 telemt 配置文件
    cat > "$CONFIG_FILE" <<EOF
# Telemt 配置 — MTProto Proxy (Rust)
# https://github.com/telemt/telemt

[general]
use_middle_proxy = true
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"
public_host = "${server_ip}"
public_port = ${DEFAULT_PORT}

[server]
port = ${DEFAULT_PORT}

[server.api]
enabled = true
listen = "127.0.0.1:9999"
whitelist = ["127.0.0.1/32", "::1/128"]

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain = "${DEFAULT_DOMAIN}"
mask = true
tls_emulation = true

[access.users]
default = "${raw_secret}"
EOF

    # 保存信息
    cat > "$INFO_FILE" <<EOF
SERVER_IP=${server_ip}
PORT=${DEFAULT_PORT}
SECRET=${secret}
RAW_SECRET=${raw_secret}
DOMAIN=${DEFAULT_DOMAIN}
TAG=
EOF

    # 创建 systemd 服务
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Telemt - MTProto Proxy for Telegram (Rust)
After=network.target

[Service]
Type=simple
ExecStart=${BINARY_FILE} ${CONFIG_FILE}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    systemctl start "$SERVICE_NAME"

    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "Telemt MTProxy 启动成功"
    else
        log_error "MTProxy 启动失败"
        journalctl -u "$SERVICE_NAME" --no-pager -n 20 >&2
        exit 1
    fi

    show_result
}

# ============================================================
# 展示结果
# ============================================================
show_result() {
    if [[ ! -f "$INFO_FILE" ]]; then
        log_error "MTProxy 未安装"
        return 1
    fi

    source "$INFO_FILE"

    echo ""
    echo "============================================================"
    echo "  MTProxy 安装完成 (telemt / Rust)"
    echo "============================================================"
    echo ""
    echo "  服务器 IP:    $SERVER_IP"
    echo "  连接端口:     $PORT"
    echo "  伪装域名:     $DOMAIN"
    echo ""
    echo "  ---- 密钥信息 ----"
    echo ""
    echo "  原始 Secret（给 @MTProxybot 注册用）:"
    echo "    $RAW_SECRET"
    echo ""
    echo "  连接 Secret（含 ee 前缀，给客户端用）:"
    echo "    $SECRET"
    echo ""

    if [[ -n "$TAG" ]]; then
        echo "  营销群绑定:   ✅ 已启用"
        echo "  Proxy Tag:    $TAG"
        echo ""
    fi

    echo "  ---- 连接链接 ----"
    echo ""
    echo "  tg://proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}"
    echo ""
    echo "  https://t.me/proxy?server=${SERVER_IP}&port=${PORT}&secret=${SECRET}"
    echo ""
    echo "============================================================"
    echo "  管理命令:"
    echo "    状态: systemctl status $SERVICE_NAME"
    echo "    重启: systemctl restart $SERVICE_NAME"
    echo "    日志: journalctl -u $SERVICE_NAME -f"
    echo "    绑定营销群: bash $0 bindtag <TAG>"
    echo "    查看信息: bash $0 info"
    echo "    卸载: bash $0 uninstall"
    echo "============================================================"
    echo ""
}

# ============================================================
# 绑定营销群
# ============================================================
do_bindtag() {
    check_root

    local tag="$1"
    if [[ -z "$tag" ]]; then
        log_error "用法: bash $0 bindtag <PROXY_TAG>"
        exit 1
    fi

    if [[ ! -f "$INFO_FILE" ]]; then
        log_error "MTProxy 未安装"
        exit 1
    fi

    source "$INFO_FILE"

    # 在 [general] 段添加/更新 ad_tag
    if grep -q "^ad_tag" "$CONFIG_FILE"; then
        sed -i "s/^ad_tag = .*/ad_tag = \"${tag}\"/" "$CONFIG_FILE"
    else
        sed -i "/^\[general\]/a ad_tag = \"${tag}\"" "$CONFIG_FILE"
    fi

    # 更新 info
    sed -i "s/^TAG=.*/TAG=${tag}/" "$INFO_FILE"

    systemctl restart "$SERVICE_NAME"

    sleep 2
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "营销群绑定成功，服务已重启"
        show_result
    else
        log_error "服务重启失败"
        journalctl -u "$SERVICE_NAME" --no-pager -n 10 >&2
    fi
}

# ============================================================
# 卸载
# ============================================================
do_uninstall() {
    check_root

    log_info "正在卸载 MTProxy..."

    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload

    rm -rf "$WORK_DIR"

    echo ""
    log_info "MTProxy 已完全卸载"
    echo ""
}

# ============================================================
# 入口
# ============================================================
main() {
    case "$1" in
        uninstall) do_uninstall ;;
        bindtag)   do_bindtag "$2" ;;
        info)      show_result ;;
        *)         do_install ;;
    esac
}

main "$@"
