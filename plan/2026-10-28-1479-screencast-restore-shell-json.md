---
status: approved
issue: 1479
spec: spec/2026-10-28-1479-screencast-restore-shell-json.md
---

# Plan: screencast-restore puts each widget back where it was

Implementer: the `coder` agent. Steps 1–5 edit five files. The lead does step 6, reviews, and
runs step 7 with the user.

## Approved decisions (from the spec, so this file stands alone)

- **Cause (decided).** Restore re-enables every hidden plugin with
  `omarchy plugin enable "$id" right`, which appends it to the end of the right section. Prep
  never recorded where a widget was. Disabling removes the widget object with its settings
  (omafob lost `showRing`). `enable` also moves a widget that is already on the bar, so a re-run
  shuffles again. No timing change helps.
- **Approach (decided).** Keep prep's hide-by-disabling and fix restore. A shell "recording mode"
  is out of scope.
- **Through the shell's IPC only.** Never write `shell.json` under a running shell
  (`modules/AGENTS.md:1027`, `:1603`).
- **Prep records** `{id, section, index, widget}` for every bar-widget instance of each id it is
  about to hide. It reads them from the snapshot's `.bar.layout` and keeps the whole widget
  object with its settings. They go into `manifest.json` as `placement`. Bar-kind plugins
  (`kinds` has `bar`) have no widget and keep today's path.
- **Prep refuses** before changing anything when a hidden id appears more than once on the bar,
  and names the ids. `putBarWidget` skips an id already placed, so a second instance could not
  come back.
- **Restore places** widgets section by section in ascending `index`, with
  `omarchy-shell shell putBarWidget <id> '{"section":S,"index":I}'`. That call is idempotent: it
  leaves a widget already on the bar alone (`shell/services/PluginRegistry.qml:339`). A "not
  ready" answer (the registry is still scanning) is retried for a few seconds, then counts as a
  failure.
- **Restore puts settings back.** For every key of the recorded widget except `id`:
  `omarchy-shell shell setBarWidget <id> <key> <json-value> '{"section":S}'`.
- **Verify is unchanged:** settle, compare the checksum, then compare `jq -S`. On failure, keep
  the snapshot and print the diff. The failure message gains a line naming `screencast-recover`.
- **A manifest without `placement`** (from a take before this change) restores the old way, with
  a warning that positions may differ.
- **Rejected:** copying the snapshot over `shell.json`; stopping and restarting the shell;
  `enable --section --index` (it moves a widget already on the bar); settling longer.

## Steps

1. **New `tests/demo/screencast/placement.jq`: the pure extraction, shared by prep and the
   check.**
   - Input: the snapshot `shell.json`, with `--argjson ids '[…]'` (the ids to hide, without
     bar-kind ones).
   - Output: `{placement: [{id, section, index, widget}…], duplicates: [ids…]}`.
   - It walks the top level of every section in `.bar.layout` (left, centerBegin, center,
     centerEnd, tray, right). `index` is the position within that section.
   - Widgets nested inside another widget's `widgets` (a folder) are not separate records: they
     come back with their folder's `widgets` setting.
   - Verify: `jq -n -f tests/demo/screencast/placement.jq --argjson ids '[]' < fixture`
     → `{"placement":[],"duplicates":[]}`. Step 4 checks it properly.
   - Traps: a plain `.jq` file, not a heredoc inside a Nix string. A heredoc reindents the whole
     file under nixfmt (CLAUDE.md §5, #802).

2. **`tests/demo/screencast/default.nix`, prep (`:215`–`:240`): record and refuse.**
   - After `disabled.json` is written (`:234`), run `placement.jq` on `$state/shell.json` with
     the non-bar ids from `disabled.json`. Reference the file as `${./placement.jq}`.
   - If `duplicates` isn't empty: print the ids, remove the state dir prep just created, and
     `exit 1`. This happens before the disable loop at `:242`, so nothing has changed yet.
   - Add `placement` to the `manifest.json` that `jq -n` builds (`--slurpfile`).
   - Verify: `nix build .#checks.x86_64-linux.screencast-placement --print-build-logs` (step 4),
     then `nix fmt -- --ci`.
   - Traps:
     - `writeShellApplication` runs shellcheck, so quote everything.
     - `jq` is already in `common` (`:60`). Add nothing to `runtimeInputs` unless it's missing.
     - Escape `${` in bash as `''${` inside the Nix string, as the file already does.
- Deviation (implemented): on a duplicate-id refusal prep removes only the files it wrote and
  then `rmdir`s `$state`, instead of `rm -rf "$state"`, so it can never delete anything it
  did not write.


3. **`tests/demo/screencast/default.nix`, restore (`:286`–`:298` and `:333`): place, then
   set.**
   - If the manifest has `placement`:
     - bar-kind ids keep the current `omarchy plugin enable "$id"` line;
     - for the rest, iterate `placement` sorted by `[section, index]`. Call `putBarWidget`, with
       up to 10 retries 0.5s apart while it answers `not ready`. Then call `setBarWidget` for
       each key except `id`, passing the value as `jq -c` JSON.
     - Any answer other than `ok`: print `  (could not restore <id>: <answer>)` and carry on.
       The verify step decides the outcome.
   - Else (legacy): the current loop unchanged, after printing
     `screencast-restore: this take predates #1479; widget positions may differ.`
   - At `:333`, after `did NOT come back`, add one line naming `screencast-recover`.
   - Verify: `nix build .#checks.x86_64-linux.screencast-placement`, `nix fmt -- --ci`, and
     `nix build` of the screencast tools: `prep`, `restore` and `recover` from
     `import ./tests/demo/screencast { inherit pkgs; }`. writeShellApplication's shellcheck must
     pass.
   - Traps:
     - The IPC call is `omarchy-shell shell <fn> <args…>`, as prep already uses for
       `listPlugins`.
     - `OMARCHY_PATH` must be the running shell's tree, which `${sessionEnv}` already handles.
       Don't change that.
     - EXIT traps read globals at exit (CLAUDE.md §5).
- Deviation (implemented): `not ready` is retried up to 11 attempts 0.5s apart, and an IPC answer
  is compared to `ok` after stripping double quotes (assumed shape; the step 7 round trip shows
  any other answer in the "could not restore" line).


4. **New check `screencast-placement` (`flake.nix`, next to `shot-coverage` at `:2478`), and its
   script `tests/demo/screencast/placement-test.sh`.**
   - Following `shot-coverage`: a `runCommand` with only its inputs copied in
     (`placement.jq`, the script, the fixture), and `jq` in `nativeBuildInputs`.
   - The script asserts:
     - the p620 hide list gives the 12 records with the sections and indices from the spec's
       table, and omafob's `widget.showRing == true`;
     - an id present twice shows up in `duplicates`;
     - **idempotence:** a small jq model of `putBarWidget` (insert at index unless the id is
       already on the bar) plus `setBarWidget` turns the fixture-minus-hidden layout back into
       the fixture layout. Applying the plan a second time changes nothing;
     - a manifest without `placement` is detected as legacy.
   - Verify: `nix build .#checks.x86_64-linux.screencast-placement --print-build-logs`, and
     `statix check .` plus `deadnix --fail .`.
   - Traps:
     - Name the check in the comment block style of its neighbours (`# #1479: …`).
     - Checks are built by name; `nix flake check` isn't how this repo runs them (CLAUDE.md §6).

5. **New fixture `tests/demo/screencast/fixtures/p620-shell.json`.**
   - Built from `~/.local/state/nixarchy/screencast.kept-202610280759/shell.json`, keeping only
     `.version`, `.bar.layout` (ids and widget settings) and `.plugins`. Drop anything else (it
     may carry a location or other personal values).
   - The ids hidden on p620 that day are in `disabled.json` in the same folder. Copy that list
     into the test as a literal, not as a file.
   - Verify: `jq -e '.bar.layout' fixtures/p620-shell.json`, and a read-through: no location,
     account or path.
   - Traps: `git add` the new files before `nix build`, because flakes only see tracked files.

6. **Review (lead).** A fresh Opus reviewer gets this plan and `git diff origin/edge`. The lead
   fixes what it finds and records deviations here in the same commit as the fix.

7. **Live round trip on p620 (lead with the user; desktop control is the user's to grant).**
   - The user closes their windows; prep refuses otherwise.
   - Note the bar layout: `jq -c .bar.layout ~/.config/omarchy/shell.json > before.json`.
   - Run the branch's `screencast-prep`. The 12 plugins hide.
   - Run `screencast-restore`. It should say "byte-identical" or "equivalent", and remove the
     state dir.
   - Then `jq -c .bar.layout ~/.config/omarchy/shell.json | diff - before.json` shows nothing.
     omafob has `showRing` again, and a glance confirms the bar.
   - Run `screencast-restore` again: "nothing to restore".
   - Partial-run check: prep again, kill restore after the first `restoring` line, run
     `screencast-recover`, and expect an equivalent result.
   - If anything differs: stop, keep the snapshot, and copy it back by hand only with the
     user's go-ahead (the manual recovery used on 2026-10-28).

## Tests

| Check | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.screencast-placement` | passes (records, duplicates, idempotence, legacy) |
| `nix build .#checks.x86_64-linux.shot-coverage` | still passes |
| `nix fmt -- --ci`, `statix check .`, `deadnix --fail .` | clean |
| prep/restore/recover build (shellcheck) | passes |
| Step 7 on p620 | bar layout identical, `showRing` back, re-run is a no-op, recover after a kill is equivalent |

## Rollback

Revert the PR. Prep and restore go back to appending on the right, and the new check and
fixture disappear. Nothing on a user's machine depends on the new manifest field. A snapshot
written by the new prep still restores with the old restore, via its legacy path (it ignores
`placement`).
