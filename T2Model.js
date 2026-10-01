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
    pciePortsCompat: false,
    audioPowerSave: true,
    usbAutosuspend: true,
    kbdTimeout: "1m",
    memSleep: "deep",
    memSleepModes: [],
    lidAction: "suspend",
    clamshellMode: true,
    wakeOnLid: true,
    wakeOnAc: false,
    hibernateDelay: "off",
    touchbarBlank: true,
    recommendedPromptShown: false
  };
}

function parseStatus(raw) {
  if (!raw || typeof raw !== "string" || !raw.trim()) return null;
  try {
    var data = JSON.parse(raw);
    if (data && typeof data === "object") {
      data.isT2 = Boolean(data.isT2);
      data.helperInstalled = Boolean(data.helperInstalled);

      if (data.battery && typeof data.battery === "object") {
        if (typeof data.battery.percent === "number") {
          data.battery.percent = Math.min(100, Math.max(0, Math.round(data.battery.percent)));
        }
        if (typeof data.battery.health === "number") {
          data.battery.health = Math.min(100, Math.max(0, Math.round(data.battery.health)));
        }
        if (typeof data.battery.watts !== "number" || isNaN(data.battery.watts) || data.battery.watts < 0) {
          data.battery.watts = 0.0;
        }
        if (typeof data.battery.cycles !== "number" || isNaN(data.battery.cycles) || data.battery.cycles < 0) {
          data.battery.cycles = 0;
        }
      }

      if (!Array.isArray(data.inactiveEthernet)) {
        data.inactiveEthernet = [];
      }
      if (!Array.isArray(data.memSleepModes)) {
        data.memSleepModes = [];
      }

      data.wifiPowerSave = Boolean(data.wifiPowerSave);
      data.pciePortsCompat = Boolean(data.pciePortsCompat);
      data.audioPowerSave = Boolean(data.audioPowerSave);
      data.usbAutosuspend = Boolean(data.usbAutosuspend);
      data.clamshellMode = data.clamshellMode !== undefined ? Boolean(data.clamshellMode) : true;
      data.wakeOnLid = Boolean(data.wakeOnLid);
      data.wakeOnAc = Boolean(data.wakeOnAc);
      data.touchbarBlank = data.touchbarBlank !== undefined ? Boolean(data.touchbarBlank) : true;
      data.recommendedPromptShown = Boolean(data.recommendedPromptShown);

      if (data.hibernateDelay !== undefined) {
        var hd = String(data.hibernateDelay).toLowerCase().trim();
        if (hd === "1800" || hd === "1800s" || hd === "30m" || hd === "30min") data.hibernateDelay = "30min";
        else if (hd === "3600" || hd === "3600s" || hd === "60m" || hd === "1h" || hd === "1hour") data.hibernateDelay = "1hour";
        else if (hd === "7200" || hd === "7200s" || hd === "120m" || hd === "2h" || hd === "2hours") data.hibernateDelay = "2hours";
        else if (hd === "0" || hd === "off" || hd === "never") data.hibernateDelay = "off";
      }
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
    var pct = Math.min(100, Math.max(0, status.battery.percent || 0));
    tip += "\nBattery: " + pct + "% (" + status.battery.status + ")";
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
    case "deep": return "Deep Sleep";
    case "s2idle": return "Modern Standby";
    case "shallow": return "Standby";
    default: return mode ? (mode.charAt(0).toUpperCase() + mode.slice(1)) : "Unknown";
  }
}

function formatLidAction(action) {
  switch (action) {
    case "suspend":
    case "suspend-then-hibernate": return "Suspend";
    case "ignore": return "Do Nothing";
    case "lock": return "Lock Screen";
    case "hibernate": return "Hibernate";
    default: return action || "Suspend";
  }
}

function formatHibernateDelay(delay) {
  var d = String(delay || "").toLowerCase().trim();
  switch (d) {
    case "off":
    case "0":
    case "":
    case "never": return "Never";
    case "30min":
    case "30m":
    case "1800":
    case "1800s": return "30 min";
    case "1hour":
    case "1h":
    case "3600":
    case "3600s": return "1 hour";
    case "2hours":
    case "2h":
    case "7200":
    case "7200s": return "2 hours";
    default: return delay || "Never";
  }
}
