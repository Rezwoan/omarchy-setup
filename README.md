# omarchy-setup

My personal [Omarchy](https://omarchy.org/) (Arch + Hyprland) configuration — everything I customized, in one place, so a fresh install can be restored in one go.

Machine: **Acer Predator Helios Neo 16 (PHN16-71)** · i5-13500HX · RTX 4050 · dual NVMe.

## Compatibility

**Targets Omarchy 4.0.1+ — the `omarchy-shell` era.** Omarchy replaced waybar/walker/mako with a single Quickshell process (`omarchy-shell`) that hosts the bar, panels, and notifications, and Hyprland config moved from `.conf` to Lua (`~/.config/hypr/*.lua`). This repo was rebuilt from scratch on 2026-08-27 for that architecture after a fresh reinstall on the same hardware.

If you're restoring onto an *older* Omarchy (waybar + `.conf` hypr config), check out an older commit — this version's `config/hypr/` and the Performance plugin will not work there.

## What's inside

```
shell/     ~/.zshrc ~/.bashrc ~/.bash_profile ~/.p10k.zsh   (oh-my-zsh + Powerlevel10k, aliases)
config/    ~/.config subset:
           hypr/                 Lua config: bindings, monitors, input, look&feel, autostart
           foot/                 the actual daily terminal — JetBrainsMono Nerd Font,
                                  and a Ctrl+Backspace word-delete fix foot doesn't ship by default
           alacritty/ kitty/ ghostty/   kept for reference (font-matched), not currently installed
           omarchy/plugins/io.github.rezwoan.performance/
                                  ← the Performance control center, as a real omarchy-shell plugin
           systemd/user/         omarchy-perf-session-save.{service,timer}
local-bin/ omarchy-perf-session-save / -restore    ← "reopen my apps on login"
system/    fix-drive-mounts.sh, omarchy-ntfs-automount-fix.sh   (drive automount; sudo)
packages/  pacman-explicit.txt, aur.txt               ← package lists to reinstall
claude/    memory/  ← Claude Code's persistent notes about this machine/repo
```

## Highlights

- **Performance plugin** — a proper `omarchy-shell` bar-widget plugin (not a menu extension —
  those don't exist anymore) living at `config/omarchy/plugins/io.github.rezwoan.performance/`.
  Click its icon in the bar (it's the Acer Predator claw logo, recolored live: green = battery
  saver, neon magenta = performance, blue = balanced). Two tabs:
  - **General** — one-tap Power Presets (persisted, reapplied on boot), power-profiles-daemon,
    thermal profile, CPU turbo/cores/max-frequency/RAPL power limit, GPU mode (envycontrol) +
    dynamic boost, 80% battery charge limit, fan speed, session-restore toggle.
  - **Keyboard** — 4-zone RGB: brightness, 9 static colors, 7 animated effects, match-theme/off.
  Every privileged write goes through a single root-owned, verb-whitelisted helper
  (`omarchy-perf-helper`) authorized via a sudoers rule scoped to just that binary — see the
  plugin's own `README.md` for the full security model and setup steps.
- **Session restore** — snapshots open windows + their workspaces every minute and
  reopens them on login (`omarchy-perf-session-save`/`-restore`).
- **Drive automount** — fstab + `systemd-automount` (by UUID) for the internal
  NTFS/exFAT data drives (`ntfs-3g`, `nofail`). Carried over from the prior install of this
  same machine; not yet re-verified on this fresh one.
- **zsh + Powerlevel10k** as the login shell (not packaged by Omarchy by default).

## Restore on a fresh Omarchy install

```bash
git clone https://github.com/Rezwoan/omarchy-setup.git
cd omarchy-setup
./install.sh          # copies configs into place (backs up anything overwritten)
```

Then follow the printed **NEXT STEPS** (install packages, oh-my-zsh/p10k, enable the
Performance plugin + its sudo helper, drive automounts, session restore). See `install.sh`
for details.

> The drive UUIDs in `system/fix-drive-mounts.sh` are specific to this machine —
> edit them (`lsblk -f`) before running on different hardware.

## Keeping this repo up to date

After changing configs on the machine, snapshot them back and push in one command:

```bash
./sync.sh "what I changed"     # pull live configs into the repo, then commit & push
./sync.sh                      # dry: pull + regenerate package lists + show git status only
```

`sync.sh` runs a secret scan and aborts before committing if it finds anything sensitive.

## Not included (on purpose)

Secrets and machine state are deliberately excluded: `~/.ssh`, `~/.gnupg`,
`~/.config/gh`, `~/.config/environment.d`, tokens, caches, and transient session
files. This repo is meant to be safe to keep public.
