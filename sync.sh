#!/bin/bash
# Snapshot the current LIVE configs on this machine back into this repo.
# Reverse of install.sh. Mirrors exactly the curated set this repo tracks.
#
#   ./sync.sh                 # copy live -> repo, regenerate package lists, scan, show git status
#   ./sync.sh "commit msg"    # ...then commit & push with that message
#
# A secret scan runs before any commit and ABORTS if anything sensitive is found.

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
# copy, dereferencing symlinks (-L) so we store content, never a dangling link
cp1() { [[ -e $1 ]] && { install -d "$(dirname "$2")"; cp -aL "$1" "$2"; }; }

say "Pulling live configs into $REPO"

# ---- shell dotfiles ----
for f in .zshrc .bashrc .bash_profile .p10k.zsh; do cp1 "$HOME/$f" "$REPO/shell/$f"; done

# ---- ~/.config/hypr (exclude *.bak) ----
rm -f "$REPO"/config/hypr/*.conf
for f in "$HOME"/.config/hypr/*.conf; do cp1 "$f" "$REPO/config/hypr/$(basename "$f")"; done

# ---- omarchy custom bits ----
cp1 "$HOME/.config/omarchy/extensions/menu.sh" "$REPO/config/omarchy/extensions/menu.sh"
for f in "$HOME"/.config/omarchy/branding/*; do cp1 "$f" "$REPO/config/omarchy/branding/$(basename "$f")"; done
cp1 "$HOME/.config/omarchy/current/theme.name" "$REPO/config/omarchy/current/theme.name"

# ---- terminal / bar / launcher / misc app configs ----
cp1 "$HOME/.config/waybar/config.jsonc"      "$REPO/config/waybar/config.jsonc"
cp1 "$HOME/.config/waybar/style.css"         "$REPO/config/waybar/style.css"
cp1 "$HOME/.config/waybar/net_monitor.sh"    "$REPO/config/waybar/net_monitor.sh"
cp1 "$HOME/.config/walker/config.toml"       "$REPO/config/walker/config.toml"
cp1 "$HOME/.config/ghostty/config"           "$REPO/config/ghostty/config"
cp1 "$HOME/.config/alacritty/alacritty.toml" "$REPO/config/alacritty/alacritty.toml"
cp1 "$HOME/.config/kitty/kitty.conf"         "$REPO/config/kitty/kitty.conf"
# NOTE: ~/.config/mako/config is an omarchy theme-managed symlink — omarchy
# recreates it on `omarchy theme set`, so it is intentionally NOT tracked here.
cp1 "$HOME/.config/swayosd/config.toml"      "$REPO/config/swayosd/config.toml"
cp1 "$HOME/.config/swayosd/style.css"        "$REPO/config/swayosd/style.css"
cp1 "$HOME/.config/fastfetch/config.jsonc"   "$REPO/config/fastfetch/config.jsonc"
cp1 "$HOME/.config/btop/btop.conf"           "$REPO/config/btop/btop.conf"
cp1 "$HOME/.config/kdeglobals"               "$REPO/config/kdeglobals"
cp1 "$HOME/.config/dolphinrc"                "$REPO/config/dolphinrc"

# ---- session-restore units + scripts ----
cp1 "$HOME/.config/systemd/user/omarchy-session-save.service" "$REPO/config/systemd/user/omarchy-session-save.service"
cp1 "$HOME/.config/systemd/user/omarchy-session-save.timer"   "$REPO/config/systemd/user/omarchy-session-save.timer"
cp1 "$HOME/.local/bin/omarchy-session-save"    "$REPO/local-bin/omarchy-session-save"
cp1 "$HOME/.local/bin/omarchy-session-restore" "$REPO/local-bin/omarchy-session-restore"

# ---- package lists ----
pacman -Qqe > "$REPO/packages/pacman-explicit.txt"
pacman -Qqm > "$REPO/packages/aur.txt"

# ---- secret scan (never publish credentials) ----
say "Scanning for secrets"
hits=$(grep -rIinE "(-----BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|sk-[A-Za-z0-9]{32,})" "$REPO" 2>/dev/null | grep -viE "placeholder_text|Enter Password")
if [[ -n $hits ]]; then
  printf '\033[1;31m!! SECRET-LIKE CONTENT FOUND — aborting before commit:\033[0m\n%s\n' "$hits"
  exit 1
fi
say "Clean — no secrets."

cd "$REPO"
git add -A
if [[ -n "${1:-}" ]]; then
  git -c user.name="Rezwoan" -c user.email="frezwoan@gmail.com" commit -m "$1" && git push
  say "Committed & pushed: $1"
else
  say "Staged. Review below, then commit with:  ./sync.sh \"your message\""
  git status --short
fi
