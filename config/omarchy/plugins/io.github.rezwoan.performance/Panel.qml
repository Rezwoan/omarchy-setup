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
    switch (key) {
      case "ultra": case "saver": case "power-saver": return "33ff77"      // green — battery saver
      case "performance": case "ultra-performance": return "ff00ea"         // neon magenta — performance
      case "balanced": return "3b82f6"                                     // blue — balanced
      default: return ""
    }
  }

  // Predator-logo tint: theme foreground is the fallback when modeHex() is
  // empty, so the logo still reflects something even in "custom" state.
  function modeColor() {
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

  // Refresh rate needs no privilege at all — `hyprctl keyword monitor` is a
  // plain user-session compositor call, unlike everything else in this file.
  // Keep the monitor's own position/scale untouched so this never reshuffles
  // a multi-monitor layout; only the "@rate" component changes.
  function setRefreshRate(hz) {
    var mon = root.status.refreshMonitor
    var res = root.status.refreshRes
    if (!mon || !res) return
    var rate = Number(hz)
    if (!isFinite(rate) || rate <= 0) return
    var pos = root.status.refreshX + "x" + root.status.refreshY
    var scale = root.status.refreshScale || "1"
    var spec = mon + "," + res + "@" + rate.toFixed(2) + "," + pos + "," + scale
    runPlain("hyprctl keyword monitor " + Util.shellQuote(spec))
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
    interval: 5000
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
    tooltipText: root.status.preset ? Model.presetLabel(root.status.preset) : "PredatorSense"
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
              columns: 3
              columnSpacing: Style.spacing.xs
              rowSpacing: Style.spacing.xs

              Repeater {
                model: profileGrid.options
                Button {
                  required property var modelData
                  text: modelData.label
                  fontSize: Style.font.bodySmall
                  foreground: root.bar.foreground
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
            visible: Model.refreshOptionsList(root.status.refreshOptions).length > 1
          }

          // ---------- Display ----------
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: Model.refreshOptionsList(root.status.refreshOptions).length > 1

            PanelSectionHeader { text: "DISPLAY"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            Column {
              width: parent.width
              spacing: Style.spacing.xs

              Text {
                text: "REFRESH RATE · " + root.status.refreshMonitor.toUpperCase()
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
                value: String(root.status.refreshCurrent)
                options: Model.refreshOptionsList(root.status.refreshOptions)
                onChanged: function(v) { root.setRefreshRate(v) }
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
