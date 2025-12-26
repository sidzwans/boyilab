#!/bin/bash
# ==============================================================================
#  Cross-Seed Trigger v1.1 (Debug Mode)
# ==============================================================================

# --- CONFIGURATION ---
LOG_FILE="/config/cross_seed_trigger.log"
API_URL="http://localhost:2468/api/webhook?apikey=media_lab_secure_key_2025_forge"

# --- INPUTS ---
# Radarr/Sonarr provide these variables automatically
JOB_TYPE="${radarr_eventtype:-$sonarr_eventtype}"
TARGET_PATH="${radarr_movie_path:-$sonarr_series_path}"
TITLE="${radarr_movie_title:-$sonarr_series_title}"

# --- TIMESTAMP ---
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# --- VALIDATION ---
if [ -z "$TARGET_PATH" ]; then
    echo "[$TIMESTAMP] [WARN] No path detected. Event: $JOB_TYPE. Title: $TITLE" >> "$LOG_FILE"
    exit 0
fi

# --- EXECUTION ---
# We capture the HTTP Status Code to see if Cross-Seed accepted it
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL" \
     -H "Content-Type: application/json" \
     -d "{\"path\":\"$TARGET_PATH\"}")

# --- LOGGING ---
if [ "$HTTP_CODE" -eq 204 ]; then
    RESULT="SUCCESS"
elif [ "$HTTP_CODE" -eq 200 ]; then
    RESULT="SUCCESS (Idle)"
else
    RESULT="FAILURE (HTTP $HTTP_CODE)"
fi

echo "[$TIMESTAMP] [$RESULT] Event: $JOB_TYPE | Path: $TARGET_PATH" >> "$LOG_FILE"

exit 0
