---
status: draft
issue: 1722
author: x
---

# Intent: codex and omp build under nixpkgs' system-library cargo hook

## Problem

The nightly nixpkgs bump (#1721, nixpkgs `f4a03c0`, the `nixos-unstable`
head of 2026-11-07 09:04) fails `build` and `install check` (runs
42578177371 and 42578177500).

- nixpkgs' `pkgs/build-support/rust/hooks/cargo-setup-hook.sh` now adds
  `cargoUseSystemLibs` to `preConfigureHooks` for every package that uses
  the cargo setup hook (as `rustPlatform.buildRustPackage` does), unless the
  package sets `dontCargoUseSystemLibs`. It exports
  `ZSTD_SYS_USE_PKG_CONFIG`, `RUSTONIG_SYSTEM_LIBONIG`,
  `AWS_LC_SYS_USE_SYSTEM`, `LIBSQLITE3_SYS_USE_PKG_CONFIG` and others.
  - A package whose crates link one of those libraries, and that does not
    list it in `buildInputs`, now fails to build.
  - `main`'s nixpkgs (`f9a75f4`, 2026-11-05) does not have the hook.
- Two packages in nixarchy's closure fail that way:
  - **codex 0.167.0**: `zstd-sys`, `aws-lc-sys` and `onig_sys` find no
    library;
  - **omp 18.16.0**: `onig_sys` finds no oniguruma.

  Everything else that failed in those runs depends on one of these two,
  apart from a transient 504 fetching disktree's tarball (the URL answers 200
  now).
- Upstream has fixed both on master, and neither fix is in the channel:
  - codex: `16b463698a` (2026-11-07 20:07) adds `aws-lc`, `oniguruma`,
    `sqlite` and `zstd`;
  - omp: `43c51fe5d9` (18.18.1, 2026-11-08) adds `oniguruma` and `zstd`.
- So each night's bump is red until the channel advances, and nixpkgs on
  `main` cannot move. Nobody can say when the channel moves, and the owner
  wants the bump working now.

## Proposed outcome

- The nixpkgs bump builds codex and omp, and its `build` and `install check`
  runs go green.
- On `main`'s current nixpkgs, nothing changes: codex's and omp's derivations
  are the same as without this change, so nothing rebuilds.
- When the channel brings upstream's fixes, the carry stops applying by
  itself, and a check says when it can be deleted.

## Affected users and systems

- `flake.nix`'s `overlays.default`. That overlay also reaches Mode A users
  who import the module, so it changes their codex and omp too.
- The nightly bump PRs and the edge channel, which follows `main`'s
  nixpkgs.

## Constraints

- Mirror upstream's fix exactly: add the same `buildInputs`, nothing more.
  Do not set `dontCargoUseSystemLibs`, which would vendor libraries that
  upstream now links from the system.
- Change a package only when two things hold: the nixpkgs in use has the
  hook, and the package still lacks one of the libraries. On `main` today,
  and on any nixpkgs with upstream's fix, the derivation must be unchanged.
  - "The nixpkgs in use" is the overlay's `prev`, which can be nixarchy's
    pinned nixpkgs, `nixpkgs-stable` (the stable VM), or a Mode A user's own.
    So the test reads `prev.path`'s `cargo-setup-hook.sh` source, not
    nixarchy's lock, and never a built hook (that would be
    import-from-derivation). The overlay is `final: _prev:` today, so `prev`
    must be named (agy review).
  - Per package, add only the libraries it lacks. When none is missing, or
    the hook is absent, return `prev.<pkg>` itself with no `overrideAttrs`,
    so the derivation is equal by construction.
- Mode A (CLAUDE.md §7, §14): a user's own override of codex or omp must
  still apply on top. The carry builds on `prev`, never replaces the
  package.
- Proof (§1): with the carry, codex and omp build on the bump's nixpkgs.
  Without it, they fail with the errors above. On `main`, their `drvPath`s
  are equal with and without it.
- A carried override of a nixpkgs package needs a line saying when to drop
  it, and something that says once it is dead, judged per package.
  - Dead means the hook is present and the package no longer lacks a library.
  - That must not fail the nightly bump. The bump is a bot's PR, and it
    cannot delete the carry, so a failing check would stall nixpkgs exactly as
    this issue does.
  - So the dead carry is reported (for example as a row in the nightly
    review), never a red check. The two upstream fixes are a day apart, so
    one can be dead while the other is still needed.

## Open questions

1. Where does the carry live: inline in `overlays.default`, or in its own
   file under `pkgs/`? Proposed: its own file, named for the hook, with a
   `pkgs/AGENTS.md` section.
2. Are codex and omp the only packages affected? The failed runs stopped at
   the first wave of failures. Proposed: build the bump's system closures
   and checks locally with the carry before the PR, and add any other
   package that fails the same way.
