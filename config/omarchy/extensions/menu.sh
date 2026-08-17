# Omarchy user menu extension — adds a native "Performance" control center.
# See $OMARCHY_PATH/bin/omarchy-menu for functions that can be overwritten.
# Sourced by omarchy-menu (near its tail) BEFORE dispatch, so overriding
# show_main_menu / go_to_menu here injects our entry into Super+Alt+Space.
# Everything lives under ~/.config/omarchy so it survives `omarchy update`.

PERF_HELPER="/usr/local/bin/omarchy-perf-helper"
PERF_SESSION_FLAG="$HOME/.config/omarchy/session-restore.enabled"
PERF_SESSION_SAVE="$HOME/.local/bin/omarchy-session-save"

# ---------- keybindings menu: show the Predator key by name ----------
# The Predator key is kernel keycode 148 -> Hyprland code:156, which the keymap
# resolves to the keysym "XF86Launch1" — so the stock keybindings menu lists it
# as "XF86Launch1". omarchy-menu sources THIS file before it calls
# omarchy-menu-keybindings, so this shell function shadows that binary *inside
# omarchy-menu only* (we still invoke the real one by absolute path). No edit to
# omarchy's source; survives `omarchy update`. Renames the label to "Predator Key".
omarchy-menu-keybindings() { omarchy-menu-keybindings-pretty "$@"; }

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
_perf_cpucap()    { local p; p=$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null); [[ -n $p ]] && echo "${p}%" || echo n/a; }
_perf_powerlimit(){ local u; u=$(cat /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null); [[ -n $u ]] && echo "$(( u/1000000 ))W" || echo n/a; }
_perf_preset()    { local p; p=$(cat /var/lib/omarchy-perf/profile 2>/dev/null); case "$p" in
                      ultra) echo "Ultra Saver" ;; balanced) echo "Balanced" ;; performance) echo "Performance" ;; *) echo "custom" ;; esac; }
_perf_cpucores()  { # report core state: all / no-HT / E-cores (n/total)
  local total online smt
  total=$(ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null | wc -l)
  online=0
  for f in /sys/devices/system/cpu/cpu[0-9]*/online; do [[ "$(cat "$f" 2>/dev/null)" == 1 ]] && online=$((online+1)); done
  [[ -e /sys/devices/system/cpu/cpu0/online ]] || online=$((online+1))  # cpu0 can't offline
  smt=$(cat /sys/devices/system/cpu/smt/control 2>/dev/null)
  if   (( online < total )); then echo "E-cores (${online}/${total})"
  elif [[ $smt == off ]];    then echo "no-HT"
  else echo "all (${total})"; fi
}

# ---------- Performance main submenu ----------
show_performance_menu() {
  local profile turbo gpu powerd session batt thermal fan battlimit cpucap cpucores preset
  profile="$(_perf_profile)"; turbo="$(_perf_turbo)"; gpu="$(_perf_gpu_mode)"
  powerd="$(_perf_powerd)"; session="$(_perf_session)"; batt="$(_perf_batt)"
  thermal="$(_perf_thermal)"; fan="$(_perf_fan)"; battlimit="$(_perf_battlimit)"
  cpucap="$(_perf_cpucap)"; cpucores="$(_perf_cpucores)"; powerlimit="$(_perf_powerlimit)"
  preset="$(_perf_preset)"

  local options="⚡  Power Preset   ·   ${preset}"
  options="$options\n󱐋  Power Profile   ·   ${profile}"
  options="$options\n󰔏  Thermal Profile   ·   ${thermal}"
  options="$options\n󰓅  CPU Turbo Boost   ·   ${turbo}"
  options="$options\n󰾆  CPU Max Freq   ·   ${cpucap}"
  options="$options\n󰬹  CPU Cores   ·   ${cpucores}"
  options="$options\n󰚥  Power Limit   ·   ${powerlimit}"
  options="$options\n󰈐  Fan Mode   ·   ${fan}"
  options="$options\n󰢮  GPU Mode   ·   ${gpu}"
  options="$options\n󱩓  GPU Dynamic Boost   ·   ${powerd/inactive/off}"
  options="$options\n󰁻  Battery Limit 80%   ·   ${battlimit}"
  options="$options\n󰌌  Keyboard Lighting"
  options="$options\n󰦛  Session Restore   ·   ${session}"
  options="$options\n󰋚  Live GPU Stats"
  options="$options\n󰁹  Battery Info   ·   ${batt}"

  case $(menu "Performance" "$options") in
  *"Power Preset"*)     show_perf_preset_menu ;;
  *"Power Profile"*)    show_perf_profile_menu ;;
  *"Thermal Profile"*)  show_perf_thermal_menu ;;
  *"CPU Turbo"*)        _perf_toggle_turbo ;;
  *"CPU Max Freq"*)     show_perf_cpucap_menu ;;
  *"CPU Cores"*)        show_perf_cpucores_menu ;;
  *"Power Limit"*)      show_perf_powerlimit_menu ;;
  *"Fan Mode"*)         show_perf_fan_menu ;;
  *"GPU Mode"*)         show_perf_gpu_menu ;;
  *"Dynamic Boost"*)    _perf_toggle_powerd ;;
  *"Battery Limit"*)    _perf_toggle_battlimit ;;
  *"Keyboard Lighting"*) show_perf_kb_menu ;;
  *"Session Restore"*)  _perf_toggle_session ;;
  *"Live GPU"*)         present_terminal "watch -n1 nvidia-smi" ;;
  *"Battery Info"*)     _perf_battery_info ;;
  *)                    back_to show_main_menu ;;
  esac
}

# ---------- Power presets (one-tap bundles; remembered across reboot) ----------
# Each preset sets CPU cores/boost/freq, RAPL wattage, thermal profile, keyboard
# light and screen brightness in one shot, then persists the choice to
# /var/lib/omarchy-perf/profile so omarchy-perf-restore.service re-applies it on boot.
show_perf_preset_menu() {
  local cur; cur="$(_perf_preset)"
  local opts="🐢  Ultra Power Saver   (E-cores · 20W · dark)"
  opts="$opts\n⚖  Balanced   (default)"
  opts="$opts\n🚀  Performance   (max power)"
  case $(menu "Power Preset  ·  now: ${cur}" "$opts") in
  *"Ultra"*)
     _perf_helper profile ultra
     _perf_notify "Ultra Power Saver" "E-cores only · no boost · 20W · min freq · screen+keyboard dark"
     ;;
  *"Balanced"*)
     _perf_helper profile balanced "$(_perf_theme_hex)"
     _perf_notify "Balanced" "All cores · boost on · 65W · everyday defaults"
     ;;
  *"Performance"*)
     _perf_helper profile performance "$(_perf_theme_hex)"
     _perf_notify "Performance" "All cores · boost on · full power"
     ;;
  *) show_performance_menu; return ;;
  esac
  show_performance_menu
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

# ---------- CPU max frequency cap (intel_pstate max_perf_pct) ----------
show_perf_cpucap_menu() {
  [[ -e /sys/devices/system/cpu/intel_pstate/max_perf_pct ]] || {
    _perf_notify "CPU Max Freq" "intel_pstate not available"; show_performance_menu; return; }
  local opts="󰓅  100%   (full speed)\n󰾅  75%\n󰾆  50%   (battery)\n󱃍  40%   (max battery)"
  case $(menu "CPU Max Frequency" "$opts") in
  *100*) _perf_helper cpu-cap 100; _perf_notify "CPU Max Freq" "100% — full speed" ;;
  *75*)  _perf_helper cpu-cap 75;  _perf_notify "CPU Max Freq" "Capped to 75%" ;;
  *50*)  _perf_helper cpu-cap 50;  _perf_notify "CPU Max Freq" "Capped to 50% — battery" ;;
  *40*)  _perf_helper cpu-cap 40;  _perf_notify "CPU Max Freq" "Capped to 40% — max battery" ;;
  *) ;;
  esac
  show_performance_menu
}

# ---------- CPU core control (offline P-cores / disable hyperthreading) ----------
show_perf_cpucores_menu() {
  [[ -e /sys/devices/system/cpu/cpu1/online ]] || {
    _perf_notify "CPU Cores" "Core hotplug not available"; show_performance_menu; return; }
  local opts="󰬹  All cores   (full)\n󰬈  No Hyperthreading\n󰾆  E-cores only   (battery)"
  case $(menu "CPU Cores  ·  resets on reboot" "$opts") in
  *"All cores"*)  _perf_helper cpu-cores all;    _perf_notify "CPU Cores" "All cores online" ;;
  *"No Hyper"*)   _perf_helper cpu-cores no-smt; _perf_notify "CPU Cores" "Hyperthreading disabled" ;;
  *"E-cores"*)    _perf_helper cpu-cores ecore;  _perf_notify "CPU Cores" "P-cores offlined — running on E-cores" ;;
  *) ;;
  esac
  show_performance_menu
}

# ---------- RAPL package power limit (PL1 sustained / PL2 burst) ----------
show_perf_powerlimit_menu() {
  [[ -e /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw ]] || {
    _perf_notify "Power Limit" "RAPL not available"; show_performance_menu; return; }
  # label   pl1  pl2
  local opts="󰚥  Full   (65W · stock)\n󰛨  45W   (balanced)\n󰋊  35W   (cool/quiet)\n󰁿  25W   (max battery)"
  case $(menu "Power Limit  ·  sustained wattage" "$opts") in
  *Full*) _perf_helper power-limit 65 157; _perf_notify "Power Limit" "65W — stock" ;;
  *45W*)  _perf_helper power-limit 45 64;  _perf_notify "Power Limit" "Capped to 45W" ;;
  *35W*)  _perf_helper power-limit 35 45;  _perf_notify "Power Limit" "Capped to 35W — cool" ;;
  *25W*)  _perf_helper power-limit 25 35;  _perf_notify "Power Limit" "Capped to 25W — max battery" ;;
  *) ;;
  esac
  show_performance_menu
}

# ---------- keyboard lighting (Linuwu-Sense four_zoned_kb) ----------
_perf_kb_base()  { local k=/sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/four_zoned_kb; [[ -d $k ]] && echo "$k"; }
_perf_theme_hex() {  # Omarchy current-theme accent, as 6 hex digits (fallback white)
  local a
  a="$(grep -m1 '^accent' "$HOME/.config/omarchy/current/theme/colors.toml" 2>/dev/null | grep -oiE '[0-9a-f]{6}' | head -1)"
  echo "${a:-ffffff}" | tr 'A-F' 'a-f'
}

show_perf_kb_menu() {
  if [[ -z "$(_perf_kb_base)" ]]; then _perf_notify "Keyboard" "4-zone RGB not available"; show_performance_menu; return; fi
  local opts="󰈹  Color (static)\n󱍢  Effect\n󰃟  Brightness\n󰸉  Match Omarchy theme\n󰽥  Off"
  case $(menu "Keyboard Lighting" "$opts") in
  *"Color"*)      show_perf_kb_color_menu ;;
  *"Effect"*)     show_perf_kb_effect_menu ;;
  *"Brightness"*) show_perf_kb_bright_menu ;;
  *"Match"*)      _perf_helper kb-zone "$(_perf_theme_hex)" 100; _perf_notify "Keyboard" "Matched theme"; show_perf_kb_menu ;;
  *"Off"*)        _perf_helper kb-bright 0; _perf_notify "Keyboard" "Backlight off"; show_perf_kb_menu ;;
  *) show_performance_menu ;;
  esac
}

show_perf_kb_color_menu() {
  local hex=""
  case $(menu "Keyboard Color" "󰉦  Theme\n󰉦  Green\n󰉦  Teal\n󰉦  Cyan\n󰉦  Blue\n󰉦  Purple\n󰉦  Red\n󰉦  Orange\n󰉦  White") in
  *Theme*)  hex="$(_perf_theme_hex)" ;;
  *Green*)  hex="82fb9c" ;;
  *Teal*)   hex="00aec7" ;;
  *Cyan*)   hex="00ffff" ;;
  *Blue*)   hex="3b82f6" ;;
  *Purple*) hex="a855f7" ;;
  *Red*)    hex="ff2b2b" ;;
  *Orange*) hex="ff8800" ;;
  *White*)  hex="ffffff" ;;
  *) show_perf_kb_menu; return ;;
  esac
  _perf_helper kb-zone "$hex" 100; _perf_notify "Keyboard" "Static #$hex"; show_perf_kb_menu
}

show_perf_kb_effect_menu() {
  local hex mode; hex="$(_perf_theme_hex)"
  case $(menu "Keyboard Effect" "󰋙  Static\n󰟆  Breathing\n󰙴  Neon\n󱡍  Wave\n󰑙  Shifting\n󰝥  Zoom\n󰇥  Meteor\n󰝤  Twinkling") in
  *Static*)    _perf_helper kb-zone "$hex" 100; _perf_notify "Keyboard" "Static"; show_perf_kb_menu; return ;;
  *Breathing*) mode=1 ;;
  *Neon*)      mode=2 ;;
  *Wave*)      mode=3 ;;
  *Shifting*)  mode=4 ;;
  *Zoom*)      mode=5 ;;
  *Meteor*)    mode=6 ;;
  *Twinkling*) mode=7 ;;
  *) show_perf_kb_menu; return ;;
  esac
  _perf_helper kb-effect "$mode" 5 100 1 "$hex"; _perf_notify "Keyboard" "Effect applied"; show_perf_kb_menu
}

show_perf_kb_bright_menu() {
  local b=""
  case $(menu "Keyboard Brightness" "󰃠  100%\n󰃝  75%\n󰃟  50%\n󰃞  25%\n󰽥  Off") in
  *100*) b=100 ;; *75*) b=75 ;; *50*) b=50 ;; *25*) b=25 ;; *Off*) b=0 ;;
  *) show_perf_kb_menu; return ;;
  esac
  _perf_helper kb-bright "$b"; _perf_notify "Keyboard" "Brightness ${b}%"; show_perf_kb_menu
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
