# Performance

A bar-widget plugin for `omarchy-shell` that ports an old walker-menu
"Performance" control center to a proper themed panel, with two tabs:

- **General** — one-tap Power Presets (Ultra Saver / Balanced / Performance,
  persisted and reapplied on boot), power-profiles-daemon, thermal profile,
  CPU turbo/cores/max-frequency/RAPL power limit, GPU mode + dynamic boost,
  80% battery charge limit, fan speed, session restore.
- **Keyboard** — 4-zone RGB: brightness, 9 static colors, 7 animated effects
  (Breathing/Neon/Wave/Shifting/Zoom/Meteor/Twinkling), match-theme/off.

The bar icon and panel header both show the Acer Predator claw mark, recolored
live based on the active mode: **green** = battery saver, **neon magenta** =
performance, **blue** = balanced, theme foreground otherwise.

Built for an Acer Predator Helios Neo 16 (PHN16-71, i5-13500HX + RTX 4050),
but everything except the Keyboard tab and battery-limit/fan (which need
Acer's `linuwu-sense` driver) works on any Intel `intel_pstate` + RAPL laptop.

## Install

```bash
omarchy plugin enable io.github.rezwoan.performance --section right
sudo bash install-helper.sh   # one-time: installs the privileged write path
```

Without `install-helper.sh`, the panel still shows live status (nothing
breaks), but every button/toggle silently no-ops — `sudo -n` to a
not-yet-installed helper just fails quietly. The panel shows a banner
reminding you when this is the case.

Optional AUR packages unlock more sections:

- `envycontrol` — GPU mode switching (Integrated/Hybrid/Nvidia)
- `linuwu-sense-dkms` — 80% battery charge limit, fan speed, keyboard RGB.
  Installing the package isn't enough on its own — its kernel module has to
  actually be loaded in place of the stock `acer_wmi` driver. If
  `lsmod | grep linuwu` comes up empty, run:
  ```bash
  sudo bash enable-keyboard.sh
  ```

**No keybind opens this panel — bar-icon click only.** On this laptop,
`hyprctl binds` shows the Predator-adjacent function key literally *is*
`XF86MonBrightnessUp` at the Hyprland level (same raw evdev keycode, no
separate signal exists to bind); check yours the same way before wiring one
up on a different machine.

## Files

- `manifest.json` — plugin declaration (`kinds: ["bar-widget"]`)
- `Panel.qml` — bar icon + popup panel (single entry point, following the
  `omarchy.power` / `omarchy.monitor` first-party pattern)
- `Model.js` — pure JSON-parsing + label/icon helpers, no QML types
- `status.sh` — read-only status snapshot (sysfs + systemctl reads only, no sudo)
- `install-helper.sh` — one-time sudo installer for the privileged write path
- `enable-keyboard.sh` — one-time sudo hot-swap from `acer_wmi` to `linuwu_sense`
- `assets/predator-mask.png` — white-on-transparent silhouette, tinted at
  runtime via `QtQuick.Effects.MultiEffect{colorization}` (same pattern as the
  first-party Tray widget's symbolic icons)

## How writes work

Every privileged action goes through `sudo -n /usr/local/bin/omarchy-perf-helper
<verb> <args>` — a root-owned, verb-whitelisted script installed by
`install-helper.sh` alongside a sudoers rule scoped to that one binary
(`NOPASSWD` only for this exact path, no broad sudo grant). The helper
validates every value before touching a sysfs node, so it can't be coerced
into running arbitrary commands even though it's passwordless.

Power presets (Ultra Saver / Balanced / Performance) are persisted to
`/var/lib/omarchy-perf/profile` and re-applied on every boot by
`omarchy-perf-restore.service`.

## Developing this plugin further

Two things that cost real debugging time and will bite again if forgotten:

- `bar.shellQuote()` is documented in Omarchy's own `shell/plugins/bar/README.md`
  but **does not exist** — the real function is `Util.shellQuote()` from
  `qs.Commons`. Calling the documented-but-wrong one throws a silent QML
  TypeError (only visible via `journalctl --user -t omarchy-shell`), so every
  click does nothing with no on-screen error at all.
- Editing this file while it's already placed in the bar does not reliably
  hot-reload, despite the plugin docs. `omarchy-shell shell rescanPlugins`
  didn't help either — only a full `omarchy restart shell` (confirm a new
  quickshell PID) reliably picks up a change. Verify with that, not the
  "Local plugin changed, reloading" journal line.

## Uninstall

```bash
omarchy plugin remove io.github.rezwoan.performance
sudo rm -f /usr/local/bin/omarchy-perf-helper /etc/sudoers.d/omarchy-perf \
           /etc/systemd/system/omarchy-perf-restore.service
sudo systemctl daemon-reload
```
