#!/usr/bin/env bash

# GitLab CE Installation Script for Proxmox LXC Container
# This script creates and configures a Debian 12 LXC container with GitLab CE

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
CTID=${CTID:-$(pvesh get /cluster/nextid)}
HOSTNAME=${HOSTNAME:-gitlab}
DISK_SIZE=${DISK_SIZE:-30}
CORES=${CORES:-4}
MEMORY=${MEMORY:-8192}
SWAP=${SWAP:-2048}
STORAGE=${STORAGE:-local-lvm}
TEMPLATE_STORAGE=${TEMPLATE_STORAGE:-local}
BRIDGE=${BRIDGE:-vmbr0}
DEBIAN_VERSION=${DEBIAN_VERSION:-12}

# GitLab Configuration
GITLAB_EXTERNAL_URL=${GITLAB_EXTERNAL_URL:-http://gitlab.local}
GITLAB_ROOT_PASSWORD=${GITLAB_ROOT_PASSWORD:-admin}
GITLAB_ROOT_EMAIL=${GITLAB_ROOT_EMAIL:-admin@home.local}

# Functions
msg_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

msg_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

msg_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

msg_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if running as root on Proxmox host
if [ "$EUID" -ne 0 ]; then 
    msg_error "Please run as root"
fi

if ! command -v pveversion &> /dev/null; then
    msg_error "This script must be run on a Proxmox VE host"
fi

echo -e "${GREEN}"
cat << "EOF"
   _____ _ _   _           _     
  / ____(_) | | |         | |    
 | |  __ _| |_| |     __ _| |__  
 | | |_ | | __| |    / _` | '_ \ 
 | |__| | | |_| |___| (_| | |_) |
  \_____|_|\__|______\__,_|_.__/ 
                                  
  GitLab CE for Proxmox LXC
EOF
echo -e "${NC}"

msg_info "Configuration:"
echo "  Container ID: $CTID"
echo "  Hostname: $HOSTNAME"
echo "  Disk: ${DISK_SIZE}GB"
echo "  CPU Cores: $CORES"
echo "  Memory: ${MEMORY}MB"
echo "  Storage: $STORAGE"
echo "  Bridge: $BRIDGE"
echo "  GitLab URL: $GITLAB_EXTERNAL_URL"
echo ""
read -p "Press Enter to continue or Ctrl+C to abort..."

# Download Debian template if not exists
msg_info "Checking for Debian $DEBIAN_VERSION template..."
TEMPLATE="debian-${DEBIAN_VERSION}-standard_${DEBIAN_VERSION}.7-1_amd64.tar.zst"
TEMPLATE_PATH="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

if ! pveam list $TEMPLATE_STORAGE | grep -q $TEMPLATE; then
    msg_info "Downloading Debian $DEBIAN_VERSION template..."
    pveam download $TEMPLATE_STORAGE $TEMPLATE
    msg_ok "Template downloaded"
else
    msg_ok "Template already exists"
fi

# Create container
msg_info "Creating LXC container $CTID..."
pct create $CTID $TEMPLATE_PATH \
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
    --password="$(openssl rand -base64 12)"

msg_ok "Container $CTID created"

# Start container
msg_info "Starting container..."
pct start $CTID
sleep 10
msg_ok "Container started"

# Wait for container to be ready
msg_info "Waiting for container to be ready..."
for i in {1..30}; do
    if pct exec $CTID -- test -f /bin/bash; then
        break
    fi
    sleep 2
done
msg_ok "Container is ready"

# Get container IP
msg_info "Getting container IP address..."
sleep 5
CONTAINER_IP=$(pct exec $CTID -- ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -z "$CONTAINER_IP" ]; then
    msg_warn "Could not determine IP address automatically"
    CONTAINER_IP="<IP_ADDRESS>"
else
    msg_ok "Container IP: $CONTAINER_IP"
fi

# Update GITLAB_EXTERNAL_URL if it's still default
if [ "$GITLAB_EXTERNAL_URL" = "http://gitlab.local" ]; then
    GITLAB_EXTERNAL_URL="http://${CONTAINER_IP}"
fi

# Install GitLab
msg_info "Installing GitLab CE (this will take 10-15 minutes)..."

pct exec $CTID -- bash <<'EOFINSTALL'
set -e

echo "Updating system..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "Installing dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    openssh-server \
    ca-certificates \
    tzdata \
    perl \
    postfix \
    apt-transport-https \
    gnupg2

echo "Adding GitLab repository..."
curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash

echo "Installing GitLab CE..."
EOFINSTALL

# Pass variables to the container and continue installation
pct exec $CTID -- bash <<EOFINSTALL2
export EXTERNAL_URL="$GITLAB_EXTERNAL_URL"
DEBIAN_FRONTEND=noninteractive apt-get install -y gitlab-ce

echo "Configuring GitLab..."
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

echo "Running GitLab reconfigure (this may take 5-10 minutes)..."
gitlab-ctl reconfigure

echo "Starting GitLab services..."
gitlab-ctl start

echo "Waiting for GitLab to be ready..."
sleep 30
for i in {1..30}; do
    if curl -sf http://localhost/-/readiness > /dev/null 2>&1; then
        echo "GitLab is ready!"
        break
    fi
    echo "Still waiting... (\$i/30)"
    sleep 10
done

echo "Configuring root user..."
gitlab-rails runner "user = User.find_by(username: 'root'); user.email = '$GITLAB_ROOT_EMAIL'; user.save!" || true

echo "Cleaning up..."
apt-get autoremove -y
apt-get autoclean -y

echo "GitLab installation completed!"
EOFINSTALL2

msg_ok "GitLab CE installed and configured"

# Create info file in container
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

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  GitLab CE Installation Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Container Details:${NC}"
echo -e "  Container ID: ${YELLOW}$CTID${NC}"
echo -e "  Hostname: ${YELLOW}$HOSTNAME${NC}"
echo -e "  IP Address: ${YELLOW}$CONTAINER_IP${NC}"
echo ""
echo -e "${BLUE}Access GitLab:${NC}"
echo -e "  URL: ${GREEN}$GITLAB_EXTERNAL_URL${NC}"
echo ""
echo -e "${BLUE}Default Credentials:${NC}"
echo -e "  Username: ${YELLOW}root${NC}"
echo -e "  Email: ${YELLOW}$GITLAB_ROOT_EMAIL${NC}"
echo -e "  Password: ${YELLOW}$GITLAB_ROOT_PASSWORD${NC}"
echo ""
echo -e "${RED}⚠️  IMPORTANT:${NC} Change the root password immediately after first login!"
echo ""
echo -e "${BLUE}Note:${NC} GitLab may take a few minutes to fully start."
echo -e "      Check status: ${YELLOW}pct exec $CTID -- gitlab-ctl status${NC}"
echo ""
echo -e "${BLUE}Credentials saved in container:${NC} /root/gitlab-info.txt"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"