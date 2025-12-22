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
    curl -s -X POST "[https://api.telegram.org/bot$BOT_TOKEN/sendMessage](https://api.telegram.org/bot$BOT_TOKEN/sendMessage)" -d chat_id="$CHAT_ID" -d text="$MSG" -d parse_mode="HTML"
    exit 1
fi

# --- SECRETS (Sentinel Only) --------------------------------------------------
PORTAINER_TOKEN="ptr_YOUR_TOKEN"
PORTAINER_BACKUP_PASS="YOUR_PASS"
PORTAINER_URL="[https://127.0.0.1:9443](https://127.0.0.1:9443)"

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
