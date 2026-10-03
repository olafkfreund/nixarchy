---
status: approved
issue: 1179
intent: intent/2026-10-03-1179-seed-instrumentation-depth.md
---

# Spec: the install checks seed the installed system at the same import depths the VM uses

## The real shape (what the VM installs)

Depth is counted from the `nixosSystem` `modules` list (0).

| depth | file | contributes |
|---|---|---|
| 0 | `installer/template/flake.nix:99-104` | `nixarchy`, home-manager, disko, `hosts/<name>` |
| 1 | `hosts/<name>/default.nix` imports | `installer/host.nix`, `disk-config.nix`, `./nixarchy-hardware.nix`, `./configuration.nix` |
| 1 | `configuration.nix` itself | timezone, keymap, `allowUnfree`, autologin, `hashedPasswordFile`, `initrd.secrets` |
| 2 | `configuration.nix` imports | `./hardware-configuration.nix` (with the initrd pin `install.sh` writes into it, `reuse_baked_initrd`, `:1910`), `./nixarchy-apps.nix`, and in the tests `./test-instrumentation.nix` (sed in) |

## The seeds today

`tests/install.nix:167-235`, `tests/free-space.nix:~148-221`,
`tests/install-encrypted.nix:~151-197` each define `targetSystemFor`:
- depth 0: nixarchy, home-manager, disko, and one block mirroring
  `default.nix`;
- depth 1: that block's imports, `host.nix`, `disk-config.nix`, and an inline
  attrset of the configuration values;
- **depth 0 again, wrongly:** `hardwareConfig cpuModule`, `initrdPin` and
  (instrumented) `instrumentation`. On the real host these three sit at
  depth 2.

Each test also carries its own copy of:
- `instrumentation` (`install-encrypted`'s adds `console=ttyS0` and turns
  plymouth off);
- the `/etc/nixarchy/test-instrumentation.nix` text;
- the cp/sed test-script lines.

## Design

### D1. One helper: `tests/lib/installed-target.nix`

- **A function** taking `{ inputs, pkgs }`, then the per-test parameters:
  - `diskConfig`, the `disk-config.nix` argument set;
  - `reference`, the config whose initrd lists are pinned
    (`reference-unencrypted` or the encrypted one);
  - `extraInstrumentation`, a module, `{ }` by default (encrypted passes its
    console and plymouth settings);
  - the username and hostname, `omarchy` and `installed`, kept as today.
- **It returns `targetSystemFor { cpuModule, instrumented ? false }`,**
  shaped exactly as the table above:
  ```nix
  modules = [
    nixosModules.nixarchy  home-manager  disko
    { imports = [
        (import installer/host.nix { … })
        (import installer/disk-config.nix diskConfig)
        { imports = [ (hardwareConfig cpuModule) initrdPin ]   # depth 2
                    ++ optional instrumented instrumentation;   # depth 2
          time.timeZone = …; … }                               # depth 1
      ]; }
  ];
  ```
- **The `hardwareConfig` and `initrdPin` comments** move into the helper
  unchanged. They are the reasons, and they stay at the code.
- **It also exports one `instrumentationEdit`:** the `cp` and the `sed` the
  test script runs, and the `/etc/nixarchy/test-instrumentation.nix` text.
  Each test's script interpolates it, so the edit the VM gets and the edit
  the check reproduces (D2) cannot drift.
- **The three tests** call the helper instead of defining their own. Their
  test scripts are otherwise unchanged.

### D2. The check: `checks.install-seed-shape` (evaluation only, cheap)

- **For each of the three tests' parameters, instrumented and not, it
  compares `system-path` `drvPath`:**
  - **seed:** the helper's `targetSystemFor`;
  - **VM:** a `nixosSystem` over the real template, `installer/template/flake.nix`'s
    module list, plus a host directory rendered from
    `installer/template/host/` with the test's values and the instrumentation
    edit applied.
- **The host directory is rendered** by `install.sh`'s own
  `substitute_host_files` if it can run in isolation (the plan establishes
  this), otherwise by a minimal substitution in a `runCommand`. It is
  imported from that derivation (IFD).
- **It is a `runCommand`** that prints `shape: equal` per case and fails on
  any difference, naming the case and both paths.
- **The free-space replica the debugger built for #1176 is the precedent:**
  it matched CI's seeded derivations exactly.

### D3. `installer/AGENTS.md` or `tests/AGENTS.md`

One paragraph: why the seed mirrors the template's depths, pointing at #1176
and this check. It extends the existing "The shape is load-bearing" comment,
which moves into the helper.

## Alternatives rejected

- **Three in-place edits:** owner chose the helper (intent, answer 1). It is
  the duplication that made #1176's trap a three-place fix.
- **Seed with the real generated flake** (`installer/mkFlake.nix` + render)
  instead of a hand-mirrored module list: that is the ideal end state, but it
  ties every VM check's evaluation to IFD and a committed tree. The check
  (D2) gets the same guarantee more cheaply, at evaluation time.
- **Only move the instrumentation:** `hardwareConfig` and `initrdPin` sit at
  the wrong depth too. They contribute no system packages today, but a
  `systemPackages` line in either would break the same way.

## Risks

- **The seeded closures change once.** The install job builds them anyway,
  and the change is the point. If CI's `install` fails afterwards, the helper
  misses something the real host has. The check is designed to show which.
- **`nixarchy-hardware.nix`** (nixos-hardware CPU modules, written by
  `install.sh`) is not in today's seeds, and the uninstrumented seed still
  matched the VM in #1176's measurement. The helper keeps it out unless the
  check shows a difference; the plan records which.
- **IFD in a check** costs a small runCommand at evaluation. Nix allows it by
  default; if the CI evaluator disallows it, the plan uses `builtins.toFile`
  for the rendered files instead.

## Verification

1. **`checks.install-seed-shape` is green with the helper,** for all six
   cases (three tests, instrumented or not).
2. **§1:** wrap `nixosModules.nixarchy` in `{ imports = [ … ]; }` (#1176's
   break) on the OLD seeds, which must go red; on the new helper it must stay
   green (the property: depth changes cannot split seed from VM). Also move
   `instrumentation` back to depth 0 in the helper: red.
3. **CI's `install`, `free-space` and `install-encrypted` stay green.**
   They are VM checks: CI and the nightly only (§6).
4. fmt, statix, deadnix.
