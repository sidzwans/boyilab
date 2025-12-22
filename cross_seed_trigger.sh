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
