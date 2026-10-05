import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "OmappleModel.js" as Model

BarWidget {
  id: root
  moduleName: "bramvanoploo.omarchy-t2-linux"

  property bool opened: false
  property var status: Model.emptyStatus()
  property int activeTab: 0
  readonly property string currentTabId: (tabs && tabs[activeTab] ? tabs[activeTab].id : "battery")
  property bool applying: false
  property string lastNotice: ""
  property bool limineUpdating: false
  property bool rebootConfirmOpen: false
  property bool recommendedConfirmOpen: false
  property bool t2FixesConfirmOpen: false
  property bool openedViaBarButton: false
  property bool keyRecorderOpen: false
  property string keyRecorderTaskKey: ""
  property string keyRecorderTaskName: ""
  property string keyRecorderRecordedChord: ""
  property string keyRecorderDisplayChord: ""
  property bool keyRecorderComplete: false
  property bool keyRecorderChecking: false
  property bool keyRecorderConflict: false
  property string keyRecorderConflictAction: ""
  property bool conflictDialogOpen: false
  property string conflictTargetTaskKey: ""
  property string conflictTargetTaskName: ""
  property string conflictTargetChord: ""
  property string conflictDisplacedTaskKey: ""
  property string conflictDisplacedTaskName: ""
  property string conflictDisplacedChord: ""
  property string conflictRecommendedChord: ""
  property bool conflictIsSystem: false
  property string conflictSystemAction: ""
  property string conflictSystemDispatcher: ""
  property string conflictSystemArg: ""
  property string pendingConflictSystemAction: ""
  property string pendingConflictSystemDefaultChord: ""
  property string pendingConflictSystemDispatcher: ""
  property string pendingConflictSystemArg: ""
  property string pendingConflictTargetTaskKey: ""
  property string pendingConflictTargetChord: ""

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helper: pluginDir + "/scripts/omapple-helper"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color hairline: Util.alpha(foreground, 0.12)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var tabs: [
    { id: "battery", title: "Battery life", icon: "󰁹", desc: "Energy & power settings" },
    { id: "suspend", title: "Suspend behaviour", icon: "󰤄", desc: "Sleep states & lid actions" },
    { id: "keybindings", title: "Keybindings", icon: "󰌘", desc: "Keyboard shortcuts & layout" },
    { id: "trackpad", title: "Trackpad", icon: "󱑣", desc: "Pointer & gesture controls" },
    // { id: "sound", title: "Sound", icon: "󰕾", desc: "Audio devices & configuration" }, // Hidden for now
    { id: "plugins", title: "Plugins", icon: "󰏓", desc: "Apple community plugins" }
  ]

  property var pluginList: []
  property bool pluginsLoading: false
  property string pluginActionStatus: ""
  property string activePluginOpId: ""
  property string pluginFilterQuery: ""
  property int pluginFilterMode: 0 // 0: All Apple Plugins, 1: Installed
  property bool filterT2Only: false

  readonly property var filteredPlugins: {
    var list = root.pluginList || []
    if (root.filterT2Only && root.status && root.status.isT2) {
      list = list.filter(function(p) { return Boolean(p && (p.isT2 || p.isExactT2)) })
    }
    if (root.pluginFilterMode === 1) {
      list = list.filter(function(p) { return Boolean(p && p.installed) })
    }
    if (root.pluginFilterQuery && root.pluginFilterQuery.trim() !== "") {
      var q = root.pluginFilterQuery.trim().toLowerCase()
      list = list.filter(function(p) {
        if (!p) return false
        return (p.name && p.name.toLowerCase().indexOf(q) !== -1) ||
               (p.id && p.id.toLowerCase().indexOf(q) !== -1) ||
               (p.description && p.description.toLowerCase().indexOf(q) !== -1) ||
               (p.author && p.author.toLowerCase().indexOf(q) !== -1)
      })
    }
    return list
  }

  function refresh() {
    if (statusProc.running) return
    statusProc.command = ["bash", helper, "status"]
    statusProc.running = true
  }

  function applyStatus(raw) {
    if (!raw || typeof raw !== "string" || !raw.trim()) return
    var parsed = Model.parseStatus(raw)
    if (parsed) {
      status = parsed
      if (root.opened && root.openedViaBarButton && parsed.isT2 && !Model.areAllT2FixesApplied(parsed) && !root.limineUpdating && !root.rebootConfirmOpen) {
        root.t2FixesConfirmOpen = true
      } else if (root.opened && parsed.isT2 && !parsed.recommendedPromptShown && !root.limineUpdating && !root.rebootConfirmOpen && !root.t2FixesConfirmOpen) {
        root.recommendedConfirmOpen = true
      }
    }
  }

  function applyPlugins(raw) {
    if (!raw || typeof raw !== "string" || !raw.trim()) return
    try {
      var parsed = JSON.parse(raw)
      if (parsed && parsed.plugins) {
        root.pluginList = parsed.plugins
      }
    } catch (e) {
      console.warn("Plugins JSON parse error:", e)
    }
  }

  function handleBarIconClick() {
    if (!root.opened) {
      root.openedViaBarButton = true
      root.open()
      if (root.status && root.status.isT2 && !Model.areAllT2FixesApplied(root.status) && !root.limineUpdating && !root.rebootConfirmOpen) {
        root.t2FixesConfirmOpen = true
      }
    } else {
      root.close()
    }
  }

  function toggle() {
    opened ? close() : open()
  }

  function open() {
    opened = true
    refresh()
    if (root.tabs[root.activeTab] && root.tabs[root.activeTab].id === "plugins") {
      fetchPlugins(true)
    } else {
      fetchPlugins(false)
    }
  }

  function close() {
    if (root.limineUpdating) return
    opened = false
    openedViaBarButton = false
    t2FixesConfirmOpen = false
  }

  function togglePciePortsCompat(enable) {
    if (root.limineUpdating) return
    root.limineUpdating = true
    if (root.status) {
      var s = Object.assign({}, root.status)
      s.pciePortsCompat = enable
      root.status = s
    }
    noticeTimer.stop()
    root.lastNotice = "Updating Limine boot configuration (limine-update)…"
    limineProc.command = ["bash", helper, "set", "pcie_ports_compat", enable ? "on" : "off"]
    limineProc.running = true
  }

  function setMemSleep(mode) {
    if (root.limineUpdating) return
    root.limineUpdating = true
    if (root.status) {
      var s = Object.assign({}, root.status)
      s.memSleep = mode
      root.status = s
    }
    noticeTimer.stop()
    root.lastNotice = "Updating Limine boot configuration (limine-update)…"
    limineProc.command = ["bash", helper, "set", "mem_sleep", mode]
    limineProc.running = true
  }

  function applyT2Fixes() {
    t2FixesConfirmOpen = false
    if (root.limineUpdating || limineProc.running || actionProc.running) return

    var pcieAlreadyApplied = Boolean(root.status && root.status.pciePortsCompat)
    var ethAlreadyApplied = Model.areAllEthernetUnmanaged(root.status)

    if (pcieAlreadyApplied && ethAlreadyApplied) {
      noticeTimer.stop()
      root.lastNotice = "All T2 fixes are already applied."
      noticeTimer.restart()
      return
    }

    if (root.status) {
      var s = Object.assign({}, root.status)
      if (!pcieAlreadyApplied) {
        s.pciePortsCompat = true
      }
      if (!ethAlreadyApplied && s.inactiveEthernet) {
        s.inactiveEthernet = s.inactiveEthernet.map(function(item) {
          return { device: item.device, managed: false, state: "unmanaged" }
        })
      }
      root.status = s
    }

    noticeTimer.stop()

    if (!pcieAlreadyApplied) {
      root.limineUpdating = true
      root.lastNotice = "Applying T2 fixes (updating Limine boot configuration)…"
      if (ethAlreadyApplied) {
        limineProc.command = ["bash", helper, "apply-t2-fixes", "--skip-eth"]
      } else {
        limineProc.command = ["bash", helper, "apply-t2-fixes"]
      }
      limineProc.running = true
    } else {
      if (actionProc.running) actionProc.running = false
      root.applying = true
      root.lastNotice = "Applying T2 ethernet fixes…"
      actionProc.command = ["bash", helper, "apply-t2-fixes", "--skip-pcie"]
      actionProc.running = true
    }
  }

  function applyRecommendedOptions() {
    recommendedConfirmOpen = false
    if (root.limineUpdating) return

    if (root.status && Model.areAllRecommendedApplied(root.status)) {
      root.lastNotice = "All recommended options are already applied."
      noticeTimer.restart()
      return
    }

    var memNeedsUpdate = Boolean(root.status && root.status.memSleepModes && root.status.memSleepModes.indexOf("deep") !== -1 && root.status.memSleep !== "deep")
    var pcieNeedsUpdate = Boolean(root.status && root.status.isT2 && !root.status.pciePortsCompat)

    if (root.status) {
      var s = Object.assign({}, root.status)
      s.memSleep = "deep"
      s.lidAction = "suspend"
      s.clamshellMode = true
      s.wakeOnLid = true
      s.wakeOnAc = false
      s.hibernateDelay = "off"
      s.touchbarBlank = true
      s.wifiPowerSave = false
      s.audioPowerSave = true
      s.usbAutosuspend = true
      s.kbdTimeout = "1m"
      if (s.isT2) s.pciePortsCompat = true
      s.recommendedPromptShown = true
      s.keybindingSelectAll = "SUPER + A"
      s.keybindingDelete = "SUPER + BACKSPACE"
      s.keybindingFind = "SUPER + F"
      s.keybindingFullscreen = "SUPER + CTRL + F"
      s.keybindingUndo = "SUPER + Z"
      s.keybindingRedo = "SUPER + SHIFT + Z"
      s.keybindingSave = "SUPER + S"
      s.keybindingCut = "SUPER + X"

      var tp = Object.assign({}, s.trackpad || Model.emptyStatus().trackpad)
      tp.naturalScroll = true
      tp.tapToClick = true
      tp.clickfingerBehavior = true
      tp.disableWhileTyping = true
      tp.scrollFactor = 0.64
      tp.middleButtonEmulation = false
      tp.tapAndDrag = true
      tp.dragLock = false
      tp.drag3fg = 0
      tp.tapButtonMap = "lrm"
      tp.flipX = false
      tp.flipY = false
      tp.sensitivity = 0.0
      tp.accelProfile = "adaptive"
      tp.leftHanded = false
      tp.swipeWorkspaces = true
      s.trackpad = tp

      var ov = Object.assign({}, s.systemKeybindingOverrides || {})
      var recChords = ["SUPER + A", "SUPER + BACKSPACE", "SUPER + F", "SUPER + CTRL + F", "SUPER + Z", "SUPER + SHIFT + Z", "SUPER + S", "SUPER + X"]
      var recTaskNames = ["selectall", "forwarddelete", "delete", "find", "findindocument", "fullscreen", "togglefullscreen", "undo", "redo", "save", "cut", "universalcut"]
      if (s.systemKeybindings) {
        for (var rc = 0; rc < recChords.length; rc++) {
          var rNorm = Model.normalizeChord(recChords[rc])
          var sysKeys = Object.keys(s.systemKeybindings)
          for (var sk = 0; sk < sysKeys.length; sk++) {
            var sysChord = sysKeys[sk]
            if (Model.normalizeChord(sysChord) === rNorm) {
              var sItem = s.systemKeybindings[sysChord]
              var sAct = sItem.action || ""
              var sActNorm = sAct.toLowerCase().replace(/\s+/g, "")
              if (recTaskNames.indexOf(sActNorm) === -1) {
                var recAlt = sItem.recommendedChord || ("SUPER + ALT + " + rNorm.split("+").pop().trim())
                ov[sAct] = {
                  action: sAct,
                  defaultChord: sItem.defaultChord || sysChord,
                  currentChord: recAlt,
                  recommendedChord: recAlt,
                  dispatcher: sItem.dispatcher || "exec",
                  arg: sItem.arg || ""
                }
              }
            }
          }
        }
      }
      s.systemKeybindingOverrides = ov

      if (s.inactiveEthernet) {
        s.inactiveEthernet = s.inactiveEthernet.map(function(item) {
          return { device: item.device, managed: false, state: "unmanaged" }
        })
      }
      root.status = s
    }

    noticeTimer.stop()
    root.lastNotice = "Applying recommended power, suspend, trackpad, and keybinding settings…"
    if (memNeedsUpdate || pcieNeedsUpdate) {
      root.limineUpdating = true
      limineProc.command = ["bash", helper, "apply-recommended"]
      limineProc.running = true
    } else {
      if (actionProc.running) actionProc.running = false
      root.applying = true
      actionProc.command = ["bash", helper, "apply-recommended", "--skip-limine"]
      actionProc.running = true
    }
  }

  function applyRecommendedSuspend() {
    if (root.limineUpdating || limineProc.running) return
    noticeTimer.stop()

    if (root.status && Model.areAllSuspendRecommendedApplied(root.status)) {
      root.lastNotice = "Recommended suspend settings are already applied."
      noticeTimer.restart()
      return
    }

    var memNeedsUpdate = Boolean(root.status && root.status.memSleepModes && root.status.memSleepModes.indexOf("deep") !== -1 && root.status.memSleep !== "deep")

    if (root.status) {
      var s = Object.assign({}, root.status)
      if (s.memSleepModes && s.memSleepModes.indexOf("deep") !== -1) {
        s.memSleep = "deep"
      }
      s.lidAction = "suspend"
      s.clamshellMode = true
      s.wakeOnLid = true
      s.wakeOnAc = false
      s.hibernateDelay = "off"
      s.touchbarBlank = true
      root.status = s
    }

    root.lastNotice = "Applying recommended suspend settings…"
    if (memNeedsUpdate) {
      root.limineUpdating = true
      limineProc.command = ["bash", helper, "apply-recommended-suspend"]
      limineProc.running = true
    } else {
      if (actionProc.running) actionProc.running = false
      root.applying = true
      actionProc.command = ["bash", helper, "apply-recommended-suspend", "--skip-limine"]
      actionProc.running = true
    }
  }

  function resetSuspendToDefaults() {
    if (root.limineUpdating || limineProc.running) return
    root.limineUpdating = true
    noticeTimer.stop()

    if (root.status) {
      var s = Object.assign({}, root.status)
      if (s.memSleepModes && s.memSleepModes.indexOf("s2idle") !== -1) {
        s.memSleep = "s2idle"
      }
      s.lidAction = "suspend"
      s.clamshellMode = false
      s.wakeOnLid = false
      s.wakeOnAc = true
      s.hibernateDelay = "off"
      s.touchbarBlank = false
      root.status = s
    }

    root.lastNotice = "Restoring suspend settings to defaults…"
    limineProc.command = ["bash", helper, "reset-suspend-to-defaults"]
    limineProc.running = true
  }

  function applyRecommendedBattery() {
    if (root.limineUpdating || limineProc.running) return
    noticeTimer.stop()

    if (root.status && Model.areAllBatteryRecommendedApplied(root.status)) {
      root.lastNotice = "Recommended battery settings are already applied."
      noticeTimer.restart()
      return
    }

    var pcieNeedsUpdate = Boolean(root.status && root.status.isT2 && !root.status.pciePortsCompat)

    if (root.status) {
      var s = Object.assign({}, root.status)
      s.wifiPowerSave = false
      s.audioPowerSave = true
      s.usbAutosuspend = true
      if (s.isT2) s.pciePortsCompat = true
      s.kbdTimeout = "1m"
      if (s.inactiveEthernet) {
        s.inactiveEthernet = s.inactiveEthernet.map(function(item) {
          return { device: item.device, managed: false, state: "unmanaged" }
        })
      }
      root.status = s
    }

    root.lastNotice = "Applying recommended battery life settings…"
    if (pcieNeedsUpdate) {
      root.limineUpdating = true
      limineProc.command = ["bash", helper, "apply-recommended-battery"]
      limineProc.running = true
    } else {
      if (actionProc.running) actionProc.running = false
      root.applying = true
      actionProc.command = ["bash", helper, "apply-recommended-battery", "--skip-limine"]
      actionProc.running = true
    }
  }

  function resetBatteryToDefaults() {
    if (root.limineUpdating || limineProc.running) return
    root.limineUpdating = true
    noticeTimer.stop()

    if (root.status) {
      var s = Object.assign({}, root.status)
      s.wifiPowerSave = true
      s.audioPowerSave = false
      s.usbAutosuspend = false
      s.pciePortsCompat = false
      s.kbdTimeout = "off"
      if (s.inactiveEthernet) {
        s.inactiveEthernet = s.inactiveEthernet.map(function(item) {
          return { device: item.device, managed: true, state: "managed" }
        })
      }
      root.status = s
    }

    root.lastNotice = "Restoring battery settings to defaults…"
    limineProc.command = ["bash", helper, "reset-battery-to-defaults"]
    limineProc.running = true
  }

  function applyRecommendedTrackpad() {
    noticeTimer.stop()
    if (root.status && Model.areAllTrackpadRecommendedApplied(root.status)) {
      root.lastNotice = "Recommended trackpad settings are already applied."
      noticeTimer.restart()
      return
    }
    if (root.status) {
      var s = Object.assign({}, root.status)
      var tp = Object.assign({}, s.trackpad || Model.emptyStatus().trackpad)
      tp.naturalScroll = true
      tp.tapToClick = true
      tp.clickfingerBehavior = true
      tp.disableWhileTyping = true
      tp.scrollFactor = 0.64
      tp.middleButtonEmulation = false
      tp.tapAndDrag = true
      tp.dragLock = false
      tp.drag3fg = 0
      tp.tapButtonMap = "lrm"
      tp.flipX = false
      tp.flipY = false
      tp.sensitivity = 0.0
      tp.accelProfile = "adaptive"
      tp.leftHanded = false
      tp.swipeWorkspaces = true
      s.trackpad = tp
      root.status = s
    }
    root.lastNotice = "Applying recommended trackpad defaults…"
    if (actionProc.running) actionProc.running = false
    root.applying = true
    actionProc.command = ["bash", helper, "apply-recommended-trackpad"]
    actionProc.running = true
  }

  function resetTrackpadToDefaults() {
    noticeTimer.stop()
    if (root.status) {
      var s = Object.assign({}, root.status)
      var tp = Object.assign({}, s.trackpad || Model.emptyStatus().trackpad)
      tp.naturalScroll = false
      tp.tapToClick = true
      tp.clickfingerBehavior = true
      tp.disableWhileTyping = true
      tp.scrollFactor = 0.4
      tp.middleButtonEmulation = false
      tp.tapAndDrag = true
      tp.dragLock = false
      tp.drag3fg = 0
      tp.tapButtonMap = "lrm"
      tp.flipX = false
      tp.flipY = false
      tp.sensitivity = 0.0
      tp.accelProfile = "adaptive"
      tp.leftHanded = false
      tp.swipeWorkspaces = true
      s.trackpad = tp
      root.status = s
    }
    root.lastNotice = "Restoring trackpad settings to defaults…"
    actionProc.command = ["bash", helper, "reset-trackpad-to-defaults"]
    actionProc.running = true
  }

  function restartTrackpad() {
    noticeTimer.stop()
    root.lastNotice = "Restarting trackpad driver…"
    actionProc.command = ["bash", helper, "restart-trackpad"]
    actionProc.running = true
  }

  function dismissRecommendedPrompt() {
    if (root.status && !root.status.recommendedPromptShown) {
      var s = Object.assign({}, root.status)
      s.recommendedPromptShown = true
      root.status = s
    }
    actionProc.command = ["bash", helper, "set", "recommended_prompt_shown", "true"]
    actionProc.running = true
  }

  function setOption(key, val) {
    if (key === "mem_sleep") {
      setMemSleep(val)
      return
    }
    if (actionProc.running) actionProc.running = false
    applying = true
    noticeTimer.stop()
    lastNotice = "Applying " + key + "…"

    // Optimistically update status for instant UI feedback
    if (root.status) {
      var s = Object.assign({}, root.status)
      if (key === "epp") {
        s.epp = val
      } else if (key === "aspm") {
        s.aspm = val
      } else if (key === "wifi_powersave") {
        s.wifiPowerSave = (val === "on" || val === "true")
      } else if (key === "pcie_ports_compat") {
        s.pciePortsCompat = (val === "on" || val === "true")
      } else if (key === "ethernet_managed") {
        var parts = String(val).split(":")
        var ethDev = parts[0]
        var isEthManaged = (parts[1] === "yes" || parts[1] === "true" || parts[1] === "on")
        if (s.inactiveEthernet) {
          s.inactiveEthernet = s.inactiveEthernet.map(function(item) {
            if (item.device === ethDev) {
              return { device: item.device, managed: isEthManaged, state: isEthManaged ? "disconnected" : "unmanaged" }
            }
            return item
          })
        }
      } else if (key === "audio_powersave") {
        s.audioPowerSave = (val === "true" || val === "on")
      } else if (key === "usb_autosuspend") {
        s.usbAutosuspend = (val === "true" || val === "on")
      } else if (key === "wake_lid") {
        s.wakeOnLid = (val === "on" || val === "true")
      } else if (key === "wake_ac") {
        s.wakeOnAc = (val === "on" || val === "true")
      } else if (key === "touchbar_blank") {
        s.touchbarBlank = (val === "true" || val === "on")
      } else if (key === "mem_sleep") {
        s.memSleep = val
      } else if (key === "lid_action") {
        s.lidAction = val
      } else if (key === "clamshell") {
        s.clamshell = (val === "true" || val === "on")
      } else if (key === "hibernate_delay") {
        s.hibernateDelay = val
      } else if (key === "kbd_timeout") {
        s.kbdTimeout = val
      } else if (key === "recommended_prompt_shown") {
        s.recommendedPromptShown = (val === "true" || val === "on")
      } else if (key === "keybinding_select_all") {
        s.keybindingSelectAll = val
      } else if (key === "keybinding_delete") {
        s.keybindingDelete = val
      } else if (key === "keybinding_find") {
        s.keybindingFind = val
      } else if (key === "keybinding_fullscreen") {
        s.keybindingFullscreen = val
      } else if (key === "keybinding_undo") {
        s.keybindingUndo = val
      } else if (key === "keybinding_redo") {
        s.keybindingRedo = val
      } else if (key === "keybinding_save") {
        s.keybindingSave = val
      } else if (key === "keybinding_cut") {
        s.keybindingCut = val
      } else if (key.indexOf("trackpad_") === 0) {
        var tpKey = key.slice(9)
        var tp = Object.assign({}, s.trackpad || Model.emptyStatus().trackpad)
        if (tpKey === "natural_scroll") tp.naturalScroll = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "tap_to_click") tp.tapToClick = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "clickfinger_behavior") tp.clickfingerBehavior = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "disable_while_typing") tp.disableWhileTyping = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "middle_button_emulation") tp.middleButtonEmulation = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "tap_and_drag") tp.tapAndDrag = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "drag_lock") tp.dragLock = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "drag_3fg") {
          tp.drag3fg = Number(val) || 0
          if (tp.drag3fg > 0) tp.swipeWorkspaces = false
        }
        else if (tpKey === "tap_button_map") tp.tapButtonMap = String(val)
        else if (tpKey === "scroll_factor") tp.scrollFactor = Number(val) || 0.64
        else if (tpKey === "sensitivity") tp.sensitivity = Number(val) || 0.0
        else if (tpKey === "accel_profile") tp.accelProfile = String(val)
        else if (tpKey === "left_handed") tp.leftHanded = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "flip_x") tp.flipX = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "flip_y") tp.flipY = (val === "true" || val === "1" || val === "on")
        else if (tpKey === "swipe_workspaces") {
          tp.swipeWorkspaces = (val === "true" || val === "1" || val === "on")
          if (tp.swipeWorkspaces) tp.drag3fg = 0
        }
        s.trackpad = tp
      }
      root.status = s
    }

    actionProc.command = ["bash", helper, "set", key, String(val)]
    actionProc.running = true
  }

  function fetchPlugins(force) {
    if (pluginsProc.running) return
    root.pluginsLoading = true
    var args = ["bash", helper, "plugins-list"]
    if (force) args.push("--force-refresh")
    pluginsProc.command = args
    pluginsProc.running = true
  }

  function installPlugin(repoUrl, pluginId) {
    if (pluginActionProc.running || !repoUrl) return
    root.activePluginOpId = pluginId
    root.pluginActionStatus = "Installing " + (pluginId || repoUrl) + "..."
    pluginActionProc.command = ["bash", helper, "plugin-install", repoUrl, pluginId]
    pluginActionProc.running = true
  }

  function updatePlugin(pluginId) {
    if (pluginActionProc.running || !pluginId) return
    root.activePluginOpId = pluginId
    root.pluginActionStatus = "Updating " + pluginId + "..."
    pluginActionProc.command = ["bash", helper, "plugin-update", pluginId]
    pluginActionProc.running = true
  }

  function removePlugin(pluginId) {
    if (pluginActionProc.running || !pluginId) return
    root.activePluginOpId = pluginId
    root.pluginActionStatus = "Removing " + pluginId + "..."
    pluginActionProc.command = ["bash", helper, "plugin-remove", pluginId]
    pluginActionProc.running = true
  }

  function togglePlugin(pluginId, enable) {
    if (pluginActionProc.running || !pluginId) return
    root.activePluginOpId = pluginId
    root.pluginActionStatus = (enable ? "Enabling " : "Disabling ") + pluginId + "..."

    // Optimistically update plugin state in memory for immediate knob flip
    if (root.pluginList) {
      var updated = []
      for (var i = 0; i < root.pluginList.length; i++) {
        var item = Object.assign({}, root.pluginList[i])
        if (item.id === pluginId) {
          item.enabled = enable
        }
        updated.push(item)
      }
      root.pluginList = updated
    }

    pluginActionProc.command = ["bash", helper, "plugin-toggle", pluginId, enable ? "enable" : "disable"]
    pluginActionProc.running = true
  }

  IpcHandler {
    target: "bramvanoploo.omarchy-t2-linux"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function showRebootDialog(): void {
      if (root.limineUpdating || limineProc.running) return
      root.open()
      root.rebootConfirmOpen = true
    }
    function showRecommendedDialog(): void { root.open(); root.recommendedConfirmOpen = true }
    function applyRecommendedOptions(): void { root.applyRecommendedOptions() }
    function showT2FixesDialog(): void { root.open(); root.t2FixesConfirmOpen = true }
    function applyT2Fixes(): void { root.applyT2Fixes() }
    function selectTab(index: int): void {
      root.activeTab = index
      if (root.tabs[index] && root.tabs[index].id === "plugins" && root.opened) {
        root.fetchPlugins(true)
      }
    }
    function setPluginFilter(query: string): void { root.pluginFilterQuery = query }
    function setPluginMode(mode: int): void { root.pluginFilterMode = mode }
    function setT2Filter(enable: bool): void { root.filterT2Only = enable }
    function scroll(y: real): void { flickable.contentY = y }
    function refreshPlugins(): void { root.fetchPlugins(true) }
    function togglePlugin(pluginId: string, enable: bool): void { root.togglePlugin(pluginId, enable) }
    function setOption(key: string, val: string): void { root.setOption(key, val) }
    function setMemSleep(mode: string): void { root.setMemSleep(mode) }
    function refresh(): void { root.refresh() }
    function scrollContent(y: real): void { flickable.contentY = y }
  }

  function openKeyRecorder(taskKey, taskName) {
    root.keyRecorderTaskKey = taskKey
    root.keyRecorderTaskName = taskName
    root.keyRecorderRecordedChord = ""
    root.keyRecorderDisplayChord = ""
    root.keyRecorderComplete = false
    root.keyRecorderChecking = false
    root.keyRecorderConflict = false
    root.keyRecorderConflictAction = ""
    root.keyRecorderOpen = true
    Qt.callLater(function() {
      if (typeof keyRecorderCatcher !== "undefined" && keyRecorderCatcher) {
        keyRecorderCatcher.forceActiveFocus()
      }
    })
  }

  function confirmKeyRecording() {
    if (!root.keyRecorderComplete || !root.keyRecorderRecordedChord) return
    var chord = root.keyRecorderRecordedChord
    var task = root.keyRecorderTaskKey

    // 1. If recording for a system override
    if (task.indexOf("system_override:") === 0) {
      var action = task.substring("system_override:".length)
      root.keyRecorderOpen = false

      // If resolving a conflict from a pending target task
      if (root.pendingConflictTargetTaskKey && root.pendingConflictTargetChord) {
        var tKey = root.pendingConflictTargetTaskKey
        var tChord = root.pendingConflictTargetChord
        var sDef = root.pendingConflictSystemDefaultChord || chord
        var sDisp = root.pendingConflictSystemDispatcher || "exec"
        var sArg = root.pendingConflictSystemArg || ""

        root.pendingConflictTargetTaskKey = ""
        root.pendingConflictTargetChord = ""
        root.pendingConflictSystemAction = ""

        if (actionProc.running) actionProc.running = false
        root.applying = true

        if (root.status) {
          var s = Object.assign({}, root.status)
          if (tKey === "keybinding_select_all") s.keybindingSelectAll = tChord
          else if (tKey === "keybinding_delete") s.keybindingDelete = tChord
          else if (tKey === "keybinding_find") s.keybindingFind = tChord
          else if (tKey === "keybinding_fullscreen") s.keybindingFullscreen = tChord
          else if (tKey === "keybinding_undo") s.keybindingUndo = tChord
          else if (tKey === "keybinding_redo") s.keybindingRedo = tChord
          else if (tKey === "keybinding_save") s.keybindingSave = tChord
          else if (tKey === "keybinding_cut") s.keybindingCut = tChord

          var ov = Object.assign({}, s.systemKeybindingOverrides || {})
          ov[action] = {
            action: action,
            defaultChord: sDef,
            currentChord: chord,
            recommendedChord: ov[action] ? ov[action].recommendedChord : chord,
            dispatcher: sDisp,
            arg: sArg
          }
          s.systemKeybindingOverrides = ov
          root.status = s
        }

        root.lastNotice = "Assigned " + Model.getTaskFriendlyName(tKey) + " (" + Model.formatChordForDisplay(tChord) + ") and set " + action + " to " + Model.formatChordForDisplay(chord)
        noticeTimer.restart()

        actionProc.command = ["bash", helper, "set-keybinding-with-system-override", tKey, tChord, action, chord, sDef, sDisp, sArg]
        actionProc.running = true
        return
      }

      // Standalone system override recording from changed system shortcuts list
      root.setSystemKeybinding(action, chord, root.pendingConflictSystemDefaultChord, root.pendingConflictSystemDispatcher, root.pendingConflictSystemArg)
      return
    }

    // 2. If resolving a pending intra-plugin conflict
    if (root.pendingConflictTargetTaskKey && root.pendingConflictTargetChord) {
      var tKey2 = root.pendingConflictTargetTaskKey
      var tChord2 = root.pendingConflictTargetChord
      root.pendingConflictTargetTaskKey = ""
      root.pendingConflictTargetChord = ""
      root.keyRecorderOpen = false

      if (actionProc.running) actionProc.running = false
      root.applying = true

      if (root.status) {
        var s2 = Object.assign({}, root.status)
        if (task === "keybinding_select_all") s2.keybindingSelectAll = chord
        else if (task === "keybinding_delete") s2.keybindingDelete = chord
        else if (task === "keybinding_find") s2.keybindingFind = chord
        else if (task === "keybinding_fullscreen") s2.keybindingFullscreen = chord
        else if (task === "keybinding_undo") s2.keybindingUndo = chord
        else if (task === "keybinding_redo") s2.keybindingRedo = chord
        else if (task === "keybinding_save") s2.keybindingSave = chord
        else if (task === "keybinding_cut") s2.keybindingCut = chord

        if (tKey2 === "keybinding_select_all") s2.keybindingSelectAll = tChord2
        else if (tKey2 === "keybinding_delete") s2.keybindingDelete = tChord2
        else if (tKey2 === "keybinding_find") s2.keybindingFind = tChord2
        else if (tKey2 === "keybinding_fullscreen") s2.keybindingFullscreen = tChord2
        else if (tKey2 === "keybinding_undo") s2.keybindingUndo = tChord2
        else if (tKey2 === "keybinding_redo") s2.keybindingRedo = tChord2
        else if (tKey2 === "keybinding_save") s2.keybindingSave = tChord2
        else if (tKey2 === "keybinding_cut") s2.keybindingCut = tChord2

        root.status = s2
      }

      root.lastNotice = "Updated " + Model.getTaskFriendlyName(tKey2) + " (" + Model.formatChordForDisplay(tChord2) + ") and " + Model.getTaskFriendlyName(task) + " (" + Model.formatChordForDisplay(chord) + ")"
      noticeTimer.restart()

      actionProc.command = ["bash", helper, "set-keybindings", task, chord, tKey2, tChord2]
      actionProc.running = true
      return
    }

    // 3. Normal plugin key recording
    root.keyRecorderChecking = true
    root.keyRecorderConflict = false
    checkKeyProc.command = ["bash", root.helper, "check-keybinding", root.keyRecorderRecordedChord, root.keyRecorderTaskKey]
    checkKeyProc.running = true
  }

  function checkAndApplyKeybinding(taskKey, newChord) {
    // 1. Check intra-plugin conflicts
    var pluginConflict = Model.findPluginConflict(taskKey, newChord, root.status)
    if (pluginConflict) {
      root.conflictIsSystem = false
      root.conflictTargetTaskKey = taskKey
      root.conflictTargetTaskName = Model.getTaskFriendlyName(taskKey)
      root.conflictTargetChord = newChord
      root.conflictDisplacedTaskKey = pluginConflict.key
      root.conflictDisplacedTaskName = pluginConflict.name
      root.conflictDisplacedChord = pluginConflict.chord
      root.conflictRecommendedChord = Model.getRecommendedAlternative(pluginConflict.key, newChord)
      root.conflictDialogOpen = true
      Qt.callLater(function() {
        if (typeof conflictDialogCatcher !== "undefined" && conflictDialogCatcher) {
          conflictDialogCatcher.forceActiveFocus()
        }
      })
      return
    }

    // 2. Check system default keybinding conflicts
    var systemConflict = Model.findSystemConflict(taskKey, newChord, root.status)
    if (systemConflict) {
      root.conflictIsSystem = true
      root.conflictTargetTaskKey = taskKey
      root.conflictTargetTaskName = Model.getTaskFriendlyName(taskKey)
      root.conflictTargetChord = newChord
      root.conflictDisplacedTaskKey = "system_override:" + systemConflict.action
      root.conflictDisplacedTaskName = systemConflict.action
      root.conflictDisplacedChord = systemConflict.currentChord
      root.conflictRecommendedChord = systemConflict.recommendedChord
      root.conflictSystemAction = systemConflict.action
      root.conflictSystemDispatcher = systemConflict.dispatcher
      root.conflictSystemArg = systemConflict.arg
      root.conflictDialogOpen = true
      Qt.callLater(function() {
        if (typeof conflictDialogCatcher !== "undefined" && conflictDialogCatcher) {
          conflictDialogCatcher.forceActiveFocus()
        }
      })
      return
    }

    root.setOption(taskKey, newChord)
    root.lastNotice = "Keybinding for " + Model.getTaskFriendlyName(taskKey) + " set to " + Model.formatChordForDisplay(newChord)
    noticeTimer.restart()
  }

  function resolveConflictWithRecommended() {
    var targetKey = root.conflictTargetTaskKey
    var targetChord = root.conflictTargetChord
    var displacedKey = root.conflictDisplacedTaskKey
    var displacedName = root.conflictDisplacedTaskName
    var displacedChord = root.conflictRecommendedChord
    var isSys = root.conflictIsSystem
    root.conflictDialogOpen = false

    if (!targetKey || !targetChord || !displacedName || !displacedChord) return

    if (actionProc.running) actionProc.running = false
    root.applying = true
    noticeTimer.stop()

    if (isSys) {
      var sysAction = root.conflictSystemAction
      var sysDef = root.conflictDisplacedChord
      var sysDisp = root.conflictSystemDispatcher
      var sysArg = root.conflictSystemArg

      if (root.status) {
        var s = Object.assign({}, root.status)
        if (targetKey === "keybinding_select_all") s.keybindingSelectAll = targetChord
        else if (targetKey === "keybinding_delete") s.keybindingDelete = targetChord
        else if (targetKey === "keybinding_find") s.keybindingFind = targetChord
        else if (targetKey === "keybinding_fullscreen") s.keybindingFullscreen = targetChord
        else if (targetKey === "keybinding_undo") s.keybindingUndo = targetChord
        else if (targetKey === "keybinding_redo") s.keybindingRedo = targetChord
        else if (targetKey === "keybinding_save") s.keybindingSave = targetChord
        else if (targetKey === "keybinding_cut") s.keybindingCut = targetChord

        var overrides = Object.assign({}, s.systemKeybindingOverrides || {})
        overrides[sysAction] = {
          action: sysAction,
          defaultChord: sysDef,
          currentChord: displacedChord,
          recommendedChord: displacedChord,
          dispatcher: sysDisp,
          arg: sysArg
        }
        s.systemKeybindingOverrides = overrides
        root.status = s
      }

      root.lastNotice = "Assigned " + root.conflictTargetTaskName + " (" + Model.formatChordForDisplay(targetChord) + ") and moved " + sysAction + " to " + Model.formatChordForDisplay(displacedChord)
      noticeTimer.restart()

      actionProc.command = ["bash", helper, "set-keybinding-with-system-override", targetKey, targetChord, sysAction, displacedChord, sysDef, sysDisp, sysArg]
      actionProc.running = true
    } else {
      if (root.status) {
        var s2 = Object.assign({}, root.status)
        if (displacedKey === "keybinding_select_all") s2.keybindingSelectAll = displacedChord
        else if (displacedKey === "keybinding_delete") s2.keybindingDelete = displacedChord
        else if (displacedKey === "keybinding_find") s2.keybindingFind = displacedChord
        else if (displacedKey === "keybinding_fullscreen") s2.keybindingFullscreen = displacedChord
        else if (displacedKey === "keybinding_undo") s2.keybindingUndo = displacedChord
        else if (displacedKey === "keybinding_redo") s2.keybindingRedo = displacedChord
        else if (displacedKey === "keybinding_save") s2.keybindingSave = displacedChord
        else if (displacedKey === "keybinding_cut") s2.keybindingCut = displacedChord

        if (targetKey === "keybinding_select_all") s2.keybindingSelectAll = targetChord
        else if (targetKey === "keybinding_delete") s2.keybindingDelete = targetChord
        else if (targetKey === "keybinding_find") s2.keybindingFind = targetChord
        else if (targetKey === "keybinding_fullscreen") s2.keybindingFullscreen = targetChord
        else if (targetKey === "keybinding_undo") s2.keybindingUndo = targetChord
        else if (targetKey === "keybinding_redo") s2.keybindingRedo = targetChord
        else if (targetKey === "keybinding_save") s2.keybindingSave = targetChord
        else if (targetKey === "keybinding_cut") s2.keybindingCut = targetChord

        root.status = s2
      }

      root.lastNotice = "Updated " + root.conflictTargetTaskName + " (" + Model.formatChordForDisplay(targetChord) + ") and " + displacedName + " (" + Model.formatChordForDisplay(displacedChord) + ")"
      noticeTimer.restart()

      actionProc.command = ["bash", helper, "set-keybindings", displacedKey, displacedChord, targetKey, targetChord]
      actionProc.running = true
    }
  }

  function resolveConflictWithCustom() {
    var targetKey = root.conflictTargetTaskKey
    var targetChord = root.conflictTargetChord
    var displacedKey = root.conflictDisplacedTaskKey
    var displacedName = root.conflictDisplacedTaskName
    var isSys = root.conflictIsSystem
    root.conflictDialogOpen = false

    root.pendingConflictTargetTaskKey = targetKey
    root.pendingConflictTargetChord = targetChord

    if (isSys) {
      root.pendingConflictSystemAction = root.conflictSystemAction
      root.pendingConflictSystemDefaultChord = root.conflictDisplacedChord
      root.pendingConflictSystemDispatcher = root.conflictSystemDispatcher
      root.pendingConflictSystemArg = root.conflictSystemArg
      root.openKeyRecorder("system_override:" + root.conflictSystemAction, displacedName)
    } else {
      root.pendingConflictSystemAction = ""
      root.openKeyRecorder(displacedKey, displacedName)
    }
  }

  function openSystemKeyRecorder(action, defaultChord, dispatcher, arg) {
    root.pendingConflictSystemAction = action
    root.pendingConflictSystemDefaultChord = defaultChord || ""
    root.pendingConflictSystemDispatcher = dispatcher || "exec"
    root.pendingConflictSystemArg = arg || ""
    root.pendingConflictTargetTaskKey = ""
    root.pendingConflictTargetChord = ""
    root.openKeyRecorder("system_override:" + action, action)
  }

  function resetSystemKeybinding(action) {
    if (!action) return
    if (actionProc.running) actionProc.running = false
    root.applying = true

    if (root.status && root.status.systemKeybindingOverrides) {
      var s = Object.assign({}, root.status)
      var ov = Object.assign({}, s.systemKeybindingOverrides)
      delete ov[action]
      s.systemKeybindingOverrides = ov
      root.status = s
    }

    root.lastNotice = "Restored " + action + " to system default"
    noticeTimer.restart()

    actionProc.command = ["bash", helper, "reset-system-keybinding", action]
    actionProc.running = true
  }

  function setSystemKeybinding(action, newChord, defaultChord, dispatcher, arg) {
    if (!action || !newChord) return
    if (actionProc.running) actionProc.running = false
    root.applying = true

    if (root.status) {
      var s = Object.assign({}, root.status)
      var ov = Object.assign({}, s.systemKeybindingOverrides || {})
      ov[action] = {
        action: action,
        defaultChord: defaultChord || (ov[action] ? ov[action].defaultChord : newChord),
        currentChord: newChord,
        recommendedChord: ov[action] ? ov[action].recommendedChord : newChord,
        dispatcher: dispatcher || "exec",
        arg: arg || ""
      }
      s.systemKeybindingOverrides = ov
      root.status = s
    }

    root.lastNotice = "Updated " + action + " to " + Model.formatChordForDisplay(newChord)
    noticeTimer.restart()

    actionProc.command = ["bash", helper, "set-system-keybinding", action, newChord, defaultChord || "", dispatcher || "exec", arg || ""]
    actionProc.running = true
  }

  function cancelConflictDialog() {
    root.conflictDialogOpen = false
    root.pendingConflictTargetTaskKey = ""
    root.pendingConflictTargetChord = ""
    root.pendingConflictSystemAction = ""
    root.lastNotice = "Keybinding change cancelled."
    noticeTimer.restart()
  }

  function triggerConflictResolution(conflict) {
    if (!conflict) return
    var isSys = (conflict.source === "system")
    root.conflictIsSystem = isSys
    root.conflictTargetTaskKey = conflict.taskKey1
    root.conflictTargetTaskName = conflict.action1
    root.conflictTargetChord = conflict.chord1 || conflict.chord
    root.conflictDisplacedTaskKey = isSys ? ("system_override:" + conflict.action2) : conflict.taskKey2
    root.conflictDisplacedTaskName = conflict.action2
    root.conflictDisplacedChord = conflict.chord2 || conflict.defaultChord || conflict.chord
    root.conflictRecommendedChord = conflict.recommendedChord
    if (isSys) {
      root.conflictSystemAction = conflict.action2
      root.conflictSystemDispatcher = conflict.dispatcher || "exec"
      root.conflictSystemArg = conflict.arg || ""
    } else {
      root.conflictSystemAction = ""
    }
    root.conflictDialogOpen = true
    Qt.callLater(function() {
      if (typeof conflictDialogCatcher !== "undefined" && conflictDialogCatcher) {
        conflictDialogCatcher.forceActiveFocus()
      }
    })
  }

  function applyRecommendedKeybindings() {
    noticeTimer.stop()
    if (root.status && Model.areAllMacShortcutsApplied(root.status)) {
      root.lastNotice = "Recommended keybindings are already applied."
      noticeTimer.restart()
      return
    }

    if (actionProc.running) actionProc.running = false
    root.applying = true

    if (root.status) {
      var s = Object.assign({}, root.status)
      s.keybindingSelectAll = "SUPER + A"
      s.keybindingDelete = "SUPER + BACKSPACE"
      s.keybindingFind = "SUPER + F"
      s.keybindingFullscreen = "SUPER + CTRL + F"
      s.keybindingUndo = "SUPER + Z"
      s.keybindingRedo = "SUPER + SHIFT + Z"
      s.keybindingSave = "SUPER + S"
      s.keybindingCut = "SUPER + X"

      var ov = Object.assign({}, s.systemKeybindingOverrides || {})
      var recChords = ["SUPER + A", "SUPER + BACKSPACE", "SUPER + F", "SUPER + CTRL + F", "SUPER + Z", "SUPER + SHIFT + Z", "SUPER + S", "SUPER + X"]
      var recTaskNames = ["selectall", "forwarddelete", "delete", "find", "findindocument", "fullscreen", "togglefullscreen", "undo", "redo", "save", "cut", "universalcut"]
      if (s.systemKeybindings) {
        for (var rc = 0; rc < recChords.length; rc++) {
          var rNorm = Model.normalizeChord(recChords[rc])
          var sysKeys = Object.keys(s.systemKeybindings)
          for (var sk = 0; sk < sysKeys.length; sk++) {
            var sysChord = sysKeys[sk]
            if (Model.normalizeChord(sysChord) === rNorm) {
              var sItem = s.systemKeybindings[sysChord]
              var sAct = sItem.action || ""
              var sActNorm = sAct.toLowerCase().replace(/\s+/g, "")
              if (recTaskNames.indexOf(sActNorm) === -1) {
                var recAlt = sItem.recommendedChord || ("SUPER + ALT + " + rNorm.split("+").pop().trim())
                ov[sAct] = {
                  action: sAct,
                  defaultChord: sItem.defaultChord || sysChord,
                  currentChord: recAlt,
                  recommendedChord: recAlt,
                  dispatcher: sItem.dispatcher || "exec",
                  arg: sItem.arg || ""
                }
              }
            }
          }
        }
      }
      s.systemKeybindingOverrides = ov
      root.status = s
    }

    root.lastNotice = "Applied recommended Mac shortcuts."
    noticeTimer.restart()

    actionProc.command = ["bash", helper, "apply-recommended-keybindings"]
    actionProc.running = true
  }

  function resetKeybindingsToDefaults() {
    if (actionProc.running) actionProc.running = false
    root.applying = true
    noticeTimer.stop()

    if (root.status) {
      var s = Object.assign({}, root.status)
      s.keybindingSelectAll = "CTRL + A"
      s.keybindingDelete = "DELETE"
      s.keybindingFind = "CTRL + F"
      s.keybindingFullscreen = "SUPER + F"
      s.keybindingUndo = "CTRL + Z"
      s.keybindingRedo = "CTRL + SHIFT + Z"
      s.keybindingSave = "CTRL + S"
      s.keybindingCut = "CTRL + X"
      s.systemKeybindingOverrides = {}
      root.status = s
    }

    root.lastNotice = "Restored keybindings to system defaults."
    noticeTimer.restart()

    actionProc.command = ["bash", helper, "reset-keybindings-to-defaults"]
    actionProc.running = true
  }

  function applyKeyOverride() {
    var task = root.keyRecorderTaskKey
    var chord = root.keyRecorderRecordedChord
    root.keyRecorderOpen = false
    root.keyRecorderConflict = false
    root.checkAndApplyKeybinding(task, chord)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onActiveTabChanged: {
    if (root.tabs[root.activeTab] && root.tabs[root.activeTab].id === "plugins" && opened) {
      root.fetchPlugins(true)
    }
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      if (root.tabs[root.activeTab] && root.tabs[root.activeTab].id === "plugins") {
        fetchPlugins(true)
      } else {
        fetchPlugins(false)
      }
      if (root.openedViaBarButton && root.status && root.status.isT2 && !Model.areAllT2FixesApplied(root.status) && !root.limineUpdating && !root.rebootConfirmOpen) {
        root.t2FixesConfirmOpen = true
      } else if (root.status && root.status.isT2 && !root.status.recommendedPromptShown && !root.limineUpdating && !root.rebootConfirmOpen && !root.t2FixesConfirmOpen) {
        root.recommendedConfirmOpen = true
      }
    } else {
      root.openedViaBarButton = false
      root.t2FixesConfirmOpen = false
      root.lastNotice = ""
      noticeTimer.stop()
    }
  }

  Component.onCompleted: {
    refresh()
    fetchPlugins()
  }

  // Process to fetch JSON status
  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  // Process to execute mutation actions
  Process {
    id: actionProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim().length > 0) {
          console.warn("T2 action error:", text)
        }
      }
    }
    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.lastNotice = "Changes saved."
      } else {
        root.lastNotice = "Operation cancelled or failed."
      }
      noticeTimer.restart()
      refreshTimer.restart()
    }
  }

  // Process to execute bootloader update (limine-update)
  Process {
    id: limineProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastNotice = "Boot configuration updated."
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text && text.trim().length > 0) {
          console.warn("limine-update output:", text)
        }
      }
    }
    onExited: function(exitCode) {
      root.limineUpdating = false
      if (exitCode === 0) {
        root.lastNotice = "Limine boot configuration updated successfully."
        root.rebootConfirmOpen = true
      } else {
        root.lastNotice = "limine-update failed (exit code " + exitCode + ")."
      }
      noticeTimer.restart()
      refreshTimer.restart()
    }
  }

  // Process to reboot computer
  Process {
    id: rebootProc
    command: ["systemctl", "reboot"]
  }

  // Process to fetch plugins catalog
  Process {
    id: pluginsProc
    stdout: StdioCollector {
      id: pluginsStdout
      waitForEnd: true
      onStreamFinished: {
        root.pluginsLoading = false
        root.applyPlugins(pluginsStdout.text)
      }
    }
    onExited: function(exitCode) {
      root.pluginsLoading = false
    }
  }

  // Process to execute plugin actions
  Process {
    id: pluginActionProc
    stdout: StdioCollector {
      id: pluginActionStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: pluginActionStderr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var opId = root.activePluginOpId
      root.activePluginOpId = ""
      var msg = ""
      if (pluginActionStdout.text && pluginActionStdout.text.trim()) {
        try {
          var res = JSON.parse(pluginActionStdout.text)
          if (res.message) msg = res.message
          else if (res.error) msg = res.error
        } catch (e) {
          msg = pluginActionStdout.text.trim()
        }
      }
      if (!msg && pluginActionStderr.text && pluginActionStderr.text.trim()) {
        msg = pluginActionStderr.text.trim()
      }
      if (exitCode === 0) {
        root.pluginActionStatus = msg || "Plugin operation completed successfully."
      } else {
        root.pluginActionStatus = msg || ("Plugin operation failed (exit code " + exitCode + ").")
      }
      root.fetchPlugins(true)
    }
  }

  // Process to check if a keybinding chord is in use
  Process {
    id: checkKeyProc
    stdout: StdioCollector {
      id: checkKeyStdout
      waitForEnd: true
      onStreamFinished: {
        root.keyRecorderChecking = false
        var out = checkKeyStdout.text ? checkKeyStdout.text.trim() : ""
        var task = root.keyRecorderTaskKey
        var chord = root.keyRecorderRecordedChord
        if (!out) {
          root.keyRecorderOpen = false
          root.checkAndApplyKeybinding(task, chord)
          return
        }
        try {
          var res = JSON.parse(out)
          root.keyRecorderOpen = false
          root.checkAndApplyKeybinding(task, chord)
        } catch(e) {
          root.keyRecorderOpen = false
          root.checkAndApplyKeybinding(task, chord)
        }
      }
    }
    onExited: function(code) {
      root.keyRecorderChecking = false
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: noticeTimer
    interval: 6000
    repeat: false
    onTriggered: root.lastNotice = ""
  }

  Timer {
    interval: root.opened ? 4000 : 15000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // --- Bar Icon Button ---
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.barIcon(root.status)
    tooltipText: Model.tooltip(root.status)
    onPressed: function(btn) {
      root.handleBarIconClick()
    }
  }

  // --- Main Settings Panel Window (Overlay, Centered, Large) ---
  PanelWindow {
    id: centerPanelWindow
    visible: root.opened
    screen: button && button.QsWindow && button.QsWindow.window ? button.QsWindow.window.screen : null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-t2-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) {
        Qt.callLater(function() {
          if (centerPanelWindow.visible) panelKeyCatcher.forceActiveFocus()
        })
      }
    }

    Item {
      id: panelKeyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (root.keyRecorderOpen) {
          event.accepted = false
          return
        }
        if (root.limineUpdating || limineProc.running) {
          event.accepted = true
          return
        }
        if (root.rebootConfirmOpen) {
          if (event.key === Qt.Key_Escape) {
            root.rebootConfirmOpen = false
            event.accepted = true
            return
          }
        }
        if (root.t2FixesConfirmOpen) {
          if (event.key === Qt.Key_Escape) {
            root.t2FixesConfirmOpen = false
            event.accepted = true
            return
          }
        }
        if (root.recommendedConfirmOpen) {
          if (event.key === Qt.Key_Escape) {
            root.recommendedConfirmOpen = false
            root.dismissRecommendedPrompt()
            event.accepted = true
            return
          }
        }
        if (root.conflictDialogOpen) {
          if (event.key === Qt.Key_Escape) {
            root.cancelConflictDialog()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.resolveConflictWithRecommended()
            event.accepted = true
            return
          }
        }
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        }
      }

      // Backdrop scrim: Clicking outside closes the panel
      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)

        MouseArea {
          anchors.fill: parent
          onClicked: {
            if (!root.limineUpdating && !limineProc.running && !root.rebootConfirmOpen && !root.recommendedConfirmOpen && !root.t2FixesConfirmOpen && !root.keyRecorderOpen && !root.conflictDialogOpen) {
              root.close()
            }
          }
        }

        // Centered Card (Large, 968x682)
        BorderSurface {
          id: mainCard
          anchors.centerIn: parent
          width: Math.min(Style.space(968), parent.width - Style.space(48))
          height: Math.min(Style.space(682), parent.height - Style.space(48))
          color: Color.popups.background
          borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
          radius: Style.cornerRadius

          // Click absorption so clicks inside card don't dismiss backdrop
          MouseArea {
            anchors.fill: parent
            onClicked: {}
          }

          Item {
            id: panelInner
            anchors.fill: parent
            anchors.margins: Style.space(24)

            Column {
              id: panelMainCol
              anchors.fill: parent
              spacing: Style.space(14)

              // Panel Header
              Item {
                id: panelHeader
                width: parent.width
                height: Style.space(42)

                Row {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(14)

                  Rectangle {
                    width: Style.space(38)
                    height: Style.space(38)
                    radius: Style.cornerRadius
                    color: Util.alpha(Color.accent, 0.16)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent
                      text: ""
                      color: Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      text: "Omapple"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                    }

                    Text {
                      text: root.status.model + " · " + root.status.chip
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  PanelActionButton {
                    iconText: "󰑐"
                    tooltipText: "Refresh hardware readings"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.subtitle
                    size: Style.space(30)
                    enabled: !root.limineUpdating
                    onClicked: root.refresh()
                  }

                  PanelActionButton {
                    iconText: "󰅖"
                    tooltipText: "Close panel (Esc)"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.subtitle
                    size: Style.space(30)
                    enabled: !root.limineUpdating
                    onClicked: root.close()
                  }
                }
              }

              PanelSeparator {
                id: panelSep
                width: parent.width
                foreground: root.foreground
              }

              // Two-column layout: Left = Vertical Tabs, Right = Category Content
              Row {
                id: bodyRow
                width: parent.width
                height: parent.height - panelHeader.height - panelSep.height - (panelMainCol.spacing * 2)
                spacing: Style.space(20)

              // -------------------------------------------------------------
              // Left Sidebar: Vertical Tabs & Hardware Info
              // -------------------------------------------------------------
              Item {
                id: verticalTabsCol
                width: Style.space(242)
                height: parent.height

                // Top: Navigation Tabs
                Column {
                  id: navTabsCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  spacing: Style.space(8)

                  Repeater {
                    model: root.tabs

                    delegate: BorderSurface {
                      id: tabButton
                      width: navTabsCol.width
                      height: Style.space(54)
                      radius: Style.cornerRadius

                      readonly property bool active: root.activeTab === index
                      readonly property bool hovered: tabMouseArea.containsMouse

                      color: active
                        ? Style.selectedFillFor(root.foreground, root.accent)
                        : (hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")

                      borderSpec: active
                        ? Border.flat(root.accent, Style.normalBorderWidth)
                        : (hovered ? Border.controlSpec("hover-cursor", root.foreground, root.accent) : Border.controlSpec("normal", root.foreground, root.accent))

                      // Left active accent strip
                      Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(3)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(4)
                        height: Style.space(34)
                        radius: 2
                        color: root.accent
                        visible: tabButton.active
                      }

                      Row {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(14)
                        anchors.rightMargin: Style.space(12)
                        spacing: Style.space(12)

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: modelData.icon
                          color: tabButton.active ? root.accent : root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.title
                        }

                        Column {
                          anchors.verticalCenter: parent.verticalCenter
                          width: parent.width - Style.space(42)
                          spacing: Style.space(2)

                          Text {
                            width: parent.width
                            text: modelData.title
                            color: tabButton.active ? root.foreground : root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            font.bold: tabButton.active
                            elide: Text.ElideRight
                          }

                          Text {
                            width: parent.width
                            text: modelData.desc
                            color: Qt.darker(root.foreground, 1.55)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                          }
                        }
                      }

                      MouseArea {
                        id: tabMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          root.activeTab = index
                          if (root.tabs[index] && root.tabs[index].id === "plugins") {
                            root.fetchPlugins(true)
                          }
                        }
                      }
                    }
                  }
                }

                // Bottom: "Apply T2 fixes only" + "Apply recommended options" button + T2 Subsystem summary
                Column {
                  id: sidebarFooterCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  spacing: Style.space(8)

                  Button {
                    id: applyT2FixesBtn
                    visible: Boolean(root.status && root.status.isT2 && !Model.areAllT2FixesApplied(root.status))
                    width: parent.width
                    height: Style.space(36)
                    text: "Apply T2 fixes only"
                    iconText: ""
                    bordered: true
                    accent: root.accent
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    onClicked: {
                      root.t2FixesConfirmOpen = true
                    }
                  }

                  Button {
                    id: applyRecommendedBtn
                    width: parent.width
                    height: Style.space(36)
                    text: "Apply recommended options"
                    iconText: "󰁨"
                    bordered: true
                    accent: root.accent
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(8)
                    onClicked: {
                      root.recommendedConfirmOpen = true
                    }
                  }

                  // Hardware Summary in sidebar footer
                  BorderSurface {
                    width: parent.width
                    implicitHeight: hwSummaryCol.implicitHeight + Style.space(20)
                    height: implicitHeight
                    color: Util.alpha(root.foreground, 0.04)
                    radius: Style.cornerRadius

                    Column {
                      id: hwSummaryCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(10)
                      spacing: Style.space(4)

                      Text {
                        text: (root.status && root.status.isT2) ? "T2 SUBSYSTEM" : ((root.status && root.status.isApple) ? "APPLE HARDWARE" : "SYSTEM HARDWARE")
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 0.8
                      }

                      Text {
                        text: "Model: " + (root.status.model || "Unknown Device")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      // T2 Case: Kernel & Chip details
                      Text {
                        visible: Boolean(root.status && root.status.isT2)
                        text: "Kernel: " + (root.status.kernel || "T2 Patched")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        visible: Boolean(root.status && root.status.isT2)
                        text: "Chip: " + (root.status.chip || "Apple T2 (106b:1801)")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      // Non-T2 Case: CPU, Platform, and Kernel
                      Text {
                        visible: !Boolean(root.status && root.status.isT2)
                        text: "CPU: " + (root.status.cpu || "Standard Processor")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        visible: !Boolean(root.status && root.status.isT2)
                        text: "Kernel: " + (root.status.kernel || "Linux")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        visible: !Boolean(root.status && root.status.isT2)
                        text: (root.status && root.status.isApple) ? "Platform: Apple (Non-T2)" : ("Subsystem: " + (root.status.chip || (root.status.arch ? root.status.arch : "Standard PC")))
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                      }
                    }
                  }
                }
              }

              // Vertical Separator
              Rectangle {
                width: 1
                height: parent.height
                color: root.hairline
              }

              // -------------------------------------------------------------
              // Right Content Area: Options for Active Tab
              // -------------------------------------------------------------
              Item {
                id: contentArea
                width: parent.width - verticalTabsCol.width - (bodyRow.spacing * 2) - 1
                height: parent.height
                clip: true

                Flickable {
                  id: flickable
                  anchors.fill: parent
                  contentWidth: width
                  contentHeight: optionsColumn.implicitHeight + Style.space(24)
                  boundsBehavior: Flickable.StopAtBounds
                  flickableDirection: Flickable.VerticalFlick
                  interactive: contentHeight > height
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  Connections {
                    target: root
                    function onActiveTabChanged() { flickable.contentY = 0 }
                    function onOpenedChanged() { if (root.opened) flickable.contentY = 0 }
                  }

                  Column {
                    id: optionsColumn
                    width: flickable.width - Style.space(14)
                    spacing: Style.space(14)

                    // Category Title Header
                    Item {
                      width: parent.width
                      height: Math.max(Style.space(38), tabRecBtn.implicitHeight)

                      Column {
                        anchors.left: parent.left
                        anchors.right: tabRecRow.left
                        anchors.rightMargin: Style.space(12)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)

                        Text {
                          text: (root.tabs && root.tabs[root.activeTab]) ? root.tabs[root.activeTab].title.toUpperCase() : ""
                          color: root.accent
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.subtitle
                          font.bold: true
                          font.letterSpacing: 1.0
                        }

                        Text {
                          text: root.currentTabId === "battery"
                            ? "Optimize power consumption, battery health, and background device drain."
                            : (root.currentTabId === "suspend"
                                ? "Fine-tune sleep modes, lid behavior, and wake triggers for your MacBook."
                                : (root.currentTabId === "keybindings"
                                    ? "Configure Apple T2 keyboard shortcuts, function keys, and layout options."
                                    : (root.currentTabId === "trackpad"
                                        ? "Configure pointer speed, natural scrolling, Force Touch gestures, and palm rejection for the Apple internal trackpad."
                                        : (root.currentTabId === "sound"
                                            ? "Manage Apple T2 audio outputs, power saving, and sound profiles."
                                            : "Discover, install, update, and remove Apple and T2 community plugins from plugins.omarchy.org."))))
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          width: parent.width
                        }
                      }

                      Row {
                        id: tabRecRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(10)

                        Text {
                          visible: root.lastNotice !== ""
                          text: root.lastNotice
                          color: Color.accent
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          anchors.verticalCenter: parent.verticalCenter
                        }

                        Button {
                          id: tabRecBtn
                          visible: root.currentTabId === "battery" || root.currentTabId === "suspend" || root.currentTabId === "keybindings" || root.currentTabId === "trackpad"
                          anchors.verticalCenter: parent.verticalCenter

                          readonly property bool allApplied: {
                            if (root.currentTabId === "battery") return Model.areAllBatteryRecommendedApplied(root.status)
                            if (root.currentTabId === "suspend") return Model.areAllSuspendRecommendedApplied(root.status)
                            if (root.currentTabId === "keybindings") return Model.areAllMacShortcutsApplied(root.status)
                            if (root.currentTabId === "trackpad") return Model.areAllTrackpadRecommendedApplied(root.status)
                            return false
                          }

                          iconText: allApplied ? "󰁌" : (root.currentTabId === "keybindings" ? "" : (root.currentTabId === "trackpad" ? "󱑣" : (root.currentTabId === "battery" ? "󰁹" : "󰤄")))
                          text: allApplied ? "Reset to Defaults" : "Apply Recommended Options"
                          tooltipText: allApplied
                            ? ("Reset " + (root.tabs && root.tabs[root.activeTab] ? root.tabs[root.activeTab].title.toLowerCase() : "tab") + " to system defaults")
                            : ("Set " + (root.tabs && root.tabs[root.activeTab] ? root.tabs[root.activeTab].title.toLowerCase() : "tab") + " to recommended options")
                          bordered: true
                          fontSize: Style.font.caption
                          iconSize: Style.font.bodySmall
                          height: Style.space(30)
                          accent: root.accent
                          enabled: !root.limineUpdating
                          onClicked: {
                            if (root.currentTabId === "battery") {
                              if (allApplied) root.resetBatteryToDefaults(); else root.applyRecommendedBattery();
                            } else if (root.currentTabId === "suspend") {
                              if (allApplied) root.resetSuspendToDefaults(); else root.applyRecommendedSuspend();
                            } else if (root.currentTabId === "keybindings") {
                              if (allApplied) root.resetKeybindingsToDefaults(); else root.applyRecommendedKeybindings();
                            } else if (root.currentTabId === "trackpad") {
                              if (allApplied) root.resetTrackpadToDefaults(); else root.applyRecommendedTrackpad();
                            }
                          }
                        }
                      }
                    }

                    PanelSeparator {
                      width: parent.width
                      foreground: root.foreground
                    }

                    // =========================================================
                    // TAB 0: BATTERY LIFE
                    // =========================================================
                    Column {
                      id: batteryTabContent
                      visible: root.currentTabId === "battery"
                      width: parent.width
                      spacing: Style.space(12)

                      // Battery Health & Power Card
                      BorderSurface {
                        width: parent.width
                        height: batRow.implicitHeight + Style.space(24)
                        color: Util.alpha(Color.accent, 0.08)
                        borderSpec: Border.flat(Util.alpha(Color.accent, 0.3), 1)
                        radius: Style.cornerRadius

                        Row {
                          id: batRow
                          anchors.left: parent.left
                          anchors.leftMargin: Style.space(16)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(20)

                          Column {
                            width: Style.space(110)
                            spacing: Style.space(2)

                            Row {
                              spacing: Style.space(6)
                              Text {
                                text: "󰁹"
                                color: Color.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                              }
                              Text {
                                text: Math.min(100, Math.max(0, root.status.battery.percent)) + "%"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                              }
                            }

                            Text {
                              text: root.status.battery.status
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          Rectangle {
                            width: 1
                            height: Style.space(40)
                            color: root.hairline
                          }

                          Column {
                            width: Style.space(130)
                            spacing: Style.space(2)
                            Text {
                              text: (root.status.battery.watts > 0 ? root.status.battery.watts + " W" : "AC Connected")
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Discharge Rate"
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          Rectangle {
                            width: 1
                            height: Style.space(40)
                            color: root.hairline
                          }

                          Column {
                            width: Style.space(120)
                            spacing: Style.space(2)
                            Text {
                              text: (root.status && root.status.battery && root.status.battery.health !== undefined)
                                ? Math.min(100, Math.max(0, Math.round(Number(root.status.battery.health) || 0))) + "%"
                                : "—"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Health (" + ((root.status && root.status.battery) ? root.status.battery.cycles : 0) + " cycles)"
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }
                        }
                      }

                      // 1. CPU Energy Performance Preference (EPP)
                      BorderSurface {
                        width: parent.width
                        height: eppCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: eppCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(10)

                          Row {
                            width: parent.width
                            Item {
                              width: parent.width - eppStatusText.implicitWidth
                              height: eppTitle.implicitHeight + eppDesc.implicitHeight
                              Column {
                                anchors.fill: parent
                                spacing: 2
                                Text {
                                  id: eppTitle
                                  text: "Energy Performance Preference (EPP)"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                                Text {
                                  id: eppDesc
                                  text: "Tuning Intel CPU energy bias to balance clock speed and battery consumption."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                }
                              }
                            }

                            Text {
                              id: eppStatusText
                              text: Model.formatEpp(root.status.epp)
                              color: root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }

                          Row {
                            width: parent.width
                            spacing: Style.space(8)
                            readonly property real btnWidth: (width - spacing * 2) / 3

                            Repeater {
                              model: [
                                { val: "power", label: "Powersave" },
                                { val: "balanced", label: "Balanced" },
                                { val: "performance", label: "Performance" }
                              ]

                              delegate: Button {
                                width: parent.btnWidth
                                text: modelData.label
                                bordered: true
                                selected: modelData.val === "balanced"
                                  ? (root.status.epp === "balanced" || root.status.epp === "balance_power" || root.status.epp === "balance_performance")
                                  : (root.status.epp === modelData.val)
                                onClicked: root.setOption("epp", modelData.val)
                              }
                            }
                          }
                        }
                      }

                      // 2. Wi-Fi Power Save Toggle
                      BorderSurface {
                        width: parent.width
                        height: Style.space(62)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(14)
                          anchors.rightMargin: Style.space(14)
                          anchors.verticalCenter: parent.verticalCenter

                          Column {
                            width: parent.width - wifiSwitch.width - Style.space(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                              text: "Wi-Fi Power Management"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Enables IEEE 802.11 power saving on the Broadcom wireless chip during idle."
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          ToggleSwitch {
                            id: wifiSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: Boolean(root.status && root.status.wifiPowerSave)
                            accent: root.accent
                            foreground: checked ? root.accent : root.foreground
                            onToggled: root.setOption("wifi_powersave", !(root.status && root.status.wifiPowerSave) ? "on" : "off")
                          }
                        }
                      }

                      // Inactive Ethernet Management (e.g. enp2s0f1u1 Apple T2 iBridge CDC-NCM or other inactive adapters)
                      BorderSurface {
                        visible: Boolean(root.status && root.status.inactiveEthernet && root.status.inactiveEthernet.length > 0)
                        width: parent.width
                        height: ethCardCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: ethCardCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(10)

                          // Header
                          Column {
                            width: parent.width
                            spacing: 2

                            Text {
                              text: "Ethernet Management"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }

                            Text {
                              text: "Prevent NetworkManager from attempting DHCP transactions on inactive network interfaces after resume."
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              wrapMode: Text.WordWrap
                              width: parent.width
                            }
                          }

                          // List of Inactive Interfaces
                          Column {
                            width: parent.width
                            spacing: Style.space(6)

                            Repeater {
                              model: (root.status && root.status.inactiveEthernet) ? root.status.inactiveEthernet : []

                              delegate: BorderSurface {
                                width: parent.width
                                height: Style.space(38)
                                color: Util.alpha(root.foreground, 0.03)
                                radius: Style.cornerRadius

                                Row {
                                  anchors.fill: parent
                                  anchors.leftMargin: Style.space(12)
                                  anchors.rightMargin: Style.space(12)
                                  anchors.verticalCenter: parent.verticalCenter

                                  Row {
                                    width: parent.width - ethDevSwitch.width
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.space(8)

                                    Text {
                                      text: "󰌘  " + modelData.device
                                      color: root.foreground
                                      font.family: root.fontFamily
                                      font.pixelSize: Style.font.body
                                      font.bold: true
                                      anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                      text: modelData.managed ? "Managed" : "Unmanaged"
                                      color: modelData.managed ? root.accent : root.dim
                                      font.family: root.fontFamily
                                      font.pixelSize: Style.font.caption
                                      anchors.verticalCenter: parent.verticalCenter
                                    }
                                  }

                                  ToggleSwitch {
                                    id: ethDevSwitch
                                    anchors.verticalCenter: parent.verticalCenter
                                    checked: Boolean(modelData && modelData.managed)
                                    accent: root.accent
                                    foreground: checked ? root.accent : root.foreground
                                    onToggled: root.setOption("ethernet_managed", modelData.device + ":" + (!modelData.managed ? "yes" : "no"))
                                  }
                                }
                              }
                            }
                          }
                        }
                      }

                      // PCIe Ports Compatibility (pcie_ports=compat in /etc/limine-entry-tool.d/t2-mac.conf)
                      BorderSurface {
                        visible: Boolean(root.status && root.status.isT2)
                        width: parent.width
                        height: Math.max(Style.space(62), pcieCol.implicitHeight + Style.space(20))
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(14)
                          anchors.rightMargin: Style.space(14)
                          anchors.verticalCenter: parent.verticalCenter

                          Column {
                            id: pcieCol
                            width: parent.width - pcieSwitch.width - Style.space(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                              text: "PCIe Ports Compatibility"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }

                            Text {
                              text: "Enables low-power states on internal PCIe buses to reduce battery drain and prevent power glitches on T2 MacBooks. Automatically updates the bootloader."
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              wrapMode: Text.WordWrap
                              width: parent.width
                            }
                          }

                          ToggleSwitch {
                            id: pcieSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: Boolean(root.status && root.status.pciePortsCompat)
                            accent: root.accent
                            foreground: checked ? root.accent : root.foreground
                            enabled: !root.limineUpdating
                            onToggled: root.togglePciePortsCompat(!(root.status && root.status.pciePortsCompat))
                          }
                        }
                      }

                      // 3. Audio Controller Power Save
                      BorderSurface {
                        width: parent.width
                        height: Style.space(62)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(14)
                          anchors.rightMargin: Style.space(14)
                          anchors.verticalCenter: parent.verticalCenter

                          Column {
                            width: parent.width - audioSwitch.width - Style.space(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                              text: "Audio Controller Power Save"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Powers down the Apple Audio controller when no media is playing."
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          ToggleSwitch {
                            id: audioSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: Boolean(root.status && root.status.audioPowerSave)
                            accent: root.accent
                            foreground: checked ? root.accent : root.foreground
                            onToggled: root.setOption("audio_powersave", !(root.status && root.status.audioPowerSave) ? "true" : "false")
                          }
                        }
                      }

                      // 5. USB Autosuspend Toggle
                      BorderSurface {
                        width: parent.width
                        height: Style.space(62)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(14)
                          anchors.rightMargin: Style.space(14)
                          anchors.verticalCenter: parent.verticalCenter

                          Column {
                            width: parent.width - usbSwitch.width - Style.space(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                              text: "USB Device Autosuspend"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Allows idle USB devices and internal bridges to enter low-power sleep."
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          ToggleSwitch {
                            id: usbSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: Boolean(root.status && root.status.usbAutosuspend)
                            accent: root.accent
                            foreground: checked ? root.accent : root.foreground
                            onToggled: root.setOption("usb_autosuspend", !(root.status && root.status.usbAutosuspend) ? "true" : "false")
                          }
                        }
                      }

                      // 6. Keyboard Backlight Timeout
                      BorderSurface {
                        width: parent.width
                        height: kbdCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: kbdCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(10)

                          Row {
                            width: parent.width
                            Item {
                              width: parent.width - kbdStatusText.implicitWidth
                              height: kbdTitle.implicitHeight + kbdDesc.implicitHeight
                              Column {
                                anchors.fill: parent
                                spacing: 2
                                Text {
                                  id: kbdTitle
                                  text: "Keyboard Backlight Idle Auto-Dim"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                                Text {
                                  id: kbdDesc
                                  text: "Turn off keyboard illumination when inactive to preserve battery."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                }
                              }
                            }

                            Text {
                              id: kbdStatusText
                              text: root.status.kbdTimeout
                              color: root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }

                          Row {
                            width: parent.width
                            spacing: Style.space(8)
                            readonly property real btnWidth: (width - spacing * 4) / 5

                            Repeater {
                              model: [
                                { val: "30s", label: "30 sec" },
                                { val: "1m", label: "1 min" },
                                { val: "2m", label: "2 min" },
                                { val: "5m", label: "5 min" },
                                { val: "off", label: "Never" }
                              ]

                              delegate: Button {
                                width: parent.btnWidth
                                text: modelData.label
                                bordered: true
                                selected: root.status.kbdTimeout === modelData.val
                                onClicked: root.setOption("kbd_timeout", modelData.val)
                              }
                            }
                          }
                        }
                      }
                    }

                    // =========================================================
                    // TAB 1: SUSPEND BEHAVIOUR
                    // =========================================================
                    Column {
                      id: suspendTabContent
                      visible: root.currentTabId === "suspend"
                      width: parent.width
                      spacing: Style.space(12)

                      // Suspend Header & Recommended Options Card
                      BorderSurface {
                        width: parent.width
                        height: suspHeaderCol.implicitHeight + Style.space(28)
                        color: Util.alpha(Color.accent, 0.08)
                        borderSpec: Border.flat(Util.alpha(Color.accent, 0.3), 1)
                        radius: Style.cornerRadius

                        Column {
                          id: suspHeaderCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(16)
                          spacing: Style.space(6)

                          Row {
                            spacing: Style.space(10)

                            Text {
                              text: "󰤄"
                              color: Color.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.title
                              anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                              text: "Apple T2 Suspend Behaviour"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                              anchors.verticalCenter: parent.verticalCenter
                            }
                          }

                          Text {
                            width: parent.width
                            text: "Configure sleep states, lid behavior, and wake triggers tailored for MacBook hardware to optimize sleep wakeups."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                          }
                        }
                      }

                      // 1. System Sleep Mode (mem_sleep)
                      BorderSurface {
                        visible: root.status && root.status.memSleepModes && root.status.memSleepModes.length > 1
                        width: parent.width
                        height: memSleepCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: memSleepCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(10)

                          Row {
                            width: parent.width
                            Item {
                              width: parent.width - memSleepStatusText.implicitWidth
                              height: memSleepTitle.implicitHeight + memSleepDesc.implicitHeight
                              Column {
                                anchors.fill: parent
                                spacing: 2
                                Text {
                                  id: memSleepTitle
                                  text: "Sleep Mode"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                                Text {
                                  id: memSleepDesc
                                  text: "Choose how deeply your computer sleeps when suspended. Deep Sleep powers down internal components to save the most battery, while Modern Standby wakes up faster but consumes more battery during sleep."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                  wrapMode: Text.WordWrap
                                  width: parent.width
                                }
                              }
                            }

                            Text {
                              id: memSleepStatusText
                              text: Model.formatMemSleep(root.status.memSleep)
                              color: root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }

                          Row {
                            width: parent.width
                            spacing: Style.space(8)
                            readonly property var modes: (root.status && root.status.memSleepModes) ? root.status.memSleepModes : []
                            readonly property real btnWidth: modes.length > 0 ? (width - spacing * (modes.length - 1)) / modes.length : width

                            Repeater {
                              model: parent.modes

                              delegate: Button {
                                width: parent.btnWidth
                                text: Model.formatMemSleep(modelData)
                                bordered: true
                                enabled: !root.limineUpdating
                                selected: root.status.memSleep === modelData
                                onClicked: root.setMemSleep(modelData)
                              }
                            }
                          }
                        }
                      }

                      // 2. Lid Close Action on Battery
                      BorderSurface {
                        width: parent.width
                        height: lidCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: lidCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(10)

                          Row {
                            width: parent.width
                            Item {
                              width: parent.width - lidStatusText.implicitWidth
                              height: lidTitle.implicitHeight + lidDesc.implicitHeight
                              Column {
                                anchors.fill: parent
                                spacing: 2
                                Text {
                                  id: lidTitle
                                  text: "Lid Close Action (On Battery)"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                                Text {
                                  id: lidDesc
                                  text: "Action taken when closing the MacBook display while on battery."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                }
                              }
                            }

                            Text {
                              id: lidStatusText
                              text: Model.formatLidAction(root.status.lidAction)
                              color: root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }

                          Row {
                            width: parent.width
                            spacing: Style.space(8)
                            readonly property real btnWidth: (width - spacing * 3) / 4

                            Repeater {
                              model: [
                                { val: "suspend", label: "Suspend" },
                                { val: "ignore", label: "Do Nothing" },
                                { val: "lock", label: "Lock" },
                                { val: "hibernate", label: "Hibernate" }
                              ]

                              delegate: Button {
                                width: parent.btnWidth
                                text: modelData.label
                                bordered: true
                                selected: root.status.lidAction === modelData.val || (modelData.val === "suspend" && root.status.lidAction === "suspend-then-hibernate")
                                onClicked: root.setOption("lid_action", modelData.val)
                              }
                            }
                          }
                        }
                      }

                      // 3. Clamshell Mode on External Power
                      BorderSurface {
                        width: parent.width
                        height: clamshellCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: clamshellCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(10)

                          Row {
                            width: parent.width
                            Item {
                              width: parent.width - clamshellStatusText.implicitWidth
                              height: clamshellTitle.implicitHeight + clamshellDesc.implicitHeight
                              Column {
                                anchors.fill: parent
                                spacing: 2
                                Text {
                                  id: clamshellTitle
                                  text: "Clamshell Mode (External Power / Display)"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                                Text {
                                  id: clamshellDesc
                                  text: "Keep MacBook running with external monitor when lid is closed on charger."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                }
                              }
                            }

                            Text {
                              id: clamshellStatusText
                              text: root.status.clamshellMode ? "Clamshell (Stay Awake)" : "Always Suspend"
                              color: root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }

                          Row {
                            width: parent.width
                            spacing: Style.space(10)
                            readonly property real btnWidth: (width - spacing) / 2

                            Repeater {
                              model: [
                                { val: "true", label: "Stay Awake (Clamshell)" },
                                { val: "false", label: "Always Suspend" }
                              ]

                              delegate: Button {
                                width: parent.btnWidth
                                text: modelData.label
                                bordered: true
                                selected: String(root.status.clamshellMode) === modelData.val
                                onClicked: root.setOption("clamshell", modelData.val)
                              }
                            }
                          }
                        }
                      }

                      // 4. Wake on Lid Open Toggle
                      BorderSurface {
                        width: parent.width
                        height: Style.space(62)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(14)
                          anchors.rightMargin: Style.space(14)
                          anchors.verticalCenter: parent.verticalCenter

                          Column {
                            width: parent.width - wakeLidSwitch.width - Style.space(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                              text: "Wake on Lid Open (LID0)"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Automatically wake the system from sleep as soon as the display lid opens."
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          ToggleSwitch {
                            id: wakeLidSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: Boolean(root.status && root.status.wakeOnLid)
                            accent: root.accent
                            foreground: checked ? root.accent : root.foreground
                            onToggled: root.setOption("wake_lid", !(root.status && root.status.wakeOnLid) ? "on" : "off")
                          }
                        }
                      }

                      // 5. Wake on AC Charger Connect Toggle
                      BorderSurface {
                        width: parent.width
                        height: Style.space(62)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(14)
                          anchors.rightMargin: Style.space(14)
                          anchors.verticalCenter: parent.verticalCenter

                          Column {
                            width: parent.width - wakeAcSwitch.width - Style.space(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                              text: "Wake on AC Charger Connect (ADP1)"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Wake the MacBook from sleep when USB-C or MagSafe charger is attached."
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          ToggleSwitch {
                            id: wakeAcSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: Boolean(root.status && root.status.wakeOnAc)
                            accent: root.accent
                            foreground: checked ? root.accent : root.foreground
                            onToggled: root.setOption("wake_ac", !(root.status && root.status.wakeOnAc) ? "on" : "off")
                          }
                        }
                      }

                      // 6. Hibernate After Prolonged Sleep Delay
                      BorderSurface {
                        width: parent.width
                        height: hibCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: hibCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(10)

                          Row {
                            width: parent.width
                            Item {
                              width: parent.width - hibStatusText.implicitWidth
                              height: hibTitle.implicitHeight + hibDesc.implicitHeight
                              Column {
                                anchors.fill: parent
                                spacing: 2
                                Text {
                                  id: hibTitle
                                  text: "Hibernate Delay (Suspend-Then-Hibernate)"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                                Text {
                                  id: hibDesc
                                  text: "Transition from sleep to hibernation after delay to avoid dead battery in bag."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                }
                              }
                            }

                            Text {
                              id: hibStatusText
                              text: Model.formatHibernateDelay(root.status.hibernateDelay)
                              color: root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                          }

                          Row {
                            width: parent.width
                            spacing: Style.space(8)
                            readonly property real btnWidth: (width - spacing * 3) / 4

                            Repeater {
                              model: [
                                { val: "off", label: "Never" },
                                { val: "30min", label: "30 min" },
                                { val: "1hour", label: "1 hour" },
                                { val: "2hours", label: "2 hours" }
                              ]

                              delegate: Button {
                                width: parent.btnWidth
                                text: modelData.label
                                bordered: true
                                selected: root.status.hibernateDelay === modelData.val
                                onClicked: root.setOption("hibernate_delay", modelData.val)
                              }
                            }
                          }
                        }
                      }

                      // 7. Touch Bar Blanking on Sleep
                      BorderSurface {
                        width: parent.width
                        height: Style.space(62)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(14)
                          anchors.rightMargin: Style.space(14)
                          anchors.verticalCenter: parent.verticalCenter

                          Column {
                            width: parent.width - tbSwitch.width - Style.space(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                              text: "Touch Bar Blanking on Sleep"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Ensures the OLED Touch Bar is powered off cleanly immediately upon suspend."
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          ToggleSwitch {
                            id: tbSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: Boolean(root.status && root.status.touchbarBlank)
                            accent: root.accent
                            foreground: checked ? root.accent : root.foreground
                            onToggled: root.setOption("touchbar_blank", !(root.status && root.status.touchbarBlank) ? "true" : "false")
                          }
                        }
                      }
                    }

                    // =========================================================
                    // TAB 2: KEYBINDINGS
                    // =========================================================
                    Column {
                      id: keybindingsTabContent
                      visible: root.currentTabId === "keybindings"
                      width: parent.width
                      spacing: Style.space(12)

                      BorderSurface {
                        width: parent.width
                        height: kbHeaderCol.implicitHeight + Style.space(28)
                        color: Util.alpha(Color.accent, 0.08)
                        borderSpec: Border.flat(Util.alpha(Color.accent, 0.3), 1)
                        radius: Style.cornerRadius

                        Column {
                          id: kbHeaderCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(16)
                          spacing: Style.space(6)

                          Row {
                            spacing: Style.space(10)

                            Text {
                              text: "󰌘"
                              color: Color.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.title
                              anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                              text: "Apple T2 Keyboard & Keybindings"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                              anchors.verticalCenter: parent.verticalCenter
                            }
                          }

                          Text {
                            width: parent.width
                            text: "Configure keyboard shortcuts for specific tasks such as Select All and Delete, with Mac defaults tailored for Apple hardware."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                          }
                        }
                      }

                      // Tasks Keybindings Card (Compact Unified Card)
                      BorderSurface {
                        width: parent.width
                        height: kbTasksCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: kbTasksCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(14)


                          Text {
                            text: "CUSTOMIZABLE SHORTCUTS"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 0.8
                          }

                          // 1. Task: Select All
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Row {
                              width: parent.width
                              spacing: Style.space(8)

                              Text {
                                id: t1Icon
                                text: "󰒅"
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                id: t1Title
                                text: "Select All"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                text: "Selects all content in the active window"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - t1Icon.implicitWidth - t1Title.implicitWidth - Style.space(16))
                              }
                            }

                            Row {
                              id: t1Btns
                              width: parent.width
                              spacing: Style.space(6)
                              readonly property real btnWidth: (width - spacing * 2) / 3

                              readonly property string cur: root.status && root.status.keybindingSelectAll ? root.status.keybindingSelectAll : "CTRL + A"
                              readonly property bool isMac: Model.normalizeChord(cur) === Model.normalizeChord("SUPER + A")
                              readonly property bool isLinux: Model.normalizeChord(cur) === Model.normalizeChord("CTRL + A")
                              readonly property bool isCustom: !isMac && !isLinux

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CMD + A"
                                tooltipText: "Mac preset (Command + A)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isMac
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_select_all", "SUPER + A")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CTRL + A"
                                tooltipText: "Standard Linux preset"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isLinux
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_select_all", "CTRL + A")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: "󰌌"
                                text: parent.isCustom ? Model.formatChordForDisplay(parent.cur) : "Custom…"
                                tooltipText: parent.isCustom ? ("Custom shortcut: " + Model.formatChordForDisplay(parent.cur) + "\nClick to re-record") : "Record custom key combination"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isCustom
                                accent: root.accent
                                onClicked: root.openKeyRecorder("keybinding_select_all", "Select All")
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // 2. Task: Forward Delete
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Row {
                              width: parent.width
                              spacing: Style.space(8)

                              Text {
                                id: t2Icon
                                text: "󰧧"
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                id: t2Title
                                text: "Forward Delete"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                text: "Mac keyboards lack dedicated Delete key"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - t2Icon.implicitWidth - t2Title.implicitWidth - Style.space(16))
                              }
                            }

                            Row {
                              id: t2Btns
                              width: parent.width
                              spacing: Style.space(6)
                              readonly property real btnWidth: (width - spacing * 2) / 3

                              readonly property string cur: root.status && root.status.keybindingDelete ? root.status.keybindingDelete : "DELETE"
                              readonly property bool isMac: Model.normalizeChord(cur) === Model.normalizeChord("SUPER + BACKSPACE")
                              readonly property bool isLinux: Model.normalizeChord(cur) === Model.normalizeChord("DELETE")
                              readonly property bool isCustom: !isMac && !isLinux

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CMD + BACKSPACE"
                                tooltipText: "Mac preset (Command + Backspace)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isMac
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_delete", "SUPER + BACKSPACE")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "DELETE"
                                tooltipText: "Standard Delete key"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isLinux
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_delete", "DELETE")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: "󰌌"
                                text: parent.isCustom ? Model.formatChordForDisplay(parent.cur) : "Custom…"
                                tooltipText: parent.isCustom ? ("Custom shortcut: " + Model.formatChordForDisplay(parent.cur) + "\nClick to re-record") : "Record custom key combination"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isCustom
                                accent: root.accent
                                onClicked: root.openKeyRecorder("keybinding_delete", "Forward Delete")
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // 3. Task: Find
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Row {
                              width: parent.width
                              spacing: Style.space(8)

                              Text {
                                id: t3Icon
                                text: "󰍉"
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                id: t3Title
                                text: "Find in Document"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                text: "Search text in pages, browsers, and editors"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - t3Icon.implicitWidth - t3Title.implicitWidth - Style.space(16))
                              }
                            }

                            Row {
                              id: t3Btns
                              width: parent.width
                              spacing: Style.space(6)
                              readonly property real btnWidth: (width - spacing * 2) / 3

                              readonly property string cur: root.status && root.status.keybindingFind ? root.status.keybindingFind : "CTRL + F"
                              readonly property bool isMac: Model.normalizeChord(cur) === Model.normalizeChord("SUPER + F")
                              readonly property bool isLinux: Model.normalizeChord(cur) === Model.normalizeChord("CTRL + F")
                              readonly property bool isCustom: !isMac && !isLinux

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CMD + F"
                                tooltipText: "Mac preset (Command + F)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isMac
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_find", "SUPER + F")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CTRL + F"
                                tooltipText: "Standard Linux preset (Control + F)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isLinux
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_find", "CTRL + F")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: "󰌌"
                                text: parent.isCustom ? Model.formatChordForDisplay(parent.cur) : "Custom…"
                                tooltipText: parent.isCustom ? ("Custom shortcut: " + Model.formatChordForDisplay(parent.cur) + "\nClick to re-record") : "Record custom key combination"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isCustom
                                accent: root.accent
                                onClicked: root.openKeyRecorder("keybinding_find", "Find")
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // 4. Task: Toggle Fullscreen
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Row {
                              width: parent.width
                              spacing: Style.space(8)

                              Text {
                                id: t4Icon
                                text: "󰊓"
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                id: t4Title
                                text: "Toggle Fullscreen"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                text: "Toggle active window fullscreen mode"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - t4Icon.implicitWidth - t4Title.implicitWidth - Style.space(16))
                              }
                            }

                            Row {
                              id: t4Btns
                              width: parent.width
                              spacing: Style.space(6)
                              readonly property real btnWidth: (width - spacing * 2) / 3

                              readonly property string cur: root.status && root.status.keybindingFullscreen ? root.status.keybindingFullscreen : "SUPER + F"
                              readonly property bool isMac: Model.normalizeChord(cur) === Model.normalizeChord("SUPER + CTRL + F")
                              readonly property bool isLinux: Model.normalizeChord(cur) === Model.normalizeChord("SUPER + F")
                              readonly property bool isCustom: !isMac && !isLinux

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CMD + CTRL + F"
                                tooltipText: "Mac preset (Cmd + Ctrl + F)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isMac
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_fullscreen", "SUPER + CTRL + F")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CMD + F"
                                tooltipText: "Standard Omarchy preset (Cmd + F)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isLinux
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_fullscreen", "SUPER + F")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: "󰌌"
                                text: parent.isCustom ? Model.formatChordForDisplay(parent.cur) : "Custom…"
                                tooltipText: parent.isCustom ? ("Custom shortcut: " + Model.formatChordForDisplay(parent.cur) + "\nClick to re-record") : "Record custom key combination"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isCustom
                                accent: root.accent
                                onClicked: root.openKeyRecorder("keybinding_fullscreen", "Toggle Fullscreen")
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // 5. Task: Undo
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Row {
                              width: parent.width
                              spacing: Style.space(8)

                              Text {
                                id: t5Icon
                                text: "󰕌"
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                id: t5Title
                                text: "Undo"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                text: "Undo last action in applications"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - t5Icon.implicitWidth - t5Title.implicitWidth - Style.space(16))
                              }
                            }

                            Row {
                              id: t5Btns
                              width: parent.width
                              spacing: Style.space(6)
                              readonly property real btnWidth: (width - spacing * 2) / 3

                              readonly property string cur: root.status && root.status.keybindingUndo ? root.status.keybindingUndo : "CTRL + Z"
                              readonly property bool isMac: Model.normalizeChord(cur) === Model.normalizeChord("SUPER + Z")
                              readonly property bool isLinux: Model.normalizeChord(cur) === Model.normalizeChord("CTRL + Z")
                              readonly property bool isCustom: !isMac && !isLinux

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CMD + Z"
                                tooltipText: "Mac preset (Command + Z)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isMac
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_undo", "SUPER + Z")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CTRL + Z"
                                tooltipText: "Standard Linux preset (Control + Z)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isLinux
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_undo", "CTRL + Z")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: "󰌌"
                                text: parent.isCustom ? Model.formatChordForDisplay(parent.cur) : "Custom…"
                                tooltipText: parent.isCustom ? ("Custom shortcut: " + Model.formatChordForDisplay(parent.cur) + "\nClick to re-record") : "Record custom key combination"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isCustom
                                accent: root.accent
                                onClicked: root.openKeyRecorder("keybinding_undo", "Undo")
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // 6. Task: Redo
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Row {
                              width: parent.width
                              spacing: Style.space(8)

                              Text {
                                id: t6Icon
                                text: "󰑎"
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                id: t6Title
                                text: "Redo"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                text: "Redo last undone action in applications"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - t6Icon.implicitWidth - t6Title.implicitWidth - Style.space(16))
                              }
                            }

                            Row {
                              id: t6Btns
                              width: parent.width
                              spacing: Style.space(6)
                              readonly property real btnWidth: (width - spacing * 2) / 3

                              readonly property string cur: root.status && root.status.keybindingRedo ? root.status.keybindingRedo : "CTRL + SHIFT + Z"
                              readonly property bool isMac: Model.normalizeChord(cur) === Model.normalizeChord("SUPER + SHIFT + Z")
                              readonly property bool isLinux: Model.normalizeChord(cur) === Model.normalizeChord("CTRL + SHIFT + Z")
                              readonly property bool isCustom: !isMac && !isLinux

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CMD + SHIFT + Z"
                                tooltipText: "Mac preset (Command + Shift + Z)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isMac
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_redo", "SUPER + SHIFT + Z")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CTRL + SHIFT + Z"
                                tooltipText: "Standard Linux preset (Control + Shift + Z)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isLinux
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_redo", "CTRL + SHIFT + Z")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: "󰌌"
                                text: parent.isCustom ? Model.formatChordForDisplay(parent.cur) : "Custom…"
                                tooltipText: parent.isCustom ? ("Custom shortcut: " + Model.formatChordForDisplay(parent.cur) + "\nClick to re-record") : "Record custom key combination"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isCustom
                                accent: root.accent
                                onClicked: root.openKeyRecorder("keybinding_redo", "Redo")
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // 7. Task: Save
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Row {
                              width: parent.width
                              spacing: Style.space(8)

                              Text {
                                id: t7Icon
                                text: "󰆓"
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                id: t7Title
                                text: "Save"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                text: "Save current document or file"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - t7Icon.implicitWidth - t7Title.implicitWidth - Style.space(16))
                              }
                            }

                            Row {
                              id: t7Btns
                              width: parent.width
                              spacing: Style.space(6)
                              readonly property real btnWidth: (width - spacing * 2) / 3

                              readonly property string cur: root.status && root.status.keybindingSave ? root.status.keybindingSave : "CTRL + S"
                              readonly property bool isMac: Model.normalizeChord(cur) === Model.normalizeChord("SUPER + S")
                              readonly property bool isLinux: Model.normalizeChord(cur) === Model.normalizeChord("CTRL + S")
                              readonly property bool isCustom: !isMac && !isLinux

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CMD + S"
                                tooltipText: "Mac preset (Command + S)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isMac
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_save", "SUPER + S")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CTRL + S"
                                tooltipText: "Standard Linux preset (Control + S)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isLinux
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_save", "CTRL + S")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: "󰌌"
                                text: parent.isCustom ? Model.formatChordForDisplay(parent.cur) : "Custom…"
                                tooltipText: parent.isCustom ? ("Custom shortcut: " + Model.formatChordForDisplay(parent.cur) + "\nClick to re-record") : "Record custom key combination"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isCustom
                                accent: root.accent
                                onClicked: root.openKeyRecorder("keybinding_save", "Save")
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // 8. Task: Cut
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Row {
                              width: parent.width
                              spacing: Style.space(8)

                              Text {
                                id: t8Icon
                                text: "󰆐"
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                id: t8Title
                                text: "Cut"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }

                              Text {
                                text: "Cut selected text or item to clipboard"
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                width: Math.max(0, parent.width - t8Icon.implicitWidth - t8Title.implicitWidth - Style.space(16))
                              }
                            }

                            Row {
                              id: t8Btns
                              width: parent.width
                              spacing: Style.space(6)
                              readonly property real btnWidth: (width - spacing * 2) / 3

                              readonly property string cur: root.status && root.status.keybindingCut ? root.status.keybindingCut : "CTRL + X"
                              readonly property bool isMac: Model.normalizeChord(cur) === Model.normalizeChord("SUPER + X")
                              readonly property bool isLinux: Model.normalizeChord(cur) === Model.normalizeChord("CTRL + X")
                              readonly property bool isCustom: !isMac && !isLinux

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CMD + X"
                                tooltipText: "Mac preset (Command + X)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isMac
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_cut", "SUPER + X")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: ""
                                text: "CTRL + X"
                                tooltipText: "Standard Linux preset (Control + X)"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isLinux
                                accent: root.accent
                                onClicked: root.checkAndApplyKeybinding("keybinding_cut", "CTRL + X")
                              }

                              Button {
                                width: parent.btnWidth
                                iconText: "󰌌"
                                text: parent.isCustom ? Model.formatChordForDisplay(parent.cur) : "Custom…"
                                tooltipText: parent.isCustom ? ("Custom shortcut: " + Model.formatChordForDisplay(parent.cur) + "\nClick to re-record") : "Record custom key combination"
                                bordered: true
                                fontSize: Style.font.caption
                                iconSize: Style.font.bodySmall
                                height: Style.space(30)
                                selected: parent.isCustom
                                accent: root.accent
                                onClicked: root.openKeyRecorder("keybinding_cut", "Cut")
                              }
                            }
                          }
                        }
                      }

                      // Changed System Shortcuts Section (Dynamic - only visible when overrides exist)
                      BorderSurface {
                        visible: Model.getSystemOverridesList(root.status).length > 0
                        width: parent.width
                        height: changedSysCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: changedSysCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(14)

                          Text {
                            text: "CHANGED SYSTEM SHORTCUTS"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 0.8
                          }

                          Repeater {
                            model: Model.getSystemOverridesList(root.status)

                            delegate: Column {
                              width: parent.width
                              spacing: Style.space(12)

                              Column {
                                width: parent.width
                                spacing: Style.space(8)

                                // Top row: Icon, Title, Description right from title
                                Row {
                                  width: parent.width
                                  spacing: Style.space(8)

                                  Text {
                                    id: sIcon
                                    text: "󰌌"
                                    color: root.accent
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    anchors.verticalCenter: parent.verticalCenter
                                  }

                                  Text {
                                    id: sTitle
                                    text: modelData.action
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                  }

                                  Text {
                                    text: "Original: " + Model.formatChordForDisplay(modelData.defaultChord)
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    width: Math.max(0, parent.width - sIcon.implicitWidth - sTitle.implicitWidth - Style.space(16))
                                  }
                                }

                                // Bottom row: 3 Buttons sharing equal width
                                Row {
                                  id: sBtns
                                  width: parent.width
                                  spacing: Style.space(6)
                                  readonly property real btnWidth: (width - spacing * 2) / 3

                                  readonly property string cur: modelData.currentChord || ""
                                  readonly property string defChord: modelData.defaultChord || ""
                                  readonly property string recChord: modelData.recommendedChord || ""
                                  readonly property bool isDefault: cur === defChord
                                  readonly property bool isRec: cur === recChord && !isDefault
                                  readonly property bool isCustom: !isDefault && !isRec

                                  Button {
                                    width: parent.btnWidth
                                    iconText: "󰁌"
                                    text: Model.formatChordForDisplay(parent.defChord)
                                    tooltipText: "System default: " + Model.formatChordForDisplay(parent.defChord) + "\nClick to restore default"
                                    bordered: true
                                    fontSize: Style.font.caption
                                    iconSize: Style.font.bodySmall
                                    height: Style.space(30)
                                    selected: parent.isDefault
                                    accent: root.accent
                                    onClicked: root.resetSystemKeybinding(modelData.action)
                                  }

                                  Button {
                                    width: parent.btnWidth
                                    iconText: ""
                                    text: Model.formatChordForDisplay(parent.recChord)
                                    tooltipText: "Recommended alternative: " + Model.formatChordForDisplay(parent.recChord)
                                    bordered: true
                                    fontSize: Style.font.caption
                                    iconSize: Style.font.bodySmall
                                    height: Style.space(30)
                                    selected: parent.isRec
                                    accent: root.accent
                                    onClicked: root.setSystemKeybinding(modelData.action, parent.recChord, parent.defChord, modelData.dispatcher, modelData.arg)
                                  }

                                  Button {
                                    width: parent.btnWidth
                                    iconText: "󰌌"
                                    text: parent.isCustom ? Model.formatChordForDisplay(parent.cur) : "Custom…"
                                    tooltipText: parent.isCustom ? ("Custom shortcut: " + Model.formatChordForDisplay(parent.cur) + "\nClick to re-record") : "Record custom key combination"
                                    bordered: true
                                    fontSize: Style.font.caption
                                    iconSize: Style.font.bodySmall
                                    height: Style.space(30)
                                    selected: parent.isCustom
                                    accent: root.accent
                                    onClicked: root.openSystemKeyRecorder(modelData.action, modelData.defaultChord, modelData.dispatcher, modelData.arg)
                                  }
                                }
                              }

                              PanelSeparator {
                                visible: index < Model.getSystemOverridesList(root.status).length - 1
                                width: parent.width
                                foreground: root.foreground
                              }
                            }
                          }
                        }
                      }

                      // Conflicting Shortcuts Section (Dynamic - only visible when conflicts exist)
                      BorderSurface {
                        visible: Model.getActiveConflicts(root.status).length > 0
                        width: parent.width
                        height: conflictingCol.implicitHeight + Style.space(28)
                        color: Util.alpha(Color.warning || root.accent, 0.05)
                        borderSpec: Border.flat(Util.alpha(Color.warning || root.accent, 0.4), 1)
                        radius: Style.cornerRadius

                        Column {
                          id: conflictingCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(14)

                          Row {
                            spacing: Style.space(8)
                            anchors.verticalCenter: undefined
                            Text {
                              text: "󰀪"
                              color: Color.warning || root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                            }
                            Text {
                              text: "CONFLICTING SHORTCUTS"
                              color: Color.warning || root.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              font.bold: true
                              font.letterSpacing: 0.8
                            }
                          }

                          Repeater {
                            model: Model.getActiveConflicts(root.status)

                            delegate: Column {
                              width: parent.width
                              spacing: Style.space(12)

                              Column {
                                width: parent.width
                                spacing: Style.space(8)

                                // Top row: Icon, Title, Description right from title
                                Row {
                                  width: parent.width
                                  spacing: Style.space(8)

                                  Text {
                                    id: cfIcon
                                    text: "󰀪"
                                    color: Color.warning || root.accent
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    anchors.verticalCenter: parent.verticalCenter
                                  }

                                  Text {
                                    id: cfTitle
                                    text: Model.formatChordForDisplay(modelData.chord)
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                  }

                                  Text {
                                    text: modelData.action1 + " conflicts with " + modelData.action2
                                    color: Color.warning || root.accent
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    width: Math.max(0, parent.width - cfIcon.implicitWidth - cfTitle.implicitWidth - Style.space(16))
                                  }
                                }

                                // Bottom row: 3 Buttons sharing equal width
                                Row {
                                  id: cfBtns
                                  width: parent.width
                                  spacing: Style.space(6)
                                  readonly property real btnWidth: (width - spacing * 2) / 3

                                  Button {
                                    width: parent.btnWidth
                                    iconText: "󰀪"
                                    text: "Resolve…"
                                    tooltipText: "Open dialog to resolve conflict between " + modelData.action1 + " and " + modelData.action2
                                    bordered: true
                                    fontSize: Style.font.caption
                                    iconSize: Style.font.bodySmall
                                    height: Style.space(30)
                                    accent: Color.warning || root.accent
                                    onClicked: root.triggerConflictResolution(modelData)
                                  }

                                  Button {
                                    width: parent.btnWidth
                                    iconText: ""
                                    text: Model.formatChordForDisplay(modelData.recommendedChord)
                                    tooltipText: "Move " + modelData.action2 + " to " + Model.formatChordForDisplay(modelData.recommendedChord)
                                    bordered: true
                                    fontSize: Style.font.caption
                                    iconSize: Style.font.bodySmall
                                    height: Style.space(30)
                                    accent: root.accent
                                    onClicked: {
                                      if (modelData.source === "system") {
                                        root.setSystemKeybinding(modelData.action2, modelData.recommendedChord, modelData.defaultChord, modelData.dispatcher, modelData.arg)
                                      } else {
                                        root.checkAndApplyKeybinding(modelData.taskKey2, modelData.recommendedChord)
                                      }
                                    }
                                  }

                                  Button {
                                    width: parent.btnWidth
                                    iconText: "󰌌"
                                    text: "Custom…"
                                    tooltipText: "Choose a custom shortcut for " + modelData.action2
                                    bordered: true
                                    fontSize: Style.font.caption
                                    iconSize: Style.font.bodySmall
                                    height: Style.space(30)
                                    accent: root.accent
                                    onClicked: {
                                      if (modelData.source === "system") {
                                        root.openSystemKeyRecorder(modelData.action2, modelData.defaultChord, modelData.dispatcher, modelData.arg)
                                      } else {
                                        root.openKeyRecorder(modelData.taskKey2, modelData.action2)
                                      }
                                    }
                                  }
                                }
                              }

                              PanelSeparator {
                                visible: index < Model.getActiveConflicts(root.status).length - 1
                                width: parent.width
                                foreground: root.foreground
                              }
                            }
                          }
                        }
                      }

                      // Keybindings Quick Reference & Info Card
                      BorderSurface {
                        width: parent.width
                        height: kbInfoCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: kbInfoCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(10)

                          Text {
                            text: "KEYBOARD SHORTCUTS REFERENCE"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 0.8
                          }

                          Text {
                            width: parent.width
                            text: "On Linux with Apple T2 MacBooks, the Command (⌘) key acts as Super / Win, and Option (⌥) maps to Alt. Function keys can be toggled between standard F1–F12 and multimedia actions."
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: Text.WordWrap
                          }
                        }
                      }
                    }

                    // =========================================================
                    // TAB: TRACKPAD
                    // =========================================================
                    Column {
                      id: trackpadTabContent
                      visible: root.currentTabId === "trackpad"
                      width: parent.width
                      spacing: Style.space(12)

                      // 1. Hero Card: Apple Force Touch Trackpad Status
                      BorderSurface {
                        width: parent.width
                        height: tpHeaderCol.implicitHeight + Style.space(28)
                        color: Util.alpha(Color.accent, 0.08)
                        borderSpec: Border.flat(Util.alpha(Color.accent, 0.3), 1)
                        radius: Style.cornerRadius

                        Column {
                          id: tpHeaderCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(16)
                          spacing: Style.space(10)

                          Row {
                            width: parent.width
                            spacing: Style.space(10)

                            Text {
                              text: "󱑣"
                              color: Color.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.title
                              anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                              width: parent.width - restartTpBtn.width - Style.space(50)
                              anchors.verticalCenter: parent.verticalCenter
                              spacing: 2

                              Text {
                                text: "Apple Force Touch Trackpad"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: (root.status && root.status.trackpad && root.status.trackpad.device)
                                  ? (root.status.trackpad.device + " · Magic Trackpad 2 Engine")
                                  : "Apple Magic Trackpad 2 Engine (USB 05AC:027C)"
                                color: Color.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                elide: Text.ElideRight
                                width: parent.width
                              }
                            }

                            Button {
                              id: restartTpBtn
                              text: "Restart Driver"
                              iconText: "󰑐"
                              bordered: true
                              fontSize: Style.font.caption
                              height: Style.space(28)
                              anchors.verticalCenter: parent.verticalCenter
                              tooltipText: "Reload the trackpad input driver if touch tracking or gestures become unresponsive"
                              onClicked: root.restartTrackpad()
                            }
                          }

                          Text {
                            width: parent.width
                            text: "Apple MacBooks feature a glass Force Touch trackpad with haptic feedback. Configure motion sensitivity, natural scroll direction, multi-finger gestures, and palm rejection for Linux."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                          }
                        }
                      }

                      // 2. Pointer Motion & Scrolling Card
                      BorderSurface {
                        width: parent.width
                        height: tpMotionCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: tpMotionCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(14)

                          Text {
                            text: "POINTER & SCROLLING"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 0.8
                          }

                          // Option: Pointer Speed
                          Column {
                            width: parent.width
                            spacing: Style.space(6)

                            Row {
                              width: parent.width

                              Column {
                                width: parent.width - speedValText.implicitWidth
                                spacing: 2

                                Text {
                                  text: "Pointer Tracking Speed"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }

                                Text {
                                  text: "Overall cursor sensitivity and movement speed across the trackpad surface."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                }
                              }

                              Text {
                                id: speedValText
                                text: {
                                  var sens = (root.status && root.status.trackpad) ? root.status.trackpad.sensitivity : 0.0
                                  var pct = Model.speedPercentFromSensitivity(sens)
                                  return pct + "%" + (pct === 50 ? " (Default)" : "")
                                }
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }
                            }

                            OmappleSlider {
                              width: parent.width
                              height: Style.space(24)
                              bar: root.bar
                              minimum: 0
                              maximum: 100
                              step: 5
                              integer: true
                              value: Model.speedPercentFromSensitivity(root.status && root.status.trackpad ? root.status.trackpad.sensitivity : 0.0)
                              onMoved: function(v) {
                                root.setOption("trackpad_sensitivity", Model.sensitivityFromSpeedPercent(v))
                              }
                              onReleased: function(v) {
                                root.setOption("trackpad_sensitivity", Model.sensitivityFromSpeedPercent(v))
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Option: Acceleration Profile
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Column {
                              width: parent.width
                              spacing: 2

                              Text {
                                text: "Pointer Acceleration Profile"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Adaptive dynamically increases cursor travel during rapid finger flicks (standard macOS behavior), while Flat maintains a strict linear 1:1 speed ratio."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            Row {
                              width: parent.width
                              spacing: Style.space(8)
                              readonly property real btnWidth: (width - spacing) / 2

                              Button {
                                width: parent.btnWidth
                                text: "Adaptive (macOS Default)"
                                iconText: ""
                                bordered: true
                                selected: !(root.status && root.status.trackpad && root.status.trackpad.accelProfile === "flat")
                                onClicked: root.setOption("trackpad_accel_profile", "adaptive")
                              }

                              Button {
                                width: parent.btnWidth
                                text: "Flat (Linear 1:1)"
                                iconText: "󰄶"
                                bordered: true
                                selected: Boolean(root.status && root.status.trackpad && root.status.trackpad.accelProfile === "flat")
                                onClicked: root.setOption("trackpad_accel_profile", "flat")
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Option: Scroll Speed
                          Column {
                            width: parent.width
                            spacing: Style.space(6)

                            Row {
                              width: parent.width

                              Column {
                                width: parent.width - scrollValText.implicitWidth
                                spacing: 2

                                Text {
                                  text: "Two-Finger Scroll Speed"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }

                                Text {
                                  text: "Speed multiplier for vertical and horizontal two-finger scrolling."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                }
                              }

                              Text {
                                id: scrollValText
                                text: {
                                  var f = (root.status && root.status.trackpad && root.status.trackpad.scrollFactor !== undefined)
                                    ? root.status.trackpad.scrollFactor
                                    : 0.64
                                  return Number(f).toFixed(2) + "x"
                                }
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                              }
                            }

                            OmappleSlider {
                              width: parent.width
                              height: Style.space(24)
                              bar: root.bar
                              minimum: 10
                              maximum: 200
                              step: 5
                              integer: true
                              value: Math.round(((root.status && root.status.trackpad ? root.status.trackpad.scrollFactor : 0.64)) * 100)
                              onMoved: function(v) {
                                root.setOption("trackpad_scroll_factor", (v / 100.0).toFixed(2))
                              }
                              onReleased: function(v) {
                                root.setOption("trackpad_scroll_factor", (v / 100.0).toFixed(2))
                              }
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Option: Natural Scrolling
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - natScrollSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Natural Scrolling"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Invert scroll direction so page content moves smoothly in the direction of your fingers (standard macOS scrolling)."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: natScrollSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.naturalScroll)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_natural_scroll", !(root.status && root.status.trackpad && root.status.trackpad.naturalScroll) ? "true" : "false")
                            }
                          }
                        }
                      }

                      // 3. Clicking & Multi-Touch Gestures Card
                      BorderSurface {
                        width: parent.width
                        height: tpGesturesCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: tpGesturesCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(14)

                          Text {
                            text: "CLICKING & GESTURES"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 0.8
                          }

                          // Tap to Click
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - tapClickSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Tap to Click"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Tap the trackpad surface with 1 finger for left-click and 2 fingers for right-click without having to depress the physical click mechanism."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: tapClickSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.tapToClick)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_tap_to_click", !(root.status && root.status.trackpad && root.status.trackpad.tapToClick) ? "true" : "false")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Two-Finger Secondary Click
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - clickfingerSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Two-Finger Secondary Click"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Click anywhere on the trackpad with two fingers to trigger right-click (Mac style) instead of pressing the bottom-right corner."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: clickfingerSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.clickfingerBehavior)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_clickfinger_behavior", !(root.status && root.status.trackpad && root.status.trackpad.clickfingerBehavior) ? "true" : "false")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Three-Finger Drag
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - drag3fgSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Three-Finger Drag"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Classic macOS gesture: place three fingers on the trackpad to drag windows, move items, or select text without clicking down. Disables 3-finger workspace swiping."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: drag3fgSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.drag3fg > 0)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_drag_3fg", (root.status && root.status.trackpad && root.status.trackpad.drag3fg > 0) ? "0" : "1")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Tap and Drag
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - tapDragSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Tap and Drag"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Double-tap and slide without physical click to drag windows or highlight passages of text."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: tapDragSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.tapAndDrag)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_tap_and_drag", !(root.status && root.status.trackpad && root.status.trackpad.tapAndDrag) ? "true" : "false")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Drag Lock
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - dragLockSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Tap Drag Lock"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Maintains drag selection when you briefly lift and reposition your finger across the trackpad, ending only after a single tap."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: dragLockSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.dragLock)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_drag_lock", !(root.status && root.status.trackpad && root.status.trackpad.dragLock) ? "true" : "false")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Middle Button Emulation
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - midEmulSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Middle Click Emulation"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Simulate a middle mouse click by pressing left and right buttons simultaneously."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: midEmulSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.middleButtonEmulation)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_middle_button_emulation", !(root.status && root.status.trackpad && root.status.trackpad.middleButtonEmulation) ? "true" : "false")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // 3-Finger Workspace Swiping
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - swipeWorkspacesSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "3-Finger Workspace Swiping"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Swipe horizontally across the trackpad with three fingers to switch between virtual workspaces. Disables 3-finger drag."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: swipeWorkspacesSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.swipeWorkspaces)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_swipe_workspaces", !(root.status && root.status.trackpad && root.status.trackpad.swipeWorkspaces) ? "true" : "false")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Tap Button Mapping
                          Column {
                            width: parent.width
                            spacing: Style.space(8)

                            Column {
                              width: parent.width
                              spacing: 2

                              Text {
                                text: "Multi-Finger Tap Button Order"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Configure tap finger mapping: LRM maps 2 fingers to Right-Click and 3 fingers to Middle-Click (Mac style). LMR maps 2 fingers to Middle-Click and 3 fingers to Right-Click (X11 style)."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            Row {
                              width: parent.width
                              spacing: Style.space(8)
                              readonly property real btnWidth: (width - spacing) / 2

                              Button {
                                width: parent.btnWidth
                                text: "LRM: Left, Right, Middle (Mac)"
                                iconText: ""
                                bordered: true
                                selected: !(root.status && root.status.trackpad && root.status.trackpad.tapButtonMap === "lmr")
                                onClicked: root.setOption("trackpad_tap_button_map", "lrm")
                              }

                              Button {
                                width: parent.btnWidth
                                text: "LMR: Left, Middle, Right (X11)"
                                iconText: "󰄶"
                                bordered: true
                                selected: Boolean(root.status && root.status.trackpad && root.status.trackpad.tapButtonMap === "lmr")
                                onClicked: root.setOption("trackpad_tap_button_map", "lmr")
                              }
                            }
                          }
                        }
                      }

                      // 4. Palm Rejection & Axis Tuning Card
                      BorderSurface {
                        width: parent.width
                        height: tpPalmCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: tpPalmCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(14)

                          Text {
                            text: "PALM REJECTION & ADVANCED"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.letterSpacing: 0.8
                          }

                          // Disable While Typing
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - dwtSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Disable While Typing (Palm Rejection)"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Temporarily locks trackpad input while typing on the keyboard to prevent palms and thumbs from triggering accidental cursor movements."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: dwtSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.disableWhileTyping)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_disable_while_typing", !(root.status && root.status.trackpad && root.status.trackpad.disableWhileTyping) ? "true" : "false")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Left-Handed Mode
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - leftHandSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Left-Handed Mode"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Swaps physical primary (left) and secondary (right) button triggers for left-handed usage."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: leftHandSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.leftHanded)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_left_handed", !(root.status && root.status.trackpad && root.status.trackpad.leftHanded) ? "true" : "false")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Invert Horizontal Axis (Flip X)
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - flipXSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Invert Horizontal Axis (Flip X)"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Invert horizontal left-to-right trackpad pointer motion."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: flipXSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.flipX)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_flip_x", !(root.status && root.status.trackpad && root.status.trackpad.flipX) ? "true" : "false")
                            }
                          }

                          PanelSeparator {
                            width: parent.width
                            foreground: root.foreground
                          }

                          // Invert Vertical Axis (Flip Y)
                          Row {
                            width: parent.width

                            Column {
                              width: parent.width - flipYSwitch.width - Style.space(14)
                              spacing: 2
                              anchors.verticalCenter: parent.verticalCenter

                              Text {
                                text: "Invert Vertical Axis (Flip Y)"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }

                              Text {
                                text: "Invert vertical up-to-down trackpad pointer motion."
                                color: root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }

                            ToggleSwitch {
                              id: flipYSwitch
                              anchors.verticalCenter: parent.verticalCenter
                              checked: Boolean(root.status && root.status.trackpad && root.status.trackpad.flipY)
                              accent: root.accent
                              foreground: checked ? root.accent : root.foreground
                              onToggled: root.setOption("trackpad_flip_y", !(root.status && root.status.trackpad && root.status.trackpad.flipY) ? "true" : "false")
                            }
                          }
                        }
                      }
                    }

                    // =========================================================
                    // TAB 3: SOUND
                    // =========================================================
                    Column {
                      id: soundTabContent
                      visible: root.currentTabId === "sound"
                      width: parent.width
                      spacing: Style.space(12)

                      BorderSurface {
                        width: parent.width
                        height: sndHeaderCol.implicitHeight + Style.space(28)
                        color: Util.alpha(Color.accent, 0.08)
                        borderSpec: Border.flat(Util.alpha(Color.accent, 0.3), 1)
                        radius: Style.cornerRadius

                        Column {
                          id: sndHeaderCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(16)
                          spacing: Style.space(6)

                          Row {
                            spacing: Style.space(10)

                            Text {
                              text: "󰕾"
                              color: Color.accent
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.title
                            }

                            Text {
                              anchors.verticalCenter: parent.verticalCenter
                              text: "Apple T2 Sound & Audio"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                          }

                          Text {
                            width: parent.width
                            text: "Manage internal speakers, microphone inputs, and audio controller power saving states for Apple T2 hardware."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                          }
                        }
                      }

                      // Audio Controller Power Save toggle in Sound tab
                      BorderSurface {
                        width: parent.width
                        height: Style.space(62)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(14)
                          anchors.rightMargin: Style.space(14)
                          anchors.verticalCenter: parent.verticalCenter

                          Column {
                            width: parent.width - soundAudioSwitch.width - Style.space(14)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                              text: "Audio Controller Power Save"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Powers down the Apple Audio controller when no media is playing to conserve battery."
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }

                          ToggleSwitch {
                            id: soundAudioSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: Boolean(root.status && root.status.audioPowerSave)
                            accent: root.accent
                            foreground: checked ? root.accent : root.foreground
                            onToggled: root.setOption("audio_powersave", !(root.status && root.status.audioPowerSave) ? "true" : "false")
                          }
                        }
                      }
                    }

                    // =========================================================
                    // TAB 4: PLUGINS
                    // =========================================================
                    Column {
                      id: pluginsTabContent
                      visible: root.currentTabId === "plugins"
                      width: parent.width
                      spacing: Style.space(12)

                      // Toolbar: Search box, T2 filter, Installed filter, plugin count, and refresh
                      Item {
                        width: parent.width
                        height: Style.space(32)

                        Row {
                          anchors.left: parent.left
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(8)

                          TextField {
                            id: pluginSearchField
                            width: Style.space(220)
                            height: Style.space(32)
                            verticalPadding: Style.space(4)
                            font.pixelSize: Style.font.caption
                            font.family: root.fontFamily
                            placeholderText: "Search Apple plugins..."
                            text: root.pluginFilterQuery
                            onTextEdited: root.pluginFilterQuery = text
                            Keys.onPressed: function(event) {
                              if (event.key === Qt.Key_Escape) {
                                text = ""
                                root.pluginFilterQuery = ""
                                event.accepted = true
                              }
                            }
                          }

                          Button {
                            id: t2FilterBtn
                            visible: Boolean(root.status && root.status.isT2)
                            height: Style.space(32)
                            fontSize: Style.font.caption
                            iconSize: Style.font.bodySmall
                            iconText: ""
                            text: "T2 plugins only"
                            bordered: true
                            selected: root.filterT2Only
                            tooltipText: root.filterT2Only ? "Show all Apple plugins" : "Show only plugins tailored specifically for Apple T2 MacBooks"
                            onClicked: root.filterT2Only = !root.filterT2Only
                          }

                          Button {
                            id: installedFilterBtn
                            height: Style.space(32)
                            fontSize: Style.font.caption
                            iconSize: Style.font.bodySmall
                            iconText: "󰄲"
                            text: "Installed"
                            bordered: true
                            selected: root.pluginFilterMode === 1
                            tooltipText: root.pluginFilterMode === 1 ? "Show all plugins" : "Show only installed plugins"
                            onClicked: root.pluginFilterMode = (root.pluginFilterMode === 1 ? 0 : 1)
                          }
                        }

                        Row {
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(10)

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.filteredPlugins.length + " plugins"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }

                          Button {
                            id: refreshPluginsBtn
                            height: Style.space(32)
                            iconText: "󰑐"
                            tooltipText: "Refresh plugins catalog"
                            bordered: true
                            iconSpinning: root.pluginsLoading
                            enabled: !root.pluginsLoading
                            onClicked: root.fetchPlugins(true)
                          }
                        }
                      }

                      // Operation in progress / feedback banner
                      BorderSurface {
                        visible: root.pluginActionStatus !== ""
                        width: parent.width
                        height: Style.space(40)
                        radius: Style.cornerRadius
                        color: Util.alpha(Color.accent, 0.12)
                        borderSpec: Border.flat(Color.accent, 1)

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(12)
                          anchors.rightMargin: Style.space(12)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(8)

                          Text {
                            text: root.activePluginOpId !== "" ? "󰑐" : "󰄲"
                            color: Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                          }

                          Text {
                            width: parent.width - Style.space(60)
                            text: root.pluginActionStatus
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            elide: Text.ElideRight
                          }

                          MouseArea {
                            width: Style.space(20)
                            height: Style.space(20)
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.activePluginOpId === ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pluginActionStatus = ""

                            Text {
                              anchors.centerIn: parent
                              text: "󰅖"
                              color: root.dim
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                            }
                          }
                        }
                      }

                      // Loading State
                      BorderSurface {
                        visible: root.pluginsLoading && root.pluginList.length === 0
                        width: parent.width
                        height: Style.space(100)
                        radius: Style.cornerRadius
                        color: Util.alpha(root.foreground, 0.03)

                        Column {
                          anchors.centerIn: parent
                          spacing: Style.space(8)

                          Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰑐"
                            color: Color.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.title
                          }

                          Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Fetching plugin catalog from plugins.omarchy.org..."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }
                      }

                      // Empty State
                      BorderSurface {
                        visible: !root.pluginsLoading && root.filteredPlugins.length === 0
                        width: parent.width
                        height: Style.space(100)
                        radius: Style.cornerRadius
                        color: Util.alpha(root.foreground, 0.03)

                        Column {
                          anchors.centerIn: parent
                          spacing: Style.space(8)

                          Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰍉"
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.title
                          }

                          Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No plugins found matching your filter."
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                          }
                        }
                      }

                      // Plugin Cards Repeater
                      Repeater {
                        model: root.filteredPlugins

                        delegate: BorderSurface {
                          id: pluginCard
                          width: parent.width
                          implicitHeight: pluginCardCol.implicitHeight + Style.space(28)
                          height: implicitHeight
                          color: Util.alpha(root.foreground, 0.03)
                          borderSpec: modelData.updateAvailable
                            ? Border.flat(Color.accent, 1)
                            : (modelData.installed ? Border.flat(Util.alpha(root.foreground, 0.16), 1) : Border.none())
                          radius: Style.cornerRadius

                          readonly property bool isBusy: root.activePluginOpId === modelData.id

                          Column {
                            id: pluginCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Style.space(14)
                            spacing: Style.space(10)

                            // 1. Header Line: Icon, Title, Author, Version, Status Badges
                            Row {
                              width: parent.width
                              spacing: Style.space(10)

                              Rectangle {
                                width: Style.space(34)
                                height: Style.space(34)
                                radius: Style.cornerRadius
                                color: modelData.updateAvailable
                                  ? Util.alpha(Color.accent, 0.2)
                                  : (modelData.installed ? Util.alpha(root.foreground, 0.08) : Util.alpha(root.foreground, 0.04))
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                  anchors.centerIn: parent
                                  text: modelData.name && modelData.name.length > 0 ? modelData.name.substring(0, 1).toUpperCase() : "󰏖"
                                  textFormat: Text.PlainText
                                  color: modelData.updateAvailable ? Color.accent : (modelData.installed ? root.foreground : root.dim)
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                              }

                              Column {
                                width: parent.width - Style.space(34) - Style.space(10) - badgesRow.width - Style.space(10)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Row {
                                  spacing: Style.space(6)

                                  Text {
                                    text: modelData.name
                                    textFormat: Text.PlainText
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: true
                                    elide: Text.ElideRight
                                  }

                                  Text {
                                    text: "v" + modelData.version
                                    textFormat: Text.PlainText
                                    color: Color.accent
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                  }

                                  Text {
                                    visible: Boolean(modelData.rankLabel)
                                    text: modelData.rankLabel
                                    textFormat: Text.PlainText
                                    color: Color.accent
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                  }

                                  Text {
                                    visible: Boolean(modelData.stars && modelData.stars > 0)
                                    text: "★ " + modelData.stars
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                  }

                                  Text {
                                    visible: Boolean(modelData.hearts && modelData.hearts > 0)
                                    text: "♥ " + modelData.hearts
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                  }
                                }

                                Text {
                                  text: "by " + modelData.author + " · " + modelData.id
                                  textFormat: Text.PlainText
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                  elide: Text.ElideRight
                                }
                              }

                              // Status Badges
                              Row {
                                id: badgesRow
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.space(6)

                                // T2 Specific Badge
                                Rectangle {
                                  visible: Boolean(modelData.isT2 || modelData.isExactT2)
                                  height: Style.space(22)
                                  width: t2BadgeRow.implicitWidth + Style.space(12)
                                  radius: Style.cornerRadius
                                  color: Util.alpha(Color.accent, 0.14)
                                  border.color: Util.alpha(Color.accent, 0.5)
                                  border.width: 1

                                  Row {
                                    id: t2BadgeRow
                                    anchors.centerIn: parent
                                    spacing: Style.space(4)
                                    Text {
                                      text: ""
                                      color: Color.accent
                                      font.family: root.fontFamily
                                      font.pixelSize: Style.font.caption
                                    }
                                    Text {
                                      text: "T2"
                                      color: Color.accent
                                      font.family: root.fontFamily
                                      font.pixelSize: Style.font.caption
                                      font.bold: true
                                    }
                                  }
                                }

                                // Update Available Badge
                                Rectangle {
                                  visible: modelData.updateAvailable
                                  height: Style.space(22)
                                  width: updateBadgeText.implicitWidth + Style.space(12)
                                  radius: Style.cornerRadius
                                  color: Util.alpha(Color.accent, 0.2)
                                  border.color: Color.accent
                                  border.width: 1

                                  Text {
                                    id: updateBadgeText
                                    anchors.centerIn: parent
                                    text: "󰚰 Update Available"
                                    color: Color.accent
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                  }
                                }


                                // Available (not installed) Badge
                                Rectangle {
                                  visible: !modelData.installed
                                  height: Style.space(22)
                                  width: availBadgeText.implicitWidth + Style.space(12)
                                  radius: Style.cornerRadius
                                  color: Util.alpha(root.foreground, 0.04)

                                  Text {
                                    id: availBadgeText
                                    anchors.centerIn: parent
                                    text: "Available"
                                    color: root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                  }
                                }

                                // Toggle Switch to enable/disable plugin (for installed plugins)
                                ToggleSwitch {
                                  id: cardToggleSwitch
                                  visible: Boolean(modelData && modelData.installed)
                                  anchors.verticalCenter: parent.verticalCenter
                                  checked: Boolean(modelData && modelData.installed && modelData.enabled)
                                  accent: root.accent
                                  foreground: checked ? root.accent : root.foreground
                                  busy: pluginCard.isBusy
                                  enabled: !pluginCard.isBusy && root.activePluginOpId === ""
                                  onToggled: root.togglePlugin(modelData.id, !modelData.enabled)

                                  PanelToolTip {
                                    visible: cardToggleSwitch.containsMouse
                                    text: (modelData && modelData.enabled) ? "Enabled" : "Disabled"
                                  }
                                }
                              }
                            }

                            // 2. Description
                            Text {
                              width: parent.width
                              text: modelData.description
                              textFormat: Text.PlainText
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              wrapMode: Text.WordWrap
                              lineHeight: 1.25
                            }

                            // 3. Actions Row
                            Row {
                              width: parent.width
                              spacing: Style.space(8)

                              // Install button (if not installed)
                              Button {
                                visible: !modelData.installed
                                tooltipText: pluginCard.isBusy ? "Installing..." : "Install"
                                iconText: pluginCard.isBusy ? "󰑐" : "󰏔"
                                iconSpinning: pluginCard.isBusy
                                bordered: true
                                accent: root.accent
                                enabled: !pluginCard.isBusy && root.activePluginOpId === ""
                                onClicked: root.installPlugin(modelData.repo || modelData.installCommand, modelData.id)
                              }

                              // Update button (if update available)
                              Button {
                                visible: modelData.installed && modelData.updateAvailable
                                tooltipText: pluginCard.isBusy ? "Updating..." : ("Update to v" + modelData.version)
                                iconText: pluginCard.isBusy ? "󰑐" : "󰚰"
                                iconSpinning: pluginCard.isBusy
                                bordered: true
                                accent: root.accent
                                enabled: !pluginCard.isBusy && root.activePluginOpId === ""
                                onClicked: root.updatePlugin(modelData.id)
                              }

                              // Remove button (if installed)
                              Button {
                                visible: modelData.installed
                                tooltipText: pluginCard.isBusy ? "Removing..." : "Remove"
                                iconText: pluginCard.isBusy ? "󰑐" : "󰆴"
                                iconSpinning: pluginCard.isBusy
                                bordered: true
                                enabled: !pluginCard.isBusy && root.activePluginOpId === ""
                                onClicked: root.removePlugin(modelData.id)
                              }

                              Item {
                                width: 1
                                height: 1
                              }

                              // External link to Omarchy Plugins website page
                              Button {
                                tooltipText: "Plugins page ↗"
                                iconText: "󰖟"
                                bordered: true
                                onClicked: {
                                  var pageUrl = modelData.webUrl || ("https://plugins.omarchy.org/plugin.html?id=" + encodeURIComponent(modelData.id))
                                  Qt.openUrlExternally(pageUrl)
                                }
                              }

                              // External link to repository
                              Button {
                                visible: modelData.repo && modelData.repo.length > 0
                                tooltipText: "GitHub ↗"
                                iconText: "󰌹"
                                bordered: true
                                onClicked: Qt.openUrlExternally(modelData.repo)
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // Blocking overlay when limine-update is in progress
          Rectangle {
            id: limineBlockingOverlay
            visible: root.limineUpdating || limineProc.running
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.85)
            z: 9999

            // Block all mouse interaction with the panel
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              preventStealing: true
              onClicked: {}
            }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(16)
              width: Math.min(parent.width - Style.space(64), Style.space(520))

              Text {
                id: spinnerIcon
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰑮"
                font.family: root.fontFamily
                font.pixelSize: Style.font.title * 2.2
                color: root.accent

                RotationAnimation on rotation {
                  from: 0
                  to: 360
                  duration: 1200
                  loops: Animation.Infinite
                  running: root.limineUpdating || limineProc.running
                }
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Applying System Changes"
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                color: root.foreground
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Updating system startup and power settings.\n\nThis process takes a moment to safely apply the changes. Please be patient while it finishes."
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: root.dim
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.2
              }
            }
          }

          // T2 fixes confirmation dialog
          Rectangle {
            id: t2FixesDialogOverlay
            visible: root.t2FixesConfirmOpen && !root.limineUpdating && !limineProc.running
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.75)
            z: 9997

            // Absorb background clicks
            MouseArea {
              anchors.fill: parent
              onClicked: {}
            }

            BorderSurface {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.space(32), Style.space(660))
              height: Math.min(parent.height - Style.space(32), Style.space(480))
              color: Color.popups.background
              borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
              radius: Style.cornerRadius

              Item {
                anchors.fill: parent

                // Header
                Row {
                  id: t2HeaderRow
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: Style.space(20)
                  spacing: Style.space(12)

                  Text {
                    text: ""
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title * 1.5
                    color: root.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Column {
                    spacing: 2
                    Text {
                      text: "Apply T2 fixes only"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      color: root.foreground
                    }
                    Text {
                      text: "Hardware-specific stability and power optimizations for Apple T2 MacBooks"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: root.dim
                    }
                  }
                }

                // Explanation Banner
                BorderSurface {
                  id: t2SummaryBox
                  anchors.top: t2HeaderRow.bottom
                  anchors.topMargin: Style.space(10)
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(20)
                  anchors.rightMargin: Style.space(20)
                  implicitHeight: t2SummaryText.implicitHeight + Style.space(16)
                  height: implicitHeight
                  color: Util.alpha(root.accent, 0.08)
                  borderSpec: Border.flat(Util.alpha(root.accent, 0.28), 1)
                  radius: Style.cornerRadius

                  Text {
                    id: t2SummaryText
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    text: "Without these fixes, Omarchy will not behave properly on Apple devices containing the T2 chip because of missing specific configurations needed for T2 hardware.\n\nApplying the T2 fixes sets inactive Ethernet interfaces to unmanaged to prevent post-suspend DHCP freezes, and enables PCIe ports compatibility (pcie_ports=compat) to allow deep bus power saving and prevent power glitches."
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: root.foreground
                    wrapMode: Text.WordWrap
                    lineHeight: 1.2
                  }
                }

                // Footer Buttons
                Row {
                  id: t2FooterRow
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.margins: Style.space(20)
                  spacing: Style.space(10)
                  z: 2

                  Button {
                    text: "Cancel"
                    bordered: true
                    onClicked: {
                      root.t2FixesConfirmOpen = false
                    }
                  }

                  Button {
                    text: "Apply T2 fixes only"
                    iconText: ""
                    bordered: true
                    accent: root.accent
                    selected: true
                    onClicked: {
                      root.applyT2Fixes()
                    }
                  }
                }

                // Scrollable list of options
                Flickable {
                  id: t2OptFlickable
                  anchors.top: t2SummaryBox.bottom
                  anchors.topMargin: Style.space(12)
                  anchors.bottom: t2FooterRow.top
                  anchors.bottomMargin: Style.space(12)
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(20)
                  anchors.rightMargin: Style.space(20)
                  contentWidth: width
                  contentHeight: t2OptContentCol.implicitHeight
                  boundsBehavior: Flickable.StopAtBounds
                  flickableDirection: Flickable.VerticalFlick
                  interactive: contentHeight > height
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                  clip: true

                  Column {
                    id: t2OptContentCol
                    width: parent.width
                    spacing: Style.space(14)

                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "T2 HARDWARE FIXES"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: root.accent
                        font.letterSpacing: 0.8
                      }

                      Repeater {
                        model: [
                          {
                            title: "Ethernet Management",
                            val: Model.areAllEthernetUnmanaged(root.status) ? "Unmanaged (Already applied)" : "Unmanaged (All devices)",
                            desc: "Sets all inactive T2 network interfaces (such as Apple iBridge CDC-NCM) to unmanaged to prevent NetworkManager DHCP query stalls after sleep/wake.",
                            applied: Model.areAllEthernetUnmanaged(root.status)
                          },
                          {
                            title: "PCIe ports compatibility",
                            val: Boolean(root.status && root.status.pciePortsCompat) ? "Enabled (Already applied)" : "Enabled",
                            desc: "Enables low-power states on internal PCIe buses (pcie_ports=compat in bootloader) to eliminate battery drain and prevent power glitches on T2 MacBooks.",
                            applied: Boolean(root.status && root.status.pciePortsCompat)
                          }
                        ]

                        delegate: BorderSurface {
                          width: parent.width
                          implicitHeight: t2OptRow.implicitHeight + Style.space(12)
                          height: implicitHeight
                          color: Util.alpha(root.foreground, 0.03)
                          radius: Style.cornerRadius

                          Row {
                            id: t2OptRow
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(8)

                            Text {
                              text: modelData.applied ? "" : "•"
                              color: root.accent
                              font.bold: true
                              font.family: root.fontFamily
                            }
                            Column {
                              width: parent.width - Style.space(20)
                              spacing: 2
                              Row {
                                spacing: Style.space(8)
                                Text {
                                  text: modelData.title + ":"
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.foreground
                                }
                                Text {
                                  text: modelData.val
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.accent
                                }
                              }
                              Text {
                                text: modelData.desc
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                color: root.dim
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // Recommended options confirmation dialog
          Rectangle {
            id: recommendedDialogOverlay
            visible: root.recommendedConfirmOpen && !root.limineUpdating && !limineProc.running
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.75)
            z: 9997

            // Absorb background clicks
            MouseArea {
              anchors.fill: parent
              onClicked: {}
            }

            BorderSurface {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.space(32), Style.space(660))
              height: Math.min(parent.height - Style.space(32), Style.space(620))
              color: Color.popups.background
              borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
              radius: Style.cornerRadius

              Item {
                anchors.fill: parent

                // Header
                Row {
                  id: recHeaderRow
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: Style.space(20)
                  spacing: Style.space(12)

                  Text {
                    text: "󰁨"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title * 1.5
                    color: root.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Column {
                    spacing: 2
                    Text {
                      text: "Apply recommended options"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      color: root.foreground
                    }
                    Text {
                      text: "Optimized suspend, battery life, trackpad, and Mac keybindings configuration"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: root.dim
                    }
                  }
                }

                // Explanation Banner
                BorderSurface {
                  id: recSummaryBox
                  anchors.top: recHeaderRow.bottom
                  anchors.topMargin: Style.space(10)
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(20)
                  anchors.rightMargin: Style.space(20)
                  implicitHeight: summaryText.implicitHeight + Style.space(16)
                  height: implicitHeight
                  color: Util.alpha(root.accent, 0.08)
                  borderSpec: Border.flat(Util.alpha(root.accent, 0.28), 1)
                  radius: Style.cornerRadius

                  Text {
                    id: summaryText
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    text: "Applying the recommended options means that the MacBook will wake from suspend easier, enjoy up to 40% less battery drain depending on system load, optimize trackpad gestures (natural scrolling, 3-finger workspace swiping, adaptive acceleration, Mac tap mapping), and configure standard Mac keyboard shortcuts (Cmd+A, Cmd+Backspace, Cmd+F, Cmd+Ctrl+F, Cmd+Z, Cmd+Shift+Z, Cmd+S, Cmd+X) with automatic conflict resolution."
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: root.foreground
                    wrapMode: Text.WordWrap
                    lineHeight: 1.2
                  }
                }

                // Footer Buttons
                Row {
                  id: recFooterRow
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.margins: Style.space(20)
                  spacing: Style.space(10)
                  z: 2

                  Button {
                    text: "Cancel"
                    bordered: true
                    onClicked: {
                      root.recommendedConfirmOpen = false
                      root.dismissRecommendedPrompt()
                    }
                  }

                  Button {
                    text: "Apply recommended options"
                    iconText: "󰁨"
                    bordered: true
                    accent: root.accent
                    selected: true
                    onClicked: {
                      root.applyRecommendedOptions()
                    }
                  }
                }

                // Scrollable list of options
                Flickable {
                  id: optFlickable
                  anchors.top: recSummaryBox.bottom
                  anchors.topMargin: Style.space(12)
                  anchors.bottom: recFooterRow.top
                  anchors.bottomMargin: Style.space(12)
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(20)
                  anchors.rightMargin: Style.space(20)
                  contentWidth: width
                  contentHeight: optContentCol.implicitHeight
                  boundsBehavior: Flickable.StopAtBounds
                  flickableDirection: Flickable.VerticalFlick
                  interactive: contentHeight > height
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                  clip: true

                  Column {
                    id: optContentCol
                    width: parent.width
                    spacing: Style.space(14)

                    // Group 1: Suspend Behaviour
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "SUSPEND BEHAVIOUR"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: root.accent
                        font.letterSpacing: 0.8
                      }

                      Repeater {
                        model: [
                          {
                            title: "Sleep mode",
                            val: "Deep Sleep",
                            desc: "Enters traditional ACPI S3 deep sleep state to minimize battery drain when suspended.",
                            applied: Boolean(root.status && (root.status.memSleepModes ? (root.status.memSleepModes.indexOf("deep") === -1 || root.status.memSleep === "deep") : root.status.memSleep === "deep"))
                          },
                          {
                            title: "Lid Close Action",
                            val: "Suspend",
                            desc: "Suspends the MacBook to preserve power when closing the display lid on battery.",
                            applied: Boolean(root.status && (root.status.lidAction === "suspend" || root.status.lidAction === "suspend-then-hibernate"))
                          },
                          {
                            title: "Clam Shell Mode",
                            val: "Stay Awake",
                            desc: "Keeps the system awake when connected to an external monitor and charger with lid closed.",
                            applied: Boolean(root.status && root.status.clamshellMode === true)
                          },
                          {
                            title: "Wake On Lid Open",
                            val: "Enabled",
                            desc: "Automatically and instantly wakes the system when opening the laptop lid.",
                            applied: Boolean(root.status && root.status.wakeOnLid === true)
                          },
                          {
                            title: "Wake on AC Charger Connect",
                            val: "Disabled",
                            desc: "Prevents unwanted wakeups when plugging in the USB-C or MagSafe charger.",
                            applied: Boolean(root.status && root.status.wakeOnAc === false)
                          },
                          {
                            title: "Hibernate Delay",
                            val: "Never",
                            desc: "Prevents unexpected transitions to disk hibernation to maintain quick sleep responsiveness.",
                            applied: Boolean(root.status && (root.status.hibernateDelay === "off" || root.status.hibernateDelay === "0" || root.status.hibernateDelay === "never"))
                          },
                          {
                            title: "Touch Bar Blanking on Sleep",
                            val: "Enabled",
                            desc: "Ensures the OLED Touch Bar is powered off cleanly immediately upon suspend.",
                            applied: Boolean(root.status && root.status.touchbarBlank === true)
                          }
                        ]

                        delegate: BorderSurface {
                          width: parent.width
                          implicitHeight: optRow1.implicitHeight + Style.space(12)
                          height: implicitHeight
                          color: Util.alpha(root.foreground, 0.03)
                          radius: Style.cornerRadius

                          Row {
                            id: optRow1
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(8)

                            Text {
                              text: modelData.applied ? "" : "•"
                              color: root.accent
                              font.bold: true
                              font.family: root.fontFamily
                            }
                            Column {
                              width: parent.width - Style.space(20)
                              spacing: 2
                              Row {
                                spacing: Style.space(8)
                                Text {
                                  text: modelData.title + ":"
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.foreground
                                }
                                Text {
                                  text: modelData.val + (modelData.applied ? " (Already applied)" : "")
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.accent
                                }
                              }
                              Text {
                                text: modelData.desc
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                color: root.dim
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }
                          }
                        }
                      }
                    }

                    // Group 2: Battery Life
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "BATTERY LIFE"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: root.accent
                        font.letterSpacing: 0.8
                      }

                      Repeater {
                        model: {
                          var items = [
                            {
                              title: "Wi-Fi Power Management",
                              val: "Disabled",
                              desc: "Prevents wireless sleep states that can cause Wi-Fi drops or stall system wakeups.",
                              applied: Boolean(root.status && root.status.wifiPowerSave === false)
                            },
                            {
                              title: "Ethernet Management",
                              val: "Unmanaged (All devices)",
                              desc: "Stops NetworkManager from querying inactive internal T2 network interfaces.",
                              applied: Model.areAllEthernetUnmanaged(root.status)
                            },
                            {
                              title: "Audio Controller Power Save",
                              val: "Enabled",
                              desc: "Powers down the internal audio hardware when inactive to reduce idle battery drain.",
                              applied: Boolean(root.status && root.status.audioPowerSave === true)
                            },
                            {
                              title: "USB Device Autosuspend",
                              val: "Enabled",
                              desc: "Puts unused internal USB controllers into low-power mode to preserve battery.",
                              applied: Boolean(root.status && root.status.usbAutosuspend === true)
                            },
                            {
                              title: "Keyboard Backlight Idle Auto-Dim",
                              val: "1 min",
                              desc: "Dims the keyboard illumination after 1 minute of inactivity to save energy.",
                              applied: Boolean(root.status && root.status.kbdTimeout === "1m")
                            }
                          ]
                          if (root.status && root.status.isT2) {
                            items.push({
                              title: "PCIe ports compatibility",
                              val: "Enabled",
                              desc: "Enables low-power PCIe bus states to eliminate battery drain (updates bootloader).",
                              applied: Boolean(root.status && root.status.pciePortsCompat === true)
                            })
                          }
                          return items
                        }

                        delegate: BorderSurface {
                          width: parent.width
                          implicitHeight: optRow2.implicitHeight + Style.space(12)
                          height: implicitHeight
                          color: Util.alpha(root.foreground, 0.03)
                          radius: Style.cornerRadius

                          Row {
                            id: optRow2
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(8)

                            Text {
                              text: modelData.applied ? "" : "•"
                              color: root.accent
                              font.bold: true
                              font.family: root.fontFamily
                            }
                            Column {
                              width: parent.width - Style.space(20)
                              spacing: 2
                              Row {
                                spacing: Style.space(8)
                                Text {
                                  text: modelData.title + ":"
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.foreground
                                }
                                Text {
                                  text: modelData.val + (modelData.applied ? " (Already applied)" : "")
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.accent
                                }
                              }
                              Text {
                                text: modelData.desc
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                color: root.dim
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }
                          }
                        }
                      }
                    }

                    // Group 3: Mac Keybindings
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "KEYBINDINGS"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: root.accent
                        font.letterSpacing: 0.8
                      }

                      Repeater {
                        model: [
                          {
                            title: "Select All",
                            val: "CMD + A",
                            desc: "Selects all content or text using standard macOS Cmd + A chord.",
                            applied: Boolean(root.status && Model.normalizeChord(root.status.keybindingSelectAll) === Model.normalizeChord("SUPER + A"))
                          },
                          {
                            title: "Delete Forward",
                            val: "CMD + BACKSPACE",
                            desc: "Maps Command + Backspace to forward delete, relocating any conflicting system shortcut.",
                            applied: Boolean(root.status && Model.normalizeChord(root.status.keybindingDelete) === Model.normalizeChord("SUPER + BACKSPACE"))
                          },
                          {
                            title: "Find in Document",
                            val: "CMD + F",
                            desc: "Standard Mac shortcut for searching text in editors and browsers.",
                            applied: Boolean(root.status && Model.normalizeChord(root.status.keybindingFind) === Model.normalizeChord("SUPER + F"))
                          },
                          {
                            title: "Toggle Fullscreen",
                            val: "CMD + CTRL + F",
                            desc: "Standard macOS fullscreen shortcut (Command + Control + F).",
                            applied: Boolean(root.status && Model.normalizeChord(root.status.keybindingFullscreen) === Model.normalizeChord("SUPER + CTRL + F"))
                          },
                          {
                            title: "Undo",
                            val: "CMD + Z",
                            desc: "Standard Mac shortcut for undoing actions in applications.",
                            applied: Boolean(root.status && Model.normalizeChord(root.status.keybindingUndo) === Model.normalizeChord("SUPER + Z"))
                          },
                          {
                            title: "Redo",
                            val: "CMD + SHIFT + Z",
                            desc: "Standard Mac shortcut for redoing actions in applications.",
                            applied: Boolean(root.status && Model.normalizeChord(root.status.keybindingRedo) === Model.normalizeChord("SUPER + SHIFT + Z"))
                          },
                          {
                            title: "Save",
                            val: "CMD + S",
                            desc: "Standard Mac shortcut for saving documents and files.",
                            applied: Boolean(root.status && Model.normalizeChord(root.status.keybindingSave) === Model.normalizeChord("SUPER + S"))
                          },
                          {
                            title: "Cut",
                            val: "CMD + X",
                            desc: "Standard Mac shortcut for cutting selected text or items to the clipboard.",
                            applied: Boolean(root.status && Model.normalizeChord(root.status.keybindingCut) === Model.normalizeChord("SUPER + X"))
                          },
                          {
                            title: "System Conflict Resolution",
                            val: "Auto-migrated",
                            desc: "Safely relocates any overlapping system shortcuts (such as Super + Backspace) to prevent conflicts.",
                            applied: Boolean(root.status && Model.areAllMacShortcutsApplied(root.status))
                          }
                        ]

                        delegate: BorderSurface {
                          width: parent.width
                          implicitHeight: optRow3.implicitHeight + Style.space(12)
                          height: implicitHeight
                          color: Util.alpha(root.foreground, 0.03)
                          radius: Style.cornerRadius

                          Row {
                            id: optRow3
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(8)

                            Text {
                              text: modelData.applied ? "" : "•"
                              color: root.accent
                              font.bold: true
                              font.family: root.fontFamily
                            }
                            Column {
                              width: parent.width - Style.space(20)
                              spacing: 2
                              Row {
                                spacing: Style.space(8)
                                Text {
                                  text: modelData.title + ":"
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.foreground
                                }
                                Text {
                                  text: modelData.val + (modelData.applied ? " (Already applied)" : "")
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.accent
                                }
                              }
                              Text {
                                text: modelData.desc
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                color: root.dim
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }
                          }
                        }
                      }
                    }

                    // Group 4: Trackpad
                    Column {
                      width: parent.width
                      spacing: Style.space(6)

                      Text {
                        text: "TRACKPAD"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: root.accent
                        font.letterSpacing: 0.8
                      }

                      Repeater {
                        model: [
                          {
                            title: "Natural Scrolling",
                            val: "Enabled",
                            desc: "Invert scroll direction so page content tracks finger movement, matching native macOS behavior.",
                            applied: Boolean(root.status && root.status.trackpad && root.status.trackpad.naturalScroll)
                          },
                          {
                            title: "3-Finger Workspace Swiping",
                            val: "Enabled",
                            desc: "Swipe horizontally across the trackpad with three fingers to switch workspaces seamlessly.",
                            applied: Boolean(root.status && root.status.trackpad && root.status.trackpad.swipeWorkspaces)
                          },
                          {
                            title: "Tap to Click",
                            val: "Enabled",
                            desc: "Tap surface with 1 finger for primary click and 2 fingers for secondary click without physical depression.",
                            applied: Boolean(root.status && root.status.trackpad && root.status.trackpad.tapToClick)
                          },
                          {
                            title: "Secondary Click (Clickfinger)",
                            val: "Two-Finger Click",
                            desc: "Clicking anywhere with two fingers emits a secondary (right) click.",
                            applied: Boolean(root.status && root.status.trackpad && root.status.trackpad.clickfingerBehavior)
                          },
                          {
                            title: "Two-Finger Scroll Speed",
                            val: "0.64x multiplier",
                            desc: "Smooth two-finger scrolling multiplier calibrated for Apple Force Touch trackpads.",
                            applied: Boolean(root.status && root.status.trackpad && Math.abs(Number(root.status.trackpad.scrollFactor) - 0.64) < 0.01)
                          },
                          {
                            title: "Acceleration Profile",
                            val: "Adaptive",
                            desc: "Dynamic macOS-style cursor acceleration curve based on finger velocity.",
                            applied: Boolean(root.status && root.status.trackpad && root.status.trackpad.accelProfile === "adaptive")
                          },
                          {
                            title: "Pointer Speed (Sensitivity)",
                            val: "Default (50%)",
                            desc: "Balanced cursor tracking speed calibrated for Retina displays.",
                            applied: Boolean(root.status && root.status.trackpad && Math.abs(Number(root.status.trackpad.sensitivity) - 0.0) < 0.01)
                          },
                          {
                            title: "Disable While Typing",
                            val: "Enabled",
                            desc: "Prevents accidental cursor drift or accidental clicks while typing on the keyboard.",
                            applied: Boolean(root.status && root.status.trackpad && root.status.trackpad.disableWhileTyping)
                          },
                          {
                            title: "Tap Button Order",
                            val: "LRM (Mac Default)",
                            desc: "Maps multi-finger tap clicks in Apple order (1-finger Left, 2-finger Right, 3-finger Middle).",
                            applied: Boolean(root.status && root.status.trackpad && root.status.trackpad.tapButtonMap === "lrm")
                          },
                          {
                            title: "Tap and Drag",
                            val: "Enabled",
                            desc: "Double-tap and slide with one finger to drag windows or select text.",
                            applied: Boolean(root.status && root.status.trackpad && root.status.trackpad.tapAndDrag)
                          },
                          {
                            title: "Three-Finger Drag",
                            val: "Disabled",
                            desc: "Disabled to allow native 3-finger horizontal workspace swiping without gesture collisions.",
                            applied: Boolean(root.status && root.status.trackpad && root.status.trackpad.drag3fg === 0)
                          }
                        ]

                        delegate: BorderSurface {
                          width: parent.width
                          implicitHeight: optRow4.implicitHeight + Style.space(12)
                          height: implicitHeight
                          color: Util.alpha(root.foreground, 0.03)
                          radius: Style.cornerRadius

                          Row {
                            id: optRow4
                            anchors.fill: parent
                            anchors.margins: Style.space(8)
                            spacing: Style.space(8)

                            Text {
                              text: modelData.applied ? "" : "•"
                              color: root.accent
                              font.bold: true
                              font.family: root.fontFamily
                            }
                            Column {
                              width: parent.width - Style.space(20)
                              spacing: 2
                              Row {
                                spacing: Style.space(8)
                                Text {
                                  text: modelData.title + ":"
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.foreground
                                }
                                Text {
                                  text: modelData.val + (modelData.applied ? " (Already applied)" : "")
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.bodySmall
                                  font.bold: true
                                  color: root.accent
                                }
                              }
                              Text {
                                text: modelData.desc
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                color: root.dim
                                wrapMode: Text.WordWrap
                                width: parent.width
                              }
                            }
                        }
                      }
                    }
                }
              }
            }
          }

          // Reboot confirmation dialog after limine-update
          Rectangle {
            id: rebootDialogOverlay
            visible: root.rebootConfirmOpen && !root.limineUpdating && !limineProc.running
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.75)
            z: 9998

            // Absorb background clicks
            MouseArea {
              anchors.fill: parent
              onClicked: {}
            }

            BorderSurface {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.space(48), Style.space(500))
              height: rebootCol.implicitHeight + Style.space(48)
              color: Color.popups.background
              borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
              radius: Style.cornerRadius

              Column {
                id: rebootCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(20)
                spacing: Style.space(16)

                Row {
                  spacing: Style.space(12)
                  Text {
                    text: "󰜉"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title * 1.5
                    color: root.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Column {
                    spacing: 2
                    Text {
                      text: "Restart Required"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      color: root.foreground
                    }
                    Text {
                      text: "System changes saved successfully"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: root.dim
                    }
                  }
                }

                Text {
                  text: "Your hardware and power settings have been updated.\n\nTo apply these changes, your computer needs to be restarted. Would you like to restart now?"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  color: root.foreground
                  wrapMode: Text.WordWrap
                  width: parent.width
                }

                Row {
                  anchors.right: parent.right
                  spacing: Style.space(10)

                  Button {
                    text: "Later"
                    bordered: true
                    onClicked: root.rebootConfirmOpen = false
                  }

                  Button {
                    text: "Restart Now"
                    iconText: "󰜉"
                    bordered: true
                    accent: root.accent
                    selected: true
                    enabled: !root.limineUpdating && !limineProc.running
                    onClicked: {
                      if (root.limineUpdating || limineProc.running) return
                      root.rebootConfirmOpen = false
                      rebootProc.running = true
                    }
                  }
                }
              }
            }
          }

          // Intra-plugin keybinding conflict resolution dialog
          Rectangle {
            id: pluginConflictDialogOverlay
            visible: root.conflictDialogOpen && !root.keyRecorderOpen
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.78)
            z: 9998

            // Absorb background clicks
            MouseArea {
              anchors.fill: parent
              onClicked: {}
            }

            Item {
              id: conflictDialogCatcher
              anchors.fill: parent
              focus: root.conflictDialogOpen && !root.keyRecorderOpen

              Keys.onPressed: function(event) {
                if (!root.conflictDialogOpen) return
                if (event.key === Qt.Key_Escape) {
                  root.cancelConflictDialog()
                  event.accepted = true
                  return
                }
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.resolveConflictWithRecommended()
                  event.accepted = true
                  return
                }
              }
            }

            BorderSurface {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.space(32), Style.space(540))
              height: conflictDialogCol.implicitHeight + Style.space(48)
              color: Color.popups.background
              borderSpec: Border.flat(root.accent, Style.normalBorderWidth)
              radius: Style.cornerRadius

              Column {
                id: conflictDialogCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(24)
                spacing: Style.space(16)

                // Dialog Header
                Row {
                  width: parent.width
                  spacing: Style.space(12)

                  Text {
                    text: "󰀪"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title * 1.5
                    color: root.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    spacing: 2
                    width: parent.width - Style.space(48)

                    Text {
                      text: "Shortcut Conflict Detected"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      color: root.foreground
                    }

                    Text {
                      text: Model.formatChordForDisplay(root.conflictTargetChord) + " is already assigned to " + root.conflictDisplacedTaskName
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: root.dim
                    }
                  }
                }

                // Explanation / Information Box
                BorderSurface {
                  width: parent.width
                  height: conflictInfoCol.implicitHeight + Style.space(24)
                  color: Util.alpha(root.accent, 0.08)
                  borderSpec: Border.flat(Util.alpha(root.accent, 0.3), 1)
                  radius: Style.cornerRadius

                  Column {
                    id: conflictInfoCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(14)
                    spacing: Style.space(8)

                    Text {
                      width: parent.width
                      wrapMode: Text.WordWrap
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      text: "<b>" + root.conflictTargetTaskName + "</b> was set to <b>" + Model.formatChordForDisplay(root.conflictTargetChord) + "</b>.<br><br>" +
                            "This conflicts with " + (root.conflictIsSystem ? "the system shortcut <b>" : "<b>") + root.conflictDisplacedTaskName + "</b>, which is currently assigned to <b>" + Model.formatChordForDisplay(root.conflictDisplacedChord) + "</b>.<br><br>" +
                            "Assign <b>" + root.conflictDisplacedTaskName + "</b> to a different shortcut to resolve this conflict:"
                    }
                  }
                }

                // Action Buttons (NO "Keep Current" button!)
                Row {
                  anchors.right: parent.right
                  spacing: Style.space(10)

                  Button {
                    iconText: "󰌌"
                    text: "Custom Shortcut…"
                    tooltipText: "Record a custom key combination for " + root.conflictDisplacedTaskName
                    bordered: true
                    fontSize: Style.font.caption
                    iconSize: Style.font.bodySmall
                    height: Style.space(32)
                    accent: root.accent
                    onClicked: {
                      root.resolveConflictWithCustom()
                    }
                  }

                  Button {
                    iconText: ""
                    text: "Set " + root.conflictDisplacedTaskName + " to " + Model.formatChordForDisplay(root.conflictRecommendedChord)
                    tooltipText: "Assign " + root.conflictDisplacedTaskName + " to " + Model.formatChordForDisplay(root.conflictRecommendedChord)
                    bordered: true
                    selected: true
                    fontSize: Style.font.caption
                    iconSize: Style.font.bodySmall
                    height: Style.space(32)
                    accent: root.accent
                    onClicked: {
                      root.resolveConflictWithRecommended()
                    }
                  }
                }
              }
            }
          }

          // Key combination recorder and conflict confirmation dialog
          Rectangle {
            id: keyRecorderDialogOverlay
            visible: root.keyRecorderOpen
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.78)
            z: 9999

            // Absorb background clicks
            MouseArea {
              anchors.fill: parent
              onClicked: {}
            }

            // Keyboard event catcher for recording keys
            Item {
              id: keyRecorderCatcher
              anchors.fill: parent
              focus: root.keyRecorderOpen

              Keys.onPressed: function(event) {
                if (!root.keyRecorderOpen) return
                if (root.keyRecorderChecking) {
                  event.accepted = true
                  return
                }

                // If currently showing conflict dialog: Enter overrides, Escape cancels back to recording
                if (root.keyRecorderConflict) {
                  if (event.key === Qt.Key_Escape) {
                    root.keyRecorderConflict = false
                    event.accepted = true
                    return
                  }
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.applyKeyOverride()
                    event.accepted = true
                    return
                  }
                  event.accepted = true
                  return
                }

                // Plain Escape cancels/closes the dialog
                if (event.key === Qt.Key_Escape && (!event.modifiers || event.modifiers === 0)) {
                  root.keyRecorderOpen = false
                  event.accepted = true
                  return
                }

                // Enter confirms if complete
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (!event.modifiers || event.modifiers === 0)) {
                  if (root.keyRecorderComplete) {
                    root.confirmKeyRecording()
                    event.accepted = true
                    return
                  }
                }

                // Convert key event to chord
                var res = Model.keyEventToChord(event)
                if (res) {
                  root.keyRecorderDisplayChord = res.displayChord
                  if (res.complete) {
                    root.keyRecorderRecordedChord = res.chord
                    root.keyRecorderComplete = true
                  } else {
                    root.keyRecorderComplete = false
                  }
                }
                event.accepted = true
              }

              Keys.onReleased: function(event) {
                if (!root.keyRecorderOpen || root.keyRecorderConflict || root.keyRecorderChecking) return
                if (!root.keyRecorderComplete) {
                  if (!event.modifiers || event.modifiers === 0) {
                    root.keyRecorderDisplayChord = ""
                  }
                }
                event.accepted = true
              }
            }

            BorderSurface {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.space(32), Style.space(520))
              height: keyRecorderCol.implicitHeight + Style.space(48)
              color: Color.popups.background
              borderSpec: Border.flat(root.keyRecorderConflict ? (Color.warning || root.accent) : root.accent, Style.normalBorderWidth)
              radius: Style.cornerRadius

              Column {
                id: keyRecorderCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(24)
                spacing: Style.space(16)

                // Dialog Header
                Row {
                  width: parent.width
                  spacing: Style.space(12)

                  Text {
                    text: root.keyRecorderConflict ? "󰀪" : "󰌌"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title * 1.5
                    color: root.keyRecorderConflict ? (Color.warning || root.accent) : root.accent
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Column {
                    spacing: 2
                    width: parent.width - Style.space(48)

                    Text {
                      text: root.keyRecorderConflict ? "Shortcut Already in Use" : ("Record Shortcut: " + root.keyRecorderTaskName)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      color: root.foreground
                    }

                    Text {
                      text: root.keyRecorderConflict ? "Conflict detected with an existing keybinding" : "Press the desired key combination on your keyboard"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      color: root.dim
                    }
                  }
                }

                // If Conflict State:
                Column {
                  visible: root.keyRecorderConflict
                  width: parent.width
                  spacing: Style.space(14)

                  BorderSurface {
                    width: parent.width
                    height: conflictWarningCol.implicitHeight + Style.space(24)
                    color: Util.alpha(Color.warning || root.accent, 0.08)
                    borderSpec: Border.flat(Util.alpha(Color.warning || root.accent, 0.35), 1)
                    radius: Style.cornerRadius

                    Column {
                      id: conflictWarningCol
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(14)
                      spacing: Style.space(8)

                      Row {
                        spacing: Style.space(8)
                        Text {
                          text: "Key Combination:"
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          text: Model.formatChordForDisplay(root.keyRecorderRecordedChord)
                          color: root.accent
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                      }

                      Row {
                        spacing: Style.space(8)
                        Text {
                          text: "Currently Assigned To:"
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                        Text {
                          text: Model.formatChordForDisplay(root.keyRecorderConflictAction)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                      }

                      Text {
                        width: parent.width
                        text: "Assigning this key combination will override the existing shortcut. Do you want to apply this key combination anyway?"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.WordWrap
                      }
                    }
                  }

                  // Action Buttons for Conflict Resolution
                  Row {
                    width: parent.width
                    spacing: Style.space(12)
                    readonly property real btnW: (width - spacing) / 2

                    Button {
                      width: parent.btnW
                      text: "Choose Another"
                      bordered: true
                      onClicked: {
                        root.keyRecorderConflict = false
                        root.keyRecorderRecordedChord = ""
                        root.keyRecorderDisplayChord = ""
                        root.keyRecorderComplete = false
                        keyRecorderCatcher.forceActiveFocus()
                      }
                    }

                    Button {
                      width: parent.btnW
                      text: "Confirm & Override"
                      bordered: true
                      accent: root.accent
                      onClicked: {
                        root.applyKeyOverride()
                      }
                    }
                  }
                }

                // If Normal Recording State:
                Column {
                  visible: !root.keyRecorderConflict
                  width: parent.width
                  spacing: Style.space(16)

                  // Visual Chord Recording Box
                  BorderSurface {
                    width: parent.width
                    height: Style.space(90)
                    color: Util.alpha(root.foreground, 0.04)
                    borderSpec: Border.flat(root.keyRecorderComplete ? root.accent : Util.alpha(root.foreground, 0.15), root.keyRecorderComplete ? 2 : 1)
                    radius: Style.cornerRadius

                    Column {
                      anchors.centerIn: parent
                      spacing: Style.space(6)

                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                          if (root.keyRecorderDisplayChord) return root.keyRecorderDisplayChord
                          return "Press key combination…"
                        }
                        color: root.keyRecorderComplete ? root.accent : (root.keyRecorderDisplayChord ? root.foreground : root.dim)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title * 1.2
                        font.bold: true
                      }

                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                          if (root.keyRecorderChecking) return "Checking availability…"
                          if (root.keyRecorderComplete) return "Ready! Click Confirm or press Enter"
                          if (root.keyRecorderDisplayChord) return "Release modifiers or press final key…"
                          return "e.g. hold Cmd / Ctrl / Alt and press a key"
                        }
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  // Dialog Action Buttons
                  Row {
                    width: parent.width
                    spacing: Style.space(12)
                    readonly property real btnW: (width - spacing * 2) / 3

                    Button {
                      width: parent.btnW
                      text: "Cancel"
                      bordered: true
                      onClicked: {
                        root.keyRecorderOpen = false
                      }
                    }

                    Button {
                      width: parent.btnW
                      text: "Clear"
                      bordered: true
                      enabled: Boolean(root.keyRecorderDisplayChord || root.keyRecorderRecordedChord)
                      onClicked: {
                        root.keyRecorderRecordedChord = ""
                        root.keyRecorderDisplayChord = ""
                        root.keyRecorderComplete = false
                        keyRecorderCatcher.forceActiveFocus()
                      }
                    }

                    Button {
                      width: parent.btnW
                      text: root.keyRecorderChecking ? "Checking…" : "Confirm"
                      bordered: true
                      accent: root.accent
                      enabled: root.keyRecorderComplete && !root.keyRecorderChecking
                      onClicked: {
                        root.confirmKeyRecording()
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
}
}
}
