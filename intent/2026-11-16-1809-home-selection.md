---
status: approved
issue: 1809
author: olafkfreund
---

# Intent: a Home Manager selection file, and writers that can target it

## Problem

nixarchy's selection model is a set of user-owned NixOS modules in
`~/.config/nixarchy/`:

- `apps.nix`, `services.nix` and `advanced.nix`, seeded from templates
  under `/etc/nixarchy/` (`modules/home.nix:1408`);
- `flatsnap.nix`, written by its plugin;
- `nixarchy-apply` copies each into the flake (`modules/apps.nix`, the
  `for part in apps services advanced flatsnap` loop), and a caller may pin
  a part's bytes with `--expect-sha256 <part>=…`;
- apply regenerates `nixarchy-apps.nix` to import what exists.

A user can already write `home.packages` in their own Home Manager
configuration. What is missing is a nixarchy-managed **user-scope**
selection file, and writer routes that edit it. nixarchy-pkg#62 adds a user
scope to the package panel and needs both. Its PR 2 refuses user-scope
actions until this lands (nixarchy-pkg
`spec/2026-11-16-62-home-manager-scope.md`, sections B and C).

## Proposed outcome

- **A fifth part, `~/.config/nixarchy/home.nix`**, a Home Manager module:
  - seeded from a new `/etc/nixarchy/home-template.nix`, a `home.packages`
    block with the `#@pkgs-begin` / `#@pkgs-end` markers;
  - copied by `nixarchy-apply` like the others, under the same
    edited-in-flake rules;
  - imported, when it exists, as
    `home-manager.users."<id -un>".imports = [ ./nixarchy/home.nix ];` in
    the generated `nixarchy-apps.nix`. That is the invoking user, as #1809
    asks;
  - a caller's `--expect-sha256 home=…` pins the bytes that are then
    applied. Today any part name is accepted and hashed, but the copy loop
    applies only four, so a `home` pin can pass while nothing is applied.
- **`--home` for three writers:** `nixarchy-pkg-add`,
  `nixarchy-pkg-remove` and `nixarchy-opt-remove` target `home.nix` and
  its `home.packages` block.
  - Each keeps the guarantees it has today, under #1789's lock and
    in-place writes. `pkg-add` edits a copy and commits only if the target
    is unchanged (`nx_commit`). The removers edit the target under the lock
    and restore its backup on failure.
  - **A `--home` request never turns into a system change.** Where a writer
    would fall back to the picker (`pkg-add` with no names, or with
    unresolved names, opens `nixarchy-search`, which dispatches system
    writers), `--home` refuses with a message instead.
- **Policy where `pkg-add` assumes the system:**
  - **a curated app name** (`firefox`): refused with today's message,
    because the app is a system toggle;
  - **the other channel (`pkgsOther`):** the Home Manager module receives
    it too, so `--home` can add from either channel;
  - **unfree packages:** with `useGlobalPkgs = true`, the system's
    `allowUnfree` and `allowUnfreePredicate` apply. `--home` does not write
    the commented `nixpkgs.config.allowUnfreePredicate` scaffold that
    `pkg-add` offers today (`modules/apps.nix:3346`), because in a Home
    Manager module it would change nothing. Its hint names the system
    setting and the system file.
- **Supported scope:** the NixOS Home Manager module with
  `home-manager.useGlobalPkgs = true` (the installer's setting,
  `installer/host.nix:212`). Elsewhere (no Home Manager module,
  `useGlobalPkgs = false`, or standalone Home Manager), `--home` refuses
  with the reason, and no `home.nix` is seeded.
- **A home part that cannot be applied fails `apply`.** Examples: the
  invoking user has no Home Manager configuration on this machine, or the
  scope above is not met. Apply then exits nonzero before switching, with
  the reason, so the user's packages are never dropped silently. Without
  `home.nix`, `apply` behaves exactly as today.
- **Nothing changes for anyone without `home.nix` who never passes
  `--home`.**

## Affected users and systems

- Users of the package panel (nixarchy-pkg) and of the three writers.
- Installer-managed machines, which meet the supported scope.
- **Files:**
  - `modules/apps.nix`: `nixarchy-apply`, the three writers,
    `nixarchy-search` only as far as the refusal, and the template under
    `/etc`;
  - `modules/home.nix`: seeding, and `pkgsOther` for the Home Manager
    module;
  - the checks that run these scripts, and `tests/options.nix`.

## Constraints

- **Mode A:** a machine without Home Manager's NixOS module must still
  evaluate the generated `nixarchy-apps.nix`, so the home import cannot be
  an unconditional `home-manager.users…` line.
- **#1789 and nixarchy-pkg#65:** the lock path and the
  `NIXARCHY_LOCK_HELD` handshake are unchanged. The `--home` paths take the
  lock exactly as the system paths do.
- **Pinning:** a `home=` pin covers the bytes that are applied. Whether to
  reject unknown part names in general is a separate compatibility
  decision, not made here.
- **Verification covers behaviour, not only bytes:**
  - scope isolation: `--home` never edits a system file, and a system call
    never edits `home.nix`;
  - picker refusal;
  - user selection;
  - the unfree scaffold being absent under `--home`;
  - apply's failure contract.

  Every new guard is shown failing first (§1). Byte-format assertions in
  `checks.options` cover the new template, as for the others.
- No host deploy is needed to verify it.

## Open questions

1. **When the invoking user has no Home Manager configuration** on a
   machine that otherwise meets the scope: proposal: apply refuses, as
   above, and does not create one. Creating a `home-manager.users.<name>`
   entry for an account would also need a NixOS user and a state version,
   which is configuration the user did not ask for.
