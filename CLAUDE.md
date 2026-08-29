# CLAUDE.md — operating guide for this repo

This is **Rezwoan's personal Omarchy (Arch Linux + Hyprland) setup + one-go restore repo**.
When Claude Code is opened from this repo, read this file first — it is the authoritative
context for the machine, the custom tooling, and the rules for changing anything.

> **Targets Omarchy 4.0.1+ (`omarchy-shell`)** — waybar/walker/mako are gone, Hyprland config
> is Lua. If a task involves an older Omarchy checkout, treat this file's paths/commands as
> not applicable and check git history for the pre-omarchy-shell version instead.

---

## The machine

- **Acer Predator Helios Neo 16 (PHN16-71)** — Intel **i5-13500HX** (6 P-cores /
  8 E-cores, 20 threads, Intel hybrid), **NVIDIA RTX 4050** (Optimus/`envycontrol`), dual NVMe.
- OS: **Omarchy** (Arch + Hyprland, launched via **uwsm**), **zsh** shell.
- User: **`rex`** (uid 1000). **sudo needs a password.**
- Acer platform control via the **`linuwu-sense`** DKMS driver (replaces `acer_wmi`):
  4-zone keyboard RGB (`four_zoned_kb`), 80% battery limit, fan control.
- Full hardware/tooling notes live in Claude's own memory — see `claude/memory/machine-hardware-setup.md`.

---

## ⚠️ Security & operating rules — always follow

1. **Never handle the sudo password.** Privileged commands must be run **by the user**, not by
   Claude piping a password. When a step needs root, tell the user to run it themselves — in
   Claude Code they can prefix a command with `!` to run it in-session (e.g.
   `!sudo bash config/omarchy/plugins/io.github.rezwoan.performance/setup.sh`).
   Never echo, pipe, or store the password.
2. **No secrets in this repo — ever.** `sync.sh` runs a secret scan that **aborts the commit**
   if it finds keys/tokens. Never add `~/.ssh`, `~/.gnupg`, `~/.config/gh`,
   `~/.config/environment.d`, credentials, or `~/.claude/{.credentials.json,history.jsonl,sessions,projects}`.
   Only the curated `claude/memory/*.md` files are tracked.
3. **All privileged actions for the PredatorSense plugin go through one root-owned,
   input-validated helper**: `/usr/local/bin/omarchy-perf-helper` (installed by the plugin's
   own `setup.sh`), run via a **scoped NOPASSWD** rule in `/etc/sudoers.d/omarchy-perf-helper`.
   It accepts only whitelisted verbs/values so it can't be coerced into arbitrary commands.
   Add new privileged features as **new verbs in that helper**, never as ad-hoc sudo or a
   broad sudoers rule.
4. **Never edit `~/.local/share/omarchy/`** (Omarchy's own source — clobbered on update) or
   `$OMARCHY_PATH/shell/plugins/` (first-party shell plugins — clobbered on update). All
   customization lives in `~/.config/` (this repo) or `~/.config/omarchy/plugins/<id>/`
   (third-party plugins). Reading Omarchy/shell source is fine and often necessary — plugin
   development means checking real component behavior against `/usr/share/omarchy/shell/`,
   not trusting a README's claimed API (see the `bar.shellQuote` lesson in
   `claude/memory/performance-plugin.md`).
5. **Confirm before hard-to-reverse / outward-facing actions** (fstab edits, repo visibility,
   force-push, deleting drives). Back up first (`install.sh` snapshots before overwriting).

---

## What lives where

```
install.sh    restore configs onto a fresh machine (backs up anything it overwrites)
sync.sh       snapshot live configs back INTO the repo, secret-scan, commit & push
README.md     human-facing overview
CLAUDE.md     ← this file, for Claude Code
AGENTS.md     ← same brief for any other coding agent (keep the two in sync)

shell/        ~/.zshrc ~/.bashrc ~/.bash_profile ~/.p10k.zsh
config/       curated ~/.config subset:
              hypr/                Lua config — bindings, monitors, input, look&feel, autostart
              foot/                actual daily terminal (font, Ctrl+Backspace fix)
              alacritty/ kitty/ ghostty/   kept for reference, not currently installed
              omarchy/plugins/io.github.rezwoan.performance/   ← the PredatorSense plugin (own README)
              systemd/user/        omarchy-perf-session-save.{service,timer}
local-bin/    omarchy-perf-session-save / -restore   ("reopen my apps on login")
system/       fix-drive-mounts.sh, omarchy-ntfs-automount-fix.sh   (drive automount; sudo)
packages/     pacman-explicit.txt, aur.txt
claude/       memory/ (Claude Code's auto-memory about this machine and repo)
```

---

## Restore on a fresh Omarchy machine

```bash
git clone https://github.com/Rezwoan/omarchy-setup.git && cd omarchy-setup
./install.sh          # copies configs into place, backing up anything overwritten
```
Then follow `install.sh`'s printed **NEXT STEPS**: install packages, oh-my-zsh/p10k, enable the
PredatorSense plugin + its sudo helper (one-time "Enable privileged controls" click, no terminal),
drive automounts, session restore.
**Drive UUIDs in `system/fix-drive-mounts.sh` are machine-specific — edit them (`lsblk -f`)
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

### PredatorSense plugin — `config/omarchy/plugins/io.github.rezwoan.performance/`
A real `omarchy-shell` bar-widget plugin (id `io.github.rezwoan.performance`, display name
"PredatorSense"), not a menu extension — those don't exist under `omarchy-shell`. Sits in the
bar (Predator claw logo, recolored per active mode: green/saver, magenta/performance,
blue/balanced). One unified PROFILE selector — Ultra Saver / Saver / Balanced / Performance /
Ultra Performance / Custom (Custom is a passive indicator, not a real preset — it lights up
whenever a raw control has been hand-tuned since the last named preset was applied) — with the
old separate Power Profile + Thermal Profile controls tucked behind a small gear (⚙) button
next to the GPU-stats/battery-info icons, plus CPU/GPU/battery/fan/session controls and a
Keyboard tab (4-zone RGB). See that directory's own `README.md` for the full control list and
the install/enable steps.

**Physical Predator button opens it** (`~/.config/hypr/bindings.lua`, `code:156`) — confirmed via
raw evdev capture that this key fires *only* evdev code 148 (KEY_PROG1) on the internal keyboard
device, while Fn+F6 fires on entirely different devices (Video Bus code 225 / Acer WMI hotkeys
code 240) and never touches code 148. An earlier assumption that these collided was wrong;
`hyprctl binds -j` doesn't decode `code:`-syntax binds in its `key`/`keycode` fields (shows empty
for ALL code-based binds, even known-working stock ones), which is what caused that confusion.

Privileged writes route through `/usr/local/bin/omarchy-perf-helper <verb> <args>`, installed
by the plugin's `setup.sh`, authorized via a **scoped NOPASSWD sudoers rule**
(`/etc/sudoers.d/omarchy-perf-helper`) — one real password prompt ever (the setup button),
then every control uses `sudo -n` and never prompts again. Power presets persist to
`/var/lib/omarchy-perf/profile` and reapply on boot via `omarchy-perf-restore.service`.
Keyboard RGB + battery limit + fan need `linuwu-sense-dkms` with its module actually loaded
(`enable-keyboard.sh` handles the `acer_wmi` → `linuwu_sense` hot-swap) — fan writes must be
`"cpu,gpu"` (e.g. `"50,50"`), a bare number is silently rejected by the driver. GPU mode
switching needs `envycontrol` (AUR) — installed on this machine.

### Drives
NTFS/exFAT volumes mount at `/mnt/{Files,Dev,Study,Windows,NewVolume}` as the user
(uid 1000), boot-mounted, `nofail`, no password (`system/fix-drive-mounts.sh`). NTFS folders
from Windows may carry the read-only DOS attribute (ntfs3/ntfs-3g blocks writes) — fix with
`chmod -R u+w /mnt/<drive>`.

### Session restore — `local-bin/omarchy-perf-session-*` + `systemd/user`
Snapshots open windows+workspaces each minute and reopens them on login (toggle from the
PredatorSense plugin's General tab, SESSION section).

---

## Editing conventions

- **Hyprland** (`~/.config/hypr/*.lua`): validate with `hyprctl reload` then `hyprctl
  configerrors`. Rebinding an existing key requires `hl.unbind(...)` first. Verify current
  Hyprland/Lua binding syntax against `/usr/share/omarchy/default/hypr/helpers.lua` (`o.bind`
  etc.) — it isn't the old `.conf` `bind=` syntax anymore.
- **omarchy-shell plugins**: edit under `~/.config/omarchy/plugins/<id>/`, never under
  `$OMARCHY_PATH/shell/plugins/`. A saved file is *supposed* to hot-reload
  (`shell/plugins/README.md` claims this), but in practice an already-placed bar-widget did
  not pick up changes reliably — verify any real change with `omarchy restart shell` (confirm
  a new quickshell PID) and a `grim` screenshot, not just the reload log line.
- Prefer stock `omarchy <group> <action>` commands (`omarchy commands` lists them). Use
  `omarchy debug --no-sudo --print` for debug info.
- The **omarchy skill** bundled with Claude Code (and Omarchy's own package) is the reference
  for desktop/WM customization — no local copy is tracked in this repo anymore, since it comes
  from the installed `omarchy` package and Claude Code itself, not from user customization.
- After changing anything on the machine, run `./sync.sh "msg"` to push it back.

## Not for this repo
Study/coursework and one-off tools are **not** tracked here — this repo is the OS setup only.
