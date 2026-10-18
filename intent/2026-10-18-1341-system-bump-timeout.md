---
status: draft
issue: 1341
author: olafkfreund
---

# Intent: a nixpkgs bump finishes inside the system job's limit

## Problem

`build.yml`'s `system` job (`:1306`, hosted `ubuntu-latest`) has a
45-minute limit (`:1318`). That limit is deliberate: its comment says a
normal run takes about 20 minutes, and 45 fails a hung job in under an hour
while still surviving a 20-minute substituter stall (411c6a4).

A nixpkgs bump breaks that assumption. It changes every derivation, so
`build-unless-proven.sh` finds no proof for any check, and one job runs the
whole suite in sequence. #1332 hit the limit twice
(jobs 117614595642 and 117666616240), each time with every check that had
finished green. #1294 timed out twice before it, for a different reason.
Measured on #1332, the steps that dominate are:

| step | minutes |
|---|---|
| Build the allowlisted tools and box image (`hypr-rdp`, `box-test-image`) | 10 |
| `session` | 9–10 |
| `plugin` | 5 |
| `options` | 4 |
| VM system closure | 3 |

So a bump PR ends `cancelled`. That turns off auto-merge, and the nightly bump
stalls until someone re-runs the job by hand. A re-run passes, because the
first attempt pushed proofs, but "re-run until green" is the habit §10 warns
against: a timeout and a real failure look alike in the summary (§6).

## Proposed outcome

- A nixpkgs bump PR's `system` work completes without a manual re-run, and
  auto-merge carries it through.
- A hung job still fails in well under an hour; the reason for the 45-minute
  cap keeps holding.
- When something does time out, the job's name says which part did.

## Affected users and systems

- `.github/workflows/build.yml`, and possibly the required-checks list if a job
  is renamed or added.
- Every pull request's merge latency, and the hosted-runner minutes per bump.
- The nightly nixpkgs bump workflow that opens these PRs.

## Constraints

- A CI-gate change (§11): this work can propose it in a PR; a maintainer
  merges it.
- Required checks must not end up `skipped` and still pass the gate (§4,
  #1144). Any new job is either required or provably covered.
- The cache rules stand: PRs push proofs only; closures go to cachix only from
  `main` and only from the allowlist (§6).
- Nothing moves to the self-hosted p620 runners that would compete with the two
  install slots (§6).

## Open questions

1. **Split or raise.** Moving the allowlisted-tools build (10 min, and only
   needed to publish from `main`) and/or `session` into their own jobs keeps
   45 meaningful. Raising the limit for bump PRs only is smaller, but it
   weakens the hang guard exactly when the most changes. The spec should
   measure a split's real saving, including each new job's own setup.
2. Whether pull requests need to build `hypr-rdp` and `box-test-image` at all,
   or only `main`, which is what publishes them.
