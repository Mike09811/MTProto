#!/bin/bash
#
# MTProxy TLS 一键安装脚本
# 基于 mtg (9seconds/mtg) — Go 语言实现的 MTProxy
# 支持 fake-tls 伪装，支持绑定营销群
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
BINARY_FILE="${WORK_DIR}/mtg"
CONFIG_FILE="${WORK_DIR}/config.toml"
INFO_FILE="${WORK_DIR}/info"
SERVICE_NAME="mtg"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

MTG_VERSION="2.1.7"
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
# 下载 mtg 二进制
# ============================================================
download_mtg() {
    log_info "下载 mtg v${MTG_VERSION}..."

    local arch
    arch=$(uname -m)
    local filename=""

    case "$arch" in
        x86_64|amd64)  filename="mtg-linux-amd64" ;;
        aarch64|arm64) filename="mtg-linux-arm64" ;;
        armv7l)        filename="mtg-linux-arm" ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac

    local url="https://github.com/9seconds/mtg/releases/download/v${MTG_VERSION}/${filename}"

    if ! curl -sfL "$url" -o "$BINARY_FILE"; then
        log_error "下载失败: $url"
        exit 1
    fi

    chmod +x "$BINARY_FILE"
    log_info "mtg 下载完成"
}

# ============================================================
# 生成 Secret
# ============================================================
generate_secret() {
    local secret
    secret=$("$BINARY_FILE" generate-secret "$DEFAULT_DOMAIN" 2>/dev/null)

    if [[ -z "$secret" ]]; then
        # 手动生成 dd + random + domain_hex
        local raw
        raw=$(head -c 16 /dev/urandom | xxd -ps 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
        local domain_hex
        domain_hex=$(echo -n "$DEFAULT_DOMAIN" | xxd -ps 2>/dev/null || echo -n "$DEFAULT_DOMAIN" | od -An -tx1 | tr -d ' \n')
        secret="dd${raw}${domain_hex}"
    fi

    echo "$secret"
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

    log_info "开始安装 MTProxy (mtg)..."

    # 安装依赖
    if command -v apt-get &>/dev/null; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl xxd >/dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y curl vim-common >/dev/null 2>&1
    fi

    mkdir -p "$WORK_DIR"

    # 下载 mtg
    download_mtg

    # 获取 IP
    local server_ip
    server_ip=$(get_server_ip)
    if [[ -z "$server_ip" ]]; then
        log_error "无法获取服务器公网 IP"
        exit 1
    fi

    # 生成 Secret
    local secret
    secret=$(generate_secret)

    log_info "Secret: $secret"

    # 提取原始 Secret（去掉 dd 前缀和域名部分）
    local raw_secret
    raw_secret=$(echo "$secret" | sed 's/^dd//' | cut -c1-32)

    # 写入 mtg 配置文件
    cat > "$CONFIG_FILE" <<EOF
secret = "${secret}"
bind-to = "0.0.0.0:${DEFAULT_PORT}"
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
Description=MTG - MTProxy for Telegram
After=network.target

[Service]
Type=simple
ExecStart=${BINARY_FILE} run ${CONFIG_FILE}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    systemctl start "$SERVICE_NAME"

    sleep 2

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "MTProxy 启动成功"
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
    echo "  MTProxy 安装完成 (mtg)"
    echo "============================================================"
    echo ""
    echo "  服务器 IP:    $SERVER_IP"
    echo "  连接端口:     $PORT"
    echo "  伪装域名:     $DOMAIN"
    echo ""
    echo "  ---- 密钥信息 ----"
    echo ""
    echo "  原始 Secret（给 @MTProxybot 用）:"
    echo "    $RAW_SECRET"
    echo ""
    echo "  连接 Secret（完整）:"
    echo "    $SECRET"
    echo ""

    if [[ -n "$TAG" ]]; then
        echo "  营销群绑定:   ✅ 已启用"
        echo "  Proxy Tag:    $TAG"
    fi

    echo ""
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

    # 更新配置
    cat > "$CONFIG_FILE" <<EOF
secret = "${SECRET}"
bind-to = "0.0.0.0:${PORT}"

[proxy-tag]
tag = "${tag}"
EOF

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
