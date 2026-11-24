---
status: draft
issue: 1934
author: x
---

# Intent: omarchy-mise-unshadow reads only scripts

## Problem

`omarchy-mise-unshadow` runs in Home Manager activation, which is ordered before
`systemd-user-sessions`, so its time is login time. For every file in
`~/.local/bin` that is not a generated launcher it greps the whole file for
`mise`. On p620 that is 285 MB of unrelated binaries, and the step took 4.1 s of
the 2026-11-24 boot.

## Proposed outcome

The "left in place" scan reads only files that start with `#!`. Activation no
longer reads large binaries, and a compiled binary that contains the string
`mise use` is no longer listed in the notice as a mise launcher.

## Affected users and systems

Every nixarchy user with files in `~/.local/bin`; the cost grows with their size.

## Constraints

Generated launchers are still removed byte-for-byte as before; a hand-written
script that calls mise is still listed.

## Open questions

None.
