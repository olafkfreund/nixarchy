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
- `flake.nix:1381`: `self.rev` in the `try` app script. Installer-only:
  `installer/cd.nix:437`, `installer/mkFlake.nix:22`, `pkgs/microvm.nix:65` --
  these pin the installer to a commit on purpose and are not in scope.

Measured on 2026-11-07, `nix eval .#<attr>.outPath` before and after the
docs-only commit that adds this file (see "Measurement" below).

What it costs: every PR and every `main` push rebuilds every VM check
(`session`, `coexist`, `integration`, `plugin`, the install trio) even when the
diff is a comment, and the cache fills with proofs that can never be hit again.
A second effect, not yet measured: `build.yml` checks out without a `ref`, so a
pull request run builds GitHub's merge commit (`refs/pull/N/merge`), whose rev
is neither the branch head nor the squash commit `main` later gets. While the
rev is in the closure, a PR's proof can never serve `main`.

## Proposed outcome

- A commit that changes no input of a check except the commit hash leaves that
  check's `outPath` unchanged, so `already-proven.sh` reports it proven and CI
  does not rebuild it.
- `nixarchy-version` still tells a user which commit and date built their
  machine (#208), and `options.json` still links declarations to the source at
  the right commit.
- A check exists that fails if commit identity leaks back into a check's
  closure (§1: it must be shown to fail).

## Affected users and systems

- `flake.nix` (`nixarchyRev`, `nixarchyDate`), `pkgs/omarchy/default.nix`
  (the splice and its own `nixarchy-version` self-check), `modules/nixos.nix`
  (catalogue `rev`), and whatever small derivation takes the rev instead.
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

1. **Where does the rev go?** Recommendation: a tiny `nixarchy-version`
   derivation (or a `/etc/nixarchy/version` file written by the module) that
   carries rev and date, with `omarchy` shipping the script with placeholders
   resolved at that last step. Keeps `omarchy` and everything above it
   commit-independent; only the top-level system closure changes per commit.
2. **The options catalogue's `rev`.** Linking to `main` instead would point old
   machines at the wrong source, so the commit stays in the URLs.
   Recommendation: rewrite the URLs in the same last-step derivation as (1), or
   store repository-relative paths in `options.json` beside one `rev` field.
   The spec chooses after reading every reader of `options.json`.
3. **Should system-level checks (`vm-toplevel`, `session`) be commit-independent
   too, or only checks built on `omarchy`?** Recommendation: all checks. A VM
   check that embeds the rev only through `/etc` text gains nothing from
   testing it, and `session` is the most expensive thing a docs PR rebuilds.
   The rev should reach the machine's real system, not the test fixtures, or
   the fixtures should use a fixed placeholder rev.
4. **Merge commit vs head (issue item 2's premise).** Recommendation: measure in
   the spec, do not change `build.yml`'s checkout here; once the rev is out of the
   closure the merge commit and the squash commit build the same outPaths for an
   unchanged tree content, and the question only matters for proofs reused
   across different tree contents, which is never sound.
5. **The guard.** Recommendation: a cheap evaluation check that evaluates a
   chosen set of check outPaths under two fake `self` revs and asserts equality,
   proven to fail by restoring the current splice.
