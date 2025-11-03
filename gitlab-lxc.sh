#!/usr/bin/env bash

# GitLab CE Installation Script for Proxmox LXC Container
# Interactive version with storage selection and verbose mode

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Verbose mode (set to 1 to enable)
VERBOSE=${VERBOSE:-0}
SILENT_MODE=""

# Check if whiptail is available for GUI
if command -v whiptail &> /dev/null; then
    HAS_WHIPTAIL=1
else
    HAS_WHIPTAIL=0
fi

# Functions
msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

msg_ok() {
    echo -e "${GREEN}[✓]${NC} $1"
}

msg_error() {
    echo -e "${RED}[✗]${NC} $1"
    exit 1
}

msg_warn() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

msg_verbose() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

show_header() {
    clear
    echo -e "${GREEN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║       _____ _ _   _           _                          ║
║      / ____(_) | | |         | |                         ║
║     | |  __ _| |_| |     __ _| |__                       ║
║     | | |_ | | __| |    / _` | '_ \                      ║
║     | |__| | | |_| |___| (_| | |_) |                     ║
║      \_____|_|\__|______\__,_|_.__/                      ║
║                                                           ║
║          GitLab CE for Proxmox LXC                        ║
║              Interactive Installer                        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check if running as root on Proxmox host
if [ "$EUID" -ne 0 ]; then 
    msg_error "Please run as root"
fi

if ! command -v pveversion &> /dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
fi

# Install whiptail if not present
if [ "$HAS_WHIPTAIL" -eq 0 ]; then
    msg_info "Installing whiptail for better user interface..."
    apt-get update > /dev/null 2>&1
    apt-get install -y whiptail > /dev/null 2>&1
    HAS_WHIPTAIL=1
    msg_ok "Whiptail installed"
fi

show_header

# Get next available CTID
NEXT_CTID=$(pvesh get /cluster/nextid)

# Interactive configuration
if [ "$HAS_WHIPTAIL" -eq 1 ]; then
    # Container ID
    CTID=$(whiptail --inputbox "Container ID (100-999999):" 10 60 "$NEXT_CTID" --title "Container Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # Hostname
    HOSTNAME=$(whiptail --inputbox "Container Hostname:" 10 60 "gitlab" --title "Container Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # CPU Cores
    CORES=$(whiptail --inputbox "CPU Cores:" 10 60 "4" --title "Container Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # Memory
    MEMORY=$(whiptail --inputbox "Memory (MB):" 10 60 "8192" --title "Container Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # Swap
    SWAP=$(whiptail --inputbox "Swap (MB):" 10 60 "2048" --title "Container Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # Disk Size
    DISK_SIZE=$(whiptail --inputbox "Disk Size (GB):" 10 60 "30" --title "Container Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # Get available storage pools
    msg_verbose "Getting available storage pools..."
    STORAGE_LIST=$(pvesm status -content rootdir | awk 'NR>1 {print $1, "(" $2 ")", "OFF"}')
    
    if [ -z "$STORAGE_LIST" ]; then
        msg_error "No storage pools available for containers"
    fi
    
    # Storage selection
    STORAGE=$(whiptail --radiolist "Select Storage for Container:" 20 70 10 \
        $STORAGE_LIST \
        --title "Storage Selection" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # Template Storage selection
    TEMPLATE_STORAGE_LIST=$(pvesm status -content vztmpl | awk 'NR>1 {print $1, "(" $2 ")", "OFF"}')
    
    TEMPLATE_STORAGE=$(whiptail --radiolist "Select Storage for Templates:" 20 70 10 \
        $TEMPLATE_STORAGE_LIST \
        --title "Template Storage Selection" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # Network Bridge
    BRIDGE_LIST=$(ip -br link show type bridge | awk '{print $1, "(" $2 ")", "OFF"}')
    
    BRIDGE=$(whiptail --radiolist "Select Network Bridge:" 20 70 10 \
        $BRIDGE_LIST \
        --title "Network Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # GitLab External URL
    GITLAB_EXTERNAL_URL=$(whiptail --inputbox "GitLab External URL:\n(Will be auto-detected if left as default)" 12 70 "http://gitlab.local" --title "GitLab Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # GitLab Root Email
    GITLAB_ROOT_EMAIL=$(whiptail --inputbox "GitLab Root Email:" 10 60 "admin@home.local" --title "GitLab Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # GitLab Root Password
    GITLAB_ROOT_PASSWORD=$(whiptail --passwordbox "GitLab Root Password:" 10 60 "admin" --title "GitLab Configuration" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit 0; fi
    
    # Verbose mode
    if whiptail --yesno "Enable verbose mode?\n(Show detailed installation steps)" 10 60 --title "Verbose Mode"; then
        VERBOSE=1
    else
        VERBOSE=0
    fi
    
    # Confirmation
    if ! whiptail --yesno "Ready to create GitLab container with these settings?\n\n\
Container ID: $CTID\n\
Hostname: $HOSTNAME\n\
CPU: $CORES cores\n\
Memory: ${MEMORY}MB\n\
Disk: ${DISK_SIZE}GB\n\
Storage: $STORAGE\n\
Bridge: $BRIDGE\n\
GitLab URL: $GITLAB_EXTERNAL_URL\n\
Root Email: $GITLAB_ROOT_EMAIL\n\
Verbose: $([ $VERBOSE -eq 1 ] && echo 'Yes' || echo 'No')" 20 70 --title "Confirm Configuration"; then
        msg_warn "Installation cancelled by user"
        exit 0
    fi
    
else
    # Fallback to non-interactive mode
    CTID=${CTID:-$NEXT_CTID}
    HOSTNAME=${HOSTNAME:-gitlab}
    CORES=${CORES:-4}
    MEMORY=${MEMORY:-8192}
    SWAP=${SWAP:-2048}
    DISK_SIZE=${DISK_SIZE:-30}
    STORAGE=${STORAGE:-local-lvm}
    TEMPLATE_STORAGE=${TEMPLATE_STORAGE:-local}
    BRIDGE=${BRIDGE:-vmbr0}
    GITLAB_EXTERNAL_URL=${GITLAB_EXTERNAL_URL:-http://gitlab.local}
    GITLAB_ROOT_EMAIL=${GITLAB_ROOT_EMAIL:-admin@home.local}
    GITLAB_ROOT_PASSWORD=${GITLAB_ROOT_PASSWORD:-admin}
fi

# Set silent mode for commands if verbose is disabled
if [ "$VERBOSE" -eq 0 ]; then
    SILENT_MODE="> /dev/null 2>&1"
fi

DEBIAN_VERSION=12

show_header

echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
echo -e "${MAGENTA}  Installation Configuration${NC}"
echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Container Settings:${NC}"
echo -e "  Container ID: ${YELLOW}$CTID${NC}"
echo -e "  Hostname: ${YELLOW}$HOSTNAME${NC}"
echo -e "  CPU Cores: ${YELLOW}$CORES${NC}"
echo -e "  Memory: ${YELLOW}${MEMORY}MB${NC}"
echo -e "  Swap: ${YELLOW}${SWAP}MB${NC}"
echo -e "  Disk: ${YELLOW}${DISK_SIZE}GB${NC}"
echo -e "  Storage: ${YELLOW}$STORAGE${NC}"
echo -e "  Template Storage: ${YELLOW}$TEMPLATE_STORAGE${NC}"
echo -e "  Bridge: ${YELLOW}$BRIDGE${NC}"
echo -e ""
echo -e "${CYAN}GitLab Settings:${NC}"
echo -e "  External URL: ${YELLOW}$GITLAB_EXTERNAL_URL${NC}"
echo -e "  Root Email: ${YELLOW}$GITLAB_ROOT_EMAIL${NC}"
echo -e "  Verbose Mode: ${YELLOW}$([ $VERBOSE -eq 1 ] && echo 'Enabled' || echo 'Disabled')${NC}"
echo -e "${MAGENTA}═══════════════════════════════════════════════════════════${NC}"
echo ""

sleep 2

# Download Debian template if not exists
msg_info "Checking for Debian $DEBIAN_VERSION template..."
msg_verbose "Looking for template in storage: $TEMPLATE_STORAGE"

TEMPLATE="debian-${DEBIAN_VERSION}-standard_${DEBIAN_VERSION}.7-1_amd64.tar.zst"
TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

if ! pveam list $TEMPLATE_STORAGE | grep -q $TEMPLATE; then
    msg_info "Downloading Debian $DEBIAN_VERSION template..."
    msg_verbose "Executing: pveam download $TEMPLATE_STORAGE $TEMPLATE"
    
    if [ "$VERBOSE" -eq 1 ]; then
        pveam download $TEMPLATE_STORAGE $TEMPLATE
    else
        pveam download $TEMPLATE_STORAGE $TEMPLATE > /dev/null 2>&1
    fi
    
    msg_ok "Template downloaded"
else
    msg_ok "Template already exists"
fi

# Create container
msg_info "Creating LXC container $CTID..."
msg_verbose "Container specifications:"
msg_verbose "  - OS: Debian $DEBIAN_VERSION"
msg_verbose "  - Type: Unprivileged"
msg_verbose "  - Features: nesting=1"
msg_verbose "  - Network: DHCP on $BRIDGE"

CREATE_CMD="pct create $CTID $TEMPLATE_PATH \
    --hostname $HOSTNAME \
    --cores $CORES \
    --memory $MEMORY \
    --swap $SWAP \
    --rootfs $STORAGE:$DISK_SIZE \
    --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
    --unprivileged 1 \
    --features nesting=1 \
    --onboot 1 \
    --ostype debian \
    --password=\"\$(openssl rand -base64 12)\""

msg_verbose "Executing: $CREATE_CMD"

if [ "$VERBOSE" -eq 1 ]; then
    eval $CREATE_CMD
else
    eval $CREATE_CMD > /dev/null 2>&1
fi

msg_ok "Container $CTID created"

# Start container
msg_info "Starting container..."
msg_verbose "Executing: pct start $CTID"

if [ "$VERBOSE" -eq 1 ]; then
    pct start $CTID
else
    pct start $CTID > /dev/null 2>&1
fi

sleep 10
msg_ok "Container started"

# Wait for container to be ready
msg_info "Waiting for container to be ready..."
for i in {1..30}; do
    msg_verbose "Checking container readiness (attempt $i/30)..."
    if pct exec $CTID -- test -f /bin/bash 2>/dev/null; then
        break
    fi
    sleep 2
done
msg_ok "Container is ready"

# Get container IP
msg_info "Getting container IP address..."
sleep 5

CONTAINER_IP=$(pct exec $CTID -- ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")

if [ -z "$CONTAINER_IP" ]; then
    msg_warn "Could not determine IP address automatically"
    CONTAINER_IP="<IP_ADDRESS>"
else
    msg_verbose "Container IP detected: $CONTAINER_IP"
    msg_ok "Container IP: $CONTAINER_IP"
fi

# Update GITLAB_EXTERNAL_URL if it's still default
if [ "$GITLAB_EXTERNAL_URL" = "http://gitlab.local" ]; then
    GITLAB_EXTERNAL_URL="http://${CONTAINER_IP}"
    msg_verbose "Updated GitLab External URL to: $GITLAB_EXTERNAL_URL"
fi

# Install GitLab
msg_info "Installing GitLab CE (this will take 10-15 minutes)..."
msg_verbose "Starting GitLab installation process in container..."

# Progress indicator for verbose mode
if [ "$VERBOSE" -eq 1 ]; then
    echo -e "${CYAN}Installation Steps:${NC}"
    echo "  1. Updating system packages"
    echo "  2. Installing dependencies"
    echo "  3. Adding GitLab repository"
    echo "  4. Installing GitLab CE"
    echo "  5. Configuring GitLab"
    echo "  6. Running initial reconfigure"
    echo ""
fi

pct exec $CTID -- bash <<EOFINSTALL
set -e

VERBOSE=$VERBOSE

msg_verbose() {
    if [ "\$VERBOSE" -eq 1 ]; then
        echo "[VERBOSE] \$1"
    fi
}

echo "[1/6] Updating system..."
msg_verbose "Executing: apt-get update"
if [ "\$VERBOSE" -eq 1 ]; then
    apt-get update
else
    apt-get update > /dev/null 2>&1
fi

msg_verbose "Executing: apt-get upgrade"
if [ "\$VERBOSE" -eq 1 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
else
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y > /dev/null 2>&1
fi

echo "[2/6] Installing dependencies..."
msg_verbose "Installing: curl, openssh-server, ca-certificates, tzdata, perl, postfix"
if [ "\$VERBOSE" -eq 1 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl openssh-server ca-certificates tzdata perl postfix
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl openssh-server ca-certificates tzdata perl postfix > /dev/null 2>&1
fi

msg_verbose "Installing: apt-transport-https, gnupg2"
if [ "\$VERBOSE" -eq 1 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        apt-transport-https gnupg2
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        apt-transport-https gnupg2 > /dev/null 2>&1
fi

echo "[3/6] Adding GitLab repository..."
msg_verbose "Downloading GitLab repository script"
if [ "\$VERBOSE" -eq 1 ]; then
    curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
else
    curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash > /dev/null 2>&1
fi

echo "[4/6] Installing GitLab CE (please wait, this takes time)..."
msg_verbose "This step downloads and installs GitLab CE package"
export EXTERNAL_URL="$GITLAB_EXTERNAL_URL"
if [ "\$VERBOSE" -eq 1 ]; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-ce
else
    DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-ce > /dev/null 2>&1
fi

echo "[5/6] Configuring GitLab..."
msg_verbose "Writing configuration to /etc/gitlab/gitlab.rb"
cat >> /etc/gitlab/gitlab.rb <<'EOFCONFIG'

# Custom Configuration
gitlab_rails['initial_root_password'] = '$GITLAB_ROOT_PASSWORD'
gitlab_rails['gitlab_signup_enabled'] = false
gitlab_rails['gitlab_default_can_create_group'] = true
gitlab_rails['gitlab_username_changing_enabled'] = false

# Email configuration
gitlab_rails['gitlab_email_enabled'] = true
gitlab_rails['gitlab_email_from'] = '$GITLAB_ROOT_EMAIL'
gitlab_rails['gitlab_email_display_name'] = 'GitLab'
gitlab_rails['gitlab_email_reply_to'] = '$GITLAB_ROOT_EMAIL'

# Time zone
gitlab_rails['time_zone'] = 'Europe/Paris'

# Backup configuration
gitlab_rails['backup_keep_time'] = 604800

# Performance tuning for LXC
postgresql['shared_buffers'] = "256MB"
postgresql['max_worker_processes'] = 8
sidekiq['max_concurrency'] = 10
puma['worker_processes'] = 2
prometheus_monitoring['enable'] = true
EOFCONFIG

echo "[6/6] Running GitLab reconfigure (5-10 minutes)..."
msg_verbose "Executing: gitlab-ctl reconfigure"
if [ "\$VERBOSE" -eq 1 ]; then
    gitlab-ctl reconfigure
else
    gitlab-ctl reconfigure > /dev/null 2>&1
fi

msg_verbose "Starting GitLab services"
if [ "\$VERBOSE" -eq 1 ]; then
    gitlab-ctl start
else
    gitlab-ctl start > /dev/null 2>&1
fi

echo "Waiting for GitLab to be ready..."
sleep 30
for i in {1..30}; do
    if curl -sf http://localhost/-/readiness > /dev/null 2>&1; then
        echo "GitLab is ready!"
        break
    fi
    msg_verbose "Still waiting for GitLab... (\$i/30)"
    sleep 10
done

msg_verbose "Configuring root user email"
gitlab-rails runner "user = User.find_by(username: 'root'); user.email = '$GITLAB_ROOT_EMAIL'; user.save!" > /dev/null 2>&1 || true

echo "Cleaning up..."
if [ "\$VERBOSE" -eq 1 ]; then
    apt-get autoremove -y
    apt-get autoclean -y
else
    apt-get autoremove -y > /dev/null 2>&1
    apt-get autoclean -y > /dev/null 2>&1
fi

echo "GitLab installation completed!"
EOFINSTALL

msg_ok "GitLab CE installed and configured"

# Create info file in container
msg_verbose "Creating information file in container"
pct exec $CTID -- bash <<EOFINFO
cat > /root/gitlab-info.txt <<'EOFCREDS'
GitLab CE Installation Information
===================================

Access URL: $GITLAB_EXTERNAL_URL
IP Address: $CONTAINER_IP

Default Credentials:
--------------------
Username: root
Email: $GITLAB_ROOT_EMAIL
Password: $GITLAB_ROOT_PASSWORD

⚠️  IMPORTANT: Change the root password immediately after first login!

Useful Commands:
----------------
gitlab-ctl status          # Check service status
gitlab-ctl restart         # Restart all services
gitlab-ctl reconfigure     # Reconfigure after editing /etc/gitlab/gitlab.rb
gitlab-ctl tail            # View logs
gitlab-rake gitlab:check   # Health check
gitlab-backup create       # Create backup

Configuration File:
-------------------
/etc/gitlab/gitlab.rb

For more information, visit: https://docs.gitlab.com/
EOFCREDS
EOFINFO

msg_ok "Installation completed successfully!"

# Final summary
show_header

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 GitLab CE Installation Complete! 🎉${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Container Details:${NC}"
echo -e "  Container ID: ${YELLOW}$CTID${NC}"
echo -e "  Hostname: ${YELLOW}$HOSTNAME${NC}"
echo -e "  IP Address: ${YELLOW}$CONTAINER_IP${NC}"
echo -e "  Storage: ${YELLOW}$STORAGE${NC}"
echo -e "  Bridge: ${YELLOW}$BRIDGE${NC}"
echo ""
echo -e "${CYAN}Access GitLab:${NC}"
echo -e "  URL: ${GREEN}$GITLAB_EXTERNAL_URL${NC}"
echo ""
echo -e "${CYAN}Default Credentials:${NC}"
echo -e "  Username: ${YELLOW}root${NC}"
echo -e "  Email: ${YELLOW}$GITLAB_ROOT_EMAIL${NC}"
echo -e "  Password: ${YELLOW}$GITLAB_ROOT_PASSWORD${NC}"
echo ""
echo -e "${RED}⚠️  SECURITY WARNING:${NC}"
echo -e "  ${RED}Change the root password immediately after first login!${NC}"
echo ""
echo -e "${CYAN}Useful Commands:${NC}"
echo -e "  ${YELLOW}pct enter $CTID${NC}               - Enter container"
echo -e "  ${YELLOW}pct exec $CTID -- gitlab-ctl status${NC} - Check status"
echo -e "  ${YELLOW}pct exec $CTID -- gitlab-ctl tail${NC}   - View logs"
echo ""
echo -e "${BLUE}Note:${NC} GitLab may take a few minutes to fully start."
echo -e "      Wait 5-10 minutes before accessing the web interface."
echo ""
echo -e "${CYAN}Credentials saved in container:${NC} /root/gitlab-info.txt"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""

# Optional: Open in browser
if command -v xdg-open &> /dev/null; then
    read -p "Open GitLab in browser? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        xdg-open "$GITLAB_EXTERNAL_URL"
    fi
fi