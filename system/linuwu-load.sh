#!/bin/bash
# Make linuwu_sense take over from acer_wmi (persist + hot-swap, no reboot).
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

# Persist across boots: don't load acer_wmi, do load linuwu_sense.
echo "blacklist acer_wmi"                    > /etc/modprobe.d/linuwu-sense.conf
echo "linuwu_sense"                          > /etc/modules-load.d/linuwu-sense.conf
echo "==> wrote modprobe blacklist + modules-load config"

# Hot-swap now.
modprobe -r acer_wmi 2>/dev/null && echo "==> unloaded acer_wmi" || echo "==> acer_wmi not loaded / already out"
if modprobe linuwu_sense; then echo "==> loaded linuwu_sense"; else echo "!! failed to load linuwu_sense"; exit 1; fi

sleep 1
BASE=$(echo /sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/*_sense 2>/dev/null)
echo "==> sysfs base: ${BASE:-<none>}"
if [[ -d $BASE ]]; then
  echo "    files: $(ls "$BASE" | tr '\n' ' ')"
  echo "    battery_limiter = $(cat "$BASE"/battery_limiter 2>/dev/null)"
  echo "    fan_speed       = $(cat "$BASE"/fan_speed 2>/dev/null)"
  echo "DONE — Linuwu-Sense active."
else
  echo "!! linuwu_sense loaded but predator_sense sysfs missing — a reboot may be needed."
fi
