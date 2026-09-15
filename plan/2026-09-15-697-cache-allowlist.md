---
status: draft
issue: 697
spec: spec/2026-09-15-697-cache-allowlist.md
---

# Plan: the binary cache holds what users and CI download, within 5 GB

## Approved decisions

This section carries the spec's decisions so the plan can be followed without
opening it.

- **Why.** nixarchy.cachix.org is Cachix's free tier: 5 GB, evicted by last
  *download*. Store-diff pushes from every job, on pull requests too, filled it
  and evicted what users and CI download. That emptied the KVM MicroVM runners
  and 31 of 34 check proofs, and blocked #693 and #696.
- **D1. No store-diff pushes.** Every `cachix/cachix-action@v17` step gets
  `skipPush: true`. The step and its `continue-on-error` otherwise stay as they
  are.
- **D2. One allowlist, pushed from `main` only.**
  `.github/scripts/cache-allowlist.sh [group]` prints installables, one per
  line. The groups:
  - `omarchy`: `.#omarchy`
  - `system`: `.#checks.x86_64-linux.vm-toplevel` and
    `.#checks.x86_64-linux.reference-toplevel`
  - `runners`: `.#microvm-<t>` and `.#microvm-<t>-tcg` for every template in
    `data/microvm-templates.nix`
  - `apps`: every app in `data/apps.nix` with `ours = true`
  - no argument: all groups

  `cachix-push.sh` pushes closures only when `GITHUB_REF=refs/heads/main`.
  Otherwise it prints `not main; closures are pushed from main only` and exits 0.
- **D3. Proofs pushed from every ref.** `cachix-push.sh --proof <check>...`
  pushes a check's result path. It refuses with `::warning::`, and does not
  fail, when the result's closure is more than one path or more than 1 MiB.
  - `build-unless-proven.sh` calls it for each check it built.
  - The direct `nix build .#checks…` calls in workflows move to
    `build-unless-proven.sh`.
  - `install-check.yml`'s hand-written proof push uses `--proof`.
  - Bump branches behave like pull requests: proofs only.
- **D4. Budget: 2 GB per commit's allowlist.** `.github/scripts/cache-budget.sh`
  realises every allowlist entry and takes the union of their closures. It
  excludes paths cache.nixos.org or hyprland.cachix.org serve, sums the rest,
  and prints the total and the ten largest paths. Over budget it exits nonzero
  with `::error::`.
  - It runs as the last step of `build.yml`'s `system` job, on pull requests and
    `main`, without `continue-on-error`.
  - `checks.cache-budget` tests it against stubs.
- **D5. Keep-alive by re-pushing.** After #696 merges, the nightly `cache` probe
  covers every allowlist entry, and its repush job (renamed from `runners` to
  `repush`) rebuilds and pushes whatever is missing. No NAR downloads.
- **D6. The p620 move is dropped.** Delete the local branch
  `ci/generated-checks-self-hosted` and its worktree; it was never pushed.
- **Guard.** `build.yml`'s "Every check is run by some workflow" step also
  asserts that every `cachix/cachix-action` block in every workflow has
  `skipPush: true`.

## Steps

Each step is one commit with a full-sentence subject. A deviation updates this
file in the same commit.

1. **`.github/scripts/cache-allowlist.sh` (new).** Prints the groups above.
   Templates are read with `nix eval --impure` from `data/microvm-templates.nix`,
   and apps from `data/apps.nix` (`ours = true`, `attr or name`, as `build.yml`'s
   `apps` job already reads them). It exits 2 on an unknown group, and on a
   group that evaluates empty.
   → verify: run on p620; `runners` prints 10 lines, `system` prints 2, `apps`
   prints at least 8, and `bogus` exits 2.

2. **`.github/scripts/cachix-push.sh`.** Adds the `main`-only guard for closures
   (D2) and `--proof` mode (D3). Closure mode is otherwise unchanged.
   → verify: fixture test in step 4.

3. **`.github/scripts/cache-budget.sh` (new).** Implements D4.
   - Reads the budget from `CACHE_BUDGET_MIB` (default 2048), with the cache
     URLs overridable so the test can stub them.
   - Checks each distinct path against upstream once.
   - If the upstream lookups take more than 60 s on p620, parallelises them
     with `xargs -P 16`.
   → verify: step 4, and a real run on p620 recorded in the PR.

4. **`tests/cache-budget.nix` (new), wired as `checks.cache-budget` in
   `flake.nix`.** Runs the real `cache-budget.sh` and `cachix-push.sh` with
   `nix`, `curl` and `cachix` stubbed. Cases:
   - (a) entries under budget pass;
   - (b) one oversized entry fails and is named;
   - (c) a path served upstream is not counted;
   - (d) a path shared by two entries is counted once;
   - (e) `--proof` on a single-path result calls `cachix push` with that path;
   - (f) `--proof` on a result with a dependency warns and does not push;
   - (g) closure mode off `main` does not push; on `main` it does.

   The generated step in `build.yml` builds it on every PR, with no claim needed.
   → verify: green; then break each of (b), (c), (d), (f) and (g) in the scripts
   and see it red (§1). Every failing output goes into the PR.

5. **`build.yml`, `omarchy.yml`, `update.yml`.**
   - Add `skipPush: true` to every `cachix-action` `with:` block (D1).
   - Add the `skipPush` assertion to the guard step, next to the existing checks.
   - Replace the omarchy push's `.#omarchy` and the system push's two toplevel
     names with `$(cache-allowlist.sh omarchy)` and `$(cache-allowlist.sh system)`.
   - Add a push of `$(cache-allowlist.sh runners)` after the
     `microvm-template` step.
   - Add a push of `$(cache-allowlist.sh apps)` at the end of `apps`.
   - Add the budget step at the end of `system`.
   - Move `bin-ledger` (`build.yml:804`) and `session` (`omarchy.yml:377`) from
     direct `nix build` to `build-unless-proven.sh`.
   → verify: actionlint clean; the guard step's shell, run with the self-hosted
   runner PATH, passes, and fails when `skipPush` is removed from one block.

6. **`.github/scripts/build-unless-proven.sh`.** After `nix build` succeeds, calls
   `cachix-push.sh --proof` with the checks it built. The push is non-fatal, so
   the script's exit status stays the build's.
   → verify: extend `checks.cache-budget` with a stubbed build: case (h), a
   built check gets a proof push and a skipped one does not.

7. **`install-check.yml`.** The "Push the proof" step calls
   `cachix-push.sh --proof install free-space installer-refusal`. Its probe
   that the cache now serves each result stays, unchanged.
   → verify: actionlint; diff review.

8. **After #696 merges: `nightly.yml` and `template-runners.sh`.** Rebase onto
   `main`.
   - `template-runners.sh` probes and repushes the output of every
     `cache-allowlist.sh` entry; rename it to `cache-entries.sh`.
   - The nightly job `runners` is renamed `repush`, and `report`'s `needs` and
     its title follow.
   - `checks.template-runners` becomes `checks.cache-entries`, with its fixtures
     unchanged in shape.
   → verify: that check green, and its three existing breaks still red.
   `build.yml`'s report-needs guard passes, and fails without `repush`.

9. **Budget on real paths.** On p620, run `cache-budget.sh` against this branch.
   → verify: total under 2048 MiB and close to the spec's estimate of about
   1.05 GB plus apps. The number and the ten largest paths go into the PR.

10. **Write-back and clean-up.**
    - `AGENTS.md` §6: what the cache holds and why, one paragraph pointing at
      `cache-allowlist.sh`, replacing any sentence that implies jobs push
      everything.
    - Delete the `ci/generated-checks-self-hosted` worktree and branch (D6).
    - `nix fmt`, statix, deadnix.
    → verify: all clean; `git branch --list ci/generated-checks-self-hosted` is
    empty.

11. **PR.** One PR from `ci/697-cache-allowlist` that links `intent/`, `spec/`
    and `plan/`, closes #697, and includes the failing outputs from steps 4, 5
    and 8 and the budget number from step 9. Workflow changes need maintainer
    review (§11), so it is not auto-merged.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.cache-budget --print-build-logs` | green; each case prints its line |
| the same, after each deliberate break | red, with that case's message |
| `nix build .#checks.x86_64-linux.cache-entries` (step 8) | green |
| `nix run nixpkgs#actionlint -- .github/workflows/*.yml` | no new findings against `main`'s baseline of 4 infos |
| `nix run nixpkgs#shellcheck -- .github/scripts/{cache-allowlist,cache-budget,cachix-push,build-unless-proven,cache-entries}.sh` | clean |
| `.github/scripts/cache-budget.sh` on p620 | exit 0, total printed, under 2048 MiB |
| `nix fmt -- --ci`, statix, deadnix | clean |

**After merge:**
- The first `main` build logs `pushing .#omarchy (N paths)` and the other
  allowlist groups.
- A PR's log shows `not main; closures are pushed from main only` and proof
  pushes.
- The next nightly reports every entry served.

## Rollback

- **Revert.** Revert the squash commit. The store-diff pushes come back with the
  `skipPush` lines, and nothing else depends on the new scripts.
- **Nightly.** If only the nightly is wrong, revert step 8's commit before the
  squash, or disable the `repush` job with `if: false` in a PR.
- **Budget.** If the budget step blocks a legitimate change, raise
  `CACHE_BUDGET_MIB` in the `system` job in that change, with the new total in
  the PR. It is not `continue-on-error` by design.
- **The cache itself.** Nothing is deleted from nixarchy.cachix.org by this
  work. Old store-diff paths age out on their own, and a rollback loses nothing.
