#!/bin/bash
CONTAINERS="gluetun qbittorrent prowlarr radarr sonarr flaresolverr jellyfin bazarr cross-seed thelounge autobrr"
BOT_TOKEN="YOUR_TOKEN"
CHAT_ID="YOUR_ID"

HEALTH=$(docker inspect --format='{{.State.Health.Status}}' gluetun 2>/dev/null)

if [ "$HEALTH" == "unhealthy" ]; then
    curl -s -X POST "[https://api.telegram.org/bot$BOT_TOKEN/sendMessage](https://api.telegram.org/bot$BOT_TOKEN/sendMessage)" \
        -d chat_id="$CHAT_ID" -d text="⚠️ <b>Forge Alert</b>%0AVPN Unhealthy. Restarting..." -d parse_mode="HTML"

    docker restart $CONTAINERS
    sleep 15
    NEW_IP=$(docker exec gluetun wget -qO- [https://ipinfo.io/ip](https://ipinfo.io/ip))
    
    curl -s -X POST "[https://api.telegram.org/bot$BOT_TOKEN/sendMessage](https://api.telegram.org/bot$BOT_TOKEN/sendMessage)" \
        -d chat_id="$CHAT_ID" -d text="✅ <b>Healed</b>%0ANew IP: <code>$NEW_IP</code>" -d parse_mode="HTML"
fi
