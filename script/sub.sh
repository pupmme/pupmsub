#!/bin/bash

# ============================================
#  sub 管理脚本
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
INSTALL_URL="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/install.sh"
INITCONFIG_URL="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/initconfig.sh"
SHELL_URL="https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/sub.sh"

# 必须 root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: 必须使用 root 用户运行${plain}" && exit 1

# check_status: 0=running, 1=stopped, 2=not installed
check_status() {
    if [[ ! -f "${SERVICE_PATH}" ]]; then return 2; fi
    if systemctl is-active --quiet ${SERVICE_NAME}; then return 0; else return 1; fi
}

show_status_line() {
    check_status
    case $? in
        0)  echo -e "  状态   ${green}Running${plain}"
            systemctl is-enabled --quiet ${SERVICE_NAME} 2>/dev/null \
                && echo -e "  自启   ${green}Yes${plain}" || echo -e "  自启   ${red}No${plain}"
            ;;
        1)  echo -e "  状态   ${red}Not Running${plain}"
            systemctl is-enabled --quiet ${SERVICE_NAME} 2>/dev/null \
                && echo -e "  自启   ${green}Yes${plain}" || echo -e "  自启   ${red}No${plain}"
            ;;
        2)  echo -e "  状态   ${red}Not Installed${plain}"
            ;;
    esac
}

# ============================================
# 有参数：直接执行对应命令后退出
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
                echo -e "${green}sub 重启成功${plain}"
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
            show_status_line
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
            echo ""
            echo -e "${yellow}确认卸载 sub？此操作不可恢复 [y/N]: ${plain}"
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
            rm -f /usr/bin/V2bX
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
        init)
            bash <(curl -Ls ${INITCONFIG_URL})
            exit $?
            ;;
        update)
            bash <(curl -Ls ${INSTALL_URL})
            exit $?
            ;;
        x25519)
            ${BIN_PATH} x25519 2>/dev/null || openssl genpkey -algorithm X25519 2>/dev/null
            exit 0
            ;;
        *)
            echo "用法: sub {start|stop|restart|status|log|install|uninstall|enable|disable|version|init|update|x25519}"
            exit 1
            ;;
    esac
fi

# ============================================
# 无参数：显示菜单后直接退出（纯展示，不交互）
# ============================================
echo ""
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo -e "${blue}              sub 管理脚本${plain}"
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
echo ""
show_status_line
echo ""
echo -e "  ${green}1.${plain}  启动      sub start"
echo -e "  ${green}2.${plain}  停止      sub stop"
echo -e "  ${green}3.${plain}  重启      sub restart"
echo -e "  ${green}4.${plain}  状态      sub status"
echo -e "  ${green}5.${plain}  日志      sub log"
echo ""
echo -e "  ${green}6.${plain}  安装      sub install"
echo -e "  ${green}7.${plain}  更新      sub update"
echo -e "  ${green}8.${plain}  卸载      sub uninstall"
echo ""
echo -e "  ${green}9.${plain}  开机自启  sub enable"
echo -e "  ${green}10.${plain} 取消自启  sub disable"
echo ""
echo -e "  ${green}11.${plain} 初始化配置 sub init"
echo -e "  ${green}12.${plain} 生成密钥  sub x25519"
echo -e "  ${green}13.${plain} 版本信息  sub version"
echo ""
echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
