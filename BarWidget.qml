import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "T2Model.js" as Model

BarWidget {
  id: root
  moduleName: "bramvanoploo.omarchy-t2-linux"

  property bool opened: false
  property var status: Model.emptyStatus()
  property int activeTab: 0 // 0 = "Battery life", 1 = "Suspend behaviour"
  property bool nonT2DialogOpen: false
  property bool applying: false
  property string lastNotice: ""
  property bool limineUpdating: false
  property bool rebootConfirmOpen: false
  property bool recommendedConfirmOpen: false

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string helper: pluginDir + "/scripts/t2-helper"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color hairline: Util.alpha(foreground, 0.12)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var tabs: [
    { id: "battery", title: "Battery life", icon: "󰁹", desc: "Energy & power settings" },
    { id: "suspend", title: "Suspend behaviour", icon: "󰤄", desc: "Sleep states & lid actions" },
    { id: "plugins", title: "Plugins", icon: "󰏓", desc: "T2 community plugins" }
  ]

  property var pluginList: []
  property bool pluginsLoading: false
  property string pluginActionStatus: ""
  property string activePluginOpId: ""
  property string pluginFilterQuery: ""
  property int pluginFilterMode: 0 // 0: T2 Direct Matches (q=T2), 1: Installed, 2: All Hardware

  readonly property var filteredPlugins: root.pluginList || []

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
      if (root.opened && parsed.isT2 && !parsed.recommendedPromptShown && !root.limineUpdating && !root.rebootConfirmOpen) {
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
    if (!root.status.isT2) {
      root.showNonT2Dialog()
    } else {
      root.toggle()
    }
  }

  function toggle() {
    if (!root.status.isT2) {
      root.showNonT2Dialog()
      return
    }
    opened ? close() : open()
  }

  function open() {
    if (!root.status.isT2) {
      root.showNonT2Dialog()
      return
    }
    nonT2DialogOpen = false
    opened = true
    refresh()
    if (activeTab === 2) {
      fetchPlugins(true)
    } else {
      fetchPlugins(false)
    }
  }

  function close() {
    if (root.limineUpdating) return
    opened = false
    nonT2DialogOpen = false
  }

  function showNonT2Dialog() {
    if (root.opened) root.close()
    nonT2DialogOpen = true
  }

  function togglePciePortsCompat(enable) {
    if (root.limineUpdating) return
    root.limineUpdating = true
    if (root.status) {
      var s = Object.assign({}, root.status)
      s.pciePortsCompat = enable
      root.status = s
    }
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
    root.lastNotice = "Updating Limine boot configuration (limine-update)…"
    limineProc.command = ["bash", helper, "set", "mem_sleep", mode]
    limineProc.running = true
  }

  function applyRecommendedOptions() {
    recommendedConfirmOpen = false
    if (root.limineUpdating) return
    root.limineUpdating = true

    if (root.status) {
      var s = Object.assign({}, root.status)
      s.memSleep = "s2idle"
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
      s.pciePortsCompat = true
      s.recommendedPromptShown = true
      if (s.inactiveEthernet) {
        s.inactiveEthernet = s.inactiveEthernet.map(function(item) {
          return { device: item.device, managed: false, state: "unmanaged" }
        })
      }
      root.status = s
    }

    root.lastNotice = "Applying recommended power and suspend settings…"
    limineProc.command = ["bash", helper, "apply-recommended"]
    limineProc.running = true
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
    function selectTab(index: int): void {
      root.activeTab = index
      if (index === 2 && root.opened) {
        root.fetchPlugins(true)
      }
    }
    function setPluginFilter(query: string): void { root.pluginFilterQuery = query }
    function setPluginMode(mode: int): void { root.pluginFilterMode = mode }
    function scroll(y: real): void { flickable.contentY = y }
    function refreshPlugins(): void { root.fetchPlugins(true) }
    function togglePlugin(pluginId: string, enable: bool): void { root.togglePlugin(pluginId, enable) }
    function setOption(key: string, val: string): void { root.setOption(key, val) }
    function setMemSleep(mode: string): void { root.setMemSleep(mode) }
    function refresh(): void { root.refresh() }
    function scrollContent(y: real): void { flickable.contentY = y }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onActiveTabChanged: {
    if (activeTab === 2 && opened) {
      root.fetchPlugins(true)
    }
  }

  onOpenedChanged: {
    if (opened) {
      if (!root.status.isT2) {
        root.close()
        root.showNonT2Dialog()
        return
      }
      refresh()
      if (activeTab === 2) {
        fetchPlugins(true)
      } else {
        fetchPlugins(false)
      }
      if (root.status && root.status.isT2 && !root.status.recommendedPromptShown && !root.limineUpdating && !root.rebootConfirmOpen) {
        root.recommendedConfirmOpen = true
      }
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
    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.lastNotice = "Changes saved."
      } else {
        root.lastNotice = "Operation cancelled or failed."
      }
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
    onExited: function(exitCode) {
      var opId = root.activePluginOpId
      root.activePluginOpId = ""
      if (exitCode === 0) {
        root.pluginActionStatus = "Plugin operation completed successfully."
      } else {
        root.pluginActionStatus = "Plugin operation failed (exit code " + exitCode + ")."
      }
      root.fetchPlugins(true)
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    repeat: false
    onTriggered: root.refresh()
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

  // --- Non-T2 Notification Dialog Window (Overlay, Centered) ---
  PanelWindow {
    id: nonT2ModalWindow
    visible: root.nonT2DialogOpen
    screen: button && button.QsWindow && button.QsWindow.window ? button.QsWindow.window.screen : null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-t2-dialog"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.nonT2DialogOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: {
      if (visible) {
        Qt.callLater(function() {
          if (nonT2ModalWindow.visible) dialogKeyCatcher.forceActiveFocus()
        })
      }
    }

    Item {
      id: dialogKeyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          root.nonT2DialogOpen = false
          event.accepted = true
        }
      }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)

        MouseArea {
          anchors.fill: parent
          onClicked: root.nonT2DialogOpen = false
        }

        BorderSurface {
          id: dialogCard
          width: Math.min(parent.width - Style.space(32), Style.space(520))
          height: dialogCol.implicitHeight + Style.space(48)
          anchors.centerIn: parent
          color: Color.popups.background
          borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)
          radius: Style.cornerRadius

          MouseArea {
            anchors.fill: parent
            onClicked: {}
          }

          Column {
            id: dialogCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(24)
            spacing: Style.space(16)

            // Dialog Header
            Row {
              width: parent.width
              spacing: Style.space(14)

              Rectangle {
                width: Style.space(44)
                height: Style.space(44)
                radius: Style.cornerRadius
                color: Util.alpha(Color.accent, 0.16)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent
                  text: "󰌢"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: "Omarchy T2 Linux"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  text: "Incompatible Hardware Detected"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            PanelSeparator {
              width: parent.width
              foreground: root.foreground
            }

            // Main Notification Message
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "This plugin is intended for use with Macbooks with the T2 chip and that chip has not been found in your computer."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              lineHeight: 1.3
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "The Apple T2 Security Chip (PCI 106b:1801 / 1802) provides hardware security, thermal control, and custom power management specific to 2018–2020 Intel MacBooks. Because your system does not contain this chip, these optimizations cannot be applied."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              lineHeight: 1.25
            }

            // System info readout
            BorderSurface {
              width: parent.width
              height: sysInfoCol.implicitHeight + Style.space(20)
              color: Util.alpha(root.foreground, 0.04)
              radius: Style.cornerRadius

              Column {
                id: sysInfoCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(10)
                spacing: Style.space(4)

                Text {
                  text: "System: " + (root.status.model || "Unknown") + " (" + (root.status.vendor || "Unknown") + ")"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  text: "Status: Apple T2 Bridge Controller not found"
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            // Action Buttons
            Row {
              anchors.right: parent.right
              spacing: Style.space(10)

              Button {
                text: "Dismiss"
                iconText: "󰅖"
                bordered: true
                accent: root.accent
                onClicked: root.nonT2DialogOpen = false
              }
            }
          }
        }
      }
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
        if (root.recommendedConfirmOpen) {
          if (event.key === Qt.Key_Escape) {
            root.recommendedConfirmOpen = false
            root.dismissRecommendedPrompt()
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
            if (!root.limineUpdating && !limineProc.running && !root.rebootConfirmOpen && !root.recommendedConfirmOpen) {
              root.close()
            }
          }
        }

        // Centered Card (Large, 880x620)
        BorderSurface {
          id: mainCard
          anchors.centerIn: parent
          width: Math.min(Style.space(880), parent.width - Style.space(48))
          height: Math.min(Style.space(620), parent.height - Style.space(48))
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
                      text: "Omarchy T2 Linux"
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
                width: Style.space(220)
                height: parent.height

                // Top: Navigation Tabs
                Column {
                  id: navTabsCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  spacing: Style.space(10)

                  Repeater {
                    model: root.tabs

                    delegate: BorderSurface {
                      id: tabButton
                      width: navTabsCol.width
                      height: Style.space(62)
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
                          if (index === 2) {
                            root.fetchPlugins(true)
                          }
                        }
                      }
                    }
                  }
                }

                // Bottom: "Apply recommended defaults" button + T2 Subsystem summary
                Column {
                  id: sidebarFooterCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  spacing: Style.space(10)

                  Button {
                    id: applyRecommendedBtn
                    width: parent.width
                    height: Style.space(36)
                    text: "Apply recommended defaults"
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
                        text: "T2 SUBSYSTEM"
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 0.8
                      }

                      Text {
                        text: "Model: " + (root.status.model || "MacBook")
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }

                      Text {
                        text: "Kernel: T2 Patched"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Text {
                        text: "Chip: Apple T2 (106b:1801)"
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
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
                      height: Style.space(36)

                      Column {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)

                        Text {
                          text: root.tabs[root.activeTab].title.toUpperCase()
                          color: root.accent
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.subtitle
                          font.bold: true
                          font.letterSpacing: 1.0
                        }

                        Text {
                          text: root.activeTab === 0
                            ? "Optimize power consumption, battery health, and background device drain."
                            : (root.activeTab === 1
                                ? "Fine-tune sleep modes, lid behavior, and wake triggers for your MacBook."
                                : "Discover, install, update, and remove T2-optimized plugins from plugins.omarchy.org.")
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }
                      }

                      Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.lastNotice !== ""
                        text: root.lastNotice
                        color: Color.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
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
                      visible: root.activeTab === 0
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
                          anchors.right: parent.right
                          anchors.leftMargin: Style.space(16)
                          anchors.rightMargin: Style.space(16)
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
                              text: root.status.battery.health + "%"
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              font.bold: true
                            }
                            Text {
                              text: "Health (" + root.status.battery.cycles + " cycles)"
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
                            checked: root.status.wifiPowerSave
                            onToggled: root.setOption("wifi_powersave", !root.status.wifiPowerSave ? "on" : "off")
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
                                    checked: modelData.managed
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

                            Row {
                              spacing: Style.space(8)
                              Text {
                                text: "PCIe Ports Compatibility"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                              }
                              Text {
                                text: (root.status && root.status.pciePortsCompat) ? "Enabled" : "Disabled"
                                color: (root.status && root.status.pciePortsCompat) ? root.accent : root.dim
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                anchors.verticalCenter: parent.verticalCenter
                              }
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
                            checked: root.status && !!root.status.pciePortsCompat
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
                            checked: root.status.audioPowerSave
                            onToggled: root.setOption("audio_powersave", !root.status.audioPowerSave ? "true" : "false")
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
                            checked: root.status.usbAutosuspend
                            onToggled: root.setOption("usb_autosuspend", !root.status.usbAutosuspend ? "true" : "false")
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
                      visible: root.activeTab === 1
                      width: parent.width
                      spacing: Style.space(12)

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
                            checked: root.status.wakeOnLid
                            onToggled: root.setOption("wake_lid", !root.status.wakeOnLid ? "on" : "off")
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
                            checked: root.status.wakeOnAc
                            onToggled: root.setOption("wake_ac", !root.status.wakeOnAc ? "on" : "off")
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
                            checked: root.status.touchbarBlank
                            onToggled: root.setOption("touchbar_blank", !root.status.touchbarBlank ? "true" : "false")
                          }
                        }
                      }
                    }

                    // =========================================================
                    // TAB 2: PLUGINS
                    // =========================================================
                    Column {
                      id: pluginsTabContent
                      visible: root.activeTab === 2
                      width: parent.width
                      spacing: Style.space(12)



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
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.body
                                    font.bold: true
                                    elide: Text.ElideRight
                                  }

                                  Text {
                                    text: "v" + modelData.version
                                    color: Color.accent
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                  }

                                  Text {
                                    visible: Boolean(modelData.rankLabel)
                                    text: modelData.rankLabel
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
                                  visible: modelData.installed
                                  anchors.verticalCenter: parent.verticalCenter
                                  checked: Boolean(modelData.installed && modelData.enabled)
                                  busy: pluginCard.isBusy
                                  enabled: !pluginCard.isBusy && root.activePluginOpId === ""
                                  onToggled: root.togglePlugin(modelData.id, !modelData.enabled)

                                  PanelToolTip {
                                    visible: cardToggleSwitch.containsMouse
                                    text: modelData.enabled ? "Enabled" : "Disabled"
                                  }
                                }
                              }
                            }

                            // 2. Description
                            Text {
                              width: parent.width
                              text: modelData.description
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
              width: Math.min(parent.width - Style.space(32), Style.space(640))
              height: Math.min(parent.height - Style.space(32), Style.space(560))
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
                      text: "Apply recommended defaults"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: true
                      color: root.foreground
                    }
                    Text {
                      text: "Optimized suspend and battery life configuration"
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
                    text: "Applying the recommended defaults means that the macbook will wake from suspend easier and will have a longer battery life, up to 42% less battery drain compared to the default configuration. Depending on the system load."
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: root.foreground
                    wrapMode: Text.WordWrap
                    lineHeight: 1.2
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
                          { title: "Sleep mode", val: "Modern Standby", desc: "Allows MacBook to enter low-power s2idle standby for faster, more reliable wakeups." },
                          { title: "Lid Close Action", val: "Suspend", desc: "Suspends the MacBook to preserve power when closing the display lid on battery." },
                          { title: "Clam Shell Mode", val: "Stay Awake", desc: "Keeps the system awake when connected to an external monitor and charger with lid closed." },
                          { title: "Wake On Lid Open", val: "Enabled", desc: "Automatically and instantly wakes the system when opening the laptop lid." },
                          { title: "Wake on AC Charger Connect", val: "Disabled", desc: "Prevents unwanted wakeups when plugging in the USB-C or MagSafe charger." },
                          { title: "Hibernate Delay", val: "Never", desc: "Prevents unexpected transitions to disk hibernation to maintain quick sleep responsiveness." },
                          { title: "Touch Bar Blanking on Sleep", val: "Enabled", desc: "Ensures the OLED Touch Bar is powered off cleanly immediately upon suspend." }
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
                              text: "•"
                              color: root.accent
                              font.bold: true
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
                        model: [
                          { title: "Wi-Fi Power Management", val: "Disabled", desc: "Prevents wireless sleep states that can cause Wi-Fi drops or stall system wakeups." },
                          { title: "Ethernet Management", val: "Unmanaged (All devices)", desc: "Stops NetworkManager from querying inactive internal T2 network interfaces." },
                          { title: "Audio Controller Power Save", val: "Enabled", desc: "Powers down the internal audio hardware when inactive to reduce idle battery drain." },
                          { title: "USB Device Autosuspend", val: "Enabled", desc: "Puts unused internal USB controllers into low-power mode to preserve battery." },
                          { title: "Keyboard Backlight Idle Auto-Dim", val: "1 min", desc: "Dims the keyboard illumination after 1 minute of inactivity to save energy." },
                          { title: "PCIe ports compatibility", val: "Enabled", desc: "Enables low-power PCIe bus states to eliminate battery drain (updates bootloader)." }
                        ]

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
                              text: "•"
                              color: root.accent
                              font.bold: true
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

                // Footer Buttons
                Row {
                  id: recFooterRow
                  anchors.bottom: parent.bottom
                  anchors.right: parent.right
                  anchors.margins: Style.space(20)
                  spacing: Style.space(10)

                  Button {
                    text: "Cancel"
                    bordered: true
                    onClicked: {
                      root.recommendedConfirmOpen = false
                      root.dismissRecommendedPrompt()
                    }
                  }

                  Button {
                    text: "Apply recommended defaults"
                    iconText: "󰁨"
                    bordered: true
                    accent: root.accent
                    selected: true
                    onClicked: {
                      root.applyRecommendedOptions()
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
        }
      }
    }
  }
}
}
