# Changelog

## 2.0.0

Telemetry, a software fan curve, and a visual redesign — inspired by a look at
two sibling Omarchy plugins (`ucmz851/omagpu`, `moneytosms/omarchy-asus`).

### Added

- **Telemetry tab**: live CPU%, CPU package temp, RAM used, GPU util/temp/power
  stat tiles; a ~2.5-minute rolling CPU/GPU-load sparkline; GPU hardware info
  (model, driver, VBIOS, PCIe link, Vulkan/Mesa versions where available); a
  capped list of processes currently using the GPU render node.
- **Software fan curve**: a draggable temp→speed editor backed by a
  `systemd --user` daemon (`fancurve.sh` / `omarchy-perf-fancurve.service`)
  that polls CPU/GPU temperature and applies the interpolated speed through
  the existing privileged helper (`sudo -n ... fan <pct>`) — no new privilege
  surface. Always reverts to auto fan if the service stops, crashes, or is
  disabled (`ExecStopPost` + an in-script `trap` fallback).
- Bar-icon tooltip now shows live CPU/GPU temp and battery %, not just the
  active preset.
- PROFILE buttons are now color- and icon-coded per preset (green/blue/
  magenta), reusing the same color mapping that already tinted the hero logo.
- hyprmoncfg-aware refresh rate: if `hyprmoncfg` is installed and actively
  managing monitor config, a refresh-rate change is followed by
  `hyprmoncfg save <profile>` so it survives a reboot instead of reverting.
  A complete no-op if hyprmoncfg isn't installed.
- Configurable telemetry poll interval (`refreshIntervalSec`, 5–60s) via the
  plugin's settings schema.
- Keyboard tab controls dim (50% opacity) when `linuwu-sense-dkms` isn't
  loaded, instead of staying fully interactive while silently no-opping.

### Changed

- `fan` helper verb now optionally accepts independent CPU/GPU values
  (`fan <cpu_pct> <gpu_pct>`), backward compatible with the existing
  single-value form. Not yet used by anything (the fan curve applies one
  shared curve to both fans) — room for per-fan curves later.
- `status.sh`'s final JSON assembly moved from a single `printf` to `jq -n`,
  to safely embed the new nested telemetry/history/process JSON without
  manual escaping.

## 1.2.0

- Refresh-rate control switched from `hyprctl keyword monitor` (rejected
  outright on this Lua-parsed Hyprland config) to `hyprctl eval` +
  `hl.monitor()`.
- Refresh-rate control changed from buttons to a `PanelSlider` with a tick
  per supported rate.

## 1.1.0

- Unified PROFILE selector (Ultra Saver/Saver/Balanced/Performance/Ultra
  Performance/Custom) replacing separate power-preset/power-profile/
  thermal-profile rows.
- Fan-speed control fixed (`linuwu_sense` expects `"cpu,gpu"`, not a bare
  number).
- Keyboard color sync to theme/profile (auto-updates on profile change,
  auto-deselects on a manual color pick).
- GPU mode selector (Integrated/Hybrid/Nvidia via envycontrol) restored.
