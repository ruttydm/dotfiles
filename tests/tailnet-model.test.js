// node --test tests/*.test.js  (or: bun test tests/)
const assert = require("node:assert/strict")
const { test } = require("node:test")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const file = path.join(__dirname, "../omarchy/.config/omarchy/plugins/ruttydm.tailnet/Model.js")
const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "")
const sandbox = { module: { exports: {} } }
vm.runInNewContext(source, sandbox, { filename: file })
const M = sandbox.module.exports
// Values from the vm realm have foreign prototypes; compare plain copies.
const plain = x => JSON.parse(JSON.stringify(x))

test("cpu percent from two /proc/stat samples", () => {
  const a = M.cpuTimes("cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 1\n")
  const b = M.cpuTimes("cpu  200 0 200 1400 0 0 0 0 0 0\n")
  assert.deepEqual(plain(a), { total: 1000, idle: 800 })
  assert.equal(M.cpuPercent(a, b), 25)
  assert.equal(M.cpuPercent(null, b), -1)
  assert.equal(M.cpuTimes("garbage"), null)
})

test("memory and bar label", () => {
  const mem = M.memory("MemTotal:  1048576 kB\nMemFree: 1 kB\nMemAvailable:  262144 kB\n")
  assert.deepEqual(plain(mem), { total: 1073741824, used: 805306368 })
  assert.equal(M.barText(7, mem), "   7%  \u{F061A}  75%")
  assert.equal(M.barText(-1, null), "   –%  \u{F061A}   –%")
})

const raw = {
  v: 1, updated: 1000, devices: [
    { id: "a", name: "pi", host: "rutty", os: "linux", online: true, group: "dev", url: "https://pi.example.cc",
      stats: { cpu: 87.4, cores: 4, load: [3.9, 2, 1], memTotal: 8e9, memAvailable: 2e9, diskTotal: 100, diskUsed: 44,
               tempC: 52.4, uptime: 3 * 86400 } },
    { id: "b", name: "mac", host: "mac", os: "macos", online: false, lastSeen: 1e6 - 2 * 86400, group: "other" },
    { id: "c", name: "tp", os: "linux", online: true, self: true, group: "dev", url: "https://tp.example.cc",
      stats: { cpu: 5, memTotal: 16e9, memAvailable: 8e9, load: [] } },
    { id: "d", name: "evil<img src=x>", online: true, group: "nope", url: "javascript:alert(1)", stats: { cpu: "x" } },
    { id: "e", name: "srv", online: true, group: "server", url: "https://srv.example.cc", error: "timed out" },
  ],
}

test("parse validates and bounds collector output", () => {
  const data = M.parse(JSON.stringify(raw))
  const evil = data.devices.find(d => d.id === "d")
  assert.equal(evil.url, "")          // only https://host URLs survive
  assert.equal(evil.group, "other")
  assert.equal(evil.stats, null)
  assert.equal(data.devices[0].stats.cpu, 87)
  assert.equal(data.devices[0].stats.memUsed, 6e9)
  assert.throws(() => M.parse("{}"))
  assert.throws(() => M.parse("not json"))
})

test("grouping, order and keyboard index", () => {
  const groups = M.grouped(M.parse(JSON.stringify(raw)).devices)
  assert.deepEqual(plain(groups.map(g => g.title)), ["Servers", "Dev boxes", "Other devices"])
  assert.deepEqual(plain(M.flat(groups).map(d => d.index)), [0, 1, 2, 3, 4])
  assert.deepEqual(plain(M.flat(groups).map(d => d.id)), ["e", "a", "c", "b", "d"])
})

test("row wording", () => {
  const ds = M.parse(JSON.stringify(raw)).devices
  const by = id => ds.find(d => d.id === id)
  assert.equal(M.detail(by("a"), 1000), "load 3.90 · disk 44% · 52°C · up 3d")
  assert.equal(M.detail(by("b"), 1e6), "offline · seen 2 d ago")
  assert.equal(M.detail(by("e"), 1000), "online · timed out")
  assert.equal(M.subtitle(by("c")), "this machine")
  assert.equal(M.subtitle(by("b")), "macOS")
  assert.equal(M.memLabel(by("a").stats), "5.6 / 7.5 GiB")
  assert.equal(M.activateHint(by("a")), "Open pi.example.cc")
  assert.equal(M.activateHint(by("c")), "Open btop")
  assert.equal(M.canActivate(by("b")), false)
  assert.equal(M.metricUrl(by("a"), "cpu"), "https://pi.example.cc/#cpu")
  assert.equal(M.metricUrl(by("a"), "evil"), "")
  assert.equal(M.metricUrl(by("b"), "mem"), "")
})

// ---------------------------------------------------------------- fleet and agents

const GiB = 1073741824
const fleetRaw = {
  v: 1, updated: 2000, devices: [
    { id: "tp", name: "tp", online: true, self: true, group: "dev", url: "https://tp.example.cc",
      t3Url: "https://t3.tp.example.cc",
      stats: { cpu: 5, memTotal: 16 * GiB, memAvailable: 8 * GiB, load: [0.2], diskTotal: 100, diskUsed: 50,
               agents: { working: 0, waiting: 0, done: 0 }, ciFailing: 0 } },
    { id: "rz", name: "rz", online: true, group: "dev", url: "https://rz.example.cc", t3Url: "https://t3.rz.example.cc",
      stats: { cpu: 88, memTotal: 64 * GiB, memAvailable: 2 * GiB, load: [9.8], diskTotal: 100, diskUsed: 93,
               swapTotal: 16 * GiB, swapFree: 0.25 * GiB, tempC: 71, uptime: 86400,
               agents: { working: 3, waiting: 1, done: 2 }, ciFailing: 1 } },
    { id: "pi", name: "pi", online: false, group: "dev", url: "https://pi.example.cc", lastSeen: 2000 - 240 },
    { id: "quiet", name: "qb", online: true, group: "dev", url: "https://qb.example.cc",
      stats: { cpu: 1, memTotal: 8 * GiB, memAvailable: 7 * GiB, load: [], agents: { working: 0, waiting: 0, done: 0 } } },
    { id: "dark", name: "db", online: true, group: "dev", url: "https://db.example.cc", error: "timed out" },
    { id: "mac", name: "mac", online: false, group: "other", lastSeen: 10 },
  ],
}
const fleet = () => M.parse(JSON.stringify(fleetRaw)).devices
const byId = id => fleet().find(d => d.id === id)

test("agents, swap and t3 survive parsing, bounded", () => {
  const rz = byId("rz")
  assert.deepEqual(plain(rz.stats.agents), { working: 3, waiting: 1, done: 2 })
  assert.equal(rz.stats.ciFailing, 1)
  assert.equal(rz.stats.swapUsed, 15.75 * GiB)
  assert.equal(rz.t3Url, "https://t3.rz.example.cc")
  const bad = M.parse(JSON.stringify({ v: 1, devices: [{ name: "x", online: true, t3Url: "https://evil.example",
    stats: { cpu: 1, memTotal: 1, memAvailable: 1, agents: { working: -4, waiting: "9", done: 2.7 },
             ciFailing: true, swapTotal: 10, swapFree: 99 } }] })).devices[0]
  assert.equal(bad.t3Url, "")
  assert.deepEqual(plain(bad.stats.agents), { working: 0, waiting: 0, done: 2 })
  assert.equal(bad.stats.ciFailing, 0)
  assert.equal(bad.stats.swapUsed, 0)
  assert.equal(byId("quiet").stats.swapTotal, 0)
  assert.equal(byId("dark").stats, null)
})

test("problems: offline fleet box, disk, swap and memory limits", () => {
  assert.deepEqual(plain(M.problems(byId("rz"))), ["disk 93%", "swap 98%", "mem 97%"])
  assert.deepEqual(plain(M.problems(byId("pi"))), ["off"])
  assert.deepEqual(plain(M.problems(byId("mac"))), [])      // other devices may sleep
  assert.deepEqual(plain(M.problems(byId("tp"))), [])
  assert.deepEqual(plain(M.problems(byId("dark"))), [])     // unreachable stats are not urgent
  assert.equal(M.urgentCount(fleet()), 2)
})

test("bar segments: one coloured name per fleet box, details left to the tooltip", () => {
  const segs = plain(M.barSegments(23, { total: 100, used: 41 }, fleet()))
  assert.equal(M.segmentsText(segs), M.barText(23, { total: 100, used: 41 }) + "  rz" + M.WAIT_ICON + " pi qb db")
  assert.deepEqual(segs.slice(1).map(s => [s.text, s.role]),
    [["  ", "fg"], ["rz", "urgent"], [M.WAIT_ICON, "accent"], [" ", "fg"], ["pi", "urgent"],
     [" ", "fg"], ["qb", "dim"], [" ", "fg"], ["db", "dim"]])
  // tp stays off the bar while it has nothing to flag; a waiting agent puts it on
  const busy = fleet()
  busy[0].stats.agents.working = 1
  assert.equal(M.pills(busy)[0].name, "rz")
  busy[0].stats.agents.waiting = 1
  assert.equal(M.pills(busy)[0].name, "tp")
  assert.equal(M.segmentsText(M.barSegments(-1, null, [])), M.barText(-1, null))
})

test("calm box with agents working is bold, waiting adds one mark", () => {
  const ds = fleet()
  const rz = ds.find(d => d.id === "rz")
  rz.stats.diskUsed = 40; rz.stats.swapUsed = 0; rz.stats.memUsed = GiB
  assert.deepEqual(plain(M.barSegments(1, null, [rz])).slice(1).map(s => [s.text, s.role]),
    [["  ", "fg"], ["rz", "bold"], [M.WAIT_ICON, "accent"]])
  rz.stats.agents.waiting = 0
  assert.deepEqual(plain(M.barSegments(1, null, [rz])).slice(1).map(s => [s.text, s.role]),
    [["  ", "fg"], ["rz", "bold"]])
})

test("problem summary, agents line and tooltip", () => {
  const ds = fleet()
  assert.equal(M.problemSummary(ds, 2000), "rz disk 93%, swap 98%, mem 97% · pi offline since 4 min · 1 PR failing")
  assert.equal(M.agentsLine(byId("rz")), "3 working · 1 waiting · 2 done · 1 PR failing")
  assert.equal(M.agentsLine(byId("tp")), "no agents running")
  assert.equal(M.agentsLine(byId("dark")), "")
  assert.equal(M.agentsLine(byId("pi")), "")
  const tip = M.fleetTooltip(23, { total: 100 * GiB, used: 41 * GiB }, ds, 2000)
  assert.match(tip, /^CPU 23%\nMemory 41\.0 \/ 100 GiB\n\nrz disk 93%/)
  assert.match(tip, /\nAgents\nrz: 3 working · 1 waiting · 2 done · 1 PR failing\n/)
  assert.doesNotMatch(tip, /tp:/)
})

test("styled rows escape names and colour only what breaks a limit", () => {
  const colors = { dim: "#6d7f72", accent: "#0f6e66", urgent: "#a33b4a" }
  const rz = byId("rz")
  assert.equal(M.detailHtml(rz, 2000, colors),
    'load 9.80 · disk <font color="#a33b4a">93%</font> · 71°C · up 24h')
  assert.equal(M.detailHtml(byId("pi"), 2000, colors), '<font color="#a33b4a">offline · seen 4 min ago</font>')
  assert.equal(M.detailHtml(byId("mac"), 2000, colors), "offline · seen 33 min ago")
  const html = M.agentsHtml(rz, colors)
  assert.match(html, /<b><font color="#0f6e66">1\S+ waiting<\/font><\/b>/)
  assert.match(html, /<font color="#a33b4a">✗1 PR failing<\/font>/)
  assert.match(html, /↗ t3<\/font>$/)
  assert.equal(M.agentsHtml(byId("dark"), colors), "")
  const evil = { online: false, name: "x", group: "dev", lastSeen: 0 }
  assert.equal(M.escapeHtml('<b a="1">&'), "&lt;b a=&quot;1&quot;&gt;&amp;")
  assert.equal(M.detailHtml(evil, 0, { urgent: '"><script>' }), '<font color="&quot;&gt;&lt;script&gt;">offline</font>')
  assert.equal(M.swapLabel(rz.stats), "15.8 / 16.0 GiB")
})
