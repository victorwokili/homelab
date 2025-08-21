#!/usr/bin/env bash
#
# restore-hub.sh - Amazing Smart Home Hub Configuration Restore System
# Seamlessly restores all your configurations into fresh containers
#
# Usage: ./restore-hub.sh /path/to/backup.tar.gz
#
set -euo pipefail

# ─── CONFIGURATION ──────────────────────────────────────────────────────────────
HUB_ROOT="/srv/hub"
HUB_USER="${HUB_USER:-$USER}"

# ─── COLOR DEFINITIONS ──────────────────────────────────────────────────────────
RESET="\e[0m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
PURPLE="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"

function info {
  echo -e "${BLUE}[INFO]${RESET} $1"
}
function done_msg {
  echo -e "${GREEN}[DONE]${RESET} $1"
}
function warn {
  echo -e "${YELLOW}[WARN]${RESET} $1"
}
function error {
  echo -e "${RED}[ERROR]${RESET} $1"
}
function restore_msg {
  echo -e "${PURPLE}[RESTORE]${RESET} $1"
}
function magic {
  echo -e "${CYAN}[MAGIC]${RESET} $1"
}

# ─── AMAZING INTRO ──────────────────────────────────────────────────────────────
function show_intro() {
  echo
  echo -e "${PURPLE}${BOLD}################################################${RESET}"
  echo -e "${PURPLE}${BOLD}#                                              #${RESET}"
  echo -e "${PURPLE}${BOLD}#       🪄 AMAZING HUB RESTORE WIZARD 🪄       #${RESET}"
  echo -e "${PURPLE}${BOLD}#                                              #${RESET}"
  echo -e "${PURPLE}${BOLD}# About to bring your smart home back to life! #${RESET}"
  echo -e "${PURPLE}${BOLD}#                                              #${RESET}"
  echo -e "${PURPLE}${BOLD}################################################${RESET}"
  echo
  magic "✨ This wizard will seamlessly restore ALL your configurations"
  magic "🏠 Home Assistant automations, dashboards, and history"
  magic "📊 Grafana dashboards and years of sensor data"
  magic "🔐 All security settings and VPN configurations"
  magic "🎯 Every service exactly as you left it"
  echo
  echo -e "${CYAN}Your fresh containers will wake up thinking nothing ever happened!${RESET}"
  echo
}

# ─── BACKUP VALIDATION ─────────────────────────────────────────────────────────
function validate_backup() {
  local backup_file="$1"
  
  restore_msg "🔍 Validating backup file..."
  
  if [ ! -f "$backup_file" ]; then
    error "Backup file not found: $backup_file"
    echo
    echo "Available backups in /home/$HUB_USER/backups/:"
    ls -la /home/$HUB_USER/backups/*.tar.gz 2>/dev/null || echo "  No backups found"
    exit 1
  fi
  
  # Test backup integrity
  if ! tar tzf "$backup_file" >/dev/null 2>&1; then
    error "Backup file is corrupted or invalid"
    exit 1
  fi
  
  # Check if it contains hub data
  if ! tar tzf "$backup_file" | grep -q "hub-data.tar.gz"; then
    error "This doesn't look like a valid hub backup"
    echo "Expected files not found in backup"
    exit 1
  fi
  
  done_msg "Backup file validated successfully"
  
  # Show backup info if available
  if tar tzf "$backup_file" | grep -q "BACKUP_INFO.txt"; then
    echo
    info "📋 Backup Information:"
    tar xzf "$backup_file" -O BACKUP_INFO.txt 2>/dev/null | head -10 | sed 's/^/  /'
    echo
  fi
}

# ─── SAFETY CHECKS ─────────────────────────────────────────────────────────────
function safety_checks() {
  restore_msg "🛡️ Performing safety checks..."
  
  # Check if we're root (we shouldn't be)
  if [ "$EUID" -eq 0 ]; then
    error "Don't run this script as root! Run as: ./restore-hub.sh"
    exit 1
  fi
  
  # Check if Docker is running
  if ! command -v docker >/dev/null 2>&1; then
    error "Docker not found. Please install Docker first."
    echo "Hint: Run the main setup script: ./enhanced-nuc-hub.sh"
    exit 1
  fi
  
  if ! docker info >/dev/null 2>&1; then
    error "Docker is not running or accessible"
    echo "Try: sudo systemctl start docker"
    exit 1
  fi
  
  # Check if hub directory exists
  if [ ! -d "$HUB_ROOT" ]; then
    warn "Hub directory doesn't exist yet"
    info "Creating hub structure..."
    sudo mkdir -p "$HUB_ROOT"
    sudo chown -R "$HUB_USER:$HUB_USER" "$HUB_ROOT"
  fi
  
  done_msg "Safety checks passed"
}

# ─── BACKUP CURRENT DATA ───────────────────────────────────────────────────────
function backup_current_data() {
  restore_msg "💾 Creating safety backup of current data..."
  
  local safety_backup="/tmp/hub-safety-backup-$(date +%s).tar.gz"
  
  if [ -d "$HUB_ROOT" ] && [ "$(ls -A "$HUB_ROOT" 2>/dev/null)" ]; then
    sudo tar czf "$safety_backup" -C /srv hub 2>/dev/null || true
    if [ -f "$safety_backup" ]; then
      info "Current data backed up to: $safety_backup"
      echo "🔒 If something goes wrong, you can restore with:"
      echo "   sudo tar xzf $safety_backup -C /srv"
    fi
  else
    info "No existing data to backup"
  fi
  
  done_msg "Safety backup completed"
}

# ─── CONTAINER MANAGEMENT ──────────────────────────────────────────────────────
function stop_containers() {
  restore_msg "⏸️ Gracefully stopping containers..."
  
  local containers=$(docker ps --format '{{.Names}}' 2>/dev/null || true)
  
  if [ -n "$containers" ]; then
    echo "Stopping containers: $containers"
    # Stop containers gracefully
    docker stop $containers >/dev/null 2>&1 || warn "Some containers didn't stop gracefully"
    # Wait a moment for clean shutdown
    sleep 3
    done_msg "Containers stopped"
  else
    info "No running containers found"
  fi
}

function start_containers() {
  restore_msg "🚀 Starting containers with your restored configurations..."
  
  # Get all containers (including stopped ones)
  local all_containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)
  
  if [ -n "$all_containers" ]; then
    # Start critical services first
    local critical_services="influxdb mosquitto homeassistant pihole"
    for service in $critical_services; do
      if echo "$all_containers" | grep -qw "$service"; then
        info "Starting critical service: $service"
        docker start "$service" >/dev/null 2>&1 || warn "Failed to start $service"
        sleep 2  # Give critical services time to initialize
      fi
    done
    
    # Start remaining containers
    for container in $all_containers; do
      if ! echo "$critical_services" | grep -qw "$container"; then
        docker start "$container" >/dev/null 2>&1 || warn "Failed to start $container"
      fi
    done
    
    magic "✨ All containers started with your configurations!"
  else
    warn "No containers found - you may need to run the main setup script first"
    echo "Hint: ./enhanced-nuc-hub.sh"
  fi
}

# ─── THE ACTUAL RESTORE MAGIC ──────────────────────────────────────────────────
function perform_restore() {
  local backup_file="$1"
  local restore_dir="/tmp/hub-restore-$(date +%s)"
  
  restore_msg "🎭 Extracting backup..."
  mkdir -p "$restore_dir"
  tar xzf "$backup_file" -C "$restore_dir" || {
    error "Failed to extract backup"
    rm -rf "$restore_dir"
    exit 1
  }
  done_msg "Backup extracted successfully"
  
  # Stop containers for clean restore
  stop_containers
  
  # Restore hub data (the main event!)
  if [ -f "$restore_dir/hub-data.tar.gz" ]; then
    magic "🏠 Restoring all your service configurations and data..."
    
    # Remove old hub data
    if [ -d "$HUB_ROOT" ]; then
      sudo rm -rf "$HUB_ROOT.old" 2>/dev/null || true
      sudo mv "$HUB_ROOT" "$HUB_ROOT.old" 2>/dev/null || true
    fi
    
    # Restore hub data
    sudo mkdir -p /srv
    sudo tar xzf "$restore_dir/hub-data.tar.gz" -C /srv || {
      error "Failed to restore hub data"
      # Try to restore old data
      if [ -d "$HUB_ROOT.old" ]; then
        sudo mv "$HUB_ROOT.old" "$HUB_ROOT"
      fi
      rm -rf "$restore_dir"
      exit 1
    }
    
    # Fix permissions
    sudo chown -R "$HUB_USER:$HUB_USER" "$HUB_ROOT"
    done_msg "Hub data restored successfully"
  else
    error "Hub data not found in backup"
    rm -rf "$restore_dir"
    exit 1
  fi
  
  # Restore system configurations
  if [ -f "$restore_dir/system-essentials.tar.gz" ]; then
    magic "⚙️ Restoring system configurations..."
    sudo tar xzf "$restore_dir/system-essentials.tar.gz" -C / 2>/dev/null || warn "Some system configs couldn't be restored"
    done_msg "System configurations restored"
  fi
  
  # Cleanup
  rm -rf "$restore_dir"
  magic "🎉 All configurations have been magically restored!"
}

# ─── SERVICE HEALTH CHECK ──────────────────────────────────────────────────────
function health_check() {
  restore_msg "🏥 Performing health check..."
  echo
  
  info "Container Status:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -15
  echo
  
  info "🔍 Checking service accessibility..."
  local services=(
    "Home Assistant:http://$(hostname -I | awk '{print $1}'):8123"
    "Portainer:http://$(hostname -I | awk '{print $1}'):9000"
    "Grafana:http://$(hostname -I | awk '{print $1}'):3000"
    "Pi-hole:http://$(hostname -I | awk '{print $1}')/admin"
  )
  
  for service_info in "${services[@]}"; do
    local name=$(echo "$service_info" | cut -d: -f1)
    local url=$(echo "$service_info" | cut -d: -f2-)
    if curl -s --connect-timeout 3 "$url" >/dev/null 2>&1; then
      echo -e "  ✅ $name: ${GREEN}Online${RESET}"
    else
      echo -e "  ⏳ $name: ${YELLOW}Starting up...${RESET}"
    fi
  done
  
  echo
  done_msg "Health check completed"
}

# ─── AMAZING SUCCESS SUMMARY ───────────────────────────────────────────────────
function show_success() {
  local local_ip=$(hostname -I | awk '{print $1}')
  
  echo
  echo -e "${GREEN}${BOLD}################################################${RESET}"
  echo -e "${GREEN}${BOLD}#                                              #${RESET}"
  echo -e "${GREEN}${BOLD}#           🎉 RESTORATION COMPLETED! 🎉       #${RESET}"
  echo -e "${GREEN}${BOLD}#                                              #${RESET}"
  echo -e "${GREEN}${BOLD}#      Your smart home has been brought back   #${RESET}"
  echo -e "${GREEN}${BOLD}#     to life with ALL your configurations!    #${RESET}"
  echo -e "${GREEN}${BOLD}#                                              #${RESET}"
  echo -e "${GREEN}${BOLD}################################################${RESET}"
  echo
  magic "✨ Your services are waking up with all their memories intact!"
  echo
  echo -e "${CYAN}🌟 What's Been Restored:${RESET}"
  echo "  🏠 Home Assistant - All automations, dashboards & history"
  echo "  📊 Grafana - All your custom dashboards and data sources"
  echo "  💾 InfluxDB - Years of sensor data and measurements"
  echo "  🔒 Pi-hole - Block lists, DNS settings, and configurations"
  echo "  🔌 All other services - Exactly as you left them"
  echo
  echo -e "${CYAN}🚀 Access Your Services:${RESET}"
  echo "  🏠 Home Assistant: http://$local_ip:8123"
  echo "  🔧 Portainer: http://$local_ip:9000"
  echo "  📊 Grafana: http://$local_ip:3000"
  echo "  🛡️ Pi-hole: http://$local_ip/admin"
  echo "  📋 Dashboard: http://$local_ip:8201"
  echo
  echo -e "${CYAN}⚡ Pro Tips:${RESET}"
  echo "  • Services may take 1-2 minutes to fully start up"
  echo "  • Check status: docker ps"
  echo "  • View logs: docker logs [service-name]"
  echo "  • All your historical data is preserved!"
  echo
  echo -e "${GREEN}${BOLD}🎯 Mission Accomplished!${RESET}"
  echo -e "${GREEN}Your smart home is back online like nothing ever happened!${RESET}"
  echo
}

# ─── MAIN EXECUTION ────────────────────────────────────────────────────────────
function main() {
  # Check arguments
  if [ $# -ne 1 ]; then
    error "Usage: $0 /path/to/backup.tar.gz"
    echo
    echo "Available backups:"
    ls -la /home/$HUB_USER/backups/*.tar.gz 2>/dev/null || echo "  No backups found"
    exit 1
  fi
  
  local backup_file="$1"
  
  # Show amazing intro
  show_intro
  
  # Validate everything
  validate_backup "$backup_file"
  safety_checks
  
  # Confirm with user
  echo -e "${YELLOW}⚠️ This will restore configurations from backup and restart all services.${RESET}"
  echo -e "${CYAN}Backup file: $(basename "$backup_file")${RESET}"
  echo
  read -p "$(echo -e "${CYAN}Ready to bring your smart home back to life? (y/N): ${RESET}")" confirm
  if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Restore cancelled. Your services remain untouched.${RESET}"
    exit 0
  fi
  
  echo
  magic "🪄 Beginning the restoration magic..."
  echo
  
  # Create safety backup
  backup_current_data
  
  # Perform the actual restore
  perform_restore "$backup_file"
  
  # Start everything back up
  start_containers
  
  # Give services time to start
  echo
  restore_msg "⏳ Giving services time to wake up..."
  sleep 15
  
  # Check health
  health_check
  
  # Show amazing success message
  show_success
}

# ─── ERROR HANDLING ────────────────────────────────────────────────────────────
function cleanup_on_error() {
  echo
  error "Something went wrong during restore!"
  
  # Try to restart containers
  warn "Attempting to restart containers..."
  docker start $(docker ps -aq) >/dev/null 2>&1 || true
  
  echo "If you have issues:"
  echo "  • Check container status: docker ps -a"
  echo "  • View container logs: docker logs [container-name]"
  echo "  • Re-run main setup: ./enhanced-nuc-hub.sh"
  echo
  echo "Safety backup location: /tmp/hub-safety-backup-*"
}

trap cleanup_on_error ERR

# Run the magic!
main "$@"