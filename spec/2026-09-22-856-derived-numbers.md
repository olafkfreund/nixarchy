---
status: draft
issue: 856
intent: intent/2026-09-22-856-derived-numbers.md
---

# Spec: the numbers the README and the site state are true, or say why not

Refs #856. **This spec covers the first of two pull requests**, as the maintainer
decided when approving the intent: items 1 and 2, the two numbers that are wrong
today. Item 3, the rest of #856's table, gets its own spec and plan under the same
intent (`spec/2026-09-22-856-derived-numbers-rest.md`) once this one has landed,
because each of its quantities needs its own derivation, and designing them now
would be designing blind.

## Design

### 1. The search index count: rounded, per machine, deliberately unchecked

Two places state it: `README.md:140` and `docs/index.md:37`.

README:140 becomes, in substance:

> **About 137,000 rows on a default install: some 25,000 NixOS options, 112,000
> packages, and 65 of the 67 apps** (the two with no nixpkgs equivalent cannot
> be indexed). The exact count depends on the machine, because the index is built
> from that system's own options and package set.

`docs/index.md:37` says "about 137,000 rows" to match.

**`and 65 of the 67 apps` stays word for word.** `readme-counts.sh`'s
`apps-indexed` quantity reads that line with `and ([0-9]+) of the [0-9]+ apps`,
and a rewording that broke the phrase would make the script refuse ("nothing
matches its pattern", §4 fail-closed). The rewrite keeps the only exact numbers
on that line that *are* checked, and rounds the ones that cannot be.

`docs/manual/getting-started.md:180` is left alone. "137,526 rows in that
screenshot" describes a picture and is true of it.

**The decision not to check it is written where the check would be.** One comment
in `readme-counts.sh`'s quantity list: the index is built at runtime from each
machine's `options.json` and nixpkgs (`modules/apps.nix`), so no figure is true
of every machine, and the prose rounds rather than claims one. A later reader who
wonders why this number has no quantity finds the reason in the place they
would look (AGENTS.md §3, a documented hole).

### 2. The default plugins: a count, and a set

What is true, from `programs.nixarchy.defaultPluginSet` in `modules/home.nix`:
eight entries, three of which carry a `gate` (podman, Boxes, devenv).

**The prose.** `docs/index.md:75` becomes:

> Eight ship by default: five are always on, and three turn on with their
> feature. ai-mirror is on its way, and Voice will be opt-in.

**The table.** `docs/manual/plugins.md` gains the missing row, placed where the
page's own sections put it:

| Plugin | What it's for | Status | Open it |
|---|---|---|---|
| [Dev environments](#dev-environments) | the per-project environments on this machine | **on wherever devenv is** | as its section says |

Its *Open it* cell is taken from the Dev environments section and its seeded
binding, not written from memory.

Each default-plugin row also carries its module id, invisibly: a trailing
`<!-- nixarchy.pkg -->` on the row. The id is the only name the module and the
manual share. Three of the eight (GitLab, GitHub Actions, Herdr) have no repo
link on the page, and none of the display names appear in the module.

**Two checks, split by what they are**, following the precedent #831's spec set
(set membership is not a quantity):

- **The counts are quantities in `readme-counts.sh`.** Three of them, all in
  `docs/index.md:75`: the total (`Eight`), the always-on number (`five`), and the
  gated number (`three`). They are derived from `home.nix` by a bounded text
  read: the lines from `^      defaultPluginSet = \{` to the next `^      \};`,
  counting `id = "` lines and `gate = ` lines. The read refuses fewer than five
  ids, because zero means the block moved, not that nixarchy has no plugins (§5,
  the `find -L` lesson). The floor moves **28 → 31**. `word_for` learns **1–4**,
  in both of its forms (capitalised and lower-case), because it stops at five
  today and `three` would make the script refuse (§4).
- **Membership is a new step in the `lint` job**, beside *Every manual page is
  in the sidebar* and built the same way: ids from the same bounded read,
  `<!-- id -->` markers from `plugins.md`, one `comm -23` per direction. The
  errors name the item: *"nixarchy.devenv is a default plugin but has no row in
  docs/manual/plugins.md"*, and the reverse for a row whose plugin left the
  defaults.

### Where the comparison lives: text, not evaluation

This is the intent's second open question. **Text.** `defaultPluginSet`'s
entries reference `inputs.*` packages and `osConfig`. Evaluating them means
evaluating a Home Manager configuration, which is the cost `checks.options` pays
(~8 minutes, 11.5 GB, AGENTS.md §6). A bounded `awk` over one attrset costs
nothing and runs in `lint`, where every pull request gets it.

What text cannot see is a default added some other way, for example by
`mkMerge` from another file. That is not how the set is written today, and the
floor-and-refuse makes a moved block loud rather than silent.

## Alternatives rejected

- **An exact, checked index count.** It would describe one machine and be wrong
  on the next, and deriving it needs a full evaluation. Rejected by the intent's
  constraint "no invented precision".
- **Deleting the index figure.** The size is the point of that paragraph, since
  one picker over everything is the claim. Rounded keeps the claim true.
- **"Seven", redefined to mean something.** No set in the tree has seven members.
- **Matching rows by display name or repo link.** Neither is shared with the
  module, and three rows have no repo link at all.
- **A new column for the id.** It works, but it puts an internal name in front of
  every reader to serve a check. The comment is invisible when rendered.
- **Everything in `readme-counts.sh`.** Its floor counts quantities. A set
  folded in would weaken what the floor guarantees, which #831's spec settled.
- **Evaluating `defaultPluginSet`.** Above: the cost of `checks.options` for one
  list.

## Risks

- **The bounded read depends on indentation.** `nix fmt` owns the indentation,
  and a reindent would move the anchors. The refusal on fewer than five ids
  turns that into a red naming the read, not a silent pass.
- **`apps-indexed` shares the edited line.** Covered above; the check run in
  Verification step 4 proves it still matches.
- **`word_for` gains four words.** Any alternation carrying the old range is
  re-read in the same change (§4). Today the words are produced, not matched,
  but the plan greps for it rather than trusting that.
- **It is a `build.yml` edit.** It adds a step, not a gate: no trigger, required
  check or timeout changes. It still goes in the pull request plainly.

## Verification

Per AGENTS.md §1, each check is broken, seen red, and restored. The breaks are
confirmed by reading the file, not by `git diff` against `HEAD`. All of this runs
in seconds under `bash`, and needs no VM and no evaluation.

1. **A default with no row.** Remove the Dev environments row's marker. Expect
   red naming `nixarchy.devenv` and nothing else. This is the state `main` is in
   today, so it is also the regression test for the gap the intent found.
2. **A row with no default.** Add a `<!-- nixarchy.gone -->` marker. Expect red
   naming it.
3. **A count that drifts.** Set `docs/index.md:75` back to `Seven`. Expect
   `readme-counts.sh --check` red on the total and silent on the other two.
4. **The shared line.** `readme-counts.sh --check` passes with README:140
   rewritten, which proves `apps-indexed` still finds its phrase. Then, as its
   break, change `65 of the 67` to `64 of the 67` and expect red.
5. **The read refuses.** Point it at a copy of `home.nix` with the block's
   anchor renamed. Expect a refusal, not a pass on zero plugins.

The lint trio (`nix fmt -- --ci`, statix, deadnix) runs over `.`, and
`actionlint` over `build.yml`.
