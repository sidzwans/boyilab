#!/bin/bash
BOT_TOKEN="YOUR_BOT_TOKEN"
CHAT_ID="YOUR_CHAT_ID"
# Format: "Name:IP:Port"
# We check Port 53 (DNS) because if AdGuard dies, the lab is effectively broken.
TARGETS=("Sentinel:10.66.66.3:53" "Forge:10.66.66.5:53")

STATE_DIR="/tmp/lab_monitor"
mkdir -p "$STATE_DIR"

send_msg() {
    curl -s -X POST "[https://api.telegram.org/bot$BOT_TOKEN/sendMessage](https://api.telegram.org/bot$BOT_TOKEN/sendMessage)" \
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
