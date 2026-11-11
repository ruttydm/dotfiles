import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// CPU and memory for this machine on the bar, and a dropdown with the same
// for every device on the tailnet.
//
// The bar label reads /proc itself every two seconds; nothing is spawned for
// it. The dropdown runs omarchy-tailnet-stats once when it opens and then
// every refreshSeconds while it stays open, and never while it is closed. That
// collector does the network work: the device list from Tailscale, and each
// ginger-dev box's https://<box>/stats.json.
Panel {
  id: root
  moduleName: "ruttydm.tailnet"
  ipcTarget: "ruttydm.tailnet"

  readonly property int refreshSeconds: Math.max(10, Math.min(300, Number(setting("refreshSeconds", 15)) || 15))
  readonly property string btopCommand: String(setting("btopCommand", "omarchy-launch-or-focus-tui btop"))
  readonly property string collectorPath: (Quickshell.env("HOME") || "") + "/.local/bin/omarchy-tailnet-stats"

  // ---- This machine, for the bar label.
  property var lastCpu: null
  property int localCpu: -1
  property var localMem: null

  // ---- The tailnet, for the dropdown.
  property var devices: []
  property real updated: 0
  property string error: ""
  property bool loading: false
  property real now: Date.now() / 1000
  readonly property var groups: Model.grouped(devices)
  readonly property var flatDevices: Model.flat(groups)
  readonly property int onlineCount: Model.onlineCount(devices)

  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Commons.Color.accent) : "transparent"

  // The open-panel dot spans the label, as it does under the clock.
  readonly property real openPanelIndicatorWidth: button.labelWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function sampleLocal() {
    statFile.reload()
    memFile.reload()
    var cur = Model.cpuTimes(statFile.text())
    var pct = Model.cpuPercent(root.lastCpu, cur)
    if (pct >= 0) root.localCpu = pct
    if (cur) root.lastCpu = cur
    var mem = Model.memory(memFile.text())
    if (mem) root.localMem = mem
  }

  function refresh() {
    if (collector.running) return
    root.loading = true
    collector.command = [root.collectorPath]
    collector.running = true
  }

  function applyCollector(text) {
    root.loading = false
    try {
      var data = Model.parse(text)
      root.devices = data.devices
      root.updated = data.updated
      root.error = data.error
    } catch (e) {
      // Keep the last good list on screen; say why it stopped moving.
      root.error = "Could not read device stats"
    }
    root.clampCursor()
  }

  function clampCursor() {
    root.cursorIndex = Math.max(0, Math.min(root.cursorIndex, root.flatDevices.length - 1))
  }

  function moveCursor(delta) {
    if (root.flatDevices.length === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      return
    }
    root.cursorIndex = Math.max(0, Math.min(root.flatDevices.length - 1, root.cursorIndex + delta))
  }

  function activate(device) {
    if (!device || !Model.canActivate(device)) return
    if (device.self) {
      if (root.bar) root.bar.run(root.btopCommand)
    } else {
      Qt.openUrlExternally(device.url)
    }
    root.close()
  }

  onOpenedChanged: {
    if (opened) {
      root.now = Date.now() / 1000
      root.cursorActive = false
      root.cursorIndex = 0
    }
  }

  FileView { id: statFile; path: "/proc/stat"; blockLoading: true; printErrors: false }
  FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true; printErrors: false }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleLocal()
  }

  Timer {
    interval: root.refreshSeconds * 1000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.now = Date.now() / 1000
  }

  Process {
    id: collector
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCollector(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("ruttydm.tailnet", text.trim().slice(0, 500))
    }
    onExited: function(code) {
      if (code !== 0) {
        root.loading = false
        root.error = "Device stats failed (exit " + code + ")"
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.barText(root.localCpu, root.localMem)
    tooltipText: root.opened ? "" : Model.barTooltip(root.localCpu, root.localMem)
    horizontalMargin: 7.5
    verticalPadding: 6
    fontSize: 12

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.bar) root.bar.run(root.btopCommand)
      } else if (b === Qt.LeftButton) {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(540))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.activate(root.flatDevices[root.cursorIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refresh() }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          // ---- Title, how many are up, and how fresh the numbers are.
          Item {
            width: parent.width
            implicitHeight: Math.max(title.implicitHeight, status.implicitHeight)

            PlainText {
              id: title
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Tailnet"
              font.pixelSize: Style.font.title
              font.bold: true
            }

            PlainText {
              id: status
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              color: root.dim
              font.pixelSize: Style.font.bodySmall
              text: {
                if (root.devices.length === 0) return root.loading ? "loading…" : ""
                var parts = [root.onlineCount + " of " + root.devices.length + " online"]
                var fresh = root.loading ? "updating…" : Model.updatedLabel(root.updated, root.now)
                if (fresh) parts.push(fresh)
                return parts.join(" · ")
              }
            }
          }

          PlainText {
            visible: root.error !== ""
            width: parent.width
            text: root.error
            color: root.urgent
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          Repeater {
            model: root.groups

            Column {
              id: group
              required property var modelData
              width: column.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: group.modelData.title
                foreground: root.fg
                fontFamily: root.fontFamily
              }

              Repeater {
                model: group.modelData.devices
                DeviceRow {
                  required property var modelData
                  width: group.width
                  device: modelData
                }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ components

  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  // A thin horizontal meter, urgent from 90%.
  component Meter: Item {
    property int value: -1
    implicitWidth: Style.space(48)
    implicitHeight: Style.space(5)

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
    }

    Rectangle {
      visible: parent.value >= 0
      height: parent.height
      radius: height / 2
      width: Math.max(height, parent.width * Math.max(0, parent.value) / 100)
      color: parent.value >= 90 ? root.urgent : root.fg
      Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
    }
  }

  component Vital: Row {
    property string label: ""
    property string value: ""
    property int pct: -1
    spacing: Style.space(8)
    layoutDirection: Qt.RightToLeft

    Meter { value: parent.pct; anchors.verticalCenter: parent.verticalCenter }
    PlainText {
      text: parent.value
      color: parent.pct >= 90 ? root.urgent : root.fg
      font.pixelSize: Style.font.bodySmall
      anchors.verticalCenter: parent.verticalCenter
    }
    PlainText {
      text: parent.label
      color: root.dim
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  component DeviceRow: Item {
    id: row
    property var device: ({})
    readonly property var stats: device.stats || null
    readonly property bool selected: root.cursorActive && root.cursorIndex === device.index
    readonly property bool clickable: Model.canActivate(device)

    implicitHeight: content.implicitHeight + Style.space(12)

    Rectangle {
      anchors.fill: parent
      radius: Style.space(8)
      color: row.selected ? root.selectedFill : (mouse.containsMouse && row.clickable ? root.hoverFill : "transparent")
    }

    Item {
      id: content
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      implicitHeight: Math.max(left.implicitHeight, right.implicitHeight)
      opacity: row.device.online ? 1 : 0.45

      Column {
        id: left
        anchors.left: parent.left
        anchors.right: right.left
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Row {
          width: parent.width
          spacing: Style.space(8)

          // Online dot: filled when up, a ring when not.
          Rectangle {
            width: Style.space(8)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: row.device.online ? Commons.Color.accent : "transparent"
            border.width: row.device.online ? 0 : 1
            border.color: root.dim
          }

          PlainText {
            text: row.device.name
            font.bold: true
            width: Math.min(implicitWidth, parent.width - Style.space(16))
          }

          PlainText {
            text: Model.subtitle(row.device)
            color: root.dim
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - parent.children[1].width - Style.space(32))
          }
        }

        PlainText {
          width: parent.width
          leftPadding: Style.space(16)
          text: Model.detail(row.device, root.now)
          color: root.dim
          font.pixelSize: Style.font.bodySmall
        }
      }

      Column {
        id: right
        visible: row.stats !== null && row.device.online
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)
        width: visible ? implicitWidth : 0

        Vital {
          anchors.right: parent.right
          label: "CPU"
          value: row.stats ? row.stats.cpu + "%" : ""
          pct: row.stats ? row.stats.cpu : -1
        }
        Vital {
          anchors.right: parent.right
          label: "RAM"
          value: row.stats ? Model.memLabel(row.stats) : ""
          pct: row.stats ? Model.percent(row.stats.memUsed, row.stats.memTotal) : -1
        }
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      // A click on the CPU or RAM meters opens that chart on the box's dashboard;
      // anywhere else on the row keeps the row's own action.
      onClicked: function(ev) {
        var p = mouse.mapToItem(right, ev.x, ev.y)
        var metric = right.visible && p.x >= 0 && p.y >= 0 && p.x <= right.width && p.y <= right.height
          ? (p.y < right.height / 2 ? "cpu" : "mem") : ""
        var url = metric ? Model.metricUrl(row.device, metric) : ""
        if (url !== "") {
          Qt.openUrlExternally(url)
          root.close()
        } else {
          root.activate(row.device)
        }
      }
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = false }
    }

    PanelToolTip {
      visible: mouse.containsMouse && row.clickable
      text: Model.activateHint(row.device)
      fontFamily: root.fontFamily
    }
  }
}
