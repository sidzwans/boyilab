#!/bin/bash
SOURCE_DIR="/media/storage/nextcloud_data/boyi/files"
DEST_DIR="gdrive:Nextcloud_Mirror"
LOG_FILE="/var/log/cloud_mirror.log"

rclone sync "$SOURCE_DIR" "$DEST_DIR" \
    --config /home/boyi/.config/rclone/rclone.conf \
    --transfers=2 --drive-stop-on-upload-limit --verbose >> "$LOG_FILE" 2>&1
