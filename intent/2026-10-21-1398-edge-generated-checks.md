---
status: draft
issue: 1398
author: olafkfreund
---

# Intent: edge publishes again: green on its full check list, and on the newest quattro

## Problem

Nothing has reached the edge channel since #1392 merged. Not main's merges
(#1392–#1397, including #1396's plugin pins), and not new carries such as
#1386.

Run 39553533096 failed in `prepare` for two independent reasons.

**1. Edge has been red at quattro 0a7beb7 since before today; nothing saw it
until now.** Until #1392, edge verify built a hand-kept list of 7 checks.
Now it builds `generated-checks.sh`'s list, and #1394's fallback must
pass the same list. Five checks fail on `origin/edge` (14888ef8) exactly as
it is, with main not merged in (reproduced locally, logs
`/mnt/data/vmtest/edge-only-*.log`):

| check | failure | first read |
|---|---|---|
| `menu-conditions` | `omarchy-launch-floating-terminal-with-presentation`: `setsid: not found`, so the editor and browser setters fail; `system.hibernate` no longer asks `omarchy-hibernation-available` | `setsid` is a missing runtime input, a real bug for edge users; the hibernate one may be an upstream change the check encodes |
| `provision-launchers` | none of the 14 agent launchers are seeded into `~/.local/bin`; no stub for an empty name | quattro changed how launchers are provisioned (likely the mise `[wrappers]` / lazy shims that #1386 also meets) |
| `launch-browser-self-call` | the patched launcher exits 0, the check wants 1 | the patch or the check is stale against quattro's launcher |
| `menu-guidance` | "remove fingerprint" no longer says "Nothing on this machine was changed" | an upstream wording or flow change, or a lost patch |
| `stale-scripts` | `omarchy-install-service-spotify` calls `omarchy-webapp-install` and `omarchy-hw-x86`, which are not found | commands quattro renamed or added that this port does not ship |

**2. Quattro 087f73d (newest) does not build.** A `--replace-fail` anchor
in `bin/omarchy-version-channel` is gone upstream:
`if grep -q "https://stable-mirror.omarchy.org/" /etc/pacman.d/mirrorlist; then`.

**And the failure digest (#1393) missed reason 2.** It printed "no error
lines" for that derivation, while the log holds
`substituteStream() … ERROR: pattern … doesn't match`. A failure digest
that cannot see the most common edge failure, patch drift, defeats its
purpose.

## Proposed outcome

- `origin/edge` passes the full generated check list on the newest
  quattro, and the scheduled run publishes.
- Each of the five reds is resolved one of two ways, chosen per check and
  said in the PR:
  - **a real edge bug is fixed** as a carry on `edge-candidate`, for
    example a missing `setsid` runtime input or an unshipped command;
  - **a check that encodes behaviour quattro deliberately changed is
    retargeted** (CLAUDE.md §1, read backwards), with the reason.
- The `omarchy-version-channel` patch is re-anchored on quattro's new code,
  or dropped if upstream now does what it did.
- The digest names a `substituteStream() … ERROR` line (fixed on `main`,
  where the script lives).
- After that, one `from_candidate` run, with your go-ahead, carries main's
  merges plus #1386 to edge.

## Affected users and systems

- Edge users: they get no updates until this lands. `menu-conditions`'
  `setsid` failure may mean the editor and browser pickers are broken on
  edge machines today.
- `edge-candidate`: carries in `pkgs/omarchy/default.nix` and perhaps
  `data/bin-ledger.nix`, plus the checks under `tests/`.
- `main`: `.github/scripts/failure-digest.sh` and its fixture
  (`tests/failure-digest.nix`).

## Constraints

- **Workflows are not changed** to make edge pass. Exempting checks
  from edge's list would hide exactly what #1392 exposed (§4).
- **One carry per cause.** A later quattro bump that drops one can then
  revert it alone.
- **§1:** each fix is proved by its existing check going green on the
  broken edge, which is already red. A retargeted check also needs a red
  case of its own.
- **§11:** pushing carries to `edge-candidate` is the established flow.
  The promotion dispatch needs your go-ahead.
- **Order:** #1386's carry joins the same `from_candidate` run, and is
  not promoted ahead of these fixes.

## Open questions

1. **One task or several?** I propose one intent and spec with a
   per-check table, and separate carry commits. The causes share a single
   gate (edge publishing), but each one is small.
2. **The digest fix:** in this task (a one-line pattern plus a fixture
   log, on `main`), or its own issue? I propose this task, because it is
   how reason 2 was missed.
3. **If a red turns out to be a real upstream bug** that Omarchy should
   fix, such as quattro's spotify installer calling a command quattro does
   not ship: should it go upstream (drafted for your approval, never
   posted unprompted), or be carried here meanwhile? I propose carrying
   here and drafting upstream.
