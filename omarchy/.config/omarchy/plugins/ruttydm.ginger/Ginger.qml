import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model
import "../ruttydm.tailnet/Model.js" as Tailnet

// Super+Alt+D: recent projects on the Ginger boxes, newest activity first, and
// each box's CPU and memory over the last six hours.
//
// Costs nothing while closed: the manifest is not keepLoaded, so the shell only
// creates this item when the panel is summoned and destroys it on close. While
// open it reads, in-process and without starting any process:
// - this machine's /proc/stat and /proc/meminfo every 2 s (the tailnet widget's parser);
// - each box's https://<box>.afai.cc/stats.json on open and every 30 s;
// - each box's status.json and history.json (about 15 KB gzipped together) on open,
//   only when the cached copy in ~/.cache/ginger-panel.json is over two minutes old,
//   because the boxes rewrite those files every two minutes anyway.
// Enter or a click opens the project in the default browser (xdg-open).
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property real now: Date.now() / 1000

  // box → { v, box, fetched, projects, history }, as cached on disk.
  property var records: ({})
  // box → { cpu, mem, uptime } live numbers.
  property var live: ({})
  property var errors: ({})
  property var lastCpu: null
  property var inflight: ({})
  // This machine's box name (ginger-dev writes it at `dev setup`); its live numbers come from /proc.
  property string selfBox: ""

  readonly property var rowsByBox: {
    var out = {}
    for (var b in root.records) out[b] = root.records[b].projects
    return out
  }
  readonly property var allRows: Model.recent(rowsByBox)
  readonly property var shownRows: Model.filter(allRows, filterText)
  readonly property var totals: Model.counts(rowsByBox)

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property color hairline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.14)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(660), panel.width - Style.gapsOut * 2)
  readonly property int rowHeight: Math.max(Style.space(30), Style.font.body + Style.space(14))
  readonly property int visibleRows: Math.max(4, Math.min(12, Math.floor((panel.height * 0.8 - Style.space(260)) / rowHeight)))

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.now = Date.now() / 1000
    root.selfBox = String(boxFile.text() || "").trim()
    root.loadCache()
    root.sampleLocal()
    root.refresh(false)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.abortAll()
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ruttydm.ginger")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ---- data

  function loadCache() {
    cacheFile.reload()
    var raw
    try { raw = JSON.parse(cacheFile.text() || "{}") } catch (e) { raw = {} }
    var next = {}
    for (var i = 0; i < Model.BOXES.length; i++) {
      var b = Model.BOXES[i]
      var r = raw && raw[b] ? Model.readCache(JSON.stringify(raw[b])) : null
      if (r) next[b] = r
    }
    root.records = next
  }

  function saveCache() {
    cacheFile.setText(JSON.stringify(root.records))
  }

  // `force` re-fetches project lists and charts even when the cache is fresh (the r key).
  function refresh(force) {
    var t = Date.now() / 1000
    for (var i = 0; i < Model.BOXES.length; i++) {
      var b = Model.BOXES[i]
      if (b !== root.selfBox) root.get(b, "stats.json", function(box, text) { root.applyStats(box, text) })
      if (force || Model.stale(root.records[b], t)) root.fetchBox(b)
    }
  }

  function fetchBox(box) {
    var parts = {}
    function done(name, text) {
      parts[name] = text
      if (!("status.json" in parts) || !("history.json" in parts)) return
      var status = null, history = null
      try { status = JSON.parse(parts["status.json"]) } catch (e) {}
      try { history = JSON.parse(parts["history.json"]) } catch (e) {}
      if (!status) {
        root.setError(box, "unreachable")
        return
      }
      root.setError(box, "")
      var next = {}
      for (var k in root.records) next[k] = root.records[k]
      next[box] = Model.boxRecord(box, status, history, Date.now() / 1000)
      root.records = next
      root.saveCache()
    }
    root.get(box, "status.json", function(b, text) { done("status.json", text) })
    root.get(box, "history.json", function(b, text) { done("history.json", text) })
  }

  // GET https://<box>.afai.cc/<file> in-process. `cb(box, text)` gets null on any failure.
  function get(box, file, cb) {
    var base = Model.boxUrl(box)
    if (!base) return cb(box, null)
    var key = box + "/" + file
    if (root.inflight[key]) return
    var xhr = new XMLHttpRequest()
    var entry = { xhr: xhr, started: Date.now() / 1000, done: false }
    root.inflight[key] = entry
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || entry.done) return
      entry.done = true
      delete root.inflight[key]
      var ok = xhr.status === 200 && xhr.responseText.length <= Model.MAX_BYTES
      cb(box, ok ? xhr.responseText : null)
    }
    xhr.open("GET", base + "/" + file)
    xhr.setRequestHeader("Accept", "application/json")
    xhr.send()
  }

  function abortStale(all) {
    var t = Date.now() / 1000
    for (var key in root.inflight) {
      var e = root.inflight[key]
      if (!all && t - e.started < 10) continue
      try { e.xhr.abort() } catch (err) {}
    }
  }

  function abortAll() { root.abortStale(true) }

  function setError(box, text) {
    var next = {}
    for (var k in root.errors) next[k] = root.errors[k]
    next[box] = text
    root.errors = next
  }

  function setLive(box, value) {
    var next = {}
    for (var k in root.live) next[k] = root.live[k]
    next[box] = value
    root.live = next
  }

  function applyStats(box, text) {
    var s = null
    try { s = text ? Tailnet.fromStatsJson(JSON.parse(text)) : null } catch (e) { s = null }
    if (!s) {
      if (!root.records[box]) root.setError(box, "unreachable")
      return
    }
    root.setLive(box, { cpu: s.cpu, mem: s.memTotal > 0 ? s.memUsed * 100 / s.memTotal : -1, uptime: s.uptime || 0 })
  }

  // This machine straight from /proc, with the tailnet widget's parsers.
  function sampleLocal() {
    if (!root.selfBox) return
    statFile.reload()
    memFile.reload()
    uptimeFile.reload()
    var cur = Tailnet.cpuTimes(statFile.text())
    var cpu = Tailnet.cpuPercent(root.lastCpu, cur)
    if (cur) root.lastCpu = cur
    var mem = Tailnet.memory(memFile.text())
    var prev = root.live[root.selfBox]
    root.setLive(root.selfBox, {
      cpu: cpu >= 0 ? cpu : (prev ? prev.cpu : -1),
      mem: mem ? mem.used * 100 / mem.total : -1,
      uptime: Number(String(uptimeFile.text() || "").split(" ")[0]) || 0
    })
  }

  // ---- actions

  function openUrl(url) {
    if (!url) return
    Quickshell.execDetached(["xdg-open", url])
    root.dismiss()
  }

  function activate(index) {
    var row = root.shownRows[index]
    if (row) root.openUrl(row.url)
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    list.positionViewAtBeginning()
  }

  function move(delta) {
    var n = root.shownRows.length
    if (n === 0) return
    root.selectedIndex = Math.max(0, Math.min(n - 1, root.selectedIndex + delta))
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // ---- sources and timers (all only exist while the panel is open)

  FileView { id: cacheFile; path: root.home + "/.cache/ginger-panel.json"; blockLoading: true; printErrors: false; atomicWrites: true }
  FileView { id: boxFile; path: root.home + "/.config/ginger-dev/box"; blockLoading: true; printErrors: false }
  FileView { id: statFile; path: "/proc/stat"; blockLoading: true; printErrors: false }
  FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true; printErrors: false }
  FileView { id: uptimeFile; path: "/proc/uptime"; blockLoading: true; printErrors: false }

  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    onTriggered: {
      root.now = Date.now() / 1000
      root.sampleLocal()
      root.abortStale(false)
    }
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.refresh(false)
  }

  // ---- view

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
  }

  // A line over a faint area, 0–100 %, oldest on the left. Repaints only when its data changes.
  component Spark: Canvas {
    property var values: []
    property color stroke: root.accent
    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onStrokeChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var v = values || []
      var n = v.length - 1
      var pts = []
      for (var i = 0; i < v.length; i++) {
        if (v[i] === null || v[i] === undefined) continue
        pts.push([n > 0 ? i * width / n : 0, height - 1 - (v[i] / 100) * (height - 2)])
      }
      if (pts.length < 2) return
      ctx.beginPath()
      ctx.moveTo(pts[0][0], height)
      for (var j = 0; j < pts.length; j++) ctx.lineTo(pts[j][0], pts[j][1])
      ctx.lineTo(pts[pts.length - 1][0], height)
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(stroke.r, stroke.g, stroke.b, 0.12)
      ctx.fill()
      ctx.beginPath()
      ctx.moveTo(pts[0][0], pts[0][1])
      for (var k = 1; k < pts.length; k++) ctx.lineTo(pts[k][0], pts[k][1])
      ctx.strokeStyle = stroke
      ctx.lineWidth = 1.4
      ctx.stroke()
    }
  }

  component Vital: Row {
    property string label: ""
    property var values: []
    property real value: -1
    property int limit: 101
    spacing: Style.space(6)
    height: Style.space(24)
    readonly property bool hot: value >= limit

    Label { width: Style.space(28); height: parent.height; text: parent.label; color: root.dim; font.pixelSize: Style.font.caption }
    Spark {
      width: parent.width - Style.space(28) - Style.space(40) - parent.spacing * 2
      height: Style.space(20)
      anchors.verticalCenter: parent.verticalCenter
      values: parent.values
      stroke: parent.hot ? root.urgent : root.accent
    }
    Label {
      width: Style.space(40); height: parent.height
      horizontalAlignment: Text.AlignRight
      text: Model.pct(parent.value)
      color: parent.hot ? root.urgent : root.foreground
      font.pixelSize: Style.font.bodySmall
    }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "ruttydm-ginger"

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: column.implicitHeight + card.contentTopInset + card.contentBottomInset
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (event.key === Qt.Key_Up) {
            root.move(-1)
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
            root.move(1)
          } else if (event.key === Qt.Key_PageUp) {
            root.move(-root.visibleRows)
          } else if (event.key === Qt.Key_PageDown) {
            root.move(root.visibleRows)
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.selectedIndex)
          } else if (event.key === Qt.Key_F5 || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R)) {
            root.refresh(true)
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.space(10)

        // Title and filter.
        Row {
          width: parent.width
          height: Style.space(30)
          spacing: Style.space(12)
          Label { text: "Ginger"; font.bold: true; font.pixelSize: Style.font.heading; height: parent.height }
          Label {
            width: parent.width - x
            height: parent.height
            text: root.filterText || "type to filter projects…"
            opacity: root.filterText ? 1 : 0.58
            font.pixelSize: Style.font.heading
          }
        }

        // One tile per box: CPU and memory over the last six hours, live value on the right.
        Row {
          id: tiles
          width: parent.width
          spacing: Style.space(10)
          Repeater {
            model: Model.BOXES
            Rectangle {
              required property string modelData
              readonly property var rec: root.records[modelData] || null
              readonly property var hist: rec ? rec.history : null
              readonly property var now_: root.live[modelData] || null
              width: (tiles.width - tiles.spacing * (Model.BOXES.length - 1)) / Model.BOXES.length
              height: tileCol.implicitHeight + Style.space(12)
              radius: root.cornerRadius
              color: tileMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06) : "transparent"
              border.width: 1
              border.color: root.hairline

              Column {
                id: tileCol
                anchors.fill: parent
                anchors.margins: Style.space(6)
                anchors.leftMargin: Style.space(9)
                anchors.rightMargin: Style.space(9)
                spacing: Style.space(2)
                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Label { id: boxName; text: modelData; font.bold: true }
                  Label {
                    width: parent.width - boxName.width - parent.spacing
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Style.font.caption
                    text: root.errors[modelData] ? root.errors[modelData] : Model.subtitle(hist, now_ ? now_.uptime : 0)
                    color: root.errors[modelData] ? root.urgent : root.dim
                    anchors.baseline: boxName.baseline
                  }
                }
                Vital { width: parent.width; label: "CPU"; values: hist ? hist.cpu : []; value: now_ ? now_.cpu : -1 }
                Vital { width: parent.width; label: "RAM"; values: hist ? hist.mem : []; value: now_ ? now_.mem : -1; limit: Tailnet.LIMITS.mem }
              }

              MouseArea {
                id: tileMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openUrl(Model.boxUrl(modelData))
              }
            }
          }
        }

        Row {
          width: parent.width
          Label {
            width: parent.width / 2
            text: "RECENT PROJECTS"
            color: root.dim
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
          Label {
            width: parent.width / 2
            horizontalAlignment: Text.AlignRight
            text: root.totals.total ? root.totals.total + " served · " + root.totals.text + " · charts 6 h" : "loading…"
            color: root.dim
            font.pixelSize: Style.font.caption
          }
        }

        ListView {
          id: list
          width: parent.width
          height: Math.max(1, Math.min(root.shownRows.length, root.visibleRows)) * root.rowHeight
          clip: true
          model: root.shownRows
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: root.selectedIndex

          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool current: index === root.selectedIndex
            width: list.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: current ? root.selectedBackground : "transparent"

            Rectangle {
              visible: parent.current
              width: Style.space(3); radius: width / 2
              height: parent.height - Style.space(14)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              color: root.accent
            }

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(10)

              Rectangle {
                width: Style.space(7); height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: modelData.up ? root.accent : root.hairline
              }
              Label { width: Style.space(170); height: parent.height; text: modelData.name; font.bold: true }
              Label {
                width: parent.width - Style.space(7) - Style.space(170) - Style.space(36) - Style.space(36) - parent.spacing * 4
                height: parent.height
                text: modelData.branch + (modelData.worktrees ? " · +" + modelData.worktrees + " worktrees" : "")
                color: root.dim
                font.pixelSize: Style.font.caption
              }
              Rectangle {
                width: Style.space(36); height: Style.space(18)
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.space(3)
                color: "transparent"
                border.width: 1
                border.color: root.hairline
                Label { anchors.centerIn: parent; text: modelData.box; font.pixelSize: Style.font.caption }
              }
              Label {
                width: Style.space(36); height: parent.height
                horizontalAlignment: Text.AlignRight
                text: Model.ago(modelData.activity, root.now)
                color: root.dim
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.selectedIndex = index
              onClicked: root.openUrl(modelData.url)
            }
          }
        }

        Label {
          visible: root.totals.total > 0 && root.shownRows.length === 0
          width: parent.width
          height: root.rowHeight
          text: "No project matches “" + root.filterText + "”"
          color: root.dim
        }

        Rectangle { width: parent.width; height: 1; color: root.hairline }

        Label {
          width: parent.width
          height: Style.space(16)
          text: "↵ open in browser    ↑↓ move    click a box for its dashboard    ctrl+r refresh    esc close"
          color: root.dim
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
