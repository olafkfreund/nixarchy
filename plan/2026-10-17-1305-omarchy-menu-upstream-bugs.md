---
status: approved
issue: 1305
spec: spec/2026-10-17-1305-omarchy-menu-upstream-bugs.md
---

# Plan: Carry three of the Omarchy menu's bugs, and draft reports for six

## What is decided (from the approved spec, 9edee1a5)

You should not need the intent or the spec. File and line references are to
`origin/main` 7e0ceac5 unless a step says otherwise. Omarchy's menu lives in
the built package at `share/omarchy/shell/plugins/menu/{Menu.qml,MenuModel.js}`.
nixarchy patches it in `pkgs/omarchy/default.nix`'s `installPhase`.

Spec decisions, in substance:

1. **Bug 1, carry (stable and edge).** In the menu, the Right arrow shares
   Enter's branch, so on an action row it runs the action (Shutdown is
   Super+Escape, Up, Right). In a select or input prompt it picks the row or
   submits the half-typed text. After the fix, Right opens a submenu or
   follows a link, and is otherwise left unhandled. Enter is unchanged.
   `rightEnters()` is true only with no prompt open, the cursor active, and a
   `menu` or `link` row under it.
2. **Bug 2, carry (stable and edge).** A select or input request displaced by
   the next open hangs its caller for ever: `openDmenu` and
   `openExistingMenu` drop the pending `doneFile` without writing it. After
   the fix, both first call `releaseDisplacedRequest()`, which writes the
   pending `doneFile` empty with
   `Quickshell.execDetached(["sh", "-c", ": > \"$1\"", "sh", root.doneFile])`.
   The path goes in as an argument, with no login shell and not through
   `resultProc`. The caller (`omarchy-menu-select`, `omarchy-menu-input`) then
   exits 1, as for Escape. `omarchy-menu-images` is NOT covered: it waits on
   `omarchy-shell image-selector`. Drop the carry when a shipped release
   contains upstream PR #9031.
3. **Bug 3, carry (stable and edge).** A partial override in
   `~/.config/omarchy/extensions/omarchy-menu.jsonc` blanks the row:
   `normalizeItem` fills every key before `mergeMenuSources` copies all of
   them. After the fix:
   - `parseMenuJsonc` records `statedKeys`, the keys the file stated, filtered
     to keys `normalizeItem` returns.
   - `mergeMenuSources` copies only those keys onto an id an earlier source
     defined. It recomputes `kind` (`action` gives action, else `target`
     gives link, else menu) and deletes `statedKeys`.
   - A first definition is copied whole. `normalizeItem` is NOT touched,
     because #1301 changes it.
   - `modules/apps.nix`'s full-row merge stays; removing it is a follow-up.
4. **Bug 4 (inline `//`)**: report only.
5. **Bug 5 (early summon)**: leave it. Upstream issue #14053 and PR #15519
   are open.
6. **Bug 6 (`summon <alias>` ignores `when`)**: report only.
7. **Bug 7 (one shell for every guard)**: report only, low priority.
8. **Bug 8 (search ancestors)**: leave it; it is a feature request.
9. **Bugs 9 and 10 (PageUp, AltGr/IME)**: no carry. Edge already has the
   fixes; stable gets them at its first bump from quattro.
10. **Bug 11 (power-profiles provider not volatile)**: report only. No
    shipped row uses that provider.
11. **A human files upstream**, from the spec's appendix (drafts A-F, for
    bugs 1, 3, 4, 6, 7, 11). No agent posts to omacom/omarchy.
12. **#1301 lands first.** These substitutions go after every `patch` line.
13. **nixarchy-menu and nixi are out of scope.** A follow-up issue asks
    whether they should take the bug-3 fix.

How the carries are written (spec):
- `substituteInPlace --replace-fail`, never a `.patch`.
  `.github/scripts/omarchy-patched-files.sh` sees only `substituteInPlace`
  and `sed -i`.
- **Two new checks:**
  - `checks.menu-model-merge`: node over the BUILT `MenuModel.js`.
  - `checks.menu-keys`: the real `Menu.qml` in a headless Quickshell, against
    a fixture menu whose actions only touch markers.
- `pkgs/AGENTS.md` gets a section "The menu's own bugs (#1305)".
- No `data/bin-ledger.nix` row: the ledger covers `bin/`, and these are
  `shell/` files.
- No coexistence fixture: no option is set.
- The squash subject is the release note (`.github/scripts/release-notes.sh`
  derives section 4 from commit subjects), so it says that Right no longer
  runs rows and that partial overrides keep the rest of the row.

### Deviations from the spec, and why

- **Bug 1's mechanism.** The spec rewrote the branch condition to
  `(event.key === Qt.Key_Right && root.rightEnters())`. That line differs on
  quattro (`Util.readingKey(event) === Qt.Key_Right`), so the main
  substitution would fail every edge build from the moment main merged into
  edge. This plan inserts a guard as the branch's first statement instead.
  That anchor, `            if (root.dmenuActive) {`, occurs exactly once in
  both 4.0.4 and quattro:

      // Right opens a submenu or follows a link, and never runs a row (#1305).
      if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && !root.rightEnters()) return

  The behaviour is identical: Right reaches the branch's body only when
  `rightEnters()` is true, and otherwise the event goes unaccepted. Testing
  "not Enter" rather than "is Right" also covers quattro's right-to-left
  mapping, where the physical Left key arrives as Right through `readingKey`.
  Measured on 2026-10-17 (step 8 has the outputs). **Consequence:** edge
  needs no product carry for bug 1. Its edge step (step 14) carries only the
  test harness's window edit.
- **Replacement text lives in snippet files**,
  `pkgs/omarchy/1305-menu-*.js`, read with `"$(cat ${./…})"`. A multi-line
  argument inside the `installPhase` `''` string changes its minimal
  indentation, and nixfmt then re-flows the whole phase
  (`pkgs/omarchy/default.nix:1310-1313` says so). The anchors stay on one
  source line, joined with `$'\n'`.
- **The harness edits its copy of `Menu.qml` in `tests/menu-keys.sh`**, with
  a `replace_once` that dies if an anchor is not found exactly once. The spec
  said these were "substitutions"; they are, just in bash rather than in
  Nix, for the same indentation reason. The spec's two `displayModel`
  accessors were dropped: no case needed them.

## Deviations during implementation

- **Step 0: merged, not rebased.** After #1301 merged (89bdbf9b), the lead
  merged `origin/main` into this branch (4541adac). The branch then held only
  intent, spec and plan files, so the merge was clean.
- **Step 2: placed after #1301's lines.** The plan's `default.nix:2090` was
  the pre-#1301 position. The block now follows #1301's `substituteInPlace` of
  `MenuModel.js`, after `:2098`.
- **Step 4: snippet indentation.** The plan's listing did not show leading
  spaces exactly. The guard uses 12, to match `if (root.dmenuActive) {`; the
  other two use 2, to match the function anchors. Step 6's nine passing cases
  and step 8's breaks show the result is right.
- **Owner waived the local load gate (2026-10-17).** The lead checked the
  p620 build gate.

## Steps

0. **Branch base: wait for #1301, do not stack.** #1301's branch exists only
   locally (`/mnt/data/vmtest/wt-1301`, no code yet), so there is nothing to
   stack on. Implementation starts only after #1301's PR has squash-merged to
   `main`. Then, in `/mnt/data/vmtest/wt-1305`:

   ```bash
   git fetch origin
   git status --short            # must print nothing
   git rebase origin/main        # this branch holds only intent/, spec/, plan/ commits
   git merge-base origin/main HEAD   # must equal: git rev-parse origin/main
   git log --stat origin/main..HEAD  # must list only intent/, spec/ and plan/ files
   ```

   **§8 stacked-PR trap:** nothing is stacked, so #1301's squash cannot
   duplicate anything here. If the owner chooses to stack instead, then
   after #1301's squash, cherry-pick THIS branch's own commits onto the new
   `origin/main` (`git log --format=%h origin/main..HEAD -- intent spec plan pkgs tests flake.nix`),
   and never merge main into the branch. After either route, run
   `git show --stat` on each commit and check it lists only this task's files
   (CLAUDE.md §5's `pull`/`reset --soft` trap).
   Before starting, call `read_new` on `#nixarchy-agents` (§9) and note
   anything that bears on the menu in the PR body.
   Traps: read the status of every `fetch`/`rebase`, never `2>/dev/null` it.

1. **Re-read #1301's merged patch and the anchors.**
   - Find #1301's `patch -d "$out/share/omarchy" … 1301-menu-disabled.patch`
     line in `pkgs/omarchy/default.nix`. At 7e0ceac5 the last patch line is
     `:2090` (902-notification-sender-close.patch); #1301's should follow it.
     Write the real line number into this plan's deviations section if it
     differs.
   - Build the package (package tier). Every later "build the package" in
     this plan means exactly this block:

     ```bash
     n=$(pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620' || true); [ "$n" = 0 ] || { echo "p620 build running"; exit 1; }
     awk '{ if ($1 >= 12) { print "load " $1; exit 1 } }' /proc/loadavg
     drv=$(nix eval --raw .#packages.x86_64-linux.omarchy.drvPath)
     nix build "$drv^*" --out-link result-omarchy --print-build-logs
     ```

   - Count every anchor in the BUILT files. Each must print `1`:

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   m=result-omarchy/share/omarchy/shell/plugins/menu
   for a in '            if (root.dmenuActive) {' \
            '  function activateIndex(index, fromPointer) {' \
            '  function openExistingMenu(initialMenu) {' \
            '  function openDmenu(payload) {'; do
     printf '%s  %s\n' "$(grep -cF "$a" "$m/Menu.qml")" "$a"
   done
   for a in '    out.push(normalizeItem(id, entry))' \
            '      for (var k2 in entry) merged[k2] = entry[k2]'; do
     printf '%s  %s\n' "$(grep -cF "$a" "$m/MenuModel.js")" "$a"
   done
   grep -A1 -F '  function openExistingMenu(initialMenu) {' "$m/Menu.qml"
   grep -A1 -F '  function openDmenu(payload) {' "$m/Menu.qml"
   ```

   The two `grep -A1` lines must each show `    requestSerial += 1` next.
   **If any count is not 1, or #1301 changed a line these anchors name, stop
   and report.** Do not adapt an anchor silently.
   Traps: run it as a script (`#!/usr/bin/env bash`), not pasted into zsh
   (§1).

2. **Bug 3: `pkgs/omarchy/default.nix` and two snippet files.**
   - Create `pkgs/omarchy/1305-menu-stated-keys.js` with exactly:

     ```js
         var normalized = normalizeItem(id, entry)
         // The keys the file stated, so a later merge copies only those (#1305).
         normalized.statedKeys = Object.keys(entry).filter(function(k) { return k in normalized })
         out.push(normalized)
     ```

   - Create `pkgs/omarchy/1305-menu-merge-stated.js` with exactly:

     ```js
           // An override copies only what it stated; a first definition is copied whole (#1305).
           var keys = (nextItems[entry.id] && entry.statedKeys) ? entry.statedKeys : Object.keys(entry)
           for (var k2 = 0; k2 < keys.length; k2++) merged[keys[k2]] = entry[keys[k2]]
           merged.kind = merged.action ? "action" : (merged.target ? "link" : "menu")
           delete merged.statedKeys
     ```

   - In `pkgs/omarchy/default.nix`, after the last `patch -d` line (step 1;
     `:2090` at 7e0ceac5, or #1301's line after it) and before
     `# Wear the snowflake.`, add one blank line, then:

     ```nix
                    # The menu's own bugs, carried until omacom/omarchy fixes them (#1305).
                    # Why: pkgs/AGENTS.md#the-menus-own-bugs-1305
                    # Bug 3: an override in the user's menu file copies only the keys it states.
                    substituteInPlace $out/share/omarchy/shell/plugins/menu/MenuModel.js \
                      --replace-fail '    out.push(normalizeItem(id, entry))' "$(cat ${./1305-menu-stated-keys.js})" \
                      --replace-fail '      for (var k2 in entry) merged[k2] = entry[k2]' "$(cat ${./1305-menu-merge-stated.js})"
     ```

   - `git add pkgs/omarchy/1305-menu-stated-keys.js pkgs/omarchy/1305-menu-merge-stated.js`
   - Run `nix fmt`, then `git diff --stat`, which must show only
     `pkgs/omarchy/default.nix` (+6) and the two new files. If it shows
     hundreds of lines, a hook ran nixpkgs-fmt: `git checkout HEAD --
     pkgs/omarchy/default.nix`, redo the edit, run `nix fmt`.
   - Verify: build the package (step 1's block), then

     ```bash
     grep -c 'statedKeys' result-omarchy/share/omarchy/shell/plugins/menu/MenuModel.js   # expect 3
     ```

     The `kind` recompute also runs on a first definition. That is
     deliberate, and changes nothing: it is `normalizeItem`'s own rule
     (MenuModel.js:21, `value.action ? "action" : (value.target ? "link" :
     "menu")`), applied to the same values.

   Traps:
   - an untracked snippet "does not exist" to nix, so `git add` first;
   - no heredoc and no multi-line argument inside the `''` string;
   - `nix fmt` after the edit;
   - `$(cat …)` strips trailing newlines. That is intended: the anchor line's
     own newline stays.

3. **`checks.menu-model-merge`.**
   - Create `tests/menu-model-merge.js` (from the scratch
     `final/menu-model-merge.js`) with exactly:

     ```js
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
     ```

   - Create `tests/menu-model-merge.nix`:

     ```nix
     { pkgs, omarchy }:
     # #1305: a partial override in the user's omarchy-menu.jsonc keeps the rest
     # of the row. Node runs the BUILT MenuModel.js; tests/AGENTS.md has the why.
     pkgs.runCommand "nixarchy-menu-model-merge" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
       node ${./menu-model-merge.js} ${omarchy}/share/omarchy/shell/plugins/menu/MenuModel.js
       touch $out
     ''
     ```

   - In `flake.nix`, after the `menu-close = import ./tests/menu-close.nix { … };`
     block (`:2528-2533` at 7e0ceac5), add:

     ```nix

               # #1305: a partial override in the user's menu file keeps the rest of the row.
               menu-model-merge = import ./tests/menu-model-merge.nix {
                 pkgs = pkgsFor.${system};
                 omarchy = self.packages.${system}.omarchy;
               };
     ```

   - `git add tests/menu-model-merge.js tests/menu-model-merge.nix`, then
     `nix fmt`, then `git diff --stat`.
   - Verify (cheap tier, the package is already built):

     ```bash
     drv=$(nix eval --raw .#checks.x86_64-linux.menu-model-merge.drvPath)
     flock /mnt/data/vmtest/codex-build.lock nix build "$drv^*" --no-link --print-build-logs
     ```

     Expected: eight `PASS` lines and a successful build.
   Traps: `git add` before building, and no new workflow edit. "Build every
   check no other job claims" picks it up (§4).

4. **Bugs 1 and 2: `pkgs/omarchy/default.nix` and three snippet files.**
   - Create `pkgs/omarchy/1305-menu-right-guard.js`:

     ```js
                 // Right opens a submenu or follows a link, and never runs a row (#1305).
                 if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && !root.rightEnters()) return
     ```

   - Create `pkgs/omarchy/1305-menu-right-enters.js`:

     ```js
       // Right opens a submenu or follows a link, and never runs a row (#1305).
       function rightEnters() {
         if (root.dmenuActive || !root.cursorActive) return false
         if (root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return false
         var kind = displayModel.get(root.selectedIndex).kind
         return kind === "menu" || kind === "link"
       }
     ```

   - Create `pkgs/omarchy/1305-menu-release-displaced.js`:

     ```js
       // A request the next one displaces is cancelled, or its caller waits for ever (#1305).
       function releaseDisplacedRequest() {
         if (root.requestActive && root.doneFile)
           Quickshell.execDetached(["sh", "-c", ": > \"$1\"", "sh", root.doneFile])
       }
     ```

   - In `pkgs/omarchy/default.nix`, directly after step 2's block, add:

     ```nix
                    # Bug 1: Right opens a submenu or follows a link, and never runs a row.
                    substituteInPlace $out/share/omarchy/shell/plugins/menu/Menu.qml \
                      --replace-fail '            if (root.dmenuActive) {' "$(cat ${./1305-menu-right-guard.js})"$'\n'"            if (root.dmenuActive) {" \
                      --replace-fail '  function activateIndex(index, fromPointer) {' "$(cat ${./1305-menu-right-enters.js})"$'\n\n'"  function activateIndex(index, fromPointer) {"
                    # Bug 2: a request the next one displaces releases its caller.
                    substituteInPlace $out/share/omarchy/shell/plugins/menu/Menu.qml \
                      --replace-fail "  function openExistingMenu(initialMenu) {"$'\n'"    requestSerial += 1" "$(cat ${./1305-menu-release-displaced.js})"$'\n\n'"  function openExistingMenu(initialMenu) {"$'\n'"    root.releaseDisplacedRequest()"$'\n'"    requestSerial += 1" \
                      --replace-fail "  function openDmenu(payload) {"$'\n'"    requestSerial += 1" "  function openDmenu(payload) {"$'\n'"    root.releaseDisplacedRequest()"$'\n'"    requestSerial += 1"
     ```

   - `git add pkgs/omarchy/1305-menu-*.js`, then `nix fmt`, then
     `git diff --stat`.
   - Verify: build the package (step 1's block), then:

     ```bash
     m=result-omarchy/share/omarchy/shell/plugins/menu/Menu.qml
     grep -c 'rightEnters' "$m"                  # expect 2
     grep -c 'releaseDisplacedRequest' "$m"      # expect 3
     ```

     On 2026-10-17 this exact Nix text was parsed (`nix-instantiate
     --parse`), evaluated, and its shell run with a `substituteInPlace`
     stand-in against the deployed 4.0.4 files. The resulting Menu.qml was
     byte-identical to the measured fix, and MenuModel.js passed all eight
     cases. An earlier draft wrote `$'\n''…`, and Nix refused to parse it:
     `''` ends an indented string.
   Traps:
   - **never put a `'` right after `$'\n'`.** `$'\n''…` contains `''`, which
     ends the Nix indented string (a parse error). After `$'\n'` or
     `$'\n\n'`, the next segment is double-quoted, as written above;
   - `$'\n'` must stay outside the other quotes;
   - one source line per argument;
   - the snippet text holds `"$1"` inside `cat`'s output, never inside the
     Nix string, so no `''$` escaping is needed;
   - `nix fmt`, then `git diff --stat`.

5. **`checks.menu-keys` files.**
   - Create `tests/menu-keys-shell.qml` (from the scratch
     `final/menu-keys-shell.qml`):

     ```qml
     // #1305 harness: loads the real menu plugin into a headless Quickshell, sends
     // keys with QtTest, and answers over IPC. Only tests/menu-keys.sh uses it.
     import Quickshell
     import Quickshell.Io
     import QtQuick
     import QtTest
     ShellRoot {
       id: r
       property var menu: null
       property string loadError: ""
       TestCase { id: tc; when: false; name: "menu-keys" }
       Component.onCompleted: {
         var c = Qt.createComponent("plugins/menu/Menu.qml")
         if (c.status !== Component.Ready) { loadError = c.errorString(); console.log("menu-keys: " + loadError); return }
         menu = c.createObject(r)
       }
       IpcHandler {
         target: "probe"
         function state(): string {
           if (!r.menu) return JSON.stringify({ error: r.loadError || "menu not created" })
           return JSON.stringify({ opened: r.menu.opened, active: r.menu.activeMenu, rows: Object.keys(r.menu.items || {}).length })
         }
         function open(payload: string): string { return String(r.menu.open(payload)) }
         function key(k: int): string { tc.keyClick(k); return "sent" }
         function sel(i: int): string { r.menu.cursorActive = true; r.menu.selectedIndex = i; return "ok" }
         function nocursor(): string { r.menu.cursorActive = false; return "ok" }
       }
     }
     ```

   - Create `tests/menu-keys.sh` (from the scratch `final/menu-keys.sh`),
     then `chmod +x`:

     ```bash
     #!/usr/bin/env bash
     # shellcheck disable=SC2015 # pass and fail always succeed, so A && B || C is if-else here
     # #1305: the real Menu.qml in a headless Quickshell. Right must not run a row,
     # and a request displaced by the next one must release its caller.
     # Usage: menu-keys.sh <built share/omarchy> <harness shell.qml>
     # Needs on PATH: qs, bash, sh, perl, sed, coreutils. TEST_BASH is the stubs' shebang.
     set -uo pipefail

     tree=$1
     work=$PWD
     shell_dir=$work/shell
     marks=$work/marks
     mkdir -p "$marks" "$work/fake/default/omarchy" "$work/stub" "$work/home"
     export HOME=$work/home

     die() { echo "menu-keys: $*" >&2; cat "$work/qs.log" 2>/dev/null >&2; exit 2; }
     for tool in qs bash sh perl sed touch mktemp; do command -v "$tool" >/dev/null || die "$tool is not on PATH"; done
     [[ -x $tree/bin/omarchy-menu-select && -x $tree/bin/omarchy-menu-input ]] || die "the built menu scripts are missing under $tree/bin"

     # Replace text that must occur exactly once, or stop: a harness edit that
     # silently matched nothing would test the shipped window, not this one.
     replace_once() {
       local file=$1 anchor=$2 replacement=$3 text rest
       text=$(<"$file")
       rest=${text#*"$anchor"}
       [[ $rest != "$text" && $rest != *"$anchor"* ]] || die "harness anchor not found exactly once in $file: ${anchor%%$'\n'*}"
       printf '%s\n' "${text%%"$anchor"*}$replacement$rest" > "$file"
     }

     # The menu's own window is a Wayland layer surface, and offscreen Quickshell
     # has "No PanelWindow backend loaded". A plain window runs the same handler.
     cp -rL "$tree/shell" "$shell_dir"
     chmod -R u+w "$shell_dir"
     replace_once "$shell_dir/plugins/menu/Menu.qml" '  PanelWindow {
         id: panel
         visible: root.opened && root.rowsLoaded
         anchors { top: true; bottom: true; left: true; right: true }
         color: "transparent"
         WlrLayershell.namespace: "omarchy-menu"
         WlrLayershell.layer: WlrLayer.Overlay
         WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
         exclusionMode: ExclusionMode.Ignore' '  FloatingWindow {
         id: panel
         visible: root.opened && root.rowsLoaded
         color: "transparent"'
     cp "$2" "$shell_dir/shell.qml"

     # The fixture menu. Its actions only touch markers: never load the shipped
     # menu here, whose rows lock, suspend and power off (tests/AGENTS.md).
     printf '%s\n' '{' \
       '  "probe": {"label": "Probe"},' \
       "  \"probe.act\": {\"label\": \"Act\", \"action\": \"touch $marks/act\"}," \
       '  "probe.link": {"label": "Link", "target": "probe.sub"},' \
       '  "probe.sub": {"label": "Sub"},' \
       "  \"probe.sub.x\": {\"label\": \"X\", \"action\": \"touch $marks/x\"}," \
       "  \"probe.d\": {\"label\": \"D\", \"action\": \"touch $marks/d\"}" \
       '}' > "$work/fake/default/omarchy/omarchy-menu.jsonc"

     # The menu scripts summon through omarchy-shell; forward that to the probe.
     # shellcheck disable=SC2016 # the stub expands its own arguments when it runs
     printf '%s\n' "#!$TEST_BASH" \
       '[ "$1 $2 $3" = "shell summon omarchy.menu" ] || { echo "stub omarchy-shell: $*" >&2; exit 2; }' \
       "exec qs ipc -p '$shell_dir' call probe open \"\$4\"" > "$work/stub/omarchy-shell"
     chmod +x "$work/stub/omarchy-shell"
     export PATH=$work/stub:$tree/bin:$PATH OMARCHY_PATH=$work/fake

     ipc() { timeout 3 qs ipc -p "$shell_dir" call probe "$@"; }
     qs -p "$shell_dir" > "$work/qs.log" 2>&1 &
     shell_pid=$!
     callers=()
     # shellcheck disable=SC2329 # run by the EXIT trap
     cleanup() {
       for p in "${callers[@]}"; do kill "$p" 2>/dev/null; done
       kill "$shell_pid" 2>/dev/null; wait "$shell_pid" 2>/dev/null
     }
     trap cleanup EXIT

     ready=
     for ((i = 0; i < 100; i++)); do
       if out=$(ipc state 2>/dev/null) && [[ $out == *'"rows":'* && $out != *'"rows":0'* ]]; then ready=1; break; fi
       kill -0 "$shell_pid" 2>/dev/null || die "the shell exited during startup"
       sleep 0.1
     done
     [[ -n $ready ]] || die "the menu never loaded its fixture rows (last state: ${out:-none})"

     K_RIGHT=$((0x01000014)) K_RETURN=$((0x01000004)) K_ESCAPE=$((0x01000000))
     failed=0
     pass() { echo "PASS $1"; }
     fail() { echo "FAIL $1"; failed=1; }
     summon() { ipc open "{\"menu\":\"$1\"}" >/dev/null; sleep 0.3; }
     active() { ipc state | sed -n 's/.*"active":"\([^"]*\)".*/\1/p'; }
     fresh() { rm -f "$marks"/*; }
     alive_after() { sleep "$2"; kill -0 "$1" 2>/dev/null; }
     exited_within() { # pid seconds -> sets rc; 0 if it exited in time
       local i
       for ((i = 0; i < $2 * 5; i++)); do kill -0 "$1" 2>/dev/null || { wait "$1"; rc=$?; return 0; }; sleep 0.2; done
       return 1
     }

     # 1a-1d, 1f: rows in `probe` are act(0) link(1) sub(2) d(3).
     fresh; summon probe; ipc sel 0 >/dev/null; ipc key $K_RIGHT >/dev/null; sleep 0.8
     [[ -e $marks/act ]] && fail "1a Right on an action row ran it" || pass "1a Right on an action row does nothing"
     summon probe; ipc sel 1 >/dev/null; ipc key $K_RIGHT >/dev/null; sleep 0.3
     [[ $(active) == probe.sub ]] && pass "1b Right on a link row follows it" || fail "1b Right on a link row: active is $(active), want probe.sub"
     summon probe; ipc sel 2 >/dev/null; ipc key $K_RIGHT >/dev/null; sleep 0.3
     [[ $(active) == probe.sub ]] && pass "1c Right on a submenu row opens it" || fail "1c Right on a submenu row: active is $(active), want probe.sub"
     fresh; summon probe; ipc nocursor >/dev/null; ipc key $K_RIGHT >/dev/null; sleep 0.8
     [[ -e $marks/act ]] && fail "1d Right with no cursor ran a row" || pass "1d Right with no cursor does nothing"

     # 1e, 1g: Right in a prompt must not answer for the caller.
     omarchy-menu-input Name > "$work/input.out" 2>&1 & p=$!; callers+=("$p"); sleep 1
     ipc key $K_RIGHT >/dev/null
     if alive_after "$p" 1; then pass "1e Right in omarchy-menu-input does not submit"; ipc key $K_ESCAPE >/dev/null; exited_within "$p" 5 || kill "$p"
     else wait "$p"; fail "1e Right in omarchy-menu-input submitted (caller exited $?, printed '$(cat "$work/input.out")')"; fi
     omarchy-menu-select Pick a b > "$work/select.out" 2>&1 & p=$!; callers+=("$p"); sleep 1
     ipc key $K_RIGHT >/dev/null
     if alive_after "$p" 1; then pass "1g Right in omarchy-menu-select does not pick"; ipc key $K_ESCAPE >/dev/null; exited_within "$p" 5 || kill "$p"
     else wait "$p"; fail "1g Right in omarchy-menu-select picked (caller exited $?, printed '$(cat "$work/select.out")')"; fi

     # 1f: the positive control. If Enter does nothing, no key arrived and 1a proves nothing.
     fresh; summon probe; ipc sel 0 >/dev/null; ipc key $K_RETURN >/dev/null; sleep 0.8
     [[ -e $marks/act ]] && pass "1f Enter on an action row runs it (keys arrive)" || fail "1f Enter on an action row did nothing: no key reached the menu"

     # 2a, 2b: a displaced request releases its caller, which exits 1 as for Escape.
     omarchy-menu-select Pick a b > /dev/null 2>&1 & p=$!; callers+=("$p"); sleep 1
     summon probe
     if exited_within "$p" 5; then [[ $rc == 1 ]] && pass "2a a select displaced by an open exits 1" || fail "2a displaced select exited $rc, want 1"
     else fail "2a a select displaced by an open is still waiting after 5 s"; kill "$p"; fi
     omarchy-menu-select First a > /dev/null 2>&1 & p=$!; callers+=("$p"); sleep 1
     omarchy-menu-select Second b > /dev/null 2>&1 & p2=$!; callers+=("$p2")
     if exited_within "$p" 5; then [[ $rc == 1 ]] && pass "2b a select displaced by a select exits 1" || fail "2b displaced select exited $rc, want 1"
     else fail "2b a select displaced by a select is still waiting after 5 s"; kill "$p"; fi
     ipc key $K_ESCAPE >/dev/null; exited_within "$p2" 5 || kill "$p2"

     exit $failed
     ```

   - Create `tests/menu-keys.nix`:

     ```nix
     { pkgs, omarchy }:
     # #1305: the real Menu.qml in a headless Quickshell. Right must not run a
     # row, and a displaced request must release its caller. Why: tests/AGENTS.md.
     pkgs.runCommand "nixarchy-menu-keys"
       {
         nativeBuildInputs = [
           pkgs.bash
           pkgs.coreutils
           pkgs.perl
           omarchy.quickshell
         ];
       }
       ''
         export XDG_RUNTIME_DIR=$TMPDIR/run QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY=wayland-test LC_ALL=C.UTF-8
         export QML_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}
         export TEST_BASH=${pkgs.bash}/bin/bash
         mkdir -m 700 "$XDG_RUNTIME_DIR"
         bash ${./menu-keys.sh} ${omarchy}/share/omarchy ${./menu-keys-shell.qml}
         touch $out
       ''
     ```

   - In `flake.nix`, directly after step 3's `menu-model-merge` entry:

     ```nix

               # #1305: Right never runs a menu row, and a displaced request releases its caller.
               menu-keys = import ./tests/menu-keys.nix {
                 pkgs = pkgsFor.${system};
                 omarchy = self.packages.${system}.omarchy;
               };
     ```

   - `git add tests/menu-keys.sh tests/menu-keys.nix tests/menu-keys-shell.qml`,
     then `nix fmt`, `git diff --stat`, and `shellcheck -s bash tests/menu-keys.sh`
     (must be clean at every level; it was on 2026-10-17).
   Traps: `#!/usr/bin/env bash` is already on the script, and the fixture
   must never be the shipped menu (Risks).

6. **First sandbox build of `checks.menu-keys`: its own step.** The harness
   has only run on p620, outside the sandbox. Build it once, visibly:

   ```bash
   #!/usr/bin/env bash
   drv=$(nix eval --raw .#checks.x86_64-linux.menu-keys.drvPath) || exit 1
   log=/mnt/data/vmtest/menu-keys-first.log    # outside the worktree, so step 7's git add -A cannot stage it
   flock /mnt/data/vmtest/codex-build.lock nix build "$drv^*" --no-link --print-build-logs > "$log" 2>&1
   rc=$?
   grep -E '^(PASS|FAIL)|menu-keys:' "$log"
   echo "status=$rc"
   exit "$rc"
   ```

   Expected: nine `PASS` lines (1a, 1b, 1c, 1d, 1e, 1g, 1f, 2a, 2b) and
   `status=0`. **Stop and report, without changing the harness to make it
   pass, if:**
   - the IPC socket cannot be created (`Failed to start IPC server`; the path
     is too long);
   - actions or the stub do not resolve under `bash -lc` (1f fails: "no key
     reached the menu", or a marker never appears, or `menu-keys: <tool> is
     not on PATH`);
   - `QtTest` does not load (`module "QtTest" is not installed` in the log).

   Any `menu-keys:` line with exit 2 is the harness failing to run, never a
   result.
   Traps: the build's own status is captured, never a pipe's (§1). The log
   lives outside the worktree. The drvPath is evaluated first, so a stale
   evaluation cannot answer (§5).

7. **Commit a known-good baseline.** `git add -A`, then
   `git status --short` must show only this task's files:
   - `pkgs/omarchy/default.nix` and the five `pkgs/omarchy/1305-menu-*.js`;
   - `flake.nix`;
   - `tests/menu-model-merge.{js,nix}`, `tests/menu-keys.{sh,nix}` and
     `tests/menu-keys-shell.qml`;
   - `plan/2026-10-17-1305-omarchy-menu-upstream-bugs.md`, only if step 1
     recorded a deviation.

   `result-omarchy` is ignored (`.gitignore`: `result-*`). Commit with the
   subject "The menu's right arrow no longer runs a row, a displaced menu
   prompt releases its caller, and a partial menu override keeps the rest of
   the row (#1305)" and the trailer
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. The §1 loop
   below checks out of this commit.
   Traps: no `wip:` subject (§8).

8. **§1 proofs: break, red, restore, green. One carry at a time.** For each
   break: edit `pkgs/omarchy/default.nix` as described, prove the break
   landed (`git diff pkgs/omarchy/default.nix` shows only the deleted
   lines), build the package (package tier), build the check, save the
   output, restore with `git checkout HEAD -- pkgs/omarchy/default.nix`,
   rebuild, and see green. Never restore with `git checkout -- <path>` (§5).

   | break | check | expected red output (measured 2026-10-17) |
   |---|---|---|
   | delete step 2's `substituteInPlace …MenuModel.js` command (3 lines) | `menu-model-merge` | the nine `FAIL` lines below, exit 1 |
   | delete the bug 1 `substituteInPlace` command (4 lines with its comment) | `menu-keys` | `FAIL 1a Right on an action row ran it`, `FAIL 1e Right in omarchy-menu-input submitted (caller exited 0, printed '')`, `FAIL 1g Right in omarchy-menu-select picked (caller exited 0, printed 'a')`; every other case PASS |
   | delete the bug 2 `substituteInPlace` command (4 lines with its comment) | `menu-keys` | `FAIL 2a a select displaced by an open is still waiting after 5 s`, `FAIL 2b a select displaced by a select is still waiting after 5 s`; every other case PASS |

   The bug 3 red output:

   ```
   FAIL label-only override: system.shutdown.kind is "menu", want "action"
   FAIL label-only override: system.shutdown.action is "", want "systemctl poweroff"
   FAIL label-only override: system.shutdown.when is "", want "true"
   FAIL label-only override: system.shutdown.icon is "", want "P"
   FAIL action-only override makes a menu an action: system.sub.label is "system.sub", want "Sub"
   FAIL stated empty when clears it: system.shutdown.action is "", want "systemctl poweroff"
   FAIL stated empty action makes it a submenu: system.shutdown.label is "system.shutdown", want "Shutdown"
   FAIL target-only override makes it a link: system.sub.label is "system.sub", want "Sub"
   FAIL an unknown key is not copied: system.shutdown.action is "", want "systemctl poweroff"
   ```

   Also prove the key filter is load-bearing: in `pkgs/omarchy/1305-menu-stated-keys.js`,
   replace `Object.keys(entry).filter(function(k) { return k in normalized })`
   with `Object.keys(entry)`. Expect
   `FAIL a stray key survived the merge: id,parent,kind,icon,iconFont,label,title,target,description,action,provider,aliases,when,checked,$comment,order`.
   #1301 adds `disabled`, so the list may name it too. Restore with
   `git checkout HEAD -- pkgs/omarchy/1305-menu-stated-keys.js`.

   **If a break stays green, first prove the break applied:** run
   `grep -c rightEnters` (or `statedKeys`, or `releaseDisplacedRequest`) on
   the rebuilt `result-omarchy`, and check the result link moved. Then grep
   the tree for a second place that does the same thing (§1). Save every red
   output for the PR body.
   Traps: build by drvPath (`nix build "$drv^*"`); and `set -o pipefail`, or
   no pipe, on any status you read.

9. **Docs: `pkgs/AGENTS.md` and `tests/AGENTS.md`.**
   - `pkgs/AGENTS.md`: insert before `<a id="display-text-size-on-a-managed-config-948"></a>`
     (`:224` at 7e0ceac5) a section with the anchor
     `<a id="the-menus-own-bugs-1305"></a>` and the heading
     `### The menu's own bugs (#1305)`. In the house style of the #1070
     section above it, write:
     - **CARRIED, until omacom/omarchy fixes them.** Three `--replace-fail`
       substitutions, written against the tree after
       `1301-menu-disabled.patch`.
     - **Bug 1**: Right ran action rows, Shutdown included, and answered
       prompts. The guard is the branch's first statement and tests "not
       Enter", so it holds on quattro's `readingKey` line too. Drop it when
       upstream restricts Right.
     - **Bug 2**: a displaced prompt hung its caller. The write goes through
       `Quickshell.execDetached(["sh", …])`, not `resultProc`, because one
       `Process` ignores a new command while it runs. Drop it when a shipped
       release contains #9031.
     - **Bug 3**: partial overrides blanked rows. Only stated keys are copied
       onto an existing id. Drop it when upstream merges stated keys only.
       `modules/apps.nix`'s full-row merge is then redundant (follow-up).
     - **Not carried, with links**: #14053/#15519 (early summon), #9031, and
       the report-only bugs 4, 6, 7, 11, plus 8 (leave), 9 and 10 (fixed on
       quattro).
     - **Checks**: `checks.menu-model-merge` and `checks.menu-keys`.
   - `tests/AGENTS.md`: insert before `## Working here` (`:1367`) a section
     `## menu-keys runs the real Menu.qml headless, and never the shipped menu`.
     It covers:
     - offscreen Quickshell has "No PanelWindow backend loaded", so the
       harness swaps the layer window for a `FloatingWindow` in its copy, and
       dies if that anchor is not found exactly once;
     - QtTest's `TestCase.keyClick` delivers real key events;
     - the stub `omarchy-shell` lets the built `omarchy-menu-select` and
       `-input` run as the callers;
     - 1f (Enter runs a row) is the positive control, without which an "all
       quiet" 1a proves nothing;
     - **the trap**: on 2026-10-17 one Right keypress against the SHIPPED menu
       ran `omarchy-launch-screensaver force` on p620. It reached nothing only
       because the environment had no compositor variables. A harness that
       sends keys loads a fixture menu whose actions touch markers, never the
       shipped one;
     - `bash -lc` actions take `PATH` from the login profile outside the
       sandbox, so a stub on `PATH` can be skipped there.
   Traps: nothing renumbers. These files have no numbered sections, and
   CLAUDE.md's numbered sections are not touched.

10. **The rest of the suite, then amend.** Run each command on its own:
    - `nix fmt -- --ci`
    - `nix run nixpkgs#statix -- check .`
    - `nix run nixpkgs#deadnix -- --fail .`
    - `shellcheck -s bash tests/menu-keys.sh`
    - by drvPath, under flock: `checks.patched-files`, `checks.omarchy`,
      `checks.qml`, `checks.menu-close`, `checks.menu-model-merge`,
      `checks.menu-keys`

    `checks.patched-files` must stay green. Its intersection list now
    includes `shell/plugins/menu/Menu.qml` and `MenuModel.js`. Confirm it
    with a real file, not `<(…)`, because the script reads its input twice
    and a process substitution can be read only once:
    `f=$(mktemp); printf '%s\n' shell/plugins/menu/Menu.qml shell/plugins/menu/MenuModel.js > "$f"; bash .github/scripts/omarchy-patched-files.sh --list "$f" .; rm -f "$f"`.
    It must print both paths; at 7e0ceac5 it printed neither.

    `checks.session` and `checks.options` are left to CI unless
    `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
    prints `0`.

    Amend the step 7 commit so the branch's last code commit has the step 7
    subject, and check that `git show --stat HEAD` lists only this task's
    files.
    Traps: §5's nixpkgs-fmt hook. If `nix fmt -- --ci` fails once and then
    passes, a hook reformatted a file; read `git diff --stat`.

11. **Follow-ups, as text for the owner.** Do not file them. Add each to the
    PR body as a ready-to-file draft, with milestone `Keeping the lights on`
    and an area label (§12):
    - (a) "Should nixarchy-menu and nixi take #1305's partial-override fix?
      Both read the unpatched MenuModel.js from the omarchy input
      (flake.nix:260, :357)."
    - (b) "modules/apps.nix's full-row menu merge (:958, :1020) is redundant
      once #1305 lands; remove it with a check that overrides still keep
      their label and icon."

    The upstream drafts A-F are in the spec's appendix. Leave them there for
    the owner; no agent posts them.

12. **Agent bus (§9), only when the owner says so.** Draft one post with two
    general lessons, and nothing else:
    - offscreen Quickshell cannot load a `PanelWindow`, and a
      `FloatingWindow` swap plus QtTest's `keyClick` drives a real plugin's
      key handler headless;
    - a key-driving harness must never load a real menu, because one
      keypress ran a real action.

    Redact any private path (§9). Post it before the PR, only after the
    owner approves.

13. **PR, only when the owner says so.** Push `fix/1305-omarchy-menu-upstream-bugs`
    and open the PR.
    - **Title (a full sentence, and it doubles as the release note):** "The
      menu's right arrow no longer runs a row, a displaced menu prompt
      releases its caller, and a partial menu override keeps the rest of the
      row (#1305)".
    - **Body, following `.github/PULL_REQUEST_TEMPLATE.md`:**
      - "What this changes, and why": the three carries. Say it would break
        on Arch too, carried by the owner's decision, with reports drafted
        for a human to file. Link `intent/`, `spec/` and `plan/` for this
        slug.
      - "How I proved the check fails": the red outputs from step 8, each
        under its break.
      - "Checks run locally": the step 10 list.
      - "What this cost": the `tests/AGENTS.md` section.
    - **Closing lines:** `Closes #1305`, alone on its line. Nothing else is
      closed. Write "a skip-CI marker" if one must be mentioned, never the
      bracketed form (§8).
    - **Name which steps the `coder` agent did**, and which steps were
      finished by the session.
    - End with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
    - **After the push:**
      - `gh pr view <n> --json headRefOid` must match the pushed commit
        before any check result is read (§6);
      - `gh pr view <n> --json mergeable` before saying it will merge.

14. **Edge: on `edge-next`, after main merges.** This runs only once `main`
    contains step 13's PR, and only when the owner says so.
    - **Prerequisite: #1301's edge carry has landed on `edge`.** #1301's
      spec says its stable-only `1301-menu-disabled.patch` line is deleted on
      edge, because quattro already has that code. Without that carry, merging
      main breaks the edge build before this step's anchors are even
      reached. Check it with `git -C /mnt/data/vmtest/wt-edge grep -c
      1301-menu-disabled.patch origin/edge -- pkgs/omarchy/default.nix`,
      which must find no patch line. If it does find one, stop and ask.
    - **Set up the worktree.** In `/mnt/data/vmtest/wt-edge`:
      `git fetch origin`; `git status --short` must print nothing, and
      `git log --oneline origin/edge..edge-next` must print nothing. If
      either prints anything, stop and ask: that is someone's work. Then `git checkout edge-next && git reset --hard origin/edge`
      (the #1280 route), followed by `git merge --no-edit origin/main`. A
      conflict stops the step.
    - **The product needs nothing.** All six anchors were checked identical
      on quattro `cce8b1c9`: Menu.qml :1350, :850, :943, :967, and
      MenuModel.js :65, :88. Re-run step 1's anchor script against the edge
      build. Any count other than 1 stops the step.
    - **The harness needs one edge carry commit.** quattro's menu window is
      `OverlayWindow`, not `PanelWindow` (Menu.qml:1263-1266). In
      `tests/menu-keys.sh`, change the `replace_once` anchor and replacement
      to:

      ```
      '  OverlayWindow {
          id: panel
          shown: root.opened && root.rowsLoaded
          WlrLayershell.namespace: "omarchy-menu"'  ->  '  FloatingWindow {
          id: panel
          visible: root.opened && root.rowsLoaded
          color: "transparent"'
      ```

      (each continuation line indented four spaces, as in the file). This is
      unmeasured on quattro. If `checks.menu-keys` cannot reach nine `PASS`
      lines there, **stop and report**; do not weaken the cases. A quattro
      menu also takes focus in `filterInput`, which forwards keys to
      `keyCatcher` first (`Ui/FilterInput.qml`), so an unhandled Right moves
      the caret, which is expected.
    - **Verify on edge, by drvPath and under the same tiers:** the edge
      `omarchy` package, `checks.menu-model-merge`, `checks.menu-keys`, and
      `checks.patched-files`. Then the §1 break for bug 1 on edge: delete the
      guard line from `pkgs/omarchy/1305-menu-right-guard.js`, keeping the
      comment. Expect 1a and 1g red; record what 1e does on quattro. Restore
      it with `git checkout HEAD -- pkgs/omarchy/1305-menu-right-guard.js`.
    - **Commit and publish.** Commit with the subject "Edge: the menu-keys
      check drives quattro's OverlayWindow menu (#1305)", then push
      `edge-next` as a fast-forward to `edge-candidate` and dispatch
      `omarchy-edge.yml` with `from_candidate=true`. `prepare`, `wait-idle`,
      `verify` and `promote` must all be green, and `edge` must contain the
      commit.
    - **Until this lands**, the daily edge run builds main's substitutions
      unchanged, which is expected to pass. Only `checks.menu-keys` would
      fail on edge, and `verify` does not run it, so `edge` users are not
      blocked.
    Traps: §11 (no force-push; edge only fast-forwards); and a p620 switch
    kills installs in flight, so this step never switches p620.

## Tests

| command | expected |
|---|---|
| step 1's anchor script | six lines starting with `1`, plus the two `requestSerial += 1` lines |
| `nix build "$(nix eval --raw .#checks.x86_64-linux.menu-model-merge.drvPath)^*"` | eight PASS, success |
| `nix build "$(nix eval --raw .#checks.x86_64-linux.menu-keys.drvPath)^*"` | nine PASS (1a-1g, 2a, 2b), success |
| each step 8 break | its listed FAIL lines, the build fails |
| `checks.patched-files`, `checks.omarchy`, `checks.qml`, `checks.menu-close` | success |
| `nix fmt -- --ci`, statix, deadnix, `shellcheck -s bash tests/menu-keys.sh` | clean |
| edge (step 14): the same two checks | nine and eight PASS |

## Rollback

- **Main:** revert the squash commit (`git revert <sha>` in a PR). That
  removes the five snippets, three substitutions, two checks and both doc
  sections together. No user state changes: the carries edit only the
  read-only package tree.
- **Edge:** revert step 14's carry commit on `edge-next`, then push it as a
  fast-forward to `edge-candidate` and publish again. Never force-push.
- **Bug 3 only:** delete step 2's block and its two snippets. A user's
  partial overrides return to blanking the row, which was the behaviour
  before.

## Deviations recorded during implementation

None yet.
