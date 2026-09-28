---
status: approved
issue: 1030
spec: spec/2026-09-27-1030-hypr-rdp-builds.md
---

# Plan: bump the pin, and add the check that keeps it fixed

Self-contained.

## The approved decisions

- **Narrow**: one configuration with hypr-rdp enabled, not one per service.
- **"It builds" and nothing more**: `options.nix` already asserts the unit,
  the template and the ExecStart.
- **Its own check, not `checks.options`**: that one peaks at 12.9 GB hosted
  and is #747's subject; a closure evaluation does not belong in it.
- **Evaluation, not a build**: `buildGo125Module` is an alias that `throw`s,
  so forcing the drvPath is enough and costs no runner minutes.
- **#1031 and #1033 are out of reach** and get named in `tests/AGENTS.md`.
- **Pin `sops-nix` at `5efb5a6f`** (2026-09-27), verified downstream.
- No workflow edit: the `omarchy` job builds every unclaimed check.

## The order matters, once

**Capture the RED before bumping.** This check can be shown failing against
the real bug on the real tree — but only until the pin moves. Run it first,
keep the output, then fix.

## Deviation, recorded as it happened

**The check forces `setupSecrets.text`, not `toplevel.drvPath`, and the
difference is 45 minutes.** Steps 2 and 5 said to force the drvPath. Doing so
put a `.drv` path in the derivation's environment, which is a **build input**
-- so nix built the entire system rather than evaluating it, and `omarchy`
timed out at its 45-minute cap twice.

Measured against three passing runs of the same step (6m25s, 12m40s, 12m45s)
before attributing it, because the first reading was "cold cache after the
flake bump" and a pin had just moved.

Forcing `builtins.stringLength
config.system.activationScripts.setupSecrets.text` leaves an integer in the
environment, forces the same evaluation, and keeps every property the spec
claimed: **3 seconds green on the new pin, 2 seconds red on the stale one**,
with the same Go error.

The red was re-proven with `--override-input` on an *installable*, after
discovering that the same flag is silently ignored inside
`--expr`/`builtins.getFlake` -- two earlier "it does not throw" results were
therefore measuring the new input and meant nothing. Both traps are written
into `tests/AGENTS.md`.

## Steps

1. Capture the current failure: evaluate the fixture's drvPath on the
   unbumped tree → verify it throws the Go error, and keep the text

2. `tests/hypr-rdp-builds.nix`: a `runCommand` that forces
   `reference.extendModules { hypr-rdp on; sops secret }
   .config.system.build.toplevel.drvPath` and writes it to `$out` → verify it
   fails on the unbumped tree

3. `flake.nix`: register `checks.hypr-rdp-builds` → verify by step 2

4. `flake.nix`: bump `sops-nix` to `5efb5a6f` → verify the lock moved

5. Re-run the check → verify green, and that the drvPath is a real path

6. Prove it is not a no-op: drop `hypr-rdp.enable` from the fixture, confirm
   the pre-bump red would not have fired → verify the enable is what forces
   sops into the closure

7. `tests/AGENTS.md`: what this check does and does not cover, beside the
   two-machine note → verify a reader learns #1031 and #1033 are elsewhere

8. `nix fmt`, read `git diff --stat` → verify no formatter blow-up

9. `reference-toplevel`, `vm-toplevel`, `menu-verbs` → verify the bump broke
   nothing else

## Tests

```sh
nix build .#checks.x86_64-linux.hypr-rdp-builds --print-build-logs
nix build .#checks.x86_64-linux.reference-toplevel --no-link
nix build .#checks.x86_64-linux.vm-toplevel --no-link
nix fmt -- --ci
```

`gh run list` before each; every runner is on p620.

**`checks.options` is NOT in this list.** It peaks at 12.9 GB hosted and this
branch does not touch `modules/`. CI runs it in the `system` job.

**The red state is real, not synthetic.** Step 1's output is the failing
evidence for the PR, and it is the bug this exists for rather than a
deliberate break. Step 6 is the deliberate break, and it proves the fixture's
`enable` is load-bearing.

Commit a baseline before any break loop — twice today I lost uncommitted work
to `git checkout HEAD --`.

## Rollback

Two files added, one input moved. Revert and the pin returns to `a8627b21`
and the check disappears; nothing else changes, because no option and no
module is touched. The closure hash moves both ways, which is the one visible
consequence.
