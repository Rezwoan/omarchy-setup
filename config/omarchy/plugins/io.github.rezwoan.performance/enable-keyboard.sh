#!/bin/bash
# Makes linuwu_sense take over from the stock acer_wmi driver (persists across
# reboots, and hot-swaps right now so you don't have to reboot). Needed for
# the Performance plugin's Keyboard tab (RGB) and Battery charge-limit/fan
# controls — linuwu-sense-dkms is already installed on this machine, but its
# kernel module was never loaded because acer_wmi got there first at boot.
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with sudo."; exit 1; }

echo "blacklist acer_wmi" > /etc/modprobe.d/linuwu-sense.conf
echo "linuwu_sense" > /etc/modules-load.d/linuwu-sense.conf
echo "==> wrote modprobe blacklist + modules-load config (for future boots)"

modprobe -r acer_wmi 2>/dev/null && echo "==> unloaded acer_wmi" || echo "==> acer_wmi not loaded / already out"
if modprobe linuwu_sense; then echo "==> loaded linuwu_sense"; else echo "!! failed to load linuwu_sense"; exit 1; fi

sleep 1
BASE=$(echo /sys/module/linuwu_sense/drivers/platform:acer-wmi/acer-wmi/*_sense 2>/dev/null)
echo "==> sysfs base: ${BASE:-<none>}"
if [[ -d $BASE ]]; then
  echo "    files: $(ls "$BASE" | tr '\n' ' ')"
  echo "    battery_limiter = $(cat "$BASE"/battery_limiter 2>/dev/null)"
  echo "    fan_speed       = $(cat "$BASE"/fan_speed 2>/dev/null)"
  echo "DONE — Linuwu-Sense active. Open the Performance panel's Keyboard tab now."
else
  echo "!! linuwu_sense loaded but the sense sysfs directory is missing — a reboot may be needed."
fi
