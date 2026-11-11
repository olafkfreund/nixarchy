---
status: approved
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
   - hosted, `needs: gate`, with `if: ${{ !cancelled() }}`, exactly as its
     dependents have. The spec says "no job-level `if:`"; review showed that
     taken literally, GitHub's default `success()` skips carry when gate
     fails, before any step runs. `!cancelled()` is not a skip condition:
     carry still runs whatever gate concluded, and its first step fails on a
     failed gate (#1134). This is a clarification of the spec's intent,
     raised with the owner in the plan review;
   - its work steps run only when `needs.gate.outputs.relevant == 'true'`,
     as `omarchy`'s and `system-build`'s do (`build.yml:316-318`, `1445`),
     so a docs-only change does no carry work and still succeeds;
   - it evaluates the carry status with `pkgs/review.sh:519`'s expression,
     and builds every key of the carry's `packages` for `needed` names
     through `legacyPackages.extend overlays.default`;
   - it asserts each output's `.drv` is in `vm-toplevel`'s derivation graph,
     then pushes through `cachix-push.sh`, where `closure_context` decides;
   - with nothing needed, it prints `no cargo carry is needed`.
4. **Its dependents:** `system-build`, `system-checks`, `system-session`,
   `omarchy`, `box` and `options` add `carry` to `needs`.
   - Each has `if: !cancelled()`.
   - Each one keeps its existing gate-result step, and gains a second
     step after it that fails when `needs.carry.result != 'success'`, with
     its own message (`carry concluded '<result>'`). So the log says which
     dependency failed.
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
   - After line 186, before the push loop (so a refusal pushes nothing,
     not part), when `ctx=bump`:
     ```bash
     cs=$("$here/cache-allowlist.sh" commit-specific) || skip_all "could not list commit-specific entries"
     for attr in "$@"; do
       grep -qxF -- "$attr" <<<"$cs" || continue
       o=$(nix path-info "$attr" 2>/dev/null) || skip_all "$attr is not built"
       grep -qxF -- "$o" "$excl" || skip_all "$attr embeds the commit but is not among the source's referrers"
     done
     ```
     Representation, one on both sides: the group echoes **full
     installables**, `.#checks.x86_64-linux.vm-toplevel` and
     `.#checks.x86_64-linux.reference-toplevel`, the same strings
     `cache-allowlist.sh system` gives and `build.yml` passes, so a whole-line
     match compares like with like. `here=$(dirname "$0")` is defined if the
     script lacks it. The here-strings are not pipes
     (`checks.grep-q-pipefail`).
   - `cache-allowlist.sh`: add a `commit-specific)` case. Leave the default
     `groups=${1:-omarchy system runners apps}` unchanged, which keeps it out
     of the no-argument output that `cache-budget.sh`, `cache-entries.sh` and
     `eval-gate.sh` read (Codex checked).
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
   - The tests call the real `cache-allowlist.sh commit-specific` (it is
     already copied into the check's `$scripts`), not a fixture of their own,
     so a format drift between the two scripts fails here.
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
     - `runs-on: ubuntu-26.04`, a timeout of 60,
       `if: ${{ !cancelled() }}` and `needs: gate`;
     - first step: copy `system-build`'s gate-result step (lines 1437-1440)
       unchanged, so a failed gate fails carry;
     - every step after it has
       `if: needs.gate.outputs.relevant == 'true'`;
     - steps: checkout, `./.github/actions/setup-nix`, and cachix-action
       (`skipPush: true`, `skipAddingSubstituter: true`, matching the other
       jobs);
     - a step that evaluates the status, `pkgs/review.sh:519`'s expression
       verbatim:
       ```bash
       status=$(nix eval --impure --json --expr "let p = (builtins.getFlake \"git+file://$PWD\").inputs.nixpkgs.legacyPackages.x86_64-linux; in (import $PWD/pkgs/cargo-system-libs.nix { inherit (p) lib; prev = p; }).status") || { echo "::error::could not evaluate the cargo carry"; exit 1; }
       ```
       It is `{ "<name>": "needed" | "inactive" | "dead" }`. Then
       `needed=$(jq -r 'to_entries[] | select(.value=="needed") | .key' <<<"$status")`.
       Empty: echo `no cargo carry is needed`, and set an output for the
       later steps' `if:`.
   - **When something is needed:**
     - the carried attributes are every key of the carry's `packages`:
       `nix eval --impure --json --expr "builtins.attrNames (import $PWD/pkgs/cargo-system-libs.nix { …same p… }).packages"`.
       That already includes `codex-acp` exactly when the helper adds it;
     - each one is built from the overlaid set:
       `drv=$(nix eval --impure --raw --expr "let f = builtins.getFlake \"git+file://$PWD\"; in (f.inputs.nixpkgs.legacyPackages.x86_64-linux.extend f.overlays.default).$name.drvPath")`,
       then `out=$(nix build --no-link --print-out-paths "$drv^*")`. Each
       capture is checked on its own (`|| exit 1`): a failure inside
       `$(…)` does not stop the step;
     - the allowlist check: `top=$(nix eval --raw .#checks.x86_64-linux.vm-toplevel.drvPath) || exit 1`.
       Then
       `nix derivation show -r "$top" | jq -r '(.derivations // .) | keys[] | sub("^/nix/store/"; "")' > drvs`,
       which gives basenames on both JSON versions (the probe found v4 keys
       are basenames). Then `grep -qxF -- "${drv#/nix/store/}" drvs`, or
       refuse that package with `::error::`;
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

## Review (Codex gpt-6.1-sol, agy model not reported), folded in

- **carry's gate step was unreachable** with no job-level `if:` (both
  reviewers). Now `if: ${{ !cancelled() }}`, which is decision 3's
  clarification for the owner.
- **carry did work on docs-only changes** (agy). Now gated on
  `relevant == 'true'`, like its neighbours.
- **The `commit_specific` format mismatch** (both): the group emits full
  installables, the guard matches whole lines, and the tests use the real
  group.
- **The guard's placement** (agy): before the push loop, so a refusal never
  pushes part of the list.
- **Distinct messages for gate and carry** in dependents (agy).
- **The concrete status, overlay and derivation-comparison expressions**
  (both). Each capture is checked on its own.
