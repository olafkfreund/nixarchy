# The history rules in the notifications plugin's Store.js, run under node
# against the shipped (patched) package. See #1663.
{ pkgs, ... }:
let
  script = pkgs.writeText "notification-store-check.js" ''
    // Loads the notifications plugin's .pragma library files into node and checks
    // the history rules in Store.js. Usage: node check.js <plugin dir>
    const fs = require("fs"), vm = require("vm"), path = require("path"), assert = require("assert");
    const dir = process.argv[2], cache = {};
    function load(name) {
      if (cache[name]) return cache[name];
      const src = fs.readFileSync(path.join(dir, name), "utf8"), ctx = { console: console };
      const body = src.split("\n").map(function (l) {
        const m = l.match(/^\.import "(.+)\.js" as (\w+)/);
        if (m) { ctx[m[2]] = load(m[1] + ".js"); return ""; }
        return l.startsWith(".pragma") ? "" : l;
      }).join("\n");
      vm.createContext(ctx); vm.runInContext(body, ctx);
      return (cache[name] = ctx);
    }
    const S = load("Store.js"), now = 2000000000, H = 3600;
    const FIELDS = ["summary", "body", "rawBody", "execArgv", "execActions"];
    const ACTIONS = JSON.stringify([{ label: "Open", argv: ["xdg-open", "https://x"] }]);
    // Newest-first by closing; arrival (ts) runs the other way, so sorting by ts would fail.
    function row(key, age) {
      return { key: key, app: "chat", summary: "sum " + key, body: "body " + key, rawBody: "<b>body " + key + "</b>",
        execArgv: JSON.stringify(["xdg-open", "https://x"]), execActions: ACTIONS,
        ts: now - 3 * H + age, closed_ts: now - age, closed_reason: "closed" };
    }
    const keys = function (a) { return a.map(function (e) { return e.key; }).join(" "); };
    const text = function (e) { return FIELDS.every(function (f) { return !!e[f]; }); };

    // 1. Migration of a pre-change file.
    const rows = [];
    for (let i = 0; i < 10; i++) rows.push(row("h" + i, i * 60));
    rows[7] = Object.assign(row("hr", 420), { summary: "Your code is 123456", body: "Your verification code is 123456" });
    rows[8].key = "h7"; rows[9].key = "h8";
    rows.push(row("hs", 25 * H));
    const h = S.retain(S.parseHistory(JSON.stringify(rows)), now);
    assert.strictEqual(keys(h), "h0 h1 h2 h3 h4 h5 h6 hr h7 h8", "1: key sequence");
    for (let i = 0; i < 10; i++) {
      const e = h[i], src = rows.filter(function (r) { return r.key === e.key; })[0];
      if (e.key === "hr") {
        assert.ok(e.summary === "Verification notification" && e.body === "[redacted]" && e.groupKey === "", "1: hr placeholder");
      } else if (i < 6) {
        FIELDS.forEach(function (f) { assert.strictEqual(e[f], src[f], "1: " + e.key + " keeps " + f); });
      } else {
        FIELDS.forEach(function (f) { assert.strictEqual(e[f], "", "1: " + e.key + " loses " + f); });
      }
      ["key", "app", "ts", "closed_ts", "closed_reason"].forEach(function (f) {
        if (e.key !== "hr") assert.strictEqual(e[f], src[f], "1: " + e.key + " keeps " + f);
      });
    }

    // 2. Boundaries: exactly 24h old goes, one second younger stays.
    const edge = S.retain(S.parseHistory(JSON.stringify([row("a", 0), row("b", 24 * H - 1), row("c", 24 * H)])), now);
    assert.strictEqual(keys(edge), "a b", "2: 24h boundary");

    // 3. Running it twice changes nothing, redacted row included.
    const again = S.retain(S.parseHistory(S.serialise(h)), now);
    assert.strictEqual(S.serialise(again), S.serialise(h), "3: idempotent");

    // 4. The text window moves when a row is added.
    const h2 = S.addHistory(h, S.closedEntry(row("hn", 0), "closed", now), now);
    assert.strictEqual(keys(h2), "hn h0 h1 h2 h3 h4 h5 h6 hr h7 h8", "4: key sequence");
    ["hn", "h0", "h1", "h2", "h3", "h4"].forEach(function (k, i) { assert.ok(text(h2[i]), "4: " + k + " has text"); });
    assert.ok(!h2[6].summary && !h2[6].body, "4: h5 lost its text");

    // 5. parseLive drops rows older than 24h; with now omitted it uses the clock.
    const aged = function (key, age) { return Object.assign(row(key, 0), { ts: now - age }); };
    const live = S.parseLive(JSON.stringify([aged("l1", 60), aged("l2", 25 * H)]), now);
    assert.strictEqual(keys(live), "l1", "5: live age");
    const clock = Date.now() / 1000;
    assert.strictEqual(S.parseLive(JSON.stringify([Object.assign(row("l3", 0), { ts: clock - 30 * H })])).length, 0, "5: default now uses the clock");
    assert.strictEqual(S.parseLive(JSON.stringify([Object.assign(row("l4", 0), { ts: clock - 60 })])).length, 1, "5: default clock keeps a fresh row");

    // The replay shows exactly the rows that have text.
    const svc = fs.readFileSync(path.join(dir, "Service.qml"), "utf8");
    assert.ok(svc.includes("readonly property int replayCount: Store.HISTORY_TEXT_ROWS"), "Service.qml replayCount reads Store.HISTORY_TEXT_ROWS");
    console.log("ok: notification history checks pass");
  '';
in
pkgs.runCommand "nixarchy-notification-store" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
  node ${script} ${pkgs.omarchy}/share/omarchy/shell/plugins/notifications
  touch $out
''
