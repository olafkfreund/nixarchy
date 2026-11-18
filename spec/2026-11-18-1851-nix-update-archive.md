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
            check=True,
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
`callPackage ./pkgs/apps/…`. No package file changes.

Measured on checkmate: through `newScope`, `outPath` is identical and only
`updateScript` differs. `final.nix-update`, the one a Mode A user's `pkgs`
carries, is untouched: the patched copy exists only as an argument inside
this scope.

### 3. Remove #1775's workaround

`flake.nix:1652-1654`: the comment and `nix flake archive . >/dev/null ||
return 1` go. With the patch, nix-update archives the tree itself, at the
moment it needs it. `git` and `gnugrep` stay in `runtimeInputs`; `nix` stays
too, because nothing else in the app removes the need for it (to be
re-checked in the plan by grepping the script for `nix `, and dropped if
nothing calls it).

### 4. A check that runs nix-update's own function

New `tests/nix-update-archive.nix`, wired as `checks.nix-update-archive`. In
a `runCommand`, with a private store (`NIX_REMOTE=local?root=$TMPDIR/root`)
so it needs no daemon and no network:

1. make a git flake with no inputs, commit it, then edit `flake.nix` the way
   nix-update edits a package file;
2. call `get_flake_store_path` from the nix-update that `nixarchy-apps`
   passes to its updaters, taken from `nixarchy-apps.checkmate.updateScript`'s
   scope (or by the same `overrideAttrs`, exported once so check and scope
   cannot drift), with that package's own interpreter;
3. fail unless the reported path exists in the private store **and** holds
   the edited file.

Prototyped: against stock nix-update 1.16.0 it fails with `FAIL:
/nix/store/lp9x…-source was reported and never written`, and with the patch
it passes. It is evaluation plus a short Python build, the cheap tier. A new
`checks.<name>` is run on pull requests by `generated-checks.sh` with no
workflow edit (§4).

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

- **`nix flake archive` fails where `metadata` did not**, for example a
  network fetch of an input that is not in the store. The `check=True`
  raises, `get_flake_store_path` catches `CalledProcessError` and returns
  `None`, and nix-update falls back to evaluating the working directory
  directly. That degrades to the old behaviour rather than to a new
  failure. On the hosted runner every input is fetched by the job's first
  evaluation anyway.
- **The patched nix-update is not in any binary cache**, so `update.yml`
  builds it (a small Python package, seconds) on each run. It is not added
  to the cachix allowlist: nobody downloads it but that one job.
- **A future nixpkgs ships a fixed or changed nix-update.** The patch then
  fails to apply and `update.yml` goes red at build time, naming the patch,
  which is the intended signal to delete it.
- Hosts: none. This touches no system closure, so p620, p510 and users'
  machines are unaffected.

## Verification

1. §1 proof for the new check: build `checks.nix-update-archive` with the
   patch removed from the scope and watch it fail with "reported and never
   written", restore it and watch it pass. Both outputs go in the PR.
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
