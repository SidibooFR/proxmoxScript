#!/usr/bin/env bash

# Proxmox Storage Diagnostic Script
# Check available storages for LXC containers and templates

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Proxmox Storage Diagnostic Tool                  ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running on Proxmox
if ! command -v pveversion &> /dev/null; then
    echo -e "${RED}[✗] This script must be run on a Proxmox VE host${NC}"
    exit 1
fi

echo -e "${GREEN}[✓] Running on Proxmox VE $(pveversion | grep pve-manager | cut -d'/' -f2)${NC}"
echo ""

# Display all storages
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}All Available Storages${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
pvesm status
echo ""

# Check storages for container root filesystems
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Storages for Container Root Filesystem (rootdir)${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"

ROOTDIR_STORAGES=$(pvesm status -content rootdir | awk 'NR>1 {print $1}')
if [ -z "$ROOTDIR_STORAGES" ]; then
    echo -e "${RED}[✗] No storages available for container root filesystems${NC}"
    echo -e "${YELLOW}    You need at least one storage with 'rootdir' content type${NC}"
else
    echo -e "${GREEN}[✓] Available storages for container root filesystem:${NC}"
    for storage in $ROOTDIR_STORAGES; do
        storage_type=$(pvesm status | grep "^${storage} " | awk '{print $2}')
        storage_avail=$(pvesm status | grep "^${storage} " | awk '{print $5}')
        echo -e "    ${GREEN}●${NC} ${YELLOW}$storage${NC} (Type: $storage_type, Available: $storage_avail)"
    done
    
    RECOMMENDED_STORAGE=$(echo "$ROOTDIR_STORAGES" | head -1)
    echo ""
    echo -e "${BLUE}💡 Recommended for STORAGE variable: ${YELLOW}$RECOMMENDED_STORAGE${NC}"
fi
echo ""

# Check storages for templates
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Storages for Container Templates (vztmpl)${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"

TEMPLATE_STORAGES=$(pvesm status -content vztmpl | awk 'NR>1 {print $1}')
if [ -z "$TEMPLATE_STORAGES" ]; then
    echo -e "${RED}[✗] No storages available for templates${NC}"
    echo -e "${YELLOW}    You need at least one storage with 'vztmpl' content type${NC}"
    echo -e "${YELLOW}    Usually 'local' (type: dir) supports templates${NC}"
else
    echo -e "${GREEN}[✓] Available storages for templates:${NC}"
    for storage in $TEMPLATE_STORAGES; do
        storage_type=$(pvesm status | grep "^${storage} " | awk '{print $2}')
        storage_avail=$(pvesm status | grep "^${storage} " | awk '{print $5}')
        echo -e "    ${GREEN}●${NC} ${YELLOW}$storage${NC} (Type: $storage_type, Available: $storage_avail)"
    done
    
    RECOMMENDED_TEMPLATE_STORAGE=$(echo "$TEMPLATE_STORAGES" | head -1)
    echo ""
    echo -e "${BLUE}💡 Recommended for TEMPLATE_STORAGE variable: ${YELLOW}$RECOMMENDED_TEMPLATE_STORAGE${NC}"
fi
echo ""

# Check network bridges
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Available Network Bridges${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"

BRIDGES=$(ip -br link show type bridge | awk '{print $1}')
if [ -z "$BRIDGES" ]; then
    echo -e "${RED}[✗] No network bridges found${NC}"
else
    echo -e "${GREEN}[✓] Available bridges:${NC}"
    for bridge in $BRIDGES; do
        bridge_state=$(ip -br link show $bridge | awk '{print $2}')
        echo -e "    ${GREEN}●${NC} ${YELLOW}$bridge${NC} (State: $bridge_state)"
    done
    
    RECOMMENDED_BRIDGE=$(echo "$BRIDGES" | head -1)
    echo ""
    echo -e "${BLUE}💡 Recommended for BRIDGE variable: ${YELLOW}$RECOMMENDED_BRIDGE${NC}"
fi
echo ""

# Check for existing Debian templates
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Existing Debian Templates${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"

EXISTING_TEMPLATES=0
for storage in $TEMPLATE_STORAGES; do
    templates=$(pveam list $storage 2>/dev/null | grep "debian-12" || true)
    if [ -n "$templates" ]; then
        echo -e "${GREEN}[✓] Found Debian 12 templates in ${YELLOW}$storage${GREEN}:${NC}"
        echo "$templates"
        EXISTING_TEMPLATES=1
    fi
done

if [ $EXISTING_TEMPLATES -eq 0 ]; then
    echo -e "${YELLOW}[!] No Debian 12 templates found${NC}"
    echo -e "${BLUE}    The script will download it automatically${NC}"
fi
echo ""

# Summary and recommendations
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}📋 Summary & Recommendations${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"

if [ -n "$ROOTDIR_STORAGES" ] && [ -n "$TEMPLATE_STORAGES" ] && [ -n "$BRIDGES" ]; then
    echo -e "${GREEN}[✓] Your system is ready for GitLab LXC installation!${NC}"
    echo ""
    echo -e "${BLUE}Recommended command to run the script:${NC}"
    echo ""
    echo -e "${YELLOW}STORAGE=$RECOMMENDED_STORAGE \\${NC}"
    echo -e "${YELLOW}TEMPLATE_STORAGE=$RECOMMENDED_TEMPLATE_STORAGE \\${NC}"
    echo -e "${YELLOW}BRIDGE=$RECOMMENDED_BRIDGE \\${NC}"
    echo -e "${YELLOW}./gitlab-proxmox-install.sh${NC}"
    echo ""
    echo -e "${BLUE}Or for interactive mode:${NC}"
    echo ""
    echo -e "${YELLOW}./gitlab-proxmox-interactive.sh${NC}"
    echo -e "${BLUE}(The interactive script will auto-detect these values)${NC}"
else
    echo -e "${RED}[✗] Configuration issues detected:${NC}"
    [ -z "$ROOTDIR_STORAGES" ] && echo -e "    ${RED}●${NC} No storage for container root filesystem"
    [ -z "$TEMPLATE_STORAGES" ] && echo -e "    ${RED}●${NC} No storage for templates"
    [ -z "$BRIDGES" ] && echo -e "    ${RED}●${NC} No network bridges"
    echo ""
    echo -e "${YELLOW}Please configure your Proxmox storage before proceeding.${NC}"
fi
echo ""

# Storage type explanations
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}💡 Storage Type Guide${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Common storage types:${NC}"
echo -e "  ${YELLOW}dir${NC}       - Directory (supports: rootdir, vztmpl, images, etc.)"
echo -e "  ${YELLOW}lvmthin${NC}   - LVM-Thin (supports: rootdir, images - NO templates)"
echo -e "  ${YELLOW}zfspool${NC}   - ZFS (supports: rootdir, images - NO templates)"
echo -e "  ${YELLOW}nfs${NC}       - NFS (supports: rootdir, vztmpl, images, etc.)"
echo ""
echo -e "${BLUE}For GitLab LXC you need:${NC}"
echo -e "  ${GREEN}●${NC} STORAGE: Any type supporting 'rootdir' (for container disk)"
echo -e "  ${GREEN}●${NC} TEMPLATE_STORAGE: Type 'dir' or 'nfs' (for Debian template)"
echo ""
echo -e "${YELLOW}Note: If you only have 'local-lvm', you need to use 'local' for templates!${NC}"
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"