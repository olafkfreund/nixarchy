---
status: approved
issue: 1021
intent: intent/2026-09-27-1021-unchecked-derived-numbers.md
---

# Spec: every number the script can write, it can also read

## What the audit found

The intent's first open question was how far this goes. Measured rather than
guessed: of **37 `quantity` calls**, **7 have a fix pattern that rewrites more
numbers than the check pattern captures.**

| quantity | check reads | fix writes | verdict |
|---|---|---|---|
| `pacman-scripts` | 1 | 2 | **covered** — `pacman-scripts-of` is its pair |
| `pacman-scripts-of` | 1 | 2 | **covered** — the #831 fix, working |
| `apps-total` | 1 | 5 | **four unguarded** |
| `apps-untouched` | 1 | 2 | **one unguarded** |
| `apps-indexed` | 1 | 2 | **one unguarded** |
| `apps-nixpkgs-row` | 1 | 2 | **one unguarded** |
| `default-plugins-on` | 1 | 2 | to confirm |

The `pacman` pair is what #831 already fixed and it is the shape the rest
should copy: two quantities, one per number, sharing a line.

**A second live instance, demonstrated rather than reasoned about.** Changing
`**57 of the 68 apps never touch this repo.**` to `99` in `README.md` and
running `--check`:

    check exit=0

Completely unguarded. That is a different line and a different quantity from
the one that started this issue, which settles the intent's question: this is
a class, not an instance.

## Design

### 1. One quantity per number, which is the file's own rule

For each unguarded number, add a `quantity` whose check pattern captures *that*
number. The `pacman-scripts` / `pacman-scripts-of` pair is the template,
including the naming: the second entry takes the first's name plus what the
number is of.

So `apps-untouched` gains `apps-untouched-of`, `apps-indexed` gains
`apps-indexed-of`, `apps-nixpkgs-row` gains `apps-nixpkgs-row-of`, and
`apps-total`'s table row gains four —
`apps-row-nixpkgs`, `apps-row-modules`, `apps-row-ours`, `apps-row-unavailable`.

The fix patterns do not change. Only what is compared changes, which is the
intent's constraint that no derivation moves.

### 2. A self-test, so this cannot come back

The intent asked whether the mismatch is mechanically detectable. It is, and
cheaply, because the script already has both patterns in hand as strings:
count the unescaped capturing groups in the check pattern, count the
`[0-9]+` and `[a-z]+` occurrences in the fix pattern's left-hand side, and
refuse when the fix writes more than the check reads.

**With an explicit allowlist**, because `pacman-scripts` is a legitimate
1-reads-2-writes entry — its sibling covers the other number. A pair declares
itself by naming its partner, so the check is "writes more than it reads and
has no declared partner", not "writes more than it reads".

This is the part that turns a fixed instance into a closed class, and it is
also the part most likely to become the thing that breaks (regex counting
regex). It stays under ~20 lines and refuses rather than guesses; if it needs
to be clever it should be abandoned and the table above kept as a comment
instead.

### 3. `--fix` is untouched

The header's argument stands: *"an auto-fixer that cannot refuse is worse than
a check"*, and `--fix` propagating a wrong derivation confidently is what it
was written against. Nothing here makes it write more eagerly, and the new
quantities make it write **less** blindly, because every number it rewrites is
now one `--check` will disagree about.

## Alternatives rejected

**Delete the duplicate statement instead of guarding it.** The intent's third
question, and the tempting answer: those four numbers appear twice in
`other-packages.md`, as prose and as a table, and a document that states a
number once cannot disagree with itself. Rejected because the two statements
are for different readers — the table is a summary somebody scans, the prose
is the explanation — and deleting one to make a check easier is letting the
check dictate the documentation. The guard is cheap; the table earns its place.

**Only fix the row that was caught.** It is the smaller diff and it leaves
four demonstrated instances live, one of which is proven above.

**A generic "every number in every rewritten line must be checked" rule with
no allowlist.** It would fail on the `pacman` pair, which is correct code, and
a guard that fails on the right answer gets disabled.

**Parsing the sed expressions properly.** The counting heuristic is crude and
that is deliberate: it only has to be right about "does this write more than
it reads", and a wrong answer is a build failure somebody reads, not a silent
pass.

## Risks

- **The self-test miscounting and refusing valid code.** The failure mode is
  loud and blocks a PR, which is the right direction but still costs somebody
  an afternoon. Mitigated by the allowlist and by running it against the file
  as it stands before adding any new quantity.
- **A new quantity whose check pattern matches the wrong occurrence.** The
  same number often appears in several files; an anchor that is too loose
  makes a check that passes for the wrong reason. Every new pattern is proven
  by changing that specific number and watching `--check` name that specific
  quantity.
- **`default-plugins-on` is listed as "to confirm".** It may be a legitimate
  pair like `pacman-scripts`. If so it joins the allowlist rather than gaining
  a quantity, and the spec is wrong about one row rather than about the class.
- **Scope creep into correcting derivations.** If a new check reveals that a
  *computed* value is wrong, that is a separate issue. This one only changes
  what is compared.

## Verification

Per §1, each new guard is proven by breaking the number it guards.

| what | how | break it by |
|---|---|---|
| each new quantity goes red for its own number | change that number by hand in the file it lives in, run `--check`, read the name it prints | — it must name the new quantity, not a neighbour |
| the demonstrated instance is closed | `57 of the 68 apps` → `99`, `--check` must now fail | it exits 0 today, which is recorded in this spec |
| the self-test catches a new unguarded number | add a throwaway `quantity` that writes two and reads one, with no partner | it must refuse, naming the quantity |
| the self-test does not fire on the `pacman` pair | run it against the file unchanged | removing the partner declaration must make it fire |
| `--fix` still produces a file `--check` accepts | `--fix` then `--check` on a dirtied tree | — |
| nothing else moved | `checks.readme-counts` green, and `git diff` limited to the script | — |

**No workflow edit.** `checks.readme-counts` already exists and already runs;
this changes its contents, not its coverage.

## Open questions

1. **Is `default-plugins-on` a pair or a gap?** One row of the table is
   unconfirmed, and confirming it is a two-minute break-and-check. Named here
   rather than assumed in either direction.
2. **Should the self-test live in `readme-counts.sh` or in the check that runs
   it?** In the script it runs on every invocation including `--fix`, which is
   where a new mismatch is introduced. That is the argument for the script;
   the argument against is that a script guarding itself is harder to reason
   about than a check guarding a script.
