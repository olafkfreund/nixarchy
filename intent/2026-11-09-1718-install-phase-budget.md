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
- #1707 (Osaka Jade, #1698) added install lines. `main`'s tag pin still fits:
  122,676 bytes measured on 2026-11-09, which leaves 324. Edge's quattro pin
  adds more of its own, and the two together go over.
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
- The built `omarchy` output is unchanged.

## Affected users and systems

- `pkgs/omarchy/default.nix` (comments only) and `pkgs/AGENTS.md`.
- The edge channel's users, who get no new quattro build until this lands.
- No change to what ships: only comment text leaves the phase.

## Constraints

- Comments only. No line of shell changes, so the output path changes only
  because the phase's text does. That is checked by building the omarchy
  tree before and after and comparing the trees, not their paths (§5:
  paths always move).
- The budget number and the check stay as they are. Raising the budget
  removes the warning but leaves the ceiling where it is.
- Switching omarchy to `__structuredAttrs` would remove the limit, but the
  check calls it "a larger change". It is out of scope here.
- The headroom is measured on both pins (main's tag, and edge's quattro),
  because the budget failed only on the second.

## Open questions

1. How much headroom is enough? Proposed: at least the 8,058 bytes #997
   left after its move, measured on the larger of the two pins.
2. Which paragraphs move? Proposed: the largest explanation blocks, each
   kept whole under its own `pkgs/AGENTS.md` heading. The spec names them.
