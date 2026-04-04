#!/bin/bash

# ============================================
# pupmsub/sub 安装脚本
# ============================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
bcyan='\033[1;36m'
plain='\033[0m'

NAME="sub"
BINARY_NAME="sub"
BIN_DIR="/usr/local/${BINARY_NAME}"
CFG_DIR="/etc/${BINARY_NAME}"
BIN_PATH="${BIN_DIR}/${BINARY_NAME}"
CMD_PATH="/usr/bin/${NAME}"
SERVICE_NAME="sub"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
VERSION="v1.0.1"
GIT_RAW="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script"

error() { echo -e "${red}错误: ${plain}$*"; }
info()  { echo -e "${blue}[信息] ${plain}$*"; }
warn()  { echo -e "${yellow}[警告] ${plain}$*"; }
success(){ echo -e "${green}[成功] ${plain}$*"; }

# ============================================
# OS 检测
# ============================================
detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue 2>/dev/null | grep -Eqi "debian"; then
        release="debian"
    elif cat /etc/issue 2>/dev/null | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue 2>/dev/null | grep -Eqi "centos|red hat|rocky|alma"; then
        release="centos"
    elif [[ -f /etc/alpine-release ]]; then
        release="alpine"
    else
        error "不支持的操作系统"
        exit 1
    fi
    info "检测系统: ${release}"
}

# ============================================
# 基础依赖
# ============================================
install_base() {
    if [[ ${release} == "centos" ]]; then
        yum install wget curl unzip tar crontabs socat jq -y -q
    elif [[ ${release} == "debian" || ${release} == "ubuntu" ]]; then
        apt-get install wget curl unzip tar cron socat jq -y -qq
    elif [[ ${release} == "alpine" ]]; then
        apk add bash wget curl unzip tar cronie openrc jq
    fi
    success "基础依赖安装完成"
}

# ============================================
# 下载二进制
# ============================================
get_architecture() {
    local arch=$(uname -m)
    case ${arch} in
        x86_64)  arch="64" ;;
        aarch64) arch="arm64-v8a" ;;
        s390x)   arch="s390x" ;;
        *)       arch="64" ;;
    esac
    echo ${arch}
}

download_binary() {
    local arch=$(get_architecture)
    local dl_url="https://github.com/pupmme/pupmsub/releases/download/${VERSION}/linux-${arch}.zip"
    mkdir -p "${BIN_DIR}"
    info "下载 pupmsub ${VERSION} (${arch})..."
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
# 下载配置文件和规则
# ============================================
download_configs() {
    mkdir -p "${CFG_DIR}"
    info "下载 GeoIP/GeoSite 规则数据库..."
    curl -fsL --connect-timeout 60 -o "${CFG_DIR}/geoip.dat" \
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
        || warn "geoip.dat 下载失败"
    curl -fsL --connect-timeout 60 -o "${CFG_DIR}/geosite.dat" \
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
        || warn "geosite.dat 下载失败"

    # 写入极简 config.json（占位，init_config 会覆盖）
    cat > "${CFG_DIR}/config.json" <<'HEREDOC'
{
    "Log": { "Level": "info" },
    "Nodes": []
}
HEREDOC
    success "配置文件初始化完成"
}

# ============================================
# 交互式初始化配置（首次安装向导）
# ============================================
init_config() {
    echo ""
    echo -e "${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${bcyan}     sub 首次安装 - 节点配置向导${plain}"
    echo -e "${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo ""

    local panel_url=""
    local api_key=""
    local node_ids=""

    read -rp "请输入面板网址 (例如 https://s.pupm.us): " panel_url
    [[ -z "${panel_url}" ]] && { error "面板地址不能为空"; exit 1; }

    read -rp "请输入 API Key: " api_key
    [[ -z "${api_key}" ]] && { error "API Key 不能为空"; exit 1; }

    echo ""
    echo -e "${yellow}请输入节点 Node ID（支持多个，逗号分隔）:${plain}"
    read -rp "例如: 1,2,3 或单个 ID: " node_ids
    [[ -z "${node_ids}" ]] && { error "Node ID 不能为空"; exit 1; }

    # 生成 singbox.json 模板（占位，用户后续自行编辑入站协议）
    cat > "${CFG_DIR}/singbox.json" <<'SINGEOF'
{
  "log": { "level": "info" },
  "dns": {
    "servers": [
      { "tag": "google", "address": "tls://8.8.8.8", "detour": "direct" },
      { "tag": "block",  "address": "rcode://success" }
    ],
    "rules": [
      { "geosite": ["category-ads-all"], "server": "block" },
      { "geosite": ["cn"], "server": "google" }
    ]
  },
  "inbounds": [
    { "tag": "api", "type": "mixed", "listen": "127.0.0.1", "listen_port": 65535, "users": [] }
  ],
  "outbounds": [
    { "tag": "direct", "type": "direct" },
    { "tag": "block",  "type": "block" }
  ],
  "route": {
    "geosite": [
      { "tag": "cn", "path": "/etc/sub/geosite.dat" },
      { "tag": "category-ads-all", "path": "/etc/sub/geosite.dat" }
    ],
    "geoip": [
      { "tag": "cn", "path": "/etc/sub/geoip.dat" }
    ],
    "rules": [
      { "geosite": ["category-ads-all"], "outbound": "block" },
      { "geosite": ["cn"], "outbound": "direct" },
      { "geoip": ["cn"], "outbound": "direct" }
    ]
  }
}
SINGEOF

    # 生成 config.json（写入面板信息）
    # 用 Python 避免 shell 字符串转义问题
    python3 - "${panel_url}" "${api_key}" "${node_ids}" "${CFG_DIR}" <<'PYEOF'
import sys, json
panel_url = sys.argv[1]
api_key = sys.argv[2]
node_ids_str = sys.argv[3]
cfg_dir = sys.argv[4]

node_ids = [n.strip() for n in node_ids_str.split(',') if n.strip()]
nodes = []
for nid in node_ids:
    nodes.append({
        "NodeID": int(nid),
        "NodeType": "vless",
        "ApiHost": panel_url,
        "ApiKey": api_key,
        "EnableUPnP": False,
        "EnableTFO": True,
        "EnableMux": True,
        "Timeout": 4,
        "ListenIP": "0.0.0.0",
        "SendIP": "0.0.0.0"
    })

config = {
    "Log": { "Level": "info" },
    "Cores": [
        {
            "Type": "sing",
            "SingConfig": {
                "Log": { "Level": "info" },
                "NTP": { "Enable": False },
                "OriginalPath": cfg_dir + "/singbox.json"
            }
        }
    ],
    "Nodes": nodes
}

with open(cfg_dir + "/config.json", "w") as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
print("OK")
PYEOF

    echo ""
    success "配置文件已生成"
    info "配置文件位置:"
    echo "  /etc/sub/config.json    ← 面板节点配置"
    echo "  /etc/sub/singbox.json   ← sing-box 原生配置（需编辑入站）"
    echo ""
    echo -e "${yellow}请编辑 /etc/sub/singbox.json 添加入站协议${plain}"
}

# ============================================
# 写入 systemd service
# ============================================
write_service() {
    cat > "${SERVICE_PATH}" <<'SVCEOF'
[Unit]
Description=sub Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=/etc/sub
ExecStart=/usr/local/sub/sub server -c /etc/sub/config.json
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    success "systemd service 已写入"
}

# ============================================
# 安装管理脚本
# ============================================
install_menu_script() {
    info "安装管理脚本..."
    curl -fsL --connect-timeout 15 -o "${CMD_PATH}" "${GIT_RAW}/sub.sh"
    chmod +x "${CMD_PATH}"
    success "管理命令已安装: sub"
}

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
            success "sub 已启动并设置开机自启"
            return 0
        fi
    fi
    warn "sub 可能启动失败，请稍后使用 sub log 查看日志"
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
    echo -e "${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${green}  sub 安装完成！${plain}"
    echo -e "${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo ""
    echo -e "  ${green}管理命令: sub${plain}"
    echo -e "  ${green}配置文件: /etc/sub/config.json${plain}"
    echo ""
    echo -e "  ${yellow}运行 sub 进入管理菜单${plain}"
    echo ""
}

do_install
