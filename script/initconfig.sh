#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

BINARY_NAME="sub"
CFG_DIR="/etc/${BINARY_NAME}"

[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行！\n" && exit 1

echo -e "\n${yellow}============================================${plain}"
echo -e "${yellow}  V2bX 配置文件生成向导${plain}"
echo -e "${yellow}============================================${plain}"
echo -e "\n${red}注意：${plain}"
echo -e "${red}1. 该功能目前处于测试阶段${plain}"
echo -e "${red}2. 生成的配置会保存到 /etc/sub/config.json${plain}"
echo -e "${red}3. 原配置会备份为 config.json.bak${plain}"
echo ""
read -rp "确认继续？(y/n，默认 n): " confirm
[[ "${confirm}" =~ ^[Nn]$|^$ ]] && exit 0

# API 信息
while true; do
    read -rp "请输入机场面板网址（例如 https://s.pupm.us）: " ApiHost
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
    echo -e "\n${green}=== 节点 ${idx} ===${plain}"
    while true; do
        read -rp "  Node ID（正整数）: " nid
        [[ "${nid}" =~ ^[0-9]+$ ]] && break
        echo -e "  ${red}错误：请输入正确的数字${plain}"
    done
    echo -e "  ${yellow}传输协议：${plain}"
    echo -e "  ${green}1${plain}. Shadowsocks  ${green}2${plain}. Vless  ${green}3${plain}. Vmess"
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
    read -rp "继续添加节点？（回车继续，输入 n/no 退出）: " again
    [[ "${again}" =~ ^[Nn][Oo]?$ ]] && break
    add_node
done

# 备份
[[ -f "${CFG_DIR}/config.json" ]] && \
    cp "${CFG_DIR}/config.json" "${CFG_DIR}/config.json.bak"

# 生成 nodes JSON 片段
nodes_json=""
for ((i=0; i<${#NODE_IDS[@]}; i++)); do
    comma=","
    [[ $i -eq $((${#NODE_IDS[@]}-1)) ]] && comma=""
    nodes_json+="{
        \"NodeID\": ${NODE_IDS[$i]},
        \"NodeType\": \"${NODE_TYPES[$i]}\",
        \"ApiHost\": \"${ApiHost}\",
        \"ApiKey\": \"${ApiKey}\",
        \"EnableUPnP\": false,
        \"EnableTFO\": true,
        \"EnableMux\": true,
        \"Timeout\": 4,
        \"ListenIP\": \"0.0.0.0\",
        \"SendIP\": \"0.0.0.0\"
    }${comma}
    "
done

# 写入 config.json
cat > "${CFG_DIR}/config.json" <<EOF
{
    "Log": {
        "Level": "info",
        "Output": ""
    },
    "Cores": [
        {
            "Type": "sing",
            "LogConfig": {
                "Disable": false,
                "Level": "info",
                "Output": "/var/log/${BINARY_NAME}.log",
                "Timestamp": true
            },
            "SingConfig": {
                "Log": {
                    "Disable": false,
                    "Level": "info",
                    "Output": "/var/log/${BINARY_NAME}.log",
                    "Timestamp": true
                },
                "NTP": {
                    "Enable": false,
                    "Server": "time.apple.com",
                    "ServerPort": 0
                },
                "DnsConfigPath": "${CFG_DIR}/dns.json",
                "OriginalPath": ""
            },
            "SingOptions": {
                "EnableProxyProtocol": false,
                "EnableTFO": true,
                "SniffEnabled": true,
                "SniffOverrideDestination": true,
                "EnableDNS": false,
                "DomainStrategy": "IPIfNonMatch"
            }
        }
    ],
    "Nodes": [
${nodes_json}    ]
}
EOF

echo ""
echo -e "${green}配置文件生成完成，正在重启服务${plain}"
systemctl restart ${BINARY_NAME}
sleep 2
if systemctl is-active --quiet ${BINARY_NAME}; then
    echo -e "${green}V2bX 重启成功，请使用 sub log 查看日志${plain}"
else
    echo -e "${red}V2bX 重启失败，请使用 sub log 查看日志${plain}"
fi
