-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Restore previously-open apps on login (Performance plugin > Session).
-- No-ops instantly unless ~/.config/omarchy/session-restore.enabled exists.
o.launch_on_start("$HOME/.local/bin/omarchy-perf-session-restore")
