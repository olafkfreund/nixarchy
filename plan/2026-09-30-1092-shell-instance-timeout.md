---
status: approved
issue: 1092
spec: spec/2026-09-30-1092-shell-instance-timeout.md
---

# Plan: bound the shell-instance probe

The #963 patch to the vendored `omarchy-shell` first probes the caller's Quickshell config path, then falls back to a single running instance ID. The probe has no deadline; the real IPC call already uses `timeout --kill-after=1s "$ipc_timeout"`. Use that same configurable timeout for the probe (`OMARCHY_SHELL_IPC_TIMEOUT`, default `2s`). Keep the path-first selection, listing fallback, multiple-instance refusal, and existing errors. Raw `qs ipc` prints IPC-level errors such as `Target not found.` with exit 0; `omarchy-shell` turns those replies into exit 1. Correct the documentation accordingly. Do not add a new timeout setting or a `qs list --all` deadline without evidence of a listing hang.

## Steps

1. `tests/shell-ipc-resolve.nix:53-65,80-117`: Extend the existing `qs` stub with a mode that sleeps only when its arguments contain `__nixarchy_probe`. Add a sixth case using `OMARCHY_SHELL_IPC_TIMEOUT=0.2s`, a ten-second stub sleep, a five-second outer `timeout`, and the existing one-instance listing. Assert the built wrapper exits before the outer timeout and its argv log contains the fallback `-i aaa111` call. Keep the original five cases and print a distinct success line for the new one -> verify by `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.shell-ipc-resolve --print-build-logs` after step 2; the old unbounded probe must make this case fail. Traps: use the built package argument, not a source-text-only check; `omarchy-shell` is unwrapped so the PATH stub works; no `producer | grep -q` under `pipefail`.
2. `pkgs/omarchy/default.nix:2033-2063`: Prefix only the #963 probe with `timeout --kill-after=1s "$ipc_timeout"`; leave the `if !` fallback, list parser, real IPC call, and error handling intact -> verify by the slow-probe check reaching `-i aaa111` and all original `shell-ipc-resolve` cases passing. Traps: this `printf` builds an upstream script and `substituteInPlace --replace-fail` must still match; after this `.nix` edit run `nix fmt` and inspect `git diff --stat` for formatter churn.
3. `pkgs/AGENTS.md:203-211`: Correct the raw-`qs` exit-status sentence and state that the wrapper converts literal IPC error replies into failure -> verify by comparing the wording with the built wrapper's `case $output` and `tests/session.nix:713-718`. Traps: distinguish raw `qs ipc` from `omarchy-shell`; no behavior change here.
4. `pkgs/omarchy/default.nix` and `tests/shell-ipc-resolve.nix`: Prove the new check can fail. Copy the fixed `default.nix` to `/mnt/data/vmtest/1092-default.nix.good`; remove only the probe's `timeout --kill-after=1s "$ipc_timeout"` prefix; confirm the diff contains that removal; run the check under `flock /mnt/data/vmtest/codex-build.lock`. Require a nonzero result naming the slow probe or outer timeout and save its output for the PR. Restore with `cp /mnt/data/vmtest/1092-default.nix.good pkgs/omarchy/default.nix`, remove the aside copy, and rerun under the lock to a green sixth-case line -> verify by the captured red and green outputs. Traps: never use `git checkout` to restore; one Nix build at a time; do not pipe a build to `tail` without `pipefail`.
5. `pkgs/omarchy/default.nix`, `tests/shell-ipc-resolve.nix`, and `pkgs/AGENTS.md`: Review the final diff, run `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, `nix run nixpkgs#deadnix -- --fail .`, and `git diff --check` -> verify by all commands succeeding and no unrelated changes in `git diff --stat`. Traps: stage new files before a flake build; do not edit installer, microVM, or `tests/options.nix` files reserved for another PR.

## Tests

- `checks.shell-ipc-resolve`: original five cases stay green; the new slow-probe case records a bounded fallback to `-i aaa111`. A missing probe timeout makes the same case red under the five-second outer timeout.
- `nix fmt -- --ci`, `statix`, `deadnix`, and `git diff --check` pass.
- No VM check is needed: the behavior is exercised through the built wrapper and a controllable `qs` stub. The check bounds the probe, not the entire request; a timed-out probe can still be followed by a bounded real call, and `qs list --all` remains unbounded by the approved design.

## Rollback

Revert the implementation commit(s) and rebuild the Omarchy package. This restores #963's previous unbounded probe; it does not require changes to user data or host configuration. If the check itself is faulty, retain the wrapper fix and revise the check with a fresh red/green proof rather than silently removing coverage.
