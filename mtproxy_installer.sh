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
SOURCE_DIR="${WORK_DIR}/telemt-src"

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
# 安装 Rust (如果未安装)
# ============================================================
install_rust() {
    if command -v cargo &>/dev/null; then
        log_info "Rust 已安装"
        return 0
    fi

    log_info "安装 Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"

    if [[ -f "$HOME/.cargo/bin/cargo" ]]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
}

# ============================================================
# 编译 telemt 源码
# ============================================================
build_telemt() {
    log_info "编译 telemt v${TELEMT_VERSION}..."

    if [[ ! -d "$SOURCE_DIR" ]]; then
        log_error "源码目录不存在: $SOURCE_DIR"
        exit 1
    fi

    cd "$SOURCE_DIR"

    if ! command -v cargo &>/dev/null; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

    log_info "开始编译（首次可能需要几分钟）..."
    if ! cargo build --release 2>&1 | tail -20; then
        log_error "编译失败"
        exit 1
    fi

    local built_binary="$SOURCE_DIR/target/release/telemt"
    if [[ ! -f "$built_binary" ]]; then
        built_binary="$SOURCE_DIR/target/release/telemt.exe"
    fi

    if [[ ! -f "$built_binary" ]]; then
        log_error "编译产物未找到"
        exit 1
    fi

    cp "$built_binary" "$BINARY_FILE"
    chmod +x "$BINARY_FILE"

    log_info "telemt 编译完成"
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

    if command -v apt-get &>/dev/null; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl xxd >/dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y curl vim-common >/dev/null 2>&1
    fi

    mkdir -p "$WORK_DIR"

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -d "${script_dir}/telemt" ]]; then
        log_info "复制 telemt 源码..."
        cp -r "${script_dir}/telemt" "$SOURCE_DIR"
    else
        log_error "未找到 telemt 源码目录: ${script_dir}/telemt"
        exit 1
    fi

    install_rust
    build_telemt

    local server_ip
    server_ip=$(get_server_ip)
    if [[ -z "$server_ip" ]]; then
        log_error "无法获取服务器公网 IP"
        exit 1
    fi

    local raw_secret
    raw_secret=$(generate_secret)

    local domain_hex
    domain_hex=$(echo -n "$DEFAULT_DOMAIN" | xxd -ps 2>/dev/null || echo -n "$DEFAULT_DOMAIN" | od -An -tx1 | tr -d ' \n')

    local secret="ee${raw_secret}${domain_hex}"

    log_info "Secret: $raw_secret"

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

    cat > "$INFO_FILE" <<EOF
SERVER_IP=${server_ip}
PORT=${DEFAULT_PORT}
SECRET=${secret}
RAW_SECRET=${raw_secret}
DOMAIN=${DEFAULT_DOMAIN}
TAG=
EOF

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

    if grep -q "^ad_tag" "$CONFIG_FILE"; then
        sed -i "s/^ad_tag = .*/ad_tag = \"${tag}\"/" "$CONFIG_FILE"
    else
        sed -i "/^\[general\]/a ad_tag = \"${tag}\"" "$CONFIG_FILE"
    fi

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
