---
status: approved
issue: 1021
author: olafkfreund
---

# Intent: a number `--fix` can write but `--check` cannot read drifts with `main` green

## Problem

`docs/manual/other-packages.md` said **"6 as NixOS modules"**. The repository
says 7, and it said 7 on `main` as well --
`grep -c '^    option = \[' data/apps.nix` gives the same answer before and
after the branch that found it. So the number had been wrong for some time,
through every pull request, with nothing able to go red.

It surfaced by accident. #1016 added a row to `data/apps.nix`, which moved the
*other* numbers on that line, and `--fix` rewrote the whole line -- silently
correcting a number nothing was watching, in a diff about remote desktop.

**The cause is structural and the script already names it.** `readme-counts.sh`
line 285, about #831:

> The SECOND number on that line, which had no entry of its own and so was
> rewritten by `--fix` and never compared by `--check` (#831). README said 445
> in four places and 444 here, through every pull request, and nothing could
> go red: the pattern above captures only the first number. **One quantity per
> number is the rule the rest of this file already follows.**

The rule exists. This line does not follow it. `quantity "apps-total"` at line
321 is:

    check:  '.*\| ([0-9]+) apps in the selection \|.*'
    fix:    s/\| [0-9]+ apps in the selection \| [0-9]+ from nixpkgs,
            [0-9]+ as NixOS modules, [0-9]+ built here,
            [0-9]+ with no equivalent \|/…/

The check captures **one** number. The fix rewrites **five**. Four of them --
`from nixpkgs`, `as NixOS modules`, `built here`, `with no equivalent` -- are
written and never read.

There are `apps-other-nixpkgs`, `apps-other-modules`, `apps-other-ours` and
`apps-other-unavailable` quantities, and they are green, because they are
anchored to a different place: the prose paragraph further down the same file
(`^([0-9]+) are NixOS modules,$`). Two statements of the same number, one
guarded and one not.

What makes this worse than an ordinary stale number is that it is **invisible
by construction**. A number `--fix` can write looks maintained. `--check`
passing looks like agreement. Neither is true, and the only detector is
somebody changing a neighbouring number by luck.

## Proposed outcome

Every number the script can write, it can also read.

- changing any number in that table row by hand and running `--check` turns it
  red, naming the quantity
- the same is true of any other number `--fix` rewrites: the audit covers the
  whole file, not only the row that was caught
- if a number cannot be given a check pattern, that is said out loud rather
  than left as a silent gap

## Affected users and systems

- `.github/scripts/readme-counts.sh`, and through it `checks.readme-counts`
  and the `omarchy` job that runs it
- `docs/manual/other-packages.md` and any other file whose numbers turn out to
  be write-only
- nobody at runtime: this is a check, and a machine's behaviour does not
  change

## Constraints

**`--fix` must stay refusable.** The header is explicit: *"an auto-fixer that
cannot refuse is worse than a check"*, and `--fix` propagating a wrong
derivation confidently is the failure it was written against. Nothing here may
make it write more eagerly.

**The check must be proven to fail.** The whole defect is a guard that could
not go red, so a fix asserted rather than demonstrated would be the same
mistake wearing a repair. Each new quantity gets a number changed by hand and
`--check` watched failing.

**One quantity per number**, which is the file's own stated rule rather than a
new convention.

**No behaviour change to the derivations.** The numbers being computed are
correct today; only what is compared changes. If a derivation turns out to be
wrong, that is a separate finding and a separate fix.

**This is a change to a check**, which needs a human's eye before it lands
(§11). The pull request proposes; it does not self-approve.

## Open questions

1. **How far does the audit go?** The row that was caught is one instance. The
   honest version sweeps every `quantity` in the file and asks, for each, "does
   the check pattern capture every number the fix pattern writes?" That is
   more work and it is the only version that closes the class rather than the
   instance. I lean towards the sweep.

2. **Can the mismatch be detected mechanically rather than by reading?** A
   self-test in the script -- count the capture groups in the check pattern
   against the substitutions in the fix pattern, and refuse when a fix writes
   more than its check reads -- would make this impossible to reintroduce. It
   is also a regex-parsing-regex job, which is how a guard becomes the thing
   that breaks. Worth trying, worth abandoning quickly if it gets clever.

3. **Is the table row the right place for those numbers at all?** The same four
   values appear twice in one file, prose and table. Deleting one of them is
   simpler than guarding both, and a document that states a number once cannot
   disagree with itself.
