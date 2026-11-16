.pragma library

// The Ginger panel's data, kept out of QML so node can test it (tests/ginger-model.test.js).
// Sources are what each box already serves on the tailnet, rewritten by its `dev refresh`
// every two minutes: https://<box>.afai.cc/status.json (projects with their last activity)
// and /history.json (24 h of vitals). Live numbers come from /stats.json, or /proc on this machine.

var BOXES = ["tp", "rz", "pi"]
var DOMAIN = "afai.cc"
var STALE = 120              // seconds: the boxes rewrite their files every two minutes
var WINDOW = 6 * 3600        // seconds of history the charts show
var POINTS = 90              // at most this many points per chart
var MAX_BYTES = 1048576      // a status.json larger than this is not ours

function boxUrl(box) {
  return /^[a-z0-9-]+$/.test(String(box)) ? "https://" + box + "." + DOMAIN : ""
}

function num(v) {
  return typeof v === "number" && isFinite(v) ? v : null
}

function str(v, max) {
  return typeof v === "string" ? v.slice(0, max || 200) : ""
}

// One box's status.json as project rows: worktrees fold into their main checkout, which takes
// the newest activity and that checkout's branch. Projects without a URL are left out.
function projectsFrom(box, status) {
  var list = status && Array.isArray(status.projects) ? status.projects : []
  var byName = {}
  var order = []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!p || typeof p !== "object") continue
    var name = str(p.worktree_of, 120) || str(p.name, 120)
    if (!name) continue
    var e = byName[name]
    if (!e) {
      e = byName[name] = { name: name, box: box, url: "", up: false, activity: 0, branch: "", worktrees: 0 }
      order.push(name)
    }
    if (p.worktree_of) {
      e.worktrees++
    } else {
      var url = str(p.url, 300)
      if (/^https:\/\/[a-z0-9.-]+\/?$/.test(url)) e.url = url.replace(/\/$/, "")
      e.up = p.web_up === true
    }
    var act = num(p.activity) || 0
    if (act >= e.activity) {
      e.activity = act
      e.branch = str(p.branch, 80)
    }
  }
  var out = []
  for (var j = 0; j < order.length; j++) if (byName[order[j]].url) out.push(byName[order[j]])
  return out
}

// Every box's rows, most recent first; ties by name, then box.
function recent(rowsByBox) {
  var all = []
  for (var box in rowsByBox) {
    var rows = rowsByBox[box] || []
    for (var i = 0; i < rows.length; i++) all.push(rows[i])
  }
  all.sort(function(a, b) {
    if (b.activity !== a.activity) return b.activity - a.activity
    if (a.name !== b.name) return a.name < b.name ? -1 : 1
    return a.box < b.box ? -1 : a.box > b.box ? 1 : 0
  })
  return all
}

// Every word must appear in the name, box or branch. "nomad pi" finds nomad on pi.
function filter(rows, text) {
  var words = String(text || "").toLowerCase().split(/\s+/).filter(function(w) { return w })
  if (words.length === 0) return rows
  return rows.filter(function(r) {
    var hay = (r.name + " " + r.box + " " + r.branch).toLowerCase()
    for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) < 0) return false
    return true
  })
}

function ago(epoch, now) {
  if (!(epoch > 0)) return ""
  var d = Math.max(0, now - epoch)
  if (d < 60) return "now"
  if (d < 3600) return Math.floor(d / 60) + "m"
  if (d < 86400) return Math.floor(d / 3600) + "h"
  return Math.floor(d / 86400) + "d"
}

function counts(rowsByBox) {
  var parts = []
  var total = 0
  for (var i = 0; i < BOXES.length; i++) {
    var n = (rowsByBox[BOXES[i]] || []).length
    if (n) parts.push(BOXES[i] + " " + n)
    total += n
  }
  return { total: total, text: parts.join(" · ") }
}

// history.json (ginger-dev history.py) as two short series over the last WINDOW seconds,
// averaged into at most POINTS buckets so a chart never draws more than that.
function series(history, now) {
  var out = { cpu: [], mem: [], cores: null, memTotal: null }
  if (!history || typeof history !== "object" || history.v !== 1 || !Array.isArray(history.samples)) return out
  var cols = Array.isArray(history.cols) ? history.cols : ["t", "cpu", "mem"]
  var it = cols.indexOf("t"), ic = cols.indexOf("cpu"), im = cols.indexOf("mem")
  if (it < 0 || ic < 0 || im < 0) return out
  out.cores = num(history.cores)
  out.memTotal = num(history.memTotal)
  var from = now - WINDOW
  var rows = history.samples.filter(function(r) { return Array.isArray(r) && num(r[it]) !== null && r[it] >= from })
  var per = Math.max(1, Math.ceil(rows.length / POINTS))
  for (var i = 0; i < rows.length; i += per) {
    var c = 0, cn = 0, m = 0, mn = 0
    for (var j = i; j < Math.min(rows.length, i + per); j++) {
      if (num(rows[j][ic]) !== null) { c += rows[j][ic]; cn++ }
      if (num(rows[j][im]) !== null) { m += rows[j][im]; mn++ }
    }
    out.cpu.push(cn ? Math.max(0, Math.min(100, c / cn)) : null)
    out.mem.push(mn ? Math.max(0, Math.min(100, m / mn)) : null)
  }
  return out
}

// The compact form the panel keeps per box, and caches on disk between opens.
function boxRecord(box, status, history, fetched) {
  return { v: 1, box: box, fetched: fetched, projects: projectsFrom(box, status), history: series(history, fetched) }
}

function readCache(text) {
  try {
    var r = JSON.parse(String(text || ""))
    return r && r.v === 1 && Array.isArray(r.projects) && r.history ? r : null
  } catch (e) {
    return null
  }
}

function stale(record, now) {
  return !record || !(record.fetched > now - STALE)
}

function pct(v) {
  return v === null || v === undefined || v < 0 ? "–" : Math.round(v) + "%"
}

function subtitle(series, uptime) {
  var parts = []
  if (series && series.cores) parts.push(series.cores + " cores")
  if (series && series.memTotal) parts.push(Math.round(series.memTotal / 1073741824) + " GB")
  if (uptime > 0) parts.push("up " + (uptime >= 86400 ? Math.floor(uptime / 86400) + "d" : Math.floor(uptime / 3600) + "h"))
  return parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    BOXES: BOXES, STALE: STALE, WINDOW: WINDOW, POINTS: POINTS, MAX_BYTES: MAX_BYTES,
    boxUrl: boxUrl, projectsFrom: projectsFrom, recent: recent, filter: filter, ago: ago, counts: counts,
    series: series, boxRecord: boxRecord, readCache: readCache, stale: stale, pct: pct, subtitle: subtitle
  }
}
