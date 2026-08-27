import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Performance control center for the Acer Predator laptop: power presets,
// CPU/GPU/fan/battery/keyboard-RGB controls, and session restore. Ported
// from an old walker-menu extension (omarchy/extensions/menu.sh) into a
// proper bar-widget plugin for the omarchy-shell era.
//
// Privileged writes go through /usr/local/bin/omarchy-perf-helper, a
// root-owned, verb-whitelisted script reachable via a scoped NOPASSWD sudo
// rule (see README.md). Every control here degrades gracefully when that
// helper — or the optional envycontrol / linuwu-sense-dkms backends — isn't
// installed: read-only status still shows, writes just no-op.
Panel {
  id: root
  moduleName: "io.github.rezwoan.performance"
  ipcTarget: "io.github.rezwoan.performance"

  property var status: Model.parseStatus("")
  property string activeTab: "general"

  // Predator-logo tint: named power preset wins when one is active (it's the
  // deliberate, one-tap choice); otherwise fall back to the power-profile,
  // so the logo still reflects something even in "custom" state. Theme
  // foreground is the fallback when neither maps to a color.
  function modeColor() {
    var key = root.status.preset || root.status.profile
    switch (key) {
      case "ultra": case "power-saver": return "#33ff77"   // green — battery saver
      case "performance": return "#ff00ea"                  // neon magenta — performance
      case "balanced": return "#3b82f6"                      // blue — balanced
      default: return root.bar ? root.bar.foreground : Color.foreground
    }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  // Fire-and-forget a privileged verb through the helper, then refresh once
  // the write has had time to land. `bar.run` is the shared fire-and-forget
  // exec every bar widget uses; sudo itself no-ops silently (stderr
  // discarded) when the NOPASSWD rule isn't installed yet, so a missing
  // helper never surfaces as an error here — the status banner covers that.
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
  function toggleBatteryLimit() { runPrivileged("battery-limit", root.status.battlimit === "on" ? "off" : "on") }
  function setFan(mode) { runPrivileged("fan", mode) }
  function setKbBrightness(pct) { runPrivileged("kb-bright", pct) }
  function setKbColor(hex) { runPrivileged("kb-zone", hex, "100") }
  function setKbEffect(mode) { runPrivileged("kb-effect", mode, "5", "100", "1", root.status.themeHex) }
  function matchKbTheme() { runPrivileged("kb-zone", root.status.themeHex, "100") }
  function turnKbOff() { runPrivileged("kb-bright", "0") }

  function toggleSession() {
    var flag = "$HOME/.config/omarchy/session-restore.enabled"
    if (root.status.session === "on") {
      runPlain("rm -f " + flag + " && systemctl --user disable --now omarchy-perf-session-save.timer")
    } else {
      runPlain("touch " + flag + " && systemctl --user enable --now omarchy-perf-session-save.timer && $HOME/.local/bin/omarchy-perf-session-save")
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
    tooltipText: root.status.preset ? Model.presetLabel(root.status.preset) : "Performance"
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
                text: "Performance"
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
            implicitHeight: setupText.implicitHeight + Style.space(16)
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.05)
            radius: Style.cornerRadius
            borderSpec: Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.14), 1)

            Text {
              id: setupText
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              wrapMode: Text.WordWrap
              text: "Privileged controls are read-only until the helper is installed — run install-helper.sh (see this plugin's README) with sudo."
              color: Qt.darker(root.bar.foreground, 1.3)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ==================== General tab ====================
          Column {
            id: generalTab
            visible: root.activeTab === "general"
            width: parent.width
            spacing: Style.space(14)

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Power preset ----------
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader { text: "POWER PRESET"; foreground: root.bar.foreground; fontFamily: root.bar.fontFamily }

            ButtonGroup {
              width: parent.width
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              value: root.status.preset
              options: [
                { value: "ultra", label: "Ultra Saver" },
                { value: "balanced", label: "Balanced" },
                { value: "performance", label: "Performance" }
              ]
              onChanged: function(v) { root.setPreset(v) }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Power profile ----------
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

          PanelSeparator { foreground: root.bar.foreground }

          // ---------- Thermal profile ----------
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
              label: "Restore apps on login"
              description: "Snapshots open windows every minute and reopens them next login"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              checked: root.status.session === "on"
              onClicked: root.toggleSession()
            }
          }

          } // end generalTab

          // ==================== Keyboard tab ====================
          Column {
            id: keyboardTab
            visible: root.activeTab === "keyboard"
            width: parent.width
            spacing: Style.space(14)

          Text {
            visible: !root.status.kbAvailable
            width: parent.width
            wrapMode: Text.WordWrap
            text: "4-zone keyboard RGB needs linuwu-sense-dkms (AUR) — not installed. Controls below no-op until it is."
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
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
            Row {
              spacing: Style.space(10)
              Repeater {
                model: Model.KB_COLORS
                BorderSurface {
                  id: swatch
                  required property var modelData
                  width: Style.space(28)
                  height: Style.space(28)
                  radius: height / 2
                  color: "#" + Model.kbColorHex(modelData.key, root.status.themeHex)
                  borderSpec: swatchMouse.containsMouse
                    ? Border.controlSpec("hover-cursor", root.bar.foreground, Color.accent)
                    : Border.flat(Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.25), 1)

                  MouseArea {
                    id: swatchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setKbColor(Model.kbColorHex(swatch.modelData.key, root.status.themeHex))
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
              onClicked: root.matchKbTheme()
            }
            Button {
              text: "Off"
              fontSize: Style.font.bodySmall
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              horizontalPadding: Style.spacing.sm
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.turnKbOff()
            }
          }

          } // end keyboardTab

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
