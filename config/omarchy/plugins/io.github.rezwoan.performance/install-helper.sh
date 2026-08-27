#!/bin/bash
# One-time privileged installer for the Performance plugin's write path.
# Run with: sudo bash install-helper.sh
#
# Installs a root-owned, verb-whitelisted helper plus a sudoers rule scoped
# to that one binary — the plugin's ButtonGroups/Toggles call it via
# `sudo -n` for every privileged action (turbo, CPU cores/cap, RAPL power
# limit, thermal profile, fan, battery limiter, keyboard RGB, power presets).
# Without this script the panel still works read-only (status is always
# plain sysfs reads); every write silently no-ops until it's installed.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with sudo."; exit 1; }

TARGET_USER="${SUDO_USER:-$(id -un 1000 2>/dev/null || echo root)}"
echo "==> Installing for user $TARGET_USER"

install -d /usr/local/bin
cat > /usr/local/bin/omarchy-perf-helper <<'HELPER'
#!/bin/bash
# omarchy-perf-helper — privileged applier for the Performance plugin.
# Root-owned, invoked via a scoped NOPASSWD sudo rule. Accepts ONLY whitelisted
# verbs/values, so it cannot be coerced into running arbitrary commands.
set -euo pipefail
cmd="${1:-}"; val="${2:-}"
case "$cmd" in
  turbo)
    case "$val" in
      on)  echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo ;;
      off) echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo ;;
      *) exit 2 ;;
    esac ;;
  power-limit) # RAPL package cap:  power-limit <pl1_watts> <pl2_watts>
    R=/sys/class/powercap/intel-rapl:0
    [[ -w $R/constraint_0_power_limit_uw ]] || exit 3
    pl1="${2:-}"; pl2="${3:-}"
    [[ $pl1 =~ ^[0-9]+$ && $pl2 =~ ^[0-9]+$ ]] || exit 2
    { (( pl1 >= 10 && pl1 <= 65 && pl2 >= 10 && pl2 <= 157 && pl2 >= pl1 )); } || exit 2
    echo $(( pl1 * 1000000 )) > "$R/constraint_0_power_limit_uw" || exit 3
    echo $(( pl2 * 1000000 )) > "$R/constraint_1_power_limit_uw" 2>/dev/null || true ;;
  cpu-cap)   # underclock: cap max CPU frequency to a percentage (20-100)
    f=/sys/devices/system/cpu/intel_pstate/max_perf_pct
    [[ -w $f ]] || exit 3
    case "$val" in
      [1-9][0-9]|100) (( val >= 20 )) || exit 2; echo "$val" > "$f" ;;
      *) exit 2 ;;
    esac ;;
  cpu-cores) # all | no-smt (disable hyperthreading) | ecore (offline P-cores)
    SMT=/sys/devices/system/cpu/smt/control
    case "$val" in
      all)
        [[ -w $SMT ]] && echo on > "$SMT" 2>/dev/null || true
        for c in /sys/devices/system/cpu/cpu[0-9]*/online; do echo 1 > "$c" 2>/dev/null || true; done ;;
      no-smt)
        for c in /sys/devices/system/cpu/cpu[0-9]*/online; do echo 1 > "$c" 2>/dev/null || true; done
        [[ -w $SMT ]] && echo off > "$SMT" || exit 3 ;;
      ecore) # keep E-cores (+ un-offlinable cpu0), offline every P-core thread
        for c in /sys/devices/system/cpu/cpu[0-9]*/online; do echo 1 > "$c" 2>/dev/null || true; done
        pcpus="$(cat /sys/devices/cpu_core/cpus 2>/dev/null)"
        if [[ -n $pcpus ]]; then
          for part in ${pcpus//,/ }; do
            lo=${part%-*}; hi=${part#*-}
            for ((i=lo; i<=hi; i++)); do
              [[ $i == 0 ]] && continue
              f=/sys/devices/system/cpu/cpu$i/online
              [[ -w $f ]] && echo 0 > "$f" 2>/dev/null || true
            done
          done
        else
          targets=()
          for d in /sys/devices/system/cpu/cpu[0-9]*; do
            n=${d##*cpu}; [[ $n == 0 ]] && continue
            [[ -w $d/online ]] || continue
            sl="$(cat "$d/topology/thread_siblings_list" 2>/dev/null)"
            [[ $sl == *,* || $sl == *-* ]] && targets+=("$d/online")
          done
          for f in "${targets[@]}"; do echo 0 > "$f" 2>/dev/null || true; done
        fi ;;
      *) exit 2 ;;
    esac ;;
  platform-profile)
    case "$val" in
      low-power|quiet|balanced|balanced-performance|performance)
        echo "$val" > /sys/firmware/acpi/platform_profile ;;
      *) exit 2 ;;
    esac ;;
  nvidia-powerd)
    case "$val" in
      on)  systemctl enable --now nvidia-powerd.service ;;
      off) systemctl disable --now nvidia-powerd.service ;;
      *) exit 2 ;;
    esac ;;
  battery-limit)
    b=$(echo /sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/*_sense 2>/dev/null)
    [[ -d $b && -w $b/battery_limiter ]] || exit 3
    case "$val" in
      on)  echo 1 > "$b/battery_limiter" ;;
      off) echo 0 > "$b/battery_limiter" ;;
      *) exit 2 ;;
    esac ;;
  fan)
    b=$(echo /sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/*_sense 2>/dev/null)
    [[ -d $b && -w $b/fan_speed ]] || exit 3
    case "$val" in
      auto) echo 0 > "$b/fan_speed" ;;
      [1-9]|[1-9][0-9]|100) echo "$val" > "$b/fan_speed" ;;
      *) exit 2 ;;
    esac ;;
  kb-zone)   # static, all 4 zones one colour:  kb-zone <hex6> <brightness0-100>
    KB=/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/four_zoned_kb
    [[ -w $KB/per_zone_mode ]] || exit 3
    h="${2:-}"; br="${3:-}"
    [[ $h =~ ^[0-9a-fA-F]{6}$ ]] || exit 2
    { [[ $br =~ ^[0-9]+$ ]] && (( br >= 0 && br <= 100 )); } || exit 2
    echo "$h,$h,$h,$h,$br" > "$KB/per_zone_mode" ;;
  kb-effect) # animated effect: kb-effect <mode0-7> <speed0-9> <bright0-100> <dir1-2> <hex6>
    KB=/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/four_zoned_kb
    [[ -w $KB/four_zone_mode ]] || exit 3
    m="${2:-}"; s="${3:-}"; br="${4:-}"; d="${5:-}"; h="${6:-}"
    [[ $m =~ ^[0-7]$ && $s =~ ^[0-9]$ && $d =~ ^[12]$ && $h =~ ^[0-9a-fA-F]{6}$ ]] || exit 2
    { [[ $br =~ ^[0-9]+$ ]] && (( br >= 0 && br <= 100 )); } || exit 2
    r=$((16#${h:0:2})); g=$((16#${h:2:2})); bl=$((16#${h:4:2}))
    echo "$m,$s,$br,$d,$r,$g,$bl" > "$KB/four_zone_mode" ;;
  kb-bright) # change brightness, keep current colours: kb-bright <0-100>
    KB=/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/four_zoned_kb
    [[ -w $KB/per_zone_mode ]] || exit 3
    br="${2:-}"; { [[ $br =~ ^[0-9]+$ ]] && (( br >= 0 && br <= 100 )); } || exit 2
    cur="$(cat "$KB/per_zone_mode" 2>/dev/null)"; zones="${cur%,*}"
    [[ $zones =~ ^[0-9a-fA-F]{6}(,[0-9a-fA-F]{6}){3}$ ]] || zones="ffffff,ffffff,ffffff,ffffff"
    echo "$zones,$br" > "$KB/per_zone_mode" ;;
  brightness) # screen backlight as a percentage: brightness <0-100>
    pct="${2:-}"
    [[ $pct =~ ^[0-9]+$ ]] || exit 2
    (( pct <= 100 )) || exit 2
    for b in /sys/class/backlight/*/; do
      [[ -w $b/brightness && -r $b/max_brightness ]] || continue
      max="$(cat "$b/max_brightness")"; [[ $max =~ ^[0-9]+$ && $max -gt 0 ]] || continue
      raw=$(( max * pct / 100 ))
      floor=$(( max / 50 )); (( floor < 1 )) && floor=1
      (( pct > 0 && raw < floor )) && raw=$floor
      echo "$raw" > "$b/brightness" 2>/dev/null || true
    done ;;
  profile) # apply a named power preset, then remember it: profile <name> [kb_hex]
    name="${2:-}"; kbhex="${3:-ffffff}"
    [[ $kbhex =~ ^[0-9a-fA-F]{6}$ ]] || kbhex=ffffff
    case "$name" in
      ultra)
        "$0" cpu-cores ecore            || true
        "$0" turbo off                  || true
        "$0" cpu-cap 20                 || true
        "$0" power-limit 20 20          || true
        "$0" platform-profile low-power || true
        "$0" kb-bright 0                || true
        "$0" brightness 1               || true ;;
      balanced)
        "$0" cpu-cores all              || true
        "$0" turbo on                   || true
        "$0" cpu-cap 100                || true
        "$0" power-limit 65 157         || true
        "$0" platform-profile balanced  || true
        "$0" kb-zone "$kbhex" 100       || true
        "$0" brightness 60              || true ;;
      performance)
        "$0" cpu-cores all              || true
        "$0" turbo on                   || true
        "$0" cpu-cap 100                || true
        "$0" power-limit 65 157         || true
        "$0" platform-profile performance || true
        "$0" kb-zone "$kbhex" 100       || true
        "$0" brightness 90              || true ;;
      *) exit 2 ;;
    esac
    install -d -m 755 /var/lib/omarchy-perf 2>/dev/null || true
    printf '%s\n' "$name"  > /var/lib/omarchy-perf/profile 2>/dev/null || true
    printf '%s\n' "$kbhex" > /var/lib/omarchy-perf/kbhex   2>/dev/null || true ;;
  apply-saved) # re-apply the remembered profile (run at boot by the restore service)
    p="$(cat /var/lib/omarchy-perf/profile 2>/dev/null)" || exit 0
    h="$(cat /var/lib/omarchy-perf/kbhex   2>/dev/null)" || h=ffffff
    [[ -n $p ]] || exit 0
    exec "$0" profile "$p" "$h" ;;
  *) echo "usage: omarchy-perf-helper {turbo|cpu-cap|cpu-cores|power-limit|platform-profile|nvidia-powerd|battery-limit|fan|kb-zone|kb-effect|kb-bright|brightness|profile|apply-saved} <value...>" >&2; exit 2 ;;
esac
HELPER
chmod 755 /usr/local/bin/omarchy-perf-helper
chown root:root /usr/local/bin/omarchy-perf-helper
echo "==> Installed /usr/local/bin/omarchy-perf-helper"

cat > /etc/sudoers.d/omarchy-perf <<EOF
# Let the Performance plugin apply power settings without a password.
# Scoped to the single root-owned, input-validated helper below.
$TARGET_USER ALL=(root) NOPASSWD: /usr/local/bin/omarchy-perf-helper
EOF
chmod 440 /etc/sudoers.d/omarchy-perf
if visudo -cf /etc/sudoers.d/omarchy-perf >/dev/null; then
  echo "==> Installed /etc/sudoers.d/omarchy-perf (validated)"
else
  echo "!! sudoers validation FAILED — removing"; rm -f /etc/sudoers.d/omarchy-perf; exit 1
fi

install -d -m 755 /var/lib/omarchy-perf
chown root:root /var/lib/omarchy-perf

cat > /etc/systemd/system/omarchy-perf-restore.service <<'UNIT'
[Unit]
Description=Restore last-selected Omarchy power profile
After=multi-user.target
ConditionPathExists=/var/lib/omarchy-perf/profile

[Service]
Type=oneshot
ExecStart=/usr/local/bin/omarchy-perf-helper apply-saved

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable omarchy-perf-restore.service >/dev/null 2>&1 || true
echo "==> Installed + enabled omarchy-perf-restore.service (remembers last profile across reboots)"
echo
echo "DONE. The Performance panel's controls go live immediately — no re-login needed."
