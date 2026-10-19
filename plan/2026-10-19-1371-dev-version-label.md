---
status: draft
issue: 1371
spec: spec/2026-10-19-1371-dev-version-label.md
---

# Plan: a dev machine reports the Omarchy commit it is running

Approved decisions, carried from the spec:

- A pure function, `pkgs/omarchy/version-label.nix`, returns the literal
  `version` when the `omarchy` input's `rev` equals nixarchy's own pinned rev
  (`rev != null`), and otherwise `dev-<YYYYMMDD>-<shortRev>`. A missing date
  or shortRev reads `unknown`, so it never throws.
- The pinned rev comes from nixarchy's own `flake.lock`
  (`ownLock.nodes.${ownLock.nodes.root.inputs.omarchy}.locked.rev or null`).
- `flake.nix` changes only at the Omarchy package's call site (line 911)
  and beside `nixarchyRev` (line 630). Line 537, the `omarchyVersion`
  literal that differs on edge, is not touched. `omarchy-nvim-config` keeps
  `omarchyVersion`.
- A new evaluation check, `checks.omarchy-version-label`: the function's
  cases, plus the wiring (the flake's own `omarchy.version` equals
  `omarchyVersion`).
- Three files, so the `coder` agent does steps 1-3 and the lead does step 4.

## Steps

1. **`pkgs/omarchy/version-label.nix`**, the function exactly as in the
   spec, with its two-line comment. `input.lastModifiedDate` looks like
   `20261019180000`, so `builtins.substring 0 8` gives `20261019`. A missing
   value gives `"unknown"`, whose substring 0 8 is `unknown`.
   → verify: `nix eval --expr` with three inputs (a matching rev, another
   rev, `{ }`).

2. **`flake.nix`:**
   - after line 630 (`nixarchyRev = …`), add
     `ownLock = builtins.fromJSON (builtins.readFile ./flake.lock);` with a
     one-line comment ("nixarchy's own pins, which a consumer's overrides
     never change (#1371)");
   - line 911, `version = omarchyVersion;`, becomes the `import
     ./pkgs/omarchy/version-label.nix { version = omarchyVersion; pinnedRev = …; input = omarchy; }`
     call from the spec;
   - register the check beside `appimage-extract` (line 2475):
     `omarchy-version-label = import ./tests/omarchy-version-label.nix { pkgs = pkgsFor.${system}; omarchy = self.packages.${system}.omarchy; inherit omarchyVersion; };`
   → verify: `nix fmt`, `git diff --stat`, and
   `nix eval --raw .#omarchy.version` prints `4.0.5`.
   Traps: `omarchy` at line 911 is the flake input (the `outputs` argument,
   line 488), not the package. Check that `ownLock` is in scope where it is
   used (the same `let` as `nixarchyRev`).

3. **`tests/omarchy-version-label.nix`**:
   `{ pkgs, omarchy, omarchyVersion }:`. Import `../pkgs/omarchy/version-label.nix`,
   then `pkgs.lib.assertMsg` each spec case, each message naming the case:
   - a matching rev gives the literal;
   - `{ rev = "b…"; lastModifiedDate = "20261019180000"; shortRev = "2d3aa60"; }`
     gives `dev-20261019-2d3aa60`;
   - `{ }` gives `dev-unknown-unknown`;
   - `pinnedRev = null`, `{ }` does not give the literal;
   - wiring: `omarchy.version == omarchyVersion`.

   End with `pkgs.runCommand "nixarchy-omarchy-version-label" { } "touch $out"`.
   → verify: `git add -A`, then
   `nix eval --raw .#checks.x86_64-linux.omarchy-version-label.drvPath`
   (the asserts run here).

4. **Lead: prove and ship** (evaluation, under the lock):
   - Green: the check's drvPath evaluates, and `nix eval --raw .#omarchy.version`
     is `4.0.5`.
   - Red 1: the function always returns `version`, so case 2's message fires.
   - Red 2: `pinnedRev = null` at the call site, so the wiring message fires.
   - Restore from HEAD after committing (§5).
   - Real override:
     `nix eval --raw .#omarchy.version --override-input omarchy git+file:///<scratch quattro clone with one extra commit>?ref=quattro`
     prints `dev-<date>-<that shortRev>`. The clone goes under
     `/mnt/data/vmtest`, and is removed afterwards.
   - Edge: a `git worktree add --detach` of `origin/edge-candidate` with this
     branch merged must be **conflict-free**. There, `.#omarchy.version` is
     `edge-20261019-81fd2d2` and the check evaluates.
   - Commit, open the PR with `Closes #1371`, and set auto-merge.

## Tests

The check's five assertions; red for both breaks; the override printing
`dev-…`; edge's label unchanged.

## Rollback

Revert the commit. Every channel goes back to the literal label.
