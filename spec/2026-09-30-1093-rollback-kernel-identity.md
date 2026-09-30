---
status: draft
issue: 1093
intent: intent/2026-09-30-1093-rollback-kernel-identity.md
---

# Spec: Warn on rollback to different kernel or module builds

## Design

In `pkgs/omarchy/nix-bin/nixarchy-rollback:108-133`, keep the selected generation number from `gum choose`, but replace the warning condition based on JSON `kernelVersion` and shortened `uname -r` with two identity comparisons. Resolve `kernel` and `kernel-modules` beneath `/run/booted-system` and beneath `$profile-$target-link` (`$profile` is set at line 28). `readlink -e` requires each target to exist as it canonicalizes its store path. Warn if either identity differs **or any of the four paths cannot be resolved**. Evaluate this before the existing diff, confirmation, and profile switch at lines 135-154; the target is the selected generation, not `/run/current-system`, which may already differ from the booted system.

Keep the warning's reboot choice but word it for both cases: a same-version kernel rebuild and a module-only rebuild can each leave loaded modules and new userspace out of sync. Version text may remain in the selection table (`pkgs/omarchy/nix-bin/nixarchy-rollback:51-59,100-105`), but it is no longer evidence for the warning decision. Preserve `--list`, cancellation, and the switch path. The packaged command is copied from `pkgs/omarchy/nix-bin/` by `pkgs/omarchy/default.nix:1012-1018`; this is the source to change, with no new runtime command beyond coreutils `readlink` already used in the Omarchy package patch at `pkgs/omarchy/default.nix:736-745`.

Add a cheap `tests/rollback-kernel.nix` runCommand check and register it under `checks` in `flake.nix` near the other script checks at lines 2264-2283. Run the actual rollback source with a sandbox copy whose two absolute system roots are replaced with fixture paths; stub `nixos-rebuild`, `gum`, `sudo`, and closure diff commands so it never switches a real system. Use two generations with the **same** `kernelVersion` and vary the resolved fixture links independently. Assert a warning for a different kernel path, a different `kernel-modules` path with an unchanged kernel, and an unresolved path; assert no warning when both match. Assert the warning appears before the confirmation and no switch occurs when confirmation is refused. The check must match the user-visible behavior, not merely search the script for `readlink`.

The existing rollback fixture at `tests/options.nix:3904-3928` tests the post-switch configuration warning, not kernel identity. `tests/options.nix` is owned by the unpushed criticals PR and must not be edited until that PR merges; the independent check avoids that conflict.

## Alternatives rejected

- Compare `kernelVersion` with `uname -r`: equal version strings do not identify rebuilt kernels, and `cut -d- -f1` loses release suffixes.
- Compare only `kernel`: a module-only NVIDIA rebuild can retain the same kernel store path.
- Compare with `/run/current-system`: rollback must compare the selected generation against what was booted, because current activation can differ from the booted system.
- Treat two empty or unresolved paths as equal: a missing identity must produce the conservative reboot warning.
- Extend `tests/options.nix` now: it is a criticals PR conflict and an expensive ~11.5 GB check; a separate runCommand check can exercise the command directly.

## Risks

- `kernel-modules` is a NixOS system link, observed on this host under both `/run/booted-system` and `/run/current-system`; a system lacking it will get the conservative warning. This may be a false positive but avoids silent unsafe activation.
- A changed module closure does not prove a particular loaded module differs. The warning tells users to reboot or use the boot menu; it does not prohibit rollback.
- A fixture that inspects only source text or accidentally invokes the host's `sudo` would give misleading coverage. The check must run the command against sandbox links and stub every mutating command.

## Verification

After plan approval, build `checks.x86_64-linux.rollback-kernel`. Before calling it proven, copy `pkgs/omarchy/nix-bin/nixarchy-rollback` aside, restore the old version comparison, and confirm the same-version kernel case fails with a clear missing-warning line. Restore with `cp` (never `git checkout`), then remove only the module comparison and confirm the module-only case fails. Restore again and confirm all cases pass. Capture both red outputs and the green result for the PR. Run `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and `nix run nixpkgs#deadnix -- --fail .` after any `.nix` edit; keep builds serialized under `/mnt/data/vmtest/codex-build.lock`.
