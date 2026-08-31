import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// PredatorSense control center for the Acer Predator laptop: a single power
// profile selector, CPU/fan/battery controls, session restore, and
// keyboard-RGB. Ported from an old walker-menu extension
// (omarchy/extensions/menu.sh) into a proper bar-widget plugin for the
// omarchy-shell era.
//
// Privileged writes go through /usr/local/bin/omarchy-perf-helper, a
// root-owned, verb-whitelisted script authorized via a scoped NOPASSWD
// sudoers rule installed once by setup.sh (see README.md). One click ever —
// the "Enable privileged controls" button — for a real auth prompt; every
// control after that runs silently via `sudo -n`, no popups. Every control
// here degrades gracefully when the helper — or the optional
// linuwu-sense-dkms backend — isn't installed: read-only status still shows,
// writes just no-op.
Panel {
  id: root
  moduleName: "io.github.rezwoan.performance"
  ipcTarget: "io.github.rezwoan.performance"

  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.rezwoan.performance"
  property var status: Model.parseStatus("")
  property string activeTab: "general"
  property bool showAdvanced: false

  // Bare hex (no #) for the active mode's color — named power preset wins
  // when one is active (it's the deliberate, one-tap choice); otherwise
  // fall back to the power-profile. Empty string means neither maps to a
  // color (fully "custom"): callers each pick their own fallback for that.
  function modeHex() {
    var key = root.status.preset || root.status.profile
    if (key === "power-saver") key = "saver" // powerprofilesctl's own name for the same color bucket
    return Model.presetColorHex(key)
  }

  // Predator-logo tint: theme foreground is the fallback when modeHex() is
  // empty, so the logo still reflects something even in "custom" state.
  // Thermal danger overrides whatever the preset/profile color would be —
  // same priority order as a hot GPU overriding a "performance" tint in
  // other laptop-control panels: the number that could actually hurt the
  // hardware always wins the icon's attention over which preset is active.
  function modeColor() {
    if (root.status.cpuTemp >= 90 || root.status.gpuTemp >= 90) return "#ff4444"
    var hex = root.modeHex()
    return hex ? ("#" + hex) : (root.bar ? root.bar.foreground : Color.foreground)
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  // Fire-and-forget a privileged verb through the helper, then refresh once
  // the write has had time to land. `bar.run` is the shared fire-and-forget
  // exec every bar widget uses. `sudo -n` is non-interactive: once setup.sh
  // has installed the scoped NOPASSWD rule this runs silently every time,
  // no dialog at all; if that rule isn't installed yet it just fails closed
  // (no popup, no hang) and the write no-ops until the setup banner's button
  // is clicked.
  function runPrivileged() {
    var args = Array.prototype.slice.call(arguments)
    var quoted = args.map(function(a) { return Util.shellQuote(String(a)) })
    root.bar.run("sudo -n /usr/local/bin/omarchy-perf-helper " + quoted.join(" "))
    refreshTimer.restart()
  }

  function runPlain(cmd) {
    root.bar.run(cmd)
    refreshTimer.restart()
  }

  // One-time privileged setup, triggered from the UI — never a terminal.
  // This is the ONLY action in the whole plugin that ever shows a real auth
  // prompt: pkexec here uses the generic exec action (no specific policy
  // exists yet, since installing it is exactly this script's job). After it
  // completes once, every other control uses `sudo -n` above and never
  // prompts again.
  function runSetup() {
    root.bar.run("pkexec bash " + Util.shellQuote(root.pluginDir + "/setup.sh")
      + " && omarchy-notification-send -u low " + Util.shellQuote("PredatorSense")
      + " " + Util.shellQuote("Privileged controls enabled"))
    refreshTimer.restart()
  }

  function runEnableKeyboard() {
    root.bar.run("pkexec bash " + Util.shellQuote(root.pluginDir + "/enable-keyboard.sh")
      + " && omarchy-notification-send -u low " + Util.shellQuote("PredatorSense")
      + " " + Util.shellQuote("Keyboard RGB driver loaded"))
    refreshTimer.restart()
  }

  function setPreset(name) {
    runPrivileged("profile", name, root.status.themeHex)
  }

  function setPowerProfile(name) {
    runPlain("powerprofilesctl set " + Util.shellQuote(name))
    runPrivileged("turbo", name === "power-saver" ? "off" : "on")
  }

  function setThermal(name) { runPrivileged("platform-profile", name) }
  function toggleTurbo() { runPrivileged("turbo", root.status.turbo === "on" ? "off" : "on") }
  function setCores(name) { runPrivileged("cpu-cores", name) }
  function setCpuCap(pct) { runPrivileged("cpu-cap", pct) }

  function setPowerLimit(pl1) {
    var pl2 = pl1 >= 65 ? 157 : Math.round(pl1 * 1.35)
    runPrivileged("power-limit", pl1, pl2)
  }

  function setGpuMode(mode) {
    if (mode === root.status.gpu) return
    runPlain("pkexec envycontrol -s " + Util.shellQuote(mode)
      + " && omarchy-notification-send -u low " + Util.shellQuote("GPU Mode")
      + " " + Util.shellQuote("Switched to " + mode + " — reboot required"))
  }

  function toggleGpuBoost() { runPrivileged("nvidia-powerd", root.status.powerd === "active" ? "off" : "on") }

  // Refresh rate needs no privilege at all. `hyprctl keyword monitor` is
  // rejected outright on this Lua-parsed Hyprland config ("keyword can't
  // work with non-legacy parsers") — same story as the physical Predator-key
  // bind — so this goes through `hyprctl eval` + the `hl.monitor()` Lua API
  // instead. `position = "auto"` is the only value that applies cleanly
  // (an explicit "x,y" string errors on the position field); fine for a
  // single internal panel, and matches what re-lays-out on a mode change
  // anyway.
  // After applying, if hyprmoncfg (github.com/crmne/hyprmoncfg) is installed
  // and actively managing monitor config, it re-applies its saved profile a
  // few seconds later — silently reverting a plain hl.monitor call. Detect
  // it and follow up with `hyprmoncfg save <profile>` so the change sticks;
  // a complete no-op (not even the probe fails loudly) when it's absent.
  function setRefreshRate(hz) {
    var mon = root.status.refreshMonitor
    var res = root.status.refreshRes
    if (!mon || !res) return
    var rate = Number(hz)
    if (!isFinite(rate) || rate <= 0) return
    var scale = root.status.refreshScale || "1"
    var lua = 'hl.monitor({ output = "' + mon + '", mode = "' + res + '@' + rate.toFixed(2)
      + '", position = "auto", scale = ' + scale + ' })'
    var script = "hyprctl eval " + Util.shellQuote(lua) + "; "
      + "if command -v hyprmoncfg >/dev/null 2>&1; then "
      + "p=$(hyprmoncfg status --json 2>/dev/null | jq -r 'if (.daemon.running==true) then (.active_profile.name // \"\") else \"\" end' 2>/dev/null); "
      + "[ -n \"$p\" ] && hyprmoncfg save \"$p\" >/dev/null 2>&1; fi"
    runPlain("bash -c " + Util.shellQuote(script))
  }
  function toggleBatteryLimit() { runPrivileged("battery-limit", root.status.battlimit === "on" ? "off" : "on") }
  function setFan(mode) { runPrivileged("fan", mode) }
  function setKbBrightness(pct) { runPrivileged("kb-bright", pct) }
  function setKbColor(hex) { runPrivileged("kb-zone", hex, "100") }
  function setKbEffect(mode) { runPrivileged("kb-effect", mode, "5", "100", "1", root.status.themeHex) }
  // Stateful, unlike a one-shot color pick: while linked, the keyboard color
  // is re-applied by the helper on every future profile change too (see
  // setup.sh's kb-link verb). Picking any plain color swatch or effect
  // clears this server-side, which is why those don't need a matching
  // client-side call here. Clicking an already-active link button toggles
  // it back off.
  function setKbLink(mode) {
    if (root.status.kbLink === mode) {
      runPrivileged("kb-link", "off")
    } else {
      runPrivileged("kb-link", mode, root.status.themeHex)
    }
  }

  // Session restore lives entirely in the user's own home dir (a flag file
  // + a systemd --user timer that snapshots open windows, restored on next
  // login by hypr/autostart.lua) — no root needed at all.
  function toggleSessionRestore() {
    var flag = Quickshell.env("HOME") + "/.config/omarchy/session-restore.enabled"
    if (root.status.sessionEnabled) {
      runPlain("rm -f " + Util.shellQuote(flag))
    } else {
      runPlain("touch " + Util.shellQuote(flag)
        + " && omarchy-notification-send -u low " + Util.shellQuote("PredatorSense")
        + " " + Util.shellQuote("Session restore enabled — your open apps will reopen next login"))
    }
  }

  // Fan curve: entirely unprivileged on this side — installing/toggling a
  // *user* systemd unit needs no root at all. Only the daemon's own periodic
  // `fan <pct>` calls go through the existing sudo -n helper path, so this
  // adds no new privileged surface (see fancurve.sh/omarchy-perf-fancurve.service).
  function setFanCurveEnabled(on) {
    var home = Quickshell.env("HOME")
    if (on) {
      var src = Util.shellQuote(root.pluginDir + "/omarchy-perf-fancurve.service")
      var destDir = Util.shellQuote(home + "/.config/systemd/user")
      var dest = Util.shellQuote(home + "/.config/systemd/user/omarchy-perf-fancurve.service")
      runPlain("install -d " + destDir + " && cp -f " + src + " " + dest
        + " && systemctl --user daemon-reload && systemctl --user enable --now omarchy-perf-fancurve.service")
    } else {
      runPlain("systemctl --user disable --now omarchy-perf-fancurve.service")
    }
  }

  function saveFanCurve(points) {
    var home = Quickshell.env("HOME")
    runPlain("install -d " + Util.shellQuote(home + "/.config/omarchy")
      + " && printf '%s' " + Util.shellQuote(JSON.stringify(points))
      + " > " + Util.shellQuote(home + "/.config/omarchy/predatorsense-fancurve.json"))
  }

  function openLiveGpuStats() {
    root.bar.run("uwsm-app -- xdg-terminal-exec watch -n1 nvidia-smi")
  }

  function sendBatteryInfo() {
    root.bar.run("bash -c 'info=$(upower -i \"$(upower -e 2>/dev/null | grep -m1 BAT)\" 2>/dev/null | grep -E \"state|percentage|energy-rate|time to|capacity:\" | sed \"s/^ *//\"); omarchy-notification-send -u low \"Battery\" \"${info:-No battery info available}\"'")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: if (opened) refresh()

  Timer {
    interval: root.setting("refreshIntervalSec", 5) * 1000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshTimer
    interval: 450
    repeat: false
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.rezwoan.performance/status.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.status = Model.parseStatus(text)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: predatorLogoComponent
    tooltipText: {
      var t = root.status.preset ? Model.presetLabel(root.status.preset) : "PredatorSense"
      if (root.status.cpuTemp >= 0) t += "\nCPU  " + Model.fmtTemp(root.status.cpuTemp)
      if (root.status.gpuTemp >= 0) t += "\nGPU  " + Model.fmtTemp(root.status.gpuTemp)
      if (root.status.battpct) t += "\nBatt " + root.status.battpct + "%"
      return t
    }
    onPressed: function(b) { root.toggle() }
  }

  // Predator claw mark, recolored per active mode via MultiEffect
  // (colorization tints the mask's opaque pixels; alpha comes from the PNG).
  Component {
    id: predatorLogoComponent
    Item {
      anchors.fill: parent
      Image {
        id: predatorGlyph
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        source: Qt.resolvedUrl("assets/predator-mask.png")
        visible: false
        layer.enabled: true
      }
      MultiEffect {
        anchors.fill: predatorGlyph
        source: predatorGlyph
        colorization: 1.0
        colorizationColor: root.modeColor()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.height, heroLabels.implicitHeight, heroActions.implicitHeight)

            Item {
              id: heroIcon
              width: Style.font.display
              height: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Image {
                id: heroGlyph
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                source: Qt.resolvedUrl("assets/predator-mask.png")
                visible: false
                layer.enabled: true
              }
              MultiEffect {
                anchors.fill: heroGlyph
                source: heroGlyph
                colorization: 1.0
                colorizationColor: root.modeColor()
              }
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: heroActions.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "PredatorSense"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.status.preset ? Model.presetLabel(root.status.preset) : "CUSTOM"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: heroActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              PanelActionButton {
                iconText: "󰋚"
                tooltipText: "Live GPU stats"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.openLiveGpuStats()
              }
              PanelActionButton {
                iconText: "󰁹"
                tooltipText: "Battery info"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.sendBatteryInfo()
              }
              PanelActionButton {
                iconText: "󰒓"
                tooltipText: "Advanced: power & thermal profile"
                foreground: root.showAdvanced ? Color.accent : root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.showAdvanced = !root.showAdvanced
              }
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                onClicked: root.refresh()
              }
            }
          }

          // ---------- Tabs ----------
          ButtonGroup {
            width: parent.width
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            value: root.activeTab
            options: [
              { value: "general", label: "General" },
              { value: "telemetry", label: "Telemetry" },
              { value: "keyboard", label: "Keyboard" }
            ]
            onChanged: function(v) { root.activeTab = v }
          }

          // ---------- Setup banner ----------
          BorderSurface {
            visible: !root.status.helperOk
            width: parent.width
            implicitHeight: setupColumn.implicitHeight + Style.space(16)
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.05)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14), 1)

            Column {
              id: setupColumn
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              spacing: Style.space(8)

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Power/CPU/battery/keyboard controls are read-only until privileged access is enabled. One click, one password prompt — never again after this."
                color: Qt.darker(root.bar.foreground, 1.3)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Button {
                text: "Enable privileged controls"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.sm
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                onClicked: root.runSetup()
              }
            }
          }

          // ==================== General tab ====================
          Column {
            id: generalTab
            visible: root.activeTab === "general"
            width: parent.width
            spacing: Style.space(14)

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Profile ----------
          // One unified selector replaces the old separate power-preset /
          // power-profile / thermal-profile rows (they all fought over the
          // same "how hard should this laptop run" question). CUSTOM isn't
          // a real preset — it's a passive indicator, shown selected
          // whenever a raw control below (or in the Advanced popover) has
          // been changed since the last named preset was applied.
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader { text: "PROFILE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Grid {
              id: profileGrid
              readonly property var options: [
                { value: "ultra", label: "Ultra Saver" },
                { value: "saver", label: "Saver" },
                { value: "balanced", label: "Balanced" },
                { value: "performance", label: "Performance" },
                { value: "ultra-performance", label: "Ultra Performance" },
                { value: "custom", label: "Custom" }
              ]
              width: parent.width
              columns: 2
              columnSpacing: Style.spacing.xs
              rowSpacing: Style.spacing.xs

              Repeater {
                model: profileGrid.options
                Button {
                  required property var modelData
                  readonly property string presetHex: Model.presetColorHex(modelData.value)
                  width: (profileGrid.width - profileGrid.columnSpacing) / 2
                  text: modelData.label
                  iconText: Model.presetIcon(modelData.value)
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  accent: presetHex ? ("#" + presetHex) : Color.accent
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  enabled: modelData.value !== "custom"
                  selected: modelData.value === "custom"
                    ? !root.status.preset
                    : root.status.preset === modelData.value
                  onClicked: root.setPreset(modelData.value)
                }
              }
            }
          }

          // ---------- Advanced (power profile + thermal profile) ----------
          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: root.showAdvanced

            PanelSeparator { foreground: root.bar.foreground }

            Column {
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader { text: "POWER PROFILE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                value: root.status.profile
                options: [
                  { value: "power-saver", label: "Saver" },
                  { value: "balanced", label: "Balanced" },
                  { value: "performance", label: "Performance" }
                ]
                onChanged: function(v) { root.setPowerProfile(v) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: thermalGroup.options.length > 0

              PanelSectionHeader { text: "THERMAL PROFILE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

              // A fixed 3-column Grid rather than ButtonGroup (which is a
              // single non-wrapping Row) — this machine's platform_profile
              // exposes 5 choices, too many to fit one row at readable width.
              Grid {
                id: thermalGroup
                readonly property var options: Model.thermalOptions(root.status.thermalChoices)
                width: parent.width
                columns: 3
                columnSpacing: Style.spacing.xs
                rowSpacing: Style.spacing.xs

                Repeater {
                  model: thermalGroup.options
                  Button {
                    required property var modelData
                    text: modelData.label
                    fontSize: Style.font.bodySmall
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    horizontalPadding: Style.spacing.sm
                    verticalPadding: Style.spacing.controlPaddingY
                    bordered: true
                    selected: root.status.thermal === modelData.value
                    onClicked: root.setThermal(modelData.value)
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- CPU ----------
          Column {
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader { text: "CPU"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Toggle {
              width: parent.width
              label: "Turbo boost"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.status.turbo === "on"
              onClicked: root.toggleTurbo()
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              Text {
                text: "CORES"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: root.status.cores
                options: [
                  { value: "all", label: "All" },
                  { value: "no-smt", label: "No hyperthreading" },
                  { value: "ecore", label: "E-cores only" }
                ]
                onChanged: function(v) { root.setCores(v) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              Text {
                text: "MAX FREQUENCY"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: String(root.status.cpucap)
                options: [
                  { value: "100", label: "100%" },
                  { value: "75", label: "75%" },
                  { value: "50", label: "50%" },
                  { value: "40", label: "40%" }
                ]
                onChanged: function(v) { root.setCpuCap(parseInt(v, 10)) }
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              Text {
                text: "POWER LIMIT"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: String(root.status.powerlimit)
                options: [
                  { value: "65", label: "Full (65W)" },
                  { value: "45", label: "45W" },
                  { value: "35", label: "35W" },
                  { value: "25", label: "25W" }
                ]
                onChanged: function(v) { root.setPowerLimit(parseInt(v, 10)) }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- GPU ----------
          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "GPU"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              visible: root.status.gpuAvailable

              Text {
                text: "MODE · REBOOT REQUIRED"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: root.status.gpu
                options: [
                  { value: "integrated", label: "Integrated" },
                  { value: "hybrid", label: "Hybrid" },
                  { value: "nvidia", label: "Nvidia" }
                ]
                onChanged: function(v) { root.setGpuMode(v) }
              }
            }

            Text {
              visible: !root.status.gpuAvailable
              width: parent.width
              wrapMode: Text.WordWrap
              text: "GPU-mode switching needs envycontrol (AUR) — not installed."
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Toggle {
              width: parent.width
              label: "Dynamic boost"
              description: "nvidia-powerd — lets the dGPU draw more power under load"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.status.powerd === "active"
              onClicked: root.toggleGpuBoost()
            }
          }

          PanelSeparator {
            foreground: root.bar.foreground
            visible: Model.refreshRates(root.status.refreshOptions).length > 1
          }

          // ---------- Display ----------
          Column {
            id: displaySection
            width: parent.width
            spacing: Style.space(10)
            visible: Model.refreshRates(root.status.refreshOptions).length > 1

            readonly property var rates: Model.refreshRates(root.status.refreshOptions)
            readonly property int currentIndex: Math.max(0, rates.indexOf(Number(root.status.refreshCurrent)))

            PanelSectionHeader { text: "DISPLAY"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Column {
              width: parent.width
              spacing: Style.spacing.sm

              Item {
                width: parent.width
                implicitHeight: Math.max(rateHeader.implicitHeight, rateValue.implicitHeight)

                Text {
                  id: rateHeader
                  text: "REFRESH RATE · " + root.status.refreshMonitor.toUpperCase()
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  id: rateValue
                  text: (displaySection.rates[Math.round(refreshSlider.liveValue)] || root.status.refreshCurrent) + " Hz"
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              PanelSlider {
                id: refreshSlider
                bar: root.bar
                width: parent.width
                minimum: 0
                maximum: Math.max(0, displaySection.rates.length - 1)
                step: 1
                integer: true
                tickCount: displaySection.rates.length
                value: displaySection.currentIndex
                onReleased: function(v) {
                  var rate = displaySection.rates[Math.round(v)]
                  if (rate !== undefined) root.setRefreshRate(rate)
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Battery ----------
          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Math.max(battHeader.implicitHeight, battValue.implicitHeight)
              PanelSectionHeader {
                id: battHeader
                text: "BATTERY"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: battValue
                text: (root.status.battpct || "—") + "% · " + (root.status.battstatus || "")
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Toggle {
              width: parent.width
              visible: root.status.battlimit !== "n/a"
              label: "80% charge limit"
              description: "Caps charging around 80% to slow long-term battery wear"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.status.battlimit === "on"
              onClicked: root.toggleBatteryLimit()
            }

            Text {
              visible: root.status.battlimit === "n/a"
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Charge limit + fan control need linuwu-sense-dkms (AUR) — not installed."
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              visible: root.status.fan !== "n/a"
              Text {
                text: "FAN"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              ButtonGroup {
                width: parent.width
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                value: root.status.fan
                options: [
                  { value: "auto", label: "Auto" },
                  { value: "50", label: "50%" },
                  { value: "70", label: "70%" },
                  { value: "100", label: "Max" }
                ]
                onChanged: function(v) { root.setFan(v) }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Session ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader { text: "SESSION"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Toggle {
              width: parent.width
              label: "Remember open apps"
              description: "Reopens your apps + workspaces on next login"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.status.sessionEnabled
              onClicked: root.toggleSessionRestore()
            }
          }

          } // end generalTab

          // ==================== Telemetry tab (v2.0.0) ====================
          Column {
            id: telemetryTab
            visible: root.activeTab === "telemetry"
            width: parent.width
            spacing: Style.space(14)

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Live stats ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader { text: "LIVE STATS"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Grid {
              id: statGrid
              readonly property var tiles: [
                { icon: "󰍛", label: "CPU", value: Model.fmtPct(root.status.cpuPct), color: Model.pctColor(root.status.cpuPct) },
                { icon: "󰔏", label: "CPU TEMP", value: Model.fmtTemp(root.status.cpuTemp), color: Model.tempColor(root.status.cpuTemp) },
                { icon: "󰘚", label: "RAM", value: Model.fmtMb(root.status.ramUsedMb), color: root.bar.foreground },
                { icon: "󰢮", label: "GPU", value: Model.fmtPct(root.status.gpuUtil), color: Model.pctColor(root.status.gpuUtil) },
                { icon: "󰔏", label: "GPU TEMP", value: Model.fmtTemp(root.status.gpuTemp), color: Model.tempColor(root.status.gpuTemp) },
                { icon: "󱐋", label: "GPU POWER", value: Model.fmtWatts(root.status.gpuPowerW), color: root.bar.foreground }
              ]
              width: parent.width
              columns: 2
              columnSpacing: Style.spacing.sm
              rowSpacing: Style.spacing.sm

              Repeater {
                model: statGrid.tiles
                BorderSurface {
                  id: tile
                  required property var modelData
                  width: (statGrid.width - statGrid.columnSpacing) / 2
                  implicitHeight: Style.space(52)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.05)
                  borderSpec: Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14), 1)

                  Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Row {
                      spacing: Style.space(6)
                      Text {
                        text: tile.modelData.icon
                        color: tile.modelData.color
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.body
                      }
                      Text {
                        text: tile.modelData.label
                        color: Qt.darker(root.bar.foreground, 1.5)
                        font.family: root.bar.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                    Text {
                      text: tile.modelData.value
                      color: tile.modelData.color
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.subtitle
                      font.bold: true
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- History sparkline ----------
          Column {
            width: parent.width
            spacing: Style.spacing.xs

            Item {
              width: parent.width
              implicitHeight: histHeader.implicitHeight
              Text {
                id: histHeader
                text: "CPU / GPU LOAD"
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.left: parent.left
              }
              Text {
                text: "CPU · GPU"
                color: Color.accent
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
              }
            }

            BorderSurface {
              width: parent.width
              implicitHeight: Style.space(80)
              radius: Style.cornerRadius
              color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.05)
              borderSpec: Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14), 1)

              Canvas {
                id: historyCanvas
                anchors.fill: parent
                anchors.margins: Style.space(6)
                renderStrategy: Canvas.Immediate
                readonly property var hist: Model.parseHistory(root.status)
                onHistChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var w = width, h = height
                  ctx.strokeStyle = "rgba(255,255,255,0.08)"; ctx.lineWidth = 1
                  ctx.beginPath(); ctx.moveTo(0, h * 0.5); ctx.lineTo(w, h * 0.5); ctx.stroke()

                  function drawSeries(data, color, lw) {
                    if (!data || data.length < 2) return
                    ctx.strokeStyle = color; ctx.lineWidth = lw
                    ctx.beginPath()
                    var step = w / Math.max(1, data.length - 1)
                    for (var i = 0; i < data.length; i++) {
                      var norm = Math.max(0, Math.min(1, data[i] / 100))
                      var y = h - norm * h
                      if (i === 0) ctx.moveTo(0, y); else ctx.lineTo(i * step, y)
                    }
                    ctx.stroke()
                  }
                  drawSeries(hist.cpu, Color.accent.toString(), 2)
                  drawSeries(hist.gpu, Qt.darker(root.bar.foreground, 1.15).toString(), 1.5)
                }
              }
            }
          }

          // ---------- GPU hardware ----------
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            visible: root.status.gpuModel !== ""

            PanelSeparator { foreground: root.bar.foreground }
            PanelSectionHeader { text: "GPU HARDWARE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.status.gpuModel
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: [
                root.status.gpuDriver ? ("Driver " + root.status.gpuDriver) : "",
                root.status.gpuVbios ? ("VBIOS " + root.status.gpuVbios) : "",
                root.status.gpuPcieGen >= 0 ? ("PCIe Gen" + root.status.gpuPcieGen + " x" + root.status.gpuPcieWidth) : "",
                root.status.vulkanVer ? ("Vulkan " + root.status.vulkanVer) : "",
                root.status.mesaVer ? ("Mesa " + root.status.mesaVer) : ""
              ].filter(function(s) { return s !== "" }).join(" · ")
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- GPU processes ----------
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            visible: root.status.gpuProcesses.length > 0

            PanelSeparator { foreground: root.bar.foreground }
            PanelSectionHeader { text: "GPU PROCESSES"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Repeater {
              model: root.status.gpuProcesses
              Item {
                required property var modelData
                width: parent.width
                implicitHeight: Math.max(procName.implicitHeight, procMem.implicitHeight) + Style.space(2)

                Text {
                  id: procName
                  text: modelData.name
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  width: parent.width - procMem.implicitWidth - Style.space(10)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  id: procMem
                  text: Model.fmtMb(modelData.memMb)
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Fan curve ----------
          Column {
            id: fanCurveSection
            width: parent.width
            spacing: Style.space(10)

            property var points: root.status.fanCurve

            PanelSectionHeader { text: "FAN CURVE"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Toggle {
              width: parent.width
              label: "Custom fan curve"
              description: "Runs a background service that sets fan speed from this curve instead of a fixed preset. Always reverts to Auto if the service stops."
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.status.fanCurveActive
              onClicked: root.setFanCurveEnabled(!root.status.fanCurveActive)
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xs
              opacity: root.status.fanCurveActive ? 1.0 : 0.6

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Drag a point to change it. Temperature 30–100°C left to right, fan speed 0–100% bottom to top."
                color: Qt.darker(root.bar.foreground, 1.5)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              Item {
                id: curveArea
                width: parent.width
                height: Style.space(140)

                Canvas {
                  id: curveCanvas
                  anchors.fill: parent
                  renderStrategy: Canvas.Immediate
                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var w = width, h = height
                    ctx.strokeStyle = "rgba(255,255,255,0.06)"; ctx.lineWidth = 1
                    for (var g = 1; g < 4; g++) {
                      var gy = h * g / 4
                      ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
                    }
                    var pts = fanCurveSection.points
                    if (!pts || pts.length < 2) return
                    ctx.strokeStyle = Color.accent.toString(); ctx.lineWidth = 2
                    ctx.beginPath()
                    for (var i = 0; i < pts.length; i++) {
                      var x = (pts[i].temp - 30) / 70 * w
                      var y = h - (pts[i].speed / 100) * h
                      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                  }
                }

                Repeater {
                  model: fanCurveSection.points.length
                  Rectangle {
                    required property int index
                    readonly property var pt: fanCurveSection.points[index]
                    width: Style.space(12)
                    height: Style.space(12)
                    radius: width / 2
                    color: Color.accent
                    x: (pt.temp - 30) / 70 * curveArea.width - width / 2
                    y: curveArea.height - (pt.speed / 100) * curveArea.height - height / 2
                  }
                }

                MouseArea {
                  id: dragArea
                  anchors.fill: parent
                  property int activeIndex: -1

                  function nearestIndex(mx, my) {
                    var best = -1, bestDist = 1e9
                    var pts = fanCurveSection.points
                    for (var i = 0; i < pts.length; i++) {
                      var px = (pts[i].temp - 30) / 70 * width
                      var py = height - (pts[i].speed / 100) * height
                      var d = Math.hypot(mx - px, my - py)
                      if (d < bestDist) { bestDist = d; best = i }
                    }
                    return best
                  }

                  onPressed: function(mouse) { activeIndex = nearestIndex(mouse.x, mouse.y) }
                  onPositionChanged: function(mouse) {
                    if (activeIndex < 0) return
                    var newTemp = Math.max(30, Math.min(100, Math.round(30 + mouse.x / width * 70)))
                    var newSpeed = Math.max(0, Math.min(100, Math.round(100 - mouse.y / height * 100)))
                    var pts = fanCurveSection.points.slice()
                    pts[activeIndex] = { temp: newTemp, speed: newSpeed }
                    fanCurveSection.points = pts
                    curveCanvas.requestPaint()
                  }
                  onReleased: {
                    if (activeIndex >= 0) root.saveFanCurve(fanCurveSection.points)
                    activeIndex = -1
                  }
                }
              }

              Button {
                text: "Reset to defaults"
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                horizontalPadding: Style.spacing.sm
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                onClicked: {
                  var defaults = [{ temp: 40, speed: 30 }, { temp: 60, speed: 50 }, { temp: 75, speed: 75 }, { temp: 90, speed: 100 }]
                  fanCurveSection.points = defaults
                  curveCanvas.requestPaint()
                  root.saveFanCurve(defaults)
                }
              }
            }
          }

          } // end telemetryTab

          // ==================== Keyboard tab ====================
          Column {
            id: keyboardTab
            visible: root.activeTab === "keyboard"
            width: parent.width
            spacing: Style.space(14)

          Column {
            visible: !root.status.kbAvailable
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.status.kbPkgInstalled
                ? "linuwu-sense-dkms is installed, but its driver isn't loaded yet — the stock acer_wmi driver got there first at boot."
                : "4-zone keyboard RGB needs linuwu-sense-dkms (AUR) — not installed. Controls below no-op until it is."
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Button {
              visible: root.status.kbPkgInstalled
              text: "Enable keyboard RGB now"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.runEnableKeyboard()
            }
          }

          // ---------- Brightness ----------
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            opacity: root.status.kbAvailable ? 1.0 : 0.5
            PanelSectionHeader { text: "BRIGHTNESS"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
            ButtonGroup {
              width: parent.width
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              cursorIndex: -1
              options: [
                { value: "0", label: "Off" },
                { value: "25", label: "25%" },
                { value: "50", label: "50%" },
                { value: "75", label: "75%" },
                { value: "100", label: "100%" }
              ]
              onChanged: function(v) { root.setKbBrightness(parseInt(v, 10)) }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Color ----------
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            opacity: root.status.kbAvailable ? 1.0 : 0.5
            PanelSectionHeader { text: "COLOR · STATIC"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
            Grid {
              width: parent.width
              columns: 5
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(10)
              Repeater {
                model: Model.KB_COLORS
                BorderSurface {
                  id: swatch
                  required property var modelData
                  width: Style.space(28)
                  height: Style.space(28)
                  radius: height / 2
                  color: "#" + Model.kbColorHex(modelData.key, root.status.themeHex, root.modeHex())
                  borderSpec: swatchMouse.containsMouse
                    ? Border.controlSpec("hover-cursor", root.bar.foreground, Color.accent)
                    : Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.25), 1)

                  MouseArea {
                    id: swatchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setKbColor(Model.kbColorHex(swatch.modelData.key, root.status.themeHex, root.modeHex()))
                  }

                  PanelToolTip {
                    visible: swatchMouse.containsMouse
                    text: swatch.modelData.label
                    fontFamily: root.bar.fontFamily
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Effects ----------
          Column {
            width: parent.width
            spacing: Style.spacing.xs
            opacity: root.status.kbAvailable ? 1.0 : 0.5
            PanelSectionHeader { text: "EFFECT"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }
            Grid {
              id: effectGrid
              readonly property var options: [
                { mode: "1", label: "Breathing" },
                { mode: "2", label: "Neon" },
                { mode: "3", label: "Wave" },
                { mode: "4", label: "Shifting" },
                { mode: "5", label: "Zoom" },
                { mode: "6", label: "Meteor" },
                { mode: "7", label: "Twinkling" }
              ]
              width: parent.width
              columns: 3
              columnSpacing: Style.spacing.xs
              rowSpacing: Style.spacing.xs

              Repeater {
                model: effectGrid.options
                Button {
                  required property var modelData
                  text: modelData.label
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  onClicked: root.setKbEffect(modelData.mode)
                }
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Quick actions ----------
          Row {
            width: parent.width
            spacing: Style.space(10)
            opacity: root.status.kbAvailable ? 1.0 : 0.5

            Button {
              text: "Match Omarchy theme"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              selected: root.status.kbLink === "theme"
              onClicked: root.setKbLink("theme")
            }
            Button {
              text: "Match Predator mode"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              selected: root.status.kbLink === "profile"
              onClicked: root.setKbLink("profile")
            }
          }

          } // end keyboardTab

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
