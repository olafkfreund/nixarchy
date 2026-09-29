---
status: draft
issue: 1070
spec: spec/2026-09-29-1070-menumodel-path.md
---

# Plan: The menu plugins load MenuModel.js from the Omarchy they were built against

## Approved decisions

Carried over from the spec:

- **nixarchy-menu** rewrites `providers/OmarchyMenu.qml`'s MenuModel import in
  its `plugin` output, with `--replace-fail` and a `test -f`. Its `checks.plugin`
  asserts that the built file names no `/run/current-system` and that the path
  it imports exists. The release is 1.0.1.
- **nixi** gains `inputs.omarchy` (`github:basecamp/omarchy/v4.0.4`,
  `flake = false`), passed to `nix/package.nix` as `omarchySrc ? null`.
  - When `omarchySrc` is set, the import is rewritten with the same
    `--replace-fail` and `test -f`, and `installCheckPhase` asserts the rewrite.
  - When it is null, nothing changes.
- **nixarchy** bumps both pins and adds `inputs.nixi.inputs.omarchy.follows = "omarchy"`.
  `pathsToLink` stays, and its comment now says belt and braces.
  `docs/internals/flake.md` is updated.
- **Spec §4, voice-safe close:**
  - nixarchy-menu gets a `dismiss()` that is only `root.cancel()`.
    `close()` is unchanged.
  - nixarchy carries a `--replace-fail` patch on `bin/omarchy-menu`'s `close)`:
    dismiss first, then upstream's hide.
  - A stub check covers it, with a break proof.
- **Verification:**
  - `checks.session`'s #1069 probe passes with `pathsToLink` removed.
  - With the line restored, everything is green.
  - `demo-scene-menus` is green.

### Four points found while planning (decided at plan approval)

**D1: the rewrite points at an 18 KB store path, not at `${omarchy}` (a deviation from the spec's wording).**
The spec's `'file://${omarchy}'` makes the whole Omarchy source a runtime
dependency of the plugin. Measured: `/nix/store/3pyxkhsa…-source` is
**128.1 MiB**, 119 MiB of it `themes/`. It is not in an installed system's
closure today (`nix-store -q --requisites /run/current-system | grep -c 3pyxkhsa` → 0).
So the spec's text would add 128 MiB to every installed machine and to the
offline ISO.

Instead, both repositories build a one-file store path from the pinned
input and import that:

```nix
menuModel = pkgs.runCommandLocal "omarchy-menu-model" { } ''
  install -Dm444 ${omarchy}/shell/plugins/menu/MenuModel.js "$out/MenuModel.js"
'';
# import target: file://${menuModel}/MenuModel.js
```

It is the same file from the same pin, and `test -f` still guards the
source path. `MenuModel.js` has no imports of its own (no `.import`, no
`Qt.include`), so moving it alone is safe. It is not the rejected
alternative "vendoring a copy into the repository": nothing is committed,
and it cannot drift from the pin.

**D2: `omarchy-shell shell call` does NOT fail when the function is missing, so `call … || hide` never falls back.**
Read from `omarchy-1052/share/omarchy/shell/shell.qml` and `bin/omarchy-shell`:

- `IpcHandler.call(id, method, arg)` (line 1835) returns
  `shell.callIfLoaded(...)`.
- `callIfLoaded` (lines 1293–1305) returns the **string** `"unknown"` in
  three cases: no loader, no item, or `typeof item[method] !== "function"`.
  It returns `"error"` if the method throws. Otherwise it returns
  `String(result)`, or `"ok"` for `undefined` or `null`.
- `qs ipc` exits 0 for all of those. `omarchy-shell` fails (exit 1) only on:
  - a qs connection error;
  - a timeout (124/137);
  - the literal outputs `Target not found.`, `Function not found.`,
    `Too few/many arguments…` or `Not ready to accept queries yet…`.

  `Function not found.` refers to the IPC handler's own functions (`call`
  exists), never the plugin's. Otherwise it echoes the output and exits 0.

So the stock menu, which has no `dismiss`, answers `unknown` with exit 0.
The patch must **match the reply**, not the status:

```sh
if [[ $(omarchy-shell shell call omarchy.menu dismiss "{}" 2>/dev/null) == ok ]]; then exit 0; fi
exec omarchy-shell shell hide omarchy.menu
```

- The `$(…)` sits inside an `if` condition, so `set -euo pipefail` in
  `omarchy-menu` does not trip on a failing `omarchy-shell`.
- `dismiss()` returns `"ok"` explicitly rather than relying on the
  undefined-to-`"ok"` mapping.
- Behaviour matches Esc: the shell's `openPanelIds` keeps the id, which is
  what `cancel()` already leaves. `toggle` reads `isPluginOpen` from
  `item.opened`, so the next Super+Space opens normally.

**D3: nixi has no release since v0.10.0, and nixarchy pins a commit on master.**
The spec's phrase "then a release commit as usual" has no precedent. nixi's
master is its release branch (nixarchy's `flake.nix` comment above `nixi`
says so), and `manifest.json` is still `0.10.0` at `9a2e430`. So no release
commit or tag. The pin moves to the fix's merge commit on master.

**The gap is large, and approving this plan accepts it.** The pin is
`4e6c1b5`. Master is 27 merged PRs ahead (#36–#83: 178 commits, 132 of them
not merges), touching:

- `nix/package.nix` (+109/−),
- `nix/hm-module.nix` (59 lines),
- `nix/enable-card.py`,
- and the deletion of `nix/migrate-plugin-dir.sh` (#35).

The bump carries all of it. The alternative, a separate nixi-only bump PR
first, is noted under Rollback, not planned.

**D4: nixarchy-menu's "QML test" is a stage in `tests/palette_dictation_check.py`, not a new `tst_*.qml`.**
`qmltestrunner` cannot instantiate `NixarchyMenu.qml`, which is a
Quickshell `PanelWindow`. The dictation check already runs the real palette
offscreen, with a fake `VoiceSession` (`detected: true`), and default voice
settings (`enabled: true`, `secondTap: "voice"`). That is exactly the state
the spec describes, and `checks.quickshell` already runs it.

### Process, per repository

- **nixarchy-menu** (`main`; merge commits; `CODEOWNERS` = owner). There is
  no `dev` branch, although CONTRIBUTING says to target `dev`. Every recent
  PR targeted `main`.
  - Each change has an issue and `intent/`, `spec/` and `plan/` files named
    `YYYY-MM-DD-<issue>-<slug>.md`, with `docs(intent|spec|plan): draft|approve …`
    commits.
  - The release is a separate PR, `chore/release-X`, which bumps
    `manifest.json` `version` (commit `chore: nixarchy-menu X (#<issue>)`). It
    is followed by an annotated tag `vX` on the merge commit and a GitHub
    release titled `nixarchy-menu X`.
- **nixi** (`master`; merge commits). The same issue and three-file
  convention, with the same `docs(...)` commit subjects.
- **Both** get an issue and three short files that cite nixarchy's
  approved intent and spec by URL and carry this plan's steps for that repo.
  Those files are committed `status: approved`, citing this plan's approval
  commit. **Approving this plan approves them**, because nixarchy's spec
  says those repositories are "covered by reference". That is why they are
  not self-approved.
- **Merging:** the orchestrator merges each PR once it is green. The owner
  approved this cross-repository work. Nothing is posted outside the
  owner's three repositories.

### Who does what

- **[O]** is the orchestrator (Opus, the session). It does all git history
  and GitHub work: branch, worktree, commit, push, issue, PR, merge, tag,
  release.
- **[C]** is the `coder` agent (Sonnet). It edits files and runs builds. It
  may `git add` new files, because a flake sees only tracked files (§5), but
  it never commits, stashes, rebases, resets or pushes.
- For break proofs [C] copies the file aside (`cp f f.orig`), breaks it,
  runs the check, and restores it with `cp f.orig f`. It never uses
  `git checkout`, and it confirms with `diff f f.orig` that the break
  landed (§1).

### Rules for every step

- **Before any local build:**
  `gh run list -R olafkfreund/nixarchy --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
  must print `0`. This holds for builds in the other two repositories as
  well, because p620 hosts all four runners (§6). If it is not 0, wait.
  Never build "just a small one".
- **VM checks:** evaluate first, then build the pinned derivation:
  `drv=$(nix eval --raw .#checks.x86_64-linux.<name>.drvPath)`, then
  `nix build "$drv^*" -L` (§5).
- **Every `.nix` edit** is followed by the repository's formatter:
  - nixarchy: `nix fmt`, then `nix fmt -- --ci`;
  - nixarchy-menu: `nix fmt` if it defines a formatter, otherwise leave the
    style alone;
  - nixi: `nix fmt` (nixpkgs-fmt).

  Then read `git diff --stat`, because a hook may have rewritten the file (§5).
- **No heredocs** inside Nix `''` strings. Use `printf '%s\n'`.
- **Never pipe a status you need** (`set -o pipefail`). Scripts run under
  bash.
- **Commit trailers:**
  - [C]'s work, committed by [O]:
    `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` and
    `Claude-Session: https://claude.ai/code/session_017VFe59s7BspTamgenHc1P5`;
  - [O]'s own commits: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
    and the same `Claude-Session`.
- **No skip-CI marker, literal or quoted,** in any commit message or PR body
  (§8).
- nixarchy commit subjects are full sentences, with no conventional prefix.
  The other two repositories use their own style: nixarchy-menu uses
  `fix:`/`chore:`, and nixi uses plain sentences with `(#N)`.

## Steps

### A. nixarchy-menu (`olafkfreund/nixarchy-menu`)

**A1 [O]: issue, worktree, process files.**
- Create the issue:
  `gh issue create -R olafkfreund/nixarchy-menu --title "The plugin loads MenuModel.js from a build-time store path, and dismiss() closes without voice"`.
  The body links nixarchy#1070 and this plan. Call its number `<M>`.
- `git -C /mnt/data/vmtest/nm-src fetch origin && git -C /mnt/data/vmtest/nm-src worktree add /mnt/data/vmtest/wt-nm-<M> -b fix/<M>-menumodel-store-path origin/main`.
  Check the base with `git -C /mnt/data/vmtest/wt-nm-<M> merge-base origin/main HEAD` = `2cce175` (§5).
- Write `intent/`, `spec/` and `plan/2026-09-30-<M>-menumodel-store-path.md`.
  Each is short, `status: approved`, cites nixarchy#1070's intent, spec and
  this plan by GitHub URL, and names this plan's approval commit. Commit
  them as `docs(intent): approve …`, `docs(spec): approve …` and
  `docs(plan): approve … (#<M>)`.

**A2 [C]: the plugin rewrite.** Edit `flake.nix`.
- Add `menuModel` to the `packages` `let` block, after `pkgs = …`:
  ```nix
  # The one Omarchy file the plugin imports, copied out of the pinned tree:
  # referencing ${omarchy} itself would put its 128 MiB into every closure.
  menuModel = pkgs.runCommandLocal "omarchy-menu-model" { } ''
    test -f ${omarchy}/shell/plugins/menu/MenuModel.js
    install -Dm444 ${omarchy}/shell/plugins/menu/MenuModel.js "$out/MenuModel.js"
  '';
  ```
- In `plugin`'s script, after the `Session.qml` `substituteInPlace`:
  ```nix
  substituteInPlace "$out/providers/OmarchyMenu.qml" \
    --replace-fail 'file:///run/current-system/sw/share/omarchy/shell/plugins/menu/MenuModel.js' 'file://${menuModel}/MenuModel.js'
  ```
- Rewrite the comment on the `omarchy` input ("Checks only … Not a runtime
  dependency"). It now says the checks use the tree, and the plugin output
  carries one file of it (`MenuModel.js`) through `menuModel`.
- Leave `checkSrc` alone. The checks keep `file://${omarchy}`, which is
  build-time only.
- Verify: `nix build .#plugin`, then
  `grep -n 'import "file://' result/providers/OmarchyMenu.qml`, which
  shows `/nix/store/…-omarchy-menu-model/MenuModel.js`.
- Verify: `nix path-info -Sh ./result` against
  `nix path-info -Sh github:olafkfreund/nixarchy-menu/2cce175#plugin`. The
  difference is about 18 KB, not 128 MiB. Record both numbers for the PR.

**A3 [C]: the plugin-output assertion.** In `flake.nix`'s `checks.plugin`,
before `touch $out`:
```sh
if grep -n '/run/current-system' ${plugin}/providers/OmarchyMenu.qml >&2; then
  echo "OmarchyMenu.qml imports MenuModel.js from the system profile, not the build-time store path" >&2
  exit 1
fi
model=$(sed -n 's|^import "file://\(/nix/store/[^"]*/MenuModel\.js\)".*|\1|p' ${plugin}/providers/OmarchyMenu.qml)
[ -n "$model" ] && [ -f "$model" ] || { echo "OmarchyMenu.qml's MenuModel.js import does not resolve: '$model'" >&2; exit 1; }
```
Add `pkgs.gnused` to that check's `nativeBuildInputs`.
- Verify: `nix build .#checks.x86_64-linux.plugin -L` is green.

**A4 [C]: `dismiss()`.** In `NixarchyMenu.qml`, directly after `close()`
(which currently ends at line 63):
```qml
  // A scripted close: nixarchy's `omarchy menu close` calls this over IPC
  // (shell call omarchy.menu dismiss) so a script never starts dictation.
  // close() stays the hotkey's second tap, voice included.
  function dismiss(arg) { root.cancel(); return "ok" }
```
- Replace the parenthesis in the `close()` comment (lines 54–55),
  "(An explicit `omarchy menu close` takes the same path; nothing in Omarchy
  calls it.)", with: "(nixarchy's `omarchy menu close` calls dismiss()
  instead; see below.)"
- `docs/architecture.md` line 32: replace "An explicit `omarchy menu close`
  takes the same path; nothing in Omarchy calls it." with: "A script closes
  it with `omarchy-shell shell call omarchy.menu dismiss '{}'`, which never
  starts a recording; nixarchy's `omarchy menu close` does that."
- `docs/architecture.md` line 65 and `CONTRIBUTING.md` line 144: after the
  runtime URL, add ", which the Nix `plugin` output rewrites at build time
  to a store copy of the same file from the pinned Omarchy input".

**A5 [C]: the test (D4).** In `tests/palette_dictation_check.py`, in the
first `Timer`'s `onTriggered`, replace the single line
`    palette.open('{}')` with the lines below. Keep the existing `perform`
line and everything after it:
```qml
    palette.open('{}')
    palette.dismiss('{}')
    test.check(!palette.opened && palette.testVoice.phase === "idle", "dismiss() closes without starting dictation")
    palette.open('{}')
    palette.close()
    test.check(palette.opened && palette.testVoice.phase === "listening", "close() as the second tap still starts dictation")
    palette.cancel()
    test.check(!palette.opened && palette.testVoice.phase === "idle", "cancel() stops the tap's recording")
    palette.open('{}')
```
The Python string is `%`-formatted (it contains `%s`), so check that none of
the added lines contains a `%`.
- Verify: `nix build .#checks.x86_64-linux.quickshell -L` is green, and the
  log shows the dictation check's `PASS`.

**A6 [C]: break proofs** (capture each failing output for the PR):
1. Remove A2's `substituteInPlace` → `checks.plugin` fails with
   `OmarchyMenu.qml imports MenuModel.js from the system profile…`. Restore.
2. Change `dismiss`'s body to `root.close(); return "ok"` →
   `checks.quickshell` fails with `FAIL dismiss() closes without starting dictation`.
   Restore.
3. Then `nix flake check -L` is fully green (this is the repository's CI
   command).

**A7 [O]: commit, PR, merge.**
- Commit: `fix: the plugin imports MenuModel.js from a build-time store path, and dismiss() closes without voice (#<M>)`,
  with the Sonnet trailers.
- Push, then
  `gh pr create -R olafkfreund/nixarchy-menu --base main`. The body is
  "what changed and why", the commands run, both break outputs and the
  closure numbers. The template's own comment says to delete the extension
  checklist. Include `Closes #<M>`.
- Merge when `nix flake check` is green and `gh pr view --json mergeable`
  says `MERGEABLE`: `gh pr merge --merge`.

**A8 [O]: release 1.0.1.**
- Branch `chore/release-1.0.1` from the new `main`. Set `manifest.json`
  `"version": "1.0.1"`, and commit `chore: nixarchy-menu 1.0.1 (#<M>)`.
- Open the PR, merge it (`--merge`) when green, and call the merge commit
  `<MENU_REL>`.
- `git tag -a v1.0.1 <MENU_REL> -m "nixarchy-menu 1.0.1" && git push origin v1.0.1`.
- `gh release create v1.0.1 -R olafkfreund/nixarchy-menu --verify-tag --title "nixarchy-menu 1.0.1"`,
  with notes covering two points:
  - The menu loads Omarchy's `MenuModel.js` from a store path fixed at build
    time, so it works without `/share/omarchy` in the system profile, on
    Home Manager standalone, and on any Nix host.
  - `dismiss()` closes the palette from a script without starting
    dictation.

### B. nixi (`olafkfreund/nixi-nixarchy`), independent of A

**B1 [O]: issue, worktree, process files.**
- Create the issue: `gh issue create -R olafkfreund/nixi-nixarchy --title "MenuSearch loads MenuModel.js from a build-time store path"`,
  with a body that links nixarchy#1070. Call its number `<X>`.
- `git -C /mnt/data/vmtest/nixi-src worktree add /mnt/data/vmtest/wt-nixi-<X> -b fix/<X>-menumodel-store-path origin/master`.
  The merge-base must be `9a2e430`.
- Add the three approved files as in A1, with nixi's subjects:
  `docs(intent): approve …`, `docs(spec): approve …`,
  `docs(plan): approve … (#<X>)`.

**B2 [C]: `flake.nix`.**
- Add `inputs.omarchy = { url = "github:basecamp/omarchy/v4.0.4"; flake = false; };`,
  with a comment: "One file of it, MenuModel.js, is copied into the store
  at build time for MenuSearch.qml. nixarchy makes this follow its own."
- Change `outputs = { self, nixpkgs, omarchy }:`.
- Change `nixi = pkgs.callPackage ./nix/package.nix { omarchySrc = omarchy; };`.
- Then `nix flake lock`. `flake.lock` gains exactly one node, `omarchy`.

**B3 [C]: `nix/package.nix`.**
- Add these to the argument set, after `opencodeAcp ? null`:
  - `runCommandLocal`;
  - `omarchySrc ? null`, with the comment: "Omarchy's source, for
    MenuModel.js. The flake passes its pinned input; left null, MenuSearch
    keeps its /run/current-system import."
- In the `let`:
  ```nix
  # One file, not ${omarchySrc}: the tree is 128 MiB and would become a runtime dependency.
  menuModel = if omarchySrc == null then null else runCommandLocal "omarchy-menu-model" { } ''
    test -f ${omarchySrc}/shell/plugins/menu/MenuModel.js
    install -Dm444 ${omarchySrc}/shell/plugins/menu/MenuModel.js "$out/MenuModel.js"
  '';
  ```
- In `installPhase`, after the existing `substituteInPlace $plugin/MenuSearch.qml … '"node"' …`:
  ```nix
  ${lib.optionalString (menuModel != null) ''
    substituteInPlace $plugin/MenuSearch.qml \
      --replace-fail 'file:///run/current-system/sw/share/omarchy/shell/plugins/menu/MenuModel.js' 'file://${menuModel}/MenuModel.js'
  ''}
  ```
- In `installCheckPhase`, after the `for f in manifest.json Ask.qml …` loop:
  ```nix
  ${lib.optionalString (menuModel != null) ''
    if grep -n '/run/current-system' $plugin/MenuSearch.qml; then
      echo "MenuSearch.qml imports MenuModel.js from the system profile, not the build-time store path"; exit 1
    fi
    grep -qF 'file://${menuModel}/MenuModel.js' $plugin/MenuSearch.qml \
      || { echo "MenuSearch.qml does not import the build-time MenuModel.js"; exit 1; }
    test -s ${menuModel}/MenuModel.js || { echo "the build-time MenuModel.js is missing"; exit 1; }
  ''}
  ```
- Update `MenuSearch.qml` lines 18–20. The comment is nixi's own; the import
  line stays as it is. New text: "The menu LOGIC comes from the system
  profile when this file is loaded from a plain checkout; the Nix package
  rewrites the import to a store copy of the same file from its pinned
  Omarchy (nix/package.nix). A QML import cannot read OMARCHY_PATH."
- Verify: `nix build .#nixi -L` is green.
- Verify: `grep -n 'import "file://' result/share/omarchy/plugins/io.github.olafkfreund.nixi/MenuSearch.qml`
  shows the `omarchy-menu-model` path.
- Verify: `nix path-info -Sh ./result` grows by about 18 KB only.

**B4 [C]: break proof.**
- Remove B3's `installPhase` substitution. `nix build .#nixi` fails with
  `MenuSearch.qml imports MenuModel.js from the system profile…`. Capture
  it, then restore.
- Then run `nix flake check -L` and `python3 tools/test_nixi.py`, both
  green.
- `tools/test_nixi.py` asserts that no Omarchy integration point was
  renamed, and it must stay green.

**B5 [O]: commit, PR, merge.**
- Commit: `MenuSearch loads MenuModel.js from a build-time store path (#<X>)`,
  with the Sonnet trailers.
- Open the PR to `master` with nixi's template:
  - tick `nix flake check` and `tools/test_nixi.py`;
  - write "not tried on a desktop: covered by nixarchy's checks.session
    after the bump";
  - include the break output and `Fixes #<X>`.
- Merge when CI is green and the PR is mergeable (`--merge`). Call the merge
  commit `<NIXI_REL>`. There is no tag and no release (D3).

### C. nixarchy (`/mnt/data/vmtest/wt-1070`, branch `fix/1070-menumodel-path`), after A8 and B5

**C1 [O]: rebase check.** `git fetch origin`. Rebase the branch onto
`origin/main` if `main` moved: rebase, never reset, and read the pull status
(§5). Then check `git merge-base origin/main HEAD`.

**C2 [C]: the pins.** Edit `flake.nix`.
- `nixarchy-menu.url` → `github:olafkfreund/nixarchy-menu/<MENU_REL>`.
  Keep its comment.
- `nixi.url` → `github:olafkfreund/nixi-nixarchy/<NIXI_REL>`, then add
  `inputs.omarchy.follows = "omarchy";` beside the `nixpkgs` follows.
- Above `nixi`, add the register's paragraph:
  - "The previous pin, 4e6c1b5, was nixi-nixarchy#37/#43 (summon action
    "ask").
  - This one is nixi-nixarchy#<X>: MenuSearch imports MenuModel.js from a
    build-time store copy of our Omarchy (#1070), which is why `omarchy`
    follows ours.
  - It also carries nixi-nixarchy#36–#83," followed by one line per group,
    written by [O] from `git log --first-parent 4e6c1b5..<NIXI_REL>`.
- Then `nix flake lock`. **Expected lock diff:** only the `nixarchy-menu`
  and `nixi` nodes change.
  - Both nodes: `rev`, `narHash`, `lastModified`.
  - `nixi` also gains `"omarchy": ["omarchy"]` in its `inputs`.
  - No node is added or removed. Check with
    `jq '.nodes|length' flake.lock`, before and after equal.
  - Check `git diff --stat flake.lock`, and that `git diff flake.lock`
    touches only those two nodes.
  - If anything else moved, discard it and run
    `nix flake update nixi nixarchy-menu`.

**C3 [C]: the `close)` patch** in `pkgs/omarchy/default.nix`, directly after
the #953 `readyNew` `substituteInPlace` (`"$restartBin" --replace-fail "$readyOld" "$readyNew"`):
```nix
# Why: pkgs/AGENTS.md#omarchy-menu-close-never-starts-dictation-1070
menuBin=$out/share/omarchy/bin/omarchy-menu
menuCloseNew=$(printf '%s\n' \
  '# nixarchy CARRIED patch (#1070): a scripted close must not start dictation.' \
  '    # `call` answers "unknown" with exit 0 when the menu has no dismiss(), so match the reply.' \
  '    if [[ $(omarchy-shell shell call omarchy.menu dismiss "{}" 2>/dev/null) == ok ]]; then exit 0; fi' \
  '    exec omarchy-shell shell hide omarchy.menu')
substituteInPlace "$menuBin" --replace-fail 'exec omarchy-shell shell hide omarchy.menu' "$menuCloseNew"
```
Match the indentation of the neighbouring lines. The first printf line has
no leading spaces because it replaces text that already sits after 4
spaces.
- Verify: `nix build .#omarchy`, then
  `sed -n '/^  close)/,/;;/p' result/share/omarchy/bin/omarchy-menu`, then
  `bash -n` on it.
- Verify: `nix build .#checks.x86_64-linux.install-phase-budget` is green,
  since the install phase is near `MAX_ARG_STRLEN` (#997). If it is red,
  move the text to `pkgs/omarchy/menu-close-dismiss.sh` and splice it with
  `$(cat ${./menu-close-dismiss.sh})`, as `text-size-managed-guard.sh` is.

**C4 [C]: the ledger and the docs.**
- `data/bin-ledger.nix`: a new row, in alphabetical order (before
  `"omarchy-menu-timezone"`):
  ```nix
  "omarchy-menu" = {
    class = "patch";
    reason = "`close` asks the menu to dismiss() over `shell call` before falling back to upstream's `shell hide`: hide reaches the menu's close(), which nixarchy-menu turns into dictation when voice is on (the hotkey's second tap), so a script that closed the menu started a recording (#1070). `call` exits 0 with \"unknown\" when the enabled menu has no dismiss(), so the reply is matched, not the status.";
  };
  ```
- `pkgs/AGENTS.md`: a section after #953's, with the anchor
  `<a id="omarchy-menu-close-never-starts-dictation-1070"></a>` and the heading
  `### omarchy-menu close never starts dictation (#1070)`. It covers:
  - the mechanism (hide → close() → the second tap → voice), and p620
    being in that state (measured 2026-09-29);
  - the patch;
  - **the `call` reply rule** from D2: `unknown` or `error` with exit 0,
    and failure only for IPC-level errors;
  - **when to drop it:** never, unless upstream grows an explicit close
    verb distinct from hide.
- `modules/nixos.nix`, the #1069 comment above `pathsToLink`:
  "nixarchy-menu and nixi import MenuModel.js from a build-time store path
  since #1070. This link is belt and braces for anything else that assumes
  /run/current-system/sw/share/omarchy (#1069)."
- `docs/internals/flake.md`:
  - In "nixarchy-menu, on by default", rewrite **The inputs follow**: its
    `omarchy` input is also a build input of the plugin now. One file
    (`MenuModel.js`, about 18 KB) is copied into the store and imported by
    absolute path. The 128 MiB tree is not referenced (#1070).
  - The **Bumping the pin** line says a release commit is pinned (v1.0.1).
  - nixi has no section on that page; its reasoning lives in the
    `flake.nix` comment (C2). Add one sentence under nixarchy-menu:
    "nixi does the same since nixi-nixarchy#<X>, which is why
    `inputs.nixi.inputs.omarchy` follows ours."
- `tests/session.nix`, #1069's probe:
  - Replace the comment "Closed over IPC: omarchy-menu close -> shell hide
    omarchy.menu -> the enabled clone's close(), which cancels when voice is
    off (it is, here)" with "Closed over IPC: omarchy-menu close -> shell
    call omarchy.menu dismiss (#1070), falling back to hide."
  - After the close loop, add
    ```python
    reply = machine.succeed(on_desktop("omarchy-shell shell call omarchy.menu dismiss '{}'")).strip()
    assert reply == "ok", f"#1070: dismiss answered {reply!r}; omarchy-menu close would fall back to hide, and to voice"
    ```
    This is the only layer that sees the real qs output format that C3
    matches.

**C5 [C]: the stub check, `tests/menu-close.nix`.** A new file, then
`git add` it.
- Arguments: `{ pkgs, omarchy }`.
- A header comment of 5 lines or fewer, naming #1070 and D2.
- `pkgs.runCommand "nixarchy-menu-close"`, with `nativeBuildInputs` of
  `bash`, `coreutils` and `gnugrep`.
- `menu=${omarchy}/share/omarchy/bin/omarchy-menu`. The script is upstream's
  and unwrapped, so PATH stubs reach it; `[ -f "$menu" ]` or fail.
- The stub `$stubs/omarchy-shell` is written with `printf '%s\n'` (no
  heredoc). It appends `"$*"` to `$LOG`, and on `$2 == call` it prints
  `$STUB_REPLY` and exits `${STUB_STATUS:-0}`. On `hide` it exits 0.
  - Do not name the variable `REPLY`; bash reserves it.
- Three cases, each starting with `: > "$LOG"`, then
  `STUB_REPLY=… STUB_STATUS=… "$menu" close || true`, then an assertion on
  the log's exact lines. Read them with `mapfile -t lines < "$LOG"`, which
  reads a file, not a process substitution (§4).

  | case | reply | status | log must be |
  | --- | --- | --- | --- |
  | nixarchy-menu loaded | `ok` | 0 | exactly `shell call omarchy.menu dismiss {}` |
  | stock menu, no dismiss | `unknown` | 0 | `shell call …dismiss {}` then `shell hide omarchy.menu` |
  | shell not answering | `` | 1 | same two lines |
- Count the cases run, and refuse unless the count is 3. Echo
  `omarchy-menu close dismisses first and falls back to hide (#1070)`.
- `flake.nix`: an explicit entry directly after `shell-restart-race`. It
  takes `omarchy`, so it cannot go in `uniformChecks`:
  ```nix
  # #1070: `omarchy-menu close` asks the menu to dismiss before hiding it, so a
  # scripted close never starts dictation; stubs stand in for omarchy-shell.
  menu-close = import ./tests/menu-close.nix {
    pkgs = pkgsFor.${system};
    omarchy = self.packages.${system}.omarchy;
  };
  ```
  No workflow edit is needed: the generated-checks step picks it up (§4).
- `tests/AGENTS.md`: a short section, "menu-close runs the real
  omarchy-menu against a stub omarchy-shell". It says what the stub pins
  (the call-before-hide order and the reply match). It also says that
  qs's real reply format is pinned only by `checks.session` (C4).

**C6 [O]: baseline commit.** Run `nix fmt`, `nix fmt -- --ci`,
`nix run nixpkgs#statix -- check .` and `nix run nixpkgs#deadnix -- --fail .`.
Then commit: `The menu plugins load MenuModel.js from the Omarchy they were built against (wip)`,
with the Sonnet trailers. Push, so CI starts on the head.

**C7 [C]: local verification.** Check `gh run list` = 0 before each build.
1. `nix build .#checks.x86_64-linux.menu-close -L` is green, 3 cases.
2. **Break:** copy aside `pkgs/omarchy/default.nix`, remove C3's
   `substituteInPlace "$menuBin" …` line, and confirm with `diff`.
   `menu-close` must go red with the first logged line being
   `shell hide omarchy.menu`. Restore with `cp`.
3. `nix build .#checks.x86_64-linux.bin-ledger .#checks.x86_64-linux.install-phase-budget .#checks.x86_64-linux.shell-restart-race -L`
   is green. If one of them fails to evaluate, name the checks it never
   reached (§13).
4. **The #1070 proof:** copy aside `modules/nixos.nix` and delete the
   `pathsToLink = [ "/share/omarchy" ];` line. Confirm with `diff`.
   - `drv=$(nix eval --raw .#checks.x86_64-linux.session.drvPath)`, then
     `nix build "$drv^*" -L`.
   - The `summoning the menu opens one (#1069)` section must pass, and C4's
     `dismiss` reply assertion too.
   - The red counterpart is #1071's recorded run: the same break on the old
     pins failed with
     `AssertionError: #1069: omarchy-menu summon install did not open a menu`.
     Cite it rather than rerun a 20-minute VM.
   - Restore with `cp`, then `git diff --stat modules/nixos.nix` must be
     empty.
5. `drv=$(nix eval --raw .#demo-scene-menus.drvPath); nix build "$drv^*" -L`
   is green, with the gate's diversity line and no `MenuModel.js unavailable`.
   It is a package, and no workflow builds it (§4).
6. `checks.options` needs about 8 min and 11.5 GB. Run it only with CI
   idle, because the nixi bump changes hm-module (D3). The same applies to
   `nixiEnablesCard`.

**C8 [O]: finish and PR.**
- Amend the commit subject to drop `(wip)` (§8). Push, then open the PR with
  the template:
  - "Closes #1070";
  - links to the intent, spec and plan, and to nixarchy-menu#<M>/v1.0.1
    and nixi-nixarchy#<X>;
  - the D1 closure numbers;
  - the break outputs from A6, B4 and C7.2, C7.4 green with the link
    removed, and #1071's red;
  - the note that steps A2–A6, B2–B4 and C2–C5 and C7 were done by the
    coder, per the managed CLAUDE.md model split.
- Before the PR, read `#nixarchy-agents`, and post D2 (`call` exits 0 on a
  missing function) if it is not already there. Redact per §9.
- Merge when all required checks are green and `gh pr view --json mergeable`
  says `MERGEABLE`. Confirm #1070 closed.

## Tests

| Command | Expected |
| --- | --- |
| nixarchy-menu `nix build .#checks.x86_64-linux.plugin` | green; red naming `/run/current-system` with A2's substitution removed |
| nixarchy-menu `nix build .#checks.x86_64-linux.quickshell` | green; red `FAIL dismiss() closes without starting dictation` when dismiss calls close() |
| nixarchy-menu `nix flake check` | green |
| nixarchy-menu `nix path-info -Sh .#plugin` vs 1.0.0 | +~18 KB, not +128 MiB |
| nixi `nix build .#nixi` | green; red "imports MenuModel.js from the system profile" with the substitution removed |
| nixi `nix flake check`, `python3 tools/test_nixi.py` | green |
| nixarchy `flake.lock` diff | only the `nixarchy-menu` and `nixi` nodes; node count unchanged |
| `checks.menu-close` | green, 3 cases; red (hide first) with C3 removed |
| `checks.bin-ledger`, `install-phase-budget`, `shell-restart-race` | green |
| `checks.session` with `pathsToLink` removed, pinned drv | the #1069 section passes; dismiss replies `ok` |
| `checks.session` on CI with the line restored | green |
| `.#demo-scene-menus` | green, no `MenuModel.js unavailable` |
| `checks.options` (CI, or locally when idle) | green |

## Rollback

- **nixarchy:** revert the squash commit. The pins return to `2cce175` and
  `4e6c1b5`, `close)` returns to upstream's hide, and `pathsToLink` (never
  removed) keeps the menu loading.
- **nixarchy-menu 1.0.1 and nixi `<NIXI_REL>`** stay published and do no
  harm: a store import works everywhere the runtime path did.
- **If the nixi bump itself causes the trouble (D3):** revert to `4e6c1b5`,
  and land a nixi-only bump to `9a2e430` first, as its own PR. Then redo C2
  for nixi alone.
