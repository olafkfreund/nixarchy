---
status: draft
issue: 997
author: olafkfreund
---

# Intent: the install phase is 2 KB from a hard kernel limit, and most of it is prose

## Problem

`pkgs/omarchy/default.nix`'s `installPhase` is **127,703 bytes**. With the
rest of the derivation's environment the total is **128,891**, against
`MAX_ARG_STRLEN` of **131,072**. Measured now, from
`nix derivation show .#omarchy`:

    installPhase bytes: 127703
    total env bytes:    128891  (MAX_ARG_STRLEN 131072)
    headroom:           2181

So any edit adding more than about 2 KB to that phase fails to build.

**This is not hypothetical.** #948's approved step 1 is *unavailable* until it
is fixed: a 48-line addition was refused exactly this way, recorded in
`plan/2026-09-24-948-text-size-on-managed-configs.md`. #982 is parked for the
same reason -- its patch would probably fit, and would leave the next person
with nothing.

## What the issue assumed, and what the file actually contains

#997 proposes moving "the larger blocks" into `writeShellScript` / `writeText`
files, so the phase grows by a path rather than by a script. Measuring the
phase first says that is aimed at the wrong mass.

The phase is 1,870 lines and 132,868 bytes in the source, of which
**73,052 bytes -- 54% -- are comment lines.** And there is no large block to
move: across 116 paragraphs the biggest is 4,256 bytes, and the top ten
together are about 27 KB. Extracting shell blocks would move executable code,
which is the part that can break, in exchange for a minority of the bytes.

**The repository's own rule already says where 73 KB of explanation belongs.**
Root `AGENTS.md` §7:

> **Long blocks move, they do not get deleted.** If an explanation is worth
> more than three lines, put it in the directory's `AGENTS.md` and leave a
> `# Why: <dir>/AGENTS.md#<anchor>` pointer.

That convention is live rather than aspirational -- `modules/home.nix` and
`pkgs/skills-relink.nix` carry five such pointers today, and `pkgs/AGENTS.md`
is 352 lines of exactly this material with the anchors already in place.

So the phase is carrying a large amount of text that a written rule says
should be one directory over, and the reason nobody moved it is that nothing
made the cost visible until the limit did.

## Proposed outcome

- the install phase has **tens of kilobytes** of headroom rather than two, so
  #948 and #982 become ordinary work again
- the long explanations are in `pkgs/AGENTS.md`, findable and readable,
  rather than inside a 127 KB shell string nobody reads end to end
- short notes -- one to three lines, at the line they protect -- stay exactly
  where they are, because §7 says that is where they belong
- **nothing the package produces changes**, and that is proven rather than
  asserted

## Affected users and systems

- `pkgs/omarchy/default.nix` and `pkgs/AGENTS.md`
- nobody at runtime: the built output is intended to be bit-identical
- #948 and #982, which this unblocks rather than contains
- every check that reads the omarchy package -- `bin-ledger`, `readme-counts`,
  `menu-verbs`, `bar-keyed-sync`, `shell-ipc-resolve`, `android`, `channel`,
  `theme-set-zed` -- which is the safety net if the output is *not* identical

## Constraints

**The output must be bit-identical, and it must be shown.** A `drvPath`
comparison cannot do it here: moving text out of `installPhase` changes the
phase, so the derivation hash changes by construction. The test that works is
comparing the built outputs -- `diff -r` between the old and new `$out` --
which is a stronger claim anyway, because it is about what ships.

**No explanation is deleted.** §7 is explicit: long blocks move. Anything that
would be lost rather than relocated is out of scope, and the diff has to make
that checkable -- text removed from one file appearing in the other.

**Short notes stay inline.** The rule is one to three lines at the line they
protect. Moving those would make the code worse to satisfy a byte count.

**Nothing the phase does may change.** No reordering, no consolidation, no
"while I am here". Bytes move; behaviour does not.

**One tranche at a time.** A single rewrite that changes the output for
several reasons at once cannot be told apart from one that broke something.

## Open questions

1. **How far to take it in one pass?** Moving every comment over three lines
   would reclaim most of 73 KB and produce an enormous diff. Moving the
   largest blocks first reaches useful headroom quickly and stays reviewable.
   What is "enough" -- a byte target, or a rule applied exhaustively?

2. **Does the phase need a guard so this cannot come back?** The limit is
   silent until it is hit, and the failure message is about `execve`, not
   about a budget. A check that fails when the environment exceeds, say, 100
   KB would make the next approach visible while there is room to act. Not
   proposed here, but it is the difference between fixing this once and
   fixing it again.

3. **Is `writeShellScript` extraction still wanted for the genuinely large
   shell blocks?** The issue's original proposal is not wrong, only
   secondary. After the prose moves, the remaining phase may be small enough
   that it is unnecessary -- or the 4 KB menu block may still be worth its own
   file.
