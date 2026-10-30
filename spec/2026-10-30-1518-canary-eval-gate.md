---
status: approved
issue: 1518
intent: intent/2026-10-30-1518-canary-eval-gate.md
---

# Spec: the nightly canary's eval gate finishes on a hosted runner again

## Design

Two changes in one PR (intent, open question 1).

**1. `eval-gate.sh` evaluates in chunks, not one batch.** Line 40,
`if pi "${targets[@]}" >/dev/null; then exit 0; fi`, becomes a loop over
fixed-size slices of `targets` (`"${targets[@]:i:n}"`, with `n` a constant of
8, so 35 targets make 5 `nix path-info` processes). If every chunk passes, the
script exits 0. If one fails, `--batch-only` exits 1 straight away, and the
normal mode falls through to the existing per-target loop over all targets,
unchanged. Each process exits before the next starts, so its evaluator heap
goes back to the OS. The four full-system targets (`vm-toplevel`,
`reference-toplevel` and the two `nixarchy-desktop` runners) then never share
one heap with all the rest.

Everything else stays the same: the target set and its order, the stdout
`target<TAB>message` interface, exit codes 0/1/2, the fetch-error-means-2
rule, and `EVAL_GATE_LOG_DIR`. The header comment gets one line saying why it
chunks (#1518). `pin-fix.sh:248` (`--batch-only`) needs no change.

**2. The canary step logs memory, swap and disk while the gate runs.** In
`nightly.yml`'s "Their machine still evaluates" step, before `eval-gate.sh`,
start a background sampler. Every 20 s it prints one `canary-resources:` line
to the job log: `free -m` used and available memory, swap used, and
`df --output=avail` for `/nix` and `/`. The step's trap stops it. If a runner
dies again, the last line before the shutdown signal says whether memory or
disk was running out. If it passes, the lines are the hosted measurement the
intent asks for. It writes nothing to `$GITHUB_STEP_SUMMARY` and changes no
exit status.

## Alternatives rejected

- **One process per target.** That's the most isolation, but the batch already
  takes 222 s on p620, and every process re-evaluates the flake and nixpkgs.
  Hosted is slower, and 35 processes could approach the canary's 30-minute
  cap.
- **Splitting only the two `nixarchy-desktop` runners into their own
  processes** (codex). That bets the cause is those two targets, which nothing
  has measured. Fixed-size chunks bound the heap whatever is added next.
- **Raising `timeout-minutes` or moving the job to p620.** Neither helps a
  runner that is shut down at 4 minutes. p620 is ruled out by the intent.
- **Smaller targets.** Ruled out by the intent, because the #1459 contract
  stands.
- **Sampling inside `eval-gate.sh`.** The script is also the bump gate's, and
  a sampler there would print into `flake-update.yml` too. The canary is where
  the question is open.

## Risks

- **Chunking doesn't help.** If the runner dies on something other than
  evaluator heap (Determinate Nix's daemon, disk), the canary stays red. The
  sampler is what turns that night into a diagnosis rather than a third
  guess.
- **Time:** five evaluations of the flake instead of one. Expect tens of
  seconds more. The spec measures it, and the plan records the number.
- **Peak memory might not fall.** If nix's process heap is dominated by
  something shared (nixpkgs itself), a chunk peaks no lower than the batch.
  It is measured before merging, and if it doesn't fall the plan says so.
- **`flake-update.yml`'s gate changes too.** Same contract and targets, so a
  bump that passed before passes now. That gate's step only runs when the
  lock changes, so it is not exercised on every run.

## Verification

1. **Local, cheap tier, under the flock:** in a scratch worktree with
   tomorrow's lock, measure the peak anonymous memory of the old and new
   `eval-gate.sh --batch-only`, each in its own `systemd-run --user --scope`,
   sampling `anon` (§6). Record both peaks and both times. The new one must
   exit 0.
2. **Contract, the §1 proof.** Temporarily add a target that cannot evaluate
   (`.#does-not-exist`) at the end of `targets`, so it falls in the last
   chunk, not the first. Then:
   - The normal mode exits 1 and prints exactly one `.#does-not-exist<TAB>…`
     row.
   - `--batch-only` exits 1.
   - The same break with the old script gives the same results, so the
     contract hasn't changed.
   - Restore with `git checkout HEAD --`, and both modes exit 0.
3. **The sampler:** run the step's sampler lines under bash locally for
   about 45 s. They print `canary-resources:` lines, and the background job is
   gone afterwards (`jobs -p` is empty).
4. `nix fmt -- --ci`, `actionlint` on `nightly.yml`, `shellcheck` on
   `eval-gate.sh`, and `checks.grep-q-pipefail`.
5. **The first nightly after merge is the hosted test** (intent, open
   question 2). Green closes #1518. If it's red, the `canary-resources:` lines
   go into #1518 as the next step's evidence. The PR says this.
