---
status: approved
issue: 1231
author: olafkfreund
---

# Intent: room in the cache allowlist budget

## Problem

`cache-budget.sh` (build.yml's `system` job, `CACHE_BUDGET_MIB: "2048"`)
measured #1227's allowlist at **1953 MiB of 2048 MiB**. 1978 MiB was the local
figure. The next entry that adds about 70 MiB, or an ordinary growth of a
closure such as a kernel, Mesa or QEMU bump, fails the step on whichever
pull request crosses the line. That pull request will usually have nothing to
do with the cache.

The largest paths, from that run:

| MiB | path | from |
|---|---|---|
| 395 | qemu-host-cpu-only-for-vm-tests | all eight KVM runners |
| 390 | docker-image-archlinux-latest.tar | box-test-image |
| 128 | source (flake inputs) | both toplevels |
| 125 | omarchy-4.0.4 | omarchy, both toplevels |
| 118 | docker-image-debian-trixie.tar | box-test-image |
| 101 | index-x86_64-linux | both toplevels |

The 2 GB figure is #697's arithmetic (`spec/2026-09-15-697-cache-allowlist.md`).
The cache is the free tier, 5 GB evicted by last download. A commit's
allowlist then measured about 1.05 GB, so 2 GB allowed it to grow twofold
while the current and the previous commit still fit in 5 GB. It has now grown
almost twofold.

## Proposed outcome

There is enough headroom for the next several ordinary additions. The reason
the cache can afford it is written down and measured, not assumed. The budget
step remains a gate.

## Affected users and systems

- `.github/workflows/build.yml`: the budget value, if it changes. That is a
  CI-gate change, so a human merges it (§11).
- `.github/scripts/cache-allowlist.sh`, if an entry goes.
- Users and CI runners: anything dropped from the allowlist is built locally
  instead of downloaded.

## Constraints

- **The free tier stays 5 GB.** Paying for more is out of scope.
- **Whatever replaces "2 GB" needs a measurement behind it.** That means the
  real overlap between two consecutive `main` commits, not a fresh guess. #697
  assumed the two commits overlap only partly. Much of the 1953 MiB never
  changes from commit to commit (QEMU, the Docker images), and that is what
  may justify a higher figure.
- **An entry can be dropped only with its reason answered.** Each allowlist
  entry names who downloads it. The box images are there because Docker Hub is
  not ours (#788, #800).

## Open questions

1. **Raise the budget, or trim the list?** I recommend measuring first, then
   raising. The measurement is the per-commit churn: the paths that differ
   between two consecutive `main` allowlists. If that churn is a few hundred
   MiB, then about 3 GB for one commit plus one commit's churn still fits in
   5 GB with room for proofs. Trimming instead costs users a download. The
   Debian box image (118 MiB) is the only entry I can see that might go without
   a real cost, and only if no test or default uses it.
2. **If raised, to what?** Decided once the measurement exists. It goes into
   the spec.
