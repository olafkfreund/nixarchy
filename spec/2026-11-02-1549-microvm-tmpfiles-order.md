---
status: approved
issue: 1549
intent: intent/2026-11-02-1549-microvm-tmpfiles-order.md
---

# Spec: a declarative sandbox's directories get the modes nixarchy declares

## Design

1. **Order our tmpfiles file first.** In `modules/services/microvm.nix:225`,
   rename `systemd.tmpfiles.settings."10-nixarchy-microvm"` to
   `"09-nixarchy-microvm"`. It then sorts before upstream's `10-microvm`, so
   for every path both files name, our entry is the one applied. All three
   entries move, as the approved intent decided:
   - `<vm>` at `0750`
   - `<vm>/share` at `0770`
   - `<vm>/policy` at `0750`

   A one-line comment at the key says why it is `09`.
2. **Assert all three modes in the VM.** In `tests/microvm-boot.nix:137`,
   assert all three directories in one `stat`: the VM directory and
   `policy/` at `microvm:kvm 750`, and `share/` at `microvm:kvm 770`. That
   check runs in the nightly only.
3. **A cheap check on every PR.** Add `checks.microvm-tmpfiles-order`, an
   evaluation-only check. Over the reference host with one declared
   machine, it asserts that for every path the `*-nixarchy-microvm`
   settings declare, no settings key that sorts earlier declares the same
   path. It prints the colliding key and path. `checks.microvm-boot` runs
   only in the nightly, so without this check a PR could not see the
   ordering regress. The check builds automatically through the "Build
   every check no other job claims" step, so no workflow edit is needed.
4. **Write the trap down.** Add a short section to `modules/AGENTS.md`: two
   tmpfiles.d files naming one path apply the lexically earliest file, so a
   nixarchy entry that must beat upstream's sorts first.

## Alternatives rejected

- **Move only `share/`, as Codex suggested.** This leaves the VM directory
  at upstream's `0775`, where group `kvm` (`programs.nixarchy.user`) can
  replace `current`, which `ExecStopPost` runs as root. The intent approved
  fixing all three.
- **Make the share's source absolute in `guest.nix`.** Upstream would then
  declare the same path and still sort first, and #1076 chose the relative
  path for the user-scoped runner (`pkgs/microvm.nix`).
- **`mkForce` upstream's tmpfiles entry away.** Overrides a value nixpkgs
  users could set; AGENTS.md §7 rules out `mkForce` on such options.
- **Patch microvm.nix upstream.** Upstream's `0775` is right for its own
  users. The conflict is ours to order.

## Risks

- **`microvm@<name>` runs as user `microvm`, the owner,** so `0750` keeps
  everything it had. The boot in `checks.microvm-boot` proves the guest
  still starts and writes its share.
- **Hosts with declared machines get the VM directory re-moded** from
  `0775` to `0750` at their next tmpfiles run. A local script that relied
  on group write there would break. Nothing in this repo does: `nixarchy
  vm` uses `$XDG_STATE_HOME`.
- **A later upstream file named `0*-…` could win again.** The cheap check
  in step 3 names it.

## Verification

- **§1 for `checks.microvm-tmpfiles-order`:** it fails with the key at
  `10-nixarchy-microvm` and names `share`, the VM directory and `policy`.
  It passes at `09`.
- **§1 for the VM:** `checks.microvm-boot` is already red on `main` (the
  nightly of 2026-11-02, `#1076: the share is 'microvm:kvm 775'`). It
  passes on the branch, built locally once CI is idle or by dispatching
  `nightly.yml`.
- **Static checks:** `nix fmt -- --ci`, statix and deadnix are clean.
- **Closes #1549:** the next nightly is green.
