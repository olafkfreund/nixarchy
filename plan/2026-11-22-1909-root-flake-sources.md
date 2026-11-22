---
status: draft
issue: 1909
spec: spec/2026-11-22-1909-root-flake-sources.md
coders:
  1: claude   # small and tricky: the failure handling is the point; the session writes it
  2: claude   # the check must be proven to fail three ways, which the session runs
  3: claude   # 12 one-line YAML insertions; mechanical, but a CI-gate change the session owns
reviewers:
  - codex     # second read on nix GC semantics
  - agy       # second read on the workflow call sites
---

# Plan: a self-hosted job keeps its own flake source alive through the host's auto-GC

Approved decisions, from the spec:

- **Cause.** Nightly run 44979123567's repush job (on p620-nixarchy-2) ran nix's auto-GC, because free space was below `min-free = 100 GiB`. That GC deleted the job's own flake source `/nix/store/3b0k…-source`, which no root held; evaluation then failed with `path … is not valid`.
- **Fix.** `.github/scripts/root-flake.sh <dir>` roots the flake source and every input, which it reads from `nix flake archive --json .` with `jq -r '[recurse(.inputs[]?) | .path? | strings | select(startswith("/nix/store/"))] | unique | .[]'`. It uses indirect roots (`nix-store --add-root <dir>/<n> --realise <p>`) under `$RUNNER_TEMP`, which on p620 is `/run/github-runner/<name>/_temp`, a host-visible `RuntimeDirectory`. Every self-hosted job runs it right after checkout. That is 12 jobs: nightly's install, install-encrypted, keyboard-boot, microvm, install-iso-net, repush and digest; omarchy-edge's verify; weekly's install-stock-iso and stable-session; release's iso; and install-check's install. On `digest` the step is `continue-on-error: true`.
- **Failure handling.** The script captures the archive output before splitting it (never `< <(…)`). It refuses a missing top-level `.path` and fewer than two paths. After rooting, it checks every path with `--check-validity` and every link in `--print-roots`, and re-runs from the archive at most three times before failing by name.
- **Coverage.** `checks.root-flake` also fails, naming the job, when any job whose `runs-on` is not a literal `ubuntu-*` label has a checkout without the root step.
- **Out of scope.** The host's `min-free` policy (config repo, the owner's call), and any workflow other than the 11 self-hosted jobs.
- **Merging.** §11: this is a CI-gate change, so the PR stays open for the owner.

## Steps

1. `.github/scripts/root-flake.sh` (new, executable, `#!/usr/bin/env bash`, `set -euo pipefail`): the six behaviours in the spec's Design: mkdir, archive, walk, root, verify-and-retry, report. Verify with `bash -n`, shellcheck through `checks.shellcheck`, and the `grep -q` guard (`checks.grep-q-pipefail`).
   Traps: `set -e` does not reach inside `$(…)`, so use `out=$(cmd) || die` (§5); a process substitution's status is lost (§4); the script must run under bash (§1).
2. `tests/root-flake.nix` (new) plus a `checks.root-flake` entry in `flake.nix`, next to `proof-push`.
   - **Script half.** Stubs: `nix` prints a fixture with a source, inputs, a nested input and an input named `path`. `nix-store` records `--add-root`, requires the root's directory to exist, and answers `--check-validity` and `--print-roots` from its record; it can be told to report one path invalid once, or always. Assert:
     - every fixture path is rooted and nothing else is;
     - a failing archive exits non-zero and roots nothing;
     - a no-input archive is refused;
     - an invalid-once path is retried and passes;
     - an always-invalid path fails, naming it.
   - **Coverage half.** A Python walk of `.github/workflows/*.yml` with PyYAML.
   - Verify that `nix build .#checks.x86_64-linux.root-flake` passes, then that each of the spec's five breaks fails it.
   Traps: in a `''` string, `''${` escapes and `\$` is literal (§5); write fixture files with `printf`, not a heredoc, if nixfmt would reindent (§5); `git add` new files before building (§5).
3. The five workflows (`nightly.yml`, `omarchy-edge.yml`, `weekly.yml`, `release.yml`, `install-check.yml`): one step after `actions/checkout` in each of the 12 jobs, named "Root this flake's source and inputs for the job (#1909)". Verify with `checks.root-flake`'s coverage half and actionlint.
   Traps: indentation in YAML; edge's `verify` checks out the candidate SHA, so the step goes after that checkout.
4. A paragraph in `tests/AGENTS.md`, or CLAUDE.md §4 if it is general (it is: "a path in the store is not a path that stays there during a job"). Append to the existing cache bullet in §4 rather than adding a section (no renumbering). Verify by reading the diff.

## Tests

- `nix build .#checks.x86_64-linux.root-flake` passes; each of the three breaks fails it with a readable message.
- Every generated check builds (`.github/scripts/generated-checks.sh`), under the build lock.
- `nix fmt -- --ci`, statix and deadnix are clean.
- By hand on p620: `.github/scripts/root-flake.sh /mnt/data/vmtest/flake-roots` roots all 63 paths. `nix-store --delete <source>` then refuses while the roots exist, and succeeds once the directory is removed. Then `nix flake archive .` re-creates the source.
- After merge: `gh workflow run nightly.yml --ref main`, then confirm in that run that the root step ran in each self-hosted job. #1909 closes only after a nightly whose `repush` job ran green.

## Rollback

Revert the PR. The roots are indirect and per-job, so nothing outlives a run.
