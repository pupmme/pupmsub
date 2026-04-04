#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}" && exit 1
fi

# check arch
arch=$(arch)
if [[ ${arch} == "x86_64" ]]; then
    arch="64"
elif [[ ${arch} == "aarch64" ]]; then
    arch="arm64-v8a"
elif [[ ${arch} == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
fi

before_show_menu() {
    echo ""
    echo -e "${green}按回车返回主菜单${plain}"
    read -s
}

confirm() {
    if [[ $# -gt 1 ]]; then
        echo && read -rp "$1 [默认 $2]: " yn
        [[ -z ${yn} ]] && yn=$2
    else
        read -rp "$1 [y/n]: " -y yn
    fi
    [[ ! ${yn} == [yY] ]] && return 1 || return 0
}

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
        yum install ca-certificates wget -y
        update-ca-trust force-enable
    else
        apt-get update -y
        apt-get install wget curl unzip tar cron socat -y
        apt-get install ca-certificates wget -y
        update-ca-certificates
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/V2bX.service ]]; then
        return 2
    fi
    temp=$(systemctl status V2bX | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_install() {
    if [[ ! -f /etc/systemd/system/V2bX.service ]]; then
        echo -e "${red}V2bX 未安装，请先安装！${plain}"
        return 1
    fi
    return 0
}

check_uninstall() {
    if [[ -f /etc/systemd/system/V2bX.service ]]; then
        echo -e "${red}V2bX 已安装，请先卸载！${plain}"
        return 1
    fi
    return 0
}

check_enabled() {
    systemctl is-enabled V2bX.service >/dev/null 2>&1 && return 0 || return 1
}

install_V2bX() {
    if [[ -e /usr/local/V2bX/ ]]; then
        rm -rf /usr/local/V2bX/
    fi

    mkdir /usr/local/V2bX/ -p
    cd /usr/local/V2bX/

    base_url="https://github.com/pupmme/pupmsub/releases/download/v1.0.0"
    zip_name="V2bX-linux-${arch}.zip"
    dl_url="${base_url}/${zip_name}"

    echo -e "开始下载 pupmsub v1.0.0..."
    curl -L -f --connect-timeout 30 --retry 3 \
        -o /usr/local/V2bX/V2bX-linux.zip \
        "${dl_url}"
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载失败，请确保服务器能访问 GitHub${plain}"
        echo "尝试手动下载: ${dl_url}"
        exit 1
    fi

    unzip -o V2bX-linux.zip
    rm -f V2bX-linux.zip
    chmod +x V2bX

    mkdir -p /etc/V2bX/

    # 下载 systemd service
    curl -fsL --connect-timeout 15 -o /etc/systemd/system/V2bX.service \
        "https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/V2bX.service"
    systemctl daemon-reload
    systemctl stop V2bX 2>/dev/null || true
    systemctl enable V2bX

    echo -e "${green}pupmsub v1.0.0 安装完成，已设置开机自启${plain}"

    # 下载配置文件
    cfg_base="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/config"
    curl -fsL --connect-timeout 15 -o /etc/V2bX/config.yml      "${cfg_base}/config.yml"
    curl -fsL --connect-timeout 15 -o /etc/V2bX/dns.json        "${cfg_base}/dns.json"
    curl -fsL --connect-timeout 15 -o /etc/V2bX/route.json      "${cfg_base}/route.json"
    curl -fsL --connect-timeout 15 -o /etc/V2bX/custom_inbound.json  "${cfg_base}/custom_inbound.json"
    curl -fsL --connect-timeout 15 -o /etc/V2bX/custom_outbound.json "${cfg_base}/custom_outbound.json"

    # 下载 geo 文件
    curl -fsL --connect-timeout 30 \
        -o /etc/V2bX/geoip.dat \
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
    curl -fsL --connect-timeout 30 \
        -o /etc/V2bX/geosite.dat \
        "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

    # 安装管理脚本
    curl -fsL --connect-timeout 15 -o /usr/bin/V2bX \
        "https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/V2bX.sh"
    chmod +x /usr/bin/V2bX
    if [[ ! -L /usr/bin/v2bx ]]; then
        ln -s /usr/bin/V2bX /usr/bin/v2bx
    fi

    if [[ ! -f /etc/V2bX/config.json ]] && [[ ! -f /etc/V2bX/config.yml ]]; then
        echo ""
        echo -e "${yellow}全新安装，请先参看教程配置必要内容${plain}"
        echo -e "配置文档: https://github.com/pupmme/pupmsub"
        first_install=true
    else
        systemctl start V2bX
        sleep 2
        check_status
        echo ""
        if [[ $? == 0 ]]; then
            echo -e "${green}V2bX 重启成功${plain}"
        else
            echo -e "${red}V2bX 可能启动失败，请稍后使用 ${green}V2bX log${red} 查看日志${plain}"
        fi
    fi

    echo ""
    echo "=========================================="
    echo " pupmsub 管理命令:"
    echo "  V2bX              - 显示管理菜单"
    echo "  V2bX start        - 启动"
    echo "  V2bX stop         - 停止"
    echo "  V2bX restart      - 重启"
    echo "  V2bX status       - 状态"
    echo "  V2bX log          - 日志"
    echo "  V2bX enable       - 开机自启"
    echo "  V2bX disable      - 取消自启"
    echo "=========================================="
}

start() {
    systemctl start V2bX
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 启动成功${plain}"
    else
        echo -e "${red}V2bX 启动失败，请查看日志${plain}"
    fi
}

stop() {
    systemctl stop V2bX
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 已停止${plain}"
    else
        echo -e "${red}V2bX 停止失败${plain}"
    fi
}

restart() {
    systemctl restart V2bX
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 重启成功${plain}"
    else
        echo -e "${red}V2bX 重启失败，请查看日志${plain}"
    fi
}

show_log() {
    journalctl -u V2bX -o cat --no-pager -n 50
}

show_V2bX_version() {
    /usr/local/V2bX/V2bX version
}

enable() {
    systemctl enable V2bX
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 已设置开机自启${plain}"
    else
        echo -e "${red}设置开机自启失败${plain}"
    fi
}

disable() {
    systemctl disable V2bX
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 已取消开机自启${plain}"
    else
        echo -e "${red}取消开机自启失败${plain}"
    fi
}

update() {
    bash <(curl -Ls https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/install.sh)
}

uninstall() {
    confirm "确定要卸载 pupmsub 吗?" "n"
    if [[ $? != 0 ]]; then
        show_menu
        return 0
    fi
    systemctl stop V2bX
    systemctl disable V2bX
    rm -f /etc/systemd/system/V2bX.service
    systemctl daemon-reload
    systemctl reset-failed
    rm -rf /etc/V2bX/
    rm -rf /usr/local/V2bX/
    rm -f /usr/bin/V2bX
    rm -f /usr/bin/v2bx
    echo ""
    echo -e "${green}卸载完成${plain}"
}

show_menu() {
    echo -e "
  ${green}pupmsub 后端管理脚本${plain}
--- https://github.com/pupmme/pupmsub ---
  ${green}0.${plain} 修改配置
————————————————
  ${green}1.${plain} 安装 pupmsub
  ${green}2.${plain} 更新 pupmsub
  ${green}3.${plain} 卸载 pupmsub
————————————————
  ${green}4.${plain} 启动
  ${green}5.${plain} 停止
  ${green}6.${plain} 重启
  ${green}7.${plain} 查看状态
  ${green}8.${plain} 查看日志
————————————————
  ${green}9.${plain} 设置开机自启
  ${green}10.${plain} 取消开机自启
————————————————
  ${green}11.${plain} 一键安装 bbr
  ${green}12.${plain} 查看版本
  ${green}13.${plain} 生成 X25519 密钥
  ${green}14.${plain} 升级管理脚本
  ${green}15.${plain} 生成配置文件
  ${green}16.${plain} 放行所有端口
————————————————
  ${green}17.${plain} 退出
"
    show_status
    echo && read -rp "请输入选择 [0-17]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && show_status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) bash <(curl -sL https://raw.githubusercontent.com/tc-holyun/Google-BBR/master/bbr.sh) ;;
        12) check_install && show_V2bX_version ;;
        13) check_install && /usr/local/V2bX/V2bX x25519 ;;
        14) update ;;
        15) /usr/local/V2bX/V2bX generate ;;
        16) iptables -F && iptables -P INPUT ACCEPT && iptables -P FORWARD ACCEPT && iptables -P OUTPUT ACCEPT && echo -e "${green}已放行所有端口${plain}" ;;
        17) exit 0 ;;
        *) echo -e "${red}请输入正确的数字 [0-17]${plain}" ;;
    esac

    [[ ${num} != "17" ]] && before_show_menu && show_menu
}

config() {
    echo "修改配置后会自动尝试重启"
    nano /etc/V2bX/config.yml
    sleep 2
    check_status
    case $? in
        0)
            echo -e "V2bX状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到未启动或启动失败，是否查看日志？[Y/n]" && read -rp "(默认: y): " yn
            [[ -z ${yn} ]] && yn="y"
            [[ ${yn} == [Yy] ]] && show_log
            ;;
        2)
            echo -e "V2bX状态: ${red}未安装${plain}"
    esac
}

install() {
    install_base
    install_V2bX
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "V2bX状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "V2bX状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "V2bX状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

before_show_menu
show_menu
