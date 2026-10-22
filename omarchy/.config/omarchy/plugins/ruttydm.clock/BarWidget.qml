import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Date/time label for the bar, and the host for the calendar popup.
//
// Left click reveals the calendar — asking "what is the date?" is what a
// click on a clock means — right click walks the common label formats, and
// middle click opens the timezone picker. When the system zone is not the
// home zone, the label also shows that home clock so travel stays comparable.
BarWidget {
  id: root
  moduleName: "omarchy.clock"

  property date displayDate: clock.date

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")
    : setting("formatAlt", "d MMMM 'W'ww yyyy")

  readonly property var formatRing: Model.clockFormatRing(configuredFormat, configuredAltFormat, Model.clockFormats(vertical))

  // What the bar shows is what shell.json stores, so a cycled format is the
  // format from then on rather than something that reverts on restart.
  readonly property string activeFormat: configuredFormat

  // Home zone beside local time. An empty compareTimezone turns it off.
  // The suffix stays off while that zone is already the system zone.
  readonly property string compareTimezone: normalizedZone(setting("compareTimezone", "Europe/Brussels"))
  readonly property string compareLabel: {
    var label = String(setting("compareLabel", "BRU") || "")
    return label !== "" ? label : "BRU"
  }
  property string localZone: ""
  property int compareOffsetMinutes: 0
  property bool zoneReady: false
  property bool componentReady: false

  readonly property bool showCompare: zoneReady && compareTimezone !== "" && localZone !== compareTimezone
  readonly property string compareClock: Model.formatOffsetClock(displayDate, compareOffsetMinutes, false)
  readonly property string compareClockFull: Model.formatOffsetClock(displayDate, compareOffsetMinutes, true)
  readonly property string compareRelation: Model.relativeOffsetLabel(-displayDate.getTimezoneOffset(), compareOffsetMinutes)
  readonly property string displayText: {
    var base = formatted(displayDate)
    if (!showCompare || compareClock === "") return base
    if (vertical) return base + "\n—\n" + compareLabel + "\n" + compareClock
    return base + "  ·  " + compareLabel + " " + compareClock
  }
  readonly property string clockTooltip: {
    if (!zoneReady || localZone === "") return ""
    var local = Model.zoneCity(localZone) + " " + Qt.formatDateTime(displayDate, "HH:mm")
    if (!showCompare) return local
    return local + "  ·  Brussels " + compareClock + "  ·  " + compareRelation
  }
  readonly property var verticalLines: displayText.split("\n")

  function normalizedZone(zone) {
    if (zone === "") return ""
    var text = String(zone == null ? "" : zone)
    if (/^[A-Za-z0-9_+-]+(\/[A-Za-z0-9_+-]+)*$/.test(text)) return text
    return "Europe/Brussels"
  }

  function refresh() {
    displayDate = new Date()
    probeZone()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  // `date +%z` is the zone's current offset, DST included. Re-read it on a
  // timer so a transition is not stuck until the next login.
  function probeZone() {
    if (!compareTimezone) {
      zoneReady = false
      localZone = ""
      return
    }
    if (!zoneProbe || zoneProbe.running) return
    var zone = compareTimezone
    // zone is already restricted to an IANA name, so it is safe to inline.
    var script = "z=" + zone
      + "; zonefile=$(readlink -f /etc/localtime)"
      + "; zonefile=${zonefile#/usr/share/zoneinfo/}"
      + "; off=$(TZ=\"$z\" date +%z)"
      + "; printf '%s %s\\n' \"$zonefile\" \"$off\""
    zoneProbe.command = ["bash", "-c", script]
    zoneProbe.running = true
  }

  function applyZoneProbe(text) {
    var parts = String(text || "").trim().split(/\s+/)
    if (parts.length < 2) return
    var minutes = Model.offsetMinutes(parts[1])
    if (minutes === null) return
    localZone = parts[0]
    compareOffsetMinutes = minutes
    zoneReady = true
  }

  function cycleFormat() {
    var current = String(configuredFormat)
    var next = Model.nextClockFormat(formatRing, current)
    if (next === "" || next === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  // ---- Calendar popup. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  // The clock fills more slot than it paints a mark for, at both
  // orientations: horizontally it is a text label in a padded slot, so the
  // dot takes the label width; vertically it is a stack of icon-sized lines,
  // so the dot takes one line — the same mark every icon widget gets, rather
  // than a rule running the height of the whole stack.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    if (componentReady) probeZone()
  }
  Component.onCompleted: {
    componentReady = true
    probeZone()
  }

  Process {
    id: zoneProbe
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyZoneProbe(text)
    }
  }

  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.probeZone()
  }

  SystemClock {
    id: clock
    // Stock precision is minutes, which freezes a :ss label for the whole minute.
    precision: SystemClock.Seconds
    onDateChanged: root.displayDate = date
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "omarchy.clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    tooltipText: root.clockTooltip
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFormat()
      else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3
            ? button.fontSize * 0.9
            : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
