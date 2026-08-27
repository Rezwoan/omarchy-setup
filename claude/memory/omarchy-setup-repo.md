---
name: omarchy-setup-repo
description: "Public dotfiles/restore repo for this Omarchy machine, rebuilt for the omarchy-shell (v4+) era"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 4d5fc693-0e17-4e1e-bce2-dc9c3fcf855e
  modified: 2026-08-27T09:51:40.852Z
---

Public repo: https://github.com/Rezwoan/omarchy-setup (GitHub user **Rezwoan**, `gh` authed via keyring token, push over HTTPS). Local clone lives at `~/omarchy-setup`.

One-go restore of this Omarchy (Arch+Hyprland) setup, rebuilt 2026-08-27 for Omarchy 4.0.1+'s `omarchy-shell` architecture — the prior version of this repo (visible in git history) targeted the old waybar/walker/mako stack and is now obsolete. Contains: shell dotfiles (`.zshrc`/oh-my-zsh+powerlevel10k), `~/.config/hypr/*.lua` (Lua-based Hyprland config, not the old `.conf` files), `~/.config/foot/foot.ini` (the actual daily terminal now, with a Ctrl+Backspace word-delete fix foot doesn't ship by default), the **Performance plugin** (`config/omarchy/plugins/io.github.rezwoan.performance/` — see [[performance-plugin]]), session-restore-v2 scripts+timer, `system/` drive-automount scripts (carried over from the old repo, NOT yet re-verified on this fresh install), and `packages/` lists. See [[machine-hardware-setup]] for the hardware this targets.

Dropped from the old repo version (dead under omarchy-shell, or not present on this fresh install): waybar, walker, swayosd, mako config, kdeglobals/dolphinrc (Dolphin isn't installed here), fastfetch, btop (was a pristine package default, no actual customization), uwsm/env, omarchy/branding+extensions (stock scaffolding, not user content), the old `claude/skills/omarchy/SKILL.md` backup (stale copy of a skill that omarchy's own package now ships and keeps current on its own).

`install.sh` restores with backups; `sync.sh "msg"` snapshots live config back and pushes (secret scan aborts on anything sensitive).
