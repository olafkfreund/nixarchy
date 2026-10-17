---
status: approved
issue: 1302
intent: intent/2026-10-17-1302-menu-unreachable-rows.md
---

# Spec: Every generated menu row is reachable by browsing, and a check says so

## Design

Three small data fixes and one new rule set in an existing check. No menu code
changes: the stock `omarchy.menu` and the `nixarchy.menu` replacement both
resolve parents and aliases through the same upstream `MenuModel.js`. Rows
reach each other through `normalizeItem`, `mergeMenuSources` and
`resolveRoute` (MenuModel.js:14-38, 176-190 in
`/nix/store/rla9km5silzbp6h9dcfz0pd1p90ia8r9-nixarchy-omarchy-tree/shell/plugins/menu/`).
nixarchy-menu imports that file by path
(`providers/OmarchyMenu.qml:5`, `:69`, `:252` in the `nixarchy-menu` input
`f3e6bce7`) and lists a screen's rows by `entry.parent !== active`
(`:402`), the same rule as Menu.qml's browse loop (`:608`). Menu.qml:589 is
the search path, which reaches any descendant and is why an orphan can still
be found by typing. So one check over the generated
file speaks for both menus.

### Changes

1. **A Flatpak submenu under Install.** `modules/apps.nix:909-920` generates
   `install.flatpak.<name>` for each entry in `data/flatpaks.nix`. Beside it,
   the same `//` chain gains one row:
   `"install.flatpak" = { icon = "󰏓"; label = "Flatpak"; };`. There is no
   `action` and no `when`. It has the same shape as upstream's
   `install.service` ("Service"), the submenu the service catalogue's rows
   already sit under. The row is emitted only when the catalogue is non-empty
   (`lib.optionalAttrs (flatpakCatalogue != { })`), so an empty catalogue does
   not leave an empty submenu.

2. **`backup`, `restore` and `rollback` summon the recovery rows.**
   - `pkgs/omarchy/default.nix:151` (`trigger.ask.backup`) loses the aliases
     `backup` and `restore`. It keeps `back up`, `save` and `copy`.
   - `:150` (`trigger.ask.update`) loses `rollback`.
   - `modules/apps.nix:545-550` (`system.recovery.rollback`) gains
     `aliases = [ "rollback" ];`.

   After this, `summon backup` and `summon restore` open Backup and recovery
   (`system.recovery`, which already declares both). `summon rollback` runs
   `nixarchy-rollback`, which asks which generation and then
   `gum confirm`s before switching. Nothing switches on the summon alone.

3. **The option's example and description stop being wrong.**
   `modules/apps.nix:1200-1213`:
   - The example becomes two rows, a `personal` submenu and its
     `personal.notes` child, so a copied example is reachable.
   - The description drops "Upstream reads a single extension file, so
     nixarchy manages it". It says what the generator header
     (`modules/apps.nix:1044-1053`) says: rows here are merged into the
     defaults file, and `~/.config/omarchy/extensions/omarchy-menu.jsonc`
     stays the user's own and overrides by id.
   - It gains one sentence: a row's parent is its id minus the last segment
     unless it sets `parent`, and a row with an `action` cannot have
     children.

4. **The tree check, inside `tests/menu-verbs.nix`.** A new script,
   `tests/menu-tree.py`, runs from `menu-verbs`' build phase against the same
   `${menu}` (the reference configuration plus boxes and devenv,
   `tests/menu-verbs.nix:28-42`). `pkgs.python3` joins that derivation's
   `nativeBuildInputs` (`tests/menu-verbs.nix:74-78`), which today holds only
   grep, sed and jq. The script applies MenuModel.js's and Menu.qml's rules to
   the generated file:
   - **Reachability walk.** Every row gets its effective parent: an explicit
     `parent`, otherwise the id minus its last segment, otherwise `root`.
     Its kind is `action` if it has an `action`, `link` if it has a
     `target`, otherwise `menu` (MenuModel.js:17-21). The walk starts with
     the screen `root`. A screen lists the rows whose parent equals its id
     (Menu.qml:608). Selecting a listed `menu` row opens the screen with its
     id, and a `link` row opens the screen named by its `target`
     (Menu.qml:733). Every row not listed on some reachable screen is
     **unreachable**. This also catches cycles and links whose children are
     stranded, which per-row rules would pass.
   - Each unreachable row's message names the cause:
     - `orphan`: the parent is not a row.
     - `under an action`: the parent has an `action`.
     - `unreachable`: anything else, such as a cycle or a link parent.
   - `when` and `disabled` are ignored. Those are runtime visibility, and a
     row hidden on this machine is still in the tree (#1301 and #1303 own
     them).
   - The walk starts at `root`, which needs no parent. MenuModel.js
     synthesises it, and gives a `"root"` row the parent `""`. A row has an
     explicit parent when its JSON object has a `parent` key, which matches
     `value.parent !== undefined`: Nix omits unset attributes.
   - **Shared or shadowed alias:** an alias (lowercased, `_` to `-`, as
     `resolveRoute` does) that two or more distinct rows declare, or whose
     `resolveRoute` winner is not one of the rows declaring it (an exact id,
     or `go`/`menu` meaning `root`, takes it first), must appear in an
     `expected` table
     inside the script, mapping alias to winning id. The script then computes
     the winner the way `resolveRoute` does (an exact id first, then the
     first declaring row in file order) and fails if the winner differs from
     the table. A shared alias missing from the table fails, and so does a
     table entry no row declares any more. The table is the deliberate list
     the intent asked for, and it names its winner, so a reorder that moves
     the winner is caught too.

   On the real menu, the script refuses rather than passes on an implausible
   parse (fewer than 200 rows, or no `install` row), the way `check-menu.py`
   and `readme-counts.sh` refuse.

   Once changes 1 and 2 have landed, the `expected` table holds today's
   deliberate sharing:
   - `ai` → `trigger.ask`
   - `app` → `apps`
   - `ask` → `trigger.ask.anything`
   - `connect` → `setup.remote.connect`
   - `gliff` → `setup.remote.gliff`
   - `help` → `help` (the exact id wins)
   - `install` → `install` (exact id; `trigger.ask.install` declares it)
   - `rdp` → `setup.remote`
   - `remote` → `setup.remote`
   - `update` → `update` (exact id; `trigger.ask.update` declares it)
   - `why` → `trigger.ask.logs`

   The two exact-id entries are dead aliases on their Ask rows for summon.
   They stay, because nixarchy-menu's search reads aliases too
   (`providers/OmarchyMenu.qml:291`).

### Decisions

1. **The Flatpak rows get an `install.flatpak` submenu row (intent question
   1).** Of the three options, this is the only one that keeps every id.
   Renaming breaks `summon install.flatpak.geforce-now` and any user override
   keyed on it. A per-row explicit `parent = "install"` would put declarative
   Flatpaks loose among Install's category submenus. A per-row
   `parent = "install.gaming"` needs a category for each catalogue entry,
   which `data/flatpaks.nix` does not carry. It would also sit the working
   GeForce NOW row beside upstream's broken `install.gaming.geforce-now`
   (#1304's) under the same label. A submenu matches how
   `install.service` already presents the service catalogue.
2. **`backup`, `restore` and `rollback` go to the recovery rows; the Ask rows
   keep the rest of their words (intent question 2).**
   - The recovery rows work on every machine. The Ask rows need a default
     agent and are hidden without one (`trigger.ask`'s `when`).
     `resolveRoute` ignores `when`, so on a machine with no agent the current
     aliases summon a row the user cannot see.
   - The other shared or shadowed aliases stay, pinned in the check's table. Each
     one's current winner is the right destination for the word, and aliases
     also feed nixarchy-menu's search (`providers/OmarchyMenu.qml:291`),
     where breadth is the point.
   - Making `resolveRoute` skip hidden rows is upstream code, so it is not
     done here (§11). It is #1305's to raise, and this spec does not depend
     on it.
3. **A user's `extraEntries` gets documentation, not a warning or a doctor
   line (intent question 3).** An evaluation-time warning has to know every
   row id, including the rows `pkgs/omarchy/default.nix` writes into the
   built tree. Reading those at evaluation is import-from-derivation, which
   this repo does not do in module code. A warning at build time, from the
   generator script, lands in a build log nobody reads. Fixing the example,
   correcting the description and stating the two rules where users write
   rows is the cheapest change that reaches the person writing one. If a
   doctor command wants this later, the check's script is the logic it would
   reuse. The capture rows on p620 are the owner's own configuration
   (`/etc/nixos/hosts/common/nixos/omarchy-gog.nix`), so they are fixed
   there, outside this repository.
4. **One check covers both menus (intent question 4).** nixarchy-menu
   parses, merges and resolves through the stock MenuModel.js (evidence
   above). If it ever forks those rules, its own repository's
   `tests/tst_menumodel.qml` is where that shows up.
5. **#1302 closes on this PR, with a comment (intent question 5).** The
   comment says that claim 1 was a resolver false positive (explicit
   `parent`), and that the capture rows and the `toggle`/`nixpkgs`/`options`
   collisions are host-local. Every in-repo defect the issue found is
   covered here, plus `rollback`, which the issue missed. Retitling an issue
   at close adds nothing.
6. **The check lives in `menu-verbs`, not a new `checks.menu-tree`.** It
   reuses `menu-verbs`' evaluation of the reference configuration, so it
   costs no second evaluation. `omarchy-edge.yml:239` already runs
   `menu-verbs` by name. A new check would run on main through the generated
   step (§4) but not on edge without a workflow edit, and that edit is a
   CI-gate change (§11). The script is its own file so it can be run against
   a fixture by hand.
7. **The script also checks itself, on copies of the real menu.** Before
   the real run, the build phase uses `jq` to write three mutated copies of
   `${menu}` and requires the script to fail on each, naming the expected id:
   - `install.flatpak` deleted: `orphan`, naming
     `install.flatpak.geforce-now`;
   - `parent` deleted from `system.recovery.home-backup.restore`:
     `under an action`;
   - `"backup"` appended to `trigger.ask.backup`'s aliases: `alias backup`.

   Mutating the real file, rather than using small inline fixtures, keeps
   the row-count floor and the alias table valid in every run. A rule that
   stops firing then fails every build, not only the one where someone
   remembered to break it (§1, §4).

### Coexistence

- **`extraEntries` rows** are merged into the defaults file by id with `//`
  (`modules/apps.nix:938`). A user row can replace `install.flatpak`, or a
  recovery row, wholesale, and could re-orphan the Flatpak rows. That is the
  documented override contract, and the check does not assert on it: the
  reference configuration has no `extraEntries`.
- **The user's extension file** is read at runtime and overrides by id
  (`mergeMenuSources`). Nothing nixarchy builds can see it, so a collision
  there (the owner's `nixpkgs`/`options` aliases, the `trigger.record`
  children) is not checked and not warned about.
- Neither of these is a NixOS option merge. No `hardware.graphics` or
  `system.path` env is touched, so §14 has no fixture to add to
  `tests/coexistence/fixtures.nix`. The answer is the corrected option
  description from change 3.

### Coordination

#1303 edits the `when` of `system.recovery.snapshot*` (`modules/apps.nix:560-594`).
This spec touches `system.recovery.rollback` (`:545-550`) and the example
(`:1200-1213`). Those are adjacent hunks, not the same lines. Whichever lands
second rebases onto the other and keeps the other's change.

## Alternatives rejected

- **A new `checks.menu-tree`:** this needs a second evaluation of the
  reference configuration and an `omarchy-edge.yml` edit to run on edge
  (decision 6).
- **Fixing the check's false-positive class away:** treating every dotted id
  as a child of its prefix, as the issue's resolver did, ignores explicit
  `parent` and would flag the two restore rows, which are correct.
- **Failing the menu generator (`modules/apps.nix:964`) on a violation:** this
  would fail a user's rebuild over their own `extraEntries` row, which the
  intent forbids. The check runs only against the reference configuration.
- **Patching `resolveRoute` to skip hidden rows:** upstream code (§11, #1305).
- **Dropping `rollback` entirely rather than giving it to
  `system.recovery.rollback`:** `summon rollback` would then try a
  non-existent id `rollback` and open nothing useful.
- **Flagging single-owner aliases that "look" like another row's id segment
  (the `rollback` shape):** there is no rule a script can apply that tells an
  intended single-owner alias from an accidental one. `backup` is both the
  last segment of `system.recovery.backup` and a deliberate alias of
  `system.recovery`. This class stays a documented hole, recorded in
  `tests/AGENTS.md` beside the other menu checks.

## Risks

- **Muscle memory:** anyone using `summon backup`, `summon restore` or
  `summon rollback` to reach the Ask prompts gets the recovery rows instead.
  The Ask rows remain in the menu and in search by label.
- **An upstream bump adds a shared alias or an orphan.** The check fails on
  the bump PR, by design. The fix is a table entry or an upstream report,
  routed per §11, not a patch.
- **Install gains a "Flatpak" entry,** which changes what every user on
  stock `omarchy.menu` sees. The same is true on nixarchy-menu.
- **Upstream may one day ship its own `install.flatpak`.** Our row overrides
  it by id, as every nixarchy row overrides upstream. The check still holds.
- **The adjacent-hunk rebase with #1303** (see Coordination).

## Verification

Cheap tier only, under `flock /mnt/data/vmtest/codex-build.lock`, one at a
time, with no VM:

- `nix build .#checks.x86_64-linux.menu-verbs --print-build-logs` passes on
  the finished branch, and its log prints the tree script's summary
  (`menu tree: N rows, all reachable; 11 shared or shadowed aliases as expected`), after
  the three self-test mutations have each failed as required.
- **The §1 proof**, from a committed baseline, reverting with
  `git checkout HEAD -- <path>` (not `git checkout --`, §5), and checking
  each break landed with `git diff` before building:
  1. **Orphan:** delete the `install.flatpak` row from `modules/apps.nix`.
     Expect a failure naming
     `orphan: install.flatpak.geforce-now (parent install.flatpak is not a row)`.
     Restore, and it passes.
  2. **Under an action:** remove `parent = "system.recovery";` from
     `system.recovery.home-backup.restore`. Expect
     `under an action: system.recovery.home-backup.restore (parent system.recovery.home-backup has an action)`.
     Restore, and it passes.
  3. **Shared alias:** put `"backup"` back into `trigger.ask.backup`'s
     aliases. Expect
     `alias backup: declared by trigger.ask.backup, system.recovery; not in the expected table`.
     Restore, and it passes.
  4. **Winner moved:** change the table's `why` entry to
     `trigger.ask.gpu`. Expect
     `alias why: resolves to trigger.ask.logs, expected trigger.ask.gpu`.
     Restore, and it passes.
  5. **Cycle:** give `install.flatpak` `parent = "install.flatpak"`, so it
     is its own parent. Every row's parent then exists and none is an action,
     so only the walk can see this. Expect
     `unreachable: install.flatpak, install.flatpak.geforce-now`. Restore,
     and it passes.

  Each failing output goes in the PR.
- **Before the data fixes (changes 1-2) land,** the script alone, run against
  `/etc/nixarchy/omarchy-menu.jsonc` on p620, reports exactly:
  - four orphans (`capture.*` ×3 and `install.flatpak.geforce-now`);
  - no other unreachable row;
  - shared aliases `backup` and `restore` not in the table.

  This proves it sees the issue's real findings and not its false positive
  (the two restore rows).
- `nix run nixpkgs#statix -- check .`, `nix run nixpkgs#deadnix -- --fail .`,
  and `nix fmt -- --ci` after `nix fmt` (§5: the editor hook reformats `.nix`
  files).
- `grep -rn 'summon backup\|summon restore\|summon rollback' docs/ tests/demo/`.
  Any document or demo scene naming these words is updated (§4's demo-scene
  trap).
