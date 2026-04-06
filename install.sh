#!/bin/bash
#
# pupmsub One-Click Installer with Interactive Setup Wizard
# Usage: curl -fsSL https://raw.githubusercontent.com/pupmme/pupmsub/main/install.sh | bash
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
REPO="pupmme/pupmsub"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/pupmsub"
DATA_DIR="/var/lib/pupmsub"
LOG_DIR="/var/log/pupmsub"
SERVICE_NAME="pupmsub"

# Detect architecture
detect_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64)     echo "amd64" ;;
        aarch64)    echo "arm64" ;;
        armv7l)     echo "armv7" ;;
        *)          echo "unknown" ;;
    esac
}

# Detect OS
 detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo $ID
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Print banner
print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ____             __  __       __ 
   / __ \__  _______/ / / /______/ /_
  / /_/ / / / / ___/ / / / ___/ __/
 / ____/ /_/ (__  ) /_/ (__  ) /_  
/_/    \__, /____/\____/____/\__/  
      /____/                        
EOF
    echo -e "${NC}"
    echo -e "${GREEN}One-Click Installer v1.0.0${NC}"
    echo -e "${BLUE}https://github.com/pupmme/pupmsub${NC}"
    echo ""
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Please run as root (use sudo)${NC}"
        exit 1
    fi
}

# Check dependencies
check_deps() {
    local deps=("curl" "systemctl")
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            echo -e "${RED}Error: $dep is required but not installed.${NC}"
            exit 1
        fi
    done
}

# Install sing-box if not present
install_singbox() {
    if command -v sing-box &> /dev/null; then
        echo -e "${GREEN}✓ sing-box already installed: $(sing-box version | head -1)${NC}"
        return
    fi

    echo -e "${YELLOW}→ Installing sing-box...${NC}"
    
    local os=$(detect_os)
    local arch=$(detect_arch)
    
    # Use official sing-box install script
    bash <(curl -fsSL https://sing-box.app/deb-install.sh) 2>/dev/null || \
    bash <(curl -fsSL https://sing-box.app/rpm-install.sh) 2>/dev/null || {
        echo -e "${RED}Failed to install sing-box. Please install manually.${NC}"
        exit 1
    }
    
    echo -e "${GREEN}✓ sing-box installed${NC}"
}

# Download and install pupmsub
install_pupmsub() {
    echo -e "${YELLOW}→ Installing pupmsub...${NC}"
    
    local arch=$(detect_arch)
    if [ "$arch" = "unknown" ]; then
        echo -e "${RED}Error: Unsupported architecture: $(uname -m)${NC}"
        exit 1
    fi
    
    # Create directories
    mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
    
    # Download latest release
    local download_url="https://github.com/${REPO}/releases/latest/download/pupmsub-linux-${arch}"
    
    echo -e "${BLUE}  Downloading from: $download_url${NC}"
    
    if curl -fsSL "$download_url" -o "$INSTALL_DIR/pupmsub"; then
        chmod +x "$INSTALL_DIR/pupmsub"
        echo -e "${GREEN}✓ pupmsub installed to $INSTALL_DIR/pupmsub${NC}"
    else
        # Fallback: build from source
        echo -e "${YELLOW}  Binary not found, building from source...${NC}"
        install_from_source
    fi
    
    # Install service file
    install_service
}

# Build from source
install_from_source() {
    if ! command -v go &> /dev/null; then
        echo -e "${RED}Error: Go is required to build from source${NC}"
        echo -e "${YELLOW}Please install Go 1.23+ or download a pre-built binary${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}  Building from source (this may take a few minutes)...${NC}"
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    git clone --depth 1 "https://github.com/${REPO}.git" . 2>/dev/null || {
        echo -e "${RED}Failed to clone repository${NC}"
        exit 1
    }
    
    go build -o "$INSTALL_DIR/pupmsub" . 2>&1 | tail -20
    
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✓ Built and installed pupmsub${NC}"
}

# Install systemd service
install_service() {
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=pupmsub - Sing-box Node Manager
Documentation=https://github.com/pupmme/pupmsub
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/pupmsub run
Restart=on-failure
RestartSec=5
StandardOutput=append:$LOG_DIR/pupmsub.log
StandardError=append:$LOG_DIR/pupmsub.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo -e "${GREEN}✓ Systemd service installed${NC}"
}

# Interactive configuration wizard
run_wizard() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                   Initial Configuration Wizard                 ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local config_file="$CONFIG_DIR/config.yaml"
    
    # API Configuration
    echo -e "${YELLOW}Step 1: Xboard API Configuration${NC}"
    echo -e "${BLUE}Enter your Xboard panel API details:${NC}"
    echo ""
    
    read -p "  API Host (e.g., https://panel.example.com): " api_host
    while [ -z "$api_host" ]; do
        echo -e "${RED}  API Host is required${NC}"
        read -p "  API Host: " api_host
    done
    
    read -p "  API Key: " api_key
    while [ -z "$api_key" ]; do
        echo -e "${RED}  API Key is required${NC}"
        read -p "  API Key: " api_key
    done
    
    read -p "  Node ID (default: 1): " node_id
    node_id=${node_id:-1}
    
    read -p "  Node Type (default: sing-box): " node_type
    node_type=${node_type:-sing-box}
    
    echo ""
    echo -e "${YELLOW}Step 2: Web Panel Settings${NC}"
    echo -e "${BLUE}Configure the local management web panel:${NC}"
    echo ""
    
    read -p "  Web Port (default: 2053): " web_port
    web_port=${web_port:-2053}
    
    read -p "  Admin Username (default: admin): " username
    username=${username:-admin}
    
    read -sp "  Admin Password (default: admin): " password
    echo ""
    password=${password:-admin}
    
    echo ""
    echo -e "${YELLOW}Step 3: Advanced Settings (optional)${NC}"
    echo ""
    
    read -p "  Sing-box binary path (default: /usr/local/bin/sing-box): " binary_path
    binary_path=${binary_path:-/usr/local/bin/sing-box}
    
    read -p "  Config path (default: /etc/pupmsub/sing-box.json): " config_path
    config_path=${config_path:-/etc/pupmsub/sing-box.json}
    
    # Generate config
    cat > "$config_file" << EOF
# pupmsub Configuration File
# Generated by install.sh on $(date)

api_host: "$api_host"
api_key: "$api_key"
node_id: $node_id
node_type: "$node_type"
binary_path: "$binary_path"
singbox_config: "$config_path"
data_dir: "$DATA_DIR"
log_path: "$LOG_DIR/pupmsub.log"
log_level: info
web_port: $web_port
username: "$username"
password: "$password"
heartbeat_interval: 30s
sync_interval: 60s
EOF
    
    chmod 600 "$config_file"
    echo -e "${GREEN}✓ Configuration saved to $config_file${NC}"
    
    # Create initial sing-box config
    mkdir -p "$(dirname "$config_path")"
    cat > "$config_path" << 'EOF'
{
  "log": {
    "level": "warn"
  },
  "inbounds": [],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rules": [
      { "protocol": ["bittorrent"], "outbound": "block" }
    ]
  }
}
EOF
    echo -e "${GREEN}✓ Initial sing-box config created${NC}"
}

# Start service
start_service() {
    echo ""
    echo -e "${YELLOW}→ Starting pupmsub service...${NC}"
    
    systemctl enable "$SERVICE_NAME" --now
    
    sleep 2
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}✓ Service started successfully${NC}"
    else
        echo -e "${RED}✗ Service failed to start${NC}"
        echo -e "${YELLOW}Check logs: journalctl -u $SERVICE_NAME -n 50${NC}"
    fi
}

# Print completion info
print_completion() {
    local ip=$(hostname -I | awk '{print $1}')
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              Installation Complete!                            ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Management Web Panel:${NC}"
    echo -e "  URL:      ${YELLOW}http://${ip}:$(grep web_port $CONFIG_DIR/config.yaml | awk '{print $2}')${NC}"
    echo -e "  Username: $(grep username $CONFIG_DIR/config.yaml | awk '{print $2}')"
    echo -e "  Password: [hidden]"
    echo ""
    echo -e "${CYAN}Useful Commands:${NC}"
    echo -e "  ${YELLOW}systemctl status $SERVICE_NAME${NC}  - Check service status"
    echo -e "  ${YELLOW}systemctl restart $SERVICE_NAME${NC} - Restart service"
    echo -e "  ${YELLOW}journalctl -u $SERVICE_NAME -f${NC}  - View logs"
    echo -e "  ${YELLOW}$INSTALL_DIR/pupmsub --help${NC}      - CLI help"
    echo ""
    echo -e "${CYAN}Configuration Files:${NC}"
    echo -e "  Main config:  $CONFIG_DIR/config.yaml"
    echo -e "  Sing-box:     $(grep singbox_config $CONFIG_DIR/config.yaml | awk '{print $2}')"
    echo -e "  Logs:         $LOG_DIR/pupmsub.log"
    echo ""
    echo -e "${GREEN}Enjoy using pupmsub!${NC}"
    echo ""
}

# Main installation flow
main() {
    print_banner
    check_root
    check_deps
    
    echo -e "${CYAN}Detected:${NC} OS=$(detect_os), Arch=$(detect_arch)"
    echo ""
    
    # Install components
    install_singbox
    install_pupmsub
    
    # Run interactive wizard
    run_wizard
    
    # Start service
    start_service
    
    # Print completion
    print_completion
}

# Run main
main "$@"
