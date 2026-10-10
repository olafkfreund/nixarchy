---
status: approved
issue: 1231
intent: intent/2026-10-10-1231-cache-budget-headroom.md
---

# Spec: room in the cache allowlist budget

## Measurement

The intent asked for the real overlap between two consecutive `main` commits.
It was measured on p620 on 2026-10-10, evaluation only, building nothing
(the method the owner chose after realising failed twice: parts of the closure
are not in the cache, see Risks).

**Method.** For `a3bbaed1` and `e29c5d37`, two consecutive mains:

1. take every `cache-allowlist.sh` entry;
2. collect the output paths of each entry's whole derivation closure;
3. keep the paths the newer commit has and the older one lacks;
4. drop what cache.nixos.org or hyprland.cachix.org serve;
5. size the rest from the local store, or else from nixarchy.cachix.org's
   narinfo.

| | |
|---|---|
| output paths, old / new | 11693 / 11858 |
| differing | 256 |
| ours and sized | 171 paths, **335 MiB** |
| unsized | 5: the toplevel, `etc`, `system-units`, `activate`, `boot.json`, each a few MiB at most |

The largest differing paths:

| MiB | path |
|---|---|
| 124.5 | omarchy-4.0.4 |
| 54.6 | initrd (reference) |
| 52.5 | initrd (vm) |
| 22.3 | gliff-0.3.0 |
| 10.0 | linux-raw-sys crate source |
| 6.7 ×2 | system-path |

**This is an upper bound for an ordinary commit**, for two reasons. First, the
derivation closure includes outputs that are only needed at build time, like
the Rust crate sources, and those are never pushed. Second, this commit
added a package; a commit that only changes docs churns only `omarchy`, the
initrds and the small files above, about 250 MiB.

**The worst case is a nixpkgs bump.** It changes nearly every path. The
exception is the two box images: they are fixed-output Docker tarballs
pinned by digest (#788), 508 MiB that only a pin bump replaces.

## Design

**Raise the budget from 2048 to 2560 MiB (2.5 GB).**

#697's rule was that the cache must hold the current commit and the one
before it, in the free tier's 5 GB (5120 MiB), with room left for proofs. It
met that rule by assuming two commits share nothing: 2 × 2048 = 4096 MiB.
The measurement replaces the assumption:

| case | current commit + what the previous one adds | at 2560 |
|---|---|---|
| ordinary commit | B + ~335 MiB | **2895 MiB**: room for about six commits of history |
| nixpkgs bump, the worst case | B + (B − 508 MiB box images) | **4612 MiB**: 508 MiB spare for proofs (each under 1 MiB) |

The worst case is the binding one: 2B − 508 ≤ 5120 − margin. 2560 leaves the
same order of margin #697 chose. The next round figure up, 2816, would leave
about 0. That buys **about 600 MiB of headroom** over today's 1953 MiB,
instead of 70.

Edits, all to the one number and to text that states it:

- `.github/workflows/build.yml:1665`: `CACHE_BUDGET_MIB: "2560"`. The step
  comment gains one line pointing at this spec's arithmetic.
- `.github/scripts/cache-budget.sh`:
  - the default `budget_mib=${CACHE_BUDGET_MIB:-2560}`, so a local run
    measures against the same figure;
  - the header comment "2 GB per commit, not 5" is rewritten as the
    measured-overlap argument in two lines, pointing here.
- `tests/cache-budget.nix`: comments only. Cases (a) and (b) say "of 2048"
  and "a 2 GB budget"; (b)'s 3010 MiB still exceeds 2560, so the assertions
  stand unchanged.
- `AGENTS.md` §6, line 578: "more than 2 GB" becomes "more than 2.5 GB, the
  most a nixpkgs bump leaves room for (#1231)".

## Alternatives rejected

- **Trim the Debian box image (118 MiB).** It buys a fifth of the headroom and
  costs every user of the Debian box template a Docker Hub pull. #788 put it
  there because Docker Hub is not ours. Keep it, and revisit only if 2.5 GB
  fills.
- **Drop the TCG or KVM runners.** QEMU alone is 395 MiB, and those are the
  downloads that make `nixarchy vm` usable on a laptop (#697's own reasons).
- **Raise to 3 GB or more.** A nixpkgs bump would need 2 × 3072 − 508 =
  5636 MiB, which does not fit in 5120. The previous commit would be evicted
  part-way through the bump, which is #697's original incident.
- **Leave it at 2 GB.** The next ordinary pull request that grows a closure
  fails a step that has nothing to do with it.

## Risks

- **The worst case is a computed bound, not an observed one.** It assumes LRU
  eviction removes the older commit's unshared paths first, which is what
  "evicted by last download" means. If a nixpkgs bump does push the cache
  past 5 GB, the nightly `repush` job re-pushes any allowlisted path that went
  missing (§4), so the failure mode is a slow PR, not a broken one.
- **The measurement is one commit pair.** The worst case does not depend on
  it, since it uses B and the box images' fixed size. The ordinary-commit
  figure does, and it is labelled as an upper bound.
- **Parts of main's own closure are not in the cache** (`system-path` for
  `e29c5d37`'s vm-toplevel, found while measuring). That is a separate
  observation, possibly an eviction or the repush gap. This task does not fix
  it. The PR notes it, and if it is real it goes in a follow-up issue.
- **CI-gate change** (§11). The owner merges; no auto-merge.

## Verification

- `checks.cache-budget`, green with the new default. **Break proof (§1):**
  - case (b) still fails 3010 MiB against 2560;
  - setting the default to 4096 must turn (b) red ("3 GB of allowlist passed").
    This shows the check really reads the figure the edit changes. Restore
    with `git checkout HEAD --`.
- The PR's `system` job prints "of a 2560 MiB budget", read from the run log,
  not assumed.
- `actionlint` on build.yml.
