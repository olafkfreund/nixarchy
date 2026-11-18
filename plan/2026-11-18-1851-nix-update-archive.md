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
Everything the prototypes established is written out below, so nothing
here depends on the scratch directory they were built in.

## Steps

1. **`pkgs/nix-update-archive.patch`** (new), against nix-update 1.16.0:
   ```diff
   --- a/nix_update/options.py
   +++ b/nix_update/options.py
   @@ -108,6 +108,15 @@
        fails (e.g. the directory is not a flake).
        """
        try:
   +        # nixarchy #1851: nix 2.35's `flake metadata` reports a dirty tree's
   +        # store path without writing it; `flake archive` writes it. Not
   +        # check=True: if archiving fails, metadata still answers as before.
   +        subprocess.run(
   +            ["nix", "flake", "archive"],
   +            cwd=import_path,
   +            capture_output=True,
   +            check=False,
   +        )
            result = subprocess.run(
                ["nix", "flake", "metadata", "--json"],
                cwd=import_path,
   ```
   Generate it with `diff -u` from a copy of the 1.16.0 source rather than
   typing it, so the hunk header and context are exact.
   → verify: `nix build --impure --expr` applying it to the flake's
   `nix-update` with `overrideAttrs` builds (the patch applies).
   Traps: `git add` the file before any flake evaluation (§5: an untracked
   file "does not exist"). The same applies to step 3's new file.

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
   diff must be empty, and `nu` must equal `stock`, nixpkgs' own
   `nix-update` imported with no overlay:
   ```bash
   env -u NIXPKGS_ALLOW_UNFREE -u NIXPKGS_ALLOW_INSECURE nix eval --json --impure --expr \
     'let f = builtins.getFlake (toString ./.);
          p = import f.inputs.nixpkgs { system = "x86_64-linux"; overlays = [ f.overlays.default ]; config.allowUnfree = true; };
      in { apps = builtins.mapAttrs (_: v: v.outPath) (removeAttrs p.nixarchy-apps [ "zen-browser" ]);
           nu = p.nix-update.outPath;
           stock = (import f.inputs.nixpkgs { system = "x86_64-linux"; }).nix-update.outPath; }'
   ```
   Capture "before" on the baseline commit, before step 5 changes any
   version. Comparing across the edit is valid here, unlike closures in general
   (§5), because no app closure contains the source tree's own store path.
   Traps: the `env -u` above, because `--impure` honours the shell's unfree
   variables (§1); `nix fmt` then read
   `git diff --stat` (§5: a hook may have run nixpkgs-fmt).

3. **`tests/nix-update-archive.nix`** (new) and its wiring in `flake.nix`'s
   `checks` next to `update-app` (`flake.nix:2808`):
   `nix-update-archive = import ./tests/nix-update-archive.nix { pkgs = pkgsFor.${system}; };`
   (the check reads `pkgs.nixarchy-apps`). A `runCommand` with
   `nativeBuildInputs = [ pkgs.git pkgs.nix ]` and nix-update NOT among
   them, because the binary under test comes from the updaters:

   - **Wiring.** Pass the updaters in as a manifest built by interpolation,
     so their scripts are build inputs: one line per member of
     `pkgs.nixarchy-apps` that has an `updateScript`, `<name> ${lib.getExe
     p.updateScript}`. In the builder, for each line read the script's
     `export PATH="…"` line (line 6 of a writeShellApplication script today;
     match the line, not its number) and pull out entries matching
     `/nix/store/*-nix-update-*/bin`. checkmate is the reference: it must
     yield **exactly one**, or the check fails saying so. Every other member
     whose script runs `nix-update` must yield the same path; on mismatch
     print `<member> uses <path>; reference checkmate uses <path>` and exit
     1. A member whose script runs `nix-update` but yields no path fails too;
     only `once` and `hey-cli`, which do not run it, are skipped.
   - **Store.** `export HOME=$TMPDIR/home XDG_CACHE_HOME=$TMPDIR/cache`,
     `NIX_REMOTE="local?root=$TMPDIR/root"`, and `NIX_CONFIG` with
     `experimental-features = nix-command flakes`, `sandbox = false` and an
     empty `substituters =`, written with `printf`, not a heredoc (§5).
   - **Fixture**, written with `printf '%s\n'` (each `${` escaped as
     `''${`), then `git init`, `git add`, and a commit:
     ```nix
     { outputs = _: { packages.x86_64-linux.demo = let
       version = "1.0";
       src = derivation { name = "demo-src-${version}"; system = "x86_64-linux"; builder = "/bin/sh";
         args = [ "-c" "echo ${version} > $out" ]; outputHashMode = "flat"; outputHashAlgo = "sha256";
         outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; };
       in { inherit version src; name = "demo-${version}"; type = "derivation"; }; }; }
     ```
     The source's content follows its version, so a version change needs a
     new hash exactly as a real release does, offline.
   - **Run.** `nix flake archive >/dev/null` on the clean tree (this is
     CI's state, and #1775's step), then
     `"$ref/nix-update" --flake demo --version 2.0`, **not piped and not
     `|| true`**: a non-zero exit fails the check. Then require that
     `flake.nix` holds `"2.0"` and no longer holds the placeholder hash.
     Prototyped results: stock fails with `UpdateError: failed to retrieve
     hash when trying to update demo.src` / `opening file
     "/nix/store/…-source": No such file or directory`; patched prints
     `Update 1.0 -> 2.0` and passes.
   Header comment: what it proves, and what it cannot (network version
   discovery; subdirectory flakes), 3 lines.
   → verify: builds and passes; save that log. **§1 proof, two breaks**,
   each confirmed landed with `git diff` and then in the evaluated
   derivation (`nix derivation show <drv>` grepped for the change) before
   building, each reverted with
   `git checkout HEAD -- flake.nix` (not the index, §5) after committing
   steps 1–3 as a baseline:
   (a) drop the `patches` line: fails with `failed to retrieve hash`;
   (b) call `checkmate` with `final.callPackage`: fails with a line naming
   both a member and checkmate.
   All three outputs (pass, a, b) go in the PR.
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
- every target `.github/scripts/generated-checks.sh` prints, plus the
  claimed checks whose files this touches (`update-app` and the `options-*`
  shards, since `flake.nix` changes), each at its §6 tier: cheap ones now
  under the lock, package tier when its gate is free, options shards and VM
  checks only when no self-hosted runner is busy
- Mode A JSON diff from step 2: empty
- `nix run .#update` exits 0 with the two bumps

Not run locally: `update.yml` itself (hosted, nightly). After merge, the
next nightly run is the confirmation, and #1849's `update.yml` row clears.

## Rollback

Revert the PR. The patch, scope and check go together; the bumps are
separate commits and can stay or go on their own. Nothing reaches a user's
system closure, so there is nothing to roll back on any host.
