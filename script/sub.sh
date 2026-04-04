#!/bin/bash

# ============================================
# pupmsub 管理脚本 (sub)
# ============================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
plain='\033[0m'

NAME="sub"
BINARY_NAME="sub"
BIN_DIR="/usr/local/${BINARY_NAME}"
CFG_DIR="/etc/${BINARY_NAME}"
BIN_PATH="${BIN_DIR}/${BINARY_NAME}"
SERVICE_NAME="sub"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
SHELL_URL="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/sub.sh"
INSTALL_URL="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/install.sh"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

# ============================================
# 如果有参数，直接执行对应命令后退出（不进入菜单）
# ============================================
if [[ $# -gt 0 ]]; then
    case $1 in
        start)
            systemctl start ${SERVICE_NAME}
            sleep 1
            if systemctl is-active --quiet ${SERVICE_NAME}; then
                echo -e "${green}sub 启动成功${plain}"
            else
                echo -e "${red}sub 启动失败，请使用 sub log 查看日志${plain}"
            fi
            exit 0
            ;;
        stop)
            systemctl stop ${SERVICE_NAME}
            sleep 1
            if systemctl is-active --quiet ${SERVICE_NAME}; then
                echo -e "${red}sub 停止失败${plain}"
            else
                echo -e "${green}sub 已停止${plain}"
            fi
            exit 0
            ;;
        restart)
            systemctl restart ${SERVICE_NAME}
            sleep 2
            if systemctl is-active --quiet ${SERVICE_NAME}; then
                echo -e "${green}sub 重启成功，请使用 sub log 查看运行日志${plain}"
            else
                echo -e "${red}sub 可能启动失败，请使用 sub log 查看日志${plain}"
            fi
            exit 0
            ;;
        status)
            echo -e "${blue}============================================${plain}"
            echo -e "${blue}  sub 状态${plain}"
            echo -e "${blue}============================================${plain}"
            systemctl status ${SERVICE_NAME} --no-pager -l
            echo ""
            if systemctl is-active --quiet ${SERVICE_NAME}; then
                echo -e "sub 状态: ${green}Running${plain}"
            else
                echo -e "sub 状态: ${red}Not Running${plain}"
            fi
            exit 0
            ;;
        log)
            echo -e "${yellow}按 Ctrl+C 退出日志查看${plain}"
            journalctl -u ${SERVICE_NAME} -f --no-pager -n 50
            exit 0
            ;;
        install)
            bash <(curl -Ls ${INSTALL_URL})
            exit $?
            ;;
        uninstall)
            confirm "确定要卸载 sub 吗?" "n"
            [[ $? != 0 ]] && exit 0
            systemctl stop ${SERVICE_NAME} 2>/dev/null || true
            systemctl disable ${SERVICE_NAME} 2>/dev/null || true
            rm -f ${SERVICE_PATH}
            systemctl daemon-reload
            systemctl reset-failed
            rm -rf /etc/sub
            rm -rf /usr/local/sub
            rm -f /usr/bin/sub
            rm -f /usr/bin/V2bX
            echo ""
            echo -e "${green}sub 已完全卸载${plain}"
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
        version)
            ${BIN_PATH} version 2>/dev/null || echo -e "${red}无法获取版本信息${plain}"
            exit 0
            ;;
        *)
            echo "用法: sub {start|stop|restart|status|log|install|uninstall|enable|disable|version}"
            exit 1
            ;;
    esac
fi

# ============================================
# 无参数：显示菜单（纯展示，不交互循环）
# ============================================

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f "${SERVICE_PATH}" ]]; then
        return 2
    fi
    temp=$(systemctl status ${SERVICE_NAME} | grep "Active:" | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    [[ x"${temp}" == x"running" ]] && return 0 || return 1
}

echo ""
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${blue}           ${green}sub - pupmsub 管理脚本${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo ""

# Show basic status inline
check_status
case $? in
    0)  echo -e "  sub 状态: ${green}Running${plain}"
        systemctl is-enabled --quiet ${SERVICE_NAME} 2>/dev/null \
            && echo -e "  开机自启: ${green}是${plain}" || echo -e "  开机自启: ${red}否${plain}"
        ;;
    1)  echo -e "  sub 状态: ${yellow}Not Running${plain}"
        systemctl is-enabled --quiet ${SERVICE_NAME} 2>/dev/null \
            && echo -e "  开机自启: ${green}是${plain}" || echo -e "  开机自启: ${red}否${plain}"
        ;;
    2)  echo -e "  sub 状态: ${red}未安装${plain}"
esac

echo ""
echo -e "  ${green}1.${plain}  安装 sub"
echo -e "  ${green}2.${plain}  卸载 sub"
echo -e "  ${green}3.${plain}  更新 sub"
echo ""
echo -e "  ${green}4.${plain}  启动 sub"
echo -e "  ${green}5.${plain}  停止 sub"
echo -e "  ${green}6.${plain}  重启 sub"
echo -e "  ${green}7.${plain}  查看状态"
echo -e "  ${green}8.${plain}  查看日志"
echo ""
echo -e "  ${green}9.${plain}  启用开机自启"
echo -e "  ${green}10.${plain} 取消开机自启"
echo ""
echo -e "  ${green}11.${plain} 查看 sub 版本"
echo ""
echo -e "  ${green}0.${plain}  退出"
echo ""
