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
