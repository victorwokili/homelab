#!/usr/bin/env bash
#
# nuc-hub.sh  —  Turn a Lenovo ThinkCentre (i5-7500T) on Ubuntu 22.04 LTS
# into a self-updating Smart Home Hub + Mini-Lab with extra fun services,
# including proper Pi-hole deployment on port 53.
#
# Run as:
#   chmod +x ~/scripts/nuc-hub.sh
#   ~/scripts/nuc-hub.sh
#

set -euo pipefail

# ─── COLOR DEFINITIONS ───────────────────────────────────────────────────────────
RESET="\e[0m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"

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

echo
echo -e "${BLUE}#############################################${RESET}"
echo -e "${BLUE}# Starting ThinkCentre Hub Setup on Ubuntu #${RESET}"
echo -e "${BLUE}#############################################${RESET}"
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

info "Installing prerequisites (curl, wget, etc.)…"
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release software-properties-common
done_msg "Prerequisite packages installed."
echo

### 2) Install Node.js (v20.x) ###
info "Installing Node.js 20.x LTS…"
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - >/dev/null
sudo apt-get install -y nodejs >/dev/null
NODE_VER="$(node --version 2>/dev/null || echo 'not installed')"
done_msg "Node.js $NODE_VER installed."
echo

### 3) Install Docker & Docker Compose Plugin ###
info "Installing Docker CE + Docker Compose plugin…"
# Add Docker’s GPG key & repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
done_msg "Docker and Docker Compose plugin installed."
echo

### 4) Add 'victor' to docker & dialout Groups ###
info "Adding user 'victor' to docker & dialout groups…"
sudo usermod -aG docker victor
sudo usermod -aG dialout victor
done_msg "'victor' is now in docker & dialout groups."
warn "You should log out and log back in (or reboot) soon so 'victor' can use Docker without sudo."
echo

### 5) Create /srv/hub Directory Structure ###
info "Creating /srv/hub directories for configs…"
sudo mkdir -p /srv/hub/mosquitto/config     && sudo mkdir -p /srv/hub/mosquitto/data
sudo mkdir -p /srv/hub/zigbee2mqtt/data
sudo mkdir -p /srv/hub/homeassistant/config
sudo mkdir -p /srv/hub/homebridge/config
sudo mkdir -p /srv/hub/scrypted/volume
sudo mkdir -p /srv/hub/heimdall/config
sudo mkdir -p /srv/hub/pihole/config     && sudo mkdir -p /srv/hub/pihole/dnsmasq.d
sudo mkdir -p /srv/hub/plex/config        && sudo mkdir -p /srv/hub/plex/tvseries    && sudo mkdir -p /srv/hub/plex/movies
sudo mkdir -p /srv/hub/influxdb/config    && sudo mkdir -p /srv/hub/influxdb/data
sudo mkdir -p /srv/hub/grafana/data
sudo mkdir -p /srv/hub/uptime/data
sudo mkdir -p /srv/hub/samba/share
sudo chown -R victor:victor /srv/hub
done_msg "/srv/hub structure created."
echo

### 6) Deploy Portainer ###
info "Deploying Portainer (Docker GUI)…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw portainer; then
  done_msg "Portainer container already exists, skipping."
else
  sudo docker run -d \
    -p 9000:9000 \
    --name=portainer \
    --restart unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
  done_msg "Portainer is running at http://$LOCAL_IP:9000"
fi
echo

### 7) Deploy Watchtower (Auto-update Containers) ###
info "Deploying Watchtower…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw watchtower; then
  done_msg "Watchtower container already exists, skipping."
else
  sudo docker run -d \
    --name=watchtower \
    --restart unless-stopped \
    -v /var/run/docker.sock:/var/run/docker.sock \
    containrrr/watchtower \
    --cleanup \
    --interval 300
  done_msg "Watchtower is running (checks every 5 minutes)."
fi
echo

### 8) Deploy Mosquitto (MQTT Broker) ###
info "Deploying Mosquitto (MQTT Broker)…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw mosquitto; then
  done_msg "Mosquitto container already exists, skipping."
else
  if [ ! -f /srv/hub/mosquitto/config/mosquitto.conf ]; then
    cat << 'EOF' | sudo tee /srv/hub/mosquitto/config/mosquitto.conf >/dev/null
# Mosquitto MQTT broker config (anonymous, persistent)
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest stdout
EOF
  fi

  sudo docker run -d \
    --name mosquitto \
    --restart unless-stopped \
    -p 1883:1883 \
    -v /srv/hub/mosquitto/config/mosquitto.conf:/mosquitto/config/mosquitto.conf:ro \
    -v /srv/hub/mosquitto/data:/mosquitto/data \
    eclipse-mosquitto:latest
  done_msg "Mosquitto MQTT is running on port 1883."
fi
echo

### 9) Deploy Zigbee2MQTT (only if a Zigbee adapter exists) ###
info "Deploying Zigbee2MQTT…"
ZIGBEE_DEVICE=""
if [ -e /dev/ttyACM0 ]; then
  ZIGBEE_DEVICE="/dev/ttyACM0"
elif [ -e /dev/ttyUSB0 ]; then
  ZIGBEE_DEVICE="/dev/ttyUSB0"
fi

if [ -z "$ZIGBEE_DEVICE" ]; then
  warn "No Zigbee adapter detected at /dev/ttyACM0 or /dev/ttyUSB0. Skipping Zigbee2MQTT."
else
  if sudo docker ps -a --format '{{.Names}}' | grep -qw zigbee2mqtt; then
    done_msg "Zigbee2MQTT container already exists, skipping."
  else
    if [ ! -f /srv/hub/zigbee2mqtt/data/configuration.yaml ]; then
      cat << 'EOF' | sudo tee /srv/hub/zigbee2mqtt/data/configuration.yaml >/dev/null
homeassistant: false
permit_join: true
mqtt:
  base_topic: zigbee2mqtt
  server: 'mqtt://localhost:1883'
  user: ''
  password: ''
serial:
  port: 'ZIGBEE_PORT_PLACEHOLDER'
devices: []
EOF
      sudo sed -i "s|ZIGBEE_PORT_PLACEHOLDER|$ZIGBEE_DEVICE|" /srv/hub/zigbee2mqtt/data/configuration.yaml
    fi

    sudo docker run -d \
      --name zigbee2mqtt \
      --restart unless-stopped \
      --device="$ZIGBEE_DEVICE" \
      --net=host \
      -v /srv/hub/zigbee2mqtt/data:/app/data \
      -v /run/udev:/run/udev:ro \
      -e TZ="$(timedatectl show --value --property=Timezone)" \
      koenkk/zigbee2mqtt:latest
    done_msg "Zigbee2MQTT is running (UI at http://$LOCAL_IP:8081)."
  fi
fi
echo

### 10) Deploy Scrypted ###
info "Deploying Scrypted (Camera/Doorbell Hub)…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw scrypted; then
  done_msg "Scrypted container already exists, skipping."
else
  sudo docker run -d \
    --name scrypted \
    --restart unless-stopped \
    --network host \
    -v /srv/hub/scrypted/volume:/server/volume \
    koush/scrypted:latest
  done_msg "Scrypted is running (UI at https://$LOCAL_IP:10443)."
fi
echo

### 11) Deploy Heimdall ###
info "Deploying Heimdall (Dashboard)…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw heimdall; then
  done_msg "Heimdall container already exists, skipping."
else
  sudo docker run -d \
    --name heimdall \
    --restart unless-stopped \
    -e PUID=1000 \
    -e PGID=1000 \
    -v /srv/hub/heimdall/config:/config \
    -p 8201:80 \
    linuxserver/heimdall:latest
  done_msg "Heimdall is running (UI at http://$LOCAL_IP:8201)."
fi
echo

### 12) Deploy Homebridge ###
info "Deploying Homebridge (HomeKit Bridge)…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw homebridge; then
  done_msg "Homebridge container already exists, skipping."
else
  sudo docker run -d \
    --name homebridge \
    --restart unless-stopped \
    --network host \
    -e PUID=1000 \
    -e PGID=1000 \
    -e TZ="$(timedatectl show --value --property=Timezone)" \
    -e HOMEBRIDGE_CONFIG_UI=1 \
    -e HOMEBRIDGE_CONFIG_UI_PORT=8581 \
    -v /srv/hub/homebridge/config:/homebridge \
    oznu/homebridge:latest
  done_msg "Homebridge is running (UI at http://$LOCAL_IP:8581)."
fi
echo

### 13) Deploy Home Assistant (Container) ###
info "Deploying Home Assistant (Home Automation)…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw homeassistant; then
  done_msg "Home Assistant container already exists, skipping."
else
  sudo docker run -d \
    --name homeassistant \
    --restart unless-stopped \
    -v /srv/hub/homeassistant/config:/config \
    --privileged \
    --network host \
    ghcr.io/home-assistant/home-assistant:stable
  done_msg "Home Assistant is running (UI at http://$LOCAL_IP:8123)."
fi
echo

### 14) Deploy Plex Media Server ###
info "Deploying Plex Media Server…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw plex; then
  done_msg "Plex container already exists, skipping."
else
  sudo docker run -d \
    --name plex \
    --restart unless-stopped \
    -e PUID=1000 \
    -e PGID=1000 \
    -e TZ="$(timedatectl show --value --property=Timezone)" \
    -e PLEX_CLAIM="" \
    -v /srv/hub/plex/config:/config \
    -v /srv/hub/plex/tvseries:/data/tvshows \
    -v /srv/hub/plex/movies:/data/movies \
    -p 32400:32400 \
    linuxserver/plex:latest
  done_msg "Plex Media Server is running (UI at http://$LOCAL_IP:32400)."
fi
echo
### 15) Deploy InfluxDB (with admin/admin setup) ###
info "Deploying InfluxDB (Time-series database)…"

# 15a) Remove any existing influxdb container
if sudo docker ps -a --format '{{.Names}}' | grep -qw influxdb; then
  warn "Removing old InfluxDB container..."
  sudo docker stop influxdb >/dev/null 2>&1 || true
  sudo docker rm influxdb >/dev/null 2>&1 || true
  done_msg "Old InfluxDB container removed."
fi

# 15b) Ensure proper ownership of InfluxDB directories
sudo chown -R 1000:1000 /srv/hub/influxdb/config /srv/hub/influxdb/data

# 15c) Run InfluxDB in setup mode with predefined credentials
sudo docker run -d \
  --name influxdb \
  --restart unless-stopped \
  -v /srv/hub/influxdb/config:/etc/influxdb2 \
  -v /srv/hub/influxdb/data:/var/lib/influxdb2 \
  -p 8086:8086 \
  -e DOCKER_INFLUXDB_INIT_MODE=setup \
  -e DOCKER_INFLUXDB_INIT_USERNAME=admin \
  -e DOCKER_INFLUXDB_INIT_PASSWORD=adminpassword \
  -e DOCKER_INFLUXDB_INIT_ORG=homelab \
  -e DOCKER_INFLUXDB_INIT_BUCKET=default \
  -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=my-super-secret-auth-token \
  influxdb:2

# 15d) Wait for InfluxDB to be ready
info "Waiting for InfluxDB to start up..."
sleep 10
for i in {1..30}; do
  if sudo docker logs influxdb 2>&1 | grep -q "Listening"; then
    done_msg "InfluxDB is ready!"
    break
  fi
  if [ $i -eq 30 ]; then
    error "InfluxDB failed to start properly. Check logs with: docker logs influxdb"
    break
  fi
  sleep 2
done

done_msg "InfluxDB is running (UI at http://$LOCAL_IP:8086) with user admin/adminpassword."

### 16) Deploy Grafana ###
info "Deploying Grafana (Metrics & Dashboards)…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw grafana; then
  done_msg "Grafana container already exists, skipping."
else
  sudo docker run -d \
    --name grafana \
    --restart unless-stopped \
    -v /srv/hub/grafana/data:/var/lib/grafana \
    -p 3000:3000 \
    grafana/grafana:latest
  done_msg "Grafana is running (UI at http://$LOCAL_IP:3000)."
fi
echo

### 17) Deploy Pi-hole (Network-wide Ad Blocker) ###
info "Deploying Pi-hole (Network-wide Ad Blocker)…"

# 17a) Disable & stop systemd-resolved so nothing else holds port 53
if systemctl is-active --quiet systemd-resolved; then
  warn "Stopping and disabling systemd-resolved so Pi-hole can bind to port 53..."
  sudo systemctl disable --now systemd-resolved
  sudo rm -f /etc/resolv.conf
  echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf >/dev/null
  done_msg "systemd-resolved disabled; /etc/resolv.conf now set to 1.1.1.1"
fi

# 17b) Stop & remove any existing Pi-hole container, to force re-creation
if sudo docker ps -a --format '{{.Names}}' | grep -qw pihole; then
  warn "Stopping and removing old Pi-hole container..."
  sudo docker stop pihole >/dev/null 2>&1 || true
  sudo docker rm pihole   >/dev/null 2>&1 || true
  done_msg "Old Pi-hole container removed."
fi

# 17c) Ensure port 53 is free on the host
if ss -ltn | grep -q ':53 '; then
  error "Port 53 is still in use on the host. Cannot start Pi-hole."
else
  info "Port 53 is free. Creating new Pi-hole container..."
  sudo docker run -d \
    --name pihole \
    --restart unless-stopped \
    -e TZ="$(timedatectl show --value --property=Timezone)" \
    -e WEBPASSWORD="changeme" \
    -v /srv/hub/pihole/config:/etc/pihole \
    -v /srv/hub/pihole/dnsmasq.d:/etc/dnsmasq.d \
    -p 53:53/tcp -p 53:53/udp \
    -p 80:80 \
    pihole/pihole:latest >/dev/null

  done_msg "Pi-hole container created; waiting for it to start listening on port 53…"

  # 17d) Wait up to 30 seconds for Pi-hole to bind to port 53
  SECONDS=0
  while (( SECONDS < 30 )); do
    if ss -ltn | grep -q ':53 ' && ss -lnup | grep -q ':53 '; then
      done_msg "Pi-hole is now listening on port 53."
      break
    fi
    sleep 1
  done

  if (( SECONDS >= 30 )); then
    error "Timed out waiting for Pi-hole to bind to port 53. Check 'docker logs pihole' for details."
  fi
fi
echo

### 18) Deploy Uptime Kuma ###
info "Deploying Uptime Kuma (Self-hosted monitoring)…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw uptime-kuma; then
  done_msg "Uptime Kuma container already exists, skipping."
else
  sudo docker run -d \
    --name uptime-kuma \
    --restart unless-stopped \
    -v /srv/hub/uptime/data:/app/data \
    -p 3001:3001 \
    louislam/uptime-kuma:latest
  done_msg "Uptime Kuma is running (UI at http://$LOCAL_IP:3001)."
fi
echo

### 19) Deploy Netdata (Real-Time System Monitoring) ###
info "Deploying Netdata (real-time system monitoring)…"
if sudo docker ps -a --format '{{.Names}}' | grep -qw netdata; then
  done_msg "Netdata container already exists, skipping."
else
  sudo docker run -d \
    --name netdata \
    --cap-add SYS_PTRACE \
    --cap-add SYS_NICE \
    --restart unless-stopped \
    -p 19999:19999 \
    -v netdata_lib:/var/lib/netdata \
    -v netdata_cache:/var/cache/netdata \
    -v /etc/passwd:/host/etc/passwd:ro \
    -v /etc/group:/host/etc/group:ro \
    -v /proc:/host/proc:ro \
    -v /sys:/host/sys:ro \
    -v /etc/os-release:/host/etc/os-release:ro \
    netdata/netdata:latest
  done_msg "Netdata is running (UI at http://$LOCAL_IP:19999)."
fi
echo

### 20) Create Backup Script for /srv/hub ###
info "Creating /home/victor/backup-hub.sh for monthly backups…"
BACKUP_SCRIPT="/home/victor/backup-hub.sh"

cat << 'EOF' > "$BACKUP_SCRIPT"
#!/usr/bin/env bash
#
# backup-hub.sh  —  Create a timestamped tarball of /srv/hub
# Usage: /home/victor/backup-hub.sh
#

set -euo pipefail

# Colors for interactive readability
RESET="\e[0m"
GREEN="\e[32m"
BLUE="\e[34m"

function info {
  echo -e "${BLUE}[INFO]${RESET}  $1"
}
function done_msg {
  echo -e "${GREEN}[DONE]${RESET}  $1"
}

TIMESTAMP="$(date +%F_%H%M)"
DEST_DIR="/home/victor/backups"
ARCHIVE_NAME="hub-backup-$TIMESTAMP.tar.gz"
DEST_PATH="$DEST_DIR/$ARCHIVE_NAME"

info "Ensuring $DEST_DIR exists..."
mkdir -p "$DEST_DIR"

info "Packaging /srv/hub → $DEST_PATH ..."
sudo tar czf "$DEST_PATH" -C /srv hub

done_msg "Backup complete: $ARCHIVE_NAME"
EOF

chmod +x "$BACKUP_SCRIPT"
done_msg "Backup script created at $BACKUP_SCRIPT"
echo

### 21) Schedule Monthly Cron Job for Backup ###
info "Scheduling monthly backup via cron (02:00 AM on day 1)…"
CRON_BACKUP_FILE="/etc/cron.d/hub-backup"
sudo bash -c "cat << 'CRON_EOF' > $CRON_BACKUP_FILE
# Run backup-hub.sh at 02:00 on the 1st of every month as user 'victor'
0 2 1 * * victor /home/victor/backup-hub.sh >/dev/null 2>&1
CRON_EOF"
sudo chmod 644 "$CRON_BACKUP_FILE"
done_msg "Cron job written to $CRON_BACKUP_FILE"
echo

### 22) Schedule Monthly Cron Job for Self-Healing Script ###
info "Scheduling monthly self-healing script via cron (03:00 AM on day 2)…"
CRON_SELFHEAL_FILE="/etc/cron.d/monthly-self-healing"
SCRIPT_PATH="/home/victor/scripts/nuc-hub.sh"

sudo bash -c "cat << 'CRON2_EOF' > $CRON_SELFHEAL_FILE
# Run nuc-hub.sh at 03:00 on the 2nd of every month as user 'victor'
0 3 2 * * victor $SCRIPT_PATH >/dev/null 2>&1
CRON2_EOF"
sudo chmod 644 "$CRON_SELFHEAL_FILE"
done_msg "Cron job written to $CRON_SELFHEAL_FILE"
echo

### 23) Install & Configure Unattended-Upgrades ###
info "Installing unattended-upgrades for automatic security updates…"
sudo apt-get update >/dev/null
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades apt-listchanges >/dev/null
done_msg "unattended-upgrades package installed"
echo

info "Configuring unattended-upgrades to apply security updates automatically…"
sudo bash -c 'cat << "UPG_CNF" > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
UPG_CNF'
sudo sed -i 's|//   "o=Ubuntu,a=noble-security";|   "o=Ubuntu,a=noble-security";|' \
    /etc/apt/apt.conf.d/50unattended-upgrades
done_msg "unattended-upgrades configured for daily security updates"
echo

info "Enabling and starting the unattended-upgrades service…"
sudo systemctl enable unattended-upgrades >/dev/null
sudo systemctl start unattended-upgrades
done_msg "unattended-upgrades service is active"
echo

### 24) BIOS Reminder: Auto Power-On After AC Loss ###
info "Reminder: Configure BIOS to 'Power On After AC Loss'…"
echo -e "${YELLOW}Please reboot your ThinkCentre and enter BIOS/UEFI to set:${RESET}"
echo -e "   → Power Management → Restore on AC/Power Loss → ${GREEN}Power On${RESET}"
echo -e "${YELLOW}This ensures the machine will automatically boot after a power outage.${RESET}"
echo

### 25) Final Summary & All Service IPs/Ports ###
echo -e "${GREEN}###############################################################${RESET}"
echo -e "${GREEN}#                                                           #${RESET}"
echo -e "${GREEN}#  Smart-Home + Mini-Lab Stack Is Now Running!               #${RESET}"
echo -e "${GREEN}#                                                           #${RESET}"
echo -e "${GREEN}###############################################################${RESET}"
echo

echo -e "${BLUE}Access your services at:${RESET}"
echo "  • Portainer:         http://$LOCAL_IP:9000"
echo "  • Zigbee2MQTT UI:    http://$LOCAL_IP:8081  (if Zigbee dongle present)"
echo "  • Scrypted:          https://$LOCAL_IP:10443"
echo "  • Homebridge UI:     http://$LOCAL_IP:8581"
echo "  • Heimdall:          http://$LOCAL_IP:8201"
echo "  • Home Assistant:    http://$LOCAL_IP:8123"
echo "  • Plex Media Server: http://$LOCAL_IP:32400"
echo "  • InfluxDB API:      http://$LOCAL_IP:8086"
echo "  • Grafana UI:        http://$LOCAL_IP:3000"
echo "  • Pi-hole UI:        http://$LOCAL_IP/admin"
echo "  • Uptime Kuma:       http://$LOCAL_IP:3001"
echo "  • Netdata:           http://$LOCAL_IP:19999"

echo
echo "Monthly backups of /srv/hub run at 02:00 on the 1st of each month."
echo "The nuc-hub.sh script re-runs at 03:00 on the 2nd of each month."
echo "Nightly security updates via unattended-upgrades ensure OS patches."
echo -e "${YELLOW}Don't forget to configure BIOS 'Power On After AC Loss'.${RESET}"
echo
