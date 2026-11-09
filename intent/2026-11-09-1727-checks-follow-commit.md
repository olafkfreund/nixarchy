---
status: draft
issue: 1727
author: x
---

# Intent: the installer's checks stop rebuilding on every commit

## Problem

#1644 set out to make a check's proof survive a commit that changes nothing
it builds. Checks get a placeholder `self` (`checkInputs`, `flake.nix:907`),
and the nightly's `commit-independent` guard names any check that still
moves. Only those in `data/commit-bound-checks.nix` may move, each with a
reason.

The guard first ran to the end in nightly 42643186698, after #1719. Seven
unlisted checks moved:

- `installer-early-exit`, `installer-input-validation`, `initrd-pin-guard`
- `installer-wizard`, `install-stock-iso` (VM checks)
- `reinstall-image`
- `stable-eval`

So the nightly is red, and #1685 cannot close. Each of these checks also
rebuilds on every pull request and every push to `main`, because no proof
can carry over. Two are VM checks, which cost minutes and a self-hosted slot
each time.

What carries the commit was measured in the issue, by `nix-diff` across a
no-op commit:

1. **The installer package reaches the real `self`.** The six installer
   checks differ at `nixarchy-flake-template`, whose `rev`, `url`, `narHash`
   and `lastModified` follow the commit. `installer-early-exit` reads
   `self.packages…install` directly (`flake.nix:2326`). The others read
   `inputs.self.packages…install` and still get the real rev, by a route
   not yet traced.
2. **The placeholder is incomplete.** `installer/mkFlake.nix` reads
   `self.narHash` and `self.lastModified` as well as `self.rev`.
   `checkInputs.self` overrides only `rev`, `shortRev` and
   `lastModifiedDate`. So even a check that does get the placeholder
   template would still move.
3. **`stable-eval`** evaluates a whole 26.05 machine, and its toplevel moves.

## Proposed outcome

- The six installer checks build against the placeholder `self`. A commit
  that changes nothing they build leaves their output paths unchanged, so
  CI reuses their proofs.
- `stable-eval` is either fixed the same way or listed in
  `data/commit-bound-checks.nix` with a provenance reason, as the spec
  decides.
- The nightly's `commit-independent` job is green, and #1685 can close.
- Each fixed check has a §1 break: point it back at the real `self`, and
  the guard names it.

## Affected users and systems

- CI only. Proof reuse in `build.yml` and `install-check.yml`, and the
  nightly's guard. VM checks stop taking a self-hosted slot on commits that
  do not touch them.
- No installed machine changes. The real installer package, the ISO and the
  generated flake keep the real rev, URL, `narHash` and `lastModified`.
  `installer-lock` and `iso-source` stay commit-bound, and they are what
  assert that.

## Constraints

- **What ships must still pin the real commit.** Only checks get the
  placeholder. The real `self.packages.install`, the ISO and the reinstall
  image are unchanged. The drvPath of each real output must be identical
  before and after, compared in the same tree (CLAUDE.md §5).
- **A placeholder must not make a check pass for the wrong reason.** A check
  that asserts something about the real rev or `narHash` belongs in the
  commit-bound list, not on the placeholder. `installer-lock` and
  `nixarchy-options` already are.
- **The guard is not loosened.** `data/commit-bound-checks.nix` gains an
  entry only with a provenance reason, never to make the nightly green
  (owner, 2026-11-09).
- **Measure before editing** (#1644's rule): run the guard locally on the
  seven names first. Every carrier the spec names must come from that
  measurement.
- **Local checks by §6 tier before any push**, including the two VM checks
  and the guard itself. The guard runs evaluation only, but over the whole
  check set.

## Open questions

1. **`stable-eval`: fix or list?** It evaluates a stable-channel machine,
   which is a function of the inputs. I lean towards fixing it: the
   machine a user gets is already asserted by `vm-toplevel` and
   `reference-toplevel`, which are commit-bound. If the spec finds it
   asserts something only the real commit can show, it gets listed instead.
2. **The placeholder's `narHash` and `lastModified`.** The likely answer is
   fixed values beside the zero rev, as `lastModifiedDate` already has. The
   spec has to check that nothing evaluated on the placeholder `self` reads
   `narHash` as a real hash of real content.
