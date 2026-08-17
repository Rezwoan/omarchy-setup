---
name: machine-hardware-setup
description: "This machine's hardware and the custom system tooling built on it"
metadata: 
  node_type: memory
  type: project
  originSessionId: 97db5c87-566d-47af-9b02-f3292351c511
  modified: 2026-08-02T00:14:44.266Z
---

Machine: **Acer Predator Helios Neo 16 (PHN16-71)** — i5-13500HX, NVIDIA RTX 4050 (Optimus), dual NVMe, Omarchy (Arch + Hyprland, uwsm), zsh, user `reezz-arch` (uid 1000), sudo needs password.

Custom setup built (all in [[omarchy-setup-repo]]):
- **Performance control center** in `Super+Alt+Space` menu via `~/.config/omarchy/extensions/menu.sh` (omarchy's extension hook). Controls power profile (power-profiles-daemon), thermal profile, CPU turbo, fan, GPU mode, GPU dynamic boost, battery limit, session restore. Privileged actions via `/usr/local/bin/omarchy-perf-helper` (root-owned, scoped NOPASSWD sudoers `/etc/sudoers.d/omarchy-perf`).
- **GPU**: `envycontrol` for Integrated/Hybrid/Nvidia mode switching (was set to integrated = dGPU off).
- **Acer battery limit + fan control**: `linuwu-sense-dkms` (module `linuwu_sense`, replaces `acer_wmi` via blacklist in `/etc/modprobe.d/linuwu-sense.conf`). Charge limit is a fixed ~80% health-mode toggle, not arbitrary %. Battery is worn to ~80% design capacity.
- **File managers**: Dolphin (GUI default, Hackerman dark theme) + yazi (TUI). Removed nautilus/spacedrive.
- **Drives**: internal NTFS (Files/Dev/Study/Windows) + exFAT (NewVolume) auto-mount via fstab `x-systemd.automount` at `/mnt/*` (ntfs3, nofail). NTFS folders from Windows carry the read-only DOS attribute (ntfs3 blocks writes) — fix with `chmod -R u+w /mnt/<drive>`.
