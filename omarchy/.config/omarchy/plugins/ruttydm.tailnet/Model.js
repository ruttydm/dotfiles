.pragma library

// Pure helpers for the tailnet widget: /proc parsing for the bar label, and
// validation, grouping and wording for the dropdown. No QML types here, so
// tests/tailnet-model.test.js can load this file under Node.

// Same glyphs the old command widget used. In JetBrainsMono Nerd Font they
// render opposite their names: U+F2DB is the pin-grid chip, U+F061A the memory stick.
var CPU_ICON = ""
var RAM_ICON = "󰘚"

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
    uptime: num(raw.uptime, 0, 1e12)
  }
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

if (typeof module !== "undefined") {
  module.exports = {
    cpuTimes: cpuTimes, cpuPercent: cpuPercent, memory: memory, barText: barText, barTooltip: barTooltip,
    gib: gib, percent: percent, ago: ago, duration: duration, updatedLabel: updatedLabel,
    parse: parse, grouped: grouped, flat: flat, onlineCount: onlineCount, subtitle: subtitle,
    detail: detail, memLabel: memLabel, canActivate: canActivate, activateHint: activateHint, metricUrl: metricUrl
  }
}
