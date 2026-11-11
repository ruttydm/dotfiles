// node --test tests/  (or: bun test tests/)
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
})
