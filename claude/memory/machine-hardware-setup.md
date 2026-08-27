---
name: machine-hardware-setup
description: "This machine's hardware, running Omarchy 4.0.1+ (omarchy-shell), and the custom tooling built on it"
metadata: 
  node_type: memory
  type: project
  originSessionId: 4d5fc693-0e17-4e1e-bce2-dc9c3fcf855e
  modified: 2026-08-27T09:52:00.229Z
---

Machine: **Acer Predator Helios Neo 16 (PHN16-71)** — i5-13500HX (6P+8E, hybrid), NVIDIA RTX 4050 (Optimus), dual NVMe, 1920x1200@165 internal display at 1.25x scale. Omarchy (Arch + Hyprland, via uwsm), user `rex` (uid 1000), sudo needs a password. Reinstalled fresh 2026-08-27 on the same physical hardware as a prior install (old repo was for that install's setup).

Omarchy is on the **omarchy-shell** architecture (v4.0.1+): a single long-running Quickshell process (`omarchy-shell`) hosts the bar, notifications, panels — waybar/walker/mako no longer exist. Hyprland config is Lua (`~/.config/hypr/*.lua`), not `.conf`. See [[omarchy-setup-repo]] for the restore repo.

Custom setup built this session (all in [[omarchy-setup-repo]]):
- **Performance plugin** — a real omarchy-shell bar-widget plugin (not a menu extension like the old setup) at `~/.config/omarchy/plugins/io.github.rezwoan.performance/`, ported from the old walker-menu "Performance" control center. See [[performance-plugin]] for the architecture and hard-won lessons.
- **linuwu-sense-dkms**: installed via AUR, but its kernel module needs a one-time hot-swap from the stock `acer_wmi` driver — see the plugin's `enable-keyboard.sh` (`modprobe -r acer_wmi && modprobe linuwu_sense` + blacklist config). Unlocks keyboard RGB + 80% battery charge limit + fan control.
- **envycontrol**: not installed yet on this machine — GPU-mode switching (Integrated/Hybrid/Nvidia) in the plugin stays hidden until it is.
- **zsh + oh-my-zsh + Powerlevel10k**: restored as the login shell. Gotcha: `chsh` updates `/etc/passwd` immediately, but a running graphical session's systemd --user manager caches `SHELL` from login time — `systemctl --user set-environment SHELL=/usr/bin/zsh` patches it live without a reboot; a real reboot fixes it permanently via PAM.
- **Fn+F6 / "Predator key"**: on this unit, `hyprctl binds` proves the Predator-adjacent function key IS `XF86MonBrightnessUp` at the Hyprland level (same raw evdev code, keycode 148 / Hyprland `code:156`) — there's no separate hardware signal to bind a shortcut to. The Performance panel is bar-icon-only, no keybind.
