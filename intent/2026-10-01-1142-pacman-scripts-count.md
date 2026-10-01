---
status: draft
issue: 1142
author: olafkfreund
---

# Intent: the pacman-coupled script count measures upstream, not our comments

## Problem

README.md says "Only **32 of 445 scripts** actually run `pacman`/`yay` —
that's the entire distro-coupling surface." `readme-counts.sh` derives the
32 (`pac`) by grepping the **built** omarchy tree. That is the same proxy
#1140 removed from the next sentence's "Nine of those are replaced": the
built tree holds our replacements, so how their comments are worded decides
the number.

#1140 deferred this count, and the deferral was wrong. #1139 rewords
`omarchy-update-available`'s comment, and `omarchy` now fails with
`pacman-scripts: README.md says 32, the repository says 31`. The script
has not changed whether it is coupled to pacman.

The sentence describes upstream's coupling surface; "Nine of those"
refers back to it. In the pinned upstream input, **36 of 444** scripts
call pacman or yay. The 445 is `$commands`, the shipped command count from
`omarchy commands --check`, which also feeds four other README sentences.

## Proposed outcome

- The coupled-script count is read from the pinned upstream input, as
  #1140's is. Rewording a replacement's comment cannot move it.
- The sentence's two numbers describe the same population.
- #1139 goes green without its comment being chosen to satisfy the check.

## Affected users and systems

- `.github/scripts/readme-counts.sh`: the `pacman-scripts` count, and
  possibly the `pacman-scripts-of` count.
- README.md: one sentence.
- #1139, which rebases onto the fix.
- No module, package or installed machine changes.

## Constraints

- Reuse #1140's `omarchy_src` (from `OMARCHY_SRC_TREE`, or the shared
  `flake archive`). Add no second lookup.
- Refuse loudly if the upstream tree is missing. Never a silent zero.
- Prove the check fails (§1). Prove that stripping "pacman" from the
  replacements' comments no longer moves it.
- The other four sentences that state 445 commands stay on `$commands`.

## Open questions

1. **The denominator.** If the numerator becomes upstream's 36, then
   "36 of 445" mixes upstream scripts with shipped commands. Two choices:
   - **(a) Recommended:** the denominator also comes from upstream
     (`ls "$omarchy_src/bin" | wc -l`, today 444). The sentence then reads
     "**36 of 444 scripts**", and `pacman-scripts-of` stops sharing
     `$commands`. #831 once found "444 here, 445 elsewhere" as drift; under
     (a) the difference is deliberate, so the comment at that quantity must
     say why: upstream's scripts versus the commands we ship.
   - **(b)** Keep `$commands` as the denominator: "36 of 445". This is a
     smaller diff, but the two numbers count different things.
2. **Wording.** Keep "actually run `pacman`/`yay`" as it stands, since the
   grep counts any mention, as it always has. **Recommended: no change.**
