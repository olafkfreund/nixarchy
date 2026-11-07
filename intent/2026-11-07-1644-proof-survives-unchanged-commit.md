---
status: draft
issue: 1644
author: x
---

# Intent: A check's proof survives a commit that changes nothing it builds

## Problem

`already-proven.sh` skips a check when its `outPath` is already in
nixarchy.cachix.org. That is sound: a check's output exists only if it passed.
But it only pays off when the `outPath` is unchanged, and today the commit
itself is an input to most of the tree, so no proof outlives its commit.

The carriers of commit identity found so far (read from the code; the
measurement below says which ones move a check):

- `flake.nix:531-548`: `nixarchyRev` and `nixarchyDate` from `self`, spliced into
  the `omarchy` package's install phase at `pkgs/omarchy/default.nix:1056-1062`
  for `nixarchy-version` (#208). Every check built on `omarchy` inherits it.
- `modules/nixos.nix:283-284`: `rev = inputs.self.rev` is written into the
  options catalogue's declaration URLs (`/etc/nixarchy/options.json`, #1166), so
  every system closure that imports the module moves per commit too, even with
  `omarchy` fixed.
  `packages.nixarchy-options` re-exports the same catalogue.
- `pkgs/microvm.nix:65`: `self.rev` pins `nixarchy vm` to its commit. It is not
  installer-only: `modules/apps.nix:3924` puts it on every installed system, and
  `checks.microvm-template` builds it (`flake.nix:2738`).
- `self.outPath` and every input's `outPath`, collected into the install checks'
  VM dependencies (`tests/install.nix:60-66`, `flake.nix:1585-1590`) and the
  ISO (`installer/cd.nix`). The source tree's store path changes on any commit,
  so these move by design, not through the rev.
- `self.rev` / `shortRev` in the `try` app (`flake.nix:1381`) and
  `installer/mkFlake.nix:22`, `installer/cd.nix:437`, which pin the installer to
  a commit on purpose.

So the checks split in two. Those built from `omarchy` or a NixOS configuration
can lose the rev and keep their proof. The real system toplevels
(`vm-toplevel`, `reference-toplevel`) and the install/ISO checks carry the
commit or the source tree by design, and a check of the machine a user really
gets should go on carrying it.

Measured on 2026-11-07, `nix eval .#<attr>.outPath` before and after a
docs-only commit (see "Measurement" below).

What it costs: every `main` push, and every pull request the gate
(`.github/scripts/pr-touches-build.sh`) judges relevant, rebuilds every VM check
(`session`, `coexist`, `integration`, `plugin`) even when the source change is
a comment, and the cache fills with proofs that can never be hit again. Some
documentation-only PRs already skip those jobs through that gate.
A second effect, not yet measured: `build.yml` checks out without a `ref`, so a
pull request run builds GitHub's merge commit (`refs/pull/N/merge`), whose rev
is neither the branch head nor the squash commit `main` later gets. While the
rev is in the closure, a PR's proof can never serve `main`.

## Proposed outcome

- A commit that changes no input of a check except the commit hash leaves that
  check's `outPath` unchanged, so `already-proven.sh` reports it proven and CI
  does not rebuild it. A named, short list of checks is exempt because it must
  carry provenance (the real toplevels, install and ISO checks), and the list
  says why for each.
- `nixarchy-version` still tells a user which commit and date built their
  machine (#208), and `options.json` still links declarations to the source at
  the right commit.
- A check exists that fails if commit identity leaks back into a check's
  closure (§1: it must be shown to fail).

## Affected users and systems

- `flake.nix` (`nixarchyRev`, `nixarchyDate`), `pkgs/omarchy/default.nix`
  (the splice and its own `nixarchy-version` self-check), `modules/nixos.nix`
  (catalogue `rev`), `pkgs/microvm.nix`, and whatever small derivation takes the
  rev instead.
- Readers of `options.json`: the picker in `modules/apps.nix:3460-3470`
  (`to_entries[]` over the top level), `tests/nixarchy-options.nix`, and the
  release asset (`.github/workflows/release.yml:252`).
- CI: `build.yml`, `omarchy.yml`, `nightly.yml`, `install-check.yml` callers of
  `build-unless-proven.sh` gain hits; no script change is expected.
- Users: none visible if `nixarchy-version` output is unchanged. A rebuild after
  a docs-only commit would no longer produce a new generation for omarchy.

## Constraints

- **Proof semantics stay as they are.** A proof is "this exact derivation
  passed", looked up by `outPath`; never by drvPath diff between commits
  (`already-proven.sh:9-13` explains why). This work removes noise from the
  inputs; it does not loosen the lookup.
- **Cache budget (§6).** No new allowlist entries; proofs are one small path
  each. Fewer distinct outPaths per week should lower cache churn, not raise it.
  `cache-budget.sh` must stay green.
- **§4/§5 traps.** Comparing closures across commits is normally meaningless
  (§5, `installer/cd.nix`'s `inputSources`), which is exactly the property under
  change: the measurement must compare two real commits and say which outputs
  are expected to differ (installer outputs) and which must not. An empty
  "to build" list must still never read as "all proven" by accident; the floor in
  `already-proven.sh:150-165` stays.
- **#208 stays honest.** A machine built from a dirty tree still says `-dirty`.
- **Not a goal:** skipping required CI jobs outright, pushing proofs from local
  builds (issue item 2, which also waits on the 2026-11-05 token rotation), or
  `build.yml`'s duplicate work (issue item 3). Each can be its own task.

## Measurement

`nix eval --raw .#<attr>.outPath` at `origin/main` (`6cd4e33f`) and again after
committing only this file:

| output | `6cd4e33f` | `c9679336` (adds this file only) | moved |
|---|---|---|---|
| `packages.omarchy` | `lqr5hmpy…-omarchy-4.5.0` | `5z0lkgn7…-omarchy-4.5.0` | yes |
| `checks.session` | `2bipljwi…-vm-test-run-nixarchy-session` | `g74dcdw9…` | yes |
| `checks.vm-toplevel` | `x41wb2nq…-nixos-system-nixarchy-…` | `1ii1mfsd…` | yes |
| `checks.package-delta` | `6xwp0j0k…-nixarchy-package-delta` | same | no |

So the issue's premise holds: a docs-only commit invalidates the proof of every
check that reaches `omarchy` or a system closure, while fixture-only
`runCommand` checks keep theirs. Not yet measured: whether `vm-toplevel` would
still move with only `omarchy` fixed (the catalogue `rev` predicts yes), and the
full list of moving checks (evaluating all of them is the memory-heavy row in
§6, left to the spec under the VM tier's gate).

## Open questions

1. **Where does the rev go?** Recommendation: a tiny last-step derivation (or a
   `/etc/nixarchy/version` file written by the module) that carries rev and
   date, with `omarchy` shipping `nixarchy-version` reading it. Keeps `omarchy`
   and everything built from it commit-independent; the real system toplevel
   still changes per commit, which is correct for it.
2. **The options catalogue's `rev`.** Linking to `main` instead would point old
   machines at the wrong source, so the commit stays in the URLs.
   Recommendation: rewrite the URLs at the last step and keep the file's shape.
   A top-level `rev` field would be read as an option by the picker's
   `to_entries[]` (`modules/apps.nix:3465`), so changing the shape needs every
   reader migrated, the release asset included.
3. **Which checks become commit-independent?** Recommendation: every check that
   tests behaviour (`session`, `coexist`, `integration`, `plugin`,
   `microvm-template`, the options shards), by giving their fixtures a fixed
   placeholder rev; `nixarchy-version` and the catalogue keep their own check
   that the real rev arrives. Exempt by name: `vm-toplevel`,
   `reference-toplevel`, the install trio and ISO checks, which carry the
   source tree by design. The cost of the placeholder is that those VM checks no
   longer test the exact bytes a user gets in `/etc`; the spec must say where
   the real rev is still asserted.
4. **Merge commit vs head (issue item 2's premise).** Recommendation: leave
   `build.yml`'s checkout alone in this task. Once the rev is out of a check's
   closure, the merge commit and the later squash commit produce the same
   outPath for the same tree content, so a PR's proof can serve `main` without
   any checkout change.
5. **The guard.** Recommendation: compare the outPaths of the non-exempt checks
   between two real commits that differ in a docs file (not two fake revs,
   which would miss `lastModifiedDate` and `self.outPath`), with the exempt list
   explicit, and prove it fails against today's splice. Whether this is a
   `checks.*` entry or a CI step is the spec's call: a flake check cannot
   evaluate two commits of itself, so it may need to live in a workflow step.
