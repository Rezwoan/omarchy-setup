---
name: omarchy-setup-repo
description: Private dotfiles/restore repo for this Omarchy machine and what it contains
metadata: 
  node_type: memory
  type: reference
  originSessionId: 97db5c87-566d-47af-9b02-f3292351c511
  modified: 2026-08-17T03:23:09.139Z
---

**Private** repo: https://github.com/Rezwoan/omarchy-setup (GitHub user **Rezwoan**, gh authed via keyring token — push over HTTPS, not SSH; SSH keys aren't set up). Made private 2026-08-17 when Claude memory was added; flip back with `gh repo edit Rezwoan/omarchy-setup --visibility public --accept-visibility-change-consequences`.

One-go restore of this Omarchy (Arch+Hyprland) setup. Contains: shell dotfiles (`.zshrc`/oh-my-zsh+powerlevel10k, `.p10k.zsh`), `~/.config` subset (hypr keybindings/autostart/monitors, waybar, walker, ghostty/alacritty/kitty, mako, swayosd, fastfetch, btop, kdeglobals+dolphinrc dark theme), the custom Performance menu (`config/omarchy/extensions/menu.sh`), session-restore scripts+timer, `system/` sudo installers, `packages/` lists, and `claude/` (auto-memory + omarchy SKILL.md). Root `CLAUDE.md` (+ `AGENTS.md` symlink) briefs Claude on a fresh clone. `./install.sh` restores with backups; `./sync.sh "msg"` snapshots live config back and pushes (secret scan aborts on anything sensitive). Secrets excluded by design. See [[machine-hardware-setup]].
