// #1305: a partial override in the user's omarchy-menu.jsonc keeps the rest
// of the row. Runs the BUILT MenuModel.js the way Menu.qml does: parse both
// files, then merge the user's over the defaults. Exit 1 is a failed case;
// exit 2 is the probe unable to run, never a result.
const path = process.argv[2]
let M
try { M = require(path) } catch (e) { console.log("cannot load " + path + ": " + e.message); process.exit(2) }
if (typeof M.parseMenuJsonc !== "function" || typeof M.mergeMenuSources !== "function") {
  console.log("MenuModel.js no longer exports parseMenuJsonc and mergeMenuSources"); process.exit(2)
}
const defaults = M.parseMenuJsonc('{"system":{"label":"System"},' +
  '"system.shutdown":{"icon":"P","label":"Shutdown","action":"systemctl poweroff","when":"true"},' +
  '"system.sub":{"label":"Sub"}}')
let bad = 0
function merged(user) { return M.mergeMenuSources(defaults, M.parseMenuJsonc(user)).items }
function check(name, user, want) {
  const items = merged(user)
  let ok = true
  for (const [id, fields] of Object.entries(want)) {
    if (!items[id]) { ok = false; console.log(`FAIL ${name}: ${id} is missing from the merged menu`); continue }
    for (const [k, v] of Object.entries(fields)) {
      if (items[id][k] !== v) { ok = false; console.log(`FAIL ${name}: ${id}.${k} is ${JSON.stringify(items[id][k])}, want ${JSON.stringify(v)}`) }
    }
  }
  if (ok) console.log("PASS " + name); else bad++
}
check("label-only override", '{"system.shutdown":{"label":"Power off"}}',
  { "system.shutdown": { kind: "action", action: "systemctl poweroff", when: "true", icon: "P", label: "Power off" } })
check("action-only override makes a menu an action", '{"system.sub":{"action":"x"}}',
  { "system.sub": { kind: "action", action: "x", label: "Sub" } })
check("stated empty when clears it", '{"system.shutdown":{"when":""}}',
  { "system.shutdown": { when: "", action: "systemctl poweroff" } })
check("stated empty action makes it a submenu", '{"system.shutdown":{"action":""}}',
  { "system.shutdown": { kind: "menu", action: "", label: "Shutdown" } })
check("target-only override makes it a link", '{"system.sub":{"target":"system"}}',
  { "system.sub": { kind: "link", target: "system", label: "Sub" } })
check("an unknown key is not copied", '{"system.shutdown":{"label":"Off","$comment":"x"}}',
  { "system.shutdown": { action: "systemctl poweroff" } })
{
  const row = merged('{"system.shutdown":{"label":"Off","$comment":"x"}}')["system.shutdown"]
  if ("$comment" in row || "statedKeys" in row) { bad++; console.log("FAIL a stray key survived the merge: " + Object.keys(row).join(",")) }
  else console.log("PASS no stray key survives the merge")
}
check("new row is normalised", '{"mine":{"label":"Mine","action":"y"}}',
  { "mine": { kind: "action", parent: "root", icon: "" } })
process.exit(bad ? 1 : 0)
