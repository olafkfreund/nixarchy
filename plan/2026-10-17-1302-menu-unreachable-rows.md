---
status: draft
issue: 1302
spec: spec/2026-10-17-1302-menu-unreachable-rows.md
---

# Plan: Every generated menu row is reachable by browsing, and a check says so

Worktree `/mnt/data/vmtest/wt-1302`, branch `fix/1302-menu-unreachable-rows`,
based on `origin/main` 7e0ceac5. Line numbers are as of that commit, and
earlier steps' insertions shift later ones, by about 9 lines in
`modules/apps.nix` after steps 1-2 and 1 line in `tests/menu-verbs.nix` after
4b. Always locate an edit by its quoted anchor text; the number is a hint.

**Precondition: do not start step 1 unless both of these hold:**
- `git log -1 --format=%s -- plan/2026-10-17-1302-menu-unreachable-rows.md`
  starts with `docs(plan): approve`;
- this file's frontmatter says `status: approved`.

Then `git status --short` must print nothing. If it prints anything, stop
and report rather than building on an unknown tree.

## What was decided (carried over from the approved spec)

Both menus resolve rows through the same upstream code:
- the stock `omarchy.menu`;
- the `nixarchy.menu` replacement, which imports the stock `MenuModel.js`.

That code is `MenuModel.js` in the omarchy tree:
- **Parent:** an explicit `parent` if the row has the key, otherwise the id
  minus its last dotted segment, otherwise `root`.
- **Kind:** `action` if the row has an `action`, else `link` if it has a
  `target`, else `menu`.
- **Summon:** `omarchy menu summon <word>` lowercases the word and maps `_`
  to `-`. `go` and `menu` mean `root`. An exact row id wins. Otherwise the
  first row in file order that declares the word as an alias wins. `when` is
  ignored.

When browsing, a screen lists the rows whose parent is its id. Choosing a
`menu` row opens the screen with its id, and a `link` row opens its `target`.

The approved decisions:

1. **Flatpak rows get an `install.flatpak` submenu row** ("Flatpak", icon
   `󰏓`, no `action`, no `when`). It is emitted only when `data/flatpaks.nix`
   is non-empty. No id is renamed. It has the same shape as upstream's
   `install.service` ("Service").
2. **`backup`, `restore` and `rollback` summon the recovery rows.**
   - `trigger.ask.backup` loses the aliases `backup` and `restore`, and
     keeps `back up`, `save` and `copy`.
   - `trigger.ask.update` loses `rollback`.
   - `system.recovery.rollback` gains `aliases = [ "rollback" ]`.
   - `system.recovery` already declares `backup` and `restore`.
   - `nixarchy-rollback` asks which generation and then `gum confirm`s, so
     nothing switches on the summon alone.
   - Every other shared or shadowed alias stays, pinned in the check's
     table.
   - Making `resolveRoute` skip hidden rows is upstream code, so it is not
     done here (§11, #1305).
3. **`menu.extraEntries` gets documentation, not a warning.**
   - Its example becomes `personal` plus `personal.notes`, matching
     `docs/manual/dotfiles.md:58-61`, which is already right.
   - Its description drops the false "Upstream reads a single extension
     file, so nixarchy manages it".
   - It states the two rules: the parent is the id minus its last segment
     unless `parent` is set, and the parent must exist; a row with an
     `action` cannot have children.
   - The `capture.*` rows on p620 live in the owner's `/etc/nixos`, outside
     this repo, and are not touched here.
4. **One check covers both menus,** because both use `MenuModel.js`.
5. **#1302 closes on this PR,** with a comment. The comment says claim 1 was
   a resolver false positive (the restore rows set an explicit `parent`),
   and that the `capture.*` rows and the `toggle`/`nixpkgs`/`options`
   collisions are host-local.
6. **The check lives inside `checks.menu-verbs`** (`tests/menu-verbs.nix`)
   as a new script, `tests/menu-tree.py`. This reuses that check's
   evaluation of the reference configuration plus boxes and devenv.
   `omarchy-edge.yml:239` already runs `menu-verbs`, so no workflow is
   edited.
7. **The check tests itself on mutated copies of the real menu**, before the
   real run: `install.flatpak` deleted, the restore row's `parent` deleted,
   `backup` added back to `trigger.ask.backup`. Each copy must fail with its
   message. A rule that stops firing then fails every build.

The check's rules:
- **Reachability walk** from `root`. Every row not listed on a reachable
  screen fails, with one of three causes:
  - `orphan`: the parent is not a row;
  - `under an action`: the parent has an `action`;
  - `unreachable`: anything else, such as a cycle or a link.
- **Aliases:** an alias two or more distinct rows declare, or one whose
  winner is not one of its declarers (an exact id or `go`/`menu` takes it
  first), must be in the `EXPECTED` table with its winner. Table entries
  that no row declares fail too.
- **Refusal:** the script refuses to pass on fewer than 200 rows or no
  `install` row.
- `when` and `disabled` are ignored. They are #1301's and #1303's.

Out of scope, and documented in step 6:
- a single-owner alias pointing at the wrong row (the old `rollback` shape);
- the user's own extension file;
- users' `extraEntries`.

**Coexistence (§14).** `extraEntries` rows and the user's extension file
override by id. That is the documented contract. Neither is a NixOS option
merge, so there is no fixture for `tests/coexistence/fixtures.nix`.

**Coordination.** #1303 edits the `when` of `system.recovery.snapshot*`
(`modules/apps.nix:560-594`), next to step 2's hunk at `:545-550`. Whichever
lands second rebases and keeps the other's change (step 7).

**Deviations from the spec:**

- **Message wording.** The spec's Verification section wrote the cycle
  failure as one line, `unreachable: install.flatpak,
  install.flatpak.geforce-now`. Its alias failure read
  `alias backup: declared by …; not in the expected table`. The script in
  step 4 differs in two ways:
  - It prints **one line per unreachable row**, each with its parent:
    `unreachable: install.flatpak (parent install.flatpak)`.
  - Its alias lines add **`resolves to X;`**, as in
    `alias backup: declared by trigger.ask.backup, system.recovery; resolves to trigger.ask.backup; not in the expected table`.

  The plan's text is what ships. Step 5's table and the PR use it.
- The manual already shows the correct two-row example, so
  `docs/manual/dotfiles.md` is not edited.

## Build rules for every step

- **Cheap work** (`nix eval`, `nix fmt`, statix, deadnix, and the script run
  directly with `python3 -I`) may run at any time, one at a time, under
  `flock /mnt/data/vmtest/codex-build.lock <cmd>`.
- **`checks.menu-verbs`** builds the `omarchy` tree once
  `pkgs/omarchy/default.nix` changes, so it is the package tier. Before each
  build, confirm both of these:
  - `pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'` prints `0`;
  - `cut -d' ' -f1 /proc/loadavg` is below 12.

  Then evaluate first and build the `.drv`, never the attribute path (§5):
  ```bash
  drv=$(nix eval --raw .#checks.x86_64-linux.menu-verbs.drvPath)
  flock /mnt/data/vmtest/codex-build.lock nix build "$drv^*" --print-build-logs --no-link
  ```
- **No VM checks and no `checks.options`.** Leave those to CI.
- **After every `.nix` edit,** run `nix fmt`, then `git diff --stat`. The
  editor hook may have reformatted the whole file with nixpkgs-fmt. If the
  stat shows far more lines than you changed, `nix fmt` has reverted the
  hook; read `git diff` before committing.
- **No heredoc inside a Nix `''` string.** In Nix `''` strings, a bash `${`
  is written `''${`.
- **New files must be `git add`ed** before any `nix eval` or `nix build` can
  see them (§5).
- **Commit each step** when its verification passes. Use a sentence subject,
  with no conventional-commit prefix (§8), ending with the trailer
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Steps

1. **`modules/apps.nix:909-921`: add the Flatpak submenu row.** The flatpak
   block is:
   ```nix
         # Why: modules/AGENTS.md#the-services-catalogue-as-menu-rows
         // lib.listToAttrs (
           lib.mapAttrsToList (
             name: fp:
             lib.nameValuePair "install.flatpak.${name}" {
             ...
           ) flatpakCatalogue
         )
   ```
   Line 920 is `) flatpakCatalogue` and line 921 is the block's closing
   `)`. Directly after line 921, and before line 922
   (`// lib.listToAttrs (`, the service catalogue), insert:
   ```nix
         # The Flatpak rows' parent: without it every one is an orphan,
         # reachable only by search (#1302).
         // lib.optionalAttrs (flatpakCatalogue != { }) {
           "install.flatpak" = {
             icon = "󰏓";
             label = "Flatpak";
           };
         }
   ```
   Copy the icon glyph from line 914 (`icon = "󰏓";`) byte for byte; do not
   retype it.

   → Verify:
   - `nix eval --raw .#nixosConfigurations.reference.config.environment.etc.'"nixarchy/omarchy-menu.jsonc"'.source.drvPath`
     prints a `/nix/store/…-nixarchy-omarchy-menu.jsonc.drv` path. This
     forces the evaluation of the whole menu row set, the new row included,
     which `system.name` would not.
   - `grep -n '"install.flatpak" = {' modules/apps.nix` shows exactly one
     line.
   - The row's presence in the generated menu is proved by step 4's check.
     Reading the generated file at eval time would be a build.

   Traps: `nix fmt`, then `git diff --stat` (hook).

2. **Aliases.**
   - `pkgs/omarchy/default.nix:150` (`trigger.ask.update`): replace
     `"generation","rollback"]` with `"generation"]`.
   - `pkgs/omarchy/default.nix:151` (`trigger.ask.backup`): replace
     `"aliases":["backup","back up","save","copy","restore"]` with
     `"aliases":["back up","save","copy"]`.
   - `modules/apps.nix:545-550` (`"system.recovery.rollback" = {`): after
     the `label = "Roll back";` line, add `aliases = [ "rollback" ];`.

   Both `default.nix` lines sit inside a JSON text in a Nix string, so edit
   only the quoted text shown. Use exact-string edits, not regex.

   → Verify:
   - `test "$(grep -c '"generation","rollback"' pkgs/omarchy/default.nix)" = 0`
     exits 0. (`grep -c` itself exits 1 on zero matches, so test the
     count, not grep's status.)
   - `grep -c '"aliases":\["back up","save","copy"\]' pkgs/omarchy/default.nix`
     prints `1`.
   - `grep -n 'aliases = \[ "rollback" \]' modules/apps.nix` shows one line
     between 545 and 552.

   Traps: `nix fmt`, then `git diff --stat`. If #1303 has merged meanwhile,
   its hunk at `:560-594` is adjacent: keep both.

3. **`modules/apps.nix:1200-1213`: the `menu.extraEntries` example and
   description.**
   - Replace the `example` body (line 1204) with the two rows from
     `docs/manual/dotfiles.md:59-60`, copied byte for byte (the icons are
     glyphs), in Nix attrset form:
     ```nix
             {
               "personal" = { icon = ""; label = "Personal"; };
               "personal.notes" = { icon = "󰎞"; label = "Notes"; action = "omarchy-launch-editor ~/notes"; };
             }
     ```
   - Replace the `description` body (lines 1207-1212) with:
     ```
             Extra rows merged into the menu defaults nixarchy generates, keyed
             by dotted id. Reuse an existing id to override it. Your own
             ~/.config/omarchy/extensions/omarchy-menu.jsonc is untouched and
             still overrides anything here by id.

             A row's parent is its id minus the last dotted segment unless it
             sets `parent`, and the parent has to be a row too: `personal.notes`
             needs a `personal` row, or it can only be found by search. A row
             with an `action` runs it rather than opening, so it cannot have
             children.
     ```

   → Verify:
   `nix eval --raw .#nixosConfigurations.reference.options.programs.nixarchy.menu.extraEntries.description`
   prints the new text. If it does not, find the right path with
   `nix eval .#nixosConfigurations.reference.options.programs.nixarchy.menu --apply builtins.attrNames`.
   Also run `grep -rn "single extension file" modules docs`, which must
   print nothing.

   Traps: `nix fmt`, then `git diff --stat`. The `example` is a
   `literalExpression ''…''`, so the new text must not contain `''` or `${`.

4. **The check: create `tests/menu-tree.py` and run it from
   `tests/menu-verbs.nix`.**

   a. Create `tests/menu-tree.py` with exactly this content:
   ```python
   """Every generated menu row is reachable by browsing, and every shared alias
   summons the row it was meant to (#1302).

   Applies MenuModel.js's rules (normalizeItem, resolveRoute) and Menu.qml's
   browse rule (a screen lists rows whose parent is its id; a menu row opens its
   id, a link row opens its target) to the generated defaults file. `when` and
   `disabled` are runtime visibility and are deliberately ignored.
   """

   import json
   import re
   import sys

   # alias -> the row `omarchy menu summon <alias>` must open. An alias two rows
   # declare, or one an exact id (or go/menu) takes first, must be listed here.
   EXPECTED = {
       "ai": "trigger.ask",
       "app": "apps",
       "ask": "trigger.ask.anything",
       "connect": "setup.remote.connect",
       "gliff": "setup.remote.gliff",
       "help": "help",
       "install": "install",
       "rdp": "setup.remote",
       "remote": "setup.remote",
       "update": "update",
       "why": "trigger.ask.logs",
   }

   raw = open(sys.argv[1]).read()
   # The same two transformations MenuModel.js applies to the JSONC.
   raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
   menu = json.loads(re.sub(r",(\s*[}\]])", r"\1", raw))
   rows = {k: v for k, v in menu.items() if isinstance(v, dict)}

   # Refuse rather than pass on a parse that found next to nothing.
   if len(rows) < 200 or "install" not in rows:
       sys.exit(f"menu tree: parsed {len(rows)} rows (no 'install'?); refusing rather than passing")


   def parent_of(row_id, row):
       if row_id == "root":
           return ""
       if "parent" in row:  # MenuModel.js: value.parent !== undefined
           return row["parent"]
       return row_id.rsplit(".", 1)[0] if "." in row_id else "root"


   def kind_of(row):
       return "action" if row.get("action") else ("link" if row.get("target") else "menu")


   children = {}
   for row_id, row in rows.items():
       children.setdefault(parent_of(row_id, row), []).append(row_id)

   # Walk the screens a user can open, starting at root.
   seen_screens, listed, todo = set(), set(), ["root"]
   while todo:
       screen = todo.pop()
       if screen in seen_screens:
           continue
       seen_screens.add(screen)
       for child in children.get(screen, []):
           listed.add(child)
           kind = kind_of(rows[child])
           if kind == "menu":
               todo.append(child)
           elif kind == "link":
               todo.append(rows[child]["target"])

   errors = []
   for row_id, row in rows.items():
       if row_id == "root" or row_id in listed:
           continue
       parent = parent_of(row_id, row)
       if parent != "root" and parent not in rows:
           errors.append(f"orphan: {row_id} (parent {parent} is not a row)")
       elif parent in rows and kind_of(rows[parent]) == "action":
           errors.append(f"under an action: {row_id} (parent {parent} has an action)")
       else:
           errors.append(f"unreachable: {row_id} (parent {parent})")


   def norm(alias):
       return str(alias or "").lower().replace("_", "-")


   def aliases_of(row):
       a = row.get("aliases")
       return [x for x in (a if isinstance(a, list) else [a]) if x]


   def resolve(word):  # MenuModel.js resolveRoute
       if not word or word in ("go", "menu"):
           return "root"
       if word in rows:
           return word
       for row_id, row in rows.items():
           if word in map(norm, aliases_of(row)):
               return row_id
       return word


   declared = {}
   for row_id, row in rows.items():
       for alias in aliases_of(row):
           owners = declared.setdefault(norm(alias), [])
           if row_id not in owners:
               owners.append(row_id)

   for alias, owners in declared.items():
       winner = resolve(alias)
       shared = len(owners) > 1 or winner not in owners
       if alias in EXPECTED:
           if winner != EXPECTED[alias]:
               errors.append(f"alias {alias}: resolves to {winner}, expected {EXPECTED[alias]}")
       elif shared:
           errors.append(
               f"alias {alias}: declared by {', '.join(owners)}; resolves to {winner}; "
               "not in the expected table"
           )
   for alias in EXPECTED:
       if alias not in declared:
           errors.append(f"alias {alias}: in the expected table but no row declares it")

   if errors:
       print("\n".join(errors), file=sys.stderr)
       sys.exit(1)
   print(f"menu tree: {len(rows)} rows, all reachable; {len(EXPECTED)} shared or shadowed aliases as expected")
   ```
   Then run `git add tests/menu-tree.py`.

   b. In `tests/menu-verbs.nix:74-78`, add `pkgs.python3` to
   `nativeBuildInputs`, after `pkgs.jq`.

   c. In `tests/menu-verbs.nix`, immediately before the line
   `    test "$fail" -eq 0` (line 375), insert the block below. It is bash
   inside the Nix `''` string: no heredoc, and `${menu}` and
   `${./menu-tree.py}` are Nix interpolations on purpose.
   ```bash
       # #1302: every row reachable by browsing, every shared alias pinned.
       # The rules are proved to fire on copies of this menu before the real
       # run, so a rule that stops firing fails every build (tests/AGENTS.md).
       sed '/^\/\//d' ${menu} > menu.json
       tree_selftest() {
         jq "$1" menu.json > broken.json
         if python3 -I ${./menu-tree.py} broken.json 2> tree.err; then
           echo "ERROR: menu-tree.py passed a menu with $2 ($1)" >&2
           exit 1
         fi
         grep -qF "$3" tree.err || {
           echo "ERROR: menu-tree.py failed on $2 without saying '$3':" >&2
           cat tree.err >&2
           exit 1
         }
       }
       tree_selftest 'del(.["install.flatpak"])' "an orphan" \
         "orphan: install.flatpak.geforce-now"
       tree_selftest 'del(.["system.recovery.home-backup.restore"].parent)' "a row under an action" \
         "under an action: system.recovery.home-backup.restore"
       tree_selftest '.["trigger.ask.backup"].aliases += ["backup"]' "an unpinned shared alias" \
         "alias backup:"
       python3 -I ${./menu-tree.py} ${menu} || fail=1
   ```
   The `sed` strips the generator's `//` header, as this file's `row()`
   helper already does at line 220. Do not add `|| true` anywhere in this
   block. `set -euo pipefail` is on at line 81, and the `if` and `||` forms
   above are what keep `set -e` from ending the build before the message.

   → Verify, without a build first:
   ```bash
   rc=0; python3 -I tests/menu-tree.py /etc/nixarchy/omarchy-menu.jsonc || rc=$?; echo "exit=$rc"
   ```
   This reads p620's deployed menu, which predates steps 1-2. It must print
   exactly these six lines and `exit=1`:
   ```
   orphan: capture.meet (parent capture is not a row)
   orphan: capture.note (parent capture is not a row)
   orphan: capture.upload (parent capture is not a row)
   orphan: install.flatpak.geforce-now (parent install.flatpak is not a row)
   alias backup: declared by trigger.ask.backup, system.recovery; resolves to trigger.ask.backup; not in the expected table
   alias restore: declared by trigger.ask.backup, system.recovery; resolves to trigger.ask.backup; not in the expected table
   ```
   The two restore rows must not be named. Then build `checks.menu-verbs`
   by drvPath, following the build rules above. Its log must contain
   `menu tree: N rows, all reachable; 11 shared or shadowed aliases as expected`
   (N is about 395) and `every menu row names a subcommand its CLI has`.

   **If the build fails with an alias line that p620's menu did not show**
   (`alias <word>: declared by …; resolves to <id>; not in the expected
   table`), the reference configuration (with boxes and devenv on) declares a
   shared alias the deployed machine lacks. Do not change any row for it.
   Instead:
   - Add `"<word>": "<id>"` to `EXPECTED` in `tests/menu-tree.py`, using the
     printed winner. Only do this if that winner is the obvious destination
     for the word. If it is not, stop and report.
   - Update the `11` in the summary text expected by steps 4 and 5 to match.
   - Record the entry as a deviation in this plan's **Deviations** list, in
     the same commit (managed instructions: a deviation updates `plan/` with
     the code).

   Traps:
   - `git add` the new `.py` before evaluating.
   - Run `nix fmt`, then `git diff --stat`.
   - No heredoc in the Nix string.
   - Before building, prove the evaluation used this tree's script:
     ```bash
     src=$(nix derivation show "$drv" | grep -oE '/nix/store/[a-z0-9]{32}[^"[:space:]]*menu-tree\.py' | head -1)
     test -n "$src" && diff "$src" tests/menu-tree.py && echo "drv uses the current menu-tree.py"
     ```

5. **§1 proof, in its own step.** First commit steps 1-4, so that
   `git checkout HEAD -- <path>` has a known-good baseline (§5). Then set up:
   ```bash
   P=/mnt/data/vmtest/proof-1302; mkdir -p "$P"
   base_drv=$(nix eval --raw .#checks.x86_64-linux.menu-verbs.drvPath)
   ```
   Then, one break at a time (n = 1..6):
   1. Apply the break.
   2. Confirm it landed: `git diff` must be non-empty and show the change.
   3. Run `git add -A`, because the flake sees only tracked or staged
      content.
   4. Re-evaluate, and prove the evaluation saw the break:
      ```bash
      drv=$(nix eval --raw .#checks.x86_64-linux.menu-verbs.drvPath)
      test "$drv" != "$base_drv" || { echo "STALE: the break did not change the derivation; stop and investigate" >&2; exit 1; }
      ```
      For breaks 4 and 6, which are script edits, also run step 4's `diff`
      of the drv's `menu-tree.py` against the working file.
   5. Build without a pipe, so the exit status is nix's own:
      ```bash
      rc=0
      flock /mnt/data/vmtest/codex-build.lock nix build "$drv^*" --print-build-logs --no-link > "$P/proof-$n.log" 2>&1 || rc=$?
      echo "exit=$rc" >> "$P/proof-$n.log"
      grep -F '<expected text from the table>' "$P/proof-$n.log"; tail -1 "$P/proof-$n.log"
      ```
      Expect the expected text present and a non-zero `exit=`. Row 5 has two
      expected lines: run one `grep -F` per line.
   6. Restore with `git checkout HEAD -- <path>` (never `git checkout --`,
      which restores the staged break).
   7. Confirm `git status --short` is empty.

   After the last break, re-evaluate. The drvPath must equal `$base_drv`;
   build it and expect green.

   | n | break | expected failing text |
   |---|---|---|
   | 1 | `modules/apps.nix`: delete the `install.flatpak` block from step 1 | `orphan: install.flatpak.geforce-now (parent install.flatpak is not a row)` |
   | 2 | `modules/apps.nix`: delete `parent = "system.recovery";` from `"system.recovery.home-backup.restore"` | `under an action: system.recovery.home-backup.restore (parent system.recovery.home-backup has an action)` |
   | 3 | `pkgs/omarchy/default.nix:151`: put `"backup",` back first in `trigger.ask.backup`'s aliases | `alias backup: declared by trigger.ask.backup, system.recovery; resolves to trigger.ask.backup; not in the expected table` |
   | 4 | `tests/menu-tree.py`: change `"why": "trigger.ask.logs"` to `"why": "trigger.ask.gpu"` | `alias why: resolves to trigger.ask.logs, expected trigger.ask.gpu` |
   | 5 | `modules/apps.nix`: add `parent = "install.flatpak";` to the `"install.flatpak"` row | `unreachable: install.flatpak.geforce-now (parent install.flatpak)` and `unreachable: install.flatpak (parent install.flatpak)` |

   Breaks 1-3 fail at the real run, after the self-tests pass. Break 1 also
   makes the first self-test's mutation a no-op, and the self-test still
   passes because the copy is broken either way. Break 4 fails at the real
   run.

   A sixth proof is for the self-test itself. In `tests/menu-tree.py`,
   change the `orphan` message's text to `missing parent:`. The build must
   fail with:
   ```
   ERROR: menu-tree.py failed on an orphan without saying 'orphan: install.flatpak.geforce-now':
   ```
   Restore it the same way.

   Simulated before writing this plan: breaks 1, 2, 3 and 5 applied with
   `jq` to a fixed copy of p620's menu produced exactly the texts above, and
   the fixed copy printed
   `menu tree: 396 rows, all reachable; 11 shared or shadowed aliases as expected`.

   → Verify: `$P/proof-1.log` … `proof-6.log` each hold their expected text
   and `exit=1`. The final build is green, and `git status --short` is
   empty. No commit comes out of
   this step.

   Traps:
   - `git checkout HEAD --`, not `--` (§5).
   - Prove each break landed before reading a green result (§1).
   - Evaluate the drvPath fresh for each break. Never reuse a background
     build (§5).

6. **`tests/AGENTS.md`: document the check and its holes.**

   **First, correct the existing section at `tests/AGENTS.md:770`,**
   `## Menu aliases: the words are a judgement, and nothing here checks them`.
   It is now half wrong:
   - Change the heading to
     `## Menu aliases: the words are a judgement, and only where they lead is checked`.
   - After its first paragraph (lines 772-775), add one paragraph: since
     #1302, `tests/menu-tree.py` (run by `checks.menu-verbs`) checks that
     every alias two rows share, or that an exact id shadows, summons the
     winner pinned in its `EXPECTED` table. It still says nothing about
     whether the words are the right words, which is the judgement the rest
     of the section describes.
   - Leave the rest of that section as it is.
   - Check that no other file links to the old heading's anchor:
     `grep -rn 'nothing-here-checks-them' . --exclude-dir=.git --exclude-dir=plan`
     must print nothing (this plan names the anchor itself), or each hit is updated to the new anchor.

   **Then append a new section** at the end of the file (after line ~1640; never insert one in the
   middle). Title it
   `## menu-tree: reachable by browsing, and what it cannot see (#1302)`.
   Its content, in house style (short paragraphs, no bullet soup):
   - **What it checks.** The reachability walk, and the alias table with
     named winners. It runs inside `checks.menu-verbs` so it shares that
     evaluation and runs on edge (`omarchy-edge.yml:239`).
   - **Why it tests itself.** It runs on mutated copies of the real menu
     before the real run.
   - **Why the parent rule must honour an explicit `parent`.** #1302's own
     resolver ignored it, and reported the two correct restore rows as
     unreachable.
   - **The holes:**
     - A single-owner alias pointing at the wrong row is not mechanically
       decidable. `rollback` on `trigger.ask.update` was that shape: one
       owner, wrong destination. `backup` is both a deliberate alias of
       `system.recovery` and the last segment of `system.recovery.backup`,
       so no segment rule can tell intended from accidental. Choosing a new
       alias means reading `resolveRoute` order by hand.
     - `resolveRoute` ignores `when`, so a hidden row can still win a summon
       (upstream code, #1305).
     - The user's `~/.config/omarchy/extensions/omarchy-menu.jsonc` and any
       `extraEntries` are never checked. The reference configuration has
       none.

   → Verify: `grep -n "menu-tree" tests/AGENTS.md` shows both the new
   heading and the paragraph added at ~770. `tail -5 tests/AGENTS.md` shows
   the new section is the last one. `grep -c "nothing here checks them"
   tests/AGENTS.md` prints `0`.

   Traps: append only; never renumber or insert in the middle (CLAUDE.md
   "Write back what cost you an hour").

7. **Final checks and the #1303 rebase.**
   ```bash
   git fetch origin
   git log --oneline 7e0ceac5..origin/main
   ```
   - If that lists #1303's merge, or anything touching `modules/apps.nix` or
     `pkgs/omarchy/default.nix`, run `git rebase origin/main`.
   - Resolve any conflict around `modules/apps.nix:545-594` by keeping both
     changes: #1303's `when` values and step 2's alias.
   - Afterwards, `git merge-base origin/main HEAD` must equal
     `git rev-parse origin/main`.
   - `git show --stat` on each commit must list only this plan's files (§5,
     the stale-base trap).
   - Re-run step 4's build after any rebase.

   Then run the cheap tier, under `flock`, one at a time:
   ```bash
   nix fmt -- --ci
   nix run nixpkgs#statix -- check .
   nix run nixpkgs#deadnix -- --fail .
   ! grep -rn 'summon \(backup\|restore\|rollback\)' docs tests/demo README.md
   ```
   - `nix fmt -- --ci` must exit 0. If it fails once and then passes, that
     is nixfmt reverting the hook, not flakiness (§5).
   - The `! grep` succeeds only when there is no match. It matched nothing
     at 7e0ceac5. If it matches after a rebase, update what that text says
     the word opens, and record the match and the edit in the PR rather than
     the `! grep` result.

   → Verify: all exit 0. The last commit's subject is a full sentence and not
   `wip:` (§8).

   Traps: `git pull`/`fetch` status must be read (§5, #922). Do not
   force-push a shared branch. This branch is ours, but pushing waits for
   the owner.

8. **PR (only after the owner says to push).**
   - **Title:** `Every menu row can be reached by browsing, and summon backup, restore and rollback open the recovery rows (#1302)`.
   - **Body:** follow `.github/PULL_REQUEST_TEMPLATE.md`.
     - **"What this changes, and why":** decisions 1-3, linking
       `intent/`, `spec/` and `plan/2026-10-17-1302-menu-unreachable-rows.md`.
     - **"How I proved the check fails":** the six failing outputs from
       step 5, verbatim, plus the pre-fix run against p620's menu from
       step 4.
     - **"Checks run locally":** `checks.menu-verbs` (green), `nix fmt`,
       statix and deadnix. Tick "New files are `git add`ed". Tick the
       `checks.*` box as not applicable, because no new check entry is
       added.
     - **"What this cost":** the false-positive lesson, recorded in
       `tests/AGENTS.md` (step 6).
     - Say which steps the `coder` agent did.
     - Under coordination, note the #1303 adjacency.
     - Write `closes #1302` exactly once, on its own. Never write a skip-CI
       marker in any form, even quoted (§8).
     - End with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
   - **After merge,** comment on #1302 with decision 5's text. That is
     outward-facing, so post it only when the owner confirms. Then check
     with `gh issue view 1302 --json state` that the issue closed.

   → Verify: `gh pr view <n> --json mergeable` before reporting the PR as on
   its way (§8).

## Tests

- **Script on p620's deployed menu** (step 4): the six lines listed there,
  and exit 1.
- **`checks.menu-verbs`, built from its drvPath** (steps 4 and 7): green,
  with `menu tree: … all reachable; 11 shared or shadowed aliases as
  expected`.
- **§1 proofs** (step 5): five breaks plus the self-test break, each red
  with the text in step 5's table, and green after restore.
- **`nix fmt -- --ci`, statix and deadnix:** clean.
- **CI:** `menu-verbs` runs on pull requests through `build.yml`'s existing
  claim (`flake.nix:1985`) and on edge (`omarchy-edge.yml:239`). Read the
  run log to confirm the `menu tree:` line appeared rather than assuming
  (§4).

## Rollback

Revert the PR's squash commit. All of it is data and a check:
- the submenu row and three alias lists return to today's values;
- `menu-tree.py` and its call in `menu-verbs` go away.

No state on any machine depends on it. After a revert, `summon backup`,
`summon restore` and `summon rollback` reach the Ask prompts again, and the
Flatpak rows return to search-only.
