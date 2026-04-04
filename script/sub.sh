#!/bin/bash

# 非 root 时自动 sudo 重跑
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi


# sub 管理脚本

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
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

[[ $EUID -ne 0 ]] && echo -e "${red}错误: 必须使用 root 用户运行${plain}" && exit 1

is_active() {
    systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null
}

is_enabled() {
    systemctl is-enabled --quiet ${SERVICE_NAME} 2>/dev/null
}

# 有参数：直接执行后退出
if [[ $# -gt 0 ]]; then
    case $1 in
        start)
            systemctl start ${SERVICE_NAME}
            sleep 1
            is_active && echo -e "${green}sub 启动成功${plain}" \
                || echo -e "${red}sub 启动失败，请使用 sub log 查看日志${plain}"
            exit 0
            ;;
        stop)
            systemctl stop ${SERVICE_NAME}
            sleep 1
            is_active && echo -e "${red}sub 停止失败${plain}" \
                || echo -e "${green}sub 已停止${plain}"
            exit 0
            ;;
        restart)
            systemctl restart ${SERVICE_NAME}
            sleep 2
            is_active && echo -e "${green}sub 重启成功${plain}" \
                || echo -e "${red}sub 可能启动失败，请使用 sub log 查看日志${plain}"
            exit 0
            ;;
        status)
            echo ""
            if [[ ! -f "${SERVICE_PATH}" ]]; then
                echo -e "  sub ${red}未安装${plain}"
            elif is_active; then
                echo -e "  sub ${green}Running${plain}"
            else
                echo -e "  sub ${red}Not Running${plain}"
            fi
            echo ""
            exit 0
            ;;
        log)
            echo -e "${yellow}按 Ctrl+C 退出日志查看${plain}"
            journalctl -u ${SERVICE_NAME} -f --no-pager -n 50
            exit 0
            ;;
        enable)
            systemctl enable ${SERVICE_NAME}
            [[ $? == 0 ]] && echo -e "${green}sub 已设置开机自启${plain}" \
                || echo -e "${red}sub 设置开机自启失败${plain}"
            exit 0
            ;;
        disable)
            systemctl disable ${SERVICE_NAME}
            [[ $? == 0 ]] && echo -e "${green}sub 已取消开机自启${plain}" \
                || echo -e "${red}sub 取消开机自启失败${plain}"
            exit 0
            ;;
        install)
            bash <(curl -Ls ${INSTALL_URL})
            exit $?
            ;;
        uninstall)
            echo ""
            echo -ne "确认卸载 sub？此操作不可恢复 [y/N]: "
            read -r yn
            [[ ! "$yn" =~ ^[Yy]$ ]] && echo "已取消" && exit 0
            systemctl stop ${SERVICE_NAME} 2>/dev/null || true
            systemctl disable ${SERVICE_NAME} 2>/dev/null || true
            rm -f ${SERVICE_PATH}
            systemctl daemon-reload
            systemctl reset-failed 2>/dev/null || true
            rm -rf /etc/sub
            rm -rf /usr/local/sub
            rm -f /usr/bin/sub
            echo -e "${green}sub 已完全卸载${plain}"
            exit 0
            ;;
        init)
            bash <(curl -Ls ${INITCONFIG_URL})
            exit $?
            ;;
        version)
            ${BIN_PATH} version 2>/dev/null || echo -e "${red}无法获取版本信息${plain}"
            exit 0
            ;;
        x25519)
            ${BIN_PATH} x25519 2>/dev/null || openssl genpkey -algorithm X25519 2>/dev/null
            exit 0
            ;;
        *)
            echo "用法: sub {start|stop|restart|status|log|enable|disable|install|uninstall|init|version|x25519}"
            exit 1
            ;;
    esac
fi

# 无参数：显示菜单后直接退出
echo ""
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${blue}            ${green}sub 管理脚本${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo ""
echo -e "  ${green}1.${plain}  sub start     启动"
echo -e "  ${green}2.${plain}  sub stop      停止"
echo -e "  ${green}3.${plain}  sub restart   重启"
echo -e "  ${green}4.${plain}  sub status    状态"
echo -e "  ${green}5.${plain}  sub log       日志"
echo ""
echo -e "  ${green}6.${plain}  sub install   安装"
echo -e "  ${green}7.${plain}  sub uninstall 卸载"
echo ""
echo -e "  ${green}8.${plain}  sub enable    开机自启"
echo -e "  ${green}9.${plain}  sub disable   取消自启"
echo ""
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
