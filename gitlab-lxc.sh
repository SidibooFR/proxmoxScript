#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT
# GitLab CE Installation Script for Proxmox LXC

APP="GitLab-CE"
var_tags="${var_tags:-git;devops;ci-cd}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

# GitLab specific variables
GITLAB_EXTERNAL_URL="${GITLAB_EXTERNAL_URL:-http://gitlab.local}"
GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-admin}"
GITLAB_ROOT_EMAIL="${GITLAB_ROOT_EMAIL:-admin@home.local}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  
  if [ ! -f /etc/gitlab/gitlab.rb ]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  
  msg_info "Updating ${APP}"
  $STD apt-get update
  $STD apt-get upgrade -y gitlab-ce
  msg_ok "Updated ${APP}"
  
  msg_info "Running GitLab reconfigure"
  $STD gitlab-ctl reconfigure
  msg_ok "Updated Successfully!"
  exit 0
}

start
build_container
description

msg_info "Setting up Container OS"
$STD apt-get update
$STD apt-get install -y \
  curl \
  openssh-server \
  ca-certificates \
  tzdata \
  perl \
  postfix
msg_ok "Set up Container OS"

msg_info "Installing GitLab Dependencies"
$STD apt-get install -y \
  apt-transport-https \
  gnupg2
msg_ok "Installed Dependencies"

msg_info "Adding GitLab Repository"
curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
msg_ok "Added GitLab Repository"

msg_info "Installing GitLab CE (this may take several minutes)"
EXTERNAL_URL="$GITLAB_EXTERNAL_URL" $STD apt-get install -y gitlab-ce
msg_ok "Installed GitLab CE"

msg_info "Configuring GitLab"
cat > /etc/gitlab/initial_root_password <<EOF
# WARNING: This value is valid only in the following conditions
#          1. If provided manually (either via \`GITLAB_ROOT_PASSWORD\` environment variable or via \`gitlab_rails['initial_root_password']\` setting in \`gitlab.rb\`, it was provided before database was seeded for the first time (usually, the first reconfigure run).
#          2. Password hasn't been changed manually, either via UI or via command line.
#
#          If the password shown here doesn't work, you must reset the admin password following https://docs.gitlab.com/ee/security/reset_user_password.html#reset-your-root-password.

Password: $GITLAB_ROOT_PASSWORD

# NOTE: This file will be automatically deleted in the first reconfigure run after 24 hours.
EOF

# Configure GitLab settings
cat >> /etc/gitlab/gitlab.rb <<EOF

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
EOF

msg_ok "Configured GitLab"

msg_info "Running GitLab Reconfigure"
$STD gitlab-ctl reconfigure
msg_ok "GitLab Reconfigured"

msg_info "Starting GitLab Services"
$STD gitlab-ctl start
msg_ok "Started GitLab Services"

msg_info "Waiting for GitLab to be ready"
sleep 30
until curl -sf http://localhost/-/readiness > /dev/null 2>&1; do
  echo "Waiting for GitLab to be ready..."
  sleep 10
done
msg_ok "GitLab is ready"

msg_info "Setting up root user"
gitlab-rails runner "user = User.find_by(username: 'root'); user.email = '$GITLAB_ROOT_EMAIL'; user.save!"
msg_ok "Root user configured"

msg_info "Cleaning Up"
$STD apt-get autoremove -y
$STD apt-get autoclean -y
msg_ok "Cleaned"

# Create version file
GITLAB_VERSION=$(gitlab-rake gitlab:env:info | grep "GitLab information" -A 20 | grep "GitLab:" | awk '{print $2}')
echo "${GITLAB_VERSION}" > /opt/${APP}_version.txt

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${GITLAB_EXTERNAL_URL}${CL}"
echo -e ""
echo -e "${INFO}${YW} Default credentials:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Username: root${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Email: ${GITLAB_ROOT_EMAIL}${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Password: ${GITLAB_ROOT_PASSWORD}${CL}"
echo -e ""
echo -e "${INFO}${YW} Important commands:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}gitlab-ctl status${CL}      - Check status"
echo -e "${TAB}${GATEWAY}${BGN}gitlab-ctl restart${CL}     - Restart GitLab"
echo -e "${TAB}${GATEWAY}${BGN}gitlab-ctl reconfigure${CL} - Reconfigure GitLab"
echo -e "${TAB}${GATEWAY}${BGN}gitlab-rake gitlab:check${CL} - Health check"
echo -e ""
echo -e "${INFO}${YW} Note: GitLab may take a few minutes to fully start${CL}"
