#!/bin/bash

# Detect active interface
IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)
if [ -z "$IFACE" ]; then
    echo '{"text": "   ⚠ Offline"}'
    exit 0
fi

# Fetch cumulative daily total from vnstat
# Silently handles errors if vnstat is still initializing
TOTAL_TRAFFIC=$(vnstat -i "$IFACE" 2>/dev/null | awk '/today/ {print $8$9}')
if [ -z "$TOTAL_TRAFFIC" ]; then
    TOTAL_TRAFFIC="Pending..."
fi

# Sample bandwidth rates
read rx1 < "/sys/class/net/$IFACE/statistics/rx_bytes"
read tx1 < "/sys/class/net/$IFACE/statistics/tx_bytes"
sleep 1
read rx2 < "/sys/class/net/$IFACE/statistics/rx_bytes"
read tx2 < "/sys/class/net/$IFACE/statistics/tx_bytes"

# Process metrics and format output
awk -v rx="$((rx2 - rx1))" -v tx="$((tx2 - tx1))" -v tot="$TOTAL_TRAFFIC" '
function format(b) {
    if (b < 102) return "0.0KB"
    else if (b < 1048576) return sprintf("%.1fKB", b/1024)
    else return sprintf("%.2fMB", b/1048576)
}
BEGIN {
    rx_str = format(rx)
    tx_str = format(tx)
    
    out = "⇣" rx_str "  ⇡" tx_str "  ∑" tot
    print "{\"text\": \"   " out "\"}"
}'
