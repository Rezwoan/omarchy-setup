-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1.25

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
-- vrr = 1 enables variable refresh rate (Adaptive-Sync) whenever the panel
-- supports it — this internal panel's EDID declares a 60-165Hz Adaptive
-- Sync range (confirmed via edid-decode), the same VRR capability Windows
-- calls "Dynamic Refresh Rate". It's a live, automatically-fluctuating rate
-- driven by frame timing, not a fixed mode you select — there's no manual
-- step between 60 and 165 to pick, on either OS.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale, vrr = 1 })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
