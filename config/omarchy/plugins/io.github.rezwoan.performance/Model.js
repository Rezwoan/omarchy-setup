// Pure helpers for the Performance panel: JSON parsing + label/icon lookups.
// No QML types in here so it stays trivially testable/readable on its own.

function parseStatus(text) {
  var fallback = {
    profile: "unknown", turbo: "n/a", thermal: "n/a", thermalChoices: "",
    cpucap: "", cores: "all", powerlimit: "", gpu: "n/a", gpuAvailable: false,
    powerd: "inactive", battlimit: "n/a", fan: "n/a", kbAvailable: false, kbPkgInstalled: false,
    battpct: "", battstatus: "", preset: "", themeHex: "ffffff",
    helperOk: false, sessionEnabled: false, kbLink: "off",
    refreshMonitor: "", refreshRes: "", refreshCurrent: "", refreshOptions: "",
    refreshX: "0", refreshY: "0", refreshScale: "1"
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

// "60,165" -> [{ value: "60", label: "60 Hz" }, { value: "165", label: "165 Hz" }]
// for a ButtonGroup. Only ever lists rates the focused monitor's current
// resolution actually reports (see status.sh), so there's nothing here to
// validate further.
function refreshOptionsList(csv) {
  var out = []
  var parts = String(csv || "").split(",")
  for (var i = 0; i < parts.length; i++) {
    var v = parts[i].trim()
    if (v === "") continue
    out.push({ value: v, label: v + " Hz" })
  }
  return out
}

function kbColorHex(key, themeHex, modeHex) {
  if (key === "theme") return themeHex || "ffffff"
  if (key === "profile") return modeHex || themeHex || "ffffff"
  for (var i = 0; i < KB_COLORS.length; i++) {
    if (KB_COLORS[i].key === key) return KB_COLORS[i].hex
  }
  return "ffffff"
}
