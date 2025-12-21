# 📘 Home Lab Master Architecture & Recovery Guide

**Version:** 1.3.2 (Autobrr Integration / DarkPeers Automation / Full System)
**Timezone:** `Asia/Kuala_Lumpur` (UTC+8)

**Changes in this version:**

1. **Phase 3D (`docker-compose.yml`):** Added `autobrr` container to the stack.
2. **Phase 4 (New):** Added the complete "Autobrr Configuration & DarkPeers Strategy" section.
3. **Phase 5 (Backup):** Renumbered from Phase 4. Added `autobrr` to the stop/start logic in `daily_backup.sh`.
4. **VPN Healer Script:** Added `autobrr` to the monitored container list.

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
curl -fsSL https://get.docker.com | sh
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
* **IP Forwarding:** Edit `/etc/sysctl.conf`  `net.ipv4.ip_forward=1`  `sudo sysctl -p`.

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

**2. Bandwidth API** (`/etc/systemd/system/bandwidth-web.service`)

```ini
[Unit]
Description=Simple Bandwidth Web Server
After=network.target
[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --bind 10.66.66.1 --directory /home/ubuntu/bandwidth-monitor
Restart=always
User=ubuntu
[Install]
WantedBy=multi-user.target

```

*Enable:* `sudo systemctl enable --now bandwidth-web`

### C. Scripts (in `/usr/local/bin/`)

**1. `vnstat-json.sh**` (Dashboard Feed)

```bash
#!/bin/bash
# Fields 9/10 are correct for vnStat 2.x
RX=$(vnstat -m -i enp0s6 --oneline | cut -d';' -f9)
TX=$(vnstat -m -i enp0s6 --oneline | cut -d';' -f10)
echo "{\"rx\": \"$RX\", \"tx\": \"$TX\"}" > /home/ubuntu/bandwidth-monitor/stats.json

```

**2. `oci_report.sh**` (Telegram Bot - Bandwidth)

```bash
#!/bin/bash
BOT_TOKEN="YOUR_BOT_TOKEN"
CHAT_ID="YOUR_CHAT_ID"
INTERFACE="enp0s6"
IMAGE_PATH="/home/ubuntu/bandwidth-monitor/summary.png"

/usr/bin/vnstati -s -i "$INTERFACE" -o "$IMAGE_PATH"
BILLABLE=$(vnstat --oneline -i "$INTERFACE" | cut -d';' -f10)
TABLE=$(vnstat -m -i "$INTERFACE" --style 3)
SERVER_NAME=$(hostname)

CAPTION="📊 <b>OCI Bandwidth Report</b>%0AServer: <i>$SERVER_NAME</i>%0A<b>⚠️ Billable (TX): $BILLABLE / 10 TB</b>%0A<pre>$TABLE</pre>"

curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendPhoto" \
     -F chat_id="$CHAT_ID" -F photo="@$IMAGE_PATH" \
     -F caption="$CAPTION" -F parse_mode="HTML"

```

**3. `monitor_lab.sh**` (Port-Aware Watchtower)

```bash
#!/bin/bash
BOT_TOKEN="YOUR_BOT_TOKEN"
CHAT_ID="YOUR_CHAT_ID"
# Format: "Name:IP:Port"
# We check Port 53 (DNS) because if AdGuard dies, the lab is effectively broken.
TARGETS=("Sentinel:10.66.66.3:53" "Forge:10.66.66.5:53")

STATE_DIR="/tmp/lab_monitor"
mkdir -p "$STATE_DIR"

send_msg() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" -d text="$1" -d parse_mode="HTML" > /dev/null
}

for target in "${TARGETS[@]}"; do
    NAME=$(echo $target | cut -d':' -f1)
    IP=$(echo $target | cut -d':' -f2)
    PORT=$(echo $target | cut -d':' -f3)
    STATE_FILE="$STATE_DIR/$NAME.down"

    timeout 3 bash -c "</dev/tcp/$IP/$PORT" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        if [ ! -f "$STATE_FILE" ]; then
            touch "$STATE_FILE"
            send_msg "🔴 <b>CRITICAL ALERT</b>%0A%0A<b>$NAME</b> is failing!%0AService (Port $PORT) is unreachable."
        fi
    else
        if [ -f "$STATE_FILE" ]; then
            rm "$STATE_FILE"
            send_msg "🟢 <b>RECOVERY</b>%0A%0A<b>$NAME</b> service is back online."
        fi
    fi
done

```

**4. `wg_manager.sh**` (Access Control - Ghost Hunter)

```bash
#!/bin/bash

# ==============================================================================
#  WireGuard Access Control Manager (v3.0 - Ghost Hunter Edition)
# ==============================================================================

WG_CONF="/etc/wireguard/wg0.conf"
CHAIN_NAME="WG_USERS"
SENTINEL_IP="10.66.66.3"
FORGE_IP="10.66.66.5"

# --- HELPER: Setup Firewall Chain ---
init_firewall() {
    iptables -N $CHAIN_NAME 2>/dev/null
    EXISTS=$(iptables -C FORWARD -i wg0 -j $CHAIN_NAME 2>/dev/null; echo $?)
    if [ $EXISTS -ne 0 ]; then
        iptables -I FORWARD 1 -i wg0 -j $CHAIN_NAME
    fi
}

# --- HELPER: Flush Rules for IP ---
flush_user() {
    local TARGET_IP=$1
    # Remove any rule in chain matching this Source IP
    iptables -L $CHAIN_NAME -n --line-numbers | grep "$TARGET_IP" | sort -r -n -k1 | awk '{print $1}' | xargs -r -n1 iptables -D $CHAIN_NAME
}

# --- HELPER: Detect & Kill Ghosts ---
check_ghosts() {
    echo "👻 Scanning for Ghost Users..."
    
    FIREWALL_IPS=$(iptables -L $CHAIN_NAME -n | awk '{print $4}' | grep "10.66.66" | sort -u)
    GHOSTS_FOUND=0
    
    for F_IP in $FIREWALL_IPS; do
        IS_VALID=0
        for C_IP in "${CLIENT_IPS[@]}"; do
            if [[ "$F_IP" == "$C_IP" ]]; then
                IS_VALID=1
                break
            fi
        done
        
        if [[ $IS_VALID -eq 0 ]]; then
            echo "   ⚠️  Ghost Detected: $F_IP (In Firewall, but not in Config)"
            read -p "      Delete rules for $F_IP? [y/n]: " CONFIRM
            if [[ "$CONFIRM" == "y" ]]; then
                flush_user "$F_IP"
                echo "      ✅ Purged."
                GHOSTS_FOUND=1
            fi
        fi
    done
    
    if [[ $GHOSTS_FOUND -eq 0 ]]; then
        echo "   ✅ System Clean (No ghosts found)."
    else
        netfilter-persistent save > /dev/null 2>&1
    fi
    echo "------------------------------------------"
}

# --- MAIN LOGIC ---
init_firewall

declare -a CLIENT_NAMES
declare -a CLIENT_IPS
COUNT=0

while read -r line; do
    if [[ $line == "### Client"* ]]; then
        NAME=$(echo $line | cut -d' ' -f3-)
        CLIENT_NAMES[$COUNT]=$NAME
    elif [[ $line == "AllowedIPs"* ]]; then
        IP=$(echo $line | cut -d'=' -f2 | tr -d ' ' | cut -d',' -f1 | cut -d'/' -f1)
        CLIENT_IPS[$COUNT]=$IP
        ((COUNT++))
    fi
done < $WG_CONF

echo "=========================================="
echo "   WireGuard Access Control Manager       "
echo "=========================================="

check_ghosts

echo "Active Users:"
for (( i=0; i<$COUNT; i++ )); do
    echo "  $((i+1)). ${CLIENT_NAMES[$i]} (${CLIENT_IPS[$i]})"
done
echo ""
read -p "Select Client to Configure (or q to quit): " SELECTION

if [[ "$SELECTION" == "q" ]]; then exit 0; fi

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "$COUNT" ]; then
    echo "Invalid selection."
    exit 1
fi

INDEX=$((SELECTION-1))
SELECTED_IP=${CLIENT_IPS[$INDEX]}
SELECTED_NAME=${CLIENT_NAMES[$INDEX]}

echo ""
echo "Configuring: $SELECTED_NAME ($SELECTED_IP)"
echo "------------------------------------------"
read -p "1. Apply 'Guard' Role (DNS Only)? [y/n]: " ROLE_GUARD
read -p "2. Apply 'Media' Role (Jellyfin Only)? [y/n]: " ROLE_MEDIA
echo "------------------------------------------"

flush_user $SELECTED_IP

IS_RESTRICTED=0

if [[ "$ROLE_GUARD" == "y" ]]; then
    echo "-> Allowing DNS..."
    iptables -A $CHAIN_NAME -s $SELECTED_IP -d $SENTINEL_IP -p udp --dport 53 -j ACCEPT
    iptables -A $CHAIN_NAME -s $SELECTED_IP -d $SENTINEL_IP -p tcp --dport 53 -j ACCEPT
    iptables -A $CHAIN_NAME -s $SELECTED_IP -d $FORGE_IP -p udp --dport 53 -j ACCEPT
    iptables -A $CHAIN_NAME -s $SELECTED_IP -d $FORGE_IP -p tcp --dport 53 -j ACCEPT
    IS_RESTRICTED=1
fi

if [[ "$ROLE_MEDIA" == "y" ]]; then
    echo "-> Allowing Jellyfin..."
    iptables -A $CHAIN_NAME -s $SELECTED_IP -d $FORGE_IP -p tcp --dport 8096 -j ACCEPT
    IS_RESTRICTED=1
fi

if [ $IS_RESTRICTED -eq 1 ]; then
    echo "-> BLOCKING all other traffic..."
    iptables -A $CHAIN_NAME -s $SELECTED_IP -j DROP
    echo "✅ Roles Applied."
else
    echo "✅ User reset to Full Access (Admin)."
fi

netfilter-persistent save > /dev/null 2>&1

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
**Critical:** We must include Google DNS (`8.8.8.8`) as the 3rd option. This ensures the server can boot and reach the internet even if the Docker containers (AdGuard) crash or the VPN tunnel is down.

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

```yaml
- Cloud Gateway (OCI):
    - OCI Console:
        icon: si-oracle
        href: https://cloud.oracle.com
        description: Latency Check
        ping: http://10.66.66.1:61208

    - OCI CPU:
        icon: mdi-cpu-64-bit
        description: Ampere A1 Load
        widget:
          type: glances
          url: http://10.66.66.1:61208
          version: 3
          metric: cpu

    - OCI Memory:
        icon: mdi-memory
        description: RAM Usage
        widget:
          type: glances
          url: http://10.66.66.1:61208
          version: 3
          metric: memory

    - OCI Network:
            icon: mdi-ethernet
            description: Public Traffic
            widget:
              type: glances
              url: http://10.66.66.1:61208
              version: 3
              # CHANGE 'enp0s6' if your interface name is different
              metric: network:enp0s6

    - OCI Storage:
        icon: mdi-harddisk
        description: Boot Volume
        widget:
          type: glances
          url: http://10.66.66.1:61208
          version: 3
          metric: fs:/

    - OCI Monthly Network:
        icon: mdi-calendar-clock
        description: "Limits: 10TB TX"
        widget:
          type: customapi
          url: http://10.66.66.1:8080/stats.json
          refresh: 600000 # 10 minutes
          mappings:
            - field: tx
              label: BILLABLE (TX)
            - field: rx
              label: FREE (RX)

-  On-Premise Cluster:
    - Sentinel (Control):
        icon: /icons/orange-pi.png
        href: http://192.168.1.2:61208
        widget:
            type: glances
            url: http://192.168.1.2:61208
            metric: "info"

    - Sentinel Storage (NVMe):
        icon: mdi-harddisk
        description: "Root: /"
        widget:
          type: glances
          url: http://192.168.1.2:61208
          version: 3
          metric: fs:/
    - Sentinel Network:
        icon: mdi-ethernet
        description: Public Traffic
        widget:
          type: glances
          url: http://192.168.1.2:61208
          version: 3
          metric: network:enP3p49s0

    # --- FORGE (Media Node) ---
    - Forge (Media):
        icon: /icons/orange-pi.png
        href: http://192.168.1.3:61208
        widget:
            type: glances
            url: http://192.168.1.3:61208
            metric: "info"
    - Forge Storage (NVMe):
        icon: mdi-harddisk-plus
        description: "Root: /"
        widget:
          type: glances
          url: http://192.168.1.3:61208
          version: 3
          metric: fs:/

    - Forge Network:
        icon: mdi-ethernet
        description: Public Traffic
        widget:
          type: glances
          url: http://192.168.1.3:61208
          version: 3
          metric: network:enP3p49s0

- Infrastructure:
    - Portainer:
        icon: portainer.png
        href: https://10.66.66.3:9443
        description: Docker Manager
        widget:
          type: portainer
          url: https://192.168.1.2:9443
          env: 9
          key: xxxx

    - AdGuard Home (Primary):
        icon: adguard-home.png
        href: http://10.66.66.3:8085
        description: Sentinel DNS
        widget:
          type: adguard
          url: http://10.66.66.3:8085
          username: admin
          password: xxxx

    - AdGuard Home (Replica):
        icon: adguard-home.png
        href: http://10.66.66.5:8085
        description: Sentinel DNS
        widget:
          type: adguard
          url: http://10.66.66.5:8085
          username: admin
          password: xxxx

- Media Lab:
    - Jellyfin:
        icon: jellyfin.png
        href: http://10.66.66.5:8096
        description: Watch Movies
        widget:
          type: jellyfin
          url: http://10.66.66.5:8096
          key: xxxx
          enableNowPlaying: true

    - qBittorrent:
        icon: qbittorrent.png
        href: http://10.66.66.5:8080/
        description: Downloader
        widget:
          type: qbittorrent
          url: http://10.66.66.5:8080
          username: admin
          password: xxxx

    - Prowlarr:
        icon: prowlarr.png
        href: http://10.66.66.5:9696
        description: Indexer Manager
        widget:
          type: prowlarr
          url: http://10.66.66.5:9696
          key: xxxx

    - Radarr:
        icon: radarr
        href: http://10.66.66.5:7878
        description: Movie Manager
        widget:
          type: radarr
          url: http://10.66.66.5:7878
          key: xxxx
          enableQueue: true

    - Sonarr:
        icon: sonarr
        href: http://10.66.66.5:8989
        description: TV Series Manager
        widget:
          type: sonarr
          url: http://10.66.66.5:8989
          key: xxxx
          enableQueue: true
    - Bazarr:
        icon: bazarr.png
        href: http://10.66.66.5:6767
        description: Subtitle Manager
        widget:
          type: bazarr
          url: http://10.66.66.5:6767
          key: xxxx
    
    - Autobrr:
        icon: autobrr.png
        href: http://10.66.66.5:7474
        description: Automation
        widget:
          type: autobrr
          url: http://10.66.66.5:7474
          key: xxxx

```

**2. `widgets.yaml**`

```yaml
- datetime:
    text_size: xl
    format:
      timeStyle: short
- openweathermap:
    latitude: x.xx
    longitude: x.xx
    units: metric # or imperial
    provider: openweathermap
    apiKey: xxxx # required only if not using provider, this reveals api key in requests
    cache: 5 # Time in minutes to cache API responses, to stay within limits
    format: # optional, Intl.NumberFormat options
      maximumFractionDigits: 1

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
      - ORIGIN_URL=http://192.168.1.2:8085
      - REPLICA1_URL=http://192.168.1.3:8085
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
**Critical:** We must include Google DNS (`8.8.8.8`) as the 3rd option. This ensures the server can boot and reach the internet even if the Docker containers (AdGuard) crash or the VPN tunnel is down.

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

*For advanced users on private trackers. This includes the "Nuclear Option" script to bypass Radarr webhook errors and trigger instant searches.*

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
*Location:* `/media/storage/config/cross-seed/config.js`
*Notes: Uses `includeSingleEpisodes` (Correct v6 Syntax) and `searchCadence: null`.*

```javascript
module.exports = {
  // Prowlarr Indexers (Use Clean URLs without '=search')
  torznab: [
     "http://localhost:9696/2/api?apikey=YOUR_PROWLARR_API_KEY", // DigitalCore
     "http://localhost:9696/3/api?apikey=YOUR_PROWLARR_API_KEY", // DarkPeers
     "http://localhost:9696/4/api?apikey=YOUR_PROWLARR_API_KEY"  // Malayabits
  ],

  // Client Injection
  action: "inject",
  torrentClients: ["qbittorrent:http://admin:YOUR_QBIT_PASSWORD@localhost:8080"],
  
  // Paths (Matches qBittorrent & Media Stack)
  torrentDir: "/torrents", 
  outputDir: null, // Set to null to prevent v6 warnings

  // Logic
  includeSingleEpisodes: true, // Replaced "includeEpisodes" (v6 fix)
  includeNonVideos: true, 
  duplicateCategories: true,
  matchMode: "safe", 
  linkDirs: [],
  flatLinking: false,

  // Automation: Manual/Script Only (Safe Backup: 1 day)
  searchCadence: null,
  
  // Exclusions (Required: excludeOlder must be 2-5x recent)
  excludeRecentSearch: "2w",
  excludeOlder: "6w",

  // Security
  apiKey: "media_lab_secure_key_2025_forge"
};

```

**3. The "Instant Trigger" Script**
*This script runs inside Radarr/Sonarr to force a cross-seed search instantly upon import.*

*Create File:* `sudo vim /media/storage/config/radarr/cross_seed_trigger.sh`

```bash
#!/bin/bash
# 1. Detect Path
TARGET_PATH="${radarr_movie_path:-$sonarr_series_path}"

# 2. Safety Check (Pass "Test" button)
if [ -z "$TARGET_PATH" ]; then
    echo "No path detected. Ignoring."
    exit 0
fi

# 3. Fire Webhook (Internal Localhost)
curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:2468/api/webhook?apikey=media_lab_secure_key_2025_forge" \
     -H "Content-Type: application/json" \
     -d "{\"path\":\"$TARGET_PATH\"}"

exit 0

```

*Permissions:*

```bash
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
**Method:** "Push" approach (Shotgun) - Autobrr sends all releases to Radarr/Sonarr; apps decide what to keep.

### A. Credentials

* **Passkey:** Used for *downloading* the .torrent file.
* **RSS Key:** Used for *listening* (the feed). **Autobrr requires the RSS Key.**

### B. The Database Conflict Fix (CRITICAL)

* **Problem:** If you manually create the Network/Channel in "IRC Settings" first, the Indexer setup will fail with `UNIQUE constraint failed`.
* **Fix:**
1. Go to **Settings  IRC**.
2. **DELETE** the `Darkpeers` network entirely (Click trash icon).
3. Go to **Indexers** and add DarkPeers.
4. Let the Indexer **automatically** create the network and join the channel.



### C. Step-by-Step Configuration

1. **Add Clients (The Connectors):**
* Go to **Clients**  **Add New**.
* **Radarr:**
* Name: `Forge Radarr`
* Host: `http://localhost:7878`
* Key: (From Radarr Settings)
* **Action:** Click **Test** (Must be Green). Save.


* **Sonarr:**
* Name: `Forge Sonarr`
* Host: `http://localhost:8989`
* Key: (From Sonarr Settings)
* **Action:** Click **Test** (Must be Green). Save.




2. **Add Indexer (The Listener):**
* Go to **Indexers**  **Add New**.
* Select **DarkPeers**.
* **RSS Key:** Paste your DarkPeers RSS Key.
* **Nick:** `Boyi_Bot`
* **NickServ:** Leave blank (or fill if needed).
* **Note:** Do not fill in channels manually.
* **Save.** (Check logs for `INF Monitoring channel #dpannounce`).


3. **Create Filter (The Trigger):**
* Go to **Filters**  **Add New**.
* **Name:** `DarkPeers Watch`.
* **Indexer:** Check `DarkPeers`.
* **Actions Tab:**
* Add Action  Select **Radarr** (This acts as "Push").
* Name: `Push to Radarr`
* Client: `Forge Radarr`
* *Note: There is NO Test button on this specific screen.*
* **Save Action.**
* Repeat for Sonarr (`Push to Sonarr`).


* **Save Filter.**



### D. Verification Protocol

How to confirm it works without a successful download:

1. **Check Logs:** Look for `INF Monitoring channel #dpannounce`.
2. **Wait for Release:** Watch for a new entry in IRC.
3. **Check for Rejection:**
* `DBG radarr: release push rejected: [Title] reasons: '[Unknown Movie]'`
* **Verdict:** **SUCCESS**. The pipeline is open; Radarr just didn't want that specific file.



---

## 💾 Phase 5: Master Backup System (Crash-Proof)

**Script:** `/usr/local/bin/daily_backup.sh` (On BOTH servers)

```bash
#!/bin/bash
# ==============================================================================
#  MASTER BACKUP SCRIPT (v1.3.0 - NFS Aware / Disk-Safe)
# ==============================================================================

# --- CONFIGURATION ------------------------------------------------------------
BACKUP_DIR="/home/boyi/backups"
DATE=$(date +"%Y-%m-%d_%H-%M")
HOSTNAME=$(hostname)
ARCHIVE_NAME="$BACKUP_DIR/$HOSTNAME-backup-$DATE.tar.gz"

# --- SAFETY CHECK: DISK SPACE ---
# Abort if Root Partition is > 90% full to prevent crash
DISK_USAGE=$(df / | grep / | awk '{ print $5 }' | sed 's/%//g')
if [ "$DISK_USAGE" -gt 90 ]; then
    BOT_TOKEN="YOUR_BOT_TOKEN_HERE"
    CHAT_ID="YOUR_CHAT_ID_HERE"
    MSG="🚨 <b>CRITICAL DISK FAILURE</b>%0A%0A<b>$HOSTNAME</b> is at <b>${DISK_USAGE}%</b> capacity!%0ABackup aborted."
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id="$CHAT_ID" -d text="$MSG" -d parse_mode="HTML"
    exit 1
fi

# --- SECRETS (Sentinel Only) --------------------------------------------------
PORTAINER_TOKEN="ptr_YOUR_TOKEN"
PORTAINER_BACKUP_PASS="YOUR_PASS"
PORTAINER_URL="https://127.0.0.1:9443"

mkdir -p "$BACKUP_DIR"

# [1] PORTAINER API BACKUP (Sentinel Only)
if [ "$HOSTNAME" == "sentinel" ]; then
    echo "Triggering Portainer API Backup..."
    curl -k -X POST "$PORTAINER_URL/api/backup" \
         -H "X-API-Key: $PORTAINER_TOKEN" \
         -H "Content-Type: application/json" \
         -d "{\"password\": \"$PORTAINER_BACKUP_PASS\"}" \
         -o "$BACKUP_DIR/portainer_config_$DATE.tar.gz"
fi

# [2] STOP CONTAINERS
echo "Stopping containers..."
if [ "$HOSTNAME" == "sentinel" ]; then
    docker stop homeassistant adguardhome mosquitto
elif [ "$HOSTNAME" == "forge" ]; then
    # Cross-Seed and Autobrr added to stop list
    docker stop qbittorrent prowlarr jellyfin adguardhome radarr sonarr flaresolverr bazarr nextcloud nextcloud-db cross-seed thelounge autobrr
fi

# [3] ARCHIVE FILES (Loop-Proof)
echo "Creating archive..."
BACKUP_PATHS="/home/boyi /etc/wireguard"

# Forge includes Media Configs from NVMe
if [ "$HOSTNAME" == "forge" ]; then
    BACKUP_PATHS="$BACKUP_PATHS /media/storage/config /home/boyi/portainer-agent"
fi

# CRITICAL: --exclude="$BACKUP_DIR" prevents infinite recursion
# Exclude sentinel_pool to prevent backing up NFS media data
tar -czf "$ARCHIVE_NAME" \
    --exclude="$BACKUP_DIR" \
    --exclude='/media/storage/downloads' \
    --exclude='/media/storage/movies' \
    --exclude='/media/storage/tv' \
    --exclude='/media/storage/sentinel_pool' \
    --exclude='/home/boyi/sentinel_media' \
    $BACKUP_PATHS

# [4] RESTART CONTAINERS
echo "Restarting containers..."
if [ "$HOSTNAME" == "sentinel" ]; then
    docker start mosquitto adguardhome homeassistant
elif [ "$HOSTNAME" == "forge" ]; then
    docker start adguardhome prowlarr jellyfin qbittorrent radarr sonarr flaresolverr bazarr nextcloud-db nextcloud cross-seed thelounge autobrr
fi

# [5] UPLOAD
echo "Uploading..."
rclone copy "$BACKUP_DIR" "gdrive:HomeLabBackups/$HOSTNAME" \
    --config /home/boyi/.config/rclone/rclone.conf \
    --transfers=1

# [6] DOUBLE DROP (Forge Only)
if [ "$HOSTNAME" == "forge" ]; then
    echo "Copying to Nextcloud..."
    NC_DIR="/media/storage/nextcloud_data/boyi/files/ServerBackups"
    mkdir -p "$NC_DIR"
    cp "$ARCHIVE_NAME" "$NC_DIR/"
    chown -R 33:33 "$NC_DIR"
    docker exec -u 33 nextcloud php occ files:scan --path="/boyi/files/ServerBackups"
fi

# [7] CLEANUP (Keep 3)
echo "Cleaning up local files..."
cd "$BACKUP_DIR" || exit
ls -1tr *.tar.gz | head -n -3 | xargs -r rm

```

### ⏰ Cron Schedules

*Run `sudo crontab -e*`

```bash
# Telegram Bandwidth Report (Daily at 08:00 MYT / 00:00 UTC)
0 8 * * * /usr/local/bin/oci_report.sh

# Update Dashboard Stats (Every 10 mins)
*/10 * * * * /usr/local/bin/vnstat-json.sh

# Watchtower Health Check (Every 5 mins)
*/5 * * * * /usr/local/bin/monitor_lab.sh

```

* **Sentinel:** `0 4 * * * /usr/local/bin/daily_backup.sh >> /var/log/backup.log 2>&1`
* **Forge:** `30 4 * * * /usr/local/bin/daily_backup.sh >> /var/log/backup.log 2>&1`
* **Forge (Cloud Mirror):** `30 5 * * * /usr/local/bin/cloud_mirror.sh >> /var/log/cloud_mirror.log 2>&1`
* **Forge (VPN Healer):** `*/5 * * * * /usr/local/bin/heal_vpn.sh >> /var/log/vpn_healer.log 2>&1`

---

## ☁️ Nextcloud Mirror Script

*Script:* `/usr/local/bin/cloud_mirror.sh`

```bash
#!/bin/bash
SOURCE_DIR="/media/storage/nextcloud_data/boyi/files"
DEST_DIR="gdrive:Nextcloud_Mirror"
LOG_FILE="/var/log/cloud_mirror.log"

rclone sync "$SOURCE_DIR" "$DEST_DIR" \
    --config /home/boyi/.config/rclone/rclone.conf \
    --transfers=2 --drive-stop-on-upload-limit --verbose >> "$LOG_FILE" 2>&1

```

---

## 🏥 VPN Healer Script

*Script:* `/usr/local/bin/heal_vpn.sh`

```bash
#!/bin/bash
CONTAINERS="gluetun qbittorrent prowlarr radarr sonarr flaresolverr jellyfin bazarr cross-seed thelounge autobrr"
BOT_TOKEN="YOUR_TOKEN"
CHAT_ID="YOUR_ID"

HEALTH=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null)

if [ "$HEALTH" == "unhealthy" ]; then
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" -d text="⚠️ <b>Forge Alert</b>%0AVPN Unhealthy. Restarting..." -d parse_mode="HTML"

    docker restart $CONTAINERS
    sleep 15
    NEW_IP=$(docker exec gluetun wget -qO- https://ipinfo.io/ip)
    
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" -d text="✅ <b>Healed</b>%0ANew IP: <code>$NEW_IP</code>" -d parse_mode="HTML"
fi

```
