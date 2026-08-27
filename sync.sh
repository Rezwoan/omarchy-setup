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

# ---- ~/.config/hypr (Lua config; drop stale generated .conf if any) ----
rm -f "$REPO"/config/hypr/*.conf
for f in autostart.lua bindings.lua hyprland.lua input.lua looknfeel.lua monitors.lua .luarc.json; do
  cp1 "$HOME/.config/hypr/$f" "$REPO/config/hypr/$f"
done
cp1 "$HOME/.config/hypr/hyprsunset.conf" "$REPO/config/hypr/hyprsunset.conf"
cp1 "$HOME/.config/hypr/xdph.conf"       "$REPO/config/hypr/xdph.conf"

# ---- terminals ----
cp1 "$HOME/.config/foot/foot.ini"            "$REPO/config/foot/foot.ini"
cp1 "$HOME/.config/alacritty/alacritty.toml" "$REPO/config/alacritty/alacritty.toml"
cp1 "$HOME/.config/kitty/kitty.conf"         "$REPO/config/kitty/kitty.conf"
cp1 "$HOME/.config/ghostty/config"           "$REPO/config/ghostty/config"

# ---- the Performance plugin, in full ----
rm -rf "$REPO/config/omarchy/plugins/io.github.rezwoan.performance"
if [[ -d "$HOME/.config/omarchy/plugins/io.github.rezwoan.performance" ]]; then
  install -d "$REPO/config/omarchy/plugins"
  cp -aL "$HOME/.config/omarchy/plugins/io.github.rezwoan.performance" \
         "$REPO/config/omarchy/plugins/io.github.rezwoan.performance"
fi

# ---- session-restore-v2 units + scripts ----
cp1 "$HOME/.config/systemd/user/omarchy-perf-session-save.service" "$REPO/config/systemd/user/omarchy-perf-session-save.service"
cp1 "$HOME/.config/systemd/user/omarchy-perf-session-save.timer"   "$REPO/config/systemd/user/omarchy-perf-session-save.timer"
cp1 "$HOME/.local/bin/omarchy-perf-session-save"    "$REPO/local-bin/omarchy-perf-session-save"
cp1 "$HOME/.local/bin/omarchy-perf-session-restore" "$REPO/local-bin/omarchy-perf-session-restore"

# ---- Claude Code: auto-memory (personal assistant context for this repo) ----
CLAUDE_MEM="$HOME/.claude/projects/-home-$(basename "$HOME")/memory"
for f in MEMORY.md omarchy-setup-repo.md machine-hardware-setup.md performance-plugin.md feedback-explicit-commands.md; do
  cp1 "$CLAUDE_MEM/$f" "$REPO/claude/memory/$f"
done

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
