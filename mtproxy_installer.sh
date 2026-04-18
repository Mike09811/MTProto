#!/bin/bash
#
# MTProxy 一键安装脚本 v2.0
# 用于在 Linux 服务器上快速部署 Telegram MTProto Proxy 代理服务
# 支持 Debian/Ubuntu、CentOS/RHEL、Alpine Linux
# 全自动安装，无交互提示
#
# 用法:
#   安装: bash mtproxy_installer.sh
#   卸载: bash mtproxy_installer.sh uninstall
#

# ============================================================
# 全局变量
# ============================================================
INSTALL_DIR="/etc/mtproxy"
BINARY_PATH="/usr/local/bin/mtproto-proxy"
SERVICE_NAME="mtproxy"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
BUILD_DIR="/tmp/MTProxy"
UPDATE_SCRIPT="/usr/local/bin/mtproxy_update.sh"
UPDATE_LOG="/var/log/mtproxy_update.log"
MTPROXY_REPO="https://github.com/TelegramMessenger/MTProxy.git"
PROXY_SECRET_URL="https://core.telegram.org/getProxySecret"
PROXY_CONFIG_URL="https://core.telegram.org/getProxyConfig"

DEFAULT_PORT=443
PROXY_PORT="${DEFAULT_PORT}"
SECRET=""
SECRET_RAW=""
FAKE_TLS_DOMAIN="cloudflare.com"
PROXY_TAG=""
SERVER_IP=""
OS_TYPE=""
PKG_MANAGER=""

# ============================================================
# 日志输出工具函数
# ============================================================

log_info() {
    echo -e "\033[32m[INFO]\033[0m $1"
}

log_warn() {
    echo -e "\033[33m[WARN]\033[0m $1" >&2
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $1" >&2
}

# ============================================================
# 桩函数（后续任务中实现）
# ============================================================

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "请以 root 用户运行此脚本"
        log_error "请尝试: sudo bash $0"
        exit 1
    fi
}

detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测操作系统：/etc/os-release 文件不存在"
        exit 1
    fi

    local os_id
    os_id=$(. /etc/os-release && echo "$ID")

    case "$os_id" in
        debian|ubuntu)
            OS_TYPE="debian"
            PKG_MANAGER="apt-get"
            ;;
        centos|rhel|fedora|rocky|alma)
            OS_TYPE="centos"
            if command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            ;;
        alpine)
            OS_TYPE="alpine"
            PKG_MANAGER="apk"
            ;;
        *)
            log_error "不支持的操作系统: $os_id"
            log_error "支持的系统: Debian/Ubuntu、CentOS/RHEL/Fedora、Alpine"
            exit 1
            ;;
    esac

    log_info "检测到操作系统: $os_id (类型: $OS_TYPE, 包管理器: $PKG_MANAGER)"
}

install_dependencies() {
    log_info "正在安装编译依赖..."

    local packages=""
    case "$OS_TYPE" in
        debian)
            $PKG_MANAGER update -y >/dev/null 2>&1
            packages="build-essential git curl libssl-dev zlib1g-dev"
            ;;
        centos)
            packages="gcc make git curl openssl-devel zlib-devel"
            ;;
        alpine)
            packages="gcc make git curl openssl-dev zlib-dev linux-headers musl-dev"
            ;;
    esac

    for pkg in $packages; do
        log_info "安装 $pkg ..."
        if ! $PKG_MANAGER install -y "$pkg" >/dev/null 2>&1; then
            log_error "依赖包安装失败: $pkg"
            log_error "请尝试手动运行: $PKG_MANAGER install -y $pkg"
            exit 1
        fi
    done

    log_info "所有依赖安装完成"
}

clone_and_build() {
    log_info "正在从 GitHub 克隆 MTProxy 源码..."

    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    fi

    if ! git clone "$MTPROXY_REPO" "$BUILD_DIR" 2>&1; then
        log_error "源码克隆失败，请检查网络连接"
        log_error "仓库地址: $MTPROXY_REPO"
        exit 1
    fi

    log_info "正在编译 MTProxy..."
    cd "$BUILD_DIR" || exit 1

    if ! make -j"$(nproc)" 2>/tmp/mtproxy_build.log; then
        log_error "MTProxy 编译失败，以下是编译日志的最后 20 行:"
        tail -20 /tmp/mtproxy_build.log >&2
        log_info "请检查编译依赖是否完整安装"
        exit 1
    fi

    cd - >/dev/null || exit 1
    log_info "MTProxy 编译成功"
}

install_binary() {
    log_info "正在安装 MTProxy 二进制文件..."

    if [[ ! -f "$BUILD_DIR/objs/bin/mtproto-proxy" ]]; then
        log_error "编译产物不存在: $BUILD_DIR/objs/bin/mtproto-proxy"
        exit 1
    fi

    cp "$BUILD_DIR/objs/bin/mtproto-proxy" "$BINARY_PATH"
    chmod +x "$BINARY_PATH"

    mkdir -p "$INSTALL_DIR"

    log_info "MTProxy 已安装到 $BINARY_PATH"
    log_info "配置目录已创建: $INSTALL_DIR"
}

generate_secret() {
    log_info "正在生成客户端连接密钥（fake-tls 模式）..."

    # 生成 16 字节随机密钥
    local raw_secret
    raw_secret=$(head -c 16 /dev/urandom | xxd -ps)

    if [[ -z "$raw_secret" ]]; then
        raw_secret=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi

    # fake-tls 伪装域名（用于绕过 DPI 检测）
    local fake_tls_domain="cloudflare.com"
    local domain_hex
    domain_hex=$(echo -n "$fake_tls_domain" | xxd -ps)

    if [[ -z "$domain_hex" ]]; then
        domain_hex=$(echo -n "$fake_tls_domain" | od -An -tx1 | tr -d ' \n')
    fi

    # 完整 Secret = dd + 随机密钥 + 域名十六进制
    SECRET="dd${raw_secret}${domain_hex}"

    # 保存原始密钥（MTProxy 启动参数使用原始密钥）
    SECRET_RAW="$raw_secret"
    echo "$raw_secret" > "$INSTALL_DIR/secret"

    log_info "Secret 已生成（fake-tls 模式，伪装域名: $fake_tls_domain）"
}

download_config() {
    log_info "正在从 Telegram 服务器下载配置文件..."

    if ! curl -sf "$PROXY_SECRET_URL" -o "$INSTALL_DIR/proxy-secret"; then
        log_error "proxy-secret 下载失败"
        log_error "请手动下载: curl -s $PROXY_SECRET_URL -o $INSTALL_DIR/proxy-secret"
        exit 1
    fi
    log_info "proxy-secret 下载完成"

    if ! curl -sf "$PROXY_CONFIG_URL" -o "$INSTALL_DIR/proxy-multi.conf"; then
        log_error "proxy-multi.conf 下载失败"
        log_error "请手动下载: curl -s $PROXY_CONFIG_URL -o $INSTALL_DIR/proxy-multi.conf"
        exit 1
    fi
    log_info "proxy-multi.conf 下载完成"
}

configure_port() {
    PROXY_PORT="${DEFAULT_PORT}"
    log_info "监听端口: $PROXY_PORT"
}

setup_systemd_service() {
    log_info "正在创建 systemd 服务..."

    local exec_start="$BINARY_PATH -u nobody -p 8888 -H $PROXY_PORT -S $SECRET_RAW --aes-pwd $INSTALL_DIR/proxy-secret $INSTALL_DIR/proxy-multi.conf -M 1 --nat-info $SERVER_IP:$SERVER_IP -D $FAKE_TLS_DOMAIN"

    if [[ -n "$PROXY_TAG" ]]; then
        exec_start="$exec_start -P $PROXY_TAG"
    fi

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=MTProxy for Telegram
After=network.target

[Service]
Type=simple
ExecStart=$exec_start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1

    log_info "systemd 服务已创建并设置为开机自启"
}

start_service() {
    log_info "正在启动 MTProxy 服务..."

    if systemctl start "$SERVICE_NAME"; then
        log_info "MTProxy 服务启动成功"
    else
        log_error "MTProxy 服务启动失败"
        log_info "服务日志:"
        journalctl -u "$SERVICE_NAME" --no-pager -n 20 >&2
        echo ""
        log_info "排查建议:"
        log_info "  1. 检查端口 $PROXY_PORT 是否被占用: ss -tlnp | grep $PROXY_PORT"
        log_info "  2. 检查配置文件是否完整: ls -la $INSTALL_DIR/"
        log_info "  3. 手动启动测试: $BINARY_PATH -u nobody -p 8888 -H $PROXY_PORT -S $SECRET_RAW --aes-pwd $INSTALL_DIR/proxy-secret $INSTALL_DIR/proxy-multi.conf -M 1"
        exit 1
    fi
}

setup_cron_update() {
    log_info "正在配置自动更新任务..."

    cat > "$UPDATE_SCRIPT" <<'UPDATEEOF'
#!/bin/bash
LOG="/var/log/mtproxy_update.log"
CONFIG_DIR="/etc/mtproxy"
UPDATED=0

update_file() {
    local url="$1" dest="$2" backup="${2}.bak"
    cp "$dest" "$backup" 2>/dev/null
    if curl -sf "$url" -o "$dest"; then
        echo "$(date): Updated $dest" >> "$LOG"
        UPDATED=1
    else
        if [[ -f "$backup" ]]; then
            mv "$backup" "$dest"
        fi
        echo "$(date): Failed to update $dest, rolled back" >> "$LOG"
    fi
}

update_file "https://core.telegram.org/getProxySecret" "$CONFIG_DIR/proxy-secret"
update_file "https://core.telegram.org/getProxyConfig" "$CONFIG_DIR/proxy-multi.conf"

if [[ "$UPDATED" -eq 1 ]]; then
    systemctl restart mtproxy
    echo "$(date): Service restarted" >> "$LOG"
fi
UPDATEEOF

    chmod +x "$UPDATE_SCRIPT"

    # 添加 cron 定时任务（每天凌晨 3 点执行）
    local cron_job="0 3 * * * $UPDATE_SCRIPT"
    (crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT"; echo "$cron_job") | crontab -

    log_info "自动更新任务已配置（每天凌晨 3:00 执行）"
}

get_server_ip() {
    log_info "正在获取服务器公网 IP..."
    SERVER_IP=$(curl -sf https://api.ipify.org || curl -sf https://ifconfig.me || curl -sf https://icanhazip.com)

    if [[ -z "$SERVER_IP" ]]; then
        SERVER_IP="<无法获取，请手动填写服务器IP>"
        log_warn "无法自动获取公网 IP，请在连接链接中手动替换"
    else
        log_info "服务器公网 IP: $SERVER_IP"
    fi
}

show_result() {
    echo ""
    echo "============================================================"
    echo "  MTProxy 安装完成"
    echo "============================================================"
    echo ""
    echo "  服务器 IP:    $SERVER_IP"
    echo "  监听端口:     $PROXY_PORT"
    echo "  模式:         fake-tls (伪装域名: $FAKE_TLS_DOMAIN)"
    echo ""
    echo "  ---- 密钥信息 ----"
    echo ""
    echo "  原始 Secret（给 @MTProxybot 用）:"
    echo "    $SECRET_RAW"
    echo ""
    echo "  连接 Secret（给客户端用，含 dd 前缀）:"
    echo "    $SECRET"
    echo ""
    echo "  ---- 连接链接（分享给用户） ----"
    echo ""
    echo "  tg://proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${SECRET}"
    echo ""
    echo "  https://t.me/proxy?server=${SERVER_IP}&port=${PROXY_PORT}&secret=${SECRET}"
    echo ""
    echo "  ---- 绑定营销群 ----"
    echo ""
    echo "  去 Telegram 找 @MTProxybot 发送 /newproxy"
    echo "  输入地址: ${SERVER_IP}:${PROXY_PORT}"
    echo "  输入密钥: ${SECRET_RAW}"
    echo "  拿到 Proxy Tag 后执行:"
    echo "    bash $0 bindtag <你的PROXY_TAG>"
    echo ""
    echo "============================================================"
    echo "  管理命令:"
    echo "    启动: systemctl start $SERVICE_NAME"
    echo "    停止: systemctl stop $SERVICE_NAME"
    echo "    状态: systemctl status $SERVICE_NAME"
    echo "    绑定营销群: bash $0 bindtag <PROXY_TAG>"
    echo "    卸载: bash $0 uninstall"
    echo "============================================================"
    echo ""
}

# ============================================================
# 安装流程
# ============================================================

do_install() {
    check_root
    detect_os
    install_dependencies
    clone_and_build
    install_binary
    generate_secret
    download_config
    configure_port
    get_server_ip
    setup_systemd_service
    start_service
    setup_cron_update
    show_result
}

# ============================================================
# 卸载流程
# ============================================================

do_uninstall() {
    check_root

    log_info "正在卸载 MTProxy..."

    # 停止服务
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl stop "$SERVICE_NAME"
        log_info "MTProxy 服务已停止"
    fi

    # 禁用开机自启
    if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
        log_info "已禁用开机自启"
    fi

    # 删除服务单元文件
    if [[ -f "$SERVICE_FILE" ]]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
        log_info "已删除服务单元文件"
    fi

    # 删除二进制文件
    if [[ -f "$BINARY_PATH" ]]; then
        rm -f "$BINARY_PATH"
        log_info "已删除 MTProxy 可执行文件"
    fi

    # 删除配置目录
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        log_info "已删除配置目录 $INSTALL_DIR"
    fi

    # 删除更新脚本
    if [[ -f "$UPDATE_SCRIPT" ]]; then
        rm -f "$UPDATE_SCRIPT"
        log_info "已删除自动更新脚本"
    fi

    # 删除 cron 定时任务
    if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT"; then
        crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT" | crontab -
        log_info "已删除 cron 定时任务"
    fi

    # 清理编译目录
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    fi

    echo ""
    log_info "============================================"
    log_info "  MTProxy 已完全卸载"
    log_info "============================================"
    echo ""
}

# ============================================================
# 绑定营销群
# ============================================================

do_bindtag() {
    check_root

    local tag="$1"
    if [[ -z "$tag" ]]; then
        log_error "请提供 Proxy Tag"
        log_error "用法: bash $0 bindtag <PROXY_TAG>"
        exit 1
    fi

    echo "$tag" > "$INSTALL_DIR/proxy_tag"

    # 读取当前 ExecStart 并追加 -P 参数
    local current_exec
    current_exec=$(grep "^ExecStart=" "$SERVICE_FILE" | sed 's/ExecStart=//')

    # 移除旧的 -P 参数（如果有）
    current_exec=$(echo "$current_exec" | sed 's/ -P [^ ]*//')

    # 添加新的 -P 参数
    current_exec="$current_exec -P $tag"

    sed -i "s|^ExecStart=.*|ExecStart=$current_exec|" "$SERVICE_FILE"

    systemctl daemon-reload
    systemctl restart "$SERVICE_NAME"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "营销群绑定成功，Proxy Tag: $tag"
        log_info "MTProxy 服务已重启"
    else
        log_error "服务重启失败，请检查 Proxy Tag 是否正确"
        journalctl -u "$SERVICE_NAME" --no-pager -n 10 >&2
    fi
}

# ============================================================
# 入口函数
# ============================================================

main() {
    case "$1" in
        uninstall) do_uninstall ;;
        bindtag)   do_bindtag "$2" ;;
        *)         do_install ;;
    esac
}

main "$@"
