#!/bin/bash

# ============================================
# pupmsub 安装脚本
# ============================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
bcyan='\033[1;36m'
plain='\033[0m'

NAME="sub"
BINARY_NAME="sub"
BIN_DIR="/usr/local/${BINARY_NAME}"
CFG_DIR="/etc/${BINARY_NAME}"
BIN_PATH="${BIN_DIR}/${BINARY_NAME}"
CMD_PATH="/usr/bin/${NAME}"
CMD_SUB="/usr/bin/${BINARY_NAME}"
SERVICE_NAME="sub"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# 检测 root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用 root 用户运行此脚本！\n" && exit 1

# 检测架构
arch=$(arch)
case ${arch} in
    x86_64)  arch="64" ;;
    aarch64) arch="arm64-v8a" ;;
    s390x)   arch="s390x" ;;
    *)       arch="64" ;;
esac

# 颜色输出
info()    { echo -e "${green}[INFO]${plain} $*"; }
warn()    { echo -e "${yellow}[WARN]${plain} $*"; }
error()   { echo -e "${red}[ERROR]${plain} $*"; }
success() { echo -e "${green}[OK]${plain} $*"; }

# ============================================
# 系统检测
# ============================================
detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        os="centos"
    elif cat /etc/issue | grep -Eqi "debian"; then
        os="debian"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        os="ubuntu"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        os="centos"
    elif cat /proc/version | grep -Eqi "debian"; then
        os="debian"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        os="ubuntu"
    else
        error "不支持的操作系统"
        exit 1
    fi
    info "检测到系统: ${os}"
}

# ============================================
# 安装基础依赖
# ============================================
install_base() {
    info "安装基础依赖..."
    if [[ ${os} == "centos" ]]; then
        yum install epel-release -y -q
        yum install wget curl unzip tar crontabs socat jq -y -q
    else
        apt-get update -y -qq
        apt-get install wget curl unzip tar cron socat jq -y -qq
    fi
    success "基础依赖安装完成"
}

# ============================================
# 下载 pupmsub 二进制
# ============================================
download_binary() {
    local dl_url="https://github.com/pupmme/pupmsub/releases/download/v1.0.1/linux-${arch}.zip"
    info "下载 pupmsub v1.0.1 (${arch})..."
    mkdir -p "${BIN_DIR}"
    if ! curl -L -f --connect-timeout 60 --retry 3 -o "${BIN_DIR}/sub.zip" "${dl_url}"; then
        error "二进制下载失败，请检查网络（需访问 GitHub）"
        info "手动下载: ${dl_url}"
        exit 1
    fi
    unzip -o "${BIN_DIR}/sub.zip" -d "${BIN_DIR}/"
    rm -f "${BIN_DIR}/sub.zip"
    chmod +x "${BIN_DIR}/sub"
    success "二进制安装完成 (${BIN_DIR}/sub)"
}

# ============================================
# 下载配置文件模板
# ============================================
download_configs() {
    mkdir -p "${CFG_DIR}"
    echo -e "${green}正在下载 GeoIP/GeoSite 数据库...${plain}"
    curl -fsL --connect-timeout 60 \
        -o "${CFG_DIR}/geoip.dat" \
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
        || echo -e "${yellow}geoip.dat 下载失败${plain}"
    curl -fsL --connect-timeout 60 \
        -o "${CFG_DIR}/geosite.dat" \
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
        || echo -e "${yellow}geosite.dat 下载失败${plain}"
    # 生成极简 config.json（占位，initconfig 会覆盖）
    cat > "${CFG_DIR}/config.json" <<'CONFIGEOF'
{
    "Log": { "Level": "info" },
    "Nodes": []
}
CONFIGEOF
    success "配置文件初始化完成"
}

# ============================================
# 写入 systemd service
# ============================================
write_service() {
    cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=sub Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=${CFG_DIR}
ExecStart=${BIN_DIR}/sub server -c ${CFG_DIR}/config.yml
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    info "systemd service 已写入"
}

# ============================================
# 安装管理脚本（菜单）
# ============================================
install_menu_script() {
    info "安装管理脚本..."
    local menu_url="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/sub.sh"
    curl -fsL --connect-timeout 15 -o "${CMD_PATH}" "${menu_url}"
    chmod +x "${CMD_PATH}"
    success "管理命令已安装: sub"
}

# ============================================
# 首次安装交互配置
# ============================================
init_config() {
    echo ""
    echo -e "${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${bcyan}     pupmsub 首次安装 - 节点配置向导${plain}"
    echo -e "${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo ""

    # 面板地址
    read -rp "请输入面板网址 (例如 https://s.pupm.us): " panel_url
    [[ -z ${panel_url} ]] && { error "面板地址不能为空"; exit 1; }

    # API Key
    read -rp "请输入 API Key: " api_key
    [[ -z ${api_key} ]] && { error "API Key 不能为空"; exit 1; }

    # 是否固定面板地址
    fix_panel="n"
    read -rp "是否固定面板地址和 Key 到配置？(y/n，默认 n): " fix_panel
    [[ -z ${fix_panel} ]] && fix_panel="n"

    # Node ID
    echo ""
    echo -e "${yellow}请输入节点 Node ID（支持多个，逗号分隔）:${plain}"
    read -rp "例如: 1,2,3 或单个 ID: " node_ids
    [[ -z ${node_ids} ]] && { error "Node ID 不能为空"; exit 1; }


    # 生成 config.json（填入面板地址和 Key）
    cat > "${CFG_DIR}/config.json" <<EOF
{
    "Log": { "Level": "info" },
    "Cores": [
        {
            "Type": "sing",
            "SingConfig": {
                "Log": { "Level": "info" },
                "NTP": { "Enable": false },
                "OriginalPath": "${CFG_DIR}/singbox.json"
            }
        }
    ],
    "Nodes": [
        {
            "NodeID": 1,
            "NodeType": "vless",
            "ApiHost": "${panel_url}",
            "ApiKey": "${api_key}",
            "EnableUPnP": false,
            "EnableTFO": true,
            "EnableMux": true,
            "Timeout": 4,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0"
        }
    ]
}
EOF


# ============================================
# 启动服务
# ============================================
start_service() {
    systemctl enable ${BINARY_NAME}
    systemctl stop ${BINARY_NAME} 2>/dev/null || true
    sleep 1
    if systemctl start ${BINARY_NAME}; then
        sleep 2
        if systemctl is-active --quiet ${BINARY_NAME}; then
            success "pupmsub 已启动并设置开机自启"
            return 0
        fi
    fi
    warn "pupmsub 可能启动失败，请稍后使用 ${green}sub log${plain} 查看日志"
    return 1
}

# ============================================
# 安装主流程
# ============================================
do_install() {
    detect_os
    install_base
    download_binary
    download_configs
    write_service
    install_menu_script
    init_config
    start_service

    echo ""
    echo -e "${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${green}  sub 安装完成！${plain}"
    echo -e "${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo ""
    echo -e "  ${green}管理命令: sub${plain}"
    echo -e "  ${green}首次配置: sub init${plain}"
    echo ""
    echo -e "  sub              - 管理菜单"
    echo -e "  sub start        - 启动"
    echo -e "  sub log          - 日志"
    echo ""
}

do_install
