---
status: draft
issue: 1718
author: x
---

# Intent: the omarchy install phase fits its budget on both pins

## Problem

The Omarchy edge channel has not published since 2026-11-09 01:30 (#1718).
Both runs that day, 42544068473 and 42571154200, stopped in `prepare` on
`checks.install-phase-budget`:

    omarchy installPhase: 123181 bytes
      budget 123000, ceiling 131058
      -181 bytes before this check fails, 7877 before the build does

- `pkgs/omarchy/default.nix`'s `installPhase` reaches the builder as one
  environment string. Past 131,058 bytes, `execve` refuses it with
  "Argument list too long" and names nothing (#948, #997). The budget
  (`tests/install-phase-budget.nix`, #1047) fails first, with 8,058 bytes
  to spare.
- #1707 (Osaka Jade, #1698) added install lines. `main` still fits at
  122,676 bytes (measured on 2026-11-09), 324 bytes under budget.
- Edge's merged tree is 505 bytes longer (measured on 2026-11-09 by diffing
  the two evaluated phases). None of the extra comes from Omarchy's source:
  - a quattro-only screensaver substitution edge carries in `default.nix`
    (#1485, about 330 bytes);
  - the version string, `edge-20261108-d9cc361` in place of `4.5.0`, which
    appears four times;
  - `--no-backup-if-mismatch` on one `patch` line.

  So overriding the Omarchy input on `main` does not reproduce edge's
  figure. Only edge's merged tree does.
- So edge refuses every run, and the next addition to `main` of about 330
  bytes turns `main` red as well.
- The phase holds 47,420 bytes of comment lines (measured on `main`), and
  its largest single blocks are about 900-1,200 bytes each. The check's own
  message names the remedy: move explanation into `pkgs/AGENTS.md` and leave
  a `# Why:` pointer (CLAUDE.md §7).

## Proposed outcome

- `checks.install-phase-budget` passes on `main` and on edge's merged tree,
  with room for normal growth on both pins.
- Edge publishes again; #1718 closes on its next green run.
- The moved explanation is still where someone editing the phase finds it:
  a section in `pkgs/AGENTS.md`, and a pointer at the line it explains.
- The shell the builder runs is unchanged: the evaluated `installPhase`,
  with comment lines removed, is byte-identical before and after.

## Affected users and systems

- `pkgs/omarchy/default.nix` (comments only) and `pkgs/AGENTS.md`.
- The edge channel's users, who get no new quattro build until this lands.
- No change to what ships: only comment text leaves the phase.

## Constraints

- Comments only. No line of shell changes.
  - Comparing the built trees cannot show that: the output path moves with
    the phase's text, and the tree embeds its own path (`$out/bin` links,
    generated scripts). So it would differ even for a correct change (Codex
    review).
  - Nix strips the smallest indent shared by every line of the phase
    (`pkgs/AGENTS.md`, "A long build phase is one indented string"). If a
    removed comment held that minimum, every remaining line would be
    reindented.
  - Both are covered by comparing the evaluated phase with comment lines
    removed: same bytes, same indentation.
- The budget number and the check stay as they are. Raising the budget
  removes the warning but leaves the ceiling where it is.
- Switching omarchy to `__structuredAttrs` would remove the limit, but the
  check calls it "a larger change". It is out of scope here.
- The headroom is measured on `main` and on edge's merged tree (`main`
  merged into `edge-candidate`), because the budget failed only on the
  second. Bytes are measured with `builtins.stringLength` on the evaluated
  phase after `nix fmt`, never estimated from the comment text: every line
  keeps the phase's shared indent.

## Open questions

1. How much headroom below the 123,000 budget is enough, measured on edge's
   merged tree? The 8,058-byte figure in the check's comment is the gap
   between the budget and the ceiling, not headroom below the budget.
   Proposed: at least 3,000 bytes, about three of the largest blocks.
2. Which comments go? Proposed, in this order:
   - delete the comments for patches that are already gone, and the ones
     whose explanation `pkgs/AGENTS.md` already holds, keeping or adding a
     `# Why:` pointer to the existing anchor. agy named candidates:
     - the #1153 and #1155 comments at `default.nix:445-453`, whose patch
       files no longer exist in `pkgs/omarchy/` (checked 2026-11-09);
     - half a sentence at `:1093` whose first half is already in
       `pkgs/AGENTS.md`;
     - the `# Short version:` blocks beside existing pointers;
   - then move the largest remaining blocks, each whole under its own
     heading.

   The spec names each one.
3. This is the second time a change passed the budget on `main` and failed
   it on edge. `pkgs/AGENTS.md`'s #1663 note says "this text tipped the edge
   build over it". `main` measures only its own tag pin. Should the headroom
   target account for quattro's growth, or should `main` measure the budget
   against quattro too? Proposed: the headroom target only, in this change.
   A second measurement is a separate decision for the owner.
