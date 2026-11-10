---
status: draft
issue: 1738
spec: spec/2026-11-10-1738-bump-cache-carry.md
coders:
  1: claude     # a hosted-runner measurement: workflow runs and reading logs, no editing
  2: codex      # small, tricky bash in cachix-push.sh: the archive read and the commit-specific guard
  3: coder      # stub cases in tests/cache-budget.nix, following the file's existing pattern
  4: coder      # the carry job and needs/gate edits across seven jobs in build.yml
  5: claude     # local checks, §1 breaks, the deliberate carry failure, the PR
reviewers:
  - codex       # step 2's bash and step 4's needs/gate logic
  - agy         # whether every job given needs: carry fails red (never skipped), and the allowlist check
---

# Plan: a nixpkgs bump that needs the cargo carry builds and caches without a hand push

Self-contained: it carries the approved spec's decisions. Builds, workflow
runs, commits and the PR are Claude's. Codex and the coder edit files only.
agy's sandbox cannot reach worktrees under `/mnt/data`, so agy only reviews,
with the files given inline. This changes CI gates (§11), so the owner merges
it.

## Decisions (from the approved spec)

1. **The source read.** `cachix-push.sh` bump mode reads the source with
   `nix flake archive --json . | jq -r '.path // empty'`, not
   `flake metadata`. Measured: Determinate Nix 3.22.5 on the hosted runner
   has `lazy-trees = true`, and `metadata .path` is null there.
2. **The commit-specific guard.** Entries known to be commit-specific (the
   `commit_specific` list: `vm-toplevel` and `reference-toplevel`) must have
   their output path as a whole line of the exclusion file, or bump mode
   refuses (`skip_all`). There is no roots-only guard and no per-entry
   "references the source" rule: one breaks carry, and the other cannot fail.
3. **The `carry` job** in `build.yml`:
   - hosted, with no job-level `if:`;
   - it evaluates the carry status with `pkgs/review.sh:519`'s expression,
     and builds every key of the carry's `packages` for `needed` names
     through `legacyPackages.extend overlays.default`;
   - it asserts each output's `.drv` is in `vm-toplevel`'s derivation graph,
     then pushes through `cachix-push.sh`, where `closure_context` decides;
   - with nothing needed, it prints `no cargo carry is needed`.
4. **Its dependents:** `system-build`, `system-checks`, `system-session`,
   `omarchy`, `box` and `options` add `carry` to `needs`.
   - Each has `if: !cancelled()`.
   - Each one's first step, the existing gate-result check, also fails on
     `needs.carry.result != 'success'`, naming carry.
   - `gate` stays in `needs`.
5. **Tests** in `tests/cache-budget.nix`: an archive-based stub, a null path,
   the commit-specific entry excluded, the commit-specific entry missing, and
   a package-only entry with a roots-only set, which pushes.

## Steps

Worktree: `/mnt/data/vmtest/wt-1738` (`fix/1738-bump-cache-carry`). The
probe worktree is `/mnt/data/vmtest/wt-1738-probe` (`probe/1738-lazy-trees`).

1. **The real referrers-closure measurement** (the probe workflow,
   `.github/workflows/probe-1738.yml` on the probe branch).
   - Replace its `measure` step with what `system-build` does, then the
     exclusion computation, with no push:
     ```bash
     out=$(nix build --no-link --print-out-paths .#checks.x86_64-linux.vm-toplevel)
     src=$(nix flake archive --json . | jq -r '.path // empty')
     tree=$(nix eval --raw .#omarchy.outPath)
     roots=("$src"); nix path-info "$tree" >/dev/null 2>&1 && roots+=("$tree")
     nix-store --query --referrers-closure "${roots[@]}" | sort -u > excl
     echo "excl lines: $(wc -l < excl)"; grep -qxF "$out" excl && echo "TOPLEVEL EXCLUDED" || echo "TOPLEVEL NOT EXCLUDED"
     ```
     Raise `timeout-minutes` to 120 for this one run. The toplevel build on
     a cold runner is the cost being measured. It is throwaway.
   - Verify: the log says `TOPLEVEL EXCLUDED`. If it says `NOT EXCLUDED`,
     stop. The spec returns to the owner (design 2b).
   - Then delete the probe branch:
     `git push origin --delete probe/1738-lazy-trees`.
   - Traps: commit the workflow change and push. Never force-push.
2. **`cachix-push.sh`** (`.github/scripts/cachix-push.sh:172-186`).
   - Line 175 becomes:
     `src=$(nix flake archive --json . 2>/dev/null | jq -r '.path // empty') || skip_all "could not archive the flake source"`.
     `set -uo pipefail` (line 40) makes the pipeline's status the `nix`
     failure. Line 176's emptiness test stays.
   - After line 186: when `ctx=bump`, for each attr given on the command
     line whose name (minus `.#checks.$system.`) is in `commit_specific`,
     resolve its output with `nix path-info "$attr"`. Then
     `grep -qxF -- "$out" "$excl" || skip_all "<attr> embeds the commit but is not among the source's referrers"`.
     That is a file read, so no `grep -q` on a pipe (`checks.grep-q-pipefail`).
   - `commit_specific` comes from `.github/scripts/cache-allowlist.sh`: add a
     `commit-specific` group that echoes the two toplevel attrs. The script
     reads it with `mapfile` after `out=$(…) || skip_all` (§4: capture, then
     split).
   - Verify: step 3's checks.
   - Traps:
     - `set -e` is off here (`-uo` only), so check each status explicitly;
     - `skip_all` exits 0 by design (a push failure must not fail a build,
       #235), so the warning is the signal;
     - widening `cache-allowlist.sh`'s groups: grep the callers
       (`grep -rn cache-allowlist.sh .github/`), since a new group must not
       join the "no argument: all" output that `cache-budget.sh` sums.
       Exclude it there.
3. **Tests** (`tests/cache-budget.nix`).
   - The stub's `"flake metadata"` case (line 100) becomes `"flake archive"`,
     returning `{"path":"/nix/store/src-flake"}`, with `STUB_META_FAILS`
     renamed `STUB_ARCHIVE_FAILS` everywhere (line 315's loop included).
   - New `STUB_ARCHIVE_NULL`: returns `{"path":null}`, and bump pushes
     nothing.
   - The stub `nix-store --referrers-closure` gains a switch,
     `STUB_REFS_WITHOUT_TOPLEVEL`, that omits the toplevel's output path.
   - Cases, beside line 269's positive control:
     - **commit-specific excluded** (the default): the push proceeds;
     - **commit-specific missing** (`STUB_REFS_WITHOUT_TOPLEVEL=1`): refused,
       with the "embeds the commit" warning;
     - **package-only**: the entry is not on the list and the referrers are
       roots only, and the push proceeds.
   - Verify: `nix build .#checks.x86_64-linux.cache-budget`, then the §1
     breaks in step 5.
   - Traps:
     - never name a variable `out`;
     - `printf`, not heredocs, in the `''` string (§5);
     - the stubs need `${pkgs.bash}` shebangs;
     - read statuses unpiped.
4. **`build.yml`.**
   - **The new `carry` job**, before `system-build` (line 1382):
     - `runs-on: ubuntu-26.04`, a timeout of 60, no `if:`, and
       `needs: gate`. If gate failed, carry's first step fails like the
       others' (#1134);
     - steps: checkout, `./.github/actions/setup-nix`, and cachix-action
       (`skipPush: true`, `skipAddingSubstituter: true`, matching the other
       jobs);
     - a step that evaluates the status (decision 3) and writes the needed
       names, or `none`.
   - **When something is needed:**
     - build the carried packages through the overlay expression;
     - assert each `.drv` basename appears in
       `nix derivation show -r $(nix eval --raw .#checks.x86_64-linux.vm-toplevel.drvPath)`'s
       derivation keys;
     - run `.github/scripts/cachix-push.sh <out paths>`.
   - **Dependents:** the six jobs listed in decision 4 (lines 294, 1382,
     1544, 1604, 1774, 2005):
     - add `carry` to `needs`;
     - make sure each has `if: !cancelled()`;
     - extend the existing gate-result step (lines 311, 1437, 1558, 1619,
       1804, 2012) so it also runs when `needs.carry.result != 'success'`,
       echoing `::error::carry concluded '<result>'`.
   - Leave `system` (line 1980) as it is: it already reads its dependents'
     results.
   - **The coverage guard:** the "Every check is run by some workflow" step
     is unaffected, because carry builds no `checks.*`. Confirm with
     actionlint and by reading the generated step.
   - Verify: `nix run nixpkgs#actionlint -- .github/workflows/build.yml`
     reports nothing new.
   - Traps:
     - §11: this is a CI-gate change, for the owner to merge;
     - `needs` on a matrix job (`options`) is per job, not per leg, so its
       gate step serves every leg;
     - no self-hosted job gains `needs: carry`.
5. **Local checks, breaks, the PR** (Claude).
   - **Cheap:** `checks.cache-budget`, `grep-q-pipefail`, `inline-python`
     (if the job embeds Python), and every generated check the change
     reaches; then `nix fmt -- --ci`, statix and deadnix.
   - **§1 breaks, each restored with `git checkout HEAD --` after a
     baseline commit:**
     - restore the `flake metadata` read → the archive-only stub fails;
     - delete the guard → the commit-specific-missing case fails;
     - apply the guard to every entry → the package-only case fails.
   - **Open the PR** (refs #1738, linking all three files), and comment
     `@codex review`.
   - **On the PR:**
     - push a temporary commit making carry's status step `exit 1`;
     - confirm every dependent is red, naming carry, and none skipped
       (`gh run view --json jobs`);
     - push a revert commit, never a force-push;
     - confirm the PR run: carry builds or substitutes the carried packages
       (the carry is active on `main`), pushes nothing (an ordinary PR), and
       the jobs run.
   - **Merge:** the owner merges, because it is a CI gate. I print the
     command.
   - **After merge:** watch the next dated bump PR for carry building once,
     the `pushing … left out as commit-specific` lines, and no job compiling
     codex.

## Tests

| check | expected |
|---|---|
| probe (step 1) | `TOPLEVEL EXCLUDED` on Determinate Nix with lazy trees |
| `cache-budget` | passes; three breaks go red |
| actionlint | nothing new |
| PR run with carry failed on purpose | every dependent red naming carry, none skipped |
| PR run | carry builds or substitutes, pushes nothing; all jobs green |
| next bump PR | one carry build, exclusion push lines, no hand push |

## Rollback

Revert the merge commit: `cachix-push.sh`, `cache-allowlist.sh`,
`cache-budget.nix` and `build.yml` return to today. Nothing is stored that
needs undoing; cache entries pushed in the meantime are ordinary allowlisted
paths.
