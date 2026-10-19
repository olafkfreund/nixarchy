---
status: draft
issue: 1346
intent: intent/2026-10-18-1346-pin-hosted-runner.md
---

# Spec: every hosted job runs on an image we chose

## The measurement

Throwaway PR #1348 (`test/ubuntu-26.04`, from `main` 4ce13f24) had every
`ubuntu-latest` in `.github/workflows/` replaced with `ubuntu-26.04`. Its
logs show `Image: ubuntu-26.04`. Results, run 39172648991 plus the install
and Copilot runs:

| job | on 26.04 |
|---|---|
| gate, build gate, apps, box, devenv-presets, omarchy, system, install, copilot-setup-steps | pass |
| lint | **fail**, on one thing only: actionlint 1.7.12 (our pinned nixpkgs) does not know the label, `label "ubuntu-26.04" is unknown` |

`box`'s KVM step, `Free disk space` and the Determinate installer all
worked on 26.04. Adding the label to `.github/actionlint.yaml` makes the same
actionlint invocation exit 0 on that tree (measured locally).

Not measured: workflows that do not run on pull requests (nightly, release,
review, weekly, wiki, update, omarchy, omarchy-edge, flake-update,
copilot-handoff). They meet 26.04 at their next run after the merge, which
is the same exposure the rollout would give them, minus the coin toss.

## Design

**Pin `ubuntu-26.04`.** The intent's first question is answered by the
measurement: the hosted jobs pass there, and 26.04 is where `ubuntu-latest`
is going anyway. Pinning 24.04 would only move this decision to a later date,
with nothing tested in between.

1. **Every functional `ubuntu-latest` becomes `ubuntu-26.04`:** the 23
   `runs-on:` lines (the fallback at `install-check.yml:329` among them) and
   the gate's `runner=["ubuntu-latest"]` output (`install-check.yml:188`).
2. **Comments:** `build.yml:1738` ("ubuntu-latest runners have /dev/kvm …")
   is a statement about now, so it names `ubuntu-26.04`. The comments at
   `install-check.yml:250` and `nightly.yml:116,425` record what happened on
   the image of the time; they stay as written.
3. **`.github/actionlint.yaml`:** `ubuntu-26.04` joins the labels, with a
   one-line comment that it is a GitHub image actionlint 1.7.12 predates, to
   drop when the pinned actionlint knows it. The file's own comment says a
   label nobody carries queues forever; this one GitHub carries.
4. **The guard (the intent's second question): in `lint`.** A step,
   "No hosted job runs on a moving image label", fails when any non-comment
   line under `.github/workflows/` names `ubuntu-latest`, printing each
   `file:line`. Its own pattern is written split (`'ubuntu-''latest'`) so it
   does not match itself. Lint runs on every pull request in seconds, and it
   is where a new job is written.

Changing the image later is then one reviewed `sed` plus the guard, never a
GitHub schedule.

## Alternatives rejected

- **Pin `ubuntu-24.04`.** Supported for years, but it defers a move the
  measurement shows is ready, and the next move is the same work with less
  notice.
- **Leave `ubuntu-latest`.** A month in which the same job runs on either
  image, which is the problem.
- **Upgrade actionlint instead of declaring the label.** It is pinned with
  nixpkgs, and a nixpkgs bump for a lint label is out of scope. The label
  entry is one line with a removal condition.
- **The guard in the nightly.** It would find a drifted job a day after it
  merged, not on the PR that adds it.

## Risks

- **A workflow nobody measured fails on 26.04** (the nightly, a release).
  It fails loudly at its next run, on a named image, which is a cleaner
  failure than one that comes and goes. The PR lists them, so whoever reads
  the first red knows where to look.
- **The guard's exclusion of comments** is a regex on `^\s*#`. A YAML value
  with `#` in a string is not a comment line, so it cannot hide one.

## Verification

- `actionlint` (the `lint` invocation) on the changed tree: clean.
- `grep -rn 'ubuntu-latest' .github/workflows/` names only the three history
  comments.
- **The guard fails** (§1): with one `runs-on: ubuntu-latest` put back, the
  step's script exits 1 and names the line; restored, it exits 0. Run under
  bash as a script, as CI does.
- The PR's own run: every job green on `ubuntu-26.04`.
- A maintainer merges (§11).
