#!/bin/bash

# ============================================
# pupmsub 管理菜单
# ============================================

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
bcyan='\033[1;36m'
plain='\033[0m'

NAME="sub"
BINARY_NAME="V2bX"
CFG_DIR="/etc/${BINARY_NAME}"
BIN_PATH="/usr/local/${BINARY_NAME}/${BINARY_NAME}"

# 检测 root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用 root 用户运行！\n" && exit 1

info()    { echo -e "${green}[INFO]${plain} $*"; }
warn()    { echo -e "${yellow}[WARN]${plain} $*"; }
error()   { echo -e "${red}[ERROR]${plain} $*"; }

# ============================================
# 服务状态检测
# ============================================
check_status() {
    if [[ ! -f /etc/systemd/system/${BINARY_NAME}.service ]]; then
        return 2  # 未安装
    fi
    local temp
    temp=$(systemctl status ${BINARY_NAME} 2>/dev/null | grep Active | awk '{print $3}' | tr -d '()')
    [[ x"${temp}" == x"running" ]] && return 0 || return 1
}

check_installed() {
    check_status
    case $? in
        2) echo -e "${red}pupmsub 未安装，请先安装！${plain}" && return 1 ;;
    esac
    return 0
}

check_not_installed() {
    if [[ -f /etc/systemd/system/${BINARY_NAME}.service ]]; then
        echo -e "${red}pupmsub 已安装，请先卸载！${plain}"
        return 1
    fi
    return 0
}

is_enabled() {
    systemctl is-enabled ${BINARY_NAME}.service >/dev/null 2>&1 && return 0 || return 1
}

show_running_status() {
    echo -e "  ${green}●${plain} pupmsub ${BINARY_NAME} 已安装"
    echo -e "  ${green}  状态: 运行中${plain}"
    is_enabled && echo -e "  ${green}  自启: 已启用${plain}" || echo -e "  ${red}  自启: 未启用${plain}"
}

show_stopped_status() {
    echo -e "  ${yellow}●${plain} pupmsub ${BINARY_NAME} 已安装"
    echo -e "  ${yellow}  状态: 未运行${plain}"
    is_enabled && echo -e "  ${green}  自启: 已启用${plain}" || echo -e "  ${red}  自启: 未启用${plain}"
}

show_not_installed_status() {
    echo -e "  ${red}●${plain} pupmsub ${BINARY_NAME} 未安装"
}

# ============================================
# 操作函数
# ============================================
start() {
    systemctl start ${BINARY_NAME}
    sleep 1
    systemctl is-active --quiet ${BINARY_NAME} && info "启动成功" || error "启动失败，查看日志: sub log"
}

stop() {
    systemctl stop ${BINARY_NAME} && info "已停止" || error "停止失败"
}

restart() {
    systemctl restart ${BINARY_NAME}
    sleep 1
    systemctl is-active --quiet ${BINARY_NAME} && info "重启成功" || error "重启失败，查看日志: sub log"
}

status() {
    check_status
    case $? in
        0) show_running_status ;;
        1) show_stopped_status ;;
        2) show_not_installed_status ;;
    esac
}

show_log() {
    journalctl -u ${BINARY_NAME} -o cat --no-pager -n 50
}

version() {
    ${BIN_PATH} version 2>/dev/null && return
    echo -e "${yellow}无法获取版本信息${plain}"
}

enable() {
    systemctl enable ${BINARY_NAME} && info "已设置开机自启" || error "设置失败"
}

disable() {
    systemctl disable ${BINARY_NAME} && info "已取消开机自启" || error "取消失败"
}

uninstall() {
    echo ""
    read -rp "确定要卸载 pupmsub 吗？[y/n]: " yn
    [[ ! ${yn} == [yY] ]] && return
    systemctl stop ${BINARY_NAME} 2>/dev/null || true
    systemctl disable ${BINARY_NAME} 2>/dev/null || true
    rm -f /etc/systemd/system/${BINARY_NAME}.service
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    rm -rf ${CFG_DIR}
    rm -rf /usr/local/${BINARY_NAME}
    rm -f /usr/bin/${NAME}
    rm -f /usr/bin/${BINARY_NAME}
    rm -f /usr/bin/sub
    info "卸载完成"
}

edit_config() {
    local cfg="${CFG_DIR}/config.yml"
    if [[ ! -f "${cfg}" ]]; then
        error "配置文件不存在: ${cfg}"
        return
    fi
    ${EDITOR:-nano} "${cfg}"
    sleep 1
    check_status
    case $? in
        0) info "配置已更新，服务运行中" ;;
        1) echo -e "配置已更新，是否重启生效？[Y/n] "
           read -rp "(默认 Y): " yn; [[ -z ${yn} ]] && yn="y"
           [[ ${yn} == [yY] ]] && restart ;;
        2) warn "服务未安装" ;;
    esac
}

edit_node() {
    local node_cfg="${CFG_DIR}/node.yml"
    if [[ ! -f "${node_cfg}" ]]; then
        error "节点配置文件不存在: ${node_cfg}"
        return
    fi
    ${EDITOR:-nano} "${node_cfg}"
    sleep 1
    check_status
    case $? in
        0) info "节点配置已更新，重启生效" && restart ;;
        1) info "节点配置已更新，重启生效" && restart ;;
        2) warn "服务未安装" ;;
    esac
}

reinstall() {
    echo ""
    read -rp "这将重新安装 pupmsub（保留配置），是否继续？[y/n]: " yn
    [[ ! ${yn} == [yY] ]] && return
    info "开始重新安装..."
    systemctl stop ${BINARY_NAME} 2>/dev/null || true
    rm -f /etc/systemd/system/${BINARY_NAME}.service
    bash <(curl -sL https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/install.sh)
}

# ============================================
# 显示菜单
# ============================================
show_header() {
    clear
    echo -e ""
    echo -e "  ${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo -e "  ${bcyan}    sub — pupmsub 管理脚本${plain}"
    echo -e "  ${bcyan}    github.com/pupmme/pupmsub${plain}"
    echo -e "  ${bcyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${plain}"
    echo ""
}

show_menu() {
    echo -e "  ${green}1.${plain} 安装 pupmsub"
    echo -e "  ${green}2.${plain} 卸载 pupmsub"
    echo ""
    echo -e "  ${green}3.${plain} 启动"
    echo -e "  ${green}4.${plain} 停止"
    echo -e "  ${green}5.${plain} 重启"
    echo -e "  ${green}6.${plain} 状态"
    echo -e "  ${green}7.${plain} 日志（最近 50 行）"
    echo ""
    echo -e "  ${green}8.${plain} 开机自启"
    echo -e "  ${green}9.${plain} 取消自启"
    echo ""
    echo -e "  ${green}10.${plain} 编辑主配置"
    echo -e "  ${green}11.${plain} 编辑节点配置"
    echo ""
    echo -e "  ${green}12.${plain} 升级 pupmsub"
    echo -e "  ${green}13.${plain} 查看版本"
    echo -e "  ${green}14.${plain} 生成 X25519 密钥"
    echo ""
    echo -e "  ${green}0.${plain} 退出"
    echo ""
}

show_status_line() {
    check_status
    case $? in
        0) echo -e "  ${green}●${plain} 运行中" ;;
        1) echo -e "  ${yellow}●${plain} 未运行" ;;
        2) echo -e "  ${red}●${plain} 未安装" ;;
    esac
    is_enabled && echo -e "  ${green}↑${plain} 自启" || echo -e "  ${red}↑${plain} 无自启"
    echo ""
}

# ============================================
# 主循环
# ============================================
main() {
    while true; do
        show_header
        show_menu
        show_status_line
        read -rp "请输入选择: " num
        echo ""

        case "${num}" in
            1)  check_not_installed && bash <(curl -sL https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/install.sh) ;;
            2)  check_installed && uninstall ;;
            3)  check_installed && start ;;
            4)  check_installed && stop ;;
            5)  check_installed && restart ;;
            6)  check_installed && status ;;
            7)  check_installed && show_log ;;
            8)  check_installed && enable ;;
            9)  check_installed && disable ;;
            10) check_installed && edit_config ;;
            11) check_installed && edit_node ;;
            12) reinstall ;;
            13) check_installed && version ;;
            14) check_installed && openssl genpkey -algorithm X25519 2>/dev/null || ${BIN_PATH} x25519 2>/dev/null || echo -e "${yellow}请使用: openssl genpkey -algorithm X25519${plain}" ;;
            0)  echo -e "${green}再见！${plain}" && exit 0 ;;
            *)  echo -e "${red}请输入正确的数字${plain}" ;;
        esac

        [[ "${num}" != "0" ]] && {
            echo ""
            read -rp "按回车继续... "
        }
    done
}

main
