---
status: approved
issue: 1305
intent: intent/2026-10-17-1305-omarchy-menu-upstream-bugs.md
---

# Spec: Carry three of the Omarchy menu's bugs, and draft reports for six

## Design

Bug numbers are the intent's. File and line references are to the deployed
tree, `/nix/store/rla9km5silzbp6h9dcfz0pd1p90ia8r9-nixarchy-omarchy-tree`,
whose menu files are byte-identical to upstream 4.0.4. The `quattro` text was
read from `omacom/omarchy@quattro`; edge pins it at `cce8b1c9`.

### Decisions

1. **Bug 1 (the right arrow activates rows): carry and report.** Stable and
   edge both carry it. A new function, `rightEnters()`, is true only when no
   select or input prompt is open, the cursor is active, and the row under it
   is a `menu` or `link` row. The key branch's Right term becomes
   `(event.key === Qt.Key_Right && root.rightEnters())`, so Right opens a
   submenu or follows a link. Anywhere else it is left unhandled: on action
   and app rows, with no cursor, and in a select or input prompt, where it
   used to pick the row or submit the half-typed text. On stable, nothing
   else handles it. On edge, `FilterInput` gets the key after `keyCatcher`
   (quattro's `Ui/FilterInput.qml`: "whatever it leaves unaccepted is typed
   here"), so Right moves the text caret, which is what a text field should
   do. Enter is unchanged. It is the only high-severity bug nobody upstream
   has reported, and Shutdown is three keys away (Super+Escape opens System,
   Up wraps to its last row, Shutdown).
2. **Bug 2 (a displaced request hangs its caller): carry, no new report.**
   Stable and edge both carry it. When `openDmenu` or `openExistingMenu`
   starts while a request is still pending, it first writes that request's
   `doneFile` empty, which is what `cancel()` does. The waiting
   `omarchy-menu-select` or `omarchy-menu-input` then exits 1, as it does for
   Escape (measured below). Both functions call one new function,
   `releaseDisplacedRequest()`, at the top. It runs
   `Quickshell.execDetached(["sh", "-c", ": > \"$1\"", "sh", root.doneFile])`.
   That passes the path as an argument, so it needs no quoting, and it uses no
   login shell, so it does not wait on the user's profile the way
   `Util.execDetached`'s `bash -lc` would. An action alias that displaces a
   request already goes through `cancel()` and is finished properly
   (`openRoute`, Menu.qml:860). `omarchy-menu-images` is not covered: it
   waits on `omarchy-shell image-selector` (`bin/omarchy-menu-images:341`),
   not this menu. That corrects the intent's table, which listed it.

   The write is detached rather than sent through `resultProc`. A single
   `Process` ignores a new command while it is still running (Menu.qml:953
   says so for `guardProc`), so a write queued behind an earlier result
   could be lost. The displaced request has not finished, so nothing else
   ever writes its file and the two writes cannot race. Upstream PR #9031
   fixes this more fully. We drop the carry when a release we ship contains
   #9031. Whether to comment on #9031 is the owner's call (§11).
3. **Bug 3 (a partial override wipes the row): carry and report.** Stable and
   edge both carry it. `parseMenuJsonc` records which keys the file actually
   stated, on the normalized item. It keeps only keys `normalizeItem`
   returns, so an unknown key (`"$comment"`) or one it ignores (`order`) is
   never copied as `undefined`. When `mergeMenuSources` merges an entry
   onto an id an earlier source already defined, it copies only those stated
   keys. It then recomputes `kind` by `normalizeItem`'s own rule (`action`
   gives `action`, otherwise `target` gives `link`, otherwise `menu`), so
   stating `"action": ""` turns an action into a submenu. Finally it drops the
   record. `normalizeItem` is not touched (see Risks: #1301).
   A first definition is still copied whole, so a new row is still fully
   normalized. Stating a key gives it the value `normalizeItem` gives a new
   row: `"when": ""` clears the guard, while `"label": ""` falls back to the
   id, as it does today. This is what Menu.qml:243 and the seeded extension
   file promise. `modules/apps.nix`'s full-row merge
   stays: it becomes redundant but stays harmless, and removing it is a
   follow-up.
4. **Bug 4 (an inline `//` drops the extension file): report only.** A fix
   needs a string-aware comment stripper, because `"https://…"` actions are
   common, and that is the most code of any carry here. The failure is
   silent: every user row disappears and nothing says why. But it takes an
   edit to the user's own file, and it happens the moment they reload, so it
   is found while they are still editing. Nixarchy's generated defaults have
   no inline comments.
5. **Bug 5 (an early summon loses the route): leave it to upstream.** Issue
   #14053 and PR #15519 are open. No report and no carry.
6. **Bug 6 (`summon <alias>` ignores `when`): report only.** Whether `when`
   should gate a direct summon is upstream's design question. Reaching a
   hidden row means summoning its id or alias by name, which is deliberate.
7. **Bug 7 (one shell for every guard): report only, low priority.** It is
   latent, because every shipped guard parses. quattro narrows only the
   `exit 0` half.
8. **Bug 8 (search ignores ancestor words): leave it.** It is a feature
   request. If the owner wants it raised, it goes to upstream's Suggestions
   discussions; nothing here files it.
9. **Bugs 9 (PageUp) and 10 (AltGr/IME): no carry.** Both are fixed on
   quattro, so edge already has the fixes. Stable gets them at the first
   stable release cut from quattro. Bug 9 is low severity. Bug 10's upstream
   fix replaces the key filter with a text input (`FilterInput`, #14433),
   which is too large to backport.
10. **Bug 11 (power-profiles provider not `volatile`): report only, no
    carry.** It is real, and still true on quattro (Menu.qml:276; `fonts` at
    :273 has the flag). But **no shipped row uses this provider.** Not 4.0.4's
    menu, not quattro's (whose providers are `apps`, `fonts` and `languages`),
    not nixarchy's generated defaults, and not the live `/etc` or extension
    files on p620. Only a user row with `"provider": "power-profiles"`, which
    upstream's `docs/menu.md` advertises, can reach it. So #1303's "Style ›
    Power profile" row was not found here, and with nothing reaching the bug,
    carrying a fix is not worth the upkeep.
11. **Q2: a human files upstream.** The appendix has one draft per bug
    reported (1, 3, 4, 6, 7, 11), in upstream's `bug.yml` shape. The owner
    edits, approves and files them; no agent posts.
12. **Q3: #1301 lands first.** These substitutions are written against the
    tree after `1301-menu-disabled.patch`. They apply after every `patch`
    line in `pkgs/omarchy/default.nix`.
13. **Q4: nixarchy-menu and nixi are out of scope**, as in #1301. Both read
    the unpatched `MenuModel.js` from the `omarchy` input (`flake.nix:260`,
    `:357`), so bugs 3, 4, 7 and 8 stay there. A follow-up issue for the owner
    asks whether they should take the bug-3 fix.

### How the carries are written

- **`substituteInPlace --replace-fail`, not a `.patch`.**
  `.github/scripts/omarchy-patched-files.sh` derives "files this port touches"
  from `substituteInPlace`, `sed -i`, `nix-bin/` and seeds. It never reads
  `.patch` files, so a bump's report would not name `Menu.qml`. `--replace-fail`
  also stops the build if a bump rewords an anchor, as the `--fuzz=0` patches
  do. The substitutions sit together in `pkgs/omarchy/default.nix`, after the
  last `patch -d … --fuzz=0` line, with one `# Why: pkgs/AGENTS.md#…` pointer.
- **Anchors, checked in both trees.** These are pre-#1301 line numbers.
  `--replace-fail` matches text, not lines, so #1301's offsets do not matter,
  but the plan cites the lines of the tree it is applied to.
  - Bug 1: the whole line Menu.qml:1106,
    `} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {`.
    On quattro (:1349) the Right term is
    `Util.readingKey(event) === Qt.Key_Right`, so it differs.
  - Bug 2: `function openExistingMenu(initialMenu) {\n    requestSerial += 1`
    (:795) and `function openDmenu(payload) {\n    requestSerial += 1` (:819).
    These are identical on quattro (:943, :967).
  - Bug 3: `out.push(normalizeItem(id, entry))` (MenuModel.js:60) and
    `for (var k2 in entry) merged[k2] = entry[k2]` (:79). Both are identical
    on quattro (:65, :88).
- **Edge.** `main` merges into `edge` (the #1278 design), so the bug 2 and
  bug 3 substitutions apply there unchanged. Bug 1's would fail the edge
  build. So one edge carry commit replaces its anchor and the Right condition
  with quattro's `Util.readingKey(event) === Qt.Key_Right` form, which keeps
  right-to-left mirroring. It goes on `edge-next` and is published through
  `edge-candidate`, as the #1280 carry was. Nothing for bugs 9 and 10 is
  carried, so edge has nothing to drop.
- **`pkgs/AGENTS.md`** gets one section, "The menu's own bugs (#1305)". For
  each carry it says what breaks without it and when to drop it: bug 1 when
  upstream restricts Right; bug 2 when a shipped release contains #9031;
  bug 3 when upstream merges stated keys only. It also lists the
  uncarried bugs and their upstream links. `data/bin-ledger.nix` needs no
  row, because it covers `bin/` and these are `shell/` files.

### Coexistence (§14)

No NixOS or Home Manager option is set or changed, so nothing can collide
with a user's own configuration. The one change that touches user data,
bug 3, makes a user's `~/.config/omarchy/extensions/omarchy-menu.jsonc` merge
the way upstream documents. A user who relied on a partial override blanking
a row loses that; nobody is known to. No `tests/coexistence` fixture, because
there is no option to collide. The release notes say that the right arrow no
longer runs rows and that partial overrides now keep the rest of the row
(§14's rule for changed behaviour a user commonly meets).

## Alternatives rejected

- **Carry every confirmed bug.** Each carry is re-applied at every bump and
  needs a check. Bugs 5 and 2 have upstream fixes in flight, and 6, 7, 8 and
  11 do no harm on a shipped menu. Bug 2 is carried anyway, because a hung
  script needs a reboot or a `kill` to clear.
- **Report only, carry nothing.** Bug 1 can power off a machine on a
  keypress, and upstream has no report of it. Waiting an unknown time for an
  upstream release is the wrong trade for a one-condition fix.
- **Carry upstream PR #9031 for bug 2.** It adds a release queue, a
  dedicated process and liveness checks in three scripts (#9031's own
  description). That is far more to re-apply than the two-line displacement
  fix, and it is unmerged, so it may change.
- **Carry bug 9's one-line PageUp fix on stable.** It is cheap, but low
  severity, and it disappears at the first stable bump from quattro. A check
  for a carry that short-lived costs more than the bug.
- **Carry bug 11's `volatile: true`.** One word, but no shipped row reaches
  it (decision 10). A check would have to invent a row in order to fail.
- **Fix bug 3 in `normalizeItem`** (fill defaults only for new rows). #1301
  already changes `normalizeItem` (it adds `disabled`), so two carries would
  edit one function. Recording the stated keys in `parseMenuJsonc` and
  honouring them in `mergeMenuSources` leaves it alone.
- **`.patch` files, like 901 and 902.** `omarchy-patched-files.sh` cannot
  see them (above).
- **Prove the `Menu.qml` fixes in `checks.session`.** It boots a VM
  (§6: nothing in flight on CI), and `tests/session.nix:822` records that a
  menu summoned over IPC does not hold keyboard focus, so a keypress probe
  there would need a compositor key path that has never been measured. The
  headless harness below reaches the same code at `runCommand` cost.

## Risks

- **#1301 conflict, by function.** #1301 carries upstream #6955's
  `Menu.qml`/`MenuModel.js` hunks as `1301-menu-disabled.patch`, and
  substitutes `guardHelpers()`. Its hunks touch `normalizeItem`,
  `mergeMenuSources` (the injected root row, MenuModel.js:86),
  `isVisible`, `labelFor`, `displayRow`, `searchScore`, `guardLine`,
  `guardScript`, and in Menu.qml the Enter branch's `else` line (:1111,
  becoming `root.settleCursor()`), the guard results and the row delegate.
  This spec touches `parseMenuJsonc` (:60), the merge loop in
  `mergeMenuSources` (:79, not the root row), the Right condition (:1106),
  `openExistingMenu` and `openDmenu`. None of these lines is in a #6955 hunk,
  but :1106 is two lines above one hunk's context and :79 is four above
  another's.
  Because the substitutions run after the patch, `--replace-fail` fails the
  build if #1301's final patch differs from the one read here. The plan's
  first step is to re-read the merged #1301 diff.
- **Bug 1 changes a habit.** A user who used Right as "run" will find it
  does nothing on action rows. That is the intent. The release note says so.
- **Bug 2's empty write races the caller's cleanup.** The caller's EXIT trap
  removes its temp files. If it was killed first, `: >` recreates an empty
  file in `/tmp`, which is harmless. Callers that wait on `doneFile` all
  treat an empty selection as cancel and exit 1 (`omarchy-menu-select:95`,
  `omarchy-menu-input:54`).
- **Bug 3 relies on an object field surviving QML.** `statedKeys` lives on a
  plain JS object only between `parseMenuJsonc` and `mergeMenuSources`. The
  comment at MenuModel.js:97-103 warns that writes into QML `var` properties
  can be dropped. The merge already builds fresh objects, and the harness
  (below) runs the real `Menu.qml` load path, not node alone.
- **The harness can run real commands.** On 2026-10-17, while this spec was
  being measured, one keypress against the SHIPPED menu ran
  `omarchy-launch-screensaver force` on p620. It reached nothing, because the
  environment had no compositor variables. So the harness loads only a
  fixture menu, whose actions `touch` marker files. In the sandbox there is
  no session to reach either way.
- **The harness edits its copy of `Menu.qml`** (below), and those edits are
  substitutions too. A bump that rewrites `PanelWindow` fails the check
  loudly, not silently, and the fix is in the check.
- **The harness has run only on p620, not in the build sandbox.** Three
  things differ there. The IPC socket path has a length limit, so the plan
  uses a short `XDG_RUNTIME_DIR`, as `tests/sleep-lock-generation.sh` does.
  Actions and providers run through `bash -lc`: on p620 the login profile
  reset `PATH`, and a provider stub was skipped. The sandbox has no
  `/etc/profile`, so stubs on `PATH` should hold there, but the plan's first
  build of the check has to show it. And `QtTest` has to resolve from
  `omarchy.quickshell`'s own Qt. If any of the three fails, the check fails
  to start, which is loud.
- **Edge.** The bug 1 edge carry has to be redone if quattro rewrites the
  key branch again. The edge build fails and names the anchor.

## Verification

Two new checks, both `runCommand`, on the cheap tier of §6. They are picked
up by "Build every check no other job claims" with no workflow edit (§4).

**`checks.menu-model-merge`** (node over the BUILT tree's `MenuModel.js`, as
#1301's check does). It parses a fixture defaults file and a user file, and
asserts seven cases:
- a label-only override keeps `kind`, `action`, `when` and `icon`;
- an action-only override turns a submenu into an action and keeps its label;
- a stated `"when": ""` clears it;
- a stated `"action": ""` turns an action into a submenu and keeps its label;
- a target-only override turns a submenu into a link and keeps its label;
- an unknown key (`"$comment"`) is not copied, and neither it nor
  `statedKeys` is left on the merged row;
- a new row is fully normalized.

- Break: delete the bug-3 substitutions. Measured against the unfixed 4.0.4
  file (`merge-probe.js`, 2026-10-17):

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
  exit=1
  ```

- Restore: with the trial fix, `exit=0`. A first trial kept the old `kind`
  when `action` was cleared, and all four of the original cases still
  passed. Codex found it, and the `"action": ""` case exists for that
  reason. Antigravity found that unfiltered stated keys leave stray fields.
  Without the filter, the probe prints
  `FAIL a stray key survived the merge: id,parent,…,$comment,order`.

**`checks.menu-keys`** (the real `Menu.qml` in a real Quickshell, headless).
This was measured working on p620 on 2026-10-17, outside the build sandbox,
with Quickshell 0.3.2 and qtdeclarative 6.11.2 (see Risks).

Setup:
- The built `shell/` is copied, and the copy of `Menu.qml` gets two
  substitutions. `PanelWindow {` becomes `FloatingWindow {`, because
  offscreen there is "No PanelWindow backend loaded". Its five layer-shell
  lines (anchors, `WlrLayershell.*`, `exclusionMode`) are deleted.
- Two accessor functions expose `displayModel`'s count and labels.
- A fixture `shell.qml` loads the plugin, imports QtTest, sends keys with
  `TestCase.keyClick`, and answers over `IpcHandler`. That includes setters
  for `selectedIndex` and `cursorActive`.
- `OMARCHY_PATH` points at a fixture tree. A `probe` submenu holds two
  action rows that `touch` markers, a link row and a submenu.
- A stub `omarchy-shell` on `PATH` forwards `shell summon omarchy.menu
  <payload>` to the probe. So the BUILT `omarchy-menu-select` and
  `omarchy-menu-input` run unmodified, and the check asserts what their
  callers see.
- The environment is `QT_QPA_PLATFORM=offscreen` with a short
  `XDG_RUNTIME_DIR` (the IPC socket path has a length limit), the way
  `tests/sleep-lock-generation.nix` does it.

Measured on 2026-10-17 on the unfixed tree, then with the trial fixes
(`rightEnters()` and `releaseDisplacedRequest()` exactly as in decisions 1
and 2):

| case | unfixed | trial fix |
|---|---|---|
| 1a Right on an action row | **red**: `act` marker written | no marker |
| 1b Right on a link row | opens `probe.sub` | opens `probe.sub` |
| 1c Right on a submenu row | opens `probe.sub` | opens `probe.sub` |
| 1d Right with no cursor | no marker | no marker |
| 1e Right in `omarchy-menu-input` | **red**: the caller returns, having submitted `""` | caller still waiting |
| 1g Right in `omarchy-menu-select` | **red**: the caller returns `a` | caller still waiting |
| 1f Enter on an action row (positive control) | marker written | marker written |
| 2a `omarchy-menu-select` displaced by an ordinary open | **red**: still waiting after 5 s | caller exits 1 |
| 2b `omarchy-menu-select` displaced by a second select | **red**: first caller still waiting after 5 s | first caller exits 1 |

1b, 1c and 1d are guards: they pass on both and stop the fix from breaking
submenu navigation. 1e and 1g test behaviour, not the `dmenuActive` term:
prompt rows are `kind: "dmenu"` (Menu.qml:533), so `rightEnters()` would
refuse them without it. The term stays as a guard and is not separately
proven. 1f proves the key path is live, so an "all quiet" 1a
cannot mean "no key arrived".

- Break per carry: delete that substitution, rebuild the package, and run
  the check. It must fail naming the case. Restore and watch it pass. The
  failing output goes in the PR.
- Edge: the same two checks on `edge-candidate`. The bug 1 break there is
  the edge carry commit reverted.

Also run, unchanged:
- `checks.patched-files`, which must now list `Menu.qml` and `MenuModel.js`;
- `checks.omarchy`;
- `nix fmt -- --ci`, statix and deadnix.

Bugs 9 and 10 need no check here, because nothing is carried. The plan
notes that the first stable bump from quattro should be checked by hand
against both.

Not covered: real keyboard focus on a Wayland layer surface. The harness
uses a plain window. That is the price of `runCommand` cost, and it is the
layer the bugs live in (the key handler), not the compositor's.

## Appendix: Upstream report drafts

For the owner to edit, approve and file at
https://github.com/omacom/omarchy/issues/new?template=bug.yml. The template
asks for **System details** and **What's wrong?**. None of these were
reproduced on Arch. They were found by reading code that nixarchy ships
unmodified. A was then run in a headless Quickshell, and B and C under
node. D, E and F rest on reading the code. If a stock Arch machine is to
hand, reproducing a draft there before filing is worth the minute it takes.

### Draft A: Right arrow runs the selected menu action, including Shutdown

**System details:** Omarchy 4.0.4 and `quattro` cce8b1c9; found in nixarchy
(Omarchy on NixOS), whose menu files are unmodified upstream.

**What's wrong?** In the menu, Right is handled in the same branch as Enter
(`shell/plugins/menu/Menu.qml`, `Keys.onPressed`: `event.key ===
Qt.Key_Right` in 4.0.4, `Util.readingKey(event) === Qt.Key_Right` on
quattro). So on an action row Right runs the action:
Super+Escape, Up (the cursor wraps to the last row, Shutdown) and Right
powers off with no confirmation. It
also launches app rows. In `omarchy-menu-select` it returns the
highlighted option, and in `omarchy-menu-input` it submits the half-typed
text. Expected: Right opens a submenu and does nothing on other rows.
Steps: Super+Escape, highlight Lock, press Right. The screen locks.

### Draft B: A partial override in omarchy-menu.jsonc blanks the row

**System details:** as above.

**What's wrong?** The extension file's header says "Reuse an existing id to
override/extend it", and `Menu.qml` says overrides are "on a per-key basis".
But `parseMenuJsonc` runs `normalizeItem` on every user entry before
`mergeMenuSources` copies all of its keys over the default, so every key the
user left out is copied as `""` or the id. Steps: put
`"system.shutdown": {"label": "Power off"}` in
`~/.config/omarchy/extensions/omarchy-menu.jsonc` and run `omarchy menu
refresh`. Shutdown disappears from System: it is now an empty submenu.
Expected: the label changes and the action stays.

### Draft C: An inline // comment silently discards omarchy-menu.jsonc

**System details:** as above.

**What's wrong?** `stripJsonc` removes only whole-line comments. A comment
after a value (`"label": "Notes", // mine`) makes `JSON.parse` throw, and
`parseMenuJsonc` returns `[]` without logging anything, so every user row
vanishes and nothing says why. Expected: inline comments are accepted, or the
parse error is shown.

### Draft D: `omarchy menu summon <alias>` runs a row whose `when` is false

**System details:** as above.

**What's wrong?** `openRoute` runs an action row reached by id or alias
before any visibility check, so a row hidden by `when` still runs when
summoned directly. A submenu hidden by `when` also opens, empty. Is that
intended? If `when` means "this does not apply here", a direct summon
probably should not run it either.

### Draft E: One user guard can stop or discard every other menu guard

**System details:** as above.

**What's wrong?** `guardScript` puts every `when`/`checked` into one bash
script as `if { expr; }`. A user guard containing `exit 0` ends the script
early, and every later row shows unconditionally and loses its ✓. A guard
with a syntax error or a nonzero `exit` fails the script, so `Menu.qml`
keeps the previous results (or, on first load, shows every guarded row).
quattro's eight groups confine `exit 0` to one group, but a failing group
still discards all eight. A subshell per guard, `( expr )`, would contain
`exit`. A syntax error still aborts the script, so containing that needs
each guard parsed on its own, for example `( eval '<expr>' )`.

### Draft F: The power-profiles provider never refreshes its ✓

**System details:** as above.

**What's wrong?** `docs/menu.md` lists `power-profiles` as a provider, but
unlike `fonts` it lacks `volatile: true` (`Menu.qml` providers map), so its
rows and their `current` are read once per shell. After switching profile
by other means, the ✓ stays on the old one until `omarchy-restart-shell`.
No shipped row uses this provider, so only a user row with
`"provider": "power-profiles"` shows it.
