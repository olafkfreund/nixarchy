---
status: approved
issue: 1727
author: x
---

# Intent: the installer's checks stop following the commit

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

So the nightly is red, and #1685 cannot close. A check whose output path
moves cannot reuse a proof, because proofs are keyed by output path
(`build-unless-proven.sh`). The guard measures the path moving; how often CI
then rebuilds depends on what each workflow builds.

**How the guard probes.** It is not an empty commit. The guard adds a tracked
file, `.commit-probe`, and commits two days later
(`commit-independent.sh:59-63`). So `rev`, `narHash`, `lastModified` and the
tree's `outPath` all change (agy). Anything that copies or hashes the whole
tree moves, as well as anything that reads the commit's metadata.

**What carries it, measured** by `nix-diff` across that probe, on `main`
`7fa60492`:

1. **`installer-early-exit` reads the real `self`.** `flake.nix:2326` uses
   `self.packages…install`, where its neighbours use `inputs.self` (which is
   `checkInputs` in the checks scope). Its `nixarchy-flake-template` moves in
   `rev`, `url`, `narHash` and `lastModified`.
2. **The placeholder is incomplete.** `installer/mkFlake.nix` reads
   `self.narHash` (`:50`) and `self.lastModified` (`:63`) as well as
   `self.rev`. `checkInputs.self` overrides only `rev`, `shortRev` and
   `lastModifiedDate`.
   - `installer-input-validation`, `initrd-pin-guard` and `installer-wizard`
     already get the zero rev, and move only in `narHash` and `lastModified`.
   - `install-stock-iso` and `reinstall-image` move under their driver
     configuration and launcher. Which field carries the commit there is not
     yet measured to the leaf.
3. **`stable-eval`'s** `toplevel` is a different 26.05 system derivation.
   `stableInputs` is already built from `checkInputs` (`flake.nix:505`), so
   what in it still carries the commit is not yet traced (agy).

## Proposed outcome

- The six installer checks no longer move with a commit that changes
  nothing they build. Each still tests the same installer behaviour it tests
  today.
- `stable-eval` no longer moves, unless the spec traces its carrier to
  something `stable-eval` exists to check. In that case it is listed, with
  the provenance reason.
- The nightly's `commit-independent` job is green, and #1685 can close.

## Affected users and systems

- **CI:** proof reuse, and the nightly guard.
- **What ships does not change.** The real `self.packages.install`, the
  ISOs, the reinstall image and the generated flake keep the real commit's
  `rev`, `url`, `narHash` and `lastModified`.

## Constraints

- **Placeholder metadata never reaches what ships** (Codex). It must not
  reach an ISO, an installed machine's `/etc/nixos/flake.lock`, or any
  package outside `checks`.
  - The proof: each real output's drvPath is identical before and after,
    compared in the same tree (CLAUDE.md §5).
  - Also, no `packages` or `nixosConfigurations` output evaluates
    `checkInputs`.
- **A check keeps testing what it tests today** (Codex).
  - Moving a check onto the placeholder may change only where it gets the
    commit's metadata, not which package, script or machine it exercises.
  - Each §1 break must hold the same property. Re-introducing the carrier,
    for example the real `narHash`, makes the guard name the check, and
    nothing else in the check changes.
- **A placeholder must be one a real flake could have** (agy).
  - `lastModified` agrees with `lastModifiedDate`: `0` and
    `19700101000000`.
  - `narHash` is a well-formed SRI `sha256-` hash.
  - If a VM check parses, locks or fetches the generated flake, the spec
    must show the placeholder does not change what it does, or that check
    stays on real metadata and is listed.
- **What asserts the real values today must stay real.** Today:
  - `installer-lock` checks that every field `mkFlake` writes (`rev`,
    `narHash`, `lastModified`) is present and well-formed
    (`tests/installer-lock.nix:42-68`);
  - `nixarchy-options` asserts the real rev;
  - `iso-source` reads `realInputs` (`flake.nix:2286`).

  The spec states which of these, if any, checks that the values equal the
  real commit's. If none does for `narHash` and `lastModified`, it says so.
  It does not claim more (Codex).
- **The guard is not loosened.** `data/commit-bound-checks.nix` gains an
  entry only with a provenance reason, never to make the nightly green
  (owner, 2026-11-09).
- **Measure before editing** (#1644's rule). The spec's carriers for
  `install-stock-iso`, `reinstall-image` and `stable-eval` come from a
  leaf-level `nix-diff`, not inference.
- **Local checks by §6 tier before any push**, including the two VM checks
  and the guard. The guard is evaluation only, but it runs over every check
  (about 66 minutes, 13 GB peak, per #1644).

## Open questions

1. **`stable-eval`.** What in it carries the commit, given `stableInputs`
   starts from `checkInputs`? And is that carrier part of what `stable-eval`
   exists to check? It evaluates the stable-channel machine, and no other
   check does, so `vm-toplevel` does not cover it (Codex). I propose the spec
   traces it first. Then it is fixed if the carrier is incidental, or listed
   if the carrier is the point.
2. **`reinstall-image`: shipped artifact or check?** The spec states what
   `checks.reinstall-image` tests. That way, moving it to the placeholder
   cannot leave the shipped reinstall image unchecked (agy).

## Decisions (owner, 2026-11-09)

- Approved as revised: the six installer checks are fixed, not listed.
- `stable-eval` and `reinstall-image` follow the open questions as proposed: trace the carrier first, then fix or list with a provenance reason.
