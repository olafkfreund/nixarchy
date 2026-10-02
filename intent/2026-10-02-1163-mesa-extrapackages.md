---
status: approved
issue: 1163
author: olafkfreund
---

# Intent: nixarchy's driver Mesa never collides with a user's own Mesa

## Problem

#1162 set `hardware.graphics.package`/`package32` (at `mkOverride 900`) to
Mesa from Hyprland's nixpkgs, so the drivers Hyprland loads share its glibc.

NixOS merges `package` and every `extraPackages` entry into one `buildEnv`,
`graphics-drivers`; `package32` and `extraPackages32` go into
`graphics-drivers-32bit`. A configuration that lists its own `mesa` there, a
common pattern, now puts two *different* Mesa builds in one environment, and
the build fails:

```
collision … share/glvnd/egl_vendor.d/50_mesa.json
```

- **Live on the owner's p620** (its own config, its own nixpkgs `c59305b`).
  The 32-bit side failed, and was fixed there by dropping `extraPackages32`.
  The 64-bit `graphics-drivers` derivation, as evaluated now, holds both
  `1vkzwrp4…-mesa-26.2.3` (via nixarchy) and `v8v8s62…-mesa-26.2.3` (its
  `extraPackages`), so it is expected to fail the same way. Not built, at the
  owner's request.
- **Who is hit:** any configuration whose `extraPackages(32)` holds a Mesa
  that is not the exact store path nixarchy chose.
  - Mode A users with their own nixpkgs are hit today.
  - Installer-managed machines are not yet: on `main`, nixarchy's
    `pkgs.mesa` is the same store path as Hyprland's. They will be from the
    next nixpkgs bump.
- **Why nothing caught it.** `checks.graphics-glibc` (#1162) compares glibc
  versions only. No check builds the merged environment with a user's own
  Mesa beside nixarchy's. #1164 is the hardening for that whole class; this
  intent is the fix for this one regression.

## Proposed outcome

- **No configuration fails with a `buildEnv` collision because of nixarchy's
  Mesa.**
- **Where nixarchy's choice and the user's own Mesa genuinely conflict,** the
  user gets an evaluation-time message that names:
  - the entry;
  - why it conflicts (the glibc relationship with Hyprland);
  - the exact one-line change.

  Not a collision in a derivation they never wrote.
- **The #1158 guarantee still holds:** the driver Hyprland loads never has a
  newer glibc than Hyprland, and `checks.graphics-glibc` stays green.
- **A check builds `graphics-drivers` and `graphics-drivers-32bit`** for a
  fixture that lists its own `mesa`. It is shown red on today's `main`.

## Affected users and systems

- `modules/nixos.nix` (the `hardware.graphics` block from #1162).
- A new or extended cheap check under `tests/`.
- `docs/internals/flake.md` (the #1162 section) and `modules/AGENTS.md`.
- Any user with `mesa` in `extraPackages(32)`: the owner's p620 now, and
  everyone with that pattern after the next nixpkgs bump.

## Constraints

- **Hyprland keeps its own nixpkgs and its cache** (no `follows`).
- **The user's explicit settings win:** nixarchy must not edit a user's list.
- **No `mkForce`** on anything a user would set (AGENTS.md §7).
- **Mode A stays inert.**
- **No changes on the owner's hosts from this work.** That happens elsewhere,
  at the owner's request.
- **Prove the new check red first** (§1).

## Open questions

1. **What should nixarchy do when a user lists their own Mesa?** Three
   options:
   - **(a) An assertion.** Fail evaluation with the fix spelled out: remove
     `mesa` from `extraPackages(32)`, or set `hardware.graphics.package`
     yourself. Honest, but a user who changes nothing gets a failed rebuild,
     though a readable one instead of the collision.
   - **(b) Step aside.** If `extraPackages(32)` already contains a Mesa,
     nixarchy does not set `package(32)`, and emits a `warnings` entry about
     the glibc risk. Nothing breaks today, but that machine can hit the #1158
     abort on the next glibc move. `checks.graphics-glibc` would still catch
     it on the reference machine, not on the user's.
   - **(c) Use the user's Mesa.** Set `package` to the user's Mesa when they
     list one. The same glibc risk as (b), silently.

   **Proposal: (a).** It is the only one that never leaves a machine that
   builds and then cannot start Hyprland.
2. **Should the same guard cover other driver packages** in
   `extraPackages(32)` that are built against our nixpkgs? Examples:
   `libva-vdpau-driver`, `rocmPackages.clr.icd`, both on p620. They load into
   Hyprland too, but carry no Mesa collision. The proposal is: not in this
   fix. `checks.graphics-glibc` already compares their glibc for the
   reference machine, and #1164 takes the general case.

## Owner's answers (2026-10-02)

1. **(a), an assertion** with the fix spelled out.
2. **Other driver packages are out of this fix,** and covered by #1164.
