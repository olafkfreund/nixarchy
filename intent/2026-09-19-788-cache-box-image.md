---
status: approved
issue: 788
author: olafkfreund
---

# Intent: a Docker Hub outage does not turn main red

Closes #788.

## Problem

`checks.box-template` and `checks.box-boot` pull the box templates' base
images from Docker Hub with `dockerTools.pullImage`. The images are pinned by
digest (the `boxImagePins` in `flake.nix:2153`, which today are `archlinux`
and `debian`), so what they fetch never changes. Where they fetch it from does
not change either: nothing puts these images in nixarchy.cachix.org, so every
runner that does not already have them in its store downloads them from Docker
Hub.

On 2026-09-19, `main`'s build after #779 went red in `box` because Docker Hub
answered one blob request with **502 Bad Gateway**. The re-run passed, and the
same job had passed on two PR branches minutes earlier. Nothing in the repo was
wrong. For as long as this setup stays, any Docker Hub bad minute makes `main`
red and needs a person to notice and re-run it.

## Proposed outcome

- The box checks get their images from somewhere nixarchy controls, so a
  Docker Hub outage no longer fails them. A run on a cold runner still passes
  with Docker Hub unreachable.
- There is one place each image digest is declared, not one per test.
- The cost against the cache budget is measured and written down.

## Affected users and systems

CI only: the `box` job and the two checks above, `flake.nix`, and the
cache allowlist and its budget. Nothing changes on any installed machine.

## Constraints

- **The allowlist has a rule against exactly this.** Its header, from #725,
  says an entry belongs there only if someone "would otherwise build it", and
  that caching a download "makes this a slower second mirror". A Docker image
  saves no build time. What it buys is **availability**, which is a new reason
  for this list. It has to be an explicit owner decision, recorded next to the
  entry and in the header, not slipped in.
- **The 2 GB budget** (`cache-budget.sh`) must still pass, with both images
  measured.
- **Show the fix works (§1):** with the images absent from the store and Docker
  Hub unreachable, the box check must fail before the change and pass after it.
- Changing the allowlist is not a CI-gate change (§11): no workflow trigger,
  required check or timeout moves.

## Decisions (owner, on approval, 2026-09-19)

1. **Availability is a reason for the cache list.** It's an explicit exception
   to the #725 rule, written into `cache-allowlist.sh`'s header and next to
   the entry.
2. **Every pinned box template image is cached,** not only the default: today
   archlinux and debian, and each new template adds one. The budget measures
   them.

## Open questions

None.
