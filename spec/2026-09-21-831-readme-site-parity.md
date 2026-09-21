---
status: draft
issue: 831
intent: intent/2026-09-21-831-readme-site-parity.md
---

# Spec: the README names every page the site publishes

Refs #831.

## The cause, measured

`omarchy commands --check` against `main`'s tree
(`mk35x5fbm57r5n5rv476pc7vgyjbi18b-omarchy-4.0.4`) answers **445 commands**. So
**445 is correct** and README L393's `444` is stale, as are `docs/index.md:28`
and `docs/llms.txt:5`.

How it survived is the part that shapes this spec.
`.github/scripts/readme-counts.sh:225-227` is:

```sh
quantity "pacman-scripts" "$pac" \
  '.*\*\*([0-9]+) of [0-9]+ scripts\*\*.*' \
  's/\*\*[0-9]+ of [0-9]+ scripts\*\*/**'"$pac"' of '"$commands"' scripts**/'
```

The capture group is on the **first** number. The second is matched and
discarded, so `--check` compares `32` and never looks at `444`. The `--fix` sed
*does* rewrite it, from `$commands` — but `--fix` runs only on an Omarchy bump.
Between bumps the number was unreadable to the only mode that runs on pull
requests.

That is the whole issue in miniature: the repository checks what it extracts,
and everything it does not extract drifts silently. The fix is therefore about
what is compared, not about correcting today's numbers.

## Design

### The check exists. README is the consumer it does not cover

**Revised after the first draft of this spec.** That draft proposed a new
`.github/scripts/docs-parity.sh` built around "the filesystem is the source of
truth, and every list about it is compared". That design was right and it is
already implemented — `build.yml:714`, the step **"Every manual page is in the
sidebar"**:

```sh
pages=$(basename -a docs/manual/*.md | sed 's/\.md$//' | grep -v '^index$' | sort)
nav=$(grep  -oE 'path: /manual/[a-z-]+'      docs/_config.yml     | … | sort -u)
llms=$(grep -oE 'manual/[a-z-]+'             docs/llms.txt        | … | sort -u)
index=$(grep -oE '\]\([a-z-]+(#[a-z-]*)?\)'  docs/manual/index.md | … | sort -u)
```

then one `comm -23` loop per list, each emitting
`::error::docs/manual/$n.md is published but not in …`.

It already takes the files on disk as truth, already names the page rather than
a count, and already checks membership rather than order with the reasoning
written out. Its comments record the incidents this spec's first draft cited as
justification: four pages drifted out of the nav (`channels`, `preview`,
`reinstall-image`, `how-this-is-tested`), and `manual/index.md` sat at 24 of 26
(#574) with `boxes` and `sandboxes` unreachable.

Writing a second script would have been the `nix.gc.automatic` mistake in
CLAUDE.md §12 — grepping for the spelling, not the behaviour, and shipping a
duplicate of something that already worked.

**So the change is a fourth list in that existing step**, built the same way:

```sh
readme=$(grep -oE 'docs/manual/[a-z-]+' README.md | sed 's|docs/manual/||' | sort -u)
```

and a fourth `comm -23` loop, erroring with *"published but not linked from
README.md"*.

README is genuinely uncovered today: `build.yml` checks it for open epics
(`The README's roadmap still matches the open epics`) and for derived numbers
(`Every derived number in the README`), and for nothing else.

Two consequences, both good:

- **no new script, and no new workflow entry.** CLAUDE.md §4's coverage guard —
  a `checks.<name>` named by no workflow — does not apply, because nothing new
  is added to `checks`. The step already runs on pull requests in the `omarchy`
  job.
- **it is still a `build.yml` edit.** Not a gate change (no new required check,
  no trigger change), but a workflow file is touched and the pull request says
  so plainly rather than burying it.

### README gains an index, not 33 table rows

The curated 13-row *What you can do with it* table stays as it is — it is an
invitation, and lengthening it to 33 rows would make it a directory instead.

README gains a complete manual index, grouped, every page linked. The check
asserts **every page on disk is linked from README by path**, not that it has a
row. Grouping and wording stay editorial; only reachability is mechanical.

### Scope of the count fix

Only the command count is corrected and checked here: `445` in README L393,
`docs/index.md:28` and `docs/llms.txt:5`, and `pacman-scripts` gains a second
capture so both numbers are compared.

The other ~15 unchecked quantities — `137,599` against `getting-started.md`'s
`137,526`, 22 themes, 13 libretro cores, 13 language toolchains, "Seven are on by
default" against README's eight panel rows, the `51 / 38 / 13` split — each need
a new derivation and a move of the 27-quantity floor. They become a follow-up
issue. Bundling them would make this change unreviewable and put a large edit to
the only script guarding the README behind a docs task.

### The two absent features and the imagery

`ai-mirror` and `nixarchy-voice` get README rows marked as the site marks them
(`coming`, and `opt-in, coming`). No new status vocabulary.

Imagery is used where README already describes what it depicts: the panel shots
under `docs/img/plugins/` and the feature GIFs under `docs/img/features/`.
Nothing is recorded — #816 owns new scenes. Assets must stay under the 1 MB rule
the demo scenes already observe.

### The reverse direction, deliberately narrowed

One new page, `docs/manual/try-it-in-a-vm.md`, covering `nix run .#try` and its
flags, `#verify`, and `installer/try-nixarchy.sh`. It is the one subject a site
reader most visibly cannot reach, and it is also the entry point for someone
deciding whether to install at all.

The rest — release versioning, the app-update-ownership table, the vendoring
contract, the ISO download and reassembly — are linked from `docs/index.md`'s
*Elsewhere* section to their README anchors rather than duplicated. They are
repository-facing subjects and a second copy is a second thing to keep true.

Note the new page is itself immediately subject to the parity check, which is the
intended proof that the check works on a page added after it.

## Alternatives rejected

- **A new `.github/scripts/docs-parity.sh`.** This spec's own first draft. It
  would have duplicated `build.yml:714` almost line for line, and the duplicate
  would have disagreed with the original the first time either changed. Rejected
  on discovering the original — recorded here rather than deleted, because the
  way it was missed is the more useful warning: the behaviour was searched for
  by the name a script would have had, and it lives in a workflow step instead.
- **`docs/_config.yml` `nav` as the source of truth.** It is the list most likely
  to be edited when a page is added, which is exactly why it cannot be the
  reference: a page added to disk and forgotten in `nav` is the failure already
  seen here, and a check reading `nav` would report it as absent rather than as
  unreachable. The existing step already made this choice.
- **Folding the check into `readme-counts.sh`.** Its floor asserts 27 quantities
  are accounted for. Set membership is not a quantity, and overloading the floor
  weakens the guarantee it exists to give. Still the right call, and now moot:
  the membership check has its own home.
- **A count-based check** — "README links 33 manual pages". CLAUDE.md §4: a count
  only says a number moved. It would go red without saying which page, and a
  rename that swaps one page for another would keep it green.
- **Fixing all 15 unchecked counts here.** See scope above.
- **Mirroring the site's prose into README.** The intent forbids it; two copies
  of the same paragraph is the drift this issue is about, not the cure.
- **Correcting `444` to `445` without widening the capture.** That fixes the
  instance and leaves the blindness, which CLAUDE.md §1 calls a green light.

## Risks

- **The README grep is looser than the three beside it.** `nav`, `llms.txt` and
  `manual/index.md` each have one link syntax; README has several — relative
  `docs/manual/x`, a full `https://olafkfreund.github.io/nixarchy/manual/x`, and
  bare prose. A grep for `docs/manual/[a-z-]+` sees only the first, so a page
  linked by its published URL would read as missing. Settle which spellings
  count, and have README use one — the check should push README toward one
  spelling, not grow a pattern per spelling.
- **Matching a substring of a longer name.** `python` is a prefix of nothing
  today, but `preview` and a future `preview-x` would both match a careless
  pattern. `sort -u` plus `comm` on whole names, as the existing loops do,
  handles this; a `grep -c` would not.
- **`readme-counts.sh` can fail closed.** §4 records `word_for` refusing on a
  number it has no word for. This change touches `pacman-scripts` only and adds
  no worded quantity, but the plan re-reads the alternations before touching the
  table.
- **Widening a format breaks whoever read the narrow one** (§4, #742). Adding a
  capture to `pacman-scripts` changes what `quantity` receives for that entry;
  every caller of that helper is re-read before the change, and
  `grep -rn readme-counts .github/` run to find workflow-side consumers.
- **`find` does not follow `result`** (§5). The page walk uses `find -L` or a
  plain glob over the worktree, and refuses on an implausible count the way
  `readme-counts.sh` already does — zero pages means a broken walk, not a clean
  repository.
- **Verify under bash** (§1). The script carries `#!/usr/bin/env bash` and is run
  as a script; interactive shells here are zsh, which does not word-split
  unquoted expansions and has already produced a fake PASS in this repository.

## Verification

Per CLAUDE.md §1, each assertion is broken first and the failing output captured
for the pull request. Three breaks, because the check makes three distinct
claims:

1. **A published page README does not name.** Delete one README link — say the
   one to `docs/manual/boxes.md`. Expect red naming `boxes.md`, and **only**
   that page: the three sibling loops must stay quiet, which is what proves the
   new loop is the one that fired.
2. **A page added after the check.** `docs/manual/try-it-in-a-vm.md` is created
   by this very change. Adding it and not linking it from README must go red —
   and since the three existing loops go red too, this doubles as evidence the
   fourth loop was wired into the same rc, not bolted on beside it.
3. **The second number in `pacman-scripts`.** Set README L393 back to
   `**32 of 444 scripts**` and run `readme-counts.sh --check`. Expect red on the
   `444`. This one is the regression test for the defect that opened the issue,
   and today it passes with the bug present — that failing-then-passing pair is
   the evidence the pull request must carry.

Before concluding anything from a green break, confirm the break landed —
`git diff`, or grep the file for what was meant to change. §1 records a `sed -i`
that matched nothing and read as a blind check.

All three run at the cheapest layer: shell scripts over the worktree, seconds,
no VM and no evaluation. Nothing here needs `checks.options` or a booted session.

## Out of scope

- New screenshots or GIFs — #816.
- The Roadmap table. Empty is correct; no epic is open and the roadmap guard
  enforces it both ways.
- The wiki. CLAUDE.md §12: no check here can see it, so nothing load-bearing
  belongs in it.
- The ~15 other unchecked quantities — follow-up issue, filed with this work.
