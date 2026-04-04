#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

BINARY_NAME="sub"
CFG_DIR="/etc/${BINARY_NAME}"

# 自动 sudo
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

echo ""
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${blue}        ${green}sub 配置文件生成向导${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo ""

# API 信息
while true; do
    read -rp "请输入面板网址（例如 https://s.pupm.us）: " ApiHost
    [[ -n "${ApiHost}" ]] && break
    echo -e "  ${red}面板地址不能为空${plain}"
done

while true; do
    read -rp "请输入面板对接 API Key: " ApiKey
    [[ -n "${ApiKey}" ]] && break
    echo -e "  ${red}API Key 不能为空${plain}"
done

# 节点列表
declare -a NODE_IDS=()
declare -a NODE_TYPES=()

add_node() {
    local idx=$((${#NODE_IDS[@]}+1))
    echo ""
    echo -e "${yellow}--- 节点 ${idx} ---${plain}"
    while true; do
        read -rp "  Node ID: " nid
        [[ "${nid}" =~ ^[0-9]+$ ]] && break
        echo -e "  ${red}错误：请输入正整数${plain}"
    done
    echo -e "  ${yellow}传输协议：${plain}"
    echo -e "  ${green}1${plain}. Shadowsocks  ${green}2${plain}. VLESS  ${green}3${plain}. VMess"
    echo -e "  ${green}4${plain}. Hysteria     ${green}5${plain}. Hysteria2  ${green}6${plain}. Tuic  ${green}7${plain}. Trojan"
    read -rp "  选择 [1-7，默认 2]: " ntype
    case "${ntype}" in
        1) ntype="shadowsocks" ;;
        3) ntype="vmess" ;;
        4) ntype="hysteria" ;;
        5) ntype="hysteria2" ;;
        6) ntype="tuic" ;;
        7) ntype="trojan" ;;
        *) ntype="vless" ;;
    esac
    NODE_IDS+=("${nid}")
    NODE_TYPES+=("${ntype}")
}

add_node
while true; do
    read -rp "继续添加节点？（回车继续，输入 n 退出）: " again
    [[ "${again}" =~ ^[Nn]$ ]] && break
    add_node
done

mkdir -p "${CFG_DIR}"

# 备份旧配置
[[ -f "${CFG_DIR}/config.json" ]] && cp "${CFG_DIR}/config.json" "${CFG_DIR}/config.json.bak"
[[ -f "${CFG_DIR}/singbox.json" ]] && cp "${CFG_DIR}/singbox.json" "${CFG_DIR}/singbox.json.bak"

# =============================================
# 生成 config.json（Cores 指向原生 singbox.json）
# =============================================
cat > "${CFG_DIR}/config.json" <<EOF
{
    "Log": {
        "Level": "info"
    },
    "Cores": [
        {
            "Type": "sing",
            "SingConfig": {
                "Log": {
                    "Level": "info"
                },
                "NTP": {
                    "Enable": false
                },
                "OriginalPath": "${CFG_DIR}/singbox.json"
            }
        }
    ],
    "Nodes": [
EOF

for ((i=0; i<${#NODE_IDS[@]}; i++)); do
    comma=","
    [[ $i -eq $((${#NODE_IDS[@]}-1)) ]] && comma=""
    cat >> "${CFG_DIR}/config.json" <<EOF
        {
            "NodeID": ${NODE_IDS[$i]},
            "NodeType": "${NODE_TYPES[$i]}",
            "ApiHost": "${ApiHost}",
            "ApiKey": "${ApiKey}",
            "EnableUPnP": false,
            "EnableTFO": true,
            "EnableMux": true,
            "Timeout": 4,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0"
        }${comma}
EOF
done

cat >> "${CFG_DIR}/config.json" <<EOF
    ]
}
EOF

# =============================================
# 生成原生 sing-box 配置（/etc/sub/singbox.json）
# =============================================
cat > "${CFG_DIR}/singbox.json" <<'SINGEOF'
{
  "log": {
    "level": "info"
  },
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8",
        "detour": "direct"
      },
      {
        "tag": "block",
        "address": "rcode://success"
      }
    ],
    "rules": [
      {
        "geosite": ["category-ads-all"],
        "server": "block"
      },
      {
        "geosite": ["cn"],
        "server": "google"
      }
    ]
  },
  "inbounds": [
    {
      "tag": "api",
      "type": "mixed",
      "listen": "127.0.0.1",
      "listen_port": 65535,
      "users": []
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct"
    },
    {
      "tag": "block",
      "type": "block"
    }
  ],
  "route": {
    "geosite": [
      {
        "tag": "cn",
        "path": "/etc/sub/geosite.dat"
      },
      {
        "tag": "category-ads-all",
        "path": "/etc/sub/geosite.dat"
      }
    ],
    "geoip": [
      {
        "tag": "cn",
        "path": "/etc/sub/geoip.dat"
      }
    ],
    "rules": [
      {
        "geosite": ["category-ads-all"],
        "outbound": "block"
      },
      {
        "geosite": ["cn"],
        "outbound": "direct"
      },
      {
        "geoip": ["cn"],
        "outbound": "direct"
      }
    ]
  }
}
SINGEOF

echo ""
echo -e "${green}配置文件已生成：${plain}"
echo "  /etc/sub/config.json    ← V2bX 封装（勿手动修改）"
echo "  /etc/sub/singbox.json   ← 原生 sing-box 配置"
echo ""
echo -e "${yellow}请编辑 /etc/sub/singbox.json 添加入站/出站节点信息${plain}"
echo ""
echo -n "重启服务？(Y/n): "
read -r yn
[[ "${yn}" =~ ^[Nn]$ ]] && exit 0

systemctl restart ${BINARY_NAME}
sleep 2
if systemctl is-active --quiet ${BINARY_NAME}; then
    echo -e "${green}sub 重启成功${plain}"
else
    echo -e "${red}sub 启动失败，请使用 sub log 查看日志${plain}"
fi
