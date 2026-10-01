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
    opened = false
    nonT2DialogOpen = false
  }

  function showNonT2Dialog() {
    if (root.opened) root.close()
    nonT2DialogOpen = true
  }

  function setOption(key, val) {
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
        s.hibernateDelay = parseInt(val) || 0
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
    function selectTab(index: int): void {
      root.activeTab = index
      if (index === 2 && root.opened) {
        root.fetchPlugins(true)
      }
    }
    function setPluginFilter(query: string): void { root.pluginFilterQuery = query }
    function setPluginMode(mode: int): void { root.pluginFilterMode = mode }
    function refreshPlugins(): void { root.fetchPlugins(true) }
    function togglePlugin(pluginId: string, enable: bool): void { root.togglePlugin(pluginId, enable) }
    function setOption(key: string, val: string): void { root.setOption(key, val) }
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
          onClicked: root.close()
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
                    onClicked: root.refresh()
                  }

                  PanelActionButton {
                    iconText: "󰅖"
                    tooltipText: "Close panel (Esc)"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.subtitle
                    size: Style.space(30)
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
              // Left Sidebar: Vertical Tabs
              // -------------------------------------------------------------
              Column {
                id: verticalTabsCol
                width: Style.space(220)
                height: parent.height
                spacing: Style.space(10)

                Repeater {
                  model: root.tabs

                  delegate: BorderSurface {
                    id: tabButton
                    width: verticalTabsCol.width
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

                Item {
                  width: 1
                  height: Style.space(12)
                }

                // Hardware Summary in sidebar footer
                BorderSurface {
                  width: verticalTabsCol.width
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
                                text: root.status.battery.percent + "%"
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

                      // 2. PCIe ASPM Policy
                      BorderSurface {
                        width: parent.width
                        height: aspmCol.implicitHeight + Style.space(28)
                        color: Util.alpha(root.foreground, 0.03)
                        radius: Style.cornerRadius

                        Column {
                          id: aspmCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.space(14)
                          spacing: Style.space(10)

                          Row {
                            width: parent.width
                            Item {
                              width: parent.width - aspmStatusText.implicitWidth
                              height: aspmTitle.implicitHeight + aspmDesc.implicitHeight
                              Column {
                                anchors.fill: parent
                                spacing: 2
                                Text {
                                  id: aspmTitle
                                  text: "PCIe Active State Power Management (ASPM)"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                                Text {
                                  id: aspmDesc
                                  text: "Enables L0s/L1 link states across NVMe storage, T2 bridge, and PCIe devices."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                }
                              }
                            }

                            Text {
                              id: aspmStatusText
                              text: Model.formatAspm(root.status.aspm)
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
                                { val: "powersave", label: "Powersave" },
                                { val: "default", label: "Default" },
                                { val: "performance", label: "Full Power" }
                              ]

                              delegate: Button {
                                width: parent.btnWidth
                                text: modelData.label
                                bordered: true
                                selected: root.status.aspm === modelData.val
                                onClicked: root.setOption("aspm", modelData.val)
                              }
                            }
                          }
                        }
                      }

                      // 3. Wi-Fi Power Save Toggle
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

                      // 4. Audio Controller Power Save
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

                      // 1. System Sleep Mode (mem_sleep: deep vs s2idle)
                      BorderSurface {
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
                                  text: "System Sleep Mode (mem_sleep)"
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.body
                                  font.bold: true
                                }
                                Text {
                                  id: memSleepDesc
                                  text: "Deep (S3 Suspend-to-RAM) completely powers down devices to prevent sleep drain."
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
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
                            spacing: Style.space(10)
                            readonly property real btnWidth: (width - spacing) / 2

                            Repeater {
                              model: [
                                { val: "deep", label: "Deep (S3 Recommended)" },
                                { val: "s2idle", label: "Modern Standby (s2idle)" }
                              ]

                              delegate: Button {
                                width: parent.btnWidth
                                text: modelData.label
                                bordered: true
                                selected: root.status.memSleep === modelData.val
                                onClicked: root.setOption("mem_sleep", modelData.val)
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
                                selected: root.status.lidAction === modelData.val
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
                              text: root.status.hibernateDelay
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

                                // Installed / Enabled Badge
                                Rectangle {
                                  visible: modelData.installed && !modelData.updateAvailable
                                  height: Style.space(22)
                                  width: installedBadgeText.implicitWidth + Style.space(12)
                                  radius: Style.cornerRadius
                                  color: modelData.enabled ? Util.alpha(Color.accent, 0.15) : Util.alpha(root.foreground, 0.06)

                                  Text {
                                    id: installedBadgeText
                                    anchors.centerIn: parent
                                    text: modelData.enabled ? "󰄲 Active" : "󰄱 Disabled"
                                    color: modelData.enabled ? Color.accent : root.dim
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
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
                                Item {
                                  id: cardToggleSwitch
                                  visible: modelData.installed
                                  anchors.verticalCenter: parent.verticalCenter
                                  width: Style.space(38)
                                  height: Style.space(20)

                                  readonly property bool isChecked: Boolean(modelData.installed && modelData.enabled)
                                  readonly property bool isBusy: pluginCard.isBusy

                                  Rectangle {
                                    id: switchTrack
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: cardToggleSwitch.isChecked
                                      ? Color.accent
                                      : Util.alpha(root.foreground, 0.15)
                                    border.color: cardToggleSwitch.isChecked
                                      ? Color.accent
                                      : Util.alpha(root.foreground, 0.25)
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    // Sliding Knob: on the right when checked, on the left when unchecked
                                    Rectangle {
                                      id: switchKnob
                                      width: parent.height - 4
                                      height: width
                                      radius: width / 2
                                      anchors.verticalCenter: parent.verticalCenter
                                      x: cardToggleSwitch.isChecked ? parent.width - width - 2 : 2
                                      color: cardToggleSwitch.isChecked ? "#ffffff" : Qt.darker(root.foreground, 1.3)

                                      Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    }
                                  }

                                  MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !cardToggleSwitch.isBusy && root.activePluginOpId === ""
                                    onClicked: {
                                      root.togglePlugin(modelData.id, !modelData.enabled)
                                    }
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
                                text: pluginCard.isBusy ? "Installing..." : "Install"
                                iconText: "󰏔"
                                bordered: true
                                accent: root.accent
                                enabled: !pluginCard.isBusy && root.activePluginOpId === ""
                                onClicked: root.installPlugin(modelData.repo || modelData.installCommand, modelData.id)
                              }

                              // Update button (if update available)
                              Button {
                                visible: modelData.installed && modelData.updateAvailable
                                text: pluginCard.isBusy ? "Updating..." : ("Update to v" + modelData.version)
                                iconText: "󰚰"
                                bordered: true
                                accent: root.accent
                                enabled: !pluginCard.isBusy && root.activePluginOpId === ""
                                onClicked: root.updatePlugin(modelData.id)
                              }

                              // Enable / Disable button (if installed)
                              Button {
                                visible: modelData.installed
                                text: modelData.enabled ? "Disable" : "Enable"
                                iconText: modelData.enabled ? "󰄲" : "󰄱"
                                bordered: true
                                selected: modelData.enabled
                                enabled: !pluginCard.isBusy && root.activePluginOpId === ""
                                onClicked: root.togglePlugin(modelData.id, !modelData.enabled)
                              }

                              // Remove button (if installed)
                              Button {
                                visible: modelData.installed
                                text: pluginCard.isBusy ? "Removing..." : "Remove"
                                iconText: "󰆴"
                                bordered: true
                                enabled: !pluginCard.isBusy && root.activePluginOpId === ""
                                onClicked: root.removePlugin(modelData.id)
                              }

                              Item {
                                width: 1
                                height: 1
                              }

                              // External link to repository
                              Button {
                                visible: modelData.repo && modelData.repo.length > 0
                                text: "GitHub ↗"
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
        }
      }
    }
  }
}
}
