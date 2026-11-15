import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// CPU and memory for this machine on the bar, then the name of each fleet box
// (servers and ginger-dev boxes) coloured by its state: urgent when it is
// offline or past a disk, swap or memory limit, bold while T3 agents work there,
// dim when quiet, and an accent pause mark when an agent waits for you. The
// tooltip and the dropdown say why, with counts, for every device on the tailnet.
//
// Kept light on purpose, and it never sends a notification: trouble is only a
// colour on the bar. What runs while the dropdown is closed:
// - /proc/stat and /proc/meminfo, read in-process every two seconds;
// - every pollSeconds (60), one in-process GET of each fleet box's
//   https://<box>/stats.json (~400 bytes; the box does the T3 work in its own
//   `dev refresh`), plus ginger-dev's agents.json for this machine. No process
//   is started for a poll. A box that fails twice in a row is offline and is
//   retried every 5 minutes; what the bar shows only changes after two polls
//   in a row agree, so nothing flashes;
// - omarchy-tailnet-stats (Tailscale's device list, disk, temperature), once
//   at start and then every 30 minutes.
// While the dropdown is open the collector also runs every refreshSeconds.
// While the session is locked nothing above runs: each tick only asks
// Hyprland (over its socket, no process) whether the lock is still there.
Panel {
  id: root
  moduleName: "ruttydm.tailnet"
  ipcTarget: "ruttydm.tailnet"

  readonly property int refreshSeconds: Math.max(10, Math.min(300, Number(setting("refreshSeconds", 15)) || 15))
  // Nothing polls while the session is locked (checkLock).
  property bool paused: false
  readonly property int pollSeconds: Math.max(30, Math.min(600, Number(setting("pollSeconds", 60)) || 60))
  readonly property string btopCommand: String(setting("btopCommand", "omarchy-launch-or-focus-tui btop"))
  readonly property string collectorPath: (Quickshell.env("HOME") || "") + "/.local/bin/omarchy-tailnet-stats"

  // ---- This machine, for the bar label.
  property var lastCpu: null
  property int localCpu: -1
  property var localMem: null

  // ---- The tailnet. `devices` is the collector's list; `polls` the in-process
  // stats.json polls by device id; `live` is both together, which is what shows.
  property var devices: []
  property var polls: ({})
  property var inflight: ({})
  property int inflightCount: 0
  readonly property var live: Model.withPolls(devices, polls, updated)
  readonly property string agentsPath: (Quickshell.env("HOME") || "") + "/.local/state/ginger-dev/agents.json"
  readonly property int sweepMinutes: 30
  property real updated: 0
  property string error: ""
  property bool loading: false
  property real now: Date.now() / 1000
  readonly property var groups: Model.grouped(live)
  readonly property var flatDevices: Model.flat(groups)
  readonly property int onlineCount: Model.onlineCount(live)
  readonly property string troubleText: Model.problemSummary(live, now)
  readonly property var segments: Model.barSegments(localCpu, localMem, live)

  property int cursorIndex: 0
  property bool cursorActive: false

  readonly property color fg: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property bool vertical: bar ? bar.vertical : false
  // StyledText colours for the dropdown rows (always #rrggbb).
  readonly property var htmlColors: ({ dim: hex(dim), accent: hex(accent), urgent: hex(urgent) })
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Commons.Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Commons.Color.accent) : "transparent"

  // The open-panel dot spans the label, as it does under the clock.
  readonly property real openPanelIndicatorWidth: vertical ? button.labelWidth : segmentRow.implicitWidth

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function hex(c) {
    function h(v) { var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h(c.r) + h(c.g) + h(c.b)
  }

  function roleColor(role) {
    if (role === "urgent") return root.urgent
    if (role === "accent") return root.accent
    if (role === "dim") return root.dim
    return root.barForeground
  }

  function openT3(device) {
    if (!device || !device.t3Url) return
    Qt.openUrlExternally(device.t3Url)
    root.close()
  }

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
    root.now = Date.now() / 1000
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

  function setPoll(id, state) {
    var next = {}
    for (var k in root.polls) next[k] = root.polls[k]
    next[id] = state
    root.polls = next
  }

  // Locked when any monitor lists LOCK in solitaryBlockedBy, as Omarchy's own
  // omarchy-hyprland-session-locked checks. Reads the monitor objects from the
  // last refresh and asks Hyprland for fresh ones for the next check.
  function checkLock() {
    var objs = []
    var ms = Hyprland.monitors.values
    for (var i = 0; i < ms.length; i++) objs.push(ms[i].lastIpcObject)
    root.paused = Model.sessionLocked(objs)
    Hyprland.refreshMonitors()
  }

  // One tick: this machine from /proc and agents.json, then every fleet box that is due.
  function pollFleet() {
    var now = Date.now() / 1000
    root.now = now
    for (var i = 0; i < root.devices.length; i++) {
      var d = root.devices[i]
      if (!d.self) continue
      agentsFile.reload()
      var stats = Model.selfStats(d.stats, root.localCpu, root.localMem, Model.localAgents(agentsFile.text(), now))
      if (stats) root.setPoll(d.id, Model.observe(root.polls[d.id], true, stats, now, d))
    }
    var targets = Model.pollTargets(root.devices)
    for (var j = 0; j < targets.length; j++) {
      if (!root.inflight[targets[j].id] && Model.due(root.polls[targets[j].id], now)) root.fetchBox(targets[j])
    }
  }

  // GET <box>/stats.json in-process. Bounded: headers over maxBytes abort, and
  // the watchdog below aborts anything older than POLL.timeout seconds.
  function fetchBox(d) {
    var url = Model.statsUrl(d)
    if (!url) return
    var xhr = new XMLHttpRequest()
    var entry = { xhr: xhr, started: Date.now() / 1000, device: d, aborted: false }
    var inflight = root.inflight
    inflight[d.id] = entry
    root.inflightCount++
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.HEADERS_RECEIVED) {
        if (Number(xhr.getResponseHeader("Content-Length") || 0) > Model.POLL.maxBytes) {
          entry.aborted = true
          xhr.abort()
        }
      } else if (xhr.readyState === XMLHttpRequest.DONE) {
        root.finishFetch(d.id, entry, !entry.aborted && xhr.status === 200 ? xhr.responseText : null)
      }
    }
    xhr.open("GET", url)
    xhr.setRequestHeader("Accept", "application/json")
    xhr.send()
  }

  function finishFetch(id, entry, text) {
    if (root.inflight[id] !== entry) return  // already finished (abort fires DONE too)
    delete root.inflight[id]
    root.inflightCount = Math.max(0, root.inflightCount - 1)
    var stats = null
    if (text && text.length <= Model.POLL.maxBytes) {
      try { stats = Model.fromStatsJson(JSON.parse(text)) } catch (e) { stats = null }
    }
    root.now = Date.now() / 1000
    root.setPoll(id, Model.observe(root.polls[id], stats !== null, stats, entry.started, entry.device))
  }

  function abortStale() {
    var now = Date.now() / 1000
    for (var id in root.inflight) {
      var entry = root.inflight[id]
      if (now - entry.started < Model.POLL.timeout) continue
      entry.aborted = true
      try { entry.xhr.abort() } catch (e) {}
      root.finishFetch(id, entry, null)
    }
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
      root.refresh()
    }
  }

  FileView { id: statFile; path: "/proc/stat"; blockLoading: true; printErrors: false }
  FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true; printErrors: false }
  FileView { id: agentsFile; path: root.agentsPath; blockLoading: true; printErrors: false }

  Timer {
    interval: 2000
    running: !root.paused
    repeat: true
    triggeredOnStart: true
    onTriggered: root.sampleLocal()
  }

  // The fleet poll: in-process, no process started. Keeps ticking while locked,
  // but then only checks whether the lock is still there.
  Timer {
    interval: root.pollSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.checkLock()
      if (!root.paused) root.pollFleet()
    }
  }

  // While locked, Hyprland's events (unlocking sends several) prompt a quick
  // recheck, so the bar wakes within a second of unlocking, not a minute.
  Connections {
    target: Hyprland
    enabled: root.paused
    function onRawEvent(event) { if (!lockRecheck.running) lockRecheck.restart() }
  }

  Timer {
    id: lockRecheck
    interval: 1000
    onTriggered: {
      root.checkLock()
      if (!root.paused) {
        root.sampleLocal()
        root.pollFleet()
      }
    }
  }

  Timer {
    interval: 2000
    running: root.inflightCount > 0
    repeat: true
    onTriggered: root.abortStale()
  }

  // The collector: at start, every sweepMinutes, and every refreshSeconds while open.
  Timer {
    interval: (root.opened ? root.refreshSeconds : root.sweepMinutes * 60) * 1000
    running: !root.paused || root.opened
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
    // The plain text keeps the button's own sizing and visibility rules; on a
    // horizontal bar the coloured runs below are drawn instead of its label.
    text: root.vertical ? Model.barText(root.localCpu, root.localMem) : Model.segmentsText(root.segments)
    labelVisible: root.vertical
    fixedWidth: root.vertical ? -1 : Math.ceil(segmentRow.implicitWidth + Style.spaceReal(7.5) * 2)
    tooltipText: root.opened ? "" : (root.live.length > 0
      ? Model.fleetTooltip(root.localCpu, root.localMem, root.live, root.now)
      : Model.barTooltip(root.localCpu, root.localMem))
    horizontalMargin: 7.5
    verticalPadding: 6
    fontSize: 12

    // The label as coloured runs. Same font and figure centring as WidgetButton's label.
    Row {
      id: segmentRow
      visible: !root.vertical
      anchors.centerIn: parent
      anchors.verticalCenterOffset: (segmentMetrics.descent - segmentMetrics.ascent
        + segmentMetrics.tightBoundingRect("0").height) / 2
      scale: button.pressScale

      Repeater {
        model: root.segments
        Text {
          required property var modelData
          textFormat: Text.PlainText
          text: modelData.text
          color: root.roleColor(modelData.role)
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          font.bold: modelData.role === "bold"
          renderType: Text.NativeRendering
          Behavior on color { ColorAnimation { duration: Style.duration(160) } }
        }
      }
    }

    FontMetrics {
      id: segmentMetrics
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
    }

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
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if ((t === "t" || t === "T") && root.cursorActive) root.openT3(root.flatDevices[root.cursorIndex])
      }

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
                if (root.live.length === 0) return root.loading ? "loading…" : ""
                var parts = [root.onlineCount + " of " + root.live.length + " online"]
                var fresh = root.loading ? "updating…" : Model.updatedLabel(root.updated, root.now)
                if (fresh) parts.push(fresh)
                return parts.join(" · ")
              }
            }
          }

          // Everything that turns the bar urgent, in one line.
          PlainText {
            visible: root.troubleText !== ""
            width: parent.width
            text: root.troubleText
            color: root.urgent
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
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

  // A thin horizontal meter, urgent from `limit`.
  component Meter: Item {
    property int value: -1
    property int limit: 90
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
      color: parent.value >= parent.limit ? root.urgent : root.fg
      Behavior on width { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
    }
  }

  component Vital: Row {
    property string label: ""
    property string value: ""
    property int pct: -1
    property int limit: 90
    // The dashboard chart a click on this vital opens.
    property string metric: ""
    spacing: Style.space(8)
    layoutDirection: Qt.RightToLeft

    Meter { value: parent.pct; limit: parent.limit; anchors.verticalCenter: parent.verticalCenter }
    PlainText {
      text: parent.value
      color: parent.pct >= parent.limit ? root.urgent : root.fg
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

  // A small dim second line that may carry <font>/<b> from Model.js (always escaped there).
  component StyledLine: Text {
    textFormat: Text.StyledText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    leftPadding: Style.space(16)
    elide: Text.ElideRight
  }

  component DeviceRow: Item {
    id: row
    property var device: ({})
    readonly property var stats: device.stats || null
    readonly property bool selected: root.cursorActive && root.cursorIndex === device.index
    readonly property bool clickable: Model.canActivate(device)
    readonly property bool urgentRow: Model.problems(device).length > 0
    property bool overAgents: false

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
      // An offline fleet box stays readable: it is the thing to look at.
      opacity: row.device.online ? 1 : (row.urgentRow ? 0.85 : 0.45)

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
            color: !row.device.online ? "transparent" : (row.urgentRow ? root.urgent : Commons.Color.accent)
            border.width: row.device.online ? 0 : 1
            border.color: row.urgentRow ? root.urgent : root.dim
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

        StyledLine {
          width: parent.width
          text: Model.detailHtml(row.device, root.now, root.htmlColors)
        }

        // T3 agents on this box; a click here opens its T3.
        StyledLine {
          id: agentsLine
          visible: text !== ""
          width: Math.min(implicitWidth, parent.width)
          text: Model.agentsHtml(row.device, root.htmlColors)
          color: root.fg
          font.underline: row.overAgents && row.device.t3Url !== ""
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
          metric: "cpu"
          value: row.stats ? row.stats.cpu + "%" : ""
          pct: row.stats ? row.stats.cpu : -1
        }
        Vital {
          anchors.right: parent.right
          label: "RAM"
          metric: "mem"
          limit: Model.LIMITS.mem
          value: row.stats ? Model.memLabel(row.stats) : ""
          pct: row.stats ? Model.percent(row.stats.memUsed, row.stats.memTotal) : -1
        }
        // Swap shares the dashboard's memory chart.
        Vital {
          anchors.right: parent.right
          visible: row.stats !== null && row.stats.swapTotal > 0
          label: "SWP"
          metric: "mem"
          limit: Model.LIMITS.swap
          value: row.stats && row.stats.swapTotal > 0 ? Model.swapLabel(row.stats) : ""
          pct: row.stats && row.stats.swapTotal > 0 ? Model.percent(row.stats.swapUsed, row.stats.swapTotal) : -1
        }
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      function inside(item, x, y) {
        if (!item.visible) return false
        var p = mouse.mapToItem(item, x, y)
        return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height
      }

      // A click on the agents line opens the box's T3; on a meter, that chart on
      // its dashboard; anywhere else on the row keeps the row's own action.
      onClicked: function(ev) {
        if (row.device.t3Url && inside(agentsLine, ev.x, ev.y)) {
          root.openT3(row.device)
          return
        }
        var url = ""
        if (inside(right, ev.x, ev.y)) {
          var p = mouse.mapToItem(right, ev.x, ev.y)
          var vital = right.childAt(right.width - 1, p.y)
          if (vital && vital.metric) url = Model.metricUrl(row.device, vital.metric)
        }
        if (url !== "") {
          Qt.openUrlExternally(url)
          root.close()
        } else {
          root.activate(row.device)
        }
      }
      onPositionChanged: function(ev) { row.overAgents = row.device.t3Url !== "" && inside(agentsLine, ev.x, ev.y) }
      onContainsMouseChanged: {
        if (containsMouse) root.cursorActive = false
        else row.overAgents = false
      }
    }

    PanelToolTip {
      visible: mouse.containsMouse && (row.clickable || row.overAgents)
      text: row.overAgents ? "Open " + row.device.t3Url.replace(/^https:\/\//, "") : Model.activateHint(row.device)
      fontFamily: root.fontFamily
    }
  }
}
