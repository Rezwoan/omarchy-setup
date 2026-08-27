---
name: performance-plugin
description: Architecture and hard lessons from building the Performance omarchy-shell plugin
metadata: 
  node_type: memory
  type: project
  originSessionId: 4d5fc693-0e17-4e1e-bce2-dc9c3fcf855e
  modified: 2026-08-27T09:52:29.669Z
---

`~/.config/omarchy/plugins/io.github.rezwoan.performance/` — a bar-widget plugin for `omarchy-shell` (Quickshell/QML) ported from an old walker-menu extension. Two tabs: General (power presets/profile/thermal/CPU/GPU/battery/session) and Keyboard (brightness/color/effects for the Predator's 4-zone RGB). Bar icon and panel header both show the Acer Predator claw logo (`assets/predator-mask.png` — a white-silhouette-on-transparent PNG processed from the official mark), recolored live via `QtQuick.Effects.MultiEffect{colorization}` based on active mode: green=saver, magenta=performance, blue=balanced. See [[omarchy-setup-repo]] and [[machine-hardware-setup]].

Privileged writes go through `sudo -n /usr/local/bin/omarchy-perf-helper <verb>` — a root-owned, verb-whitelisted script installed by the plugin's own `install-helper.sh`, authorized via a sudoers rule scoped to just that binary.

**Hard lessons (re-check these if a future plugin edit "does nothing" again):**
- `bar.shellQuote()` **does not exist**, despite `shell/plugins/bar/README.md` documenting it as a `bar` API. The real function is `Util.shellQuote()` from `qs.Commons`. Calling `root.bar.shellQuote(...)` throws a silent QML TypeError (visible only in `journalctl --user -t omarchy-shell`) — every click did nothing and left no visible error. Always grep the actual shell source (`/usr/share/omarchy/shell/`) for real usages before trusting a plugin README's API list.
- **Editing an already-placed bar-widget plugin's QML does NOT reliably hot-reload**, even though `shell/plugins/README.md` claims file saves auto-reload. `omarchy-shell shell rescanPlugins` didn't help either. Only `omarchy restart shell` (full quickshell process restart, confirmed via a new PID) reliably picks up changes to a widget already sitting in the bar. Verify any layout/logic change with a real restart + `grim` screenshot, not by trusting the log's "Local plugin changed, reloading" line.
- `ButtonGroup` is a plain `Row` — it does **not wrap**. A row with more than ~4 options (e.g. this machine's 5 `platform_profile` choices) silently overflows the panel's right edge. Use a fixed-column `Grid` (like the first-party `monitor` panel's scale-preset row) instead — plain `Flow` was tried first and, unexplained, did not wrap either.
- `qmllint` (`/usr/lib/qt6/bin/qmllint`, not on PATH) can't resolve the `qs.Ui`/`qs.Commons` virtual import scheme at all — even linting a known-good first-party file produces the same cascade of "not found" warnings. That noise is expected; only trust it for real syntax errors (brace/paren mismatches), not import-resolution warnings.
