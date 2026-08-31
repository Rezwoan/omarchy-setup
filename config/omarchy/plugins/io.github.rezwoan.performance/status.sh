#!/bin/bash
# Read-only status snapshot for the PredatorSense bar plugin. Never needs
# sudo — every value here is a plain sysfs/systemctl/file read. Prints one
# JSON object.
set -uo pipefail

ls_base() {
  local b
  b=$(echo /sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/*_sense 2>/dev/null)
  [[ -d $b ]] && echo "$b"
}
kb_base() {
  local k=/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/four_zoned_kb
  [[ -d $k ]] && echo "$k"
}

profile="$(powerprofilesctl get 2>/dev/null || echo unknown)"

turbo="n/a"
case "$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)" in
  0) turbo=on ;;
  1) turbo=off ;;
esac

thermal="$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo n/a)"
thermal_choices="$(cat /sys/firmware/acpi/platform_profile_choices 2>/dev/null || echo "")"

cpucap="$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null || echo "")"

total=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l)
online=0
for f in /sys/devices/system/cpu/cpu[0-9]*/online; do
  [[ "$(cat "$f" 2>/dev/null)" == 1 ]] && online=$((online + 1))
done
[[ -e /sys/devices/system/cpu/cpu0/online ]] || online=$((online + 1)) # cpu0 can't offline
smt=$(cat /sys/devices/system/cpu/smt/control 2>/dev/null || echo "")
if ((online < total)); then
  cores="ecore"
elif [[ $smt == off ]]; then
  cores="no-smt"
else
  cores="all"
fi

pl_uw=$(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || echo "")
powerlimit=""
[[ -n $pl_uw ]] && powerlimit=$((pl_uw / 1000000))

gpu="n/a"
gpu_available=false
if command -v envycontrol >/dev/null 2>&1; then
  gpu_available=true
  gpu="$(envycontrol --query 2>/dev/null | tail -1 | tr '[:upper:]' '[:lower:]' | grep -oE 'integrated|hybrid|nvidia' | head -1)"
  [[ -z $gpu ]] && gpu="n/a"
fi

powerd="inactive"
systemctl is-active nvidia-powerd >/dev/null 2>&1 && powerd="active"

lsb="$(ls_base)"
battlimit="n/a"
if [[ -n $lsb && -r "$lsb/battery_limiter" ]]; then
  [[ "$(cat "$lsb/battery_limiter" 2>/dev/null)" == "1" ]] && battlimit=on || battlimit=off
fi

fan="n/a"
if [[ -n $lsb && -r "$lsb/fan_speed" ]]; then
  # linuwu_sense reports/expects "cpu,gpu" (see predator_fan_speed_show/store
  # in linuwu_sense.c) — a bare number here was always rejected with
  # -EINVAL, which is why the fan control silently did nothing.
  raw="$(cat "$lsb/fan_speed" 2>/dev/null)"
  cpu_v="${raw%%,*}"
  [[ -z $cpu_v || $cpu_v == 0 ]] && fan=auto || fan="$cpu_v"
fi

kb_available=false
[[ -n "$(kb_base)" ]] && kb_available=true

# Distinguish "package not installed" from "installed but module not loaded"
# so the panel can offer a one-click fix (pkexec enable-keyboard.sh) instead
# of just telling the user to go install something they already have.
kb_pkg_installed=false
pacman -Qq linuwu-sense-dkms >/dev/null 2>&1 && kb_pkg_installed=true

battpct="$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)"
battstatus="$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)"

preset="$(cat /var/lib/omarchy-perf/profile 2>/dev/null || echo "")"

theme_hex="$(grep -m1 '^accent' "$HOME/.local/state/omarchy/current/theme/colors.toml" 2>/dev/null | grep -oiE '[0-9a-f]{6}' | head -1)"
[[ -z $theme_hex ]] && theme_hex="ffffff"

session_enabled=false
[[ -f "$HOME/.config/omarchy/session-restore.enabled" ]] && session_enabled=true

kb_link="$(cat /var/lib/omarchy-perf/kblink 2>/dev/null)"
[[ $kb_link == theme || $kb_link == profile ]] || kb_link=off

# Refresh rate: no privilege needed at all — it's applied via `hyprctl eval`
# + `hl.monitor()` (see Panel.qml), same as any other hyprctl call. Options
# are derived from the focused monitor's own availableModes at the same
# resolution it's currently running, so the buttons only ever offer rates
# the display actually supports.
refresh_monitor=""
refresh_res=""
refresh_current=""
refresh_options=""
refresh_scale="1"
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  mon_json="$(hyprctl -j monitors 2>/dev/null)"
  if [[ -n $mon_json ]]; then
    focused="$(echo "$mon_json" | jq -c '([.[] | select(.focused)] + .)[0] // empty' 2>/dev/null)"
    if [[ -n $focused && $focused != "null" ]]; then
      refresh_monitor="$(echo "$focused" | jq -r '.name // ""')"
      refresh_current="$(echo "$focused" | jq -r '(.refreshRate // 0) | round')"
      refresh_scale="$(echo "$focused" | jq -r '.scale // 1')"
      refresh_res="$(echo "$focused" | jq -r '"\(.width // 0)x\(.height // 0)"')"
      refresh_options="$(echo "$focused" | jq -r --arg res "$refresh_res" '
        [(.availableModes // [])[] | select(startswith($res + "@"))
          | (split("@")[1] | rtrimstr("Hz") | rtrimstr("hz") | tonumber | round)]
        | unique | sort | join(",")' 2>/dev/null)"
    fi
  fi
fi

# Privileged writes go through a scoped NOPASSWD sudoers rule installed once
# by setup.sh (see README.md) — `sudo -n` fails closed with exit 1 ("a
# password is required") if that rule isn't installed, and only reaches the
# helper (exiting 2, its own no-args usage error) once it is. That's a safe,
# side-effect-free non-interactive readiness probe.
helper_ok=false
if [[ -x /usr/local/bin/omarchy-perf-helper ]]; then
  sudo -n /usr/local/bin/omarchy-perf-helper >/dev/null 2>&1
  [[ $? -eq 2 ]] && helper_ok=true
fi

printf '{"profile":"%s","turbo":"%s","thermal":"%s","thermalChoices":"%s","cpucap":"%s","cores":"%s","powerlimit":"%s","gpu":"%s","gpuAvailable":%s,"powerd":"%s","battlimit":"%s","fan":"%s","kbAvailable":%s,"kbPkgInstalled":%s,"battpct":"%s","battstatus":"%s","preset":"%s","themeHex":"%s","helperOk":%s,"sessionEnabled":%s,"kbLink":"%s","refreshMonitor":"%s","refreshRes":"%s","refreshCurrent":"%s","refreshOptions":"%s","refreshScale":"%s"}\n' \
  "$profile" "$turbo" "$thermal" "$thermal_choices" "$cpucap" "$cores" "$powerlimit" "$gpu" "$gpu_available" "$powerd" "$battlimit" "$fan" "$kb_available" "$kb_pkg_installed" "${battpct:-}" "${battstatus:-}" "$preset" "$theme_hex" "$helper_ok" "$session_enabled" "$kb_link" \
  "$refresh_monitor" "$refresh_res" "$refresh_current" "$refresh_options" "$refresh_scale"
