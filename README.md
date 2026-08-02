# omarchy-setup

My personal [Omarchy](https://omarchy.org/) (Arch + Hyprland) configuration — everything I customized, in one place, so a fresh install can be restored in one go.

Machine: **Acer Predator Helios Neo 16 (PHN16-71)** · i5-13500HX · RTX 4050 · dual NVMe.

## What's inside

```
shell/     ~/.zshrc ~/.bashrc ~/.bash_profile ~/.p10k.zsh   (aliases, prompt)
config/    ~/.config subset:
           hypr/         keybindings, autostart, monitors, look & feel, idle/lock
           omarchy/      extensions/menu.sh  ← the custom Performance control center
           waybar/ walker/ ghostty/ alacritty/ kitty/ swayosd/ fastfetch/ btop/
           kdeglobals dolphinrc               ← Dolphin "Hackerman" dark theme + settings
           systemd/user/ omarchy-session-save.{service,timer}
local-bin/ omarchy-session-save / -restore    ← "reopen my apps on login"
system/    omarchy-perf-install.sh            ← power helper + sudoers + drive automounts (sudo)
           linuwu-load.sh                     ← load Acer driver for battery limit / fan control
packages/  pacman-explicit.txt, aur.txt       ← package lists to reinstall
```

## Highlights

- **Performance control center** — a native entry injected into the Omarchy menu
  (`Super+Alt+Space → Performance`) via `~/.config/omarchy/extensions/menu.sh`.
  Controls: power profile, thermal profile, CPU turbo, **fan mode**, GPU mode
  (envycontrol), GPU dynamic boost, **Acer 80% battery limit** (Linuwu-Sense),
  session-restore toggle, live GPU stats, battery info. Privileged actions go
  through a small root-owned, input-validated helper with a scoped NOPASSWD rule.
- **Session restore** — snapshots open windows + their workspaces every minute and
  reopens them on login.
- **Drive automount** — fstab + `systemd-automount` (by UUID) for the internal
  NTFS/exFAT data drives (`ntfs3`, `nofail`).
- **Dolphin dark theme** matched to the Omarchy "Hackerman" palette.

## Restore on a fresh Omarchy install

```bash
git clone https://github.com/Rezwoan/omarchy-setup.git
cd omarchy-setup
./install.sh          # copies configs into place (backs up anything overwritten)
```

Then follow the printed **NEXT STEPS** (install packages, run the `system/` sudo
scripts, enable session restore, re-log into Hyprland). See `install.sh` for details.

> The drive UUIDs in `system/omarchy-perf-install.sh` are specific to my machine —
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
