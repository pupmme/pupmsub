#!/bin/bash

NAME="sub"
BINARY_NAME="sub"
BIN_DIR="/usr/local/${BINARY_NAME}"
CFG_DIR="/etc/${BINARY_NAME}"
BIN_PATH="${BIN_DIR}/${BINARY_NAME}"
SERVICE_NAME="sub"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

[[ $EUID -ne 0 ]] && echo -e "\033[0;31m错误: 必须使用 root 用户运行\033[0m\n" && exit 1

# 有参数：直接执行后退出
if [[ $# -gt 0 ]]; then
    case $1 in
        start)
            systemctl start ${SERVICE_NAME}
            exit 0
            ;;
        stop)
            systemctl stop ${SERVICE_NAME}
            exit 0
            ;;
        restart)
            systemctl restart ${SERVICE_NAME}
            exit 0
            ;;
        status)
            systemctl status ${SERVICE_NAME} --no-pager -l
            exit 0
            ;;
        log)
            journalctl -u ${SERVICE_NAME} -f --no-pager -n 50
            exit 0
            ;;
        uninstall)
            systemctl stop ${SERVICE_NAME} 2>/dev/null
            systemctl disable ${SERVICE_NAME} 2>/dev/null
            rm -f ${SERVICE_PATH}
            systemctl daemon-reload
            systemctl reset-failed
            rm -rf /etc/sub
            rm -rf /usr/local/sub
            rm -f /usr/bin/sub
            rm -f /usr/bin/V2bX
            exit 0
            ;;
        *)
            exit 1
            ;;
    esac
fi

# 无参数：纯展示菜单后退出
echo "---------------------------"
echo "   sub 管理脚本"
echo "---------------------------"
echo "   1.  启动"
echo "   2.  停止"
echo "   3.  重启"
echo "   4.  状态"
echo "   5.  日志"
echo "   6.  卸载"
echo "---------------------------"
