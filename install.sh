#!/bin/bash
# Restore this Omarchy setup on a fresh machine.
#   ./install.sh            # copy configs into place (backs up anything it overwrites)
# Then follow the printed steps for packages + the privileged (sudo) parts.
#
# Targets Omarchy 4.0.1+ (the omarchy-shell / Lua-hypr-config era). See
# README.md's Compatibility section if you're restoring onto an older Omarchy.

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

# ---- ~/.config/ (walks the whole tree: hypr/*.lua, foot, alacritty, kitty,
#      ghostty, the omarchy/plugins/io.github.rezwoan.performance plugin,
#      systemd/user units — whatever's actually under config/) ----
while IFS= read -r -d '' src; do
  rel="${src#$REPO/config/}"
  copy "$src" "$HOME/.config/$rel"
done < <(find "$REPO/config" -type f -print0)
chmod +x "$HOME/.config/omarchy/plugins/io.github.rezwoan.performance/"*.sh 2>/dev/null || true

# ---- ~/.local/bin/ ----
install -d "$HOME/.local/bin"
for f in "$REPO"/local-bin/*; do
  [[ -f $f ]] || continue
  copy "$f" "$HOME/.local/bin/$(basename "$f")"
  chmod +x "$HOME/.local/bin/$(basename "$f")"
done

systemctl --user daemon-reload 2>/dev/null || true

say "Config files restored."
cat <<'NEXT'

────────────────────────── NEXT STEPS ──────────────────────────
1) Install packages you had (review first, it includes AUR):
     sudo pacman -S --needed - < packages/pacman-explicit.txt
     # AUR (needs yay): while read p; do yay -S --needed --noconfirm "$p"; done < packages/aur.txt
   Key extras this setup relies on:
     zsh zsh-completions          (oh-my-zsh + powerlevel10k installed separately, see below)
     ntfs-3g                      (mounts the NTFS data drives, if you use system/)
     envycontrol                  (GPU-mode switching in the Performance plugin)
     linuwu-sense-dkms            (Acer battery limit / fan / keyboard RGB)

2) oh-my-zsh + Powerlevel10k (not packaged; .zshrc expects both):
     git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
     git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
       ~/.oh-my-zsh/custom/themes/powerlevel10k
     chsh -s /usr/bin/zsh
   If a terminal opened in the SAME login session still shows bash after
   chsh, that session's systemd --user manager cached the old shell —
   `systemctl --user set-environment SHELL=/usr/bin/zsh` fixes it live,
   or just log out/in.

3) Enable the Performance plugin and install its privileged helper:
     omarchy plugin enable io.github.rezwoan.performance --section right
     sudo bash ~/.config/omarchy/plugins/io.github.rezwoan.performance/install-helper.sh
   Read that plugin's own README.md for what each piece does. If you have
   an Acer with linuwu-sense-dkms installed but its module never loaded
   (check `lsmod | grep linuwu`), also run:
     sudo bash ~/.config/omarchy/plugins/io.github.rezwoan.performance/enable-keyboard.sh

4) Drive automounts + NTFS fixes (only if this is the original machine —
   edit the UUIDs in system/fix-drive-mounts.sh for a different one):
     sudo bash system/fix-drive-mounts.sh
     sudo bash system/omarchy-ntfs-automount-fix.sh   # only if a drive shows "dirty" and won't mount rw

5) Enable "session restore" (reopen apps on login) from the Performance
   plugin's General tab, or manually:
     touch ~/.config/omarchy/session-restore.enabled
     systemctl --user enable --now omarchy-perf-session-save.timer

6) `omarchy restart shell` (bar/plugins) and `hyprctl reload` (keybinds) —
   or just re-log into Hyprland — so everything picks up.
─────────────────────────────────────────────────────────────────
NEXT
