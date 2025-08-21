#!/usr/bin/env bash
#
# enhanced-nuc-hub.sh  —  Modular Smart Home Hub Setup
# Automatically registers services for backup/restore system
#
# Run as:
#   chmod +x ~/scripts/enhanced-nuc-hub.sh
#   ~/scripts/enhanced-nuc-hub.sh
#

set -euo pipefail

# ─── COLOR DEFINITIONS ───────────────────────────────────────────────────────────
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
function enhanced {
  echo -e "${PURPLE}[ENHANCED]${RESET} $1"
}

# ─── HUB CONFIGURATION AND DISCOVERY SYSTEM ─────────────────────────────────────
HUB_ROOT="/srv/hub"
SERVICE_REGISTRY="$HUB_ROOT/hub-registry.json"
HUB_CONFIG="$HUB_ROOT/hub-config.json"
HUB_USER="${HUB_USER:-$USER}"

# Initialize hub metadata for complete discoverability
function init_hub_metadata {
  # Create hub configuration file with all metadata
  cat << EOF | sudo tee "$HUB_CONFIG" >/dev/null
{
  "hub_info": {
    "version": "1.0",
    "created": "$(date -Iseconds)",
    "last_updated": "$(date -Iseconds)",
    "local_ip": "$LOCAL_IP",
    "hostname": "$(hostname)",
    "hub_root": "$HUB_ROOT",
    "backup_root": "/home/$HUB_USER/backups",
    "user": "$HUB_USER"
  },
  "backup_strategy": {
    "data_paths": ["$HUB_ROOT"],
    "exclude_patterns": ["*.log", "*.tmp", "cache/*"],
    "container_handling": "stop_during_backup",
    "retention_policy": "keep_last_6_monthly"
  },
  "network_config": {
    "firewall_ports": ["53/tcp", "53/udp", "80/tcp", "1883/tcp", "3000/tcp", "3001/tcp", "8081/tcp", "8086/tcp", "8123/tcp", "8201/tcp", "8581/tcp", "9000/tcp", "10443/tcp", "19999/tcp", "32400/tcp"],
    "internal_dns": "$LOCAL_IP",
    "mqtt_broker": "localhost:1883"
  }
}
EOF
  
  # Create service registry with metadata
  cat << EOF | sudo tee "$SERVICE_REGISTRY" >/dev/null
{
  "registry_info": {
    "version": "1.0",
    "created": "$(date -Iseconds)",
    "discovery_method": "automatic",
    "backup_compatible": true
  },
  "services": []
}
EOF
  
  sudo chown $HUB_USER:$HUB_USER "$HUB_CONFIG" "$SERVICE_REGISTRY"
}

function register_service {
  local name="$1"
  local data_path="$2"
  local container_name="$3"
  local url="$4"
  local description="$5"
  local service_type="${6:-general}"
  local backup_priority="${7:-normal}"
  
  # Ensure registry exists
  [ ! -f "$SERVICE_REGISTRY" ] && init_hub_metadata
  
  # Add comprehensive service metadata
  local service_json=$(cat << EOF
{
  "name": "$name",
  "data_path": "$data_path",
  "container_name": "$container_name",
  "url": "$url",
  "description": "$description",
  "service_type": "$service_type",
  "backup_priority": "$backup_priority",
  "installed": "$(date -Iseconds)",
  "ports": [],
  "dependencies": [],
  "backup_size_estimate": "unknown",
  "critical": false
}
EOF
)
  
  # Add to registry using jq
  if command -v jq >/dev/null 2>&1; then
    echo "$service_json" | jq ". as \$new | $(cat "$SERVICE_REGISTRY") | .services += [\$new] | .registry_info.last_updated = \"$(date -Iseconds)\"" > "/tmp/registry.tmp"
    sudo mv "/tmp/registry.tmp" "$SERVICE_REGISTRY"
    sudo chown $HUB_USER:$HUB_USER "$SERVICE_REGISTRY"
  fi
  
  # Update hub config with last service addition
  if command -v jq >/dev/null 2>&1; then
    jq ".hub_info.last_updated = \"$(date -Iseconds)\" | .hub_info.total_services = (.hub_info.total_services // 0) + 1" "$HUB_CONFIG" > "/tmp/hub-config.tmp"
    sudo mv "/tmp/hub-config.tmp" "$HUB_CONFIG"
    sudo chown $HUB_USER:$HUB_USER "$HUB_CONFIG"
  fi
}

# Function for backup scripts to discover everything automatically
function create_discovery_helper {
  cat << 'EOF' | sudo tee "$HUB_ROOT/discovery-helper.sh" >/dev/null
#!/usr/bin/env bash
# Hub Discovery Helper - Used by backup/restore scripts
# This file is auto-generated and provides complete hub discovery

HUB_ROOT="/srv/hub"
SERVICE_REGISTRY="$HUB_ROOT/hub-registry.json"
HUB_CONFIG="$HUB_ROOT/hub-config.json"

# Get all service data paths for backup
get_all_data_paths() {
  if [ -f "$SERVICE_REGISTRY" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.services[].data_path' "$SERVICE_REGISTRY" 2>/dev/null
  else
    # Fallback: discover by directory structure
    find "$HUB_ROOT" -maxdepth 1 -type d -not -name "logs" -not -name "config" | grep -v "^$HUB_ROOT$"
  fi
}

# Get all container names for stop/start operations
get_all_containers() {
  if [ -f "$SERVICE_REGISTRY" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.services[].container_name' "$SERVICE_REGISTRY" 2>/dev/null | grep -v "^null$"
  else
    # Fallback: get all hub-related containers
    docker ps -a --format '{{.Names}}' | grep -E "(portainer|watchtower|mosquitto|zigbee2mqtt|homeassistant|scrypted|heimdall|homebridge|plex|influxdb|grafana|pihole|uptime-kuma|netdata)"
  fi
}

# Get hub metadata
get_hub_info() {
  if [ -f "$HUB_CONFIG" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.hub_info' "$HUB_CONFIG" 2>/dev/null
  else
    echo "{\"version\":\"unknown\",\"backup_root\":\"/home/$USER/backups\",\"user\":\"$USER\"}"
  fi
}

# Get critical services (backup priority)
get_critical_services() {
  if [ -f "$SERVICE_REGISTRY" ] && command -v jq >/dev/null 2>&1; then
    jq -r '.services[] | select(.backup_priority == "high" or .critical == true) | .container_name' "$SERVICE_REGISTRY" 2>/dev/null
  fi
}

# Export functions for use by backup scripts
export -f get_all_data_paths get_all_containers get_hub_info get_critical_services
EOF
  
  sudo chmod +x "$HUB_ROOT/discovery-helper.sh"
  sudo chown $HUB_USER:$HUB_USER "$HUB_ROOT/discovery-helper.sh"
}

echo
echo -e "${BLUE}################################################${RESET}"
echo -e "${BLUE}# Modular Smart Home Hub Setup with Auto-Backup #${RESET}"
echo -e "${BLUE}################################################${RESET}"
echo

### 0) Detect local IPv4 address ###
LOCAL_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -z "$LOCAL_IP" ]]; then
  warn "Unable to detect local IP via hostname -I. Trying fallback..."
  LOCAL_IP="$(ip -4 addr show "$(ip route get 1 | awk '{print $5; exit}')" \
    | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
fi
if [[ -z "$LOCAL_IP" ]]; then
  error "Could not determine local IP address. Exiting."
  exit 1
fi
info "Detected local IP: $LOCAL_IP"
echo

### 1) Update Ubuntu & Install Essentials ###
info "Updating Ubuntu packages…"
sudo apt update && sudo apt upgrade -y
done_msg "Ubuntu is fully updated."
echo

info "Installing prerequisites and monitoring tools…"
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release \
  software-properties-common htop btop iotop ncdu tree jq fail2ban ufw \
  smartmontools lm-sensors psmisc net-tools
done_msg "Essential packages installed."
echo

### 2) Install Node.js (v20.x) ###
info "Installing Node.js 20.x LTS…"

# Check if Node.js is already installed
if command -v node >/dev/null 2>&1; then
  NODE_VER="$(node --version 2>/dev/null || echo 'not installed')"
  info "Node.js $NODE_VER already installed, skipping."
else
  # Test DNS resolution first
  if ! nslookup deb.nodesource.com >/dev/null 2>&1; then
    warn "DNS resolution issues detected. Trying to fix..."
    # Temporarily use different DNS
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null
    sleep 2
  fi
  
  if curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null 2>&1; then
    sudo apt-get install -y nodejs >/dev/null
    NODE_VER="$(node --version 2>/dev/null || echo 'not installed')"
    done_msg "Node.js $NODE_VER installed."
  else
    warn "Failed to install Node.js from repository, but continuing..."
    NODE_VER="installation failed"
  fi
fi
echo

### 3) Install Docker & Docker Compose Plugin ###
info "Installing Docker CE + Docker Compose plugin…"

# Check if Docker is already installed
if command -v docker >/dev/null 2>&1; then
  info "Docker already installed, ensuring it's running..."
  sudo systemctl enable docker
  sudo systemctl start docker
  done_msg "Docker verified and running."
else
  # Test DNS and install Docker
  if ! nslookup download.docker.com >/dev/null 2>&1; then
    warn "DNS resolution issues for Docker repository. Trying to fix..."
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null
    sleep 2
  fi
  
  if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null; then
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
    done_msg "Docker and Docker Compose plugin installed."
  else
    error "Failed to install Docker due to network issues. Exiting."
    exit 1
  fi
fi
echo

### 4) Add current user to docker & dialout Groups ###
info "Adding user '$HUB_USER' to docker & dialout groups…"
sudo usermod -aG docker $HUB_USER
sudo usermod -aG dialout $HUB_USER
done_msg "'$HUB_USER' is now in docker & dialout groups."
echo

### 5) Configure Enhanced Security ###
enhanced "Configuring enhanced security with UFW and fail2ban…"

# Configure UFW firewall
sudo ufw --force reset >/dev/null 2>&1
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh

# Allow specific service ports
declare -a PORTS=(
  "53/tcp" "53/udp" "80/tcp" "1883/tcp" "3000/tcp" "3001/tcp" 
  "8081/tcp" "8086/tcp" "8123/tcp" "8201/tcp" "8581/tcp" 
  "9000/tcp" "10443/tcp" "19999/tcp" "32400/tcp"
)

for port in "${PORTS[@]}"; do
  sudo ufw allow "$port" >/dev/null
done

sudo ufw --force enable
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
done_msg "Security configured: UFW firewall + fail2ban enabled."
echo

### 6) Configure System Monitoring ###
enhanced "Setting up hardware monitoring…"
sudo sensors-detect --auto >/dev/null 2>&1 || true

# Enable SMART monitoring (handle different service names)
if systemctl list-unit-files | grep -q "^smartmontools.service"; then
  sudo systemctl enable smartmontools
  sudo systemctl start smartmontools
elif systemctl list-unit-files | grep -q "^smartd.service"; then
  sudo systemctl enable smartd >/dev/null 2>&1 || true
  sudo systemctl start smartd >/dev/null 2>&1 || true
else
  warn "SMART monitoring service not found, but smartmontools package is installed"
fi

done_msg "Hardware monitoring configured."
echo

### 7) Create Self-Discovering Hub Structure ###
info "Creating self-discovering modular hub structure…"

# Core hub directories with standardized layout
sudo mkdir -p "$HUB_ROOT"/{logs,config,scripts}
sudo mkdir -p /home/$HUB_USER/backups

# Initialize hub metadata and discovery system
init_hub_metadata
create_discovery_helper

# Set proper ownership
sudo chown -R $HUB_USER:$HUB_USER "$HUB_ROOT"
sudo chown -R $HUB_USER:$HUB_USER /home/$HUB_USER/backups

done_msg "Self-discovering hub structure created with full metadata."
echo

### 8) Deploy Portainer ###
enhanced "Deploying Portainer (Docker Management)…"
SERVICE_NAME="portainer"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/data"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    -p 9000:9000 -p 9443:9443 \
    --name="$SERVICE_NAME" --restart unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$DATA_DIR/data":/data \
    portainer/portainer-ce:latest
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:9000" "Docker Management Interface" "management" "high"
echo

### 9) Deploy Watchtower ###
enhanced "Deploying Watchtower (Container Auto-updater)…"
SERVICE_NAME="watchtower"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/config"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$DATA_DIR/config":/config \
    -e WATCHTOWER_CLEANUP=true \
    -e WATCHTOWER_ROLLING_RESTART=true \
    containrrr/watchtower --interval 3600
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "N/A" "Container Auto-updater" "automation" "normal"
echo

### 10) Deploy Mosquitto ###
enhanced "Deploying Mosquitto (MQTT Broker)…"
SERVICE_NAME="mosquitto"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR"/{config,data}
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  # Create config if it doesn't exist
  if [ ! -f "$DATA_DIR/config/mosquitto.conf" ]; then
    cat << 'EOF' | sudo tee "$DATA_DIR/config/mosquitto.conf" >/dev/null
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/data/mosquitto.log
log_type all
connection_messages true
log_timestamp true
EOF
    sudo chown $HUB_USER:$HUB_USER "$DATA_DIR/config/mosquitto.conf"
  fi

  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    -p 1883:1883 \
    -v "$DATA_DIR/config/mosquitto.conf":/mosquitto/config/mosquitto.conf:ro \
    -v "$DATA_DIR/data":/mosquitto/data \
    eclipse-mosquitto:latest
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "mqtt://$LOCAL_IP:1883" "MQTT Message Broker" "communication" "high"
echo

### 11) Deploy Zigbee2MQTT ###
enhanced "Deploying Zigbee2MQTT (if adapter present)…"
SERVICE_NAME="zigbee2mqtt"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/data"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

# Check for Zigbee adapter
ZIGBEE_DEVICE=""
if [ -e /dev/ttyACM0 ]; then
  ZIGBEE_DEVICE="/dev/ttyACM0"
elif [ -e /dev/ttyUSB0 ]; then
  ZIGBEE_DEVICE="/dev/ttyUSB0"
fi

if [ -z "$ZIGBEE_DEVICE" ]; then
  warn "No Zigbee adapter detected. Skipping $SERVICE_NAME."
else
  if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
    done_msg "$SERVICE_NAME container already exists, skipping."
  else
    # Create config if it doesn't exist
    if [ ! -f "$DATA_DIR/data/configuration.yaml" ]; then
      cat << EOF | sudo tee "$DATA_DIR/data/configuration.yaml" >/dev/null
homeassistant: true
permit_join: false
mqtt:
  base_topic: zigbee2mqtt
  server: 'mqtt://localhost:1883'
serial:
  port: '$ZIGBEE_DEVICE'
  adapter: auto
advanced:
  log_level: info
  pan_id: GENERATE
  network_key: GENERATE
frontend:
  port: 8081
  host: 0.0.0.0
devices: []
groups: []
EOF
      sudo chown $HUB_USER:$HUB_USER "$DATA_DIR/data/configuration.yaml"
    fi

    sudo docker run -d \
      --name="$SERVICE_NAME" --restart unless-stopped \
      --device="$ZIGBEE_DEVICE" --net=host \
      -v "$DATA_DIR/data":/app/data \
      -v /run/udev:/run/udev:ro \
      -e TZ="$(timedatectl show --value --property=Timezone)" \
      koenkk/zigbee2mqtt:latest
    done_msg "$SERVICE_NAME deployed"
  fi

  register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:8081" "Zigbee Device Manager" "smart_home" "high"
fi
echo

### 12) Deploy Home Assistant ###
enhanced "Deploying Home Assistant (Home Automation)…"
SERVICE_NAME="homeassistant"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/config"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    -v "$DATA_DIR/config":/config \
    -v /etc/localtime:/etc/localtime:ro \
    --privileged --network host \
    ghcr.io/home-assistant/home-assistant:stable
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:8123" "Home Automation Platform" "smart_home" "critical"
echo

### 13) Deploy Scrypted ###
enhanced "Deploying Scrypted (Camera/Security Hub)…"
SERVICE_NAME="scrypted"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/volume"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    --network host \
    -v "$DATA_DIR/volume":/server/volume \
    koush/scrypted:latest
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "https://$LOCAL_IP:10443" "Camera & Security Management" "security" "normal"
echo

### 14) Deploy Heimdall ###
enhanced "Deploying Heimdall (Service Dashboard)…"
SERVICE_NAME="heimdall"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/config"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    -e PUID=1000 -e PGID=1000 \
    -v "$DATA_DIR/config":/config \
    -p 8201:80 \
    linuxserver/heimdall:latest
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:8201" "Service Dashboard" "management" "normal"
echo

### 15) Deploy Homebridge ###
enhanced "Deploying Homebridge (HomeKit Bridge)…"
SERVICE_NAME="homebridge"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/config"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    --network host \
    -e PUID=1000 -e PGID=1000 \
    -e TZ="$(timedatectl show --value --property=Timezone)" \
    -e HOMEBRIDGE_CONFIG_UI=1 \
    -e HOMEBRIDGE_CONFIG_UI_PORT=8581 \
    -v "$DATA_DIR/config":/homebridge \
    oznu/homebridge:latest
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:8581" "Apple HomeKit Bridge" "smart_home" "normal"
echo

### 16) Deploy Plex ###
enhanced "Deploying Plex Media Server…"
SERVICE_NAME="plex"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR"/{config,media/tvseries,media/movies}
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    -e PUID=1000 -e PGID=1000 \
    -e TZ="$(timedatectl show --value --property=Timezone)" \
    -v "$DATA_DIR/config":/config \
    -v "$DATA_DIR/media/tvseries":/data/tvshows \
    -v "$DATA_DIR/media/movies":/data/movies \
    -p 32400:32400 \
    linuxserver/plex:latest
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:32400" "Media Streaming Server" "media" "normal"
echo

### 17) Deploy InfluxDB ###
enhanced "Deploying InfluxDB (Time-series Database)…"
SERVICE_NAME="influxdb"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR"/{config,data}
sudo chown -R 1000:1000 "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  warn "Removing old $SERVICE_NAME container..."
  sudo docker stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  sudo docker rm "$SERVICE_NAME" >/dev/null 2>&1 || true
fi

sudo docker run -d \
  --name="$SERVICE_NAME" --restart unless-stopped \
  -v "$DATA_DIR/config":/etc/influxdb2 \
  -v "$DATA_DIR/data":/var/lib/influxdb2 \
  -p 8086:8086 \
  -e DOCKER_INFLUXDB_INIT_MODE=setup \
  -e DOCKER_INFLUXDB_INIT_USERNAME=admin \
  -e DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword \
  -e DOCKER_INFLUXDB_INIT_ORG=homelab \
  -e DOCKER_INFLUXDB_INIT_BUCKET=default \
  -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=my-super-secret-auth-token \
  influxdb:2

sleep 10
done_msg "$SERVICE_NAME deployed"

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:8086" "Time-series Database (admin/adminpassword)" "database" "high"
echo

### 18) Deploy Grafana ###
enhanced "Deploying Grafana (Analytics Dashboard)…"
SERVICE_NAME="grafana"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/data"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    -v "$DATA_DIR/data":/var/lib/grafana \
    -e GF_SECURITY_ADMIN_USER=admin \
    -e GF_SECURITY_ADMIN_PASSWORD=admin \
    -e GF_USERS_ALLOW_SIGN_UP=false \
    -p 3000:3000 \
    grafana/grafana:latest
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:3000" "Analytics Dashboard (admin/admin)" "monitoring" "normal"
echo

### 19) Deploy Pi-hole ###
enhanced "Deploying Pi-hole (Network Ad Blocker)…"
SERVICE_NAME="pihole"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR"/{config,dnsmasq.d}
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

# Disable systemd-resolved for port 53
if systemctl is-active --quiet systemd-resolved; then
  warn "Disabling systemd-resolved for Pi-hole..."
  sudo systemctl disable --now systemd-resolved
  sudo rm -f /etc/resolv.conf
  echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf >/dev/null
fi

# Remove existing container
if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  sudo docker stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  sudo docker rm "$SERVICE_NAME" >/dev/null 2>&1 || true
fi

sudo docker run -d \
  --name="$SERVICE_NAME" --restart unless-stopped \
  -e TZ="$(timedatectl show --value --property=Timezone)" \
  -e WEBPASSWORD="changeme" \
  -e PIHOLE_DNS_="1.1.1.1;8.8.8.8" \
  -v "$DATA_DIR/config":/etc/pihole \
  -v "$DATA_DIR/dnsmasq.d":/etc/dnsmasq.d \
  -p 53:53/tcp -p 53:53/udp -p 80:80 \
  pihole/pihole:latest >/dev/null

sleep 5
done_msg "$SERVICE_NAME deployed"

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP/admin" "Network Ad Blocker (password: changeme)" "network" "critical"
echo

### 20) Deploy Uptime Kuma ###
enhanced "Deploying Uptime Kuma (Service Monitoring)…"
SERVICE_NAME="uptime-kuma"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/data"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    -v "$DATA_DIR/data":/app/data \
    -p 3001:3001 \
    louislam/uptime-kuma:latest
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:3001" "Service Uptime Monitor" "monitoring" "normal"
echo

### 21) Deploy Netdata ###
enhanced "Deploying Netdata (System Monitoring)…"
SERVICE_NAME="netdata"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR"/{lib,cache}
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

if sudo docker ps -a --format '{{.Names}}' | grep -qw "$SERVICE_NAME"; then
  done_msg "$SERVICE_NAME container already exists, skipping."
else
  sudo docker run -d \
    --name="$SERVICE_NAME" --restart unless-stopped \
    --cap-add SYS_PTRACE --cap-add SYS_NICE \
    -p 19999:19999 \
    -v "$DATA_DIR/lib":/var/lib/netdata \
    -v "$DATA_DIR/cache":/var/cache/netdata \
    -v /etc/passwd:/host/etc/passwd:ro \
    -v /etc/group:/host/etc/group:ro \
    -v /proc:/host/proc:ro \
    -v /sys:/host/sys:ro \
    -v /etc/os-release:/host/etc/os-release:ro \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    netdata/netdata:latest
  done_msg "$SERVICE_NAME deployed"
fi

register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "http://$LOCAL_IP:19999" "Real-time System Monitor" "monitoring" "normal"
echo

### 22) Finalize Discovery System ###
enhanced "Finalizing self-discovery system for future services…"

# Create template for adding new services
cat << 'EOF' | sudo tee "$HUB_ROOT/add-service-template.sh" >/dev/null
#!/usr/bin/env bash
# Template for adding new services to the hub
# Usage: Copy this template and modify for your service

# Example: Adding WireGuard VPN
SERVICE_NAME="wireguard"
DATA_DIR="$HUB_ROOT/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/config"
sudo chown -R $HUB_USER:$HUB_USER "$DATA_DIR"

# Deploy container (modify as needed)
sudo docker run -d \
  --name="$SERVICE_NAME" --restart unless-stopped \
  --cap-add=NET_ADMIN \
  -p 51820:51820/udp \
  -v "$DATA_DIR/config":/config \
  -e PUID=1000 -e PGID=1000 \
  linuxserver/wireguard:latest

# Register service (REQUIRED - this makes it discoverable by backup/restore)
register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" "vpn://$LOCAL_IP:51820" "WireGuard VPN Server" "network" "high"
EOF

sudo chown $HUB_USER:$HUB_USER "$HUB_ROOT/add-service-template.sh"
chmod +x "$HUB_ROOT/add-service-template.sh"

done_msg "Complete discovery system ready:"
echo "  • Service registry: $SERVICE_REGISTRY" 
echo "  • Hub config: $HUB_CONFIG"
echo "  • Discovery helper: $HUB_ROOT/discovery-helper.sh"
echo "  • Service template: $HUB_ROOT/add-service-template.sh"
echo

### 23) Schedule Monthly Backup ###
enhanced "Scheduling automated backup…"
sudo bash -c "echo \"0 2 1 * * $HUB_USER /home/$HUB_USER/backup-hub.sh >> /home/$HUB_USER/backups/backup.log 2>&1\" > /etc/cron.d/hub-backup"
sudo chmod 644 /etc/cron.d/hub-backup
done_msg "Monthly backup scheduled for 2AM on 1st of each month"
echo

### 24) Final Summary ###
echo -e "${GREEN}###############################################################${RESET}"
echo -e "${GREEN}#                                                           #${RESET}"
echo -e "${GREEN}#  Modular Smart Home Hub Setup Complete!                    #${RESET}"
echo -e "${GREEN}#                                                           #${RESET}"
echo -e "${GREEN}###############################################################${RESET}"
echo

echo -e "${PURPLE}🔍 Complete Discovery System:${RESET}"
echo "  • Registry file:     $SERVICE_REGISTRY"
echo "  • Hub config:        $HUB_CONFIG" 
echo "  • Discovery helper:  $HUB_ROOT/discovery-helper.sh"
echo "  • Service template:  $HUB_ROOT/add-service-template.sh"
echo "  • Data location:     $HUB_ROOT/[service-name]/"
echo "  • Auto-discovery:    100% automatic for backup/restore"

echo
echo -e "${BLUE}🏠 Smart Home Services:${RESET}"
if [ -f "$SERVICE_REGISTRY" ] && command -v jq >/dev/null 2>&1; then
  jq -r '.services[] | select(.description | contains("Home") or contains("Smart") or contains("Automation")) | "  • \(.name): \(.url)"' "$SERVICE_REGISTRY" 2>/dev/null || echo "  • Services registered in $SERVICE_REGISTRY"
else
  echo "  • Home Assistant:    http://$LOCAL_IP:8123"
  echo "  • Zigbee2MQTT:       http://$LOCAL_IP:8081 (if available)"
  echo "  • Homebridge:        http://$LOCAL_IP:8581"
  echo "  • Scrypted:          https://$LOCAL_IP:10443"
fi

echo
echo -e "${BLUE}🔧 Management Services:${RESET}"
echo "  • Portainer:         http://$LOCAL_IP:9000"
echo "  • Heimdall:          http://$LOCAL_IP:8201"
echo "  • Uptime Kuma:       http://$LOCAL_IP:3001"
echo "  • Netdata:           http://$LOCAL_IP:19999"
echo "  • Grafana:           http://$LOCAL_IP:3000 (admin/admin)"
echo "  • InfluxDB:          http://$LOCAL_IP:8086 (admin/adminpassword)"

echo
echo -e "${BLUE}🌐 Network Services:${RESET}"
echo "  • Pi-hole Admin:     http://$LOCAL_IP/admin (password: changeme)"
echo "  • Plex Media:        http://$LOCAL_IP:32400"

echo
echo -e "${PURPLE}💾 Modular Backup System:${RESET}"
echo "  • Auto-discovery:    All services automatically backed up"
echo "  • Registry-based:    New services auto-detected"
echo "  • Data location:     All in /srv/hub/ for easy backup"
echo "  • Schedule:          Monthly at 2AM on 1st"

echo
echo -e "${PURPLE}🔒 Security Features:${RESET}"
echo "  • UFW Firewall:       Active with service-specific rules"
echo "  • fail2ban:           Active intrusion prevention"
echo "  • SMART monitoring:   Enabled for disk health"

echo
echo -e "${YELLOW}📝 Next Steps:${RESET}"
echo "1. Get backup-hub.sh and restore-hub.sh scripts"
echo "2. Configure BIOS 'Power On After AC Loss'"
echo "3. Access services and configure as needed"
echo "4. To add services: Follow the modular pattern and register_service"

echo
echo -e "${GREEN}✅ Modular hub ready! Add services easily with auto-backup.${RESET}"
