#!/bin/bash
# Restore this Omarchy setup on a fresh machine.
#   ./install.sh            # copy configs into place (backs up anything it overwrites)
# Then follow the printed steps for packages + the privileged (sudo) parts.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.config-backup-$STAMP"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
backup_of() { # back up a path before we overwrite it
  local dest="$1"
  [[ -e $dest ]] || return 0
  local rel="${dest#$HOME/}"
  install -d "$(dirname "$BACKUP/$rel")"
  cp -a "$dest" "$BACKUP/$rel"
}
copy() { # copy src -> dest, backing up first
  local src="$1" dest="$2"
  install -d "$(dirname "$dest")"
  backup_of "$dest"
  cp -a "$src" "$dest"
}

say "Backing up anything overwritten to: $BACKUP"

# ---- shell dotfiles -> ~/ ----
for f in .zshrc .bashrc .bash_profile .p10k.zsh; do
  [[ -f $REPO/shell/$f ]] && copy "$REPO/shell/$f" "$HOME/$f"
done

# ---- ~/.config/ ----
while IFS= read -r -d '' src; do
  rel="${src#$REPO/config/}"
  copy "$src" "$HOME/.config/$rel"
done < <(find "$REPO/config" -type f -print0)

# ---- ~/.local/bin/ ----
install -d "$HOME/.local/bin"
for f in "$REPO"/local-bin/*; do
  [[ -f $f ]] || continue
  copy "$f" "$HOME/.local/bin/$(basename "$f")"
  chmod +x "$HOME/.local/bin/$(basename "$f")"
done

# ---- systemd user units ----
systemctl --user daemon-reload 2>/dev/null || true

say "Config files restored."
cat <<'NEXT'

────────────────────────── NEXT STEPS ──────────────────────────
1) Install packages you had (review first, they include AUR):
     sudo pacman -S --needed - < packages/pacman-explicit.txt
     # AUR (needs yay): while read p; do yay -S --needed --noconfirm "$p"; done < packages/aur.txt
   Key extras this setup relies on:
     dolphin  yazi  power-profiles-daemon  thermald
     envycontrol            (GPU mode switching)
     linuwu-sense-dkms      (Acer battery limit + fan control)
     oh-my-zsh + powerlevel10k   (prompt; install separately if missing)

2) Privileged bits (Performance helper + sudoers + drive automounts):
     sudo bash system/omarchy-perf-install.sh
   (Edit the drive UUIDs in that script first if this is a different machine.)

3) Load the Acer driver (battery limit / fan control):
     sudo bash system/linuwu-load.sh

4) Enable "session restore" (reopen apps on login), optional:
     touch ~/.config/omarchy/session-restore.enabled
     systemctl --user enable --now omarchy-session-save.timer

5) Re-log into Hyprland (or `hyprctl reload`) so keybinds/autostart apply.
   The Performance menu appears in Super+Alt+Space automatically.
─────────────────────────────────────────────────────────────────
NEXT
