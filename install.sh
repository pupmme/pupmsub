#!/bin/sh

set -e

NAME="pupmsub"
BINARY_NAME="pupmsub"
SYSTEM_NAME="pupmsub"

# Directories
INSTALL_DIR="/etc/pupmsub"
BIN_DIR="/usr/local/bin"
LOG_DIR="/var/log/pupmsub"
SERVICE_DIR="/etc/systemd/system"

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
  x86_64)   ARCH_STR="amd64" ;;
  aarch64)  ARCH_STR="arm64" ;;
  armv7l)   ARCH_STR="armv7" ;;
  *)        echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

# Detect libc
LIBC=$(ldd /bin/ls 2>/dev/null | grep -c "musl" || true)
if [ "$LIBC" -gt 0 ]; then
  LIBC_STR="musl"
else
  LIBC_STR="gnu"
fi

PLATFORM="${ARCH_STR}-${LIBC_STR}"
TMP_DIR=$(mktemp -d)
ARCHIVE="pupmsub-linux-${PLATFORM}.tar.gz"
URL="https://github.com/pupmme/pupmsub/releases/latest/download/${ARCHIVE}"

echo "=== ${NAME} 安装脚本 ==="
echo "Platform: ${PLATFORM}"

# Download
echo "下载 ${ARCHIVE}..."
cd "$TMP_DIR"
if command -v curl >/dev/null 2>&1; then
  curl -sL "$URL" -o "$ARCHIVE" || { echo "下载失败"; exit 1; }
elif command -v wget >/dev/null 2>&1; then
  wget -q "$URL" -O "$ARCHIVE" || { echo "下载失败"; exit 1; }
else
  echo "需要 curl 或 wget"
  exit 1
fi

# Extract
echo "解压..."
tar -xzf "$ARCHIVE"
EXTRACTED_DIR=$(find . -maxdepth 1 -type d | grep -v '^\.$' | head -1)

# Install
echo "安装到 ${BIN_DIR}/${BINARY_NAME}..."
mkdir -p "${BIN_DIR}" "${INSTALL_DIR}" "${LOG_DIR}"
cp "${EXTRACTED_DIR}/${BINARY_NAME}" "${BIN_DIR}/"
cp "${EXTRACTED_DIR}/${SYSTEM_NAME}.service" "/${SERVICE_DIR}/" 2>/dev/null || true

# Create default config
if [ ! -f "${INSTALL_DIR}/config.yaml" ]; then
  mkdir -p "${INSTALL_DIR}"
  cat > "${INSTALL_DIR}/config.yaml" << 'EOF'
api_host: "http://localhost:8080"
api_key: "your-api-key-here"
node_id: 1
node_type: "sing-box"
binary_path: "/usr/local/bin/sing-box"
singbox_config: "/etc/pupmsub/sing-box.json"
data_dir: "/etc/pupmsub"
log_path: "/var/log/pupmsub/pupmsub.log"
log_level: "info"
web_port: 2053
username: "admin"
password: "admin"
heartbeat_interval: "30s"
sync_interval: "60s"
EOF
  echo "默认配置已写入 ${INSTALL_DIR}/config.yaml"
  echo "请编辑配置："
  echo "  1. api_host: 填写 xboard 面板地址"
  echo "  2. api_key: 填写节点密钥"
  echo "  3. web_port: 管理面板端口（默认 2053）"
fi

# Install sing-box if not present
if [ ! -f "/usr/local/bin/sing-box" ]; then
  echo "正在安装 sing-box..."
  SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-${PLATFORM}.tar.gz"
  if command -v curl >/dev/null 2>&1; then
    curl -sL "$SINGBOX_URL" -o /tmp/sing-box.tar.gz
  else
    wget -q "$SINGBOX_URL" -O /tmp/sing-box.tar.gz
  fi
  tar -xzf /tmp/sing-box.tar.gz -C /usr/local/bin sing-box
  chmod +x /usr/local/bin/sing-box
  rm -f /tmp/sing-box.tar.gz
  echo "sing-box 安装完成"
fi

# Reload systemd
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
  systemctl enable ${SYSTEM_NAME}
  echo "${SYSTEM_NAME} 服务已安装并设置为开机启动"
fi

# Cleanup
cd /
rm -rf "$TMP_DIR"

echo ""
echo "=== ${NAME} 安装完成 ==="
echo "服务:   systemctl start ${SYSTEM_NAME}"
echo "状态:   systemctl status ${SYSTEM_NAME}"
echo "日志:   journalctl -u ${SYSTEM_NAME} -f"
echo "管理面板: http://localhost:2053"
echo ""
echo "首次使用请编辑 ${INSTALL_DIR}/config.yaml 配置 xboard 地址和密钥"
