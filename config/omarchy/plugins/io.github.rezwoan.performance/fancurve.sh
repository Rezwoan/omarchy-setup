#!/bin/bash
# omarchy-perf-fancurve — unprivileged fan-curve daemon for PredatorSense.
#
# Polls CPU/GPU temperature every ~5s, interpolates the hotter of the two
# against a user-authored curve, and applies the result through the
# existing privileged helper via `sudo -n` — the exact same non-interactive
# path every other control in this plugin already uses. This daemon has no
# privilege of its own and makes no sudoers/polkit change.
#
# Runs as a systemd --user unit (omarchy-perf-fancurve.service), not a
# disowned background loop: `Restart=on-failure` recovers from a crash, and
# `ExecStopPost=` (backed up by the `trap` below, in case this is ever run
# outside systemd during development) reverts to auto fan on any stop path
# so a dead daemon never leaves the fan pinned.
set -uo pipefail

HELPER=/usr/local/bin/omarchy-perf-helper
CURVE_FILE="$HOME/.config/omarchy/predatorsense-fancurve.json"

revert_to_auto() { sudo -n "$HELPER" fan auto >/dev/null 2>&1 || true; }
trap revert_to_auto EXIT

cpu_temp() {
  local want tz
  for want in x86_pkg_temp TCPU TCPU_PCI; do
    for tz in /sys/class/thermal/thermal_zone*; do
      [[ -r $tz/type && "$(cat "$tz/type" 2>/dev/null)" == "$want" && -r $tz/temp ]] || continue
      echo $(($(cat "$tz/temp") / 1000))
      return
    done
  done
  for hw in /sys/class/hwmon/hwmon*; do
    [[ "$(cat "$hw/name" 2>/dev/null)" == "coretemp" && -r "$hw/temp1_input" ]] || continue
    echo $(($(cat "$hw/temp1_input") / 1000))
    return
  done
}

gpu_temp() {
  command -v nvidia-smi >/dev/null 2>&1 || return
  nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | tr -d ' '
}

# Linear-interpolate `speed` for `hot` against the curve's {temp,speed}
# points (sorted ascending). Below the first point holds its speed; above
# the last point holds its speed. Small point count (a handful) — clarity
# over cleverness, one jq call per point is negligible at a 5s cycle.
interpolate() {
  local hot="$1" pts p prev_t="" prev_s="" cur_t cur_s
  pts="$(jq -c 'sort_by(.temp)[]' "$CURVE_FILE" 2>/dev/null)"
  [[ -z $pts ]] && { echo 50; return; }
  while IFS= read -r p; do
    cur_t="$(jq -r '.temp' <<<"$p")"
    cur_s="$(jq -r '.speed' <<<"$p")"
    if [[ -z $prev_t ]] && ((hot <= cur_t)); then
      echo "$cur_s"
      return
    fi
    if [[ -n $prev_t ]] && ((hot >= prev_t && hot <= cur_t)); then
      awk -v t="$hot" -v t0="$prev_t" -v t1="$cur_t" -v s0="$prev_s" -v s1="$cur_s" \
        'BEGIN { if (t1==t0) print s0; else printf "%.0f\n", s0 + (s1-s0)*(t-t0)/(t1-t0) }'
      return
    fi
    prev_t="$cur_t"
    prev_s="$cur_s"
  done <<<"$pts"
  echo "${prev_s:-50}"
}

while true; do
  if [[ -r $CURVE_FILE ]]; then
    ct="$(cpu_temp)"; ct="${ct:-0}"
    gt="$(gpu_temp)"; gt="${gt:-0}"
    hot=$((ct > gt ? ct : gt))
    pct="$(interpolate "$hot")"
    [[ $pct =~ ^[0-9]+$ ]] || pct=50
    ((pct < 0)) && pct=0
    ((pct > 100)) && pct=100
    if ((pct <= 0)); then
      sudo -n "$HELPER" fan auto >/dev/null 2>&1 || true
    else
      sudo -n "$HELPER" fan "$pct" >/dev/null 2>&1 || true
    fi
  fi
  sleep 5
done
