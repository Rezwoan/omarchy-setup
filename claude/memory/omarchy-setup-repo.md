---
name: omarchy-setup-repo
description: Public dotfiles/restore repo for this Omarchy machine and what it contains
metadata: 
  node_type: memory
  type: reference
  originSessionId: 97db5c87-566d-47af-9b02-f3292351c511
  modified: 2026-08-02T00:14:30.602Z
---

Public repo: https://github.com/Rezwoan/omarchy-setup (GitHub user **Rezwoan**, gh authed via keyring token — push over HTTPS, not SSH; SSH keys aren't set up).

One-go restore of this Omarchy (Arch+Hyprland) setup. Contains: shell dotfiles (`.zshrc`/oh-my-zsh+powerlevel10k, `.p10k.zsh`), `~/.config` subset (hypr keybindings/autostart/monitors, waybar, walker, ghostty/alacritty/kitty, mako, swayosd, fastfetch, btop, kdeglobals+dolphinrc dark theme), the custom Performance menu (`config/omarchy/extensions/menu.sh`), session-restore scripts+timer, `system/` sudo installers, and `packages/` lists. `./install.sh` restores with backups. Secrets excluded by design. See [[machine-hardware-setup]].
