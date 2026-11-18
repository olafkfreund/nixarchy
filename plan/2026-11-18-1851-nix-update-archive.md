---
status: draft
issue: 1851
spec: spec/2026-11-18-1851-nix-update-archive.md
coders:
  1: coder   # copy a prototype file into place; no logic to invent
  2: coder   # mechanical: one let-binding and 20 identical call-site renames in flake.nix
  3: codex   # small, tricky shell: private store, fixture flake, wiring assertion
  4: coder   # prose in two docs files
reviewers:
  - codex    # independent read of the diff against this plan (agy is out of use, #2748)
---

# Plan: `nix run .#update` can bump a version again

Approved decisions, carried from the spec so this file stands alone:

- Patch nix-update 1.16.0 so `get_flake_store_path`
  (`nix_update/options.py`) runs `nix flake archive` (same `cwd`,
  `capture_output=True`, **`check=False`**) immediately **before** its
  existing `nix flake metadata --json` call. The `metadata` call stays, so
  subdirectory handling is unchanged, and a failed archive falls through to
  today's behaviour.
- Only our updaters get the patched copy: `nixarchy-apps` in `flake.nix` is
  built with `final.newScope { nix-update = <patched>; }`. `final.nix-update`
  (what a Mode A user's `pkgs` has) is untouched, and every app's `outPath`
  is unchanged; 15 updateScripts change (all but `once` and `hey-cli`).
- #1775's pre-copy in the `update` app is removed.
- New `checks.nix-update-archive` runs a real offline version-and-hash bump
  with the binary the updaters actually use, and fails if any nix-update
  updater uses a different one.
- The `owe` 0.2.16 and `checkmate` 0.1.3 bumps ride in this PR, one commit
  each. Upstream report is filed (Mic92/nix-update#693).

Worktree: `/mnt/data/vmtest/wt-1849`, branch `fix/1851-nix-update-archive`.
Prototypes (patch, check) are in
`/tmp/claude-1000/-mnt-code-Source-home-nixarchy/54f7e9a8-2f53-4161-bf14-8fad36cebad2/scratchpad/nu/`
(`nix-update-archive.patch`, `e2e.nix`).

## Steps

1. **`pkgs/nix-update-archive.patch`** (new): the prototype patch, with its
   headers rewritten to `a/nix_update/options.py` / `b/nix_update/options.py`
   and no timestamps. Its comment names #1851 and says `check=False` keeps
   `metadata` answering if archiving fails.
   → verify: `nix build --impure --expr` applying it to the flake's
   `nix-update` with `overrideAttrs` builds (the patch applies).
   Traps: `git add` the file before any flake evaluation (§5: an untracked
   file "does not exist").

2. **`flake.nix:1228`** `nixarchy-apps = {` becomes
   `nixarchy-apps = let callPackage = final.newScope { nix-update = final.nix-update.overrideAttrs (o: { patches = (o.patches or [ ]) ++ [ ./pkgs/nix-update-archive.patch ]; }); }; in {`,
   with a one-line `# Why: docs/internals/flake.md#nix-run-update-rewrites-the-pinned-versions-and-ha`
   above the binding. Replace each of the 20 `final.callPackage ./pkgs/apps/`
   inside that set with `callPackage ./pkgs/apps/`, titlebars' explicit
   argument set kept as is.
   **`flake.nix:1652-1654`**: delete the two-line comment and
   `nix flake archive . >/dev/null || return 1`. Then grep the app's `text`
   for `nix `; nothing else calls it, so drop `nix` from that app's
   `runtimeInputs` (each updateScript brings its own).
   → verify (Mode A): run this from the worktree on the committed baseline
   (before the edit) and again after it, then `diff` the two outputs; the
   diff must be empty, and `nu` must equal nixpkgs' own
   `nix-update.outPath`:
   ```bash
   env -u NIXPKGS_ALLOW_UNFREE -u NIXPKGS_ALLOW_INSECURE nix eval --json --impure --expr \
     'let f = builtins.getFlake (toString ./.);
          p = import f.inputs.nixpkgs { system = "x86_64-linux"; overlays = [ f.overlays.default ]; config.allowUnfree = true; };
      in { apps = builtins.mapAttrs (_: v: v.outPath) (removeAttrs p.nixarchy-apps [ "zen-browser" ]);
           nu = p.nix-update.outPath; }'
   ```
   Comparing across the edit is valid here, unlike closures in general
   (§5), because no app closure contains the source tree's own store path.
   Traps: the `env -u` above, because `--impure` honours the shell's unfree
   variables (§1); `nix fmt` then read
   `git diff --stat` (§5: a hook may have run nixpkgs-fmt).

3. **`tests/nix-update-archive.nix`** (new) and its wiring in `flake.nix`'s
   `checks` next to `update-app` (`flake.nix:2808`):
   `nix-update-archive = import ./tests/nix-update-archive.nix { pkgs = pkgsFor.${system}; };`
   (the check reads `pkgs.nixarchy-apps`). Port `e2e.nix` from the
   scratchpad, with these changes:
   - no `builtins.getFlake` and no absolute path;
   - the binary under test is read at build time from
     `lib.getExe pkgs.nixarchy-apps.checkmate.updateScript`'s script (the
     `/nix/store/…-nix-update-…/bin` on its PATH line);
   - for every member of `nixarchy-apps` with an `updateScript` whose script
     names a `nix-update` path, assert it is that same path; on mismatch,
     print the member's name and exit 1;
   - keep the `nix flake archive` of the clean tree before running
     `nix-update --flake demo --version 2.0` (it reproduces CI's state);
   - fail unless `flake.nix` then holds `"2.0"` and no placeholder hash.
   Header comment: what it proves, and what it cannot (network version
   discovery; subdirectory flakes), 3 lines.
   → verify: builds and passes. **§1 proof, two breaks**, each confirmed
   landed with `git diff` before building, each reverted with
   `git checkout HEAD -- flake.nix` (not the index, §5) after committing
   steps 1–3 as a baseline:
   (a) drop the `patches` line: fails with `failed to retrieve hash`;
   (b) call `checkmate` with `final.callPackage`: fails naming checkmate.
   Save both outputs for the PR.
   Traps: build the evaluated `.drv` (`nix eval --raw
   .#checks.x86_64-linux.nix-update-archive.drvPath`, then
   `nix build '<drv>^*'`), not by attribute, so a background evaluation
   cannot build a stale tree (§5); no heredoc in a `''` string (§5, use
   `printf`); `''${` to escape interpolation; check `nix build`'s exit
   status, not its last line.

4. **`docs/internals/flake.md`** under
   `### nix run .#update` (line 1184): a short paragraph naming the patch,
   why (`flake metadata` on nix 2.35 does not write a dirty tree), the
   upstream issue, and that it is deleted once the patch stops applying.
   **`pkgs/AGENTS.md`**: one row or line for `pkgs/nix-update-archive.patch`
   where it lists carried patches, marked as reported upstream.
   → verify: `nix build .#checks.x86_64-linux.docs-lists` if it covers
   these files; `grep -n nix-update-archive docs/internals/flake.md pkgs/AGENTS.md`.
   Traps: none.

5. **Bumps** (session): `nix run .#update` in the worktree. Expect
   `pkgs/apps/owe.nix` 0.2.16 and `pkgs/apps/checkmate.nix` 0.1.3 with new
   hashes, exit 0. Build `.#owe` and `.#checkmate`. Commit each file alone:
   "Bump owe to 0.2.16" / "Bump checkmate to 0.1.3". If upstream has moved
   further by then, take what the updater writes and say so in the PR.
   Traps: package tier for these builds (§6 gates).

## Tests

All under `flock /mnt/data/vmtest/codex-build.lock`, by §6 tier, in bash:

- `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
  `nix run nixpkgs#deadnix -- --fail .`
- `checks.nix-update-archive` (pass, plus the two §1 failures)
- `checks.update-app`, `checks.grep-q-pipefail`
- every target `.github/scripts/generated-checks.sh` prints that this
  change reaches (cheap ones now; package tier when the gate is free)
- Mode A JSON diff from step 2: empty
- `nix run .#update` exits 0 with the two bumps

Not run locally: `update.yml` itself (hosted, nightly). After merge, the
next nightly run is the confirmation, and #1849's `update.yml` row clears.

## Rollback

Revert the PR. The patch, scope and check go together; the bumps are
separate commits and can stay or go on their own. Nothing reaches a user's
system closure, so there is nothing to roll back on any host.
