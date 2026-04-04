#!/bin/bash

# ============================================
# sub 管理脚本 (V2bX-script 风格)
# ============================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

NAME="sub"
BINARY_NAME="sub"
BIN_DIR="/usr/local/${BINARY_NAME}"
CFG_DIR="/etc/${BINARY_NAME}"
BIN_PATH="${BIN_DIR}/${BINARY_NAME}"
SERVICE_NAME="sub"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
INSTALL_URL="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/install.sh"
INITCONFIG_URL="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/initconfig.sh"

# ============================================
# 自动提权
# ============================================
[[ $EUID -ne 0 ]] && exec sudo "$0" "$@"

# ============================================
# 通用函数
# ============================================
confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        [[ x"${temp}" == x"" ]] && temp=$2
    else
        read -rp "$1 [y/n]: " temp
    fi
    [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

# ============================================
# 状态检测
# ============================================
# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f "${SERVICE_PATH}" ]]; then
        return 2
    fi
    temp=$(systemctl status ${SERVICE_NAME} | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    [[ x"${temp}" == x"running" ]] && return 0 || return 1
}

check_enabled() {
    temp=$(systemctl is-enabled ${SERVICE_NAME})
    [[ x"${temp}" == x"enabled" ]] && return 0 || return 1
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装 sub${plain}"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi
    return 0
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}sub 已安装，请不要重复安装${plain}"
        [[ $# == 0 ]] && before_show_menu
        return 1
    fi
    return 0
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "sub状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "sub状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "sub状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    [[ $? == 0 ]] \
        && echo -e "是否开机自启: ${green}是${plain}" \
        || echo -e "是否开机自启: ${red}否${plain}"
}

# ============================================
# 操作函数
# ============================================
install() {
    bash <(curl -Ls ${INSTALL_URL})
    [[ $? == 0 ]] && { [[ $# == 0 ]] && start || start 0; }
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls ${INSTALL_URL}) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 sub，请使用 sub log 查看运行日志${plain}"
        exit
    fi
    [[ $# == 0 ]] && before_show_menu
}

uninstall() {
    confirm "确定要卸载 sub 吗?" "n"
    [[ $? != 0 ]] && { [[ $# == 0 ]] && show_menu; return 0; }
    systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    systemctl disable ${SERVICE_NAME} 2>/dev/null || true
    rm ${SERVICE_PATH} -f
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    rm ${CFG_DIR}/ -rf
    rm ${BIN_DIR}/ -rf
    rm /usr/bin/${BINARY_NAME} -f
    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/${BINARY_NAME} -f${plain} 进行删除"
    echo ""
    [[ $# == 0 ]] && before_show_menu
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}sub已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        systemctl start ${SERVICE_NAME}
        sleep 2
        check_status
        [[ $? == 0 ]] \
            && echo -e "${green}sub 启动成功，请使用 sub log 查看运行日志${plain}" \
            || echo -e "${red}sub 可能启动失败，请稍后使用 sub log 查看日志信息${plain}"
    fi
    [[ $# == 0 ]] && before_show_menu
}

stop() {
    systemctl stop ${SERVICE_NAME}
    sleep 2
    check_status
    [[ $? == 1 ]] \
        && echo -e "${green}sub 停止成功${plain}" \
        || echo -e "${red}sub 停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    [[ $# == 0 ]] && before_show_menu
}

restart() {
    systemctl restart ${SERVICE_NAME}
    sleep 2
    check_status
    [[ $? == 0 ]] \
        && echo -e "${green}sub 重启成功，请使用 sub log 查看运行日志${plain}" \
        || echo -e "${red}sub 可能启动失败，请稍后使用 sub log 查看日志信息${plain}"
    [[ $# == 0 ]] && before_show_menu
}

status() {
    systemctl status ${SERVICE_NAME} --no-pager -l
    [[ $# == 0 ]] && before_show_menu
}

show_log() {
    journalctl -u ${SERVICE_NAME}.service -e --no-pager -f
    [[ $# == 0 ]] && before_show_menu
}

enable() {
    systemctl enable ${SERVICE_NAME}
    [[ $? == 0 ]] \
        && echo -e "${green}sub 设置开机自启成功${plain}" \
        || echo -e "${red}sub 设置开机自启失败${plain}"
    [[ $# == 0 ]] && before_show_menu
}

disable() {
    systemctl disable ${SERVICE_NAME}
    [[ $? == 0 ]] \
        && echo -e "${green}sub 取消开机自启成功${plain}" \
        || echo -e "${red}sub 取消开机自启失败${plain}"
    [[ $# == 0 ]] && before_show_menu
}

show_version() {
    echo -n "sub 版本："
    ${BIN_PATH} version 2>/dev/null || echo -e "${red}无法获取版本信息${plain}"
    echo ""
    [[ $# == 0 ]] && before_show_menu
}

generate_x25519() {
    echo -n "正在生成 x25519 密钥："
    ${BIN_PATH} x25519 2>/dev/null || openssl genpkey -algorithm X25519 2>/dev/null
    echo ""
    [[ $# == 0 ]] && before_show_menu
}

update_shell() {
    wget -O /usr/bin/${BINARY_NAME} -N --no-check-certificate \
        "https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/sub.sh"
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/${BINARY_NAME}
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

show_usage() {
    echo "sub 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "${BINARY_NAME}              - 显示管理菜单"
    echo "${BINARY_NAME} start        - 启动 sub"
    echo "${BINARY_NAME} stop         - 停止 sub"
    echo "${BINARY_NAME} restart      - 重启 sub"
    echo "${BINARY_NAME} status       - 查看 sub 状态"
    echo "${BINARY_NAME} enable       - 设置 sub 开机自启"
    echo "${BINARY_NAME} disable      - 取消 sub 开机自启"
    echo "${BINARY_NAME} log          - 查看 sub 日志"
    echo "${BINARY_NAME} x25519       - 生成 x25519 密钥"
    echo "${BINARY_NAME} version      - 查看 sub 版本"
    echo "${BINARY_NAME} install      - 安装 sub"
    echo "${BINARY_NAME} uninstall    - 卸载 sub"
    echo "${BINARY_NAME} init         - 初始化配置"
    echo "${BINARY_NAME} update       - 更新 sub"
    echo "${BINARY_NAME} update x.x.x - 安装 sub 指定版本"
    echo "${BINARY_NAME} update_shell - 升级维护脚本"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}sub 后端管理脚本，${plain}${red}不适用于docker${plain}
--- https://github.com/pupmme/pupmsub ---
  ${green}1.${plain} 安装 sub
  ${green}2.${plain} 更新 sub
  ${green}3.${plain} 卸载 sub
————————————————
  ${green}4.${plain} 启动 sub
  ${green}5.${plain} 停止 sub
  ${green}6.${plain} 重启 sub
  ${green}7.${plain} 查看 sub 状态
  ${green}8.${plain} 查看 sub 日志
————————————————
  ${green}9.${plain} 设置 sub 开机自启
  ${green}10.${plain} 取消 sub 开机自启
————————————————
  ${green}11.${plain} 查看 sub 版本
  ${green}12.${plain} 生成 x25519 密钥
  ${green}13.${plain} 初始化配置
  ${green}14.${plain} 升级 sub 维护脚本
 "
    show_status
    echo && read -rp "请输入选择 [1-14]: " num

    case "${num}" in
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) check_install && show_version ;;
        12) check_install && generate_x25519 ;;
        13) check_install && bash <(curl -Ls ${INITCONFIG_URL}) ;;
        14) update_shell ;;
        *) echo -e "${red}请输入正确的数字 [1-14]${plain}" ;;
    esac
}

# ============================================
# 入口
# ============================================
if [[ $# > 0 ]]; then
    case $1 in
        "start")      check_install 0 && start 0 ;;
        "stop")       check_install 0 && stop 0 ;;
        "restart")    check_install 0 && restart 0 ;;
        "status")     check_install 0 && status 0 ;;
        "enable")     check_install 0 && enable 0 ;;
        "disable")    check_install 0 && disable 0 ;;
        "log")        check_install 0 && show_log 0 ;;
        "update")     check_install 0 && update 0 $2 ;;
        "install")    check_uninstall 0 && install 0 ;;
        "uninstall")  check_install 0 && uninstall 0 ;;
        "init")       check_install 0 && bash <(curl -Ls ${INITCONFIG_URL}) ;;
        "x25519")     check_install 0 && generate_x25519 0 ;;
        "version")    check_install 0 && show_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
