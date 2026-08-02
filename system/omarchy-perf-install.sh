#!/bin/bash
# One-time privileged installer for the Omarchy Performance center + drive automount.
# Run with: sudo bash omarchy-perf-install.sh
# Creates: root-owned power helper, a scoped NOPASSWD sudoers rule, and fstab
# automount entries (by UUID) for the internal data drives.
#
# NOTE: the fstab UUIDs below are specific to the original machine. On a
# different machine, edit the DRIVES array with your own `lsblk -f` UUIDs
# (or remove that section and mount drives however you like).

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with sudo."; exit 1; }

TARGET_USER="${SUDO_USER:-$(id -un 1000 2>/dev/null || echo reezz-arch)}"
U="$(id -u "$TARGET_USER")"; G="$(id -g "$TARGET_USER")"
echo "==> Installing for user $TARGET_USER (uid=$U gid=$G)"

# ------------------------------------------------------------------ helper
install -d /usr/local/bin
cat > /usr/local/bin/omarchy-perf-helper <<'HELPER'
#!/bin/bash
# omarchy-perf-helper — privileged applier for the Omarchy Performance menu.
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
  epp)
    case "$val" in
      power|balance_power|balance_performance|performance|default)
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
          [[ -w $f ]] && echo "$val" > "$f" || true
        done ;;
      *) exit 2 ;;
    esac ;;
  platform-profile)
    case "$val" in
      low-power|quiet|balanced|balanced-performance|performance)
        echo "$val" > /sys/firmware/acpi/platform_profile ;;
      *) exit 2 ;;
    esac ;;
  gpu-runtime)
    case "$val" in
      auto|on)
        for d in /sys/bus/pci/devices/*/; do
          [[ "$(cat "$d/vendor" 2>/dev/null)" == "0x10de" ]] && echo "$val" > "$d/power/control" 2>/dev/null || true
        done ;;
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
  *) echo "usage: omarchy-perf-helper {turbo|epp|platform-profile|gpu-runtime|nvidia-powerd|battery-limit|fan|kb-zone|kb-effect|kb-bright} <value...>" >&2; exit 2 ;;
esac
HELPER
chmod 755 /usr/local/bin/omarchy-perf-helper
chown root:root /usr/local/bin/omarchy-perf-helper
echo "==> Installed /usr/local/bin/omarchy-perf-helper"

# ------------------------------------------------------------------ sudoers
cat > /etc/sudoers.d/omarchy-perf <<EOF
# Let the Omarchy Performance menu apply power settings without a password.
# Scoped to the single root-owned, input-validated helper below.
$TARGET_USER ALL=(root) NOPASSWD: /usr/local/bin/omarchy-perf-helper
EOF
chmod 440 /etc/sudoers.d/omarchy-perf
if visudo -cf /etc/sudoers.d/omarchy-perf >/dev/null; then
  echo "==> Installed /etc/sudoers.d/omarchy-perf (validated)"
else
  echo "!! sudoers validation FAILED — removing"; rm -f /etc/sudoers.d/omarchy-perf; exit 1
fi

# ------------------------------------------------------------------ fstab automounts
STAMP="$(date +%s)"
cp /etc/fstab "/etc/fstab.bak.$STAMP"
echo "==> Backed up /etc/fstab -> /etc/fstab.bak.$STAMP"

NTFS_OPTS="rw,nofail,x-systemd.automount,x-systemd.idle-timeout=60,uid=$U,gid=$G,umask=022,windows_names"
EXFAT_OPTS="rw,nofail,x-systemd.automount,x-systemd.idle-timeout=60,uid=$U,gid=$G,umask=022"

# label|uuid|fstype|mountpoint|opts   (EDIT UUIDs for a different machine)
DRIVES=(
  "Files|5C8275718275510E|ntfs3|/mnt/Files|$NTFS_OPTS"
  "Dev|9C64263364261116|ntfs3|/mnt/Dev|$NTFS_OPTS"
  "Study|1842602F426013B2|ntfs3|/mnt/Study|$NTFS_OPTS"
  "NewVolume|0665-C06E|exfat|/mnt/NewVolume|$EXFAT_OPTS"
  "Windows|98CE4C2DCE4C064A|ntfs3|/mnt/Windows|$NTFS_OPTS"
)

added=0
tmp="/tmp/_fstab_add.$STAMP"
{ echo ""; echo "# --- Omarchy Performance: drive automounts (added $(date -Iseconds)) ---"; } > "$tmp"
for row in "${DRIVES[@]}"; do
  IFS='|' read -r label uuid fstype mnt opts <<< "$row"
  if grep -qiE "UUID=$uuid([[:space:]]|$)" /etc/fstab; then
    echo "   skip $label (UUID already in fstab)"; continue
  fi
  install -d -m 0755 "$mnt"
  printf 'UUID=%-20s %-16s %-6s %s 0 0\n' "$uuid" "$mnt" "$fstype" "$opts" >> "$tmp"
  echo "   + $label -> $mnt ($fstype)"; added=$((added+1))
done
if [[ $added -gt 0 ]]; then cat "$tmp" >> /etc/fstab; fi
rm -f "$tmp"

systemctl daemon-reload
echo "==> fstab updated ($added drive(s) added), systemd reloaded"
echo
echo "DONE. Log out/in (or reboot) for automounts + the Performance menu to be fully live."
