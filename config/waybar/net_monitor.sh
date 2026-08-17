#!/bin/bash
# Self-contained network monitor for waybar — no daemon, no root, no vnstat.
#
#   • Live  ⇣ down / ⇡ up  speed, straight from the kernel byte counters.
#   • Persistent  Today / Month / Total  usage, accumulated locally: each tick
#     differences /sys/.../{rx,tx}_bytes and adds the delta, correctly handling
#     counter resets on reconnect/reboot (cur < last  ⇒  count all of cur).
#   • State lives in  ~/.local/state/waybar-netusage/<iface>  and survives
#     reboots. flock serialises concurrent callers so no byte is double-counted.
#   • On the FIRST run for an interface it seeds Month/Total from vnstat if it's
#     still installed, so existing history carries over. vnstat is then optional.
#
# Driven by waybar's `interval` (every couple of seconds). That's the sampler —
# no background service required on an always-on desktop.

set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/waybar-netusage"
mkdir -p "$STATE_DIR" 2>/dev/null

# --- active interface (default route) --------------------------------------
IFACE=$(ip route 2>/dev/null | awk '/^default/ {print $5; exit}')
if [ -z "$IFACE" ]; then
    echo '{"text":"   ⚠ Offline","tooltip":"No network connection"}'
    exit 0
fi
STAT="/sys/class/net/$IFACE/statistics"
if ! [ -r "$STAT/rx_bytes" ]; then
    echo '{"text":"   ⚠","tooltip":"'"$IFACE"': no counters"}'
    exit 0
fi

read -r cur_rx < "$STAT/rx_bytes"
read -r cur_tx < "$STAT/tx_bytes"
now_ns=$(date +%s%N)
today=$(date +%F)
ymonth=$(date +%Y-%m)

STATE="$STATE_DIR/$IFACE"
exec 9>"$STATE_DIR/$IFACE.lock"; flock 9      # serialise concurrent callers

# --- load persisted state (or seed) ----------------------------------------
seeded=0
if [ -r "$STATE" ]; then
    read -r last_rx last_tx prev_ns s_date day s_month monthb total < "$STATE"
else
    last_rx=$cur_rx; last_tx=$cur_tx; prev_ns=$now_ns
    s_date=$today; day=0; s_month=$ymonth; monthb=0; total=0
    seeded=1
    # best-effort history import from vnstat (month = f11, all-time = f15)
    line=$(vnstat -i "$IFACE" --oneline b 2>/dev/null)
    if [ -n "$line" ]; then
        vm=$(echo "$line" | cut -d';' -f11); va=$(echo "$line" | cut -d';' -f15)
        [[ $vm =~ ^[0-9]+$ ]] && monthb=$vm
        [[ $va =~ ^[0-9]+$ ]] && total=$va
    fi
fi
# defend against a short/corrupt state line (set -u safety)
[[ ${last_rx:-} =~ ^[0-9]+$ ]] || last_rx=$cur_rx
[[ ${last_tx:-} =~ ^[0-9]+$ ]] || last_tx=$cur_tx
[[ ${prev_ns:-} =~ ^[0-9]+$ ]] || prev_ns=$now_ns
[[ ${day:-}    =~ ^[0-9]+$ ]] || day=0
[[ ${monthb:-} =~ ^[0-9]+$ ]] || monthb=0
[[ ${total:-}  =~ ^[0-9]+$ ]] || total=0
[ -n "${s_date:-}" ]  || s_date=$today
[ -n "${s_month:-}" ] || s_month=$ymonth

# --- deltas with counter-reset handling ------------------------------------
if [ "$cur_rx" -ge "$last_rx" ]; then drx=$((cur_rx-last_rx)); else drx=$cur_rx; fi
if [ "$cur_tx" -ge "$last_tx" ]; then dtx=$((cur_tx-last_tx)); else dtx=$cur_tx; fi
[ "$seeded" = 1 ] && { drx=0; dtx=0; }        # don't count pre-existing counter
delta=$((drx+dtx))

# --- day / month rollover ---------------------------------------------------
[ "$s_date"  != "$today"  ] && { day=0;    s_date=$today;   }
[ "$s_month" != "$ymonth" ] && { monthb=0; s_month=$ymonth; }
day=$((day+delta)); monthb=$((monthb+delta)); total=$((total+delta))

printf '%s %s %s %s %s %s %s %s\n' \
    "$cur_rx" "$cur_tx" "$now_ns" "$s_date" "$day" "$s_month" "$monthb" "$total" > "$STATE"
flock -u 9

# --- live speed -------------------------------------------------------------
elapsed=$(awk -v a="$now_ns" -v b="$prev_ns" 'BEGIN{e=(a-b)/1e9; if(e<0.2)e=1; print e}')
rx_rate=$(awk -v d="$drx" -v e="$elapsed" 'BEGIN{printf "%.0f", d/e}')
tx_rate=$(awk -v d="$dtx" -v e="$elapsed" 'BEGIN{printf "%.0f", d/e}')

human() { awk -v b="${1:-0}" 'BEGIN{ if(b=="")b=0; split("B KB MB GB TB PB",u," "); i=1; while(b>=1024&&i<6){b/=1024;i++} if(i==1)printf "%d%s",b,u[i]; else printf "%.1f%s",b,u[i] }'; }
rate()  { awk -v b="${1:-0}" 'BEGIN{ split("B KB MB GB",u," "); i=1; while(b>=1024&&i<4){b/=1024;i++} if(i==1)printf "%d%s/s",b,u[i]; else printf "%.1f%s/s",b,u[i] }'; }

rx_h=$(rate "$rx_rate"); tx_h=$(rate "$tx_rate")
text="   ⇣${rx_h}  ⇡${tx_h}  ∑$(human "$day")"
tip="<b>${IFACE}</b>   ⇣ ${rx_h}   ⇡ ${tx_h}\nToday:   $(human "$day")\nMonth:  $(human "$monthb")\nTotal:    $(human "$total")"
printf '{"text":"%s","tooltip":"%s"}\n' "$text" "$tip"
