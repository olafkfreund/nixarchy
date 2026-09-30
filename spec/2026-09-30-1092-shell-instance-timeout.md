---
status: draft
issue: 1092
intent: intent/2026-09-30-1092-shell-instance-timeout.md
---

# Spec: bound the shell-instance probe

## Design

`pkgs/omarchy/default.nix:2033-2063` patches the vendored `omarchy-shell`. Its #963 path-first probe at line 2037 runs raw `qs ipc` without a deadline; the real IPC call at line 2062 already uses `timeout --kill-after=1s "$ipc_timeout"`. Prefix the probe with that same timeout command. `omarchy-shell` already sets `ipc_timeout` from `OMARCHY_SHELL_IPC_TIMEOUT`, defaulting to `2s`, before the patch runs. Keep the current `if ! ...; then` fallback: a timed-out probe should resolve a running instance through `qs list --all`, then let the existing bounded real call report whether the shell responds. Preserve path-first selection, the multiple-instance refusal, and the existing user-facing errors.

`pkgs/AGENTS.md:203-211` should distinguish raw `qs ipc` from its wrapper. Raw `qs ipc` prints `Target not found.` or `Function not found.` with status 0 for an IPC-level failure; the wrapper translates those literal replies into exit 1. Connection failure or timeout is already nonzero from raw `qs`. This is consistent with the wrapper's comment and `tests/session.nix:713-718`; the probe must use raw status, not assume a missing target returns 1.

Extend `tests/shell-ipc-resolve.nix:53-65,80-117`, the existing stubbed check for this exact patch. Add a stub mode that sleeps only for `__nixarchy_probe`, set `OMARCHY_SHELL_IPC_TIMEOUT` to a short value for that case, and invoke the built `omarchy-shell` inside an outer timeout longer than the inner one but shorter than the stub sleep. Assert the command completes before the outer timeout and that `qs` receives the fallback `-i <instance>` call. The existing five selector and refusal cases remain.

## Alternatives rejected

- A separate probe duration: the wrapper already offers `OMARCHY_SHELL_IPC_TIMEOUT`; a second knob could drift from the real call.
- A deadline on `qs list --all`: there is no evidence of a listing hang in this issue. Add one only if measured.
- Always selecting by instance ID: #963 deliberately tries the current path first, and that common path should remain intact.
- A source-text-only assertion: it can see a `timeout` token without proving the wrapper stops waiting when `qs` stalls.

## Risks

- A busy but live shell can exceed the probe timeout and trigger the instance-list fallback. The real call remains independently bounded, so the command can take roughly two timeout periods plus process cleanup; the check must not claim one timeout bounds the entire request.
- `qs list --all` is still unbounded. This is an accepted scope limit until a listing hang is shown.
- The vendored patch uses `substituteInPlace --replace-fail`; an Omarchy source change may break the patch at build time and require review.

## Verification

1. Extend `checks.shell-ipc-resolve` with a slow-probe fixture as above. Run it with `nix build .#checks.x86_64-linux.shell-ipc-resolve --print-build-logs` after staging any new files; it must print a distinct successful slow-probe line alongside the existing five cases.
2. Prove the new assertion is live: copy `pkgs/omarchy/default.nix` aside under `/mnt/data/vmtest/`, remove only the new probe timeout, confirm the diff shows that removal, then run the same check. It must fail because the outer timeout kills the call before fallback; capture that output for the PR. Restore with `cp`, never `git checkout`, and rerun to green. Keep builds serial under the shared lock if other work is in flight.
3. After editing the Nix file, run `nix fmt`, inspect `git diff --stat`, and require `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and `nix run nixpkgs#deadnix -- --fail .` to pass.
