---
status: approved
issue: 1085
spec: spec/2026-09-30-1085-bluetooth-pairing.md
---

# Plan: Keep incoming Bluetooth pairing closed

Nixarchy's `bt-agent -c NoInputNoOutput` starts for the graphical session while BlueZ's adapter `Pairable` defaults to true. The pinned Omarchy panel starts discovery but never changes pairability. The approved behavior is `Pairable: no` during idle and panel use, with outgoing pairing from the panel still working. Device-initiated pairing is deliberately unavailable. BlueZ's 120-second timeout limits exposure if another client enables pairability; it is not the primary gate. No panel patch is required because BlueZ's `Pairable` property affects incoming requests only. Mode A, where `programs.nixarchy` is disabled, must be unchanged.

## Steps

1. `modules/nixos.nix:1675-1698,1842`: before starting `bt-agent`, set the default adapter non-pairable and fail closed if that operation fails; retain the existing retry behavior, replace the false panel-scan comment, and set `hardware.bluetooth.settings.General.PairableTimeout = 120` inside the enabled module → verify by the new evaluated-module check and `nix fmt -- --ci`. Traps: `ExecCondition` can skip the unit, so do not use it for a failed security gate; an unavailable adapter must not leave the agent running; a timeout alone leaves the default pairable state open; avoid changing Mode A.
2. `tests/bluetooth-pairing.nix` (new): add a cheap check of the evaluated module's enabled and disabled states and the generated `bt-agent` unit. Assert the startup off guard, fail-closed behavior, timeout 120, and no Bluetooth additions while disabled → verify by `nix build .#checks.x86_64-linux.bluetooth-pairing --no-link`, after staging the new file. Traps: do not hardcode a copy of module settings into the check; prove it fails by breaking the real module as in Tests.
3. `flake.nix:1742-2294`: register `checks.bluetooth-pairing` with the existing checks so CI picks it up automatically → verify by `nix eval .#checks.x86_64-linux --apply builtins.attrNames` and the check build. Traps: do not edit workflows or run `checks.options` locally; it uses about 11.5 GB RSS.
4. `pkgs/verify.sh:444-458`: report actual adapter `Pairable` state and the user agent's status on hardware; flag `Pairable: yes` while the agent is active → verify with a shell syntax check and the manual hardware run. Traps: do not claim the radio-free session VM proves pairing; avoid counting a failed `bluetoothctl show` as `Pairable: no`.
5. Review the diff, run the checks in Tests, commit implementation with each commit naming the plan step, and open a PR against `main` with the repository template, links to intent/spec/plan, `Closes #1085`, and captured red/green check output → verify by `git diff --check`, clean status, PR diff, and CI. Traps: no merge, no workflow changes, no local VM checks, and no log artifacts in the commit.

## Tests

- No builds or VM runs at this plan gate. During implementation, before any build longer than seconds, run `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`; wait if an install job is active.
- Stage `tests/bluetooth-pairing.nix` before building: flakes omit untracked files. Run `nix fmt`, inspect `git diff --stat`, then require `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, `nix run nixpkgs#deadnix -- --fail .`, and `git diff --check` to pass.
- Prove the new check fails twice. First copy `modules/nixos.nix` aside to `/mnt/data/vmtest/1085-nixos.nix.save`; remove only the agent's non-pairable startup gate, stage the change, run `nix build .#checks.x86_64-linux.bluetooth-pairing --no-link` and capture the nonzero result and diagnostic. Restore with `cp /mnt/data/vmtest/1085-nixos.nix.save modules/nixos.nix` and stage it. Repeat with the timeout setting removed. Inspect `git diff --cached` each time to prove the break landed. Never use `git checkout` to restore a staged break. Keep logs outside the worktree or paste their key lines into the PR; remove the saved copy after proof.
- With the source restored, run the check and capture the green result. On real hardware, confirm `bluetoothctl show` says `Pairable: no` at idle, with the panel open, after closing, and after an adapter power cycle; confirm an outgoing pair initiated from the panel succeeds while `Pairable: no`. If another client turns pairability on, confirm it returns to no within 120 seconds. Run `nixarchy-verify` and compare its report. A power-cycle failure requires fixing the off-state mechanism before completion.

## Rollback

Revert the implementation commits and rebuild the host; the prior agent and Bluetooth configuration return. This restores the previous incoming-pairing exposure, so keep the affected adapter powered off until a corrected change is deployed.
