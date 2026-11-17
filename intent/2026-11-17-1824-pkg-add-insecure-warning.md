---
status: draft
issue: 1824
author: x
---

# Intent: `nixarchy-pkg-add` warns after adding an insecure package

Follows `intent/2026-11-16-1814-pkg-index-insecure.md` (merged as #1818).

## Problem

`nixarchy-pkg-add` prints a note after adding an unfree package (the unfree
paragraph near `flags=" [unfree ..."` in `modules/apps.nix`) and after adding
a broken one (`[broken in nixpkgs -- expect the build to fail]`). It says
nothing for an insecure one. Someone who adds an insecure package by name from
the command line, without the picker, learns about it only when the rebuild
refuses it. The picker already says so: #1818 gave the package index an
`insecure` flag and a `Marked INSECURE in nixpkgs.` preview line, read from
`meta.insecure` and `meta.knownVulnerabilities`.

## Proposed outcome

After `nixarchy-pkg-add <name>` adds a package whose nixpkgs meta is insecure
(`meta.insecure == true`, or a non-empty `meta.knownVulnerabilities` list),
the row for that package in the report carries a notice worded like the
picker's line, next to the existing `[unfree ...]` and `[broken ...]` notices.
The package is still added (this is a warning, as for broken, not a refusal).
A package that is not insecure, or whose meta cannot be read, reports exactly
what it reports today.

## Affected users and systems

- Anyone adding packages by name: `nixarchy-pkg-add` and `--home` (same
  evaluation).
- `modules/apps.nix` (the `probe` expression and the flags paragraph),
  `tests/pkg-index.nix` or a sibling check.

## Constraints

- The meaning of "insecure" is the index's (`modules/pkg-index.nix`): `true`
  from `meta.insecure == true`, or a non-empty list in
  `meta.knownVulnerabilities`; a throwing meta or a malformed value is "not
  insecure" and never fails the add. One definition, not a second reading
  that could disagree with the picker.
- The probe already evaluates under `tryEval`; a throwing
  `knownVulnerabilities` must not turn a resolvable package into "no match".
- Output of the unfree and broken notices, and the report columns, do not
  change.

## Open questions

None. Wording: `[insecure in nixpkgs -- the rebuild will refuse it unless you
permit it]`, modelled on the picker's `Marked INSECURE in nixpkgs.` and the
broken notice's shape; the refusal is nixpkgs' own (`permittedInsecurePackages`).
