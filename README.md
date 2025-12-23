### 1. MASTER_MANUAL.md (v1.3.5)

* **Change:** Updated Version Header.
* **Note:** This document remains the ground truth for architecture.

```markdown
# 📘 Home Lab Master Architecture & Recovery Guide

**Version:** 1.3.5 (Stability Patch / DNS & Nextcloud Fixes)
**Timezone:** `Asia/Kuala_Lumpur` (UTC+8)

## 🏗️ Architecture Overview

| Node | Hostname | IP (LAN) | IP (WireGuard) | Key Services |
| --- | --- | --- | --- | --- |
| **OCI Gateway** | `instance-xxxx` | Public IP | `10.66.66.1` | Internet Gateway, VPN Hub, Monitoring |
| **Sentinel** | `sentinel` | `192.168.1.2` | `10.66.66.3` | Control Plane, **NFS Server (Cold Storage)** |
| **Forge** | `forge` | `192.168.1.3` | `10.66.66.5` | Data Plane, **NFS Client**, Media Stack, IRC, Autobrr |

---

## 🛑 Phase 0: System Bootstrap (Run Once)

### 1. Basic Setup (Run on ALL 3 Machines)

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install curl vim git htop net-tools wireguard resolvconf iptables-persistent rclone -y
curl -fsSL [https://get.docker.com](https://get.docker.com) | sh
sudo usermod -aG docker $USER
sudo timedatectl set-timezone Asia/Kuala_Lumpur

```

### 2. Monitoring Agent (Run on ALL 3 Machines)

*We install Glances in Web Server mode for the Dashboard.*

```bash
sudo apt install glances python3-bottle -y

# Create Service (Force Web Mode + All Interfaces)
sudo tee /etc/systemd/system/glances.service > /dev/null <<EOF
[Unit]
Description=Glances Web Server
After=network.target

[Service]
ExecStart=/usr/bin/glances -w -p 61208
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now glances

```

### 3. OCI Gateway Specifics

* **Oracle Firewall:** Allow Ingress UDP 51820.
* **IP Forwarding:** Edit `/etc/sysctl.conf` -> `net.ipv4.ip_forward=1` -> `sudo sysctl -p`.

### 4. Sentinel Specifics

```bash
sudo hostnamectl set-hostname sentinel
sudo vim /etc/hosts # Update 127.0.1.1 to sentinel
mkdir -p /home/boyi/homeassistant/config
mkdir -p /home/boyi/mosquitto/config
mkdir -p /home/boyi/mosquitto/data
mkdir -p /home/boyi/mosquitto/log
mkdir -p /home/boyi/adguard/work
mkdir -p /home/boyi/adguard/conf
mkdir -p /home/boyi/homepage/config
mkdir -p /home/boyi/homepage/icons # Local Icons Host Folder
mkdir -p /home/boyi/backups
sudo chown -R 1883:1883 /home/boyi/mosquitto

```

### 5. Forge Specifics

```bash
sudo hostnamectl set-hostname forge
sudo vim /etc/hosts # Update 127.0.1.1 to forge

# Mount NVMe
sudo mkdir -p /media/storage
sudo mount -a

# Create Directories
sudo mkdir -p /media/storage/{movies,tv,downloads,config,nextcloud_data}
sudo mkdir -p /media/storage/config/{cross-seed,thelounge,autobrr}
sudo chown -R 1000:1000 /media/storage

# Create App Configs
mkdir -p /home/boyi/adguard/{work,conf}
mkdir -p /home/boyi/nextcloud/{db,html}
mkdir -p /home/boyi/portainer-agent

# Permissions
sudo chown -R 33:33 /media/storage/nextcloud_data
sudo chown -R 33:33 /home/boyi/nextcloud/html

```

---

## 🌍 Phase 1: OCI Gateway Configuration

### A. Firewall (IPTables)

```bash
# WireGuard & Monitoring
sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT
sudo iptables -I INPUT -i wg0 -p icmp -j ACCEPT
sudo iptables -I INPUT -i wg0 -p tcp --dport 61208 -j ACCEPT # Glances
sudo iptables -I INPUT -i wg0 -p tcp --dport 8080 -j ACCEPT  # Bandwidth API
# Routing
sudo iptables -t nat -A POSTROUTING -o enp0s6 -j MASQUERADE
sudo netfilter-persistent save

```

### B. Monitoring Services (Systemd)

**1. Glances** (Created in Phase 0)

**2. Bandwidth API**

* **Source File:** `bandwidth-web.service`
* **Destination:** `/etc/systemd/system/bandwidth-web.service`

```bash
sudo cp bandwidth-web.service /etc/systemd/system/
sudo systemctl enable --now bandwidth-web

```

### C. Scripts (in `/usr/local/bin/`)

**1. `vnstat-json.sh**` (Dashboard Feed)

* **Source File:** `vnstat-json.sh`
* **Destination:** `/usr/local/bin/vnstat-json.sh`

```bash
sudo cp vnstat-json.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/vnstat-json.sh

```

**2. `oci_report.sh**` (Telegram Bot - Bandwidth)

* **Source File:** `oci_report.sh`
* **Destination:** `/usr/local/bin/oci_report.sh`

```bash
sudo cp oci_report.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/oci_report.sh

```

**3. `monitor_lab.sh**` (Port-Aware Watchtower)

* **Source File:** `monitor_lab.sh`
* **Destination:** `/usr/local/bin/monitor_lab.sh`

```bash
sudo cp monitor_lab.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/monitor_lab.sh

```

**4. `wg_manager.sh**` (Access Control - Ghost Hunter)

* **Source File:** `wg_manager.sh`
* **Destination:** `/usr/local/bin/wg_manager.sh`

```bash
sudo cp wg_manager.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/wg_manager.sh

```

### D. Cron Schedule (OCI)

*Run `sudo crontab -e*`

```bash
# Telegram Bandwidth Report (Daily at 08:00 MYT / 00:00 UTC)
0 8 * * * /usr/local/bin/oci_report.sh

# Update Dashboard Stats (Every 10 mins)
*/10 * * * * /usr/local/bin/vnstat-json.sh

# Watchtower Health Check (Every 5 mins)
*/5 * * * * /usr/local/bin/monitor_lab.sh

```

---

## 🧠 Phase 2: Sentinel (Control Node)

### A. System Config (DNS & Firewall)

**1. Configure DNS (`/etc/resolv.conf`)**
**Critical:** We must include Google DNS (`8.8.8.8`) as the 3rd option.

*Edit:* `sudo vim /etc/resolv.conf`

```text
nameserver 127.0.0.1
nameserver 10.66.66.5
nameserver 8.8.8.8

```

*Lock the file:* `sudo chattr +i /etc/resolv.conf`

**2. Firewall (IPTables):**

```bash
# TRUSTED INTERNAL (Forge) - Allow ALL traffic (Fixes NFS hangs)
sudo iptables -I INPUT -s 192.168.1.3 -j ACCEPT

# Apps
sudo iptables -I INPUT -p tcp --dport 3000 -j ACCEPT  # Homepage
sudo iptables -I INPUT -p tcp --dport 9443 -j ACCEPT  # Portainer
sudo iptables -I INPUT -p tcp --dport 8085 -j ACCEPT  # AdGuard (Admin)
sudo iptables -I INPUT -p tcp --dport 53 -j ACCEPT    # DNS
sudo iptables -I INPUT -p udp --dport 53 -j ACCEPT    # DNS
sudo iptables -I INPUT -p tcp --dport 8123 -j ACCEPT  # HA
sudo iptables -I INPUT -p tcp --dport 1883 -j ACCEPT  # MQTT
sudo iptables -I INPUT -p tcp --dport 61208 -j ACCEPT # Glances
sudo iptables -I INPUT -i lo -j ACCEPT
sudo netfilter-persistent save

```

### B. NFS Server (Cold Storage)

We export a directory to Forge to utilize Sentinel's free space.

**1. Install & Create:**

```bash
sudo apt update
sudo apt install nfs-kernel-server -y
mkdir -p /home/boyi/sentinel_media
sudo chown -R 1000:1000 /home/boyi/sentinel_media
sudo chmod 775 /home/boyi/sentinel_media

```

**2. Configure Export (`/etc/exports`):**
*Edit:* `sudo vim /etc/exports`
*Append this line:*

```text
/home/boyi/sentinel_media 192.168.1.3(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)

```

**3. Apply:**

```bash
sudo exportfs -a
sudo systemctl restart nfs-kernel-server

```

### C. Dashboard Config (`homepage`)

**1. `services.yaml**`

* **Source File:** `services.yaml`
* **Destination:** `/home/boyi/homepage/config/services.yaml`

```bash
cp services.yaml /home/boyi/homepage/config/

```

**2. `widgets.yaml**`

* **Source File:** `widgets.yaml`
* **Destination:** `/home/boyi/homepage/config/widgets.yaml`

```bash
cp widgets.yaml /home/boyi/homepage/config/

```

### D. Portainer Server & Stacks (YAML)

**1. `smarthome**`

```yaml
services:
  homeassistant:
    image: "homeassistant/home-assistant:stable"
    volumes:
      - /home/boyi/homeassistant/config:/config
      - /etc/localtime:/etc/localtime:ro
    restart: unless-stopped
    network_mode: host
    privileged: true
  mosquitto:
    image: eclipse-mosquitto
    restart: unless-stopped
    ports: ["1883:1883"]
    volumes:
      - /home/boyi/mosquitto/config:/mosquitto/config
      - /home/boyi/mosquitto/data:/mosquitto/data

```

**2. `adguard-sync**`

```yaml
services:
  adguard:
    image: adguard/adguardhome
    restart: unless-stopped
    network_mode: host
    volumes:
      - /home/boyi/adguard/work:/opt/adguardhome/work
      - /home/boyi/adguard/conf:/opt/adguardhome/conf
    # NOTE: Set bind_port: 8085 in AdGuardHome.yaml

  adguardhome-sync:
    image: ghcr.io/bakito/adguardhome-sync:latest
    restart: unless-stopped
    ports: ["8080:8080"]
    environment:
      - CRON=*/10 * * * *
      - ORIGIN_URL=[http://192.168.1.2:8085](http://192.168.1.2:8085)
      - REPLICA1_URL=[http://192.168.1.3:8085](http://192.168.1.3:8085)
      # Add Credentials

```

**3. `dashboard**`

```yaml
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    ports: ["3000:3000"]
    volumes:
      - /home/boyi/homepage/config:/app/config
      - /home/boyi/homepage/icons:/app/public/icons # Local Icon Mount
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - HOMEPAGE_ALLOWED_HOSTS=*
    restart: unless-stopped

```

---

## 🦾 Phase 3: Forge (Media Node)

### A. System Config (DNS & Kernel)

**1. Configure DNS (`/etc/resolv.conf`)**
*Edit:* `sudo vim /etc/resolv.conf`

```text
nameserver 127.0.0.1
nameserver 10.66.66.3
nameserver 8.8.8.8

```

*Lock the file:* `sudo chattr +i /etc/resolv.conf`

**2. Kernel Tweak (MANDATORY):** Disable `rp_filter`.

```bash
echo "net.ipv4.conf.all.rp_filter=0" | sudo tee -a /etc/sysctl.d/99-gluetun.conf
echo "net.ipv4.conf.default.rp_filter=0" | sudo tee -a /etc/sysctl.d/99-gluetun.conf
sudo sysctl -p /etc/sysctl.d/99-gluetun.conf

```

**3. Firewall (IPTables):**

```bash
# Infrastructure
sudo iptables -I INPUT -p tcp --dport 9001 -j ACCEPT  # Agent
sudo iptables -I INPUT -p tcp --dport 8081 -j ACCEPT  # Nextcloud
# Media Stack
sudo iptables -I INPUT -p tcp --dport 8096 -j ACCEPT  # Jellyfin
sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT  # qBit
sudo iptables -I INPUT -p tcp --dport 9696 -j ACCEPT  # Prowlarr
sudo iptables -I INPUT -p tcp --dport 7878 -j ACCEPT  # Radarr
sudo iptables -I INPUT -p tcp --dport 8989 -j ACCEPT  # Sonarr
sudo iptables -I INPUT -p tcp --dport 6767 -j ACCEPT  # Bazarr
sudo iptables -I INPUT -p tcp --dport 7474 -j ACCEPT  # Autobrr
# Cross-Seed / The Lounge
sudo iptables -I INPUT -p tcp --dport 2468 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 9000 -j ACCEPT
# AdGuard Replica
sudo iptables -I INPUT -p tcp --dport 8085 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 53 -j ACCEPT
# Glances
sudo iptables -I INPUT -p tcp --dport 61208 -j ACCEPT
# Proxies
sudo iptables -I INPUT -p tcp --dport 8388 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 8388 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 8888 -j ACCEPT
# Samba
sudo iptables -I INPUT -p tcp --dport 445 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 139 -j ACCEPT
sudo netfilter-persistent save

```

### B. NFS Client (Mount)

We mount Sentinel's storage into the existing `/media/storage` structure.

**1. Install & Create:**

```bash
sudo apt update
sudo apt install nfs-common -y
sudo mkdir -p /media/storage/sentinel_pool
sudo chown -R 1000:1000 /media/storage/sentinel_pool

```

**2. Permanent Mount (`/etc/fstab`):**
*Edit:* `sudo vim /etc/fstab`
*Append:*

```text
192.168.1.2:/home/boyi/sentinel_media /media/storage/sentinel_pool nfs defaults,_netdev,timeo=14,intr 0 0

```

**3. Sub-directories:**

```bash
sudo mount -a
sudo mkdir -p /media/storage/sentinel_pool/{movies,tv}
sudo chown -R 1000:1000 /media/storage/sentinel_pool

```

### C. Portainer Agent

*File:* `/home/boyi/portainer-agent/docker-compose.yml`

```yaml
services:
  agent:
    image: portainer/agent:latest
    container_name: portainer_agent
    restart: always
    ports: ["9001:9001"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes

```

*Run:* `cd /home/boyi/portainer-agent && sudo docker compose up -d`

### D. Stack: `media-lab` (Standard Automation)

```yaml
services:
  gluetun:
    image: qmcgaw/gluetun
    cap_add: ["NET_ADMIN"]
    devices: ["/dev/net/tun:/dev/net/tun"]
    ports:
      - "8080:8080"     # qBittorrent
      - "9696:9696"     # Prowlarr
      - "7878:7878"     # Radarr
      - "8989:8989"     # Sonarr
      - "6767:6767"     # Bazarr
      - "7474:7474"     # Autobrr
      - "2468:2468"     # Cross-Seed (Optional)
      - "9000:9000"     # The Lounge (IRC)
      - "8388:8388/tcp" # Shadowsocks
      - "8388:8388/udp" # Shadowsocks
      - "8888:8888/tcp" # HTTP Proxy
    volumes:
      - /media/storage/config/gluetun:/gluetun
    environment:
      - VPN_SERVICE_PROVIDER=airvpn
      - VPN_TYPE=wireguard
      # --- CREDENTIALS ---
      - WIREGUARD_PRIVATE_KEY=<YOUR_PRIVATE_KEY>
      - WIREGUARD_PRESHARED_KEY=<YOUR_PRESHARED_KEY>
      - WIREGUARD_ADDRESSES=<YOUR_IP>
      - FIREWALL_VPN_INPUT_PORTS=31412
      # --- STABILITY ---
      - WIREGUARD_MTU=1280
      - WIREGUARD_PERSISTENT_KEEPALIVE=15
      - DOT=off
      - DNS_KEEP_NAMESERVER=on
    restart: always

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    environment:
      - PUID=1000
      - PGID=1000
      - WEBUI_PORT=8080
    volumes:
      - /media/storage/config/qbittorrent:/config
      - /media/storage:/data  # Unified Path (NVMe + NFS)
    network_mode: "service:gluetun"
    depends_on: ["gluetun"]
    restart: always

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /media/storage/config/prowlarr:/config
    network_mode: "service:gluetun"
    depends_on: ["gluetun"]
    restart: unless-stopped

  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    environment:
      - LOG_LEVEL=info
      - TZ=Asia/Kuala_Lumpur
    network_mode: "service:gluetun"
    depends_on: ["gluetun"]
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /media/storage/config/radarr:/config
      - /media/storage:/data
    network_mode: "service:gluetun"
    depends_on: ["gluetun"]
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /media/storage/config/sonarr:/config
      - /media/storage:/data
    network_mode: "service:gluetun"
    depends_on: ["gluetun"]
    restart: unless-stopped

  bazarr:
    image: lscr.io/linuxserver/bazarr:latest
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Kuala_Lumpur
    volumes:
      - /media/storage/config/bazarr:/config
      - /media/storage:/data
    network_mode: "service:gluetun"
    depends_on: ["gluetun"]
    restart: unless-stopped

  autobrr:
    image: ghcr.io/autobrr/autobrr:latest
    container_name: autobrr
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Kuala_Lumpur
    volumes:
      - /media/storage/config/autobrr:/config
    network_mode: "service:gluetun"
    depends_on: ["gluetun", "prowlarr", "radarr", "sonarr"]
    restart: unless-stopped

  jellyfin:
    image: lscr.io/linuxserver/jellyfin:latest
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - /media/storage/config/jellyfin:/config
      - /media/storage:/data
    ports: ["8096:8096"]
    restart: unless-stopped
    network_mode: host

  thelounge:
    image: lscr.io/linuxserver/thelounge:latest
    container_name: thelounge
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Kuala_Lumpur
    volumes:
      - /media/storage/config/thelounge:/config
    network_mode: "service:gluetun"
    depends_on:
      - gluetun
    restart: unless-stopped

```

### E. (Optional) Private Tracker Automation: Cross-Seed

**1. Update `docker-compose.yml` (Append to services):**

```yaml
  cross-seed:
    image: ghcr.io/cross-seed/cross-seed:latest
    container_name: cross-seed
    user: "1000:1000"
    environment:
      - TZ=Asia/Kuala_Lumpur
    volumes:
      - /media/storage/config/cross-seed:/config
      - /media/storage/config/qbittorrent/qBittorrent/BT_backup:/torrents:ro
      - /media/storage:/data
    network_mode: "service:gluetun"
    depends_on: ["gluetun", "qbittorrent", "prowlarr"]
    command: daemon
    restart: unless-stopped

```

**2. Configuration File (`config.js`)**

* **Source File:** `config.js`
* **Destination:** `/media/storage/config/cross-seed/config.js`

```bash
cp config.js /media/storage/config/cross-seed/

```

**3. The "Instant Trigger" Script**

* **Source File:** `cross_seed_trigger.sh`
* **Destination:** `/media/storage/config/radarr/cross_seed_trigger.sh`

```bash
sudo cp cross_seed_trigger.sh /media/storage/config/radarr/
sudo chmod +x /media/storage/config/radarr/cross_seed_trigger.sh
# Copy to Sonarr
sudo cp /media/storage/config/radarr/cross_seed_trigger.sh /media/storage/config/sonarr/

```

**4. Activate in Radarr & Sonarr**

* **Settings > Connect > + Custom Script**
* **Name:** `Cross-Seed Trigger`
* **Triggers:** `On Import`, `On Upgrade`
* **Path:** `/config/cross_seed_trigger.sh`
* **Test & Save.**

### F. Stack: `private-cloud` (Nextcloud)

```yaml
services:
  db:
    image: mariadb:10.6
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    volumes:
      - /home/boyi/nextcloud/db:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=YOUR_DB_ROOT_PASS
      - MYSQL_PASSWORD=YOUR_NC_DB_PASS
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
    restart: always

  redis:
    image: redis:alpine
    restart: always

  app:
    image: nextcloud:latest
    ports: ["8081:80"]
    links: ["db", "redis"]
    volumes:
      - /home/boyi/nextcloud/html:/var/www/html
      - /media/storage/nextcloud_data:/var/www/html/data
    environment:
      - MYSQL_PASSWORD=YOUR_NC_DB_PASS
      - MYSQL_DATABASE=nextcloud
      - MYSQL_USER=nextcloud
      - MYSQL_HOST=db
      - REDIS_HOST=redis
      - NEXTCLOUD_TRUSTED_DOMAINS=192.168.1.3 10.66.66.5
    restart: always

```

### G. Stack: `adguard-replica`

```yaml
services:
  adguard-replica:
    image: adguard/adguardhome
    restart: unless-stopped
    network_mode: host
    volumes:
      - /home/boyi/adguard/work:/opt/adguardhome/work
      - /home/boyi/adguard/conf:/opt/adguardhome/conf

```

---

## ⚡ Phase 4: Autobrr Configuration (DarkPeers)

**Goal:** Automatic downloading via IRC Announce channels.

### A. Credentials

* **Passkey:** Used for *downloading*.
* **RSS Key:** Used for *listening*.

### B. The Database Conflict Fix (CRITICAL)

1. Go to **Settings > IRC**.
2. **DELETE** the `Darkpeers` network entirely.
3. Go to **Indexers** and add DarkPeers.
4. Let the Indexer **automatically** create the network.

### C. Step-by-Step Configuration

1. **Add Clients:** Add Radarr/Sonarr (Test must pass).
2. **Add Indexer:** Select DarkPeers, use RSS Key, set Nick to `Boyi_Bot`.
3. **Create Filter:** Set Trigger (Radarr/Sonarr) in Actions tab.

---

## 💾 Phase 5: Master Backup & Recovery Scripts

**1. Daily Backup Script**

* **Source File:** `daily_backup.sh`
* **Destination:** `/usr/local/bin/daily_backup.sh`

```bash
sudo cp daily_backup.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/daily_backup.sh

```

**2. Cloud Mirror Script**

* **Source File:** `cloud_mirror.sh`
* **Destination:** `/usr/local/bin/cloud_mirror.sh`

```bash
sudo cp cloud_mirror.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/cloud_mirror.sh

```

**3. VPN Healer Script**

* **Source File:** `heal_vpn.sh`
* **Destination:** `/usr/local/bin/heal_vpn.sh`

```bash
sudo cp heal_vpn.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/heal_vpn.sh

```

### ⏰ Cron Schedules

*Run `sudo crontab -e*`

* **Sentinel:**

```bash
0 4 * * * /usr/local/bin/daily_backup.sh >> /var/log/backup.log 2>&1

```

* **Forge:**

```bash
# Backup & Mirror
30 4 * * * /usr/local/bin/daily_backup.sh >> /var/log/backup.log 2>&1
30 5 * * * /usr/local/bin/cloud_mirror.sh >> /var/log/cloud_mirror.log 2>&1
# VPN Health Check
*/5 * * * * /usr/local/bin/heal_vpn.sh >> /var/log/vpn_healer.log 2>&1

```

```

---

### 2. daily_backup.sh (v1.3.5)
* **Change:** Updated version comment to `1.3.5`.
* **Change:** Included `sleep 15` Staged Startup logic.

