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
# -1 is the in-band "sensor not reported" sentinel across every numeric
# telemetry field below (matches Model.js's fmt* helpers) — reject anything
# that isn't a bare number (nvidia-smi prints "[N/A]" for fields a given GPU
# doesn't report, e.g. power.limit on most laptop GPUs) rather than letting
# garbage into the JSON.
sanitize_num() {
  [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && echo "$1" || echo "-1"
}
hwmon_temp() {
  # Find a hwmon chip by exact name (e.g. "coretemp") and print one of its
  # tempN_input files in whole degrees C, or empty if not found/readable.
  local want=$1 attr=${2:-temp1_input} hw name
  for hw in /sys/class/hwmon/hwmon*; do
    name="$(cat "$hw/name" 2>/dev/null)"
    if [[ $name == "$want" && -r "$hw/$attr" ]]; then
      echo "$(($(cat "$hw/$attr") / 1000))"
      return
    fi
  done
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

# ---------------------------------------------------------------------------
# Telemetry (v2.0.0) — all unprivileged, all best-effort. Every source here
# degrades to -1/""/"[]" cleanly when absent so the panel never breaks on a
# machine missing an optional dependency.
# ---------------------------------------------------------------------------

# CPU %: two /proc/stat samples, one now and one from the last run, persisted
# in a small state file — avoids a blocking sleep just to get a delta.
cpu_state="$HOME/.cache/omarchy-perf/cpu-prev"
install -d -m 755 "$(dirname "$cpu_state")" 2>/dev/null || true
read -r cur_total cur_idle < <(awk '/^cpu /{t=0; for(i=2;i<=NF;i++) t+=$i; print t, $5}' /proc/stat)
prev_total=0; prev_idle=0
[[ -f $cpu_state ]] && read -r prev_total prev_idle < "$cpu_state" 2>/dev/null
echo "$cur_total $cur_idle" > "$cpu_state" 2>/dev/null || true
dtotal=$((cur_total - prev_total))
didle=$((cur_idle - prev_idle))
cpu_pct=0
((dtotal > 0)) && cpu_pct=$((100 * (dtotal - didle) / dtotal))

# RAM: MemTotal - MemAvailable (accounts for reclaimable cache, unlike MemFree).
mem_total_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)"
mem_avail_kb="$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null)"
ram_used_mb=-1; ram_total_mb=-1
if [[ -n $mem_total_kb && -n $mem_avail_kb ]]; then
  ram_used_mb=$(((mem_total_kb - mem_avail_kb) / 1024))
  ram_total_mb=$((mem_total_kb / 1024))
fi

# CPU package temp: match thermal_zone by *type string*, not index (zone
# numbering isn't stable across boots/kernel updates) — x86_pkg_temp is the
# standard Intel aggregate; TCPU/TCPU_PCI are this hardware's own zones.
# Falls back to the coretemp hwmon chip if no thermal_zone matches.
cpu_temp=""
for want in x86_pkg_temp TCPU TCPU_PCI; do
  for tz in /sys/class/thermal/thermal_zone*; do
    if [[ -r $tz/type && "$(cat "$tz/type" 2>/dev/null)" == "$want" && -r $tz/temp ]]; then
      cpu_temp="$(($(cat "$tz/temp") / 1000))"
      break 2
    fi
  done
done
[[ -z $cpu_temp ]] && cpu_temp="$(hwmon_temp coretemp)"
cpu_temp="$(sanitize_num "${cpu_temp:--1}")"

# Fan RPM straight from the "acer" hwmon chip (same EC the fan_speed sysfs
# control belongs to) — resolved by chip name, not a hardcoded hwmon index.
fan1_rpm=""; fan2_rpm=""
for hw in /sys/class/hwmon/hwmon*; do
  if [[ "$(cat "$hw/name" 2>/dev/null)" == "acer" ]]; then
    [[ -r $hw/fan1_input ]] && fan1_rpm="$(cat "$hw/fan1_input")"
    [[ -r $hw/fan2_input ]] && fan2_rpm="$(cat "$hw/fan2_input")"
    break
  fi
done
fan1_rpm="$(sanitize_num "${fan1_rpm:--1}")"
fan2_rpm="$(sanitize_num "${fan2_rpm:--1}")"

# GPU telemetry + hardware info: one nvidia-smi call, comma-split. Fields a
# given GPU doesn't report come back as the literal string "[N/A]" (seen on
# this laptop's power.limit) — sanitize_num() catches that.
gpu_model=""; gpu_util=-1; gpu_mem_used=-1; gpu_mem_total=-1; gpu_temp=-1
gpu_power=-1; gpu_power_limit=-1; gpu_clock_sm=-1; gpu_clock_mem=-1
gpu_driver=""; gpu_vbios=""; gpu_pcie_gen=-1; gpu_pcie_width=-1
if command -v nvidia-smi >/dev/null 2>&1; then
  nv_csv="$(nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,clocks.sm,clocks.mem,driver_version,vbios_version,pcie.link.gen.current,pcie.link.width.current --format=csv,noheader,nounits 2>/dev/null | head -1)"
  if [[ -n $nv_csv ]]; then
    IFS=',' read -r gpu_model gpu_util gpu_mem_used gpu_mem_total gpu_temp gpu_power gpu_power_limit gpu_clock_sm gpu_clock_mem gpu_driver gpu_vbios gpu_pcie_gen gpu_pcie_width <<<"$nv_csv"
    # nvidia-smi pads every field after the first comma with a leading space.
    gpu_model="$(sed 's/^ *//;s/ *$//' <<<"$gpu_model")"
    gpu_driver="$(sed 's/^ *//;s/ *$//' <<<"$gpu_driver")"
    gpu_vbios="$(sed 's/^ *//;s/ *$//' <<<"$gpu_vbios")"
    gpu_util="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_util")")"
    gpu_mem_used="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_mem_used")")"
    gpu_mem_total="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_mem_total")")"
    gpu_temp="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_temp")")"
    gpu_power="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_power")")"
    gpu_power_limit="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_power_limit")")"
    gpu_clock_sm="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_clock_sm")")"
    gpu_clock_mem="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_clock_mem")")"
    gpu_pcie_gen="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_pcie_gen")")"
    gpu_pcie_width="$(sanitize_num "$(sed 's/^ *//' <<<"$gpu_pcie_width")")"
  fi
fi

# Best-effort graphics-stack versions — only shown if the (optional) tool is
# installed, same graceful-degradation philosophy as envycontrol/linuwu-sense.
vulkan_ver=""
command -v vulkaninfo >/dev/null 2>&1 && vulkan_ver="$(vulkaninfo --summary 2>/dev/null | grep -m1 -oE 'Vulkan Instance Version: [0-9.]+' | grep -oE '[0-9.]+$')"
mesa_ver=""
command -v glxinfo >/dev/null 2>&1 && mesa_ver="$(glxinfo 2>/dev/null | grep -m1 'OpenGL version string' | grep -oE 'Mesa [0-9.]+' | awk '{print $2}')"

# Active GPU render-client processes: which /dev/dri/renderD* holders exist,
# capped at 8 by RSS, any single failure degrades to an empty list rather
# than a broken status line (mirrors omagpu's approach).
gpu_processes="[]"
if command -v fuser >/dev/null 2>&1 && ls /dev/dri/renderD* >/dev/null 2>&1; then
  proc_entries=()
  declare -A seen_pids=()
  for node in /dev/dri/renderD*; do
    for pid in $(timeout 0.8 fuser "$node" 2>/dev/null); do
      pid="${pid//[!0-9]/}"
      [[ -z $pid || -n ${seen_pids[$pid]:-} ]] && continue
      seen_pids[$pid]=1
      comm="$(cat "/proc/$pid/comm" 2>/dev/null)"
      [[ -z $comm ]] && continue
      rss_pages="$(awk '{print $2}' "/proc/$pid/statm" 2>/dev/null)"
      [[ $rss_pages =~ ^[0-9]+$ ]] || rss_pages=0
      mem_mb=$((rss_pages * 4096 / 1024 / 1024))
      proc_entries+=("$(jq -n --arg name "$comm" --argjson pid "$pid" --argjson memMb "$mem_mb" '{pid:$pid,name:$name,memMb:$memMb}')")
    done
  done
  if ((${#proc_entries[@]} > 0)); then
    gpu_processes="$(printf '%s\n' "${proc_entries[@]}" | jq -s 'sort_by(-.memMb)[0:8]' 2>/dev/null)"
    [[ -z $gpu_processes || $gpu_processes == "null" ]] && gpu_processes="[]"
  fi
fi

# Rolling ~30-sample history for the panel's sparklines — one sample appended
# per status.sh invocation (the panel's own poll cadence), atomic write.
hist_file="$HOME/.config/omarchy/predatorsense-history.json"
install -d -m 755 "$(dirname "$hist_file")" 2>/dev/null || true
history_json="$(jq -c -n \
  --argjson old "$(cat "$hist_file" 2>/dev/null || echo '{}')" \
  --argjson cpu "$cpu_pct" --argjson gpu "$gpu_util" \
  --argjson cpuTemp "$cpu_temp" --argjson gpuTemp "$gpu_temp" '
  ($old.cpu // []) as $c | ($old.gpu // []) as $g |
  ($old.cpuTemp // []) as $ct | ($old.gpuTemp // []) as $gt |
  { cpu: (($c + [$cpu])[-30:]), gpu: (($g + [$gpu])[-30:]),
    cpuTemp: (($ct + [$cpuTemp])[-30:]), gpuTemp: (($gt + [$gpuTemp])[-30:]) }' 2>/dev/null)"
if [[ -n $history_json ]]; then
  printf '%s' "$history_json" >"${hist_file}.tmp" && mv "${hist_file}.tmp" "$hist_file"
else
  history_json='{"cpu":[],"gpu":[],"cpuTemp":[],"gpuTemp":[]}'
fi

# Fan-curve daemon state (systemd --user unit, see fancurve.sh) — plain
# unprivileged systemctl query, same as checking any other user service.
fancurve_active=false
systemctl --user is-active --quiet omarchy-perf-fancurve.service 2>/dev/null && fancurve_active=true

# The curve itself, so the editor doesn't need a second file-read round trip.
# Falls back to a sane default set until the user saves their own.
fancurve_file="$HOME/.config/omarchy/predatorsense-fancurve.json"
fancurve_json="$(cat "$fancurve_file" 2>/dev/null)"
echo "$fancurve_json" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 ||
  fancurve_json='[{"temp":40,"speed":30},{"temp":60,"speed":50},{"temp":75,"speed":75},{"temp":90,"speed":100}]'

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

jq -n \
  --arg profile "$profile" --arg turbo "$turbo" --arg thermal "$thermal" \
  --arg thermalChoices "$thermal_choices" --arg cpucap "$cpucap" --arg cores "$cores" \
  --arg powerlimit "$powerlimit" --arg gpu "$gpu" --argjson gpuAvailable "$gpu_available" \
  --arg powerd "$powerd" --arg battlimit "$battlimit" --arg fan "$fan" \
  --argjson kbAvailable "$kb_available" --argjson kbPkgInstalled "$kb_pkg_installed" \
  --arg battpct "${battpct:-}" --arg battstatus "${battstatus:-}" --arg preset "$preset" \
  --arg themeHex "$theme_hex" --argjson helperOk "$helper_ok" --argjson sessionEnabled "$session_enabled" \
  --arg kbLink "$kb_link" --arg refreshMonitor "$refresh_monitor" --arg refreshRes "$refresh_res" \
  --arg refreshCurrent "$refresh_current" --arg refreshOptions "$refresh_options" --arg refreshScale "$refresh_scale" \
  --argjson cpuPct "$cpu_pct" --argjson ramUsedMb "$ram_used_mb" --argjson ramTotalMb "$ram_total_mb" \
  --argjson cpuTemp "$cpu_temp" --argjson fan1Rpm "$fan1_rpm" --argjson fan2Rpm "$fan2_rpm" \
  --arg gpuModel "$gpu_model" --argjson gpuUtil "$gpu_util" --argjson gpuMemUsedMb "$gpu_mem_used" \
  --argjson gpuMemTotalMb "$gpu_mem_total" --argjson gpuTemp "$gpu_temp" --argjson gpuPowerW "$gpu_power" \
  --argjson gpuPowerLimitW "$gpu_power_limit" --argjson gpuClockSm "$gpu_clock_sm" --argjson gpuClockMem "$gpu_clock_mem" \
  --arg gpuDriver "$gpu_driver" --arg gpuVbios "$gpu_vbios" --argjson gpuPcieGen "$gpu_pcie_gen" \
  --argjson gpuPcieWidth "$gpu_pcie_width" --arg vulkanVer "$vulkan_ver" --arg mesaVer "$mesa_ver" \
  --argjson gpuProcesses "$gpu_processes" --argjson history "$history_json" --argjson fanCurveActive "$fancurve_active" \
  --argjson fanCurve "$fancurve_json" \
  '{profile:$profile, turbo:$turbo, thermal:$thermal, thermalChoices:$thermalChoices, cpucap:$cpucap,
    cores:$cores, powerlimit:$powerlimit, gpu:$gpu, gpuAvailable:$gpuAvailable, powerd:$powerd,
    battlimit:$battlimit, fan:$fan, kbAvailable:$kbAvailable, kbPkgInstalled:$kbPkgInstalled,
    battpct:$battpct, battstatus:$battstatus, preset:$preset, themeHex:$themeHex, helperOk:$helperOk,
    sessionEnabled:$sessionEnabled, kbLink:$kbLink, refreshMonitor:$refreshMonitor, refreshRes:$refreshRes,
    refreshCurrent:$refreshCurrent, refreshOptions:$refreshOptions, refreshScale:$refreshScale,
    cpuPct:$cpuPct, ramUsedMb:$ramUsedMb, ramTotalMb:$ramTotalMb, cpuTemp:$cpuTemp,
    fan1Rpm:$fan1Rpm, fan2Rpm:$fan2Rpm, gpuModel:$gpuModel, gpuUtil:$gpuUtil, gpuMemUsedMb:$gpuMemUsedMb,
    gpuMemTotalMb:$gpuMemTotalMb, gpuTemp:$gpuTemp, gpuPowerW:$gpuPowerW, gpuPowerLimitW:$gpuPowerLimitW,
    gpuClockSm:$gpuClockSm, gpuClockMem:$gpuClockMem, gpuDriver:$gpuDriver, gpuVbios:$gpuVbios,
    gpuPcieGen:$gpuPcieGen, gpuPcieWidth:$gpuPcieWidth, vulkanVer:$vulkanVer, mesaVer:$mesaVer,
    gpuProcesses:$gpuProcesses, history:$history, fanCurveActive:$fanCurveActive, fanCurve:$fanCurve}'
