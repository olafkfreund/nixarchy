---
status: approved
issue: 1155
spec: spec/2026-10-02-1155-panel-loaders-kept.md
---

# Plan: a plugin change rebuilds only the panels it changed

## Approved decisions (self-contained)

- **Carry upstream's fix.** Carry omacom/omarchy@0066ea216b (#13439), its
  `shell/shell.qml` part only, as `pkgs/omarchy/1155-panel-loaders-kept.patch`.
  Apply it with `--fuzz=0`, right after the tree copy and **before** every
  `substituteInPlace` in `pkgs/omarchy/default.nix`. It applies cleanly to
  v4.0.4 and on top of #1153's backport (measured 2026-10-02).
- **Retire part B of the #901 patch** (the `panelOld`/`panelNew` substitution
  and the `samePanelEntries` helper). **Keep part A** (`enabledPluginSignature`
  and the `cfgOld`/`cfgNew` substitution in `onShellConfigChanged`).
- **Checks:**
  - a new cheap `checks.panel-loaders`, which carries its own negative control;
  - a `checks.session` symptom assertion, honestly labelled if its break run
    stays green;
  - a p620 hand count: 62 `Panel.qml` duplicates after the 08:20 restart on
    2026-10-02, and 0 expected after.
- **#958: note the link only.** It stays closed.

## Repo traps that apply throughout

- **Formatter hook:** after editing any `.nix` file, run `nix fmt`, then
  `git diff --stat` (§5). Then run `statix check .` and `deadnix --fail .` on
  the whole tree, reading their exit status.
- **Untracked files:** `git add` every new file before evaluating.
- **Build tiers (§6):**
  - cheap checks run one at a time under
    `flock /mnt/data/vmtest/codex-build.lock`;
  - `.#omarchy` waits for load < 12 and no p620 system build;
  - `checks.session` runs in CI only.
- **No heredoc inside `installPhase`:** the phase is one `''…''` string, which
  is why the existing blocks use `printf '%s\n'`.
- **The install-phase budget:** `checks.install-phase-budget` fails above
  123,000 bytes. This change should *free* about 900 bytes; measure it.
- **#1153 overlaps:** it also patches `shell.qml` and adds a `patch` line at
  the same place. Whichever merges second rebases, puts its `patch` line
  directly after the other's, and rebuilds `.#omarchy` (§9).
- **Work in this worktree** (`/mnt/data/vmtest/wt-1155`, branch
  `fix/1155-panel-loaders-kept`), never in the main checkout: that one is on
  #1153's branch.

## Steps

1. **The patch: `pkgs/omarchy/1155-panel-loaders-kept.patch` (new);
   `pkgs/omarchy/default.nix:422-424`.**
   - Generate it with
     `git -C /mnt/data/vmtest/owe/omarchy show 0066ea216b -- shell/shell.qml`.
     Keep only the diff, from `diff --git` onwards.
   - Prepend a comment header saying:
     - "CARRIED, upstream omacom/omarchy@0066ea216b (#13439)";
     - why it applies first;
     - "Deleted by the quattro bump, which already has it".
   - In `default.nix`, directly after the line
     `rm -rf $out/share/omarchy/{.git,.github,docs,manual,test,plans,agents}`
     (`:424`) and before the first `substituteInPlace`, add:
     ```
     # CARRIED (#1155): upstream's per-entry panel sync. Applied first so the
     # #901 part-A edits below target the patched text.
     patch -d "$out/share/omarchy" -p1 --forward --fuzz=0 < ${./1155-panel-loaders-kept.patch}
     ```
   - **Verify:** do not build yet. Step 2 must land with this, because part B's
     `--replace-fail` now fails by design. Instead check that it applies:
     `git -C /mnt/data/vmtest/owe/omarchy apply --check` against v4.0.4, using
     a temporary detached checkout, as the spec measured.

2. **Retire part B: `pkgs/omarchy/default.nix:1889-1962` (on `main`'s
   numbering).**
   - In `helpersNew` (`:1890`), delete the `samePanelEntries` lines: the two
     comment lines `// Same manifest OBJECT…` and `// manifest objects…`, the
     function (`:1906-1916`), and the blank `""` after it. Keep
     `enabledPluginSignature` and the final `"$helpersAnchor"`. Change the
     comment above (`# The two helpers, before computePanelEntries`) to "The
     helper".
   - Delete the part B block whole: from its comment
     `# B: never replace an identical panel list…` through
     `substituteInPlace "$shellQml" --replace-fail "$panelOld" "$panelNew"`
     (`:1949-1962` or thereabouts; find it by content, not by line number).
   - Leave the part A block (`cfgOld`/`cfgNew`) untouched.
   - **Verify:**
     - `nix build .#omarchy -L` (package tier) builds;
     - the build log shows `patching file shell/shell.qml` for the 1155 patch;
     - `grep -c 'panelEntryModel' result/share/omarchy/shell/shell.qml` is at
       least 3;
     - `grep -c 'panelEntries' result/share/omarchy/shell/shell.qml` is 0;
     - `grep -c 'enabledPluginSignature' result/share/omarchy/shell/shell.qml`
       is at least 2.
   - **Traps:** `nix fmt` must not reflow the `printf` blocks. Check
     `git diff --stat` shows only the expected lines.

3. **Notes and budget: `pkgs/AGENTS.md:703-718`.**
   - Rewrite the #901 section's "Two causes, one per patch below" paragraph.
     The first cause (any save fans out `pluginsChanged()`) is still fixed by
     part A. The second (a fresh JS array rebuilds every panel) is now fixed
     by carrying upstream's #13439 (#1155), and part B is retired. Keep the
     drop condition for part A.
   - Add a short `## Panel loaders survive a plugin change (#1155)` section
     beside it covering: what the patch is, why it applies first, the p620
     numbers, the #958 link (noted, not claimed), and "deleted by the quattro
     bump".
   - **Verify (cheap tier, one at a time):**
     `nix build .#checks.x86_64-linux.install-phase-budget --no-link -L`
     (record the new byte count; it should drop), then `.bin-ledger` (no row
     expected: `shell.qml` is not under `bin/`), then `.patched-files`.

4. **`checks.panel-loaders`: `tests/panel-loaders.nix` (new); `flake.nix`, beside
   `manifest-has-kind` (`:2270`).**
   - **Arguments:** `{ pkgs, omarchy, omarchySrc }`, like
     `tests/manifest-has-kind.nix`.
   - **What it runs:** a `pkgs.runCommand` that runs a small `python3` script
     (in its own file, `tests/panel-loaders.py`, so there is no heredoc) on a
     `shell.qml` path. The script asserts, with a message per failure:
     1. `Instantiator {` followed by `model: panelEntryModel` (regex, DOTALL),
        and the string `panelEntries` not present;
     2. the keep-condition
        `next.kind === row.entryKind && next.keepLoaded === row.keepLoaded && next.sourceUrl === row.sourceUrl`
        followed by `delete wanted[row.pluginId]`;
     3. inside `function unloadPanels() {…}`, `panelEntryModel.clear()`;
     4. `function enabledPluginSignature()` present, so part A survived.

     It exits non-zero on any failure.
   - **Negative control in the same check, after
     `checks.shell-restart-race`'s pattern:** run the script against
     `${omarchySrc}/shell/shell.qml`, upstream v4.0.4 unpatched, and **require
     it to fail.** Then run it against
     `${omarchy}/share/omarchy/shell/shell.qml` and require it to pass. Each
     run therefore proves the check can still fail. Capture the exit status
     with `if python3 … ; then …`, not a pipe.
   - **Wiring:** add `panel-loaders = import ./tests/panel-loaders.nix { … };`
     beside `manifest-has-kind`, with the same arguments. CI runs a new check
     automatically (§4); no workflow edit.
   - **Verify (cheap tier):**
     `nix build .#checks.x86_64-linux.panel-loaders --no-link -L` is green, and
     its log shows the control failing as required.
   - **§1:** temporarily point the positive run at `omarchySrc` as well, show
     the check go red, and revert with a scratch copy, not `git checkout --`.
     Paste the red output in the PR.

5. **The symptom in `checks.session`: `tests/session.nix`.**
   - Find where the session first settles after login, and any existing
     `omarchy-restart-shell` (grep the file). Add a block
     `# ---- panel loaders (#1155) ----` that:
     1. records a journal cursor (`journalctl --user --show-cursor -n 0` or the
        `-b` timestamp approach the file already uses), runs
        `omarchy-restart-shell` as the user, and waits for
        `omarchy-shell shell ping` to answer `ok`;
     2. waits a fixed settling window, as a polling loop of about 20 s for the
        journal to go quiet, not a bare sleep;
     3. reads the shell's journal **since the cursor** into a variable, and
        asserts that no line contains `another handler is registered` together
        with a path ending in `/Panel.qml`, `/Menu.qml` or a manifest overlay
        entry. Print the count per path either way.
   - Bar widgets are excluded on purpose (one per monitor is legitimate), with
     a comment saying so.
   - **Verify:**
     - `nix build .#checks.x86_64-linux.session.driver --no-link` (lint and
       typecheck, package tier);
     - the full run is CI's.
   - **§1 and §3:** the PR records a CI run with the 1155 `patch` line removed.
     If it goes red, the assertion is proven. If not, the PR says so, and the
     block's comment is edited to call it a tripwire, not a detector.
     `checks.panel-loaders` carries the proof.

6. **PR.**
   - Run `nix fmt -- --ci`, statix and deadnix.
   - Check `git merge-base origin/main HEAD` and `git show --stat` (§5).
   - **The body:**
     - links intent, spec and plan;
     - pastes the step 4 red output and the step 5 break-run result;
     - gives the install-phase byte count before and after;
     - notes the #958 link without claiming a fix;
     - uses `closes #1155`;
     - contains no skip-CI marker;
     - says which steps the coder did.
   - **After merge, on p620:** log in again (Hyprland still has the old tree),
     restart the shell, and count `Panel.qml` duplicates in the journal since
     the restart. Comment the number on #1155.

## Tests

| step | command | expected |
|---|---|---|
| 1 | `git apply --check` against v4.0.4 | clean |
| 2 | `nix build .#omarchy -L`, plus the greps | builds; `panelEntries` gone; part A present |
| 3 | `checks.{install-phase-budget,bin-ledger,patched-files}`, one at a time | green; budget figure drops |
| 4 | `checks.panel-loaders` | green; the control fails inside it; the §1 inversion is red |
| 5 | session driver build; `checks.session` in CI | lint green; CI green; break run reported |
| 6 | p620 hand count | 0 `Panel.qml` duplicates after a restart |

## Rollback

Revert the squash commit. That restores part B and removes the patch and the
check together. Nothing persists on any machine.

## Correction (2026-10-02, owner-approved: carry it, corrected)

The p620 evidence quoted above is **bar widgets, not panels**. In nixarchy's
plugins (`nixarchy.podman`, `.microvm`, `.devenv`), `Panel.qml` is
`entryPoints.barWidget`. Bar widgets are loaded by `syncPluginWidgets`, not the
panel `Instantiator`, so this change does not touch them. Counted after the
08:20 restart, every duplicate on p620 was a bar widget (`Panel.qml` 45,
`BarWidget.qml` 11, and three others twice each), and none was a panel, menu
or overlay. They most likely come from one bar per monitor, a separate
question.

This is carried on upstream's own evidence instead: two OSDs at once in 1 of 5
busy runs before #13439, and 0 of 10 after. It also retires our #901 part B
and frees about 2.3 KB of the install phase.

Consequences for the plan:
- the `checks.session` block watches the panel, menu and overlay entry points
  read from every installed manifest, never bar widgets, and must include
  `Osd.qml`;
- it requires a real line from the restarted shell, not only the marker;
- the p620 "62 → 0" hand count is dropped, because it measured bar widgets.
