// T2Model.js: State parsing, defaults, and formatting for Omarchy T2 Linux

function emptyStatus() {
  return {
    isT2: true,
    model: "Detecting…",
    vendor: "Apple Inc.",
    chip: "Apple T2 Security Chip",
    helperInstalled: false,
    battery: {
      present: false,
      percent: 0,
      status: "Unknown",
      watts: 0.0,
      health: 100,
      cycles: 0,
      online: false
    },
    epp: "balance_power",
    aspm: "default",
    wifiPowerSave: false,
    inactiveEthernet: [],
    audioPowerSave: true,
    usbAutosuspend: true,
    kbdTimeout: "1m",
    memSleep: "deep",
    lidAction: "suspend",
    clamshellMode: true,
    wakeOnLid: true,
    wakeOnAc: false,
    hibernateDelay: "off",
    touchbarBlank: true
  };
}

function parseStatus(raw) {
  if (!raw || typeof raw !== "string" || !raw.trim()) return null;
  try {
    var data = JSON.parse(raw);
    if (data && typeof data === "object") {
      return data;
    }
  } catch (e) {
    console.warn("T2Model: failed to parse status JSON:", e, raw);
  }
  return null;
}

function barIcon(status) {
  if (!status || !status.isT2) {
    return "󰌢"; // Laptop icon or alert icon
  }
  return ""; // Apple logo glyph
}

function tooltip(status) {
  if (!status) return "Omarchy T2 Linux";
  if (!status.isT2) {
    return "Omarchy T2 Linux\nApple T2 chip not detected on this system";
  }
  var tip = "Omarchy T2 Linux (" + (status.model || "T2 MacBook") + ")";
  if (status.battery && status.battery.present) {
    tip += "\nBattery: " + status.battery.percent + "% (" + status.battery.status + ")";
    if (status.battery.watts > 0) {
      tip += " · " + status.battery.watts + "W";
    }
  }
  tip += "\nSleep: " + (status.memSleep === "deep" ? "Deep (S3)" : "s2idle");
  tip += " · EPP: " + status.epp;
  return tip;
}

function formatEpp(epp) {
  switch (epp) {
    case "power": return "Powersave";
    case "balanced":
    case "balance_power":
    case "balance_performance": return "Balanced";
    case "performance": return "Performance";
    default: return epp || "Unknown";
  }
}

function formatAspm(aspm) {
  switch (aspm) {
    case "powersave": return "Powersave";
    case "default": return "Default";
    case "performance": return "Performance";
    default: return aspm || "Unknown";
  }
}

function formatMemSleep(mode) {
  switch (mode) {
    case "deep": return "Deep Sleep (S3)";
    case "s2idle": return "Modern Standby (Freeze)";
    default: return mode || "Unknown";
  }
}

function formatLidAction(action) {
  switch (action) {
    case "suspend": return "Suspend";
    case "ignore": return "Do Nothing";
    case "lock": return "Lock Screen";
    case "hibernate": return "Hibernate";
    default: return action || "Suspend";
  }
}
