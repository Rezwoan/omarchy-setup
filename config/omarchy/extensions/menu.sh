# Omarchy user menu extension — adds a native "Performance" control center.
# See $OMARCHY_PATH/bin/omarchy-menu for functions that can be overwritten.
# Sourced by omarchy-menu (near its tail) BEFORE dispatch, so overriding
# show_main_menu / go_to_menu here injects our entry into Super+Alt+Space.
# Everything lives under ~/.config/omarchy so it survives `omarchy update`.

PERF_HELPER="/usr/local/bin/omarchy-perf-helper"
PERF_SESSION_FLAG="$HOME/.config/omarchy/session-restore.enabled"
PERF_SESSION_SAVE="$HOME/.local/bin/omarchy-session-save"

# ---------- state readers (all defensive; never fail the menu) ----------
_perf_profile()   { powerprofilesctl get 2>/dev/null || echo "unknown"; }
_perf_turbo()     { case "$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)" in
                      0) echo on ;; 1) echo off ;; *) echo n/a ;; esac; }
_perf_gpu_mode()  { command -v envycontrol >/dev/null 2>&1 \
                      && envycontrol --query 2>/dev/null | tail -1 | tr '[:upper:]' '[:lower:]' | grep -oE 'integrated|hybrid|nvidia' | head -1 \
                      || echo "n/a"; }
_perf_powerd()    { systemctl is-active nvidia-powerd 2>/dev/null || true; }
_perf_session()   { [[ -f $PERF_SESSION_FLAG ]] && echo on || echo off; }
_perf_batt()      { local c s; c=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); \
                    s=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); echo "${c:-?}% ${s:-}"; }
# Linuwu-Sense (Acer Predator) sysfs — present only once linuwu_sense is loaded
_perf_ls_base()   { local b; b=$(echo /sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/*_sense 2>/dev/null); [[ -d $b ]] && echo "$b"; }
_perf_battlimit() { local b; b="$(_perf_ls_base)"; [[ -n $b && -r $b/battery_limiter ]] && { [[ "$(cat "$b"/battery_limiter 2>/dev/null)" == "1" ]] && echo on || echo off; } || echo n/a; }
_perf_fan()       { local b v; b="$(_perf_ls_base)"; [[ -n $b && -r $b/fan_speed ]] && { v="$(cat "$b"/fan_speed 2>/dev/null)"; [[ -z $v || $v == 0* ]] && echo auto || echo "$v"; } || echo n/a; }
_perf_thermal()   { cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo n/a; }

# ---------- Performance main submenu ----------
show_performance_menu() {
  local profile turbo gpu powerd session batt thermal fan battlimit
  profile="$(_perf_profile)"; turbo="$(_perf_turbo)"; gpu="$(_perf_gpu_mode)"
  powerd="$(_perf_powerd)"; session="$(_perf_session)"; batt="$(_perf_batt)"
  thermal="$(_perf_thermal)"; fan="$(_perf_fan)"; battlimit="$(_perf_battlimit)"

  local options="󱐋  Power Profile   ·   ${profile}"
  options="$options\n󰔏  Thermal Profile   ·   ${thermal}"
  options="$options\n󰓅  CPU Turbo Boost   ·   ${turbo}"
  options="$options\n󰈐  Fan Mode   ·   ${fan}"
  options="$options\n󰢮  GPU Mode   ·   ${gpu}"
  options="$options\n󱩓  GPU Dynamic Boost   ·   ${powerd/inactive/off}"
  options="$options\n󰁻  Battery Limit 80%   ·   ${battlimit}"
  options="$options\n󰦛  Session Restore   ·   ${session}"
  options="$options\n󰋚  Live GPU Stats"
  options="$options\n󰁹  Battery Info   ·   ${batt}"

  case $(menu "Performance" "$options") in
  *"Power Profile"*)    show_perf_profile_menu ;;
  *"Thermal Profile"*)  show_perf_thermal_menu ;;
  *"CPU Turbo"*)        _perf_toggle_turbo ;;
  *"Fan Mode"*)         show_perf_fan_menu ;;
  *"GPU Mode"*)         show_perf_gpu_menu ;;
  *"Dynamic Boost"*)    _perf_toggle_powerd ;;
  *"Battery Limit"*)    _perf_toggle_battlimit ;;
  *"Session Restore"*)  _perf_toggle_session ;;
  *"Live GPU"*)         present_terminal "watch -n1 nvidia-smi" ;;
  *"Battery Info"*)     _perf_battery_info ;;
  *)                    back_to show_main_menu ;;
  esac
}

# ---------- Power profile (power-profiles-daemon, no root needed) ----------
show_perf_profile_menu() {
  local cur; cur="$(_perf_profile)"
  local opts="󰾆  Power Saver   (max battery)\n󰗑  Balanced\n󰓅  Performance   (max power)"
  case $(menu "Power Profile" "$opts") in
  *"Power Saver"*)  powerprofilesctl set power-saver 2>/dev/null; _perf_helper turbo off; _perf_notify "Power Saver" "CPU power-saving, turbo off" ;;
  *"Balanced"*)     powerprofilesctl set balanced 2>/dev/null;   _perf_helper turbo on;  _perf_notify "Balanced" "Balanced power profile" ;;
  *"Performance"*)  powerprofilesctl set performance 2>/dev/null; _perf_helper turbo on;  _perf_notify "Performance" "Max performance, turbo on" ;;
  *) show_performance_menu; return ;;
  esac
  show_performance_menu
}

# ---------- GPU mode (envycontrol; needs reboot) ----------
show_perf_gpu_menu() {
  if ! command -v envycontrol >/dev/null 2>&1; then
    _perf_notify "GPU Mode" "envycontrol is not installed"; show_performance_menu; return
  fi
  local cur mode=""; cur="$(_perf_gpu_mode)"
  local opts="󰌪  Integrated   (dGPU OFF · best battery)\n󰓅  Hybrid   (on-demand)\n󰢮  Nvidia   (max performance)"
  case $(menu "GPU Mode  ·  reboot required" "$opts") in
  *Integrated*) mode="integrated" ;;
  *Hybrid*)     mode="hybrid" ;;
  *Nvidia*)     mode="nvidia" ;;
  *) show_performance_menu; return ;;
  esac
  if [[ "$mode" == "$cur" ]]; then
    _perf_notify "GPU Mode" "Already in $mode mode"; show_performance_menu; return
  fi
  if pkexec envycontrol -s "$mode" >/dev/null 2>&1; then
    _perf_notify "GPU Mode → $mode" "Reboot required to take effect"
  else
    _perf_notify "GPU Mode" "Switch to $mode failed or cancelled"
  fi
  show_performance_menu
}

# ---------- thermal profile (platform_profile) ----------
show_perf_thermal_menu() {
  local choices f
  f="/sys/firmware/acpi/platform_profile_choices"
  [[ -r $f ]] || { _perf_notify "Thermal Profile" "Not supported"; show_performance_menu; return; }
  # Build a menu from the actual choices this machine exposes
  local opts=""
  for p in $(cat "$f"); do opts="${opts:+$opts\n}󰔏  ${p}"; done
  local sel; sel="$(menu "Thermal Profile" "$opts")"
  sel="$(printf '%s' "$sel" | grep -oE 'low-power|quiet|balanced-performance|balanced|performance' | head -1)"
  if [[ -n $sel ]]; then _perf_helper platform-profile "$sel"; _perf_notify "Thermal Profile" "Set to $sel"; fi
  show_performance_menu
}

# ---------- fan mode (Linuwu-Sense fan_speed) ----------
show_perf_fan_menu() {
  if [[ -z "$(_perf_ls_base)" ]]; then _perf_notify "Fan Mode" "Linuwu-Sense not loaded"; show_performance_menu; return; fi
  local opts="󰈐  Auto\n󰈐  50%\n󰈐  70%\n󰈐  Max (100%)"
  case $(menu "Fan Mode" "$opts") in
  *Auto*)     _perf_helper fan auto; _perf_notify "Fan" "Auto" ;;
  *50%*)      _perf_helper fan 50;   _perf_notify "Fan" "50%" ;;
  *70%*)      _perf_helper fan 70;   _perf_notify "Fan" "70%" ;;
  *Max*)      _perf_helper fan 100;  _perf_notify "Fan" "Max (100%)" ;;
  *) ;;
  esac
  show_performance_menu
}

# ---------- toggles ----------
_perf_toggle_battlimit() {
  if [[ "$(_perf_battlimit)" == "n/a" ]]; then _perf_notify "Battery Limit" "Linuwu-Sense not loaded"; show_performance_menu; return; fi
  if [[ "$(_perf_battlimit)" == "on" ]]; then _perf_helper battery-limit off; _perf_notify "Battery Limit" "Disabled — will charge to 100%"
  else _perf_helper battery-limit on; _perf_notify "Battery Limit" "Enabled — caps charge at ~80%"; fi
  show_performance_menu
}
_perf_toggle_turbo() {
  if [[ "$(_perf_turbo)" == "on" ]]; then _perf_helper turbo off; _perf_notify "CPU Turbo" "Turbo boost OFF"
  else _perf_helper turbo on; _perf_notify "CPU Turbo" "Turbo boost ON"; fi
  show_performance_menu
}
_perf_toggle_powerd() {
  if [[ "$(_perf_powerd)" == "active" ]]; then _perf_helper nvidia-powerd off; _perf_notify "GPU Dynamic Boost" "Disabled"
  else _perf_helper nvidia-powerd on; _perf_notify "GPU Dynamic Boost" "Enabled"; fi
  show_performance_menu
}
_perf_toggle_session() {
  if [[ -f $PERF_SESSION_FLAG ]]; then
    rm -f "$PERF_SESSION_FLAG"; systemctl --user disable --now omarchy-session-save.timer >/dev/null 2>&1
    _perf_notify "Session Restore" "Disabled — apps won't reopen"
  else
    touch "$PERF_SESSION_FLAG"; systemctl --user enable --now omarchy-session-save.timer >/dev/null 2>&1
    [[ -x $PERF_SESSION_SAVE ]] && "$PERF_SESSION_SAVE" >/dev/null 2>&1
    _perf_notify "Session Restore" "Enabled — open apps will reopen on login"
  fi
  show_performance_menu
}

# ---------- battery detail ----------
_perf_battery_info() {
  local info
  info="$(upower -i "$(upower -e 2>/dev/null | grep -m1 BAT)" 2>/dev/null \
        | grep -E 'state|percentage|energy-rate|time to|capacity:' | sed 's/^ *//')"
  [[ -z $info ]] && info="Battery: $(_perf_batt)"
  notify-send -u low "󰁹  Battery" "$info"
  show_performance_menu
}

# ---------- privileged helper wrapper (NOPASSWD sudo) ----------
_perf_helper() { [[ -x $PERF_HELPER ]] && sudo -n "$PERF_HELPER" "$@" >/dev/null 2>&1; }
_perf_notify() { notify-send -u low "󰓅  $1" "$2" 2>/dev/null; }

# ---------- inject "Performance" into the main Omarchy menu ----------
# Preserve the original dispatcher so unknown items still route normally.
if declare -F go_to_menu >/dev/null && ! declare -F _orig_go_to_menu >/dev/null; then
  eval "_orig_go_to_menu() $(declare -f go_to_menu | tail -n +2)"
  go_to_menu() {
    case "${1,,}" in
    *performance*) show_performance_menu ;;
    *) _orig_go_to_menu "$1" ;;
    esac
  }
fi

# Re-list the main menu with our entry added (after Trigger).
show_main_menu() {
  go_to_menu "$(menu "Go" "󰀻  Apps\n󰧑  Learn\n󱓞  Trigger\n󰓅  Performance\n  Style\n  Setup\n󰉉  Install\n󰭌  Remove\n  Update\n  About\n  System")"
}
