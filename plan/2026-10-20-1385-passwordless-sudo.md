---
status: draft
issue: 1385
spec: spec/2026-10-20-1385-passwordless-sudo.md
---

# Plan: Omarchy's passwordless-sudo toggle is hidden everywhere on nixarchy

Approved decisions, carried from the spec:

- **Edge** (`pkgs/omarchy/default.nix`, quattro-only section), two
  `substituteInPlace --replace-fail` edits on
  `$out/share/omarchy/shell/plugins/bar/indicators/PasswordlessSudo.qml`:
  - `  active: granted` becomes `  visible: false; active: granted`;
  - `    if (!root.bar) return` becomes `    return`.

  Each replacement is on one line, with no `''` and no `${` (§5).
- **Edge:** remove the `PasswordlessSudo` option from
  `shell/plugins/bar/widgets/Indicators.manifest.json` with `jq`
  (already in the package's inputs: `pkgs/omarchy/default.nix:21`):
  `del(.barWidget.schema[].options[]? | select(.value == "PasswordlessSudo"))`.
  Then `! grep -q PasswordlessSudo` that file, or fail the build.
- **Main** (`modules/apps.nix`): add
  `"setup.security.passwordless-sudo" = { when = "false"; };`, with edge's
  comment, in the same override set edge uses.
- `docs/manual/security.md`: the toggle is hidden on both channels, in
  the menu and the bar.
- **The check,** `checks.passwordless-sudo-hidden` (`runCommand`):
  - indicator neutered if the file exists;
  - manifest free of the option if it exists;
  - the menu row's `when` is `"false"`, read the way `tests/menu-verbs.nix`
    reads the overrides.
- The stub and its bin-ledger row are unchanged.
- **Who implements:** five files across two branches, so the `coder` agent
  does steps 1-2 and the lead does 3-4.

## Steps

1. **Coder, main** (branch `fix/1385-passwordless-sudo`):
   - the `apps.nix` row;
   - the `security.md` paragraph;
   - `tests/passwordless-sudo-hidden.nix`, registered in `flake.nix`
     beside the other cheap checks.

   The menu assertion reuses whatever `tests/menu-verbs.nix` uses to read
   the merged overrides. Read it first.
   → verify: `nix fmt`, `git diff --stat`, and evaluate the check's
   `drvPath`.
2. **Coder, edge** (`git worktree add --detach /mnt/data/vmtest/wt-edge1385 origin/edge-candidate`):
   - the two substitutions and the `jq` step in edge's quattro section,
     beside the other quattro-only edits (~line 872), with a one-line
     comment naming #1385;
   - cherry-pick step 1's commit (the check, the row and the docs), so
     edge carries the same check. Edge already has the row, so keep a
     single copy.

   → verify: `nix fmt`, `git diff --stat`.
3. **Lead: prove** (§6 tiers):
   - main: the check is green, and red with the row override removed;
   - edge (package tier): `.#omarchy` builds and the check is green; red
     with substitution 1 removed, and red with the `jq` step removed. Each
     red names its cause. Restore with `git checkout HEAD --` after a
     baseline commit;
   - edge `checks.session` when CI is idle: no QML errors.
4. **Lead: ship.**
   - Main: open the PR (`Closes #1385`), with auto-merge.
   - Edge: push to `edge-candidate` together with the pending
     #1380/#1377 candidate, so it lands in one edge run.

## Tests

- The check is green on main and edge, and red for each of the three
  breaks.
- `.#omarchy` builds on edge, and `session` is green on edge.

## Rollback

Revert the main PR and the edge-candidate commit. The icon and row come
back as before.
