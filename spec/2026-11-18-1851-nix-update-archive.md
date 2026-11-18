---
status: draft
issue: 1851
intent: intent/2026-11-18-1851-nix-update-archive.md
---

# Spec: `nix run .#update` can bump a version again

Decisions carried from the approved intent: report upstream (done:
Mic92/nix-update#693), and the `owe` and `checkmate` bumps ride in this PR as
the fix's end-to-end proof.

## Design

### 1. Patch nix-update, not the wrapper around it

New file `pkgs/nix-update-archive.patch`. It adds one call to
`get_flake_store_path` in `nix_update/options.py`, **before** the existing
`nix flake metadata --json`:

```python
        subprocess.run(
            ["nix", "flake", "archive"],
            cwd=import_path,
            capture_output=True,
            check=False,
        )
```

`archive` writes the tree into the store at the path `metadata` then reports;
measured on nix 2.35.6, the two return the same path. Keeping the `metadata`
call, rather than replacing it, keeps nix-update's subdirectory handling
(`_metadata_flake_dir` reads `locked`/`resolved`/`original`, which
`archive`'s output lacks). That is the reason the patch adds a line and does
not swap a word, which corrects the intent's guess.

A patch file, rather than `substituteInPlace`: it fails the build with a
readable reject if upstream changes those lines (the intent's
`--replace-fail` constraint), and it is what goes upstream unchanged.

`check=False`, not `True`: if archiving fails (say an input that cannot be
fetched), `metadata` still runs and answers exactly as it did before the
patch, so a failed archive degrades to today's behaviour rather than
skipping `metadata` and falling back to evaluating the raw working
directory. Codex's review found the `check=True` draft did the latter.

Cost: `nix flake archive` also copies the flake's inputs, which are already
in the store after the first evaluation. 1.5 s warm on this repository.

### 2. Only our updaters get the patched copy

`flake.nix:1228`, the `nixarchy-apps` set, becomes:

```nix
nixarchy-apps =
  let
    # Why: docs/internals/flake.md#nix-run-update-rewrites-the-pinned-versions-and-ha
    callPackage = final.newScope {
      nix-update = final.nix-update.overrideAttrs (o: {
        patches = (o.patches or [ ]) ++ [ ./pkgs/nix-update-archive.patch ];
      });
    };
  in
  { ... }
```

Every `final.callPackage ./pkgs/apps/…` inside the set becomes
`callPackage ./pkgs/apps/…`. No package file changes. Of the set's
updaters, 15 call nix-update; `once` and `hey-cli` have their own and are
unaffected (the intent's "18" counted files that mention nix-update, not
updaters).

Measured: through `newScope`, every one of the 20 package files in the set
keeps its `outPath` (Codex evaluated all 20, with titlebars' explicit
Hyprland argument; I checked checkmate), and exactly the 15 nix-update
updateScripts change. nixpkgs defines `callPackage = pkgs.newScope { }`
(`pkgs/top-level/splice.nix:120-124`), so the scope is the same one with
`nix-update` replaced. `final.nix-update`, the one a Mode A user's `pkgs`
carries, is untouched: the patched copy exists only as an argument inside
this scope.

### 3. Remove #1775's workaround

`flake.nix:1652-1654`: the comment and `nix flake archive . >/dev/null ||
return 1` go. With the patch, nix-update archives the tree itself, at the
moment it needs it. `git` and `gnugrep` stay in `runtimeInputs`; `nix` stays
too, because nothing else in the app removes the need for it (to be
re-checked in the plan by grepping the script for `nix `, and dropped if
nothing calls it).

### 4. A check that runs a real version-and-hash update with the updaters' own nix-update

New `tests/nix-update-archive.nix`, wired as `checks.nix-update-archive`,
taking `nixarchy-apps` from the flake's own `pkgsFor`. A `runCommand`, with a
private store (`NIX_REMOTE=local?root=$TMPDIR/root`, `sandbox = false`, no
substituters), so it needs no daemon and no network:

1. **Use the updaters' binary, not a copy.** At build time, read the
   nix-update path out of `checkmate.updateScript`'s script (it is a build
   input, so it and its nix-update are in the sandbox), and assert that every
   other nix-update updateScript in `nixarchy-apps` names the same path. A
   scope that stops passing the patched copy to any updater fails here,
   naming the updater.
2. **A real bump, offline.** A git flake whose package `demo` has
   `version = "1.0"` and a `src` that is a fixed-output derivation built by
   `/bin/sh` writing its version, with a placeholder hash. So a version
   change needs a new hash exactly as a real release does.
3. `nix flake archive` the clean tree first, as #1775 does and as CI's store
   effectively has, then run `nix-update --flake demo --version 2.0` with
   that binary.
4. Fail unless `flake.nix` then holds `"2.0"` **and** a hash that is not the
   placeholder.

Prototyped (with the patch applied by hand, before the wiring step):

```
stock:   nix_update.errors.UpdateError: failed to retrieve hash when trying to update demo.src
         error: opening file "/nix/store/x56j…-source": No such file or directory
         FAIL: version and hash not both updated
patched: Update 1.0 -> 2.0 … ok   (outputHash rewritten to sha256-1Sbr…)
```

The stock failure is CI's error, at the same point (the post-edit prefetch),
which is what makes it the right failure rather than any failure. Without
step 3 the stock run fails earlier, at its first evaluation, for a related
but different reason; the check keeps step 3 so it describes the real case.

Cost: evaluation, the patched nix-update's Python build, one tiny
fixed-output build. Cheap tier. A new `checks.<name>` is run on pull requests
by `generated-checks.sh` with no workflow edit (§4; `generated-checks.sh:123`).

### 5. Docs

`docs/internals/flake.md#nix-run-update-rewrites-the-pinned-versions-and-ha`
gains a short paragraph: why the patch exists, the upstream issue, and that
it should be dropped once nixpkgs ships a nix-update with the fix (the patch
then fails to apply, which is the signal). `pkgs/AGENTS.md` names the patch
in its patch list if it keeps one.

### 6. The bumps

Run the fixed `nix run .#update` in the worktree. It should rewrite
`pkgs/apps/owe.nix` (0.2.16) and `pkgs/apps/checkmate.nix` (0.1.3) with
their hashes. Build both. Each is its own commit, so either can be reverted
alone.

## Alternatives rejected

- **Keep the pre-copy and add a second one inside each updateScript.** The
  missing path is created inside nix-update, between its version edit and
  its prefetch. No wrapper outside the process can reach that moment.
- **Override `nix-update` in the overlay.** It would change the nix-update
  every Mode A user gets from our overlay, against the intent.
- **Pass `{ nix-update = …; }` at each of the 18 `callPackage` calls.** Same
  effect as the scope, 18 places to forget when an app is added.
- **Swap `metadata` for `archive`.** It loses subdirectory-flake support,
  which nix-update upstream has and other users need.
- **Run nix-update without `--flake`.** This repository has no `default.nix`
  that exposes the apps, and `--flake` is what makes nix-update read the
  flake's own nixpkgs.
- **Pin an older nix inside nix-update.** It holds back a whole nix for one
  line, and stops matching the nix the rest of the flake evaluates with.

## Risks

- **`nix flake archive` fails where `metadata` did not**, for example an
  input that cannot be fetched. With `check=False` the failure is ignored and
  `metadata` runs as before, so the outcome is today's: the path may be
  missing and the updater fails the same way it does now, and the `update`
  app reverts it and carries on (#1537). No new failure mode. On the hosted
  runner every input is fetched by the job's first evaluation anyway.
- **`archive` copies every flake input into the store** on each updater
  call. Measured at 1.5 s warm here; on a cold store it is the fetch the
  job's evaluation does anyway.
- **The patched nix-update is not in any binary cache**, so `update.yml`
  and the pull-request run of `checks.nix-update-archive` both build it (a
  small Python package, seconds). It stays off the cachix allowlist: the
  check's proof is pushed as usual, and nobody else downloads the package.
- **A future nixpkgs ships a fixed or changed nix-update.** The patch then
  fails to apply and `update.yml` goes red at build time, naming the patch,
  which is the intended signal to delete it.
- Hosts: none. This touches no system closure, so p620, p510 and users'
  machines are unaffected.

## Verification

1. §1 proof for the new check, two breaks, each landed and confirmed with
   `git diff` before building (§1, "a break that stays green may be a break
   that never applied"):
   - remove the patch from the scope's override: the check fails with
     `failed to retrieve hash … opening file`;
   - leave the patch, but call checkmate with `final.callPackage`: the
     wiring step fails, naming checkmate.

   Restore, and it passes. All three outputs go in the PR.
2. Mode A: in the same tree (§5), compare `outPath` of every
   `nixarchy-apps` member before and after the scope change; all equal.
   Compare `pkgs.nix-update.outPath` from the overlay with nixpkgs' own;
   equal.
3. End to end: `nix run .#update` in the worktree bumps `owe` and
   `checkmate`, exits 0, and both packages build.
4. `checks.update-app` and everything `generated-checks.sh` prints that the
   change reaches, built locally by §6 tier before the push; `nix fmt --
   --ci`, statix, deadnix, and `checks.grep-q-pipefail`.
5. After merge: the next nightly `update.yml` runs green, and the review row
   for #1849 clears.
