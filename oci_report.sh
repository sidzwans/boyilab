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

curl -s -X POST "[https://api.telegram.org/bot$BOT_TOKEN/sendPhoto](https://api.telegram.org/bot$BOT_TOKEN/sendPhoto)" \
     -F chat_id="$CHAT_ID" -F photo="@$IMAGE_PATH" \
     -F caption="$CAPTION" -F parse_mode="HTML"
