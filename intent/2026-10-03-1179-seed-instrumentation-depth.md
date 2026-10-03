---
status: draft
issue: 1179
author: olafkfreund
---

# Intent: the install checks seed the installed system at the same import depths the VM uses

## Problem

`checks.install`, `checks.free-space` and `checks.install-encrypted` install
offline. They succeed only if the system the VM installs is exactly the system
the test seeded beforehand, down to `system-path`'s hash. `system-path` hashes
the ORDER of `environment.systemPackages`, and `lib.modules` merges list
definitions in import-depth order. So two configurations with the same modules
at different depths can produce different `system-path`s.

**The seeds and the VM put two modules at different depths:**

| module | seed (each test's `targetSystemFor`) | VM (the generated `hosts/installed`) |
|---|---|---|
| `test-instrumentation.nix` | top of `modules` (`++ optional instrumented …`) | `configuration.nix`'s imports, four levels down (sed in at test time) |
| the hardware config | top of `modules` (`hardwareConfig cpuModule`) | `configuration.nix`'s imports (`./hardware-configuration.nix`) |

- **Locations:** `tests/install.nix:232-235`, `tests/free-space.nix:218-221`,
  `tests/install-encrypted.nix:194-197`; the VM shape is
  `installer/template/host/configuration.nix:7-12`.
- **Why it holds today:** the orders agree only because nixarchy's own module
  sits at depth 0 on both sides.
- **#1176 broke it:** a `_file` imports wrap moved nixarchy's module one level
  deeper. `xwininfo` (from the instrumentation) went from entry 21 in the seed
  to entry 0 in the VM, `system-path` no longer matched, and the offline
  install tried to build `texinfo` from source.
- **Fixed for that one change, not in general:** #1176 removed the wrap, which
  fixed that change but left the trap in place.

Each test also duplicates the whole seed construction: its own
`instrumentation`, `hardwareConfig`, `initrdPin` and `targetSystemFor`, the
`/etc/nixarchy/test-instrumentation.nix` text, and the cp/sed test-script
lines. `install-encrypted`'s instrumentation also differs (`console=ttyS0`,
plymouth off).

## Proposed outcome

- **Each seed builds the installed system in the same module shape the VM
  installs:** the host module's own imports hold a `configuration.nix`-level
  module, which imports the hardware config and, when instrumented, the
  instrumentation.
- **A change to any module's import depth can no longer make the seed and the
  VM disagree on order,** and so cannot make the offline install build from
  source.
- **Proven (§1):** with this fix in place, the #1176 wrap is re-applied on a
  probe, and seed and VM `system-path` stay equal, by evaluation. Without the
  fix, the same probe gives different `system-path`s. That is a cheap,
  evaluation-only check, so it can run on every pull request, not only in the
  install job.

## Affected users and systems

- **Tests only:** the three files above, possibly a shared helper under
  `tests/`, and a new cheap check. No user-facing change, nothing in
  `modules/` or `installer/`.
- **CI:** the install job's seeded closure changes once. It is still built in
  the same job.

## Constraints

- **The seeded closure must stay what the ISO and the VM install.** The fix
  changes where modules are imported in the TEST, never what the installer
  writes.
- **`install-encrypted`'s extra instrumentation** (`console=ttyS0`, plymouth
  off) keeps working.
- **VM checks run in CI only (§6).** Local proof is by evaluation: the
  debugger's comparison from #1176 (seed shape versus VM shape, `system-path`
  `drvPath`) is the method.
- **Not a CI gate change:** no workflow edit is expected. A new
  `checks.<name>` is run automatically (§4).

## Open questions

1. **A shared helper, or three edits?** Factoring `targetSystemFor` and the
   instrumentation into one `tests/lib/installed-target.nix` removes the
   duplication that made this a three-place fix. It is a bigger diff to three
   VM checks. The proposal is the helper: a hand-maintained triple fails open
   (AGENTS.md §4).
2. **The cheap check:** an evaluation-only `checks.install-seed-shape` that
   builds both shapes for each test and compares `system-path` `drvPath`s.
   The proposal is yes. It catches the next depth change on every pull
   request, minutes before the install job would.
