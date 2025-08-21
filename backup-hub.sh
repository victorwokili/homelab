#!/usr/bin/env bash
#
# backup-hub.sh - Simple Configuration Backup for Smart Home Hub
# Backs up only configurations and data - containers will be recreated fresh
#
# Usage: ./backup-hub.sh
#

set -euo pipefail

# ─── CONFIGURATION ──────────────────────────────────────────────────────────────
HUB_ROOT="/srv/hub"
HUB_USER="${HUB_USER:-$USER}"
BACKUP_ROOT="/home/$HUB_USER/backups"

# ─── COLOR DEFINITIONS ──────────────────────────────────────────────────────────
RESET="\e[0m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
PURPLE="\e[35m"

function info {
  echo -e "${BLUE}[INFO]${RESET}  $1"
}
function done_msg {
  echo -e "${GREEN}[DONE]${RESET}  $1"
}
function warn {
  echo -e "${YELLOW}[WARN]${RESET}  $1"
}
function error {
  echo -e "${RED}[ERROR]${RESET} $1"
}
function backup_msg {
  echo -e "${PURPLE}[BACKUP]${RESET} $1"
}

echo
echo -e "${PURPLE}##########################################${RESET}"
echo -e "${PURPLE}# Smart Home Hub Configuration Backup   #${RESET}"
echo -e "${PURPLE}##########################################${RESET}"
echo

# ─── BACKUP LOGIC ───────────────────────────────────────────────────────────────
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_NAME="hub-config-backup-$TIMESTAMP"
BACKUP_FILE="$BACKUP_NAME.tar.gz"
BACKUP_PATH="$BACKUP_ROOT/$BACKUP_FILE"
TEMP_DIR="/tmp/$BACKUP_NAME"

backup_msg "Starting configuration backup at $(date)"
info "This backup contains ONLY configs and data - containers will be fresh on restore"

# Create directories
mkdir -p "$BACKUP_ROOT"
mkdir -p "$TEMP_DIR"

# ─── BACKUP HUB CONFIGURATIONS ─────────────────────────────────────────────────
backup_msg "Backing up service configurations and data..."

if [ -d "$HUB_ROOT" ]; then
  # Create the hub data backup (this is the important stuff)
  sudo tar czf "$TEMP_DIR/hub-data.tar.gz" -C /srv hub 2>/dev/null || {
    error "Failed to backup hub data"
    rm -rf "$TEMP_DIR"
    exit 1
  }
  
  # Create manifest of what's included
  echo "Hub Configuration Backup" > "$TEMP_DIR/BACKUP_INFO.txt"
  echo "========================" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "Date: $(date)" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "Hub Root: $HUB_ROOT" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "Local IP: $(hostname -I | awk '{print $1}')" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "Hostname: $(hostname)" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "What's Included:" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "- All service configurations from /srv/hub/" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "- Service registry and hub metadata" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "- All your data (dashboards, sensor history, etc.)" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "What's NOT Included:" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "- Docker containers (will be recreated fresh)" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "- Docker images (will download latest)" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "- System packages (Ubuntu will be fresh)" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "" >> "$TEMP_DIR/BACKUP_INFO.txt"
  echo "Service Directories Backed Up:" >> "$TEMP_DIR/BACKUP_INFO.txt"
  find "$HUB_ROOT" -maxdepth 1 -type d | grep -v "^$HUB_ROOT$" | sed 's|.*/|  • |' >> "$TEMP_DIR/BACKUP_INFO.txt"
  
  done_msg "Hub configurations backed up"
else
  error "Hub directory not found: $HUB_ROOT"
  rm -rf "$TEMP_DIR"
  exit 1
fi

# ─── BACKUP IMPORTANT SYSTEM CONFIGS ──────────────────────────────────────────
backup_msg "Backing up essential system configurations..."

# Only backup configs that are actually important for restore
SYSTEM_CONFIGS=""
[ -d /etc/cron.d ] && SYSTEM_CONFIGS="$SYSTEM_CONFIGS /etc/cron.d"
[ -f /home/$HUB_USER/.bashrc ] && SYSTEM_CONFIGS="$SYSTEM_CONFIGS /home/$HUB_USER/.bashrc"
[ -d /home/$HUB_USER/scripts ] && SYSTEM_CONFIGS="$SYSTEM_CONFIGS /home/$HUB_USER/scripts"

if [ -n "$SYSTEM_CONFIGS" ]; then
  sudo tar czf "$TEMP_DIR/system-essentials.tar.gz" $SYSTEM_CONFIGS 2>/dev/null || {
    warn "Some system configs could not be backed up (non-critical)"
    touch "$TEMP_DIR/system-essentials.tar.gz"
  }
else
  touch "$TEMP_DIR/system-essentials.tar.gz"
fi

done_msg "System configurations backed up"

# ─── CREATE SIMPLE RESTORE INSTRUCTIONS ───────────────────────────────────────
backup_msg "Creating restore instructions..."

cat << EOF > "$TEMP_DIR/RESTORE_INSTRUCTIONS.txt"
Simple Hub Restore Instructions
==============================

To restore your smart home hub:

1. SETUP NEW MACHINE:
   - Install Ubuntu 22.04+ on new machine
   - Run the main setup script: ./enhanced-nuc-hub.sh
   - This will create fresh containers with latest versions

2. RESTORE YOUR DATA:
   - Stop all containers: docker stop \$(docker ps -q)
   - Extract this backup: tar xzf hub-config-backup-*.tar.gz
   - Restore hub data: sudo tar xzf hub-data.tar.gz -C /srv
   - Fix permissions: sudo chown -R $HUB_USER:$HUB_USER /srv/hub
   - Restore system configs: sudo tar xzf system-essentials.tar.gz -C /

3. START EVERYTHING:
   - Start containers: docker start \$(docker ps -aq)
   - Or re-run setup script: ./enhanced-nuc-hub.sh (safe to re-run)

4. VERIFY:
   - Check containers: docker ps
   - Visit your service URLs to confirm everything works

AUTOMATED RESTORE:
Use: ./restore-hub.sh /path/to/backup.tar.gz

Your configurations will be inserted into the fresh containers
exactly as they were before!
EOF

done_msg "Restore instructions created"

# ─── CREATE FINAL BACKUP ───────────────────────────────────────────────────────
backup_msg "Creating final backup archive..."

if tar czf "$BACKUP_PATH" -C "$TEMP_DIR" . 2>/dev/null; then
  done_msg "Backup archive created successfully"
else
  error "Failed to create backup archive"
  echo "Available space: $(df -h "$BACKUP_ROOT" | tail -1 | awk '{print $4}')"
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Cleanup
rm -rf "$TEMP_DIR"

# Get backup size
BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)

# Log the backup
echo "$(date '+%Y-%m-%d %H:%M:%S') - $BACKUP_FILE ($BACKUP_SIZE)" >> "$BACKUP_ROOT/backup.log"

# Cleanup old backups (keep last 6)
backup_msg "Cleaning up old backups..."
cd "$BACKUP_ROOT"
ls -t hub-config-backup-*.tar.gz 2>/dev/null | tail -n +7 | xargs rm -f 2>/dev/null || true
done_msg "Old backups cleaned up (keeping last 6)"

# ─── SUCCESS SUMMARY ───────────────────────────────────────────────────────────
echo
echo -e "${GREEN}##########################################${RESET}"
echo -e "${GREEN}# Configuration Backup Completed!       #${RESET}"
echo -e "${GREEN}##########################################${RESET}"
echo
echo -e "${BLUE}Backup Details:${RESET}"
echo "  📁 File: $BACKUP_FILE"
echo "  📊 Size: $BACKUP_SIZE"
echo "  📂 Location: $BACKUP_PATH"
echo "  🕒 Completed: $(date)"
echo
echo -e "${BLUE}What's Backed Up:${RESET}"
echo "  ✅ All service configurations and data"
echo "  ✅ Service registry and metadata"
echo "  ✅ Essential system settings"
echo "  ✅ Your dashboards, sensor history, etc."
echo
echo -e "${BLUE}Restore Process:${RESET}"
echo "  1️⃣  Run main script on new machine"
echo "  2️⃣  Run: ./restore-hub.sh $BACKUP_PATH"
echo "  3️⃣  Your configs will be inserted into fresh containers"
echo
echo -e "${BLUE}Backup Log:${RESET}"
echo "  📝 tail -f $BACKUP_ROOT/backup.log"
echo
echo -e "${GREEN}✅ Ready for disaster recovery! Your configs are safe.${RESET}"