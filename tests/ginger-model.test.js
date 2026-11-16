// node --test tests/*.test.js
const assert = require("node:assert/strict")
const { test } = require("node:test")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const file = path.join(__dirname, "../omarchy/.config/omarchy/plugins/ruttydm.ginger/Model.js")
const source = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "")
const sandbox = { module: { exports: {} } }
vm.runInNewContext(source, sandbox, { filename: file })
const M = sandbox.module.exports
const plain = x => JSON.parse(JSON.stringify(x))

const NOW = 1_800_000_000

const STATUS = {
  box: "rz",
  projects: [
    { name: "nomad", url: "https://nomad.rz.afai.cc", worktree_of: null, web_up: true, activity: NOW - 3600, branch: "main" },
    { name: "nomad-t3-abc", url: "https://nomad-t3-abc.rz.afai.cc", worktree_of: "nomad", activity: NOW - 60, branch: "feat/gin-1-x" },
    { name: "tools", url: "", worktree_of: null, activity: NOW },
    { name: "roost", url: "https://roost.rz.afai.cc/", worktree_of: null, web_up: false, activity: NOW - 7200, branch: "main" },
    { name: "evil", url: "javascript:alert(1)", worktree_of: null, activity: NOW },
    { name: "orphan-wt", url: "https://orphan-wt.rz.afai.cc", worktree_of: "gone", activity: NOW },
    null,
  ],
}

test("worktrees fold into their project, which takes the newest activity and its branch", () => {
  const rows = plain(M.projectsFrom("rz", STATUS))
  assert.deepEqual(rows.map(r => r.name), ["nomad", "roost"])
  assert.deepEqual(rows[0], {
    name: "nomad", box: "rz", url: "https://nomad.rz.afai.cc", up: true,
    activity: NOW - 60, branch: "feat/gin-1-x", worktrees: 1,
  })
  assert.equal(rows[1].url, "https://roost.rz.afai.cc")
})

test("recent puts the newest activity first across boxes; filter needs every word", () => {
  const rows = M.recent({
    rz: M.projectsFrom("rz", STATUS),
    pi: [{ name: "nomad", box: "pi", url: "https://nomad.pi.afai.cc", up: false, activity: NOW - 10, branch: "research/x", worktrees: 0 }],
  })
  assert.deepEqual(plain(rows).map(r => r.name + "@" + r.box), ["nomad@pi", "nomad@rz", "roost@rz"])
  assert.deepEqual(plain(M.filter(rows, "nomad rz")).map(r => r.box), ["rz"])
  assert.deepEqual(plain(M.filter(rows, "research")).map(r => r.box), ["pi"])
  assert.equal(M.filter(rows, "  ").length, 3)
})

test("history becomes two bounded series over the chart window", () => {
  const samples = []
  for (let t = NOW - 24 * 3600; t <= NOW; t += 120) samples.push([t, 10, 50, 0.1, 30, 40, null])
  samples.push([NOW, 200, null, 0, 0, 0, 0])
  const s = plain(M.series({ v: 1, cores: 12, memTotal: 64e9, cols: ["t", "cpu", "mem", "load", "disk", "temp", "swap"], samples }, NOW))
  assert.ok(s.cpu.length <= M.POINTS && s.cpu.length > 60)
  assert.equal(s.cores, 12)
  assert.ok(s.cpu.every(v => v === null || (v >= 0 && v <= 100)))
  assert.deepEqual(plain(M.series({ v: 2 }, NOW)), { cpu: [], mem: [], cores: null, memTotal: null })
})

test("cache records round-trip and go stale after two minutes", () => {
  const rec = M.boxRecord("rz", STATUS, null, NOW)
  assert.deepEqual(plain(M.readCache(JSON.stringify(rec))), plain(rec))
  assert.equal(M.readCache("{"), null)
  assert.equal(M.stale(rec, NOW + 60), false)
  assert.equal(M.stale(rec, NOW + M.STALE + 1), true)
  assert.equal(M.stale(null, NOW), true)
})

test("labels", () => {
  assert.equal(M.ago(NOW - 30, NOW), "now")
  assert.equal(M.ago(NOW - 300, NOW), "5m")
  assert.equal(M.ago(NOW - 7300, NOW), "2h")
  assert.equal(M.ago(NOW - 3 * 86400, NOW), "3d")
  assert.equal(M.ago(0, NOW), "")
  assert.equal(M.pct(-1), "–")
  assert.equal(M.pct(42.6), "43%")
  assert.equal(M.subtitle({ cores: 12, memTotal: 64 * 1073741824 }, 3 * 86400), "12 cores · 64 GB · up 3d")
  assert.equal(M.boxUrl("rz"), "https://rz.afai.cc")
  assert.equal(M.boxUrl("x/../y"), "")
  assert.deepEqual(plain(M.counts({ rz: [1, 2], pi: [1] })), { total: 3, text: "rz 2 · pi 1" })
})
