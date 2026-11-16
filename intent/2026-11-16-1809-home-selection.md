---
status: draft
issue: 1809
author: olafkfreund
---

# Intent: a Home Manager selection file, and writers that can target it

## Problem

nixarchy's selection model has four user-owned files in
`~/.config/nixarchy/`:

- `apps.nix`, `services.nix`, `advanced.nix` and `flatsnap.nix`;
- each is seeded from a template under `/etc/nixarchy/`;
- `nixarchy-apply` copies each into the flake (`modules/apps.nix`, the
  `for part in apps services advanced flatsnap` loop);
- each copy is pinned by `--expect-sha256 <part>=…`;
- each is imported by the generated `nixarchy-apps.nix`.

All four are NixOS modules. There is no user-scope file: a package a user
wants only in their own profile has to go into the system's
`environment.systemPackages`.

nixarchy-pkg#62 adds a user scope to the package panel, and needs nixarchy
to provide one. Its PR 2 refuses user-scope actions, with a reason, until
this lands (nixarchy-pkg `spec/2026-11-16-62-home-manager-scope.md`,
sections B and C).

## Proposed outcome

- **A fifth part, `~/.config/nixarchy/home.nix`**, a Home Manager module:
  - seeded from a new `/etc/nixarchy/home-template.nix` (a
    `home.packages` block with the same `#@pkgs-begin` / `#@pkgs-end`
    markers);
  - copied by `nixarchy-apply` like the other four, under the same
    edited-in-flake rules and the same `--expect-sha256 home=…` pin;
  - imported only when it exists, as `home-manager.users."<user>".imports =
    [ ./nixarchy/home.nix ];` in the generated `nixarchy-apps.nix`.
- **`--home` for three writers.** `nixarchy-pkg-add`, `nixarchy-pkg-remove`
  and `nixarchy-opt-remove` gain `--home`, which targets `home.nix` and its
  `home.packages` block with the same markers, under the same writer lock
  and the same in-place writes as #1789.
- **Policy where `pkg-add` assumes the system:**
  - a curated app name (`firefox`): still refused with today's message,
    because the app is a system toggle;
  - the other channel (`pkgsOther`): the Home Manager module gets it too,
    so `--home` can add from either channel;
  - unfree packages: with `useGlobalPkgs = true` (the installer's
    setting), the system's `allowUnfree` and `allowUnfreePredicate`
    already apply. The `--home` hint names the system setting.
- **Nothing changes without `home.nix`.** `apply`'s output, the generated
  file and every writer behave as today when the file does not exist and
  `--home` is not passed.
- `checks.options`' byte-format assertions cover the new file as they cover
  the others.

## Affected users and systems

- **Users of the package panel** (nixarchy-pkg) and of the three writers.
- **Installer-managed machines**, which use the NixOS Home Manager module
  with `useGlobalPkgs = true` (`installer/host.nix:213`).
- **Files:**
  - `modules/apps.nix`: `nixarchy-apply`, the three writers, and the
    template under `/etc`;
  - `modules/home.nix`: seeding, and `pkgsOther` for the Home Manager
    module;
  - `tests/options.nix` and the writer checks.

## Constraints

- **Mode A, and machines without Home Manager's NixOS module.** The
  generated `nixarchy-apps.nix` is a NixOS module. A
  `home-manager.users…` line on a machine that does not import Home
  Manager fails evaluation, so the import must hold there: skipped with a
  message, never an evaluation error. Standalone Home Manager users have
  no `home-manager.users` either.
- **Which user.** `apply` runs as the user (`id -un`), and the module knows
  `programs.nixarchy.user`. They can differ, so the spec decides which one
  names the `home-manager.users` entry, and what happens when they
  disagree.
- **#1789's guarantees hold for the new target.** The lock, the handshake,
  in-place writes (inode, mode, owner and symlink kept), whole-file-or-none,
  and the commit-time "changed while running" refusal.
- **nixarchy-pkg#65's contract** is unchanged: same lock path, same
  `NIXARCHY_LOCK_HELD`.
- **Pinning:** `--expect-sha256 home=…` is refused for a part apply does
  not know today. Its acceptance must not loosen validation for other part
  names.
- **§1:** every new guard is shown failing first.
- No host deploy is needed to verify it: the checks run the scripts and
  evaluate both configurations.

## Open questions

1. **Which user is named** in `home-manager.users."<user>"`? Proposal:
   `programs.nixarchy.user`, written into the generated file by `apply`
   only when it matches `id -un`. When they disagree, apply refuses the
   home part with a message, and still applies the other four.
2. **Without Home Manager's NixOS module:** proposal: the generated file
   becomes a function of `{ options, lib, ... }` and imports the home part
   only under `lib.optionalAttrs (options ? home-manager)`. When it is
   absent, `apply` warns that `home.nix` is not applied on this machine.
3. **Seeding:** proposal: `home.nix` is seeded only when the machine uses
   Home Manager through NixOS, so Mode A users without it never get a file
   that does nothing.
