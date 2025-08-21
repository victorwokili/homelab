# 🏠 Self-Managing Smart Home Hub Setup

*Transform any Ubuntu system into a production-ready smart home hub with enterprise-level automation*

## 📖 What This Script Does

I got tired of manually managing my smart home services, dealing with broken containers, and worrying about losing my configurations. So I built this comprehensive setup script that creates a **bulletproof, self-healing smart home hub** that practically runs itself.

After running this once, you'll have 14+ services running in Docker containers, all automatically updating, backing themselves up, and monitoring their own health. It's designed for people who want enterprise-grade reliability without the enterprise-grade complexity.

## 🎯 Why I Built This

**The Problem:** Smart home setups are fragile. Containers stop working, configurations get lost, updates break things, and you spend more time fixing your automation than enjoying it.

**My Solution:** A completely modular, self-discovering system where:
- 🔄 Everything updates itself automatically  
- 💾 All data gets backed up without you thinking about it
- 🔍 New services you add are automatically included in monitoring and backups
- 🛡️ Security is handled automatically with firewalls and intrusion detection
- 📊 You get comprehensive monitoring dashboards out of the box

## 🏗️ What You Get

### 🏠 Smart Home Core
| Service | What It Does | Access |
|---------|-------------|---------|
| **Home Assistant** | Your main automation hub | `http://your-ip:8123` |
| **Zigbee2MQTT** | Manages all your Zigbee devices | `http://your-ip:8081` |
| **Mosquitto** | MQTT message broker for IoT | `mqtt://your-ip:1883` |
| **Homebridge** | Connects everything to Apple HomeKit | `http://your-ip:8581` |
| **Scrypted** | Camera and doorbell management | `https://your-ip:10443` |

### 🔧 Management Dashboard  
| Service | What It Does | Access |
|---------|-------------|---------|
| **Portainer** | Manage all your Docker containers | `http://your-ip:9000` |
| **Heimdall** | Beautiful dashboard for all services | `http://your-ip:8201` |
| **Uptime Kuma** | Monitor if services are running | `http://your-ip:3001` |

### 📊 Monitoring & Analytics
| Service | What It Does | Access |
|---------|-------------|---------|
| **Netdata** | Real-time system performance | `http://your-ip:19999` |
| **Grafana** | Beautiful charts and dashboards | `http://your-ip:3000` |
| **InfluxDB** | Stores all your sensor data | `http://your-ip:8086` |

### 🌐 Network & Media
| Service | What It Does | Access |
|---------|-------------|---------|
| **Pi-hole** | Blocks ads across your entire network | `http://your-ip/admin` |
| **Plex** | Stream your movies and TV shows | `http://your-ip:32400` |

### 🤖 Behind-the-Scenes Magic
- **Watchtower**: Automatically updates all containers every hour
- **UFW Firewall**: Protects your system with smart rules
- **fail2ban**: Automatically blocks suspicious IP addresses  
- **Automated Backups**: Monthly full system backups with 6-month retention

## 🚀 Quick Start

### Prerequisites
- Ubuntu 22.04 LTS or newer (I've tested it extensively on 22.04)
- At least 4GB RAM (8GB recommended if you want to run Plex smoothly)
- 20GB+ free disk space (more if you're storing media files)
- A user account with sudo privileges

### Installation

1. **Download the script:**
```bash
wget https://raw.githubusercontent.com/yourusername/smart-home-hub/main/enhanced-nuc-hub.sh
```

2. **Make it executable:**
```bash
chmod +x enhanced-nuc-hub.sh
```

3. **Run it (grab a coffee, takes about 10-15 minutes):**
```bash
./enhanced-nuc-hub.sh
```

4. **That's it!** The script will show you all the URLs when it's done.

## 🎛️ The Magic Behind the Scenes

### Self-Discovery Architecture

Here's the cool part - I designed this so you never have to manually update backup scripts or worry about new services being forgotten. Every service registers itself in a JSON registry:

```json
{
  "services": [
    {
      "name": "homeassistant",
      "data_path": "/srv/hub/homeassistant",
      "url": "http://192.xxx.x.xxx:8123",
      "service_type": "smart_home",
      "backup_priority": "critical"
    }
  ]
}
```

This means when you add new services later, they automatically get:
- ✅ Included in backups
- ✅ Added to monitoring
- ✅ Listed in your service dashboard
- ✅ Updated by Watchtower

### Standardized Data Storage

Everything lives in `/srv/hub/` with a predictable structure:
```
/srv/hub/
├── homeassistant/config/     # Your HA configuration
├── grafana/data/             # All your dashboards
├── influxdb/data/           # Years of sensor data
├── pihole/config/           # Your DNS settings
├── plex/media/              # Movies and TV shows
└── hub-registry.json        # The magic discovery file
```

This makes backups simple and reliable. No hunting around for config files scattered across the system.

## 💾 Bulletproof Backup System

### What Gets Backed Up
- **Every single configuration file** from all services
- **All your data** (dashboards, sensor history, etc.)
- **Container states** so everything starts exactly how you left it
- **System configurations** (firewall rules, scheduled jobs)
- **The service registry** so restore knows what to restore

### Backup Schedule
- 🗓️ **Monthly full backup** (1st of month at 2AM)
- 🔍 **Weekly verification** (makes sure backups aren't corrupted)
- 🧹 **Daily log cleanup** (prevents disk from filling up)
- 📊 **Real-time monitoring** (alerts if anything breaks)

### Easy Recovery
If disaster strikes, recovery is one command:
```bash
./restore-hub.sh /path/to/backup.tar.gz
```

It automatically:
- Stops all containers
- Restores all data to exact previous state  
- Brings everything back online
- Verifies all services are healthy

## 🛡️ Security That Actually Works

I've seen too many smart home setups that are basically wide open to the internet. This script sets up proper security layers:

### Firewall Protection
- Default deny all incoming connections
- Only allows specific ports for services you're actually using
- SSH access is maintained so you don't lock yourself out

### Intrusion Detection  
- fail2ban automatically blocks IPs that try suspicious stuff
- Monitors SSH, web services, and other attack vectors
- Temporary blocks escalate to permanent bans for persistent attackers

### Container Isolation
- Each service runs in its own container
- Services can't interfere with each other
- Easy to remove problematic services without affecting others

## 🔧 Adding New Services

I built a template system so adding new services is easy and they automatically integrate with everything else.

### Using the Template System

1. **Copy the template:**
```bash
cp /srv/hub/add-service-template.sh setup-newservice.sh
```

2. **Modify for your service:**
```bash
#!/usr/bin/env bash

SERVICE_NAME="your-service"
DATA_DIR="/srv/hub/$SERVICE_NAME"
sudo mkdir -p "$DATA_DIR/config"

# Deploy the container
sudo docker run -d \
  --name="$SERVICE_NAME" --restart unless-stopped \
  -p your-port:container-port \
  -v "$DATA_DIR/config":/config \
  your/container:latest

# This is the magic - register it for auto-discovery
register_service "$SERVICE_NAME" "$DATA_DIR" "$SERVICE_NAME" \
  "http://your-ip:port" "Service Description" "service_type" "priority"
```

3. **Run it:**
```bash
./setup-newservice.sh
```

Now your service is automatically included in backups, monitoring, and updates!

## 📊 Monitoring That Actually Helps

### Real-Time System Health
**Netdata** gives you gorgeous real-time charts of:
- CPU, memory, and disk usage
- Network traffic
- Container resource usage  
- Temperature monitoring
- Disk health (SMART data)

### Service Uptime Tracking
**Uptime Kuma** monitors all your services and can:
- Send notifications when something goes down
- Track response times
- Create beautiful status pages
- Integrate with Discord, Slack, email, etc.

### Custom Analytics
**Grafana + InfluxDB** lets you:
- Create stunning dashboards of your sensor data
- Track long-term trends
- Set up alerts for important metrics
- Correlate data across different services

## 🎯 Real-World Usage Tips

### Performance Tuning
- **Low-end hardware?** Disable Plex and reduce logging verbosity
- **High-end hardware?** Increase InfluxDB retention and add more Grafana plugins
- **SSD vs HDD:** Script works on both, but SSDs make everything much snappier

### Network Setup
- **Router configuration:** Point your DHCP to your Pi-hole IP for network-wide ad blocking
- **Port forwarding:** Only forward ports you actually need (the script tells you which ones)

### Maintenance Schedule
The system largely maintains itself, but I recommend:
- **Monthly:** Check the backup logs and test restore procedure
- **Quarterly:** Review Grafana dashboards and clean up old data
- **Yearly:** Update the base Ubuntu system and review security settings

## 🚨 Troubleshooting Common Issues

### Container Won't Start
```bash
# Check what went wrong
docker logs [container-name]

# Common fix: check data directory permissions
sudo chown -R victor:victor /srv/hub/[service-name]/
```

### Network Issues
```bash
# Check if Pi-hole is interfering with DNS
docker logs pihole

# Temporary DNS fix
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

### Port Conflicts
```bash
# See what's using a port
sudo netstat -tulpn | grep :8123

# Check firewall status
sudo ufw status
```

### Service Discovery Not Working
```bash
# Verify the registry file
cat /srv/hub/hub-registry.json | jq

# Manually rebuild if needed
./enhanced-nuc-hub.sh  # Safe to re-run
```

## 🔄 Updating and Maintenance

### Automatic Updates
- **Containers:** Watchtower handles this hourly
- **Security patches:** Ubuntu unattended-upgrades (if you enable it)
- **Script updates:** Re-run the script - it's designed to be safe

### Manual Maintenance
```bash
# Check all container status
docker ps

# View system resources
htop

# Check backup status
ls -la /home/victor/backups/

# Manual backup
/home/victor/backup-hub.sh
```

## 📊 Default Credentials

**Important:** Change these immediately after setup:

| Service | Username | Password | Notes |
|---------|----------|----------|--------|
| **Grafana** | admin | admin | Change on first login |
| **InfluxDB** | admin | adminpassword | Web UI at :8086 |
| **Pi-hole** | N/A | changeme | Web admin password |

All other services require setup through their web interfaces.

## 🔧 Script Architecture

### Key Features
- **Modular Design:** Each service is independent and can be safely removed
- **Self-Discovery:** New services automatically register for backups and monitoring
- **Idempotent:** Safe to run multiple times - won't break existing setup
- **Comprehensive Logging:** Full audit trail of all actions
- **Error Handling:** Graceful failure recovery and detailed error messages

### Directory Structure
```
/srv/hub/
├── [service-name]/           # Each service gets its own directory
├── hub-registry.json         # Service discovery database
├── hub-config.json          # System configuration
├── discovery-helper.sh      # Backup automation functions
├── add-service-template.sh  # Template for new services
└── logs/                    # Centralized logging
```

### Backup System
```
/home/victor/backups/
├── complete-hub-backup-YYYY-MM-DD_HH-MM-SS.tar.gz
├── backup.log               # Backup operation log
└── [older backups...]       # Automatic 6-month retention
```

## 🤝 Contributing

This script is designed to be community-driven and easily extensible. Contributions welcome for:

- **🔌 New service integrations**
- **🐛 Bug fixes and improvements**  
- **📖 Documentation updates**
- **🔧 Platform compatibility**
- **⚡ Performance optimizations**

### Service Addition Guidelines
When adding new services, ensure:
1. Follow the registration pattern in the template
2. Use standardized data paths (`/srv/hub/[service-name]/`)
3. Include proper service metadata (type, priority, description)
4. Add firewall rules if needed
5. Test backup/restore functionality

## 📄 License

MIT License - feel free to use, modify, and distribute as needed.

---

**🏆 Built with ❤️ for the smart home community. Questions? Issues? Want to contribute? Open an issue or submit a PR!**

*This script represents hundreds of hours of testing, refinement, and real-world usage. It's the setup I actually use in my own home, and I'm confident it will serve you well.*
