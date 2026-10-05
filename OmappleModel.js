// OmappleModel.js: State parsing, defaults, and formatting for Omapple

function emptyStatus() {
  return {
    isT2: true,
    isApple: true,
    model: "Detecting…",
    vendor: "Apple Inc.",
    chip: "Apple T2 Security Chip",
    cpu: "Detecting…",
    kernel: "Detecting…",
    arch: "x86_64",
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
    recommendedPromptShown: false,
    keybindingSelectAll: "CTRL + A",
    keybindingDelete: "DELETE",
    keybindingFind: "CTRL + F",
    keybindingFullscreen: "SUPER + F",
    keybindingUndo: "CTRL + Z",
    keybindingRedo: "CTRL + SHIFT + Z",
    keybindingSave: "CTRL + S",
    keybindingCut: "CTRL + X",
    keybindingReload: "CTRL + R",
    keybindingSelectAddress: "CTRL + L",
    trackpad: {
      device: "Apple Force Touch Trackpad",
      present: true,
      naturalScroll: true,
      tapToClick: true,
      clickfingerBehavior: true,
      disableWhileTyping: true,
      scrollFactor: 0.64,
      middleButtonEmulation: false,
      tapAndDrag: true,
      dragLock: false,
      drag3fg: 0,
      tapButtonMap: "lrm",
      flipX: false,
      flipY: false,
      sensitivity: 0.0,
      accelProfile: "adaptive",
      leftHanded: false,
      swipeWorkspaces: true
    }
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
        } else {
          data.battery.percent = 0;
        }
        if (typeof data.battery.health === "number") {
          data.battery.health = Math.min(100, Math.max(0, Math.round(data.battery.health)));
        } else {
          data.battery.health = 100;
        }
        if (typeof data.battery.watts !== "number" || isNaN(data.battery.watts) || data.battery.watts < 0) {
          data.battery.watts = 0.0;
        }
        if (typeof data.battery.cycles !== "number" || isNaN(data.battery.cycles) || data.battery.cycles < 0) {
          data.battery.cycles = 0;
        }
        data.battery.present = Boolean(data.battery.present);
        data.battery.status = data.battery.status ? String(data.battery.status) : "Unknown";
        data.battery.online = Boolean(data.battery.online);
      } else {
        data.battery = emptyStatus().battery;
      }

      if (!data.systemKeybindingOverrides || typeof data.systemKeybindingOverrides !== "object") {
        data.systemKeybindingOverrides = {};
      }
      if (!data.systemKeybindings || typeof data.systemKeybindings !== "object") {
        data.systemKeybindings = {};
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
      data.keybindingSelectAll = data.keybindingSelectAll ? String(data.keybindingSelectAll).trim() : "CTRL + A";
      data.keybindingDelete = data.keybindingDelete ? String(data.keybindingDelete).trim() : "DELETE";
      data.keybindingFind = data.keybindingFind ? String(data.keybindingFind).trim() : "CTRL + F";
      data.keybindingFullscreen = data.keybindingFullscreen ? String(data.keybindingFullscreen).trim() : "SUPER + F";
      data.keybindingUndo = data.keybindingUndo ? String(data.keybindingUndo).trim() : "CTRL + Z";
      data.keybindingRedo = data.keybindingRedo ? String(data.keybindingRedo).trim() : "CTRL + SHIFT + Z";
      data.keybindingSave = data.keybindingSave ? String(data.keybindingSave).trim() : "CTRL + S";
      data.keybindingCut = data.keybindingCut ? String(data.keybindingCut).trim() : "CTRL + X";
      data.keybindingReload = data.keybindingReload ? String(data.keybindingReload).trim() : "CTRL + R";
      data.keybindingSelectAddress = data.keybindingSelectAddress ? String(data.keybindingSelectAddress).trim() : "CTRL + L";

      if (data.hibernateDelay !== undefined) {
        var hd = String(data.hibernateDelay).toLowerCase().trim();
        if (hd === "1800" || hd === "1800s" || hd === "30m" || hd === "30min") data.hibernateDelay = "30min";
        else if (hd === "3600" || hd === "3600s" || hd === "60m" || hd === "1h" || hd === "1hour") data.hibernateDelay = "1hour";
        else if (hd === "7200" || hd === "7200s" || hd === "120m" || hd === "2h" || hd === "2hours") data.hibernateDelay = "2hours";
        else if (hd === "0" || hd === "off" || hd === "never") data.hibernateDelay = "off";
      }

      if (data.trackpad && typeof data.trackpad === "object") {
        data.trackpad.present = Boolean(data.trackpad.present);
        data.trackpad.device = data.trackpad.device ? String(data.trackpad.device) : "Apple Force Touch Trackpad";
        data.trackpad.naturalScroll = data.trackpad.naturalScroll !== undefined ? Boolean(data.trackpad.naturalScroll) : true;
        data.trackpad.tapToClick = data.trackpad.tapToClick !== undefined ? Boolean(data.trackpad.tapToClick) : true;
        data.trackpad.clickfingerBehavior = data.trackpad.clickfingerBehavior !== undefined ? Boolean(data.trackpad.clickfingerBehavior) : true;
        data.trackpad.disableWhileTyping = data.trackpad.disableWhileTyping !== undefined ? Boolean(data.trackpad.disableWhileTyping) : true;
        data.trackpad.middleButtonEmulation = Boolean(data.trackpad.middleButtonEmulation);
        data.trackpad.tapAndDrag = data.trackpad.tapAndDrag !== undefined ? Boolean(data.trackpad.tapAndDrag) : true;
        data.trackpad.dragLock = Boolean(data.trackpad.dragLock);
        data.trackpad.drag3fg = typeof data.trackpad.drag3fg === "number" ? Math.max(0, Math.min(3, Math.round(data.trackpad.drag3fg))) : (data.trackpad.drag3fg ? 1 : 0);
        data.trackpad.tapButtonMap = String(data.trackpad.tapButtonMap || "lrm").toLowerCase() === "lmr" ? "lmr" : "lrm";
        data.trackpad.flipX = Boolean(data.trackpad.flipX);
        data.trackpad.flipY = Boolean(data.trackpad.flipY);
        data.trackpad.leftHanded = Boolean(data.trackpad.leftHanded);
        data.trackpad.swipeWorkspaces = data.trackpad.swipeWorkspaces !== undefined ? Boolean(data.trackpad.swipeWorkspaces) : true;
        if (data.trackpad.drag3fg > 0 && data.trackpad.swipeWorkspaces) {
          data.trackpad.swipeWorkspaces = false;
        }
        data.trackpad.accelProfile = String(data.trackpad.accelProfile || "adaptive").toLowerCase() === "flat" ? "flat" : "adaptive";

        if (typeof data.trackpad.scrollFactor === "number" && !isNaN(data.trackpad.scrollFactor)) {
          data.trackpad.scrollFactor = Math.max(0.1, Math.min(2.0, Math.round(data.trackpad.scrollFactor * 100) / 100));
        } else {
          data.trackpad.scrollFactor = 0.64;
        }

        if (typeof data.trackpad.sensitivity === "number" && !isNaN(data.trackpad.sensitivity)) {
          data.trackpad.sensitivity = Math.max(-1.0, Math.min(1.0, Math.round(data.trackpad.sensitivity * 100) / 100));
        } else {
          data.trackpad.sensitivity = 0.0;
        }
      } else {
        data.trackpad = emptyStatus().trackpad;
      }

      return data;
    }
  } catch (e) {
    console.warn("OmappleModel: failed to parse status JSON:", e, raw);
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
  if (!status) return "Omapple";
  if (!status.isT2) {
    return "Omapple\nApple T2 chip not detected on this system";
  }
  var tip = "Omapple (" + (status.model || "T2 MacBook") + ")";
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

function keyEventToChord(event) {
  if (!event) return null;
  var key = event.key;
  var modifiers = event.modifiers || 0;

  var isModifierOnly = (
    key === Qt.Key_Control ||
    key === Qt.Key_Shift ||
    key === Qt.Key_Alt ||
    key === Qt.Key_AltGr ||
    key === Qt.Key_Meta ||
    key === Qt.Key_Super_L ||
    key === Qt.Key_Super_R ||
    key === Qt.Key_Hyper_L ||
    key === Qt.Key_Hyper_R
  );

  var parts = [];

  var hasCtrl = (modifiers & Qt.ControlModifier) !== 0 || key === Qt.Key_Control;
  var hasSuper = (modifiers & Qt.MetaModifier) !== 0 || key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R;
  var hasAlt = (modifiers & Qt.AltModifier) !== 0 || key === Qt.Key_Alt || key === Qt.Key_AltGr;
  var hasShift = (modifiers & Qt.ShiftModifier) !== 0 || key === Qt.Key_Shift;

  if (hasCtrl) parts.push("CTRL");
  if (hasSuper) parts.push("SUPER");
  if (hasAlt) parts.push("ALT");
  if (hasShift) parts.push("SHIFT");

  var displayParts = parts.map(function(p) { return p === "SUPER" ? "CMD" : p; });

  if (isModifierOnly) {
    return {
      complete: false,
      chord: parts.length > 0 ? parts.join(" + ") : "",
      displayChord: displayParts.length > 0 ? (displayParts.join(" + ") + " + …") : ""
    };
  }

  var keyName = "";
  if (key >= Qt.Key_A && key <= Qt.Key_Z) {
    keyName = String.fromCharCode(key);
  } else if (key >= Qt.Key_0 && key <= Qt.Key_9) {
    keyName = String.fromCharCode(key);
  } else if (key >= Qt.Key_F1 && key <= Qt.Key_F24) {
    keyName = "F" + (key - Qt.Key_F1 + 1);
  } else {
    switch (key) {
      case Qt.Key_Backspace: keyName = "BACKSPACE"; break;
      case Qt.Key_Delete: keyName = "DELETE"; break;
      case Qt.Key_Return:
      case Qt.Key_Enter: keyName = "RETURN"; break;
      case Qt.Key_Tab: keyName = "TAB"; break;
      case Qt.Key_Space: keyName = "SPACE"; break;
      case Qt.Key_Escape: keyName = "ESCAPE"; break;
      case Qt.Key_Up: keyName = "UP"; break;
      case Qt.Key_Down: keyName = "DOWN"; break;
      case Qt.Key_Left: keyName = "LEFT"; break;
      case Qt.Key_Right: keyName = "RIGHT"; break;
      case Qt.Key_Home: keyName = "HOME"; break;
      case Qt.Key_End: keyName = "END"; break;
      case Qt.Key_PageUp: keyName = "PAGEUP"; break;
      case Qt.Key_PageDown: keyName = "PAGEDOWN"; break;
      case Qt.Key_Insert: keyName = "INSERT"; break;
      case Qt.Key_Minus: keyName = "MINUS"; break;
      case Qt.Key_Equal: keyName = "EQUAL"; break;
      case Qt.Key_BracketLeft: keyName = "BRACKETLEFT"; break;
      case Qt.Key_BracketRight: keyName = "BRACKETRIGHT"; break;
      case Qt.Key_Backslash: keyName = "BACKSLASH"; break;
      case Qt.Key_Semicolon: keyName = "SEMICOLON"; break;
      case Qt.Key_Apostrophe: keyName = "APOSTROPHE"; break;
      case Qt.Key_Comma: keyName = "COMMA"; break;
      case Qt.Key_Period: keyName = "PERIOD"; break;
      case Qt.Key_Slash: keyName = "SLASH"; break;
      case Qt.Key_QuoteLeft:
      case Qt.Key_AsciiTilde: keyName = "GRAVE"; break;
      default:
        if (event.text && event.text.trim()) {
          keyName = event.text.trim().toUpperCase();
        }
        break;
    }
  }

  if (!keyName) {
    return {
      complete: false,
      chord: parts.length > 0 ? parts.join(" + ") : "",
      displayChord: displayParts.length > 0 ? (displayParts.join(" + ") + " + …") : ""
    };
  }

  parts.push(keyName);
  displayParts.push(keyName === "SUPER" ? "CMD" : keyName);
  var fullChord = parts.join(" + ");
  var fullDisplayChord = displayParts.join(" + ");
  return {
    complete: true,
    chord: fullChord,
    displayChord: fullDisplayChord
  };
}

function formatChordForDisplay(chord) {
  if (!chord) return "";
  return String(chord).replace(/\bSUPER\b/g, "CMD").replace(/\bSuper\b/g, "Cmd");
}

function normalizeChord(chord) {
  if (!chord) return "";
  var tokens = String(chord).split(/[\+\s]+/).filter(function(t) { return t.length > 0; });
  var mods = [];
  var key = "";
  for (var i = 0; i < tokens.length; i++) {
    var t = tokens[i].toUpperCase();
    if (t === "SUPER" || t === "CMD" || t === "COMMAND" || t === "WIN" || t === "LOGO" || t === "META") {
      if (mods.indexOf("SUPER") === -1) mods.push("SUPER");
    } else if (t === "CTRL" || t === "CONTROL") {
      if (mods.indexOf("CTRL") === -1) mods.push("CTRL");
    } else if (t === "ALT" || t === "OPTION") {
      if (mods.indexOf("ALT") === -1) mods.push("ALT");
    } else if (t === "SHIFT") {
      if (mods.indexOf("SHIFT") === -1) mods.push("SHIFT");
    } else {
      key = t;
    }
  }
  mods.sort();
  if (key) mods.push(key);
  return mods.join(" + ");
}

function getTaskFriendlyName(taskKey) {
  var key = String(taskKey || "").toLowerCase().replace(/_/g, "");
  if (key === "keybindingselectall") return "Select All";
  if (key === "keybindingdelete") return "Forward Delete";
  if (key === "keybindingfind") return "Find in Document";
  if (key === "keybindingfullscreen") return "Toggle Fullscreen";
  if (key === "keybindingundo") return "Undo";
  if (key === "keybindingredo") return "Redo";
  if (key === "keybindingsave") return "Save";
  if (key === "keybindingcut") return "Cut";
  if (key === "keybindingreload") return "Reload";
  if (key === "keybindingselectaddress") return "Select Address";
  return taskKey || "Keybinding";
}

function getRecommendedAlternative(taskKey, conflictingChord) {
  var norm = normalizeChord(conflictingChord);
  var key = String(taskKey || "").toLowerCase().replace(/_/g, "");
  if (key === "keybindingfullscreen") {
    return (norm === normalizeChord("SUPER + F")) ? "SUPER + CTRL + F" : "SUPER + F";
  }
  if (key === "keybindingfind") {
    return (norm === normalizeChord("SUPER + F")) ? "CTRL + F" : "SUPER + F";
  }
  if (key === "keybindingselectall") {
    return (norm === normalizeChord("SUPER + A")) ? "CTRL + A" : "SUPER + A";
  }
  if (key === "keybindingdelete") {
    return (norm === normalizeChord("SUPER + BACKSPACE")) ? "DELETE" : "SUPER + BACKSPACE";
  }
  if (key === "keybindingundo") {
    return (norm === normalizeChord("SUPER + Z")) ? "CTRL + Z" : "SUPER + Z";
  }
  if (key === "keybindingredo") {
    return (norm === normalizeChord("SUPER + SHIFT + Z")) ? "CTRL + SHIFT + Z" : "SUPER + SHIFT + Z";
  }
  if (key === "keybindingsave") {
    return (norm === normalizeChord("SUPER + S")) ? "CTRL + S" : "SUPER + S";
  }
  if (key === "keybindingcut") {
    return (norm === normalizeChord("SUPER + X")) ? "CTRL + X" : "SUPER + X";
  }
  if (key === "keybindingreload") {
    return (norm === normalizeChord("SUPER + R")) ? "CTRL + R" : "SUPER + R";
  }
  if (key === "keybindingselectaddress") {
    return (norm === normalizeChord("SUPER + L")) ? "CTRL + L" : "SUPER + L";
  }
  return "";
}

function findPluginConflict(targetTaskKey, newChord, currentStatus) {
  var tasks = [
    { key: "keybinding_select_all", name: "Select All", chord: (currentStatus && currentStatus.keybindingSelectAll) ? currentStatus.keybindingSelectAll : "CTRL + A" },
    { key: "keybinding_delete", name: "Forward Delete", chord: (currentStatus && currentStatus.keybindingDelete) ? currentStatus.keybindingDelete : "DELETE" },
    { key: "keybinding_find", name: "Find in Document", chord: (currentStatus && currentStatus.keybindingFind) ? currentStatus.keybindingFind : "CTRL + F" },
    { key: "keybinding_fullscreen", name: "Toggle Fullscreen", chord: (currentStatus && currentStatus.keybindingFullscreen) ? currentStatus.keybindingFullscreen : "SUPER + F" },
    { key: "keybinding_undo", name: "Undo", chord: (currentStatus && currentStatus.keybindingUndo) ? currentStatus.keybindingUndo : "CTRL + Z" },
    { key: "keybinding_redo", name: "Redo", chord: (currentStatus && currentStatus.keybindingRedo) ? currentStatus.keybindingRedo : "CTRL + SHIFT + Z" },
    { key: "keybinding_save", name: "Save", chord: (currentStatus && currentStatus.keybindingSave) ? currentStatus.keybindingSave : "CTRL + S" },
    { key: "keybinding_cut", name: "Cut", chord: (currentStatus && currentStatus.keybindingCut) ? currentStatus.keybindingCut : "CTRL + X" },
    { key: "keybinding_reload", name: "Reload", chord: (currentStatus && currentStatus.keybindingReload) ? currentStatus.keybindingReload : "CTRL + R" },
    { key: "keybinding_select_address", name: "Select Address", chord: (currentStatus && currentStatus.keybindingSelectAddress) ? currentStatus.keybindingSelectAddress : "CTRL + L" }
  ];

  var normTarget = normalizeChord(newChord);
  if (!normTarget) return null;

  var normTargetKey = String(targetTaskKey || "").toLowerCase().replace(/_/g, "");

  for (var i = 0; i < tasks.length; i++) {
    var t = tasks[i];
    var normTKey = t.key.toLowerCase().replace(/_/g, "");
    if (normTKey !== normTargetKey) {
      if (normalizeChord(t.chord) === normTarget) {
        return t;
      }
    }
  }
  return null;
}

function findSystemConflict(targetTaskKey, newChord, currentStatus) {
  if (!newChord || !currentStatus) return null;
  var normTarget = normalizeChord(newChord);
  if (!normTarget) return null;

  var friendly = getTaskFriendlyName(targetTaskKey).toLowerCase().replace(/\s+/g, '');
  var overrides = currentStatus.systemKeybindingOverrides || {};
  var systemMap = currentStatus.systemKeybindings || {};

  // 1. Check active overrides
  var overrideKeys = Object.keys(overrides);
  for (var i = 0; i < overrideKeys.length; i++) {
    var oItem = overrides[overrideKeys[i]];
    if (oItem && oItem.currentChord && normalizeChord(oItem.currentChord) === normTarget) {
      var actNorm = String(oItem.action || "").toLowerCase().replace(/\s+/g, '');
      var isCutMatch = (actNorm === "universalcut" && friendly === "cut");
      if (actNorm !== friendly && !isCutMatch) {
        return {
          isSystem: true,
          action: oItem.action,
          name: oItem.action,
          defaultChord: oItem.defaultChord,
          currentChord: oItem.currentChord,
          recommendedChord: oItem.recommendedChord || ("SUPER + ALT + " + normTarget.split("+").pop().trim()),
          dispatcher: oItem.dispatcher || "exec",
          arg: oItem.arg || ""
        };
      }
    }
  }

  // 2. Check system defaults
  var systemKeys = Object.keys(systemMap);
  for (var j = 0; j < systemKeys.length; j++) {
    var sKey = systemKeys[j];
    if (normalizeChord(sKey) === normTarget) {
      var sItem = systemMap[sKey];
      var sAct = sItem.action || "";
      var actNorm2 = sAct.toLowerCase().replace(/\s+/g, '');
      // If this action was already overridden to something else, its default chord is free
      if (overrides[sAct] && normalizeChord(overrides[sAct].currentChord) !== normTarget) {
        continue;
      }
      // If this is the plugin task's own counterpart, ignore
      if (actNorm2 === friendly || (actNorm2 === "fullscreen" && friendly === "togglefullscreen") || (actNorm2 === "find" && friendly === "findindocument") || (actNorm2 === "selectall" && friendly === "selectall") || (actNorm2 === "undo" && friendly === "undo") || (actNorm2 === "redo" && friendly === "redo") || (actNorm2 === "save" && friendly === "save") || (actNorm2 === "delete" && friendly === "forwarddelete") || (actNorm2 === "universalcut" && friendly === "cut") || (actNorm2 === "reload" && friendly === "reload") || (actNorm2 === "selectaddress" && friendly === "selectaddress") || (actNorm2 === "focusaddressbar" && friendly === "selectaddress") || (actNorm2 === "selectaddressbar" && friendly === "selectaddress")) {
        continue;
      }
      return {
        isSystem: true,
        action: sAct,
        name: sAct,
        defaultChord: sItem.defaultChord || sKey,
        currentChord: sItem.defaultChord || sKey,
        recommendedChord: sItem.recommendedChord || ("SUPER + ALT + " + normTarget.split("+").pop().trim()),
        dispatcher: sItem.dispatcher || "exec",
        arg: sItem.arg || ""
      };
    }
  }
  return null;
}

function getSystemOverridesList(status) {
  if (!status || !status.systemKeybindingOverrides) return [];
  var res = [];
  var keys = Object.keys(status.systemKeybindingOverrides);
  for (var i = 0; i < keys.length; i++) {
    var item = status.systemKeybindingOverrides[keys[i]];
    if (item && item.action) {
      res.push(item);
    }
  }
  return res;
}

function getActiveConflicts(status) {
  if (!status) return [];
  var conflicts = [];
  var seen = {};

  var tasks = [
    { key: "keybinding_select_all", prop: "keybindingSelectAll", name: "Select All", chord: (status && status.keybindingSelectAll) ? status.keybindingSelectAll : "CTRL + A" },
    { key: "keybinding_delete", prop: "keybindingDelete", name: "Forward Delete", chord: (status && status.keybindingDelete) ? status.keybindingDelete : "DELETE" },
    { key: "keybinding_find", prop: "keybindingFind", name: "Find in Document", chord: (status && status.keybindingFind) ? status.keybindingFind : "CTRL + F" },
    { key: "keybinding_fullscreen", prop: "keybindingFullscreen", name: "Toggle Fullscreen", chord: (status && status.keybindingFullscreen) ? status.keybindingFullscreen : "SUPER + F" },
    { key: "keybinding_undo", prop: "keybindingUndo", name: "Undo", chord: (status && status.keybindingUndo) ? status.keybindingUndo : "CTRL + Z" },
    { key: "keybinding_redo", prop: "keybindingRedo", name: "Redo", chord: (status && status.keybindingRedo) ? status.keybindingRedo : "CTRL + SHIFT + Z" },
    { key: "keybinding_save", prop: "keybindingSave", name: "Save", chord: (status && status.keybindingSave) ? status.keybindingSave : "CTRL + S" },
    { key: "keybinding_cut", prop: "keybindingCut", name: "Cut", chord: (status && status.keybindingCut) ? status.keybindingCut : "CTRL + X" },
    { key: "keybinding_reload", prop: "keybindingReload", name: "Reload", chord: (status && status.keybindingReload) ? status.keybindingReload : "CTRL + R" },
    { key: "keybinding_select_address", prop: "keybindingSelectAddress", name: "Select Address", chord: (status && status.keybindingSelectAddress) ? status.keybindingSelectAddress : "CTRL + L" }
  ];

  // 1. Check pairwise intra-plugin conflicts
  for (var i = 0; i < tasks.length; i++) {
    for (var j = i + 1; j < tasks.length; j++) {
      var t1 = tasks[i];
      var t2 = tasks[j];
      var norm1 = normalizeChord(t1.chord);
      var norm2 = normalizeChord(t2.chord);
      if (norm1 && norm1 === norm2) {
        var pairKey = [t1.key, t2.key].sort().join("::");
        if (!seen[pairKey]) {
          seen[pairKey] = true;
          conflicts.push({
            chord: t1.chord,
            source: "plugin",
            action1: t1.name,
            taskKey1: t1.key,
            chord1: t1.chord,
            action2: t2.name,
            taskKey2: t2.key,
            chord2: t2.chord,
            defaultChord: t2.chord,
            recommendedChord: getRecommendedAlternative(t2.key, t1.chord)
          });
        }
      }
    }
  }

  // 2. Check plugin tasks vs system keybindings
  var overrides = status.systemKeybindingOverrides || {};
  var systemMap = status.systemKeybindings || {};
  var pluginActionNorms = ["togglefullscreen", "fullscreen", "findindocument", "find", "selectall", "undo", "redo", "save", "forwarddelete", "delete", "cut", "universalcut", "reload", "selectaddress", "focusaddressbar", "selectaddressbar"];

  for (var k = 0; k < tasks.length; k++) {
    var task = tasks[k];
    var normT = normalizeChord(task.chord);
    if (!normT) continue;

    // Check system defaults
    var sysKeys = Object.keys(systemMap);
    for (var s = 0; s < sysKeys.length; s++) {
      var sChord = sysKeys[s];
      if (normalizeChord(sChord) === normT) {
        var sItem = systemMap[sChord];
        var sAct = sItem.action || "";
        var sActNorm = sAct.toLowerCase().replace(/\s+/g, "");

        if (pluginActionNorms.indexOf(sActNorm) !== -1) continue;
        if (overrides[sAct] && normalizeChord(overrides[sAct].currentChord) !== normT) continue;

        var cKey = task.key + "::system::" + sAct;
        if (!seen[cKey]) {
          seen[cKey] = true;
          conflicts.push({
            chord: task.chord,
            source: "system",
            action1: task.name,
            taskKey1: task.key,
            chord1: task.chord,
            action2: sAct,
            taskKey2: sAct,
            chord2: sChord,
            defaultChord: sItem.defaultChord || sChord,
            recommendedChord: sItem.recommendedChord || ("SUPER + ALT + " + normT.split("+").pop().trim()),
            dispatcher: sItem.dispatcher || "exec",
            arg: sItem.arg || ""
          });
        }
      }
    }

    // Check active overrides
    var oKeys = Object.keys(overrides);
    for (var o = 0; o < oKeys.length; o++) {
      var oItem = overrides[oKeys[o]];
      if (oItem && oItem.currentChord && normalizeChord(oItem.currentChord) === normT) {
        var oAct = oItem.action || "";
        var oActNorm = oAct.toLowerCase().replace(/\s+/g, "");
        if (pluginActionNorms.indexOf(oActNorm) !== -1) continue;

        var cKeyO = task.key + "::override::" + oAct;
        if (!seen[cKeyO]) {
          seen[cKeyO] = true;
          conflicts.push({
            chord: task.chord,
            source: "system",
            action1: task.name,
            taskKey1: task.key,
            chord1: task.chord,
            action2: oAct,
            taskKey2: oAct,
            chord2: oItem.currentChord,
            defaultChord: oItem.defaultChord || oItem.currentChord,
            recommendedChord: oItem.recommendedChord || ("SUPER + ALT + " + normT.split("+").pop().trim()),
            dispatcher: oItem.dispatcher || "exec",
            arg: oItem.arg || ""
          });
        }
      }
    }
  }

  return conflicts;
}

function areAllMacShortcutsApplied(status) {
  if (!status) return false;
  var sel = normalizeChord(status.keybindingSelectAll);
  var del = normalizeChord(status.keybindingDelete);
  var find = normalizeChord(status.keybindingFind);
  var full = normalizeChord(status.keybindingFullscreen);
  var undo = normalizeChord(status.keybindingUndo);
  var redo = normalizeChord(status.keybindingRedo);
  var save = normalizeChord(status.keybindingSave);
  var cut = normalizeChord(status.keybindingCut);
  var reload = normalizeChord(status.keybindingReload);
  var selectAddress = normalizeChord(status.keybindingSelectAddress);

  return (
    sel === normalizeChord("SUPER + A") &&
    del === normalizeChord("SUPER + BACKSPACE") &&
    find === normalizeChord("SUPER + F") &&
    full === normalizeChord("SUPER + CTRL + F") &&
    undo === normalizeChord("SUPER + Z") &&
    redo === normalizeChord("SUPER + SHIFT + Z") &&
    save === normalizeChord("SUPER + S") &&
    cut === normalizeChord("SUPER + X") &&
    reload === normalizeChord("SUPER + R") &&
    selectAddress === normalizeChord("SUPER + L")
  );
}

function areAllSuspendRecommendedApplied(status) {
  if (!status) return false;
  var mem = String(status.memSleep || "").toLowerCase();
  var lid = String(status.lidAction || "").toLowerCase();
  var clam = Boolean(status.clamshellMode);
  var wakeLid = Boolean(status.wakeOnLid);
  var wakeAc = Boolean(status.wakeOnAc);
  var hib = String(status.hibernateDelay || "").toLowerCase();
  var tb = Boolean(status.touchbarBlank);

  var memOk = true;
  if (status.memSleepModes && status.memSleepModes.indexOf("deep") !== -1) {
    memOk = (mem === "deep");
  }

  return (
    memOk &&
    (lid === "suspend" || lid === "suspend-then-hibernate") &&
    clam === true &&
    wakeLid === true &&
    wakeAc === false &&
    (hib === "off" || hib === "0" || hib === "never") &&
    tb === true
  );
}

function areAllBatteryRecommendedApplied(status) {
  if (!status) return false;
  var wifi = Boolean(status.wifiPowerSave);
  var audio = Boolean(status.audioPowerSave);
  var usb = Boolean(status.usbAutosuspend);
  var pcie = Boolean(status.pciePortsCompat);
  var kbd = String(status.kbdTimeout || "").toLowerCase();

  var ethOk = true;
  if (Array.isArray(status.inactiveEthernet) && status.inactiveEthernet.length > 0) {
    for (var i = 0; i < status.inactiveEthernet.length; i++) {
      if (status.inactiveEthernet[i].managed) {
        ethOk = false;
        break;
      }
    }
  }

  return (
    wifi === false &&
    audio === true &&
    usb === true &&
    (status.isT2 ? pcie === true : true) &&
    kbd === "1m" &&
    ethOk
  );
}

function areAllRecommendedApplied(status) {
  if (!status) return false;
  return (
    areAllBatteryRecommendedApplied(status) &&
    areAllSuspendRecommendedApplied(status) &&
    areAllTrackpadRecommendedApplied(status) &&
    areAllMacShortcutsApplied(status)
  );
}

function areAllEthernetUnmanaged(status) {
  if (!status || !Array.isArray(status.inactiveEthernet) || status.inactiveEthernet.length === 0) return true;
  for (var i = 0; i < status.inactiveEthernet.length; i++) {
    if (status.inactiveEthernet[i].managed) return false;
  }
  return true;
}

function areAllT2FixesApplied(status) {
  if (!status) return false;
  return Boolean(status.pciePortsCompat) && areAllEthernetUnmanaged(status);
}

function areAllTrackpadRecommendedApplied(status) {
  if (!status || !status.trackpad) return false;
  var tp = status.trackpad;
  return Boolean(
    tp.naturalScroll &&
    tp.tapToClick &&
    tp.clickfingerBehavior &&
    tp.disableWhileTyping &&
    Math.abs(Number(tp.scrollFactor) - 0.64) < 0.01 &&
    tp.drag3fg === 0 &&
    tp.tapAndDrag &&
    !tp.dragLock &&
    !tp.middleButtonEmulation &&
    tp.tapButtonMap === "lrm" &&
    Math.abs(Number(tp.sensitivity) - 0.0) < 0.01 &&
    tp.accelProfile === "adaptive" &&
    !tp.leftHanded &&
    !tp.flipX &&
    !tp.flipY &&
    tp.swipeWorkspaces
  );
}

function speedPercentFromSensitivity(sensitivity) {
  var s = Number(sensitivity);
  if (!isFinite(s)) s = 0.0;
  return Math.round(Math.max(0, Math.min(100, (s + 1.0) * 50)));
}

function sensitivityFromSpeedPercent(percent) {
  var p = Number(percent);
  if (!isFinite(p)) p = 50;
  var clamped = Math.max(0, Math.min(100, p));
  return Math.round(((clamped / 50.0) - 1.0) * 100) / 100;
}

function scrollPercentFromFactor(factor) {
  var f = Number(factor);
  if (!isFinite(f)) f = 0.64;
  var clamped = Math.max(0.1, Math.min(2.0, f));
  return Math.round(((clamped - 0.1) / 1.9) * 100);
}

function factorFromScrollPercent(percent) {
  var p = Number(percent);
  if (!isFinite(p)) p = 50;
  var clamped = Math.max(0, Math.min(100, p));
  return Math.round((0.1 + (clamped / 100.0) * 1.9) * 100) / 100;
}

function formatAccelProfile(profile) {
  var p = String(profile || "").toLowerCase().trim();
  if (p === "flat") return "Flat";
  return "Adaptive";
}

function formatTapButtonMap(map) {
  var m = String(map || "").toLowerCase().trim();
  if (m === "lmr") return "LMR (X11 Standard)";
  return "LRM (Mac Default)";
}

