---
status: draft
issue: 1407
author: olafkfreund
---

# Intent: a hand-pinned Omarchy bump with a stale version string fails a check

## Problem

`flake.nix` names the Omarchy pin twice:

- `omarchy.url = "github:basecamp/omarchy/<tag>"` (:81);
- `omarchyVersion = "<version>"` (:540), the package's version, which
  becomes the system label, the ISO label and the release notes.

Only `omarchy.yml`'s automated bump step checks that the two agree
(:87-102). A hand pin, as in #1403 and in any emergency bump, can leave
`omarchyVersion` stale, and **every check passes**. #1403's C1 measured
it: with the url at `v4.5.0-rc1` and `omarchyVersion = "4.0.6"`,
`.#omarchy` built `omarchy-4.0.6` from 4.5 code.
`checks.omarchy-version-label` compares the package to `omarchyVersion`,
and `version-label.nix` compares revs, but neither compares the version
to the pin.

## Proposed outcome

- On stable (a tag pin), a check fails unless
  `"v" + omarchyVersion == flake.lock.nodes.omarchy.original.ref`.
- On edge (a rev pin, version `edge-<date>-<rev>`), the same check
  requires the version's rev part to match the locked rev, so edge
  keeps its own form and gains the same guard.

## Affected users and systems

- `tests/omarchy-version-label.nix` (extended) and its call in
  `flake.nix` (~:2525), which is passed the parsed `flake.lock`.
- Nobody's machine. It is a check.

## Constraints

- **§1:** red is the measured #1403 state (url `v4.5.0-rc1`, version
  `4.0.6`), and the edge form gets its own red (a mismatched rev).
- **Extend the existing check, not a new one.** It already owns "the
  version label is right" (#1371).
- Read the pin from `flake.lock`, not by parsing `flake.nix` text. The
  lock is what was actually built.
- Waits for #1405, since `main` is on the tag form there.

## Open questions

None. The mechanism is fixed by the issue, and the only choice (extend
rather than add a check) follows the repo's rule.
