#!/bin/bash
# Fields 9/10 are correct for vnStat 2.x
RX=$(vnstat -m -i enp0s6 --oneline | cut -d';' -f9)
TX=$(vnstat -m -i enp0s6 --oneline | cut -d';' -f10)
echo "{\"rx\": \"$RX\", \"tx\": \"$TX\"}" > /home/ubuntu/bandwidth-monitor/stats.json
