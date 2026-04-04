#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
cyan='\033[0;36m'
bcyan='\033[1;36m'
bold='\033[1m'
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

# 自动 sudo
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

is_active() {
    systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null
}

is_installed() {
    [[ -f "${SERVICE_PATH}" ]] && [[ -f "${CFG_DIR}/config.json" ]]
}

show_status_line() {
    if ! is_installed; then
        echo -e "  ${yellow}[ 未安装 ]${plain}"
        return
    fi
    if is_active; then
        echo -e "  ${green}[ Running ]${plain}"
    else
        echo -e "  ${red}[ Not Running ]${plain}"
    fi
}

# ============================================
# 有参数：直接执行对应命令后退出
# ============================================
if [[ $# -gt 0 ]]; then
    case $1 in
        start)
            is_installed || { echo -e "${red}错误: 请先运行 sub install 安装${plain}"; exit 1; }
            systemctl start ${SERVICE_NAME}
            sleep 1
            is_active && echo -e "${green}✓ 启动成功${plain}" \
                || echo -e "${red}✗ 启动失败，运行 sub log 查看日志${plain}"
            exit 0
            ;;
        stop)
            is_installed || { echo -e "${red}错误: 请先运行 sub install 安装${plain}"; exit 1; }
            systemctl stop ${SERVICE_NAME}
            sleep 1
            is_active && echo -e "${red}✗ 停止失败${plain}" \
                || echo -e "${green}✓ 已停止${plain}"
            exit 0
            ;;
        restart)
            is_installed || { echo -e "${red}错误: 请先运行 sub install 安装${plain}"; exit 1; }
            systemctl restart ${SERVICE_NAME}
            sleep 2
            is_active && echo -e "${green}✓ 重启成功${plain}" \
                || echo -e "${red}✗ 可能启动失败，运行 sub log 查看日志${plain}"
            exit 0
            ;;
        status)
            echo ""
            show_status_line
            echo ""
            if is_installed; then
                systemctl status ${SERVICE_NAME} --no-pager -l
            fi
            exit 0
            ;;
        log)
            is_installed || { echo -e "${red}错误: 请先运行 sub install 安装${plain}"; exit 1; }
            echo -e "${yellow}按 Ctrl+C 退出${plain}"
            journalctl -u ${SERVICE_NAME} -f --no-pager -n 50
            exit 0
            ;;
        enable)
            is_installed || { echo -e "${red}错误: 请先运行 sub install 安装${plain}"; exit 1; }
            systemctl enable ${SERVICE_NAME}
            [[ $? == 0 ]] && echo -e "${green}✓ 已设置开机自启${plain}" \
                || echo -e "${red}✗ 设置失败${plain}"
            exit 0
            ;;
        disable)
            is_installed || { echo -e "${red}错误: 请先运行 sub install 安装${plain}"; exit 1; }
            systemctl disable ${SERVICE_NAME}
            [[ $? == 0 ]] && echo -e "${green}✓ 已取消开机自启${plain}" \
                || echo -e "${red}✗ 取消失败${plain}"
            exit 0
            ;;
        install)
            bash <(curl -Ls ${INSTALL_URL})
            exit $?
            ;;
        uninstall)
            echo ""
            echo -ne "${yellow}确认卸载 sub？此操作不可恢复 [y/N]: ${plain}"
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
            echo -e "${green}✓ sub 已完全卸载${plain}"
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

# ============================================
# 无参数：交互式菜单
# ============================================
while true; do
    clear
    echo ""
    echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "${blue}            ${bold}sub 管理脚本${plain}"
    echo -e "${blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo ""
    show_status_line
    echo ""
    echo -e "  ${green}1.${plain}  启动"
    echo -e "  ${green}2.${plain}  停止"
    echo -e "  ${green}3.${plain}  重启"
    echo -e "  ${green}4.${plain}  状态"
    echo -e "  ${green}5.${plain}  日志"
    echo ""
    echo -e "  ${green}6.${plain}  安装"
    echo -e "  ${green}7.${plain}  卸载"
    echo -e "  ${green}8.${plain}  初始化配置"
    echo ""
    echo -e "  ${green}9.${plain}  开机自启"
    echo -e "  ${green}10.${plain} 取消自启"
    echo ""
    echo -e "  ${green}11.${plain} 版本信息"
    echo -e "  ${green}12.${plain} 生成密钥"
    echo ""
    echo -e "  ${green}0.${plain}  退出"
    echo ""
    echo -en "${cyan}请输入数字: ${plain}"
    read -r num

    case "${num}" in
        1)
            echo ""
            if ! is_installed; then
                echo -e "${red}请先选择 [6] 安装${plain}"
            else
                systemctl start ${SERVICE_NAME}
                sleep 1
                is_active && echo -e "${green}✓ 启动成功${plain}" \
                    || echo -e "${red}✗ 启动失败${plain}"
            fi
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        2)
            echo ""
            if ! is_installed; then
                echo -e "${red}请先选择 [6] 安装${plain}"
            else
                systemctl stop ${SERVICE_NAME}
                sleep 1
                is_active && echo -e "${red}✗ 停止失败${plain}" \
                    || echo -e "${green}✓ 已停止${plain}"
            fi
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        3)
            echo ""
            if ! is_installed; then
                echo -e "${red}请先选择 [6] 安装${plain}"
            else
                systemctl restart ${SERVICE_NAME}
                sleep 2
                is_active && echo -e "${green}✓ 重启成功${plain}" \
                    || echo -e "${red}✗ 可能启动失败${plain}"
            fi
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        4)
            echo ""
            if ! is_installed; then
                echo -e "${red}请先选择 [6] 安装${plain}"
            else
                show_status_line
                echo ""
                systemctl status ${SERVICE_NAME} --no-pager -l
            fi
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        5)
            echo ""
            if ! is_installed; then
                echo -e "${red}请先选择 [6] 安装${plain}"
            else
                echo -e "${yellow}按 Ctrl+C 退出日志${plain}"
                journalctl -u ${SERVICE_NAME} -f --no-pager -n 30
            fi
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        6)
            echo ""
            bash <(curl -Ls ${INSTALL_URL})
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        7)
            echo ""
            echo -ne "${yellow}确认卸载 sub？此操作不可恢复 [y/N]: ${plain}"
            read -r yn
            [[ "$yn" =~ ^[Yy]$ ]] || { echo "已取消"; }
            if [[ "$yn" =~ ^[Yy]$ ]]; then
                systemctl stop ${SERVICE_NAME} 2>/dev/null || true
                systemctl disable ${SERVICE_NAME} 2>/dev/null || true
                rm -f ${SERVICE_PATH}
                systemctl daemon-reload
                systemctl reset-failed 2>/dev/null || true
                rm -rf /etc/sub
                rm -rf /usr/local/sub
                rm -f /usr/bin/sub
                echo -e "${green}✓ sub 已完全卸载${plain}"
            fi
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        8)
            echo ""
            bash <(curl -Ls ${INITCONFIG_URL})
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        9)
            echo ""
            if ! is_installed; then
                echo -e "${red}请先选择 [6] 安装${plain}"
            else
                systemctl enable ${SERVICE_NAME}
                [[ $? == 0 ]] && echo -e "${green}✓ 已设置开机自启${plain}" \
                    || echo -e "${red}✗ 设置失败${plain}"
            fi
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        10)
            echo ""
            if ! is_installed; then
                echo -e "${red}请先选择 [6] 安装${plain}"
            else
                systemctl disable ${SERVICE_NAME}
                [[ $? == 0 ]] && echo -e "${green}✓ 已取消开机自启${plain}" \
                    || echo -e "${red}✗ 取消失败${plain}"
            fi
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        11)
            echo ""
            ${BIN_PATH} version 2>/dev/null || echo -e "${red}无法获取版本信息${plain}"
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        12)
            echo ""
            ${BIN_PATH} x25519 2>/dev/null || openssl genpkey -algorithm X25519 2>/dev/null
            echo -en "${yellow}按回车返回菜单...${plain}"
            read -r _
            ;;
        0|exit|quit)
            clear
            exit 0
            ;;
        *)
            echo ""
            echo -e "${red}请输入正确的数字 (0-12)${plain}"
            sleep 1
            ;;
    esac
done
