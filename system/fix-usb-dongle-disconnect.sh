#!/bin/bash
# Fix a wireless keyboard/mouse 2.4GHz dongle dropping after being idle for a
# bit (stops responding until you physically unplug/replug it). Root cause,
# confirmed via `journalctl -k`: PCIe runtime PM (power/control=auto) on the
# xHCI USB controller was suspending the *whole controller* on idle, and
# mishandling resume for this dongle specifically — a real
# `usb 1-1: USB disconnect` + re-enumeration as a new device, not just the
# dongle itself autosuspending (its own power/control was already "on").
#
# Installs a udev rule pinning the controller (by PCI address) and the
# dongle (by USB vendor:product ID, as defense in depth) to full power
# always. Safe: only affects this one PCI device and this one USB device,
# not USB power management system-wide.
#
# Run with:  sudo bash fix-usb-dongle-disconnect.sh
# Auto-detects the dongle by matching /sys/bus/usb/devices/*/product against
# "Dongle" (case-insensitive) — override with DONGLE_VID/DONGLE_PID env vars
# if your receiver reports a different product string.

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Please run with sudo:  sudo bash fix-usb-dongle-disconnect.sh"; exit 1; }

find_dongle() {
  local d vid pid product
  for d in /sys/bus/usb/devices/*/; do
    [[ -f "$d/idVendor" && -f "$d/idProduct" && -f "$d/product" ]] || continue
    product="$(cat "$d/product" 2>/dev/null)"
    if [[ $product =~ [Dd]ongle ]]; then
      vid="$(cat "$d/idVendor")"
      pid="$(cat "$d/idProduct")"
      pci="$(readlink -f "$d" | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | head -1)"
      echo "$vid $pid $pci"
      return 0
    fi
  done
  return 1
}

if [[ -n "${DONGLE_VID:-}" && -n "${DONGLE_PID:-}" ]]; then
  VID="$DONGLE_VID"; PID="$DONGLE_PID"; PCI="${DONGLE_PCI:-}"
else
  read -r VID PID PCI < <(find_dongle) || {
    echo "Couldn't auto-detect a USB device whose product name contains \"Dongle\"."
    echo "Find yours with: for d in /sys/bus/usb/devices/*/; do cat \"\$d/product\" 2>/dev/null; done"
    echo "Then re-run as: DONGLE_VID=xxxx DONGLE_PID=yyyy DONGLE_PCI=0000:00:14.0 sudo -E bash $0"
    exit 1
  }
fi

[[ -n $PCI ]] || { echo "Found dongle $VID:$PID but couldn't resolve its parent PCI controller — pass DONGLE_PCI=0000:xx:xx.x explicitly."; exit 1; }

echo "==> Dongle: $VID:$PID on PCI controller $PCI"

RULE=/etc/udev/rules.d/50-usb-dongle-no-suspend.rules
cat > "$RULE" <<EOF
# Keep the USB host controller hosting the 2.4GHz wireless dongle at full
# power always — see fix-usb-dongle-disconnect.sh for why.
ACTION=="add", SUBSYSTEM=="pci", KERNEL=="$PCI", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="$VID", ATTR{idProduct}=="$PID", ATTR{power/control}="on", ATTR{power/autosuspend_delay_ms}="-1"
EOF
chmod 644 "$RULE"
echo "==> Installed $RULE"

udevadm control --reload
echo "$PCI" > "/sys/bus/pci/devices/$PCI/power/control" 2>/dev/null || true
for d in /sys/bus/usb/devices/*/; do
  if [[ -f "$d/idVendor" && "$(cat "$d/idVendor")" == "$VID" && "$(cat "$d/idProduct" 2>/dev/null)" == "$PID" ]]; then
    echo on > "$d/power/control"
    echo -1 > "$d/power/autosuspend_delay_ms"
  fi
done
echo "on" > "/sys/bus/pci/devices/$PCI/power/control"
echo "==> Applied immediately — no reboot needed. The rule re-applies automatically on every boot/reconnect."
