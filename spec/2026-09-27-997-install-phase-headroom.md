---
status: approved
issue: 997
intent: intent/2026-09-27-997-install-phase-headroom.md
---

# Spec: move the prose out of the install phase

## Design

**Move explanations longer than three lines from `installPhase` into
`pkgs/AGENTS.md`, leaving a `# Why: pkgs/AGENTS.md#<anchor>` pointer.**

This is not a new convention. Root `AGENTS.md` §7 states it, `pkgs/AGENTS.md`
is 352 lines of exactly this material with `##` anchors already, and five
pointers of this shape exist today in `modules/home.nix` and
`pkgs/skills-relink.nix`.

### Why prose rather than the shell blocks the issue proposed

Measured, not assumed:

| | |
|---|---|
| phase, in source | 1,870 lines / 132,868 bytes |
| **comment lines** | **73,052 bytes — 54%** |
| largest single paragraph | 4,256 bytes |
| top ten paragraphs together | ~27 KB |

There is no large block to extract. Moving shell into `writeShellScript`
files would relocate the part that can break in exchange for a minority of
the bytes; moving prose relocates the majority and cannot change behaviour.

### What moves and what stays

**Moves:** any comment run of four lines or more that explains *why* — a
failure history, an upstream quirk, a rejected alternative. It becomes a `##`
section in `pkgs/AGENTS.md` with the issue numbers it already cites, and the
phase keeps a one-line `# Why:` pointer.

**Stays:** one-to-three-line notes at the line they protect. §7 is explicit
that this is where they belong, and shortening the file by making the code
harder to edit is the wrong trade.

**Nothing is deleted.** Text leaving one file appears in the other, and the
diff is the proof.

### Order

Largest first, in tranches, each its own commit with its own output
comparison. A single rewrite that changes the output for several reasons at
once cannot be told apart from one that broke something.

## Verification: compare outputs, not derivations

The issue proposed comparing `drvPath`. **That cannot work here.** Moving text
out of `installPhase` changes the phase, so the derivation hash changes by
construction — a `drvPath` match would mean the edit had not landed.

The test that works is stronger, because it is about what ships:

```sh
before=$(nix build --no-link --print-out-paths .#omarchy)   # on the old tree
after=$(nix build --no-link --print-out-paths .#omarchy)    # on the new one
diff -r "$before" "$after" && echo "bit-identical"
```

An empty `diff -r` proves the package is unchanged. That is the acceptance
criterion for every tranche, and a tranche that fails it is read rather than
argued with.

Backstop, if a tranche legitimately changes output: the package is read by
`bin-ledger`, `readme-counts`, `menu-verbs`, `bar-keyed-sync`,
`shell-ipc-resolve`, `android`, `channel` and `theme-set-zed`.

## Alternatives rejected

**`writeShellScript` extraction, as #997 proposed.** Not wrong, but aimed at
19% of the problem and at the risky part of it. Left open for the genuinely
large shell blocks *after* the prose moves, when the remaining phase may not
need it.

**Deleting comments.** §7 says long blocks move, they do not get deleted, and
the failure history in them is the most valuable thing in the file.

**Shortening comments in place.** Rewriting 73 KB of prose to be terser is a
larger, more subjective diff than moving it, and it loses detail to buy bytes.

**Doing nothing and raising the limit.** `MAX_ARG_STRLEN` is the kernel's;
there is nothing to raise.

**One large commit.** Cheaper to write, impossible to bisect.

## Risks

- **A move that drops text.** The `diff -r` cannot see it, because comments do
  not reach the output. Mitigated by the diff being readable — removed from
  one file, added to the other, in the same commit — and by moving in tranches
  small enough to read.
- **Anchor drift.** A `# Why:` pointer naming a section that is later renamed
  is a dead reference and nothing checks it. Real, and it is the same exposure
  the five existing pointers already carry; noted rather than solved here.
- **The limit comes back.** This buys headroom, not a guarantee. Intent's open
  question 2 — a check that fails when the derivation environment exceeds a
  budget — is the durable answer and is proposed below as optional.
- **Another agent is active in this tree.** #1026 merged during this work.
  `pkgs/omarchy/default.nix` is a file others touch, so this wants rebasing
  and re-diffing before merge rather than after.

## Proposed addition: a budget check

Optional, and I recommend it. A check that measures the derivation's
environment and fails above a threshold — say 100 KB, leaving 30 KB of
notice — turns a silent kernel limit into a readable budget. Without it,
the next approach is invisible until an unrelated PR fails with an `execve`
error that names nothing in this repository.

It is cheap: `nix derivation show .#omarchy`, sum the env, compare. It needs
no new workflow entry, because `generated-checks.sh` builds every check not on
the claimed list.

## Open questions

1. **What byte target is "enough" for this pass?** Moving the ten largest
   paragraphs reclaims roughly 27 KB and is reviewable. Applying the
   four-line rule exhaustively reclaims most of 73 KB and is not. I propose
   the first, and the second as follow-up work if anyone wants it.
2. **Should the budget check land in this PR or its own?** It is a new check,
   so it has its own break-it-and-watch-it-fail obligation. Bundling it makes
   one PR harder to review; separating it risks it never being written.
