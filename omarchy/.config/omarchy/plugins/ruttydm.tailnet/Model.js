.pragma library

// Pure helpers for the tailnet widget: /proc parsing for the bar label, and
// validation, grouping and wording for the dropdown. No QML types here, so
// tests/tailnet-model.test.js can load this file under Node.

// Same glyphs the old command widget used. In JetBrainsMono Nerd Font they
// render opposite their names: U+F2DB is the pin-grid chip, U+F061A the memory stick.
var CPU_ICON = ""
var RAM_ICON = "󰘚"

// Agent marks: working (play), waiting for you (pause), done (check); a failing PR is a plain ✗.
var WORK_ICON = String.fromCodePoint(0xF040A)
var WAIT_ICON = String.fromCodePoint(0xF03E4)
var DONE_ICON = String.fromCodePoint(0xF012C)
var FAIL_MARK = "\u2717"

// A fleet box turns urgent on the bar at these percentages, or when it is offline.
var LIMITS = { disk: 90, swap: 80, mem: 95 }

var GROUPS = [
  { key: "server", title: "Servers" },
  { key: "dev", title: "Dev boxes" },
  { key: "other", title: "Other devices" }
]

function cpuTimes(statText) {
  var first = String(statText || "").split("\n", 1)[0].trim().split(/\s+/)
  if (first[0] !== "cpu" || first.length < 9) return null
  var total = 0
  for (var i = 1; i <= 8; i++) {
    var n = Number(first[i])
    if (!isFinite(n)) return null
    total += n
  }
  return { total: total, idle: Number(first[4]) + Number(first[5]) }
}

function cpuPercent(prev, cur) {
  if (!prev || !cur) return -1
  var total = cur.total - prev.total
  if (total <= 0) return -1
  var busy = total - (cur.idle - prev.idle)
  return Math.max(0, Math.min(100, Math.round(busy * 100 / total)))
}

function memory(meminfoText) {
  var total = 0, available = -1
  var lines = String(meminfoText || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^(MemTotal|MemAvailable):\s+(\d+)\s*kB/.exec(lines[i])
    if (!m) continue
    if (m[1] === "MemTotal") total = Number(m[2]) * 1024
    else available = Number(m[2]) * 1024
  }
  if (total <= 0 || available < 0) return null
  return { total: total, used: Math.max(0, total - available) }
}

function pad3(n) {
  var s = String(n)
  while (s.length < 3) s = " " + s
  return s
}

// "  23%   41%" with the chip and memory glyphs; fixed width so the bar does
// not shift as the numbers change.
function barText(cpu, mem) {
  var c = cpu >= 0 ? pad3(cpu) + "%" : "  –%"
  var r = mem ? pad3(Math.round(mem.used * 100 / mem.total)) + "%" : "  –%"
  return CPU_ICON + " " + c + "  " + RAM_ICON + " " + r
}

function barTooltip(cpu, mem) {
  var lines = ["CPU " + (cpu >= 0 ? cpu + "%" : "–")]
  if (mem) lines.push("Memory " + gib(mem.used) + " / " + gib(mem.total) + " GiB")
  lines.push("Click for every device on the tailnet")
  return lines.join("\n")
}

function gib(bytes) {
  var v = Number(bytes) / 1073741824
  if (!isFinite(v) || v < 0) return "–"
  return v >= 100 ? String(Math.round(v)) : v.toFixed(1)
}

function percent(used, total) {
  if (!(total > 0) || !(used >= 0)) return -1
  return Math.max(0, Math.min(100, Math.round(used * 100 / total)))
}

function ago(epoch, now) {
  if (!(epoch > 0)) return ""
  var s = Math.max(0, Math.floor(now - epoch))
  if (s < 90) return "just now"
  if (s < 3600) return Math.round(s / 60) + " min ago"
  if (s < 48 * 3600) return Math.round(s / 3600) + " h ago"
  return Math.round(s / 86400) + " d ago"
}

function duration(seconds) {
  var s = Number(seconds)
  if (!(s >= 0)) return ""
  if (s < 3600) return Math.max(1, Math.round(s / 60)) + "m"
  if (s < 48 * 3600) return Math.round(s / 3600) + "h"
  return Math.round(s / 86400) + "d"
}

function updatedLabel(updated, now) {
  if (!(updated > 0)) return ""
  var s = Math.max(0, Math.floor(now - updated))
  return s < 5 ? "updated just now" : "updated " + s + "s ago"
}

// ---------------------------------------------------------------- input

function str(value, max) {
  var s = value === undefined || value === null ? "" : String(value)
  return s.length > max ? s.slice(0, max) : s
}

function num(value, lo, hi) {
  var n = Number(value)
  if (value === null || value === undefined || typeof value === "boolean" || !isFinite(n)) return null
  if (n < lo || n > hi) return null
  return n
}

function cleanStats(raw) {
  if (!raw || typeof raw !== "object") return null
  var cpu = num(raw.cpu, 0, 100)
  var memTotal = num(raw.memTotal, 1, 1e16)
  var memAvailable = num(raw.memAvailable, 0, 1e16)
  if (cpu === null || memTotal === null || memAvailable === null) return null
  var swapTotal = num(raw.swapTotal, 0, 1e16)
  var swapFree = num(raw.swapFree, 0, 1e16)
  var load = Array.isArray(raw.load) ? raw.load.slice(0, 3).map(function(v) { return num(v, 0, 1e5) }).filter(function(v) { return v !== null }) : []
  return {
    cpu: Math.round(cpu),
    cores: num(raw.cores, 1, 4096),
    load: load,
    memTotal: memTotal,
    memUsed: Math.max(0, memTotal - Math.min(memAvailable, memTotal)),
    diskTotal: num(raw.diskTotal, 1, 1e18),
    diskUsed: num(raw.diskUsed, 0, 1e18),
    tempC: num(raw.tempC, -50, 200),
    uptime: num(raw.uptime, 0, 1e12),
    swapTotal: swapTotal || 0,
    swapUsed: swapTotal > 0 && swapFree !== null ? Math.max(0, swapTotal - Math.min(swapFree, swapTotal)) : 0,
    agents: cleanAgents(raw.agents),
    ciFailing: count(raw.ciFailing)
  }
}

// A whole count from JSON: numbers only (no "9", no true), 0 when absent or out of range.
function count(value) {
  var n = typeof value === "number" ? num(value, 0, 1e5) : null
  return n === null ? 0 : Math.floor(n)
}

// { working, waiting, done } or null when the box reports no agents (no T3, older ginger-dev).
function cleanAgents(raw) {
  if (!raw || typeof raw !== "object") return null
  return { working: count(raw.working), waiting: count(raw.waiting), done: count(raw.done) }
}

// The collector's output, parsed and bounded. Throws on anything that is not
// its JSON, so the caller can keep showing the last good result.
function parse(text) {
  var data = JSON.parse(String(text || ""))
  if (!data || data.v !== 1 || !Array.isArray(data.devices)) throw new Error("unexpected collector output")
  var devices = []
  var list = data.devices.slice(0, 200)
  for (var i = 0; i < list.length; i++) {
    var d = list[i] || {}
    var group = d.group === "server" || d.group === "dev" ? d.group : "other"
    var url = str(d.url, 200)
    if (!/^https:\/\/[a-z0-9.-]+$/.test(url)) url = ""
    var t3Url = str(d.t3Url, 200)
    if (!/^https:\/\/t3\.[a-z0-9.-]+$/.test(t3Url)) t3Url = ""
    devices.push({
      id: str(d.id, 120) || ("device-" + i),
      name: str(d.name, 64) || "device",
      host: str(d.host, 64),
      os: str(d.os, 16),
      online: d.online === true,
      self: d.self === true,
      group: group,
      lastSeen: num(d.lastSeen, 0, 1e11) || 0,
      url: url,
      t3Url: t3Url,
      stats: cleanStats(d.stats),
      error: str(d.error, 40)
    })
  }
  return { updated: num(data.updated, 0, 1e11) || 0, error: str(data.error, 200), devices: devices }
}

// [{ key, title, devices }] in display order, empty groups dropped. Each
// device gets `index`, its position in the flat keyboard order.
function grouped(devices) {
  var out = []
  var index = 0
  for (var g = 0; g < GROUPS.length; g++) {
    var members = []
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].group !== GROUPS[g].key) continue
      var copy = {}
      for (var k in devices[i]) copy[k] = devices[i][k]
      copy.index = index++
      members.push(copy)
    }
    if (members.length > 0) out.push({ key: GROUPS[g].key, title: GROUPS[g].title, devices: members })
  }
  return out
}

function flat(groups) {
  var out = []
  for (var g = 0; g < groups.length; g++)
    for (var i = 0; i < groups[g].devices.length; i++) out.push(groups[g].devices[i])
  return out
}

function onlineCount(devices) {
  var n = 0
  for (var i = 0; i < devices.length; i++) if (devices[i].online) n++
  return n
}

function subtitle(d) {
  var parts = []
  if (d.self) parts.push("this machine")
  else if (d.host && d.host !== d.name) parts.push(d.host)
  if (d.os && d.os !== "linux") parts.push(d.os === "macos" ? "macOS" : d.os)
  return parts.join(" · ")
}

// Second line of a row: the vitals when there are stats, otherwise why not.
function detail(d, now) {
  if (!d.online) {
    var seen = ago(d.lastSeen, now)
    return seen ? "offline · seen " + seen : "offline"
  }
  var s = d.stats
  if (!s) {
    if (!d.url) return "online"
    return "online · " + (d.error || "no stats")
  }
  var parts = []
  if (s.load.length > 0) parts.push("load " + s.load[0].toFixed(2))
  var disk = percent(s.diskUsed, s.diskTotal)
  if (disk >= 0) parts.push("disk " + disk + "%")
  if (s.tempC !== null) parts.push(Math.round(s.tempC) + "°C")
  if (s.uptime !== null) parts.push("up " + duration(s.uptime))
  return parts.join(" · ")
}

function memLabel(s) {
  return gib(s.memUsed) + " / " + gib(s.memTotal) + " GiB"
}

function canActivate(d) {
  return d.self || d.url !== ""
}

// The box dashboard opens a metric's history chart from the URL hash.
function metricUrl(d, metric) {
  if (!d || !d.url || ["cpu", "mem", "load", "disk", "temp"].indexOf(metric) < 0) return ""
  return d.url + "/#" + metric
}

function activateHint(d) {
  if (d.self) return "Open btop"
  if (d.url) return "Open " + d.url.replace(/^https:\/\//, "")
  return ""
}

// ---------------------------------------------------------------- fleet

// The boxes the bar watches: servers and dev boxes other than this machine.
function isFleet(d) {
  return !d.self && (d.group === "dev" || d.group === "server")
}

// Why a device needs attention, as short phrases ("swap 98%", "off"); empty when it is fine.
// Offline only counts for fleet boxes; this machine is never offline to itself.
function problems(d) {
  if (!d) return []
  if (!d.online) return isFleet(d) ? ["off"] : []
  var s = d.stats
  if (!s || !(isFleet(d) || d.self)) return []
  var out = []
  var disk = percent(s.diskUsed, s.diskTotal)
  if (disk >= LIMITS.disk) out.push("disk " + disk + "%")
  var swap = s.swapTotal > 0 ? percent(s.swapUsed, s.swapTotal) : -1
  if (swap >= LIMITS.swap) out.push("swap " + swap + "%")
  var mem = percent(s.memUsed, s.memTotal)
  if (mem >= LIMITS.mem) out.push("mem " + mem + "%")
  return out
}

function agentsOf(d) {
  var a = d && d.stats && d.online ? d.stats.agents : null
  return a || { working: 0, waiting: 0, done: 0 }
}

function failingOf(d) {
  return d && d.stats && d.online ? d.stats.ciFailing || 0 : 0
}

// One pill per fleet box, plus this machine when it has agents or a problem.
function pills(devices) {
  var out = []
  for (var i = 0; i < devices.length; i++) {
    var d = devices[i]
    if (!isFleet(d) && !d.self) continue
    var a = agentsOf(d)
    var p = {
      name: d.name, problems: problems(d), working: a.working, waiting: a.waiting, failing: failingOf(d),
      unknown: d.online && !d.self && d.url !== "" && !d.stats
    }
    if (d.self && p.problems.length === 0 && p.working + p.waiting + p.failing === 0) continue
    out.push(p)
  }
  return out
}

// The bar label as coloured runs: [{ text, role }] with role fg | dim | bold | accent | urgent.
// The local CPU and memory come first, unchanged; each pill follows two spaces after.
function barSegments(cpu, mem, devices) {
  var out = [{ text: barText(cpu, mem), role: "fg" }]
  var list = pills(devices || [])
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    var busy = p.working + p.waiting + p.failing > 0
    out.push({ text: "  ", role: "fg" })
    if (p.problems.length > 0) out.push({ text: p.name + " " + p.problems.join(" "), role: "urgent" })
    else out.push({ text: p.name, role: busy ? "bold" : "dim" })
    if (p.unknown && p.problems.length === 0) out.push({ text: "?", role: "dim" })
    if (p.working > 0) {
      out.push({ text: " " + p.working, role: "fg" })
      out.push({ text: WORK_ICON, role: "dim" })
    }
    if (p.waiting > 0) out.push({ text: " " + p.waiting + WAIT_ICON, role: "accent" })
    if (p.failing > 0) out.push({ text: " " + FAIL_MARK + p.failing, role: "urgent" })
  }
  return out
}

function segmentsText(segments) {
  var s = ""
  for (var i = 0; i < segments.length; i++) s += segments[i].text
  return s
}

function urgentCount(devices) {
  var n = 0
  for (var i = 0; i < devices.length; i++) if (problems(devices[i]).length > 0) n++
  return n
}

// "rz swap 98% · pi offline 4 min": every problem on one line, for the dropdown and the tooltip.
function problemSummary(devices, now) {
  var parts = []
  for (var i = 0; i < devices.length; i++) {
    var d = devices[i]
    var list = problems(d)
    if (list.length === 0) continue
    if (!d.online) {
      var seen = ago(d.lastSeen, now)
      parts.push(d.name + " offline" + (seen && seen !== "just now" ? " since " + seen.replace(/ ago$/, "") : ""))
    } else {
      parts.push(d.name + " " + list.join(", "))
    }
  }
  var failing = 0
  for (var j = 0; j < devices.length; j++) failing += failingOf(devices[j])
  if (failing > 0) parts.push(failing + (failing === 1 ? " PR" : " PRs") + " failing")
  return parts.join(" · ")
}

// "3 working · 1 waiting · 2 done · 1 PR failing", or "" for a box that reports no agents.
function agentsLine(d) {
  if (!d || !d.online || !d.stats || !d.stats.agents) return ""
  var a = d.stats.agents
  var parts = []
  if (a.working > 0) parts.push(a.working + " working")
  if (a.waiting > 0) parts.push(a.waiting + " waiting")
  if (a.done > 0) parts.push(a.done + " done")
  var f = failingOf(d)
  if (f > 0) parts.push(f + (f === 1 ? " PR" : " PRs") + " failing")
  return parts.length > 0 ? parts.join(" · ") : "no agents running"
}

function escapeHtml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function tint(text, color) {
  return '<font color="' + escapeHtml(color) + '">' + escapeHtml(text) + "</font>"
}

// The agents line as StyledText: waiting in the accent colour, failing PRs urgent, the rest plain.
function agentsHtml(d, colors) {
  if (!agentsLine(d)) return ""
  var a = d.stats.agents
  var parts = []
  if (a.working > 0) parts.push(escapeHtml(a.working + " ") + tint(WORK_ICON + " working", colors.dim))
  if (a.waiting > 0) parts.push("<b>" + tint(a.waiting + WAIT_ICON + " waiting", colors.accent) + "</b>")
  if (a.done > 0) parts.push(escapeHtml(a.done + " ") + tint(DONE_ICON + " done", colors.dim))
  var f = failingOf(d)
  if (f > 0) parts.push(tint(FAIL_MARK + f + (f === 1 ? " PR" : " PRs") + " failing", colors.urgent))
  if (parts.length === 0) return tint("no agents running", colors.dim)
  var html = parts.join(tint(" · ", colors.dim))
  return d.t3Url ? html + tint("  \u2197 t3", colors.dim) : html
}

// The vitals line as StyledText, with the number that breaks a limit in the urgent colour.
function detailHtml(d, now, colors) {
  if (!d.online) {
    var text = detail(d, now)
    return problems(d).length > 0 ? tint(text, colors.urgent) : escapeHtml(text)
  }
  var s = d.stats
  if (!s) return escapeHtml(detail(d, now))
  var parts = []
  if (s.load.length > 0) parts.push(escapeHtml("load " + s.load[0].toFixed(2)))
  var disk = percent(s.diskUsed, s.diskTotal)
  if (disk >= 0) parts.push("disk " + (disk >= LIMITS.disk ? tint(disk + "%", colors.urgent) : disk + "%"))
  if (s.tempC !== null) parts.push(Math.round(s.tempC) + "°C")
  if (s.uptime !== null) parts.push(escapeHtml("up " + duration(s.uptime)))
  return parts.join(" · ")
}

function swapLabel(s) {
  return gib(s.swapUsed) + " / " + gib(s.swapTotal) + " GiB"
}

// The bar's tooltip once the fleet is known: this machine, then what needs attention, then agents.
function fleetTooltip(cpu, mem, devices, now) {
  var lines = ["CPU " + (cpu >= 0 ? cpu + "%" : "–")]
  if (mem) lines.push("Memory " + gib(mem.used) + " / " + gib(mem.total) + " GiB")
  var trouble = problemSummary(devices || [], now)
  if (trouble) lines.push("", trouble)
  var agentLines = []
  for (var i = 0; i < (devices || []).length; i++) {
    var line = agentsLine(devices[i])
    if (line && line !== "no agents running") agentLines.push(devices[i].name + ": " + line)
  }
  if (agentLines.length > 0) {
    lines.push("", "Agents")
    lines = lines.concat(agentLines)
  }
  lines.push("", "Click for every device on the tailnet")
  return lines.join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    cpuTimes: cpuTimes, cpuPercent: cpuPercent, memory: memory, barText: barText, barTooltip: barTooltip,
    gib: gib, percent: percent, ago: ago, duration: duration, updatedLabel: updatedLabel,
    parse: parse, grouped: grouped, flat: flat, onlineCount: onlineCount, subtitle: subtitle,
    detail: detail, memLabel: memLabel, canActivate: canActivate, activateHint: activateHint, metricUrl: metricUrl,
    LIMITS: LIMITS, WORK_ICON: WORK_ICON, WAIT_ICON: WAIT_ICON, DONE_ICON: DONE_ICON,
    isFleet: isFleet, problems: problems, pills: pills, barSegments: barSegments, segmentsText: segmentsText,
    urgentCount: urgentCount, problemSummary: problemSummary, agentsLine: agentsLine, agentsHtml: agentsHtml,
    detailHtml: detailHtml, swapLabel: swapLabel, fleetTooltip: fleetTooltip, escapeHtml: escapeHtml
  }
}
