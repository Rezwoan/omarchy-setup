---
name: machine-hardware-setup
description: "This machine's hardware, running Omarchy 4.0.1+ (omarchy-shell), and the custom tooling built on it"
metadata: 
  node_type: memory
  type: project
  originSessionId: 4d5fc693-0e17-4e1e-bce2-dc9c3fcf855e
  modified: 2026-08-31T15:41:03.255Z
---

Machine: **Acer Predator Helios Neo 16 (PHN16-71)** — i5-13500HX (6P+8E, hybrid), NVIDIA RTX 4050 (Optimus), dual NVMe, 1920x1200@165 internal display at 1.25x scale. Omarchy (Arch + Hyprland, via uwsm), user `rex` (uid 1000), sudo needs a password. Reinstalled fresh 2026-08-27 on the same physical hardware as a prior install (old repo was for that install's setup).

Omarchy is on the **omarchy-shell** architecture (v4.0.1+): a single long-running Quickshell process (`omarchy-shell`) hosts the bar, notifications, panels — waybar/walker/mako no longer exist. Hyprland config is Lua (`~/.config/hypr/*.lua`), not `.conf`. See [[omarchy-setup-repo]] for the restore repo.

Custom setup built this session (all in [[omarchy-setup-repo]]):
- **Performance plugin** — a real omarchy-shell bar-widget plugin (not a menu extension like the old setup) at `~/.config/omarchy/plugins/io.github.rezwoan.performance/`, ported from the old walker-menu "Performance" control center. See [[performance-plugin]] for the architecture and hard-won lessons.
- **linuwu-sense-dkms**: installed via AUR, but its kernel module needs a one-time hot-swap from the stock `acer_wmi` driver — see the plugin's `enable-keyboard.sh` (`modprobe -r acer_wmi && modprobe linuwu_sense` + blacklist config). Unlocks keyboard RGB + 80% battery charge limit + fan control.
- **envycontrol**: not installed yet on this machine — GPU-mode switching (Integrated/Hybrid/Nvidia) in the plugin stays hidden until it is.
- **zsh + oh-my-zsh + Powerlevel10k**: restored as the login shell. Gotcha: `chsh` updates `/etc/passwd` immediately, but a running graphical session's systemd --user manager caches `SHELL` from login time — `systemctl --user set-environment SHELL=/usr/bin/zsh` patches it live without a reboot; a real reboot fixes it permanently via PAM.
- **Fn+F6 / "Predator key" — CORRECTED, see [[performance-plugin]] for full detail**: these are two genuinely distinct physical keys, confirmed via a live raw evdev capture (not assumed). The Predator button fires *only* evdev code 148 (`KEY_PROG1`) on the internal keyboard device; Fn+F6 fires on entirely different devices and never touches code 148. Bound in `~/.config/hypr/bindings.lua` as `o.bind("code:156", ...)` (156 = evdev 148 + 8) — opens the PredatorSense panel, and *only* that key, not Fn+F6. The prior note here (claiming they're the same key/keycode) was wrong — it came from misreading `hyprctl binds -j`, which reports empty `key`/`keycode` fields for *every* `code:`-syntax bind, not just failed ones.
- **USB 2.4GHz wireless keyboard/mouse dongle drops after idling** — root cause confirmed via `journalctl -k`: a real `usb 1-1: USB disconnect` + re-enumeration, not just the dongle's own autosuspend (its `power/control` was already `on`). The actual cause is PCIe runtime PM on the xHCI USB controller hosting it (`0000:00:14.0`, Intel 700-series chipset) — `power/control=auto` let the whole controller runtime-suspend and mishandle resuming this specific dongle (vendor:product `0c45:fefe`, reports as "2.4G Dongle"). Fixed via a udev rule pinning both the controller and the dongle to `power/control=on` — see `system/fix-usb-dongle-disconnect.sh` in [[omarchy-setup-repo]].
