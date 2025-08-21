#!/usr/bin/env bash
#
# backup-hub.sh - Smart Home Hub Backup with Scheduling Support
# Supports: Monthly backups, Weekly verification, Daily cleanup
#
# Usage: 
#   ./backup-hub.sh                    # Manual backup
#   ./backup-hub.sh --verify           # Weekly verification
#   ./backup-hub.sh --cleanup          # Daily cleanup
#   ./backup-hub.sh --setup-schedule   # Setup cron jobs
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

# ─── SCHEDULING FUNCTIONS ──────────────────────────────────────────────────────
function setup_schedule() {
  backup_msg "Setting up automated backup schedule..."
  
  # Get the absolute path to this script
  local script_path="$(readlink -f "$0")"
  
  # Create cron jobs for all three tasks
  cat << EOF | sudo tee /etc/cron.d/hub-backup-schedule >/dev/null
# Smart Home Hub Backup Schedule
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Monthly full backup (1st of month at 2AM)
0 2 1 * * $HUB_USER $script_path >> /home/$HUB_USER/backups/backup.log 2>&1

# Weekly verification (Sundays at 3AM)
0 3 * * 0 $HUB_USER $script_path --verify >> /home/$HUB_USER/backups/backup.log 2>&1

# Daily log cleanup (every day at 1AM)
0 1 * * * $HUB_USER $script_path --cleanup >> /home/$HUB_USER/backups/backup.log 2>&1
EOF

  sudo chmod 644 /etc/cron.d/hub-backup-schedule
  
  done_msg "Backup schedule configured:"
  echo "  🗓️  Monthly full backup: 1st of month at 2AM"
  echo "  🔍 Weekly verification: Sundays at 3AM"
  echo "  🧹 Daily log cleanup: Every day at 1AM"
}

function verify_backups() {
  backup_msg "🔍 Weekly backup verification starting..."
  
  local verification_failed=0
  local total_backups=0
  local corrupt_backups=0
  
  cd "$BACKUP_ROOT" 2>/dev/null || {
    error "Backup directory not found: $BACKUP_ROOT"
    return 1
  }
  
  # Check all backup files
  for backup in hub-config-backup-*.tar.gz; do
    if [ ! -f "$backup" ]; then
      warn "No backup files found"
      return 0
    fi
    
    total_backups=$((total_backups + 1))
    backup_msg "Verifying: $backup"
    
    # Test archive integrity
    if tar tzf "$backup" >/dev/null 2>&1; then
      # Check if essential files are present
      if tar tzf "$backup" | grep -q "hub-data.tar.gz" && \
         tar tzf "$backup" | grep -q "BACKUP_INFO.txt"; then
        info "✅ $backup - OK"
      else
        warn "⚠️  $backup - Missing essential files"
        verification_failed=$((verification_failed + 1))
      fi
    else
      error "❌ $backup - CORRUPTED"
      corrupt_backups=$((corrupt_backups + 1))
      verification_failed=$((verification_failed + 1))
      
      # Move corrupted backup to quarantine
      mkdir -p "$BACKUP_ROOT/corrupted"
      mv "$backup" "$BACKUP_ROOT/corrupted/"
      warn "Moved corrupted backup to quarantine"
    fi
  done
  
  # Log verification results
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "$timestamp - VERIFICATION: $total_backups total, $verification_failed failed, $corrupt_backups corrupted" >> "$BACKUP_ROOT/backup.log"
  
  if [ $verification_failed -eq 0 ]; then
    done_msg "All backups verified successfully"
  else
    warn "$verification_failed backup(s) failed verification"
    if [ $corrupt_backups -gt 0 ]; then
      error "⚠️  $corrupt_backups corrupted backup(s) found and quarantined"
      info "🔧 Consider running a manual backup to ensure you have valid backups"
    fi
  fi
  
  return $verification_failed
}

function daily_cleanup() {
  backup_msg "🧹 Daily maintenance cleanup starting..."
  
  # Clean up old log entries (keep last 90 days)
  if [ -f "$BACKUP_ROOT/backup.log" ]; then
    local temp_log="/tmp/backup-log-cleanup-$$"
    local cutoff_date=$(date -d '90 days ago' '+%Y-%m-%d')
    
    # Keep recent log entries
    if grep -v "^$cutoff_date" "$BACKUP_ROOT/backup.log" > "$temp_log" 2>/dev/null; then
      mv "$temp_log" "$BACKUP_ROOT/backup.log"
      info "Log cleanup: Removed entries older than 90 days"
    else
      rm -f "$temp_log"
      info "Log cleanup: No old entries to remove"
    fi
  fi
  
  # Clean up any temp files that might be left behind
  find /tmp -name "hub-*backup-*" -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true
  find /tmp -name "hub-*restore-*" -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true
  
  # Check disk space and warn if low
  local available_space=$(df "$BACKUP_ROOT" | tail -1 | awk '{print $4}')
  local available_gb=$((available_space / 1024 / 1024))
  
  if [ $available_gb -lt 5 ]; then
    warn "⚠️  Low disk space: Only ${available_gb}GB available for backups"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Low disk space (${available_gb}GB available)" >> "$BACKUP_ROOT/backup.log"
    
    # Automatically remove oldest backups if critically low
    if [ $available_gb -lt 2 ]; then
      warn "🚨 Critically low space - removing oldest backups"
      cd "$BACKUP_ROOT"
      ls -t hub-config-backup-*.tar.gz 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null || true
      info "Kept only 3 most recent backups due to space constraints"
    fi
  fi
  
  # Log cleanup completion
  echo "$(date '+%Y-%m-%d %H:%M:%S') - CLEANUP: Maintenance completed" >> "$BACKUP_ROOT/backup.log"
  done_msg "Daily cleanup completed"
}

# ─── ORIGINAL BACKUP LOGIC ─────────────────────────────────────────────────────
function perform_backup() {
  echo
  echo -e "${PURPLE}##########################################${RESET}"
  echo -e "${PURPLE}# Smart Home Hub Configuration Backup   #${RESET}"
  echo -e "${PURPLE}##########################################${RESET}"
  echo

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
  echo "$(date '+%Y-%m-%d %H:%M:%S') - BACKUP: $BACKUP_FILE ($BACKUP_SIZE)" >> "$BACKUP_ROOT/backup.log"

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
}

# ─── MAIN EXECUTION ────────────────────────────────────────────────────────────
case "${1:-}" in
  --verify)
    verify_backups
    ;;
  --cleanup)
    daily_cleanup
    ;;
  --setup-schedule)
    setup_schedule
    ;;
  --help|-h)
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  (no args)          Run manual backup"
    echo "  --verify           Weekly backup verification"
    echo "  --cleanup          Daily maintenance cleanup"
    echo "  --setup-schedule   Setup automated cron schedule"
    echo "  --help, -h         Show this help"
    ;;
  "")
    perform_backup
    ;;
  *)
    error "Unknown option: $1"
    echo "Use --help for usage information"
    exit 1
    ;;
esac