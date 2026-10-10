---
status: draft
issue: 1231
spec: spec/2026-10-10-1231-cache-budget-headroom.md
---

# Plan: room in the cache allowlist budget

The approved decision is to **raise the allowlist budget from 2048 to 2560
MiB.** Why 2560:

- **The measurement:** consecutive mains (`a3bbaed1` → `e29c5d37`, evaluation
  only) churned at most 335 MiB.
- **The worst case is a nixpkgs bump:** 2B − 508 MiB, where the 508 MiB is
  the two box images pinned by digest (#788). At B = 2560 that is 4612 MiB
  of the free tier's 5120.
- **3 GB would not fit:** the same sum comes to 5636 MiB.

Nothing is trimmed from the allowlist. This is a CI-gate change (§11): the
owner merges, and auto-merge is not armed. It touches four
files, so the `coder` agent implements the steps, per the managed model split;
this session runs the §6-gated builds if the coder's guard blocks them,
reviews with a fresh Opus agent, and commits.

## Steps

1. **`.github/workflows/build.yml:1665`.** Change `CACHE_BUDGET_MIB: "2048"`
   to `"2560"`. Add one comment line above `env:`: why 2560 and not 5 GB,
   with a pointer to `spec/2026-10-10-1231-cache-budget-headroom.md`.
   - **Verify:** `nix run nixpkgs#actionlint -- .github/workflows/build.yml`.
   - **Traps:** do not write the skip-CI marker literally anywhere (§8).

2. **`.github/scripts/cache-budget.sh:13-18`.** Change the default to
   `budget_mib=${CACHE_BUDGET_MIB:-2560}`. Replace the "2 GB per commit, not
   5" paragraph with the measured-overlap argument in at most four lines: the
   current commit plus the previous one, the box images shared, and a nixpkgs
   bump as the binding case. Point at the spec.
   - **Verify:** `bash -n`, and `shellcheck`, which must show no new findings
     against `main`'s copy.
   - **Traps:** none beyond keeping the comment short (§7).

3. **`tests/cache-budget.nix:97` and `:122`.** Comments and messages only:
   "of 2048" becomes "of 2560", and "a 2 GB budget" becomes "a 2.5 GB
   budget". Leave the assertions alone; (b)'s 3010 MiB still exceeds 2560.
   - **Verify:** build `checks.x86_64-linux.cache-budget` by drvPath, under
     `flock /mnt/data/vmtest/codex-build.lock`.
   - **Traps:**
     - no heredoc changes, so nixfmt is not at risk, but still run `nix fmt`
       and read `git diff --stat` (§5);
     - `git add` before evaluating.

4. **§1 break proof.** From a committed baseline:
   - set the default in `cache-budget.sh` to `4096`, `git add`, evaluate the
     drvPath and confirm the break is in it, then build;
   - expect case (b) red: "3 GB of allowlist passed".
   - `git checkout HEAD --` the file, and expect green.

   The proof shows the check reads the figure step 2 changes. Capture both
   outputs.

5. **`AGENTS.md` §6, line 578.** "more than 2 GB" becomes "more than 2.5 GB,
   the most a nixpkgs bump leaves room for (#1231)".
   - **Verify:** `grep -n "2.5 GB" AGENTS.md`.
   - **Traps:** do not insert or renumber sections (the "Write back" rule).

6. **Commit, PR.** One commit with a full-sentence subject. The PR:
   - links all three artifacts;
   - carries the measurement table and the break-proof output;
   - notes the side finding that part of `e29c5d37`'s vm-toplevel closure
     (`system-path`) was not in nixarchy.cachix.org when measured.

   **Do not arm auto-merge.** After CI, confirm that the `system` job log
   prints "of a 2560 MiB budget".

## Tests

| command | expected |
|---|---|
| `nix build '<cache-budget drv>^*'` | green, with all of its cases `ok` |
| break: default 4096 | red at case (b) |
| `actionlint` on build.yml | clean |
| `nix fmt -- --ci`, `statix`, `deadnix --fail` | clean |
| PR `system` job | "… MiB of a 2560 MiB budget", passing |

## Rollback

Revert the commit. The budget returns to 2048, and the next allowlist growth
fails the step again, as it would today.
