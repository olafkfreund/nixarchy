// checks.menu-guards: judge the menu's guards with the menu's own code (#1301).
// usage: node menu-guards.js <tree> <upstream-menu.jsonc> <basePATH> <workdir> <bash>
"use strict"
const fs = require("fs")
const path = require("path")
const { spawnSync } = require("child_process")

// bash by absolute path: a bare "bash" resolves through node's own PATH. stdin
// is never a socket: bash sources /etc/bashrc when it is, which resets PATH.
const [tree, upstreamMenu, basePath, work, bash] = process.argv.slice(2)
const M = require(path.join(tree, "shell/plugins/menu/MenuModel.js"))
const PKG = /\bomarchy-pkg-(present|missing)\b/
const failures = []
const fail = (msg) => failures.push(msg)

const load = (file) => M.mergeMenuSources(M.parseMenuJsonc(fs.readFileSync(file, "utf8")), [])
const menu = load(path.join(tree, "default/omarchy/omarchy-menu.jsonc"))
const rows = menu.items
const ids = Object.keys(rows)
// normalizeItem keeps only the keys MenuModel.js knows, so `disabled` is read
// from the raw file: an unpatched model would drop it and the check must say so.
const raw = JSON.parse(M.stripJsonc(fs.readFileSync(path.join(tree, "default/omarchy/omarchy-menu.jsonc"), "utf8")))

// Every name a guard asks about, from both menus.
const names = new Set()
for (const src of [raw, JSON.parse(M.stripJsonc(fs.readFileSync(upstreamMenu, "utf8")))]) {
  for (const row of Object.values(src)) {
    for (const f of ["when", "checked", "disabled"]) {
      const s = String((row && row[f]) || "")
      for (const m of s.matchAll(/omarchy-pkg-(?:present|missing)((?:\s+[A-Za-z0-9._@+-]+)+)/g))
        for (const n of m[1].trim().split(/\s+/)) {
          names.add(n)
          names.add(n.replace(/-bin$/, "").replace(/-stable$/, ""))
        }
      for (const m of s.matchAll(/command -v\s+([A-Za-z0-9._@+-]+)/g)) names.add(m[1])
    }
  }
}

function world(name, present) {
  const dir = path.join(work, name)
  const bin = path.join(dir, "bin")
  const home = path.join(dir, "home")
  fs.mkdirSync(bin, { recursive: true })
  fs.mkdirSync(path.join(home, ".config/nixarchy"), { recursive: true })
  fs.writeFileSync(path.join(home, ".config/nixarchy/apps.nix"), "{ }\n")
  if (present) for (const n of names) fs.writeFileSync(path.join(bin, n), "#!/bin/sh\nexit 0\n", { mode: 0o755 })
  const env = { PATH: bin + ":" + basePath, HOME: home }
  const script = M.guardScript(rows)
  const r = spawnSync(bash, ["--noprofile", "--norc", "-c", script], { env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] })
  if (r.status !== 0) fail(`${name}: guard batch exited ${r.status}: ${r.stderr}`)
  const res = { w: {}, c: {}, d: {} }
  for (const line of r.stdout.split("\n")) {
    const m = line.trim().match(/^(.*):([wcd]):([01])$/)
    if (m) res[m[2]][m[1]] = m[3] === "1"
  }
  const visible = (id) => M.isVisible(rows, menu.itemOrder, res.w, rows[id])
  const dim = (id) => {
    if (typeof M.isDisabled !== "function")
      throw new Error(`MenuModel.isDisabled is not a function: this menu cannot dim ${id}`)
    return M.isDisabled(res.d, rows[id])
  }
  return { env, visible, dim }
}

const absent = world("absent", false)
const present = world("present", true)

const install = ids.filter((id) => id.startsWith("install.") && raw[id])
const withDisabled = install.filter((id) => raw[id].disabled)
const counts = {}
const count = (k) => (counts[k] = (counts[k] || 0) + 1)

for (const id of withDisabled) {
  const d = String(raw[id].disabled)
  if (raw[id].when && PKG.test(raw[id].when))
    fail(`${id}: has disabled and a package-guard when (${raw[id].when}), so an installed app is hidden instead of dimmed`)
  if (!raw[id].when) {
    count("disabled-no-when")
    if (!absent.visible(id)) fail(`${id}: hidden in absent`)
    if (!present.visible(id)) fail(`${id}: hidden in present, where it should be dim`)
  }
  if (d === "true") {
    count("unavailable")
    if (!absent.dim(id) || !present.dim(id)) fail(`${id}: "Not available" row is selectable`)
  } else if (/command -v|omarchy-pkg-/.test(d)) {
    count("dims-on-path")
    if (absent.dim(id)) fail(`${id}: dim with nothing installed`)
    if (!present.dim(id)) fail(`${id}: not dim with its command installed`)
  }
}

for (const id of install) {
  const r = raw[id]
  const inWhen = PKG.test(String(r.when || ""))
  const inDisabled = PKG.test(String(r.disabled || ""))
  if (!inWhen && !inDisabled) continue
  count("package-guarded")
  if (!absent.visible(id) || (inDisabled && absent.dim(id))) fail(`${id}: not offered with nothing installed`)
  if (inWhen && present.visible(id)) fail(`${id}: visible with its package present (${r.when})`)
  if (inDisabled && !present.dim(id)) fail(`${id}: not dim with its package present (${r.disabled})`)
}

const upRaw = JSON.parse(M.stripJsonc(fs.readFileSync(upstreamMenu, "utf8")))
for (const id of Object.keys(upRaw)) {
  if (!id.startsWith("remove.") || !PKG.test(String(upRaw[id].when || ""))) continue
  count("upstream-guarded-remove")
  if (!raw[id]) { fail(`${id}: upstream's remove row is missing from the generated menu`); continue }
  // A row nixarchy ported has its own action or its own `when` (a "false" is the
  // generator's hide, not a port); #1304 owns those.
  const when = String(raw[id].when || "")
  if (raw[id].action !== upRaw[id].action) continue
  if (when !== String(upRaw[id].when || "") && when !== "false") continue
  count("unported-remove")
  if (present.visible(id)) fail(`${id}: visible with its package present, and still runs upstream's ${upRaw[id].action}`)
}

// The in-shell helper and the shipped command must give the same answer.
const helper = path.join(tree, "bin/omarchy-pkg-present")
const sample = [...names]
for (const [wn, w] of [["absent", absent], ["present", present]]) {
  // The whole batch, not a cut of it: edge runs each guard inside a group.
  const probe = M.guardScript({ probe: { id: "probe", when: 'omarchy-pkg-present "$1"' } })
  for (const n of sample.concat(sample.map((s) => s + "-bin"), sample.map((s) => s + "-stable"))) {
    const out = spawnSync(bash, ["--noprofile", "--norc", "-c", probe, "x", n], { env: w.env, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).stdout
    if (!/^probe:w:[01]$/m.test(out)) { fail(`${wn}: the guard batch gave no answer for ${n}`); continue }
    const inShell = /^probe:w:1$/m.test(out) ? 0 : 1
    const shipped = spawnSync(helper, [n], { env: w.env, stdio: "ignore" }).status
    count("helper-agreement")
    if ((inShell === 0) !== (shipped === 0)) fail(`${wn}: omarchy-pkg-present ${n}: the menu says ${inShell === 0}, bin/omarchy-pkg-present says ${shipped === 0}`)
  }
}

// package-guarded is 0: on stable the only such rows (hermes, perplexity) are
// hidden by #1304; edge still has three.
const floors = { "disabled-no-when": 30, unavailable: 3, "dims-on-path": 40, "package-guarded": 0, "upstream-guarded-remove": 1, "unported-remove": 0, "helper-agreement": 60 }
for (const [k, min] of Object.entries(floors))
  if ((counts[k] || 0) < min) fail(`only ${counts[k] || 0} ${k} cases, expected at least ${min}: the menu changed shape or this check stopped reading it`)

console.log(JSON.stringify(counts))
if (failures.length) {
  console.error(failures.length + " failure(s):\n" + failures.join("\n"))
  process.exit(1)
}
console.log("menu guards answer what is installed, through the menu's own model")
