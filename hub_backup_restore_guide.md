# Smart Home Hub Backup & Restore System

A comprehensive backup and restore solution for your smart home hub that automatically protects all your configurations, data, and settings.

## 📋 Table of Contents
- [Overview](#overview)
- [Quick Start](#quick-start)
- [Scripts](#scripts)
- [Setting Up Automated Backups](#setting-up-automated-backups)
- [Monitoring Your Backups](#monitoring-your-backups)
- [Restoring from Backup](#restoring-from-backup)
- [Troubleshooting](#troubleshooting)

## 🎯 Overview

This backup system protects your smart home hub by:
- **📁 Backing up configurations only** - Not the containers themselves
- **🔄 Automated scheduling** - Monthly backups, weekly verification, daily cleanup
- **🔍 Self-monitoring** - Detects corrupted backups and alerts you
- **⚡ Fast restore** - Fresh containers with your exact configurations
- **💾 Space efficient** - Only keeps what's essential

### What Gets Backed Up
✅ All service configurations (Home Assistant, Grafana, etc.)  
✅ Your dashboards, automations, and custom settings  
✅ Historical data (sensor readings, logs, etc.)  
✅ Service registry and hub metadata  
✅ Essential system configurations  

### What Doesn't Get Backed Up
❌ Docker containers (rebuilt fresh during restore)  
❌ Docker images (downloaded fresh during restore)  
❌ Operating system files  
❌ Temporary files and caches  

## 🚀 Quick Start

1. **Download the scripts** (backup-hub.sh and restore-hub.sh)
2. **Make them executable:**
   ```bash
   chmod +x backup-hub.sh restore-hub.sh
   ```
3. **Set up automated backups:**
   ```bash
   ./backup-hub.sh --setup-schedule
   ```
4. **Verify everything is working:**
   ```bash
   sudo cat /etc/cron.d/hub-backup-schedule
   ```

That's it! Your hub is now protected with automated backups.

## 📜 Scripts

[backup-hub.sh](https://github.com/victorwokili/homelab/blob/main/nuc-hub.sh)

[restore-hub.sh](https://github.com/victorwokili/homelab/blob/main/restore-hub.sh)

