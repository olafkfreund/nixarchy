---
status: approved
issue: 1140
author: olafkfreund
---

# Intent: the replaced-pacman-scripts count measures upstream, not our comments

## Problem

README.md says "Six of those are replaced outright, in
`pkgs/omarchy/nix-bin/`". `.github/scripts/readme-counts.sh` derives that
number (`repl_n`, around line 198) by grepping the **built** omarchy tree
(`OMARCHY_TREE`, default `./result`) for `pacman|yay`, then intersecting
the hits with the file names in `pkgs/omarchy/nix-bin/`.

The built tree contains our replacements, not upstream's scripts. So a
replaced script is counted only while its own comments happen to say
"pacman". The count measures how our comments are worded, not what we
replaced.

#1130 (PR #1139) rewrote the comment in `omarchy-update-available`, and the
`omarchy` job went red: `pacman-replaced: README.md says Six, the repository
says Five`. Nothing had been un-replaced. Measured against the pinned
upstream input (`inputs.omarchy`), nix-bin replaces **nine** upstream scripts
that call pacman or yay, on main and on the branch alike:

- `omarchy-default-agent`
- `omarchy-migrate`
- the six `omarchy-pkg-*`
- `omarchy-update-available`

This is the proxy trap in AGENTS.md §4. "Six" was never the number the
sentence claims.

## Proposed outcome

- The count is the number of nix-bin scripts whose **upstream**
  counterpart calls pacman or yay, read from the pinned upstream input.
- Rewording a comment in a replacement cannot move the count.
- README states the true number.
- #1139 goes green without a word of its comment being chosen to satisfy
  the check.

## Affected users and systems

- `.github/scripts/readme-counts.sh`, which runs as `--check` in `build.yml`
  and as `--fix` in `omarchy.yml`.
- README.md: the one sentence.
- #1139, which rebases onto the fix.
- No module, package or installed machine changes.

## Constraints

- Find the upstream tree the way the script already finds `nix-skills`, with
  `nix flake archive --json` (AGENTS.md §5: inputs are not reachable through
  `#`). Allow an environment override, the way `OMARCHY_TREE` and
  `NIX_SKILLS_TREE` work.
- Refuse loudly when the upstream tree cannot be found. Never fall back to a
  silent zero (§4: an auto-fixer that cannot refuse is worse than a check).
- Prove the check fails (§1): make the count wrong and watch `--check` go
  red. Separately, show that rewording a replacement's comment no longer
  moves it.
- This is not a CI-gate change: no workflow, trigger or required check
  moves.

## Open questions

1. **Scope of the sibling count.** The same paragraph's "**32 of 445
   scripts** actually run pacman" (`pac`) also greps the built tree. Against
   upstream it is 36 of 444. The built tree's figure counts what *ships*
   still naming pacman: upstream scripts we left alone, plus any replacement
   whose comment mentions it. That is the same proxy, but the sentence is
   about upstream's coupling surface.
   - **Recommendation:** leave it alone here, and file a follow-up if the
     owner wants it moved too. That keeps this change to the one number
     that is wrong today.
2. **"the ones the menus drive".** That clause is true of the `pkg-*` scripts
   and `update-available`. It is looser for `default-agent` and `migrate`.
   - **Recommendation:** reword it to "Nine of those are replaced outright,
     in `pkgs/omarchy/nix-bin/`", keeping a description of what they cover
     that is true of all nine.
