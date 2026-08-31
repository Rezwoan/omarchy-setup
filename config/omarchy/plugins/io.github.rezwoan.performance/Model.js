// Pure helpers for the Performance panel: JSON parsing + label/icon lookups.
// No QML types in here so it stays trivially testable/readable on its own.

function parseStatus(text) {
  var fallback = {
    profile: "unknown", turbo: "n/a", thermal: "n/a", thermalChoices: "",
    cpucap: "", cores: "all", powerlimit: "", gpu: "n/a", gpuAvailable: false,
    powerd: "inactive", battlimit: "n/a", fan: "n/a", kbAvailable: false, kbPkgInstalled: false,
    battpct: "", battstatus: "", preset: "", themeHex: "ffffff",
    helperOk: false, sessionEnabled: false, kbLink: "off",
    refreshMonitor: "", refreshRes: "", refreshCurrent: "", refreshOptions: "", refreshScale: "1",
    cpuPct: -1, ramUsedMb: -1, ramTotalMb: -1, cpuTemp: -1, fan1Rpm: -1, fan2Rpm: -1,
    gpuModel: "", gpuUtil: -1, gpuMemUsedMb: -1, gpuMemTotalMb: -1, gpuTemp: -1,
    gpuPowerW: -1, gpuPowerLimitW: -1, gpuClockSm: -1, gpuClockMem: -1,
    gpuDriver: "", gpuVbios: "", gpuPcieGen: -1, gpuPcieWidth: -1,
    vulkanVer: "", mesaVer: "", gpuProcesses: [],
    history: { cpu: [], gpu: [], cpuTemp: [], gpuTemp: [] }, fanCurveActive: false,
    fanCurve: [{ temp: 40, speed: 30 }, { temp: 60, speed: 50 }, { temp: 75, speed: 75 }, { temp: 90, speed: 100 }]
  }
  try {
    var parsed = JSON.parse(String(text || "").trim())
    if (!parsed || typeof parsed !== "object") return fallback
    for (var key in fallback) {
      if (parsed[key] === undefined || parsed[key] === null) parsed[key] = fallback[key]
    }
    return parsed
  } catch (e) {
    return fallback
  }
}

function presetLabel(preset) {
  switch (preset) {
    case "ultra": return "ULTRA SAVER"
    case "saver": return "SAVER"
    case "balanced": return "BALANCED"
    case "performance": return "PERFORMANCE"
    case "ultra-performance": return "ULTRA PERFORMANCE"
    default: return "CUSTOM"
  }
}

// Same ramp as Panel.qml's modeHex(), keyed by preset value instead of
// current state — lets each PROFILE button show what it WOULD look like if
// selected, not just what's currently active. Reused, not reinvented: this
// is the single source of truth both call.
function presetColorHex(preset) {
  switch (preset) {
    case "ultra": case "saver": return "33ff77"
    case "performance": case "ultra-performance": return "ff00ea"
    case "balanced": return "3b82f6"
    default: return ""
  }
}

function presetIcon(preset) {
  switch (preset) {
    case "ultra": case "saver": return "󰡳"
    case "performance": case "ultra-performance": return "󰓅"
    default: return "󰗑"
  }
}

function profileIcon(name) {
  switch (name) {
    case "power-saver": return "󰾆"
    case "performance": return "󰓅"
    default: return "󰗑"
  }
}

function profileLabel(name) {
  switch (name) {
    case "power-saver": return "Saver"
    case "performance": return "Performance"
    case "balanced": return "Balanced"
    default: return name || "Unknown"
  }
}

function coreLabel(cores) {
  switch (cores) {
    case "no-smt": return "No hyperthreading"
    case "ecore": return "E-cores only"
    default: return "All cores"
  }
}

function coreIcon(cores) {
  switch (cores) {
    case "no-smt": return "󰬈"
    case "ecore": return "󰾆"
    default: return "󰬹"
  }
}

// "low-power quiet balanced balanced-performance performance" -> ordered,
// de-duplicated list of { value, label } for a ButtonGroup. Fixed display
// order regardless of the order the kernel reports them in.
function thermalOptions(choicesRaw) {
  var order = ["low-power", "quiet", "balanced", "balanced-performance", "performance"]
  var labels = {
    "low-power": "Low power", "quiet": "Quiet", "balanced": "Balanced",
    "balanced-performance": "Balanced+", "performance": "Performance"
  }
  var present = String(choicesRaw || "").trim().split(/\s+/)
  var out = []
  for (var i = 0; i < order.length; i++) {
    if (present.indexOf(order[i]) !== -1) out.push({ value: order[i], label: labels[order[i]] })
  }
  return out
}

function fanLabel(fan) {
  if (fan === "auto") return "Auto"
  if (fan === "n/a") return "n/a"
  return fan + "%"
}

var KB_COLORS = [
  { key: "theme", label: "Theme" },
  { key: "profile", label: "Profile" },
  { key: "green", label: "Green", hex: "82fb9c" },
  { key: "teal", label: "Teal", hex: "00aec7" },
  { key: "cyan", label: "Cyan", hex: "00ffff" },
  { key: "blue", label: "Blue", hex: "3b82f6" },
  { key: "purple", label: "Purple", hex: "a855f7" },
  { key: "red", label: "Red", hex: "ff2b2b" },
  { key: "orange", label: "Orange", hex: "ff8800" },
  { key: "white", label: "White", hex: "ffffff" }
]

// "60,165" -> [60, 165]. Drives the refresh-rate slider by index rather
// than raw Hz, so dragging always lands on a hardware-supported rate. Only
// ever lists rates the focused monitor's current resolution actually
// reports (see status.sh).
function refreshRates(csv) {
  var out = []
  var parts = String(csv || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var v = parseInt(parts[i], 10)
    if (!isNaN(v)) out.push(v)
  }
  return out
}

// Centralized formatters (v2.0.0) — every numeric telemetry field uses -1 as
// its "not reported" sentinel (see status.sh); every formatter shares that
// one convention and an em-dash for "no data," so a sensor going missing on
// someone else's hardware never needs a per-callsite fix.
function fmtTemp(c) { return c < 0 ? "—" : Math.round(c) + "°C" }
function fmtPct(p) { return p < 0 ? "—" : Math.round(p) + "%" }
function fmtWatts(w) { return w < 0 ? "—" : w.toFixed(1) + "W" }
function fmtRpm(r) { return r < 0 ? "—" : Math.round(r) + " RPM" }
function fmtMhz(m) { return m < 0 ? "—" : Math.round(m) + " MHz" }
function fmtMb(mb) {
  if (mb < 0) return "—"
  return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : Math.round(mb) + " MB"
}

// One shared threshold ladder for anything measured in °C — CPU temp, GPU
// temp, hotspot, all read the same ramp so "what does orange mean" only has
// one answer in the whole panel.
function tempColor(c) {
  if (c < 0) return "#888888"
  if (c >= 90) return "#ff4444"
  if (c >= 80) return "#ff8844"
  if (c >= 65) return "#ffcc44"
  return "#44cc66"
}

// Same idea for anything measured 0-100% (GPU/CPU util, VRAM, battery).
function pctColor(p) {
  if (p < 0) return "#888888"
  if (p >= 90) return "#ff4444"
  if (p >= 75) return "#ff8844"
  return "#44cc66"
}

// Rolling-history JSON (see status.sh's predatorsense-history.json) parsed
// defensively, same fallback-on-any-failure style as parseStatus.
function parseHistory(status) {
  var h = status && status.history
  if (!h || typeof h !== "object") return { cpu: [], gpu: [], cpuTemp: [], gpuTemp: [] }
  return {
    cpu: Array.isArray(h.cpu) ? h.cpu : [],
    gpu: Array.isArray(h.gpu) ? h.gpu : [],
    cpuTemp: Array.isArray(h.cpuTemp) ? h.cpuTemp : [],
    gpuTemp: Array.isArray(h.gpuTemp) ? h.gpuTemp : []
  }
}

function kbColorHex(key, themeHex, modeHex) {
  if (key === "theme") return themeHex || "ffffff"
  if (key === "profile") return modeHex || themeHex || "ffffff"
  for (var i = 0; i < KB_COLORS.length; i++) {
    if (KB_COLORS[i].key === key) return KB_COLORS[i].hex
  }
  return "ffffff"
}
