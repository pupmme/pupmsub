#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

NAME="sub"
BINARY_NAME="sub"
BIN_DIR="/usr/local/${BINARY_NAME}"
CFG_DIR="/etc/${BINARY_NAME}"
BIN_PATH="${BIN_DIR}/${BINARY_NAME}"
SERVICE_PATH="/etc/systemd/system/${BINARY_NAME}.service"
SHELL_URL="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/sub.sh"
INSTALL_URL="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/install.sh"

confirm() {
    if [[ $# -gt 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        [[ -z ${temp} ]] && temp=$2
    else
        echo && read -rp "$1 [y/n]: " temp
    fi
    [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]
}

confirm_restart() {
    confirm "是否重启V2bX" "y"
    [[ $? == 0 ]] && restart || show_menu
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f "${SERVICE_PATH}" ]]; then
        return 2
    fi
    temp=$(systemctl status ${BINARY_NAME} | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    [[ x"${temp}" == x"running" ]] && return 0 || return 1
}

check_enabled() {
    systemctl is-enabled ${BINARY_NAME} >/dev/null 2>&1
}

check_install() {
    check_status
    case $? in
        2)  echo "" && echo -e "${red}请先安装V2bX${plain}"
            [[ $# == 0 ]] && before_show_menu
            return 1
            ;;
    esac
    return 0
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo "" && echo -e "${red}V2bX已安装，请不要重复安装${plain}"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi
    return 0
}

show_status() {
    check_status
    case $? in
        0)  echo -e "V2bX状态: ${green}已运行${plain}"
            check_enabled && echo -e "是否开机自启: ${green}是${plain}" \
                          || echo -e "是否开机自启: ${red}否${plain}"
            ;;
        1)  echo -e "V2bX状态: ${yellow}未运行${plain}"
            check_enabled && echo -e "是否开机自启: ${green}是${plain}" \
                          || echo -e "是否开机自启: ${red}否${plain}"
            ;;
        2)  echo -e "V2bX状态: ${red}未安装${plain}"
    esac
}

install() {
    bash <(curl -Ls ${INSTALL_URL})
    [[ $? == 0 ]] && start || before_show_menu
}

update() {
    echo ""
    if [[ $# == 0 ]]; then
        echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls ${INSTALL_URL}) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 V2bX，请使用 sub log 查看运行日志${plain}"
        exit
    fi
    [[ $# == 0 ]] && before_show_menu
}

config() {
    echo "V2bX在修改配置后会自动尝试重启"
    vi ${CFG_DIR}/config.yml
    sleep 2
    check_status
    case $? in
        0)  echo -e "V2bX状态: ${green}已运行${plain}" ;;
        1)  echo -e "检测到您未启动V2bX或V2bX自动重启失败，是否查看日志？[Y/n]"; echo
            read -e -rp "(默认: y):" yn; [[ -z ${yn} ]] && yn="y"
            [[ ${yn} == [Yy] ]] && show_log ;;
        2)  echo -e "V2bX状态: ${red}未安装${plain}"
    esac
}

uninstall() {
    confirm "确定要卸载 V2bX 吗?" "n"
    [[ $? != 0 ]] && { [[ $# == 0 ]] && show_menu || return 0; }
    systemctl stop ${BINARY_NAME}
    systemctl disable ${BINARY_NAME}
    rm -f ${SERVICE_PATH}
    systemctl daemon-reload
    systemctl reset-failed
    rm -rf /etc/V2bX
    rm -rf /usr/local/V2bX
    rm -rf ${CFG_DIR}
    rm -rf ${BIN_DIR}
    rm -f /usr/bin/${NAME}
    rm -f /usr/bin/${BINARY_NAME}
    rm -f /usr/bin/V2bX
    echo ""
    echo -e "卸载成功，删除脚本: ${green}rm /usr/bin/${NAME} -f${plain}"
    echo ""
    [[ $# == 0 ]] && before_show_menu
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo "" && echo -e "${green}V2bX已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        systemctl start ${BINARY_NAME}
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}V2bX 启动成功，请使用 sub log 查看运行日志${plain}"
        else
            echo -e "${red}V2bX可能启动失败，请稍后使用 sub log 查看日志信息${plain}"
        fi
    fi
    [[ $# == 0 ]] && before_show_menu
}

stop() {
    systemctl stop ${BINARY_NAME}
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}V2bX 停止成功${plain}"
    else
        echo -e "${red}V2bX停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi
    [[ $# == 0 ]] && before_show_menu
}

restart() {
    systemctl restart ${BINARY_NAME}
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 重启成功，请使用 sub log 查看运行日志${plain}"
    else
        echo -e "${red}V2bX可能启动失败，请稍后使用 sub log 查看日志信息${plain}"
    fi
    [[ $# == 0 ]] && before_show_menu
}

status() {
    systemctl status ${BINARY_NAME} --no-pager -l
    [[ $# == 0 ]] && before_show_menu
}

enable() {
    systemctl enable ${BINARY_NAME}
    [[ $? == 0 ]] && echo -e "${green}V2bX 设置开机自启成功${plain}" \
               || echo -e "${red}V2bX 设置开机自启失败${plain}"
    [[ $# == 0 ]] && before_show_menu
}

disable() {
    systemctl disable ${BINARY_NAME}
    [[ $? == 0 ]] && echo -e "${green}V2bX 取消开机自启成功${plain}" \
               || echo -e "${red}V2bX 取消开机自启失败${plain}"
    [[ $# == 0 ]] && before_show_menu
}

show_log() {
    journalctl -u ${BINARY_NAME}.service -e --no-pager -f
    [[ $# == 0 ]] && before_show_menu
}

initconfig() {
    check_install || return
    bash <(curl -Ls https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/initconfig.sh)
    [[ $? == 0 ]] && restart || before_show_menu
}

update_shell() {
    wget -O /usr/bin/${NAME} -N --no-check-certificate ${SHELL_URL}
    if [[ $? != 0 ]]; then
        echo "" && echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/${NAME}
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

generate_x25519() {
    echo -n "正在生成 x25519 密钥："
    ${BIN_PATH} x25519 2>/dev/null || openssl genpkey -algorithm X25519 2>/dev/null
    echo ""
    [[ $# == 0 ]] && before_show_menu
}

show_version() {
    echo -n "V2bX 版本："
    ${BIN_PATH} version 2>/dev/null || echo -e "${red}无法获取版本信息${plain}"
    echo ""
    [[ $# == 0 ]] && before_show_menu
}

show_menu() {
    echo ""
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "          ${green}sub - pupmsub 管理脚本${plain}"
    echo -e "          github.com/pupmme/pupmsub"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    show_status
    echo ""
    echo -e "  ${green}1.${plain} 安装 V2bX"
    echo -e "  ${green}2.${plain} 卸载 V2bX"
    echo -e "  ${green}3.${plain} 更新 V2bX"
    echo ""
    echo -e "  ${green}4.${plain} 启动 V2bX"
    echo -e "  ${green}5.${plain} 停止 V2bX"
    echo -e "  ${green}6.${plain} 重启 V2bX"
    echo -e "  ${green}7.${plain} 查看状态"
    echo -e "  ${green}8.${plain} 查看日志"
    echo ""
    echo -e "  ${green}9.${plain} 启用开机自启"
    echo -e "  ${green}10.${plain} 取消开机自启"
    echo ""
    echo -e "  ${green}11.${plain} 修改配置文件"
    echo -e "  ${green}12.${plain} 初始化配置"
    echo -e "  ${green}13.${plain} 生成 x25519 密钥"
    echo -e "  ${green}14.${plain} 查看 V2bX 版本"
    echo ""
    echo -e "  ${green}15.${plain} 升级脚本"
    echo -e "  ${green}16.${plain} 安装 BBR"
    echo ""
    echo -e "  ${green}0.${plain} 退出"
    echo ""
}

main() {
    while true; do
        show_menu
        read -rp "请输入数字: " num
        echo ""
        case "${num}" in
            1)  check_uninstall && install ;;
            2)  check_install && uninstall ;;
            3)  update ;;
            4)  check_install && start ;;
            5)  check_install && stop ;;
            6)  check_install && restart ;;
            7)  check_install && status ;;
            8)  check_install && show_log ;;
            9)  check_install && enable ;;
            10) check_install && disable ;;
            11) check_install && config ;;
            12) initconfig ;;
            13) check_install && generate_x25519 ;;
            14) check_install && show_version ;;
            15) update_shell ;;
            16) install_bbr ;;
            0)  exit 0 ;;
            *)  echo -e "${red}请输入正确的数字${plain}" ;;
        esac
    done
}

install_bbr() {
    bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}

main
