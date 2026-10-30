---
status: approved
issue: 1518
spec: spec/2026-10-30-1518-canary-eval-gate.md
coders:      # the owner asked for agy and codex on these issues
  1: agy
  2: agy
reviewers:   # read-only, on top of the fresh Opus review
  - codex
---

# Plan: the nightly canary's eval gate finishes on a hosted runner again

Approved decisions (carried from the spec):

- `.github/scripts/eval-gate.sh` evaluates its targets in fixed chunks of 8,
  in separate `nix path-info --derivation --no-eval-cache` processes, instead
  of one batch. If every chunk passes, it exits 0. If one fails,
  `--batch-only` exits 1 at once, and the normal mode runs the existing
  per-target loop over all targets, unchanged.
- Nothing else in the contract changes: the target set and its order, the
  stdout `target<TAB>message` rows, exit codes 0/1/2, the fetch-error-means-2
  rule, and `EVAL_GATE_LOG_DIR`. `pin-fix.sh` is untouched.
- `nightly.yml`'s canary step runs a background sampler that prints one
  `canary-resources:` line every 20 s (memory used and available, swap used,
  free disk on `/nix` and `/`). An EXIT trap stops it. It writes nothing to
  the step summary and changes no exit status.
- Ruled out: one process per target, splitting only the desktop runners,
  timeout or runner changes, a smaller target set, sampling inside the script.
- The hosted test is the first nightly after merge. That nightly's
  `canary-resources:` lines are the measurement either way.

The workflow edit is a CI-gate change (§11), approved with the spec.
Branch `fix/1518-canary-eval-gate`. Worktree `/mnt/data/vmtest/nixarchy-1518`.

## Steps

1. `.github/scripts/eval-gate.sh:37-41`. Keep `pi()` (37) and replace lines
   39-41 with:
   ```bash
   # Chunks, not one batch: each process hands its evaluator heap back when it
   # exits, and all targets in one process is where hosted runners died (#1518).
   chunk=8
   echo "eval-gate: ${#targets[@]} targets, in chunks of $chunk" >&2
   ok=1
   for ((i = 0; i < ${#targets[@]}; i += chunk)); do
     pi "${targets[@]:i:chunk}" >/dev/null || { ok=0; break; }
   done
   [ "$ok" = 1 ] && exit 0
   [ "$batch_only" = 1 ] && exit 1
   ```
   Everything from line 43 on stays as it is. The old stderr line
   `eval-gate: N targets, batch` is read by nothing (`grep -rn` over
   `.github docs tests` finds only the script).
   → Verify with `bash -n .github/scripts/eval-gate.sh` and
   `nix run nixpkgs#shellcheck -- .github/scripts/eval-gate.sh`.
   Traps: under `set -u`, `${targets[@]:i:chunk}` is fine because `targets`
   is never empty (lines 24-25 exit 2 first). Use no `mapfile < <(…)` (§4).

2. `.github/workflows/nightly.yml`, the canary's "Their machine still
   evaluates" step. Directly after `set -euo pipefail` (line 530), insert at
   the step's indentation:
   ```bash
   # One line every 20 s of what the runner has left, so a runner that dies
   # mid-gate says whether memory or disk ran out (#1518).
   (
     while :; do
       echo "canary-resources: $(free -m | awk '/^Mem:/ {printf "mem_used=%sM mem_avail=%sM ", $3, $7} /^Swap:/ {printf "swap_used=%sM ", $3}')disk_nix=$(df -BG --output=avail /nix | tail -1 | tr -d ' ') disk_root=$(df -BG --output=avail / | tail -1 | tr -d ' ')"
       sleep 20
     done
   ) &
   sampler=$!
   trap 'kill "$sampler" 2>/dev/null || true' EXIT
   ```
   The rest of the step stays as it is.
   → Verify with `nix run nixpkgs#actionlint -- .github/workflows/nightly.yml`.
   Traps:
   - `sampler` must be a global, not a `local`: the EXIT trap reads it at
     exit (§5).
   - No `${{ }}` in the line.
   - The `$(…)` pipelines inside the sampler only print, so a failure there
     can kill the sampler but never the step.

3. Commit steps 1-2 with a full-sentence subject (§8), push, and open the PR.
   It links intent, spec and plan, says `closes #1518` once, and puts the
   §1 output in the template's failing-output section.

## Tests

All local runs are cheap tier (§6): run them one at a time under
`flock /mnt/data/vmtest/codex-build.lock`.

- **Measure.** In a detached scratch worktree with `nix flake update` run,
  copy the old and new `eval-gate.sh` in side by side. Run each as
  `--batch-only` in its own `systemd-run --user --scope -p MemoryMax=20G
  -p MemorySwapMax=0`, sampling `anon` from `memory.stat`. Record both peaks
  and both times in Results below. Pass: the new one exits 0. If its peak is
  not lower, say so in Results and the PR, because the sampler is then the
  main deliverable.
- **§1 contract proof**, in the same scratch tree, for both the old and the
  new script:
  - Append `targets+=(".#does-not-exist")` right before the gate loop, so the
    bad target lands in the last chunk.
  - Normal mode exits 1 with exactly one row, starting `.#does-not-exist\t`,
    and no other rows.
  - `--batch-only` exits 1.
  - Remove the line (and check with `grep -c does-not-exist` that it's gone).
    Both modes exit 0.

  The old and new scripts must give identical exit codes and rows.
- **Sampler.** Run step 2's lines in a `#!/usr/bin/env bash` script with
  `set -euo pipefail` and a `sleep 45` in place of the gate. It prints 3
  `canary-resources:` lines, and no sampler process is left afterwards
  (`pgrep -f canary-resources` reports nothing).
- `nix fmt -- --ci`, `checks.grep-q-pipefail`, and actionlint plus
  shellcheck as above.
- **Reviews:** a fresh Opus agent gets the plan path and
  `git diff origin/main`. Codex runs `review --base origin/main` read-only.
- **Hosted:** the first nightly after merge. Green closes #1518. If it's red,
  the `canary-resources:` lines go into #1518.

## Results

(filled in during implementation)

## Rollback

Revert the squash commit. The gate goes back to one batch, and the canary
loses its sampler.
