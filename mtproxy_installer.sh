#!/bin/bash
#
# MTProxy TLS 一键安装脚本
# 基于 sunpma/mtp 方案，使用预编译二进制，支持 TLS 域名伪装
# 支持绑定营销群（Proxy Tag）
#
# 用法:
#   安装: bash mtproxy_installer.sh
#   卸载: bash mtproxy_installer.sh uninstall
#   启动: bash mtproxy_installer.sh start
#   停止: bash mtproxy_installer.sh stop
#   重启: bash mtproxy_installer.sh restart
#   状态: bash mtproxy_installer.sh status
#   绑定营销群: bash mtproxy_installer.sh bindtag <PROXY_TAG>
#

# ============================================================
# 全局变量
# ============================================================
WORK_DIR="/home/mtproxy"
PID_FILE="${WORK_DIR}/pid"
CONFIG_FILE="${WORK_DIR}/mtp_config"
SECRET_FILE="${WORK_DIR}/secret"
PROXY_SECRET_FILE="${WORK_DIR}/proxy-secret"
PROXY_MULTI_FILE="${WORK_DIR}/proxy-multi.conf"
BINARY_FILE="${WORK_DIR}/mtproto-proxy"

PROXY_SECRET_URL="https://core.telegram.org/getProxySecret"
PROXY_CONFIG_URL="https://core.telegram.org/getProxyConfig"
# 预编译二进制下载地址（sunpma/mtp 提供的版本，支持 fake-tls）
BINARY_URL="https://github.com/nicholasgasior/docker-mtproto-proxy/releases/latest/download/mtproto-proxy-linux-amd64"

DEFAULT_PORT=443
DEFAULT_MANAGE_PORT=8888
DEFAULT_DOMAIN="azure.microsoft.com"

# ============================================================
# 日志函数
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
# 检测 root 权限
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
    local ip
    ip=$(curl -sf4 https://api.ipify.org || curl -sf4 https://ifconfig.me || curl -sf4 https://icanhazip.com)
    echo "$ip"
}

# ============================================================
# 生成随机 Secret（32 位十六进制）
# ============================================================
generate_secret() {
    head -c 16 /dev/urandom | xxd -ps 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

# ============================================================
# 下载 Telegram 配置文件
# ============================================================
download_config() {
    log_info "下载 proxy-secret..."
    if ! curl -sf "$PROXY_SECRET_URL" -o "$PROXY_SECRET_FILE"; then
        log_error "proxy-secret 下载失败"
        exit 1
    fi

    log_info "下载 proxy-multi.conf..."
    if ! curl -sf "$PROXY_CONFIG_URL" -o "$PROXY_MULTI_FILE"; then
        log_error "proxy-multi.conf 下载失败"
        exit 1
    fi
}

# ============================================================
# 下载预编译二进制
# ============================================================
download_binary() {
    log_info "下载 MTProxy 二进制文件..."

    # 尝试从 sunpma/mtp 的源下载
    local arch
    arch=$(uname -m)
    local download_url=""

    case "$arch" in
        x86_64|amd64)
            download_url="https://raw.githubusercontent.com/sunpma/mtp/master/mtproto-proxy"
            ;;
        aarch64|arm64)
            download_url="https://raw.githubusercontent.com/sunpma/mtp/master/mtproto-proxy-arm64"
            ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac

    if ! curl -sfL "$download_url" -o "$BINARY_FILE"; then
        log_error "二进制文件下载失败"
        log_error "URL: $download_url"
        exit 1
    fi

    chmod +x "$BINARY_FILE"
    log_info "MTProxy 二进制文件下载完成"
}

# ============================================================
# 安装
# ============================================================
do_install() {
    check_root

    if [[ -f "$CONFIG_FILE" ]]; then
        log_warn "MTProxy 已安装，如需重新安装请先卸载: bash $0 uninstall"
        exit 1
    fi

    log_info "开始安装 MTProxy TLS..."

    # 安装依赖
    if command -v apt-get &>/dev/null; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl xxd >/dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y curl vim-common >/dev/null 2>&1
    elif command -v apk &>/dev/null; then
        apk add curl xxd >/dev/null 2>&1
    fi

    # 创建工作目录
    mkdir -p "$WORK_DIR"

    # 下载二进制和配置
    download_binary
    download_config

    # 生成 Secret
    local secret
    secret=$(generate_secret)
    echo "$secret" > "$SECRET_FILE"

    # 获取服务器 IP
    local server_ip
    server_ip=$(get_server_ip)

    if [[ -z "$server_ip" ]]; then
        log_error "无法获取服务器公网 IP"
        exit 1
    fi

    # 生成伪装域名的十六进制
    local domain_hex
    domain_hex=$(echo -n "$DEFAULT_DOMAIN" | xxd -ps 2>/dev/null || echo -n "$DEFAULT_DOMAIN" | od -An -tx1 | tr -d ' \n')

    # 写入配置文件
    cat > "$CONFIG_FILE" <<EOF
PORT=${DEFAULT_PORT}
MANAGE_PORT=${DEFAULT_MANAGE_PORT}
SECRET=${secret}
DOMAIN=${DEFAULT_DOMAIN}
DOMAIN_HEX=${domain_hex}
SERVER_IP=${server_ip}
TAG=
EOF

    # 启动服务
    do_start

    # 展示结果
    show_result
}

# ============================================================
# 启动
# ============================================================
do_start() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "MTProxy 未安装"
        exit 1
    fi

    # 检查是否已在运行
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log_warn "MTProxy 已在运行 (PID: $old_pid)"
            return 0
        fi
        rm -f "$PID_FILE"
    fi

    # 读取配置
    source "$CONFIG_FILE"

    # 构建启动参数
    local args="-u nobody -p $MANAGE_PORT -H $PORT -S $SECRET"
    args="$args --aes-pwd $PROXY_SECRET_FILE $PROXY_MULTI_FILE"
    args="$args -D $DOMAIN"
    args="$args --nat-info $(hostname -I | awk '{print $1}'):$SERVER_IP"

    if [[ -n "$TAG" ]]; then
        args="$args -P $TAG"
    fi

    # 启动
    cd "$WORK_DIR" || exit 1
    $BINARY_FILE $args &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    sleep 1

    if kill -0 "$pid" 2>/dev/null; then
        log_info "MTProxy 启动成功 (PID: $pid)"
    else
        log_error "MTProxy 启动失败"
        rm -f "$PID_FILE"
        exit 1
    fi
}

# ============================================================
# 停止
# ============================================================
do_stop() {
    if [[ ! -f "$PID_FILE" ]]; then
        log_warn "MTProxy 未在运行"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        sleep 1
        # 强制杀死子进程
        kill -9 "$pid" 2>/dev/null
        log_info "MTProxy 已停止"
    else
        log_warn "MTProxy 进程不存在"
    fi

    rm -f "$PID_FILE"
}

# ============================================================
# 重启
# ============================================================
do_restart() {
    do_stop
    sleep 1
    do_start
}

# ============================================================
# 状态
# ============================================================
do_status() {
    if [[ ! -f "$PID_FILE" ]]; then
        log_info "MTProxy 未在运行"
        return 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if kill -0 "$pid" 2>/dev/null; then
        log_info "MTProxy 运行中 (PID: $pid)"
        return 0
    else
        log_warn "MTProxy 进程不存在（PID 文件残留）"
        rm -f "$PID_FILE"
        return 1
    fi
}

# ============================================================
# 展示结果
# ============================================================
show_result() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "MTProxy 未安装"
        return 1
    fi

    source "$CONFIG_FILE"

    local domain_hex
    domain_hex=$(echo -n "$DOMAIN" | xxd -ps 2>/dev/null || echo -n "$DOMAIN" | od -An -tx1 | tr -d ' \n')

    local full_secret="dd${SECRET}${domain_hex}"

    echo ""
    echo "============================================================"
    echo "  MTProxy TLS 安装完成"
    echo "============================================================"
    echo ""
    echo "  服务器 IP:    $SERVER_IP"
    echo "  连接端口:     $PORT"
    echo "  管理端口:     $MANAGE_PORT"
    echo "  伪装域名:     $DOMAIN"
    echo ""
    echo "  ---- 密钥信息 ----"
    echo ""
    echo "  原始 Secret（给 @MTProxybot 用）:"
    echo "    $SECRET"
    echo ""
    echo "  连接 Secret（含 dd 前缀）:"
    echo "    $full_secret"
    echo ""

    if [[ -n "$TAG" ]]; then
        echo "  营销群绑定:   ✅ 已启用"
        echo "  Proxy Tag:    $TAG"
    else
        echo "  营销群绑定:   ❌ 未配置（可用 bindtag 命令绑定）"
    fi

    echo ""
    echo "  ---- 连接链接 ----"
    echo ""
    echo "  tg://proxy?server=${SERVER_IP}&port=${PORT}&secret=${full_secret}"
    echo ""
    echo "  https://t.me/proxy?server=${SERVER_IP}&port=${PORT}&secret=${full_secret}"
    echo ""
    echo "============================================================"
    echo "  管理命令:"
    echo "    启动: bash $0 start"
    echo "    停止: bash $0 stop"
    echo "    重启: bash $0 restart"
    echo "    状态: bash $0 status"
    echo "    绑定营销群: bash $0 bindtag <TAG>"
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

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "MTProxy 未安装"
        exit 1
    fi

    # 更新配置文件中的 TAG
    sed -i "s/^TAG=.*/TAG=${tag}/" "$CONFIG_FILE"

    log_info "Proxy Tag 已保存: $tag"
    log_info "正在重启服务..."

    do_restart
    show_result
}

# ============================================================
# 卸载
# ============================================================
do_uninstall() {
    check_root

    log_info "正在卸载 MTProxy..."

    do_stop

    if [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
        log_info "已删除程序目录 $WORK_DIR"
    fi

    # 清理 rc.local 中的自启动
    if [[ -f /etc/rc.local ]]; then
        sed -i '/mtproxy/d' /etc/rc.local 2>/dev/null
    fi

    echo ""
    log_info "============================================"
    log_info "  MTProxy 已完全卸载"
    log_info "============================================"
    echo ""
}

# ============================================================
# 配置开机自启
# ============================================================
setup_autostart() {
    # 使用 rc.local 方式
    if [[ ! -f /etc/rc.local ]]; then
        echo '#!/bin/bash' > /etc/rc.local
        chmod +x /etc/rc.local
    fi

    if ! grep -q "mtproxy" /etc/rc.local 2>/dev/null; then
        sed -i '/^exit 0/d' /etc/rc.local 2>/dev/null
        echo "bash ${WORK_DIR}/mtproxy_installer.sh start > /dev/null 2>&1 &" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
        log_info "已配置开机自启"
    fi
}

# ============================================================
# 入口
# ============================================================
main() {
    case "$1" in
        start)     do_start ;;
        stop)      do_stop ;;
        restart)   do_restart ;;
        status)    do_status ;;
        uninstall) do_uninstall ;;
        bindtag)   do_bindtag "$2" ;;
        info)      show_result ;;
        *)         do_install ;;
    esac
}

main "$@"
