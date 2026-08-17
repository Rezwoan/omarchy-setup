# AGENTS.md — operating guide for this repo

This is **Rezwoan's personal Omarchy (Arch Linux + Hyprland) setup + one-go restore repo**.
When any coding agent is opened from this repo, read this file first — it is the authoritative
context for the machine, the custom tooling, and the rules for changing anything.
(`CLAUDE.md` carries the same brief for Claude Code; keep the two files in sync.)

> Repo is **private** (`github.com/Rezwoan/omarchy-setup`). It holds personal config and
> assistant memory, so it is intentionally not public. Do not re-publish it publicly without
> being asked.

---

## The machine

- **Acer Predator Helios Neo 16 (PHN16-71, 2023)** — Intel **i5-13500HX** (6 P-cores /
  8 E-cores, 20 threads, Intel hybrid), **NVIDIA RTX 4050** (Optimus/`envycontrol`), dual NVMe.
- OS: **Omarchy** (Arch + Hyprland, launched via **uwsm**), **zsh** shell.
- User: **`reezz-arch`** (uid 1000). **sudo needs a password.**
- Acer platform control via the **`linuwu-sense`** DKMS driver (replaces `acer_wmi`):
  4-zone keyboard RGB (`four_zoned_kb`), 80% battery limit, fan control, `predator_sense`.
- Full hardware/tooling notes: `claude/memory/machine-hardware-setup.md`.

---

## ⚠️ Security & operating rules — always follow

1. **Never handle the sudo password.** Privileged commands must be run **by the user**, not by
   the agent piping a password. When a step needs root, tell the user to run it themselves (in
   Claude Code they can prefix with `!` to run in-session, e.g.
   `!sudo bash system/omarchy-perf-install.sh`). Never echo, pipe, or store the password.
2. **No secrets in this repo — ever.** `sync.sh` runs a secret scan that **aborts the commit**
   if it finds keys/tokens. Never add `~/.ssh`, `~/.gnupg`, `~/.config/gh`,
   `~/.config/environment.d`, credentials, or assistant credential/history/session files. Only the
   curated files under `claude/` are tracked.
3. **All privileged actions go through one root-owned, input-validated helper**:
   `/usr/local/bin/omarchy-perf-helper` (installed by `system/omarchy-perf-install.sh`), run via a
   **scoped NOPASSWD** rule in `/etc/sudoers.d/omarchy-perf`. It accepts only whitelisted
   verbs/values so it can't be coerced into arbitrary commands. Add new privileged features as
   **new verbs in that helper**, never as ad-hoc sudo or a broad sudoers rule.
4. **Never edit `~/.local/share/omarchy/`** (Omarchy's own source — clobbered on update).
   All customization lives in `~/.config/` and this repo. Reading omarchy source is fine.
5. **Confirm before hard-to-reverse / outward-facing actions** (fstab edits, repo visibility,
   force-push, deleting drives). Back up first (both installers snapshot before overwriting).

---

## What lives where

```
install.sh    restore configs onto a fresh machine (backs up anything it overwrites)
sync.sh       snapshot live configs back INTO the repo, secret-scan, commit & push
README.md     human-facing overview
CLAUDE.md     brief for Claude Code
AGENTS.md     ← this file (same brief for other agents)

shell/        ~/.zshrc ~/.bashrc ~/.bash_profile ~/.p10k.zsh
config/       curated ~/.config subset:
              hypr/      keybindings, autostart, monitors, looknfeel, idle/lock
              omarchy/extensions/menu.sh   ← the custom Performance control center
              waybar/    config.jsonc, style.css, net_monitor.sh (network monitor)
              walker/ ghostty/ alacritty/ kitty/ swayosd/ fastfetch/ btop/
              kdeglobals dolphinrc          ← Dolphin "Hackerman" dark theme
              uwsm/env   (XDG_MENU_PREFIX=arch- → Dolphin "Open With" lists apps)
              mimeapps.list                 ← default apps per file type
              systemd/user/ omarchy-session-save.{service,timer}
local-bin/    omarchy-session-save / -restore   ("reopen my apps on login")
system/       omarchy-perf-install.sh   root helper + sudoers + drive fstab entries (sudo)
              fix-drive-mounts.sh       convert drives to boot-mount, no password (sudo)
              linuwu-load.sh            load the Acer driver
packages/     pacman-explicit.txt, aur.txt
claude/       memory/ (auto-memory + notes) and skills/omarchy/SKILL.md
```

---

## Restore on a fresh Omarchy machine

```bash
git clone https://github.com/Rezwoan/omarchy-setup.git && cd omarchy-setup
./install.sh          # copies configs into place, backing up anything overwritten
```
Then follow install.sh's printed **NEXT STEPS**: install packages, run the `system/` sudo
scripts, enable session restore, re-log into Hyprland.
**Drive UUIDs in `system/omarchy-perf-install.sh` are machine-specific — edit them (`lsblk -f`)
before running on different hardware.**

## Save changes back to the repo

```bash
./sync.sh "what I changed"   # pull live config → repo, regenerate package lists, scan, commit, push
./sync.sh                    # dry run: copy + scan + show git status, no commit
```
`sync.sh` copies a **curated set** of files (see the `cp1` lines). If you add a new config that
should be tracked, add a `cp1` line there too.

---

## Custom tooling (what the user relies on)

### Performance control center — `config/omarchy/extensions/menu.sh`
Injected into the Omarchy menu (`Super+Alt+Space → Performance`, also bound to the **Predator key**,
Hyprland `code:156`). Menu items and the helper verb each maps to:

- **⚡ Power Preset** → `omarchy-perf-helper profile <ultra|balanced|performance>` — one-tap bundles.
  **Ultra Power Saver** = E-cores only + turbo off + `max_perf_pct=20` + RAPL 20W + `low-power`
  thermal + EPP `power` + keyboard light off + screen dimmed to ~2%.
  The chosen preset is **persisted** to `/var/lib/omarchy-perf/profile` and re-applied on every boot
  by **`omarchy-perf-restore.service`** (`omarchy-perf-helper apply-saved`).
- Power Profile (power-profiles-daemon), Thermal Profile (`platform_profile`), CPU Turbo,
  CPU Max Freq (`max_perf_pct`), CPU Cores (all / no-HT / E-cores only via CPU hotplug +
  `cpu_core`/`cpu_atom` hybrid maps), Power Limit (RAPL PL1/PL2), Fan Mode, GPU Mode (envycontrol),
  GPU Dynamic Boost (nvidia-powerd), Battery Limit 80% (linuwu-sense), Keyboard Lighting
  (`four_zoned_kb`), Session Restore, Live GPU stats, Battery info.

**Helper verbs** (`/usr/local/bin/omarchy-perf-helper …`): `turbo cpu-cap cpu-cores power-limit epp
platform-profile gpu-runtime nvidia-powerd battery-limit fan kb-zone kb-effect kb-bright brightness
profile apply-saved`. To add a privileged feature: add a validated verb here, redeploy with
`sudo bash system/omarchy-perf-install.sh`, then wire a menu entry in `menu.sh`.

### Waybar network monitor — `config/waybar/net_monitor.sh`
Self-contained, **no daemon, no root, no vnstat**. Shows live ⇣/⇡ speed + persistent
Today/Month/Total usage, accumulated locally in `~/.local/state/waybar-netusage/` (handles counter
resets on reconnect/reboot, flock-guarded). Seeds Month/Total from vnstat once if present. After
editing waybar config: **`omarchy restart waybar`** (waybar does not auto-reload).

### Drives
Five internal NTFS/exFAT volumes mount at `/mnt/{Files,Dev,Study,Windows,NewVolume}` as the user
(uid 1000), **boot-mounted** (via `system/fix-drive-mounts.sh`), `nofail`, no password. NTFS folders
from Windows may carry the read-only DOS attribute (ntfs3 blocks writes) — fix with
`chmod -R u+w /mnt/<drive>`.

### Session restore — `local-bin/omarchy-session-*` + `systemd/user`
Snapshots open windows+workspaces each minute and reopens them on login (toggle in the menu).

---

## Editing conventions

- **Hyprland** (`~/.config/hypr/`): auto-reloads on save, but validate with `hyprctl reload` then
  `hyprctl configerrors`. Rebinding an existing key requires an `unbind` first — tell the user what
  it was bound to. Verify current Hyprland window-rule syntax against the wiki (it changes).
- **Waybar**: `omarchy restart waybar` after any change. **Walker**: `omarchy restart walker`.
  **Terminals**: `omarchy restart terminal`.
- Prefer stock `omarchy <group> <action>` commands (`omarchy commands` lists them). Use
  `omarchy debug --no-sudo --print` for debug info.
- The **omarchy skill** at `claude/skills/omarchy/SKILL.md` is the full reference for desktop/WM
  customization — follow it for any `~/.config/{hypr,waybar,walker,omarchy,…}` work.
- After changing anything on the machine, run `./sync.sh "msg"` to push it back.

## Not for this repo
Study/coursework and one-off tools (e.g. the `runasm` assembly helper for `~/AIUB/…`) are **not**
tracked here — this repo is the OS setup only.
