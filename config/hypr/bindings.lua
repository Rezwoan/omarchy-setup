-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- Physical Predator button -> open PredatorSense. Confirmed via raw evdev
-- capture: this key fires ONLY evdev code 148 (KEY_PROG1) on the internal
-- keyboard device, while Fn+F6 fires on entirely different devices (Video
-- Bus code 225 / Acer WMI hotkeys code 240) and never touches code 148 — so
-- despite an earlier (wrong) assumption that these collided, they're
-- cleanly distinct. code:156 = evdev 148 + 8 (Hyprland's X11 keycode offset).
o.bind("code:156", "PredatorSense", "omarchy-shell io.github.rezwoan.performance toggle")
