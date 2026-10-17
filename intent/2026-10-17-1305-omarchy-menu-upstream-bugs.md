---
status: draft
issue: 1305
author: olafkfreund
---

# Intent: Decide what happens to the Omarchy menu's own bugs

## Problem

A review of the menu on 2026-10-17 found bugs in Omarchy's own menu code,
`shell/plugins/menu/Menu.qml` and `MenuModel.js`, and in the
`omarchy-menu-select`/`-input`/`-images` scripts that wait on it. Nixarchy
does not change the menu files: in 4.0.4 both are byte-identical to upstream's
source (`/nix/store/3pyxkhsadqhyrcm57inxgb9dax4r5vb2-source`). So each of
these would happen on Arch too. Under the routing rule in
`pkgs/omarchy/skills/nixarchy/contributing.md` they are Omarchy's bugs, and
nothing has been reported upstream.

Each one was checked against 4.0.4 (stable) and against `quattro`, upstream's
default branch. Edge pins `quattro` at `cce8b1c9`, which is identical to its
head today. MenuModel.js was run under node for 3, 4 and 8, and the index arithmetic for
9. Codex and
Antigravity each checked the claims independently; the corrections they made
are folded in below. Rows are ordered by severity, so the numbers differ from
the issue's.

| # | Bug | Severity | 4.0.4 | quattro / edge | Upstream knows? |
|---|---|---|---|---|---|
| 1 | **The right arrow activates rows the way Enter does** (Menu.qml:1106). On an action row that includes Shutdown and Reboot, which close every window and power off with no prompt. It launches app rows, and in `omarchy-menu-input` it submits the half-typed text | high: unsaved work lost | yes | yes | not found |
| 2 | **A menu request that is displaced hangs its caller for ever.** `openDmenu`, and `openExistingMenu` (the ordinary Super+Space open), drop the pending `doneFile` without writing it. `omarchy-menu-select` (bin:91), `-input` (:50) and `-images` (:301) then wait with no limit. Nixarchy's `OMARCHY_SHELL_IPC_TIMEOUT` patch bounds only the summon in `-select`, not the wait | high: a script hangs | yes | yes | PR [#9031](https://github.com/omacom/omarchy/pull/9031), open, covers it ("a request displaced by the next one") |
| 3 | **A partial override in `~/.config/omarchy/extensions/omarchy-menu.jsonc` wipes the row.** `normalizeItem` fills in defaults before `mergeMenuSources` copies every key, so a label-only override turns Shutdown into an empty `kind: "menu"`, and the row disappears. Upstream promises the opposite twice: Menu.qml:243 says overrides are "on a per-key basis", and the seeded file says "Reuse an existing id to override/extend it" | medium: the row disappears | yes | yes | not found ([#14425](https://github.com/omacom/omarchy/issues/14425) is a nearby feature request) |
| 4 | **An inline `//` comment silently drops the whole extension file.** `stripJsonc` removes only full-line comments, and the parse error returns `[]` without reporting anything | medium: silent | yes | yes | not found |
| 5 | **A summon before the menu files load loses its route.** `pendingInitialMenu` is written (Menu.qml:866) and never read, so the menu opens root. An action alias opens root as well, instead of running | medium | yes | yes | issue [#14053](https://github.com/omacom/omarchy/issues/14053) and PR [#15519](https://github.com/omacom/omarchy/pull/15519), both open. An earlier PR, #14055, was closed |
| 6 | **`summon <alias>` ignores `when`.** `openRoute` runs a leaf action before any visibility check, and it opens a hidden submenu | low to medium: depends on the row | yes | yes | not found |
| 7 | **One bad guard affects the others.** Every `when`/`checked` runs in one shell as `if { expr; }`. An `exit 0` truncates the batch, and every later row shows unconditionally and loses its ✓. A non-zero exit or a syntax error discards the batch (Menu.qml:987), so the last results stay, or on first load every guarded row shows. quattro splits the guards into eight groups, which limits `exit 0` to one group; a failure in any group still discards all eight | latent: every shipped guard parses | yes | yes, partly narrowed | not found |
| 8 | **Search ignores ancestor words.** "install vim" does not find Install › Editor › Vim, because `matchesQuery` reads only the row's own label, leaf id, aliases and description | low: arguably design | yes | yes | not found |
| 9 | **PageUp in a list shorter than 6 rows loses the cursor.** `(i + delta + count) % count` gives -2 | low | yes | **fixed**: `nextSelectable` normalises the index | already fixed |
| 10 | **AltGr and IME characters cannot be typed in search.** Characters are accepted only with no modifier or with Shift | medium for non-US layouts | yes | **fixed in code** by `FilterInput` (#14433). Not checked on a live session | already fixed |

Two claims were refuted: the stale `maxRowsHeight` is the documented design
("the starting menu sets the ceiling", Menu.qml:157), and the bar icon's store
path is substituted at build time. Neither is in scope.

Two facts in this repository bear on the decision:

- **Nixarchy has already worked around bug 3 for its own rows.**
  `modules/apps.nix:958` and `:1020` describe the same normalize-then-merge
  behaviour, and they rebuild every override as a full row. Users editing
  their own extension file are not covered.
- **nixarchy-menu and nixi carry upstream's `MenuModel.js` as well**, but
  they read it from the raw `omarchy` flake input (`flake.nix:260`, `:357`,
  `follows = "omarchy"`), not from the patched package. A fix carried in
  `pkgs/omarchy` would not reach them, though bugs 3, 4, 7 and 8 do.

## Proposed outcome

- For each bug in the table, a recorded decision: report upstream (a human
  files it), carry a fix here, both, or leave it. The reason goes with each
  decision.
- Every carried fix has a check that fails without it, and an entry in
  `pkgs/AGENTS.md` saying when it can be dropped.
- Everything left to upstream is listed with its upstream link (or "not
  filed"), so #1305 can close without losing track of anything.

## Affected users and systems

- Everyone on the stock Omarchy menu, which is the default
  (`programs.nixarchy.menu.default = "omarchy"`), on both channels. Bugs 9 and
  10 affect stable only.
- Users with their own extension file (bugs 3 and 4). Nixi's installer writes
  a row into that file as well.
- Scripts that call `omarchy-menu-select`, `-input` or `-images` (bug 2): upstream's
  own menu commands use them to ask a question.
- `pkgs/omarchy/default.nix`, and on edge, the `edge` branch's own carries
  (the #1278 design).
- nixarchy-menu and nixi, through their own copy of `MenuModel.js`.
- **#1301 also changes `MenuModel.js`** (its pacman guards and the ignored
  `disabled` field). Two carried changes to one file have to agree, so they
  need coordinating before either spec.

## Constraints

- **§11: never file upstream unprompted.** A human files, or approves the
  exact text first. That includes commenting on #9031 or #15519. Search
  `omacom/omarchy`, not the old `basecamp` name, which `gh search` refuses.
- **A carried fix is re-applied at every source bump.** A fix that lands
  upstream arrives for free. So carry one only when the harm while waiting
  justifies the upkeep.
- **§1/§2: a carried fix needs a check that fails without it**, at the cheapest
  layer that can see the bug. That cost differs: `MenuModel.js` is plain
  functions, while `Menu.qml` and the wait loops need a running shell.
- Stable and edge are fixed separately. Edge already has 9 and 10, so a
  stable-only carry for those is dropped at the next stable bump past 4.0.4.
- Mode A: changing nothing outside the menu files leaves it untouched.

## Open questions

1. **Per bug: report upstream, carry a fix, both, or leave it?** The evidence:
   - **1 (right arrow powers off).** The most severe, not known upstream, and
     probably a small fix. Candidate for **both**: carry it now and report it.
   - **2 (hung caller).** Severe, and any ordinary menu open triggers it.
     Upstream PR #9031 fixes it and is still open. Carry it, or wait for #9031?
   - **3, 4 (extension file silently mangled or ignored).** Not known
     upstream. Nixarchy's own rows are already protected from 3, and only
     users' own files are exposed. Report, carry, or both?
   - **5 (early summon).** Upstream PR #15519 is open. Leave it to upstream?
   - **6 (summon ignores `when`).** Not known upstream. A bug, or a choice?
     `when` often means "is this available" rather than "is this safe".
     Report only?
   - **7 (one shell for every guard).** Latent, and quattro narrows only part
     of it. Leave it, or report it?
   - **8 (search ancestors).** Closer to a feature request. Leave it, or post
     it in upstream's Discussions?
   - **9, 10.** Already fixed upstream and on edge. Carry on stable until the
     next stable bump, or leave them?
2. **Who files upstream, and in what form?** One report per bug, or one
   grouped issue? This intent assumes a human files from text an agent
   drafts and the human approves.
3. **#1301 coordination.** Does #1301's `MenuModel.js` change land first, with
   this rebased on it, or are the two specs written together?
4. **Should a carried `MenuModel.js` fix also reach nixarchy-menu and nixi?**
   Both read the unpatched file from the `omarchy` input. Should they share
   the fix, or does it stop at the stock menu?
