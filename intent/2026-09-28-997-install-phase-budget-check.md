---
status: approved
issue: 997
author: Olaf Freund
---

# Intent: the install phase says it is getting full before it is

## Problem

`pkgs/omarchy/default.nix`'s `installPhase` is one string handed to `execve`,
and the kernel refuses any single argument or environment string over
`MAX_ARG_STRLEN`, 131,072 bytes. When it is exceeded, the build fails with
**"Argument list too long", naming nothing**. #948's approved work was refused
that way, and it took #997 to work out why.

The first pass (#998, #1028) moved prose out and bought headroom:

| | installPhase | headroom |
|---|---|---|
| before #997 | 127,703 | 2,181 |
| after #1028 | 114,691 | 16,381 |
| **today (`c9e1a86`)** | **113,966** | **17,106** |

The number moves both ways with ordinary work: it has moved by about 700
bytes since #1028. What doesn't move is that nothing measures it. No check,
no comment and no script in the tree reads its length; the only `131072` is a
disk size. So the next author to run out finds out the way #948 did, and a
large patch (the first pass measured single paragraphs at 2-4 KB) can take
several thousand bytes at once.

The first pass's plan deferred this explicitly: *"The budget check goes in its
own pull request."*

## Proposed outcome

A check that fails **well before** the kernel limit and names the problem in
this repo's words: how big the phase is, the budget, and that the fix is to
move prose to `pkgs/AGENTS.md` behind a `# Why:` pointer (AGENTS.md §7). It
runs on every pull request, and a PR that eats the headroom goes red with a
reason instead of dying later with none.

## Affected users and systems

Contributors editing `pkgs/omarchy/default.nix`, meaning every Omarchy patch.
No machine changes. It's a check.

## Constraints

- **Evaluation only, no build.** The phase's length is known at evaluation.
  Put a *value* in the check, not a store path (tests/AGENTS.md: a drvPath in
  a derivation's environment is a build input). So it costs seconds.
- **It must be able to fail** (§1): shown red by pushing the phase over the
  budget, not only green on today's tree.
- **The budget is a number someone will argue with**, so it is stated with its
  reasoning. It must leave room for one ordinary patch (the first pass
  measured single paragraphs at 2-4 KB), and it must not go red today.
- It counts what `execve` counts: the phase as the builder receives it, not
  the `.nix` source.

## Open questions

1. **Where is the line?** One option is a fixed budget (for example, fail at
   123,000, which leaves 8 KB headroom). The other is a ceiling plus a warning
   band. My lean is one fixed number, because a warning nobody reads is §4's
   decoration.
2. **Just `installPhase`, or every phase of every package here?** Only
   `omarchy`'s phase has ever come near the limit. Guarding one named thing is
   honest about what is measured; a general sweep is a bigger claim. I lean
   towards the one, with the check's message saying so.
