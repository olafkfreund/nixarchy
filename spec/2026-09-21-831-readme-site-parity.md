---
status: approved
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

### The source of truth is the filesystem

`docs/manual/*.md` — **33 files today** — is what Jekyll publishes. Everything
else is a list *about* that set: `docs/_config.yml` `nav`, the Manual section of
`docs/llms.txt`, the table in `docs/manual/index.md`, and now README.

So one comparison, four consumers: each list is checked against the files on
disk, and each failure **names the page**, never a count. CLAUDE.md §4 records
both halves of this failing before — four pages published and reachable from no
sidebar, and a third index nothing compared that was already missing Boxes and
Sandboxes. Those are the same bug as this one and this check subsumes them.

A new script, `.github/scripts/docs-parity.sh`, since `readme-counts.sh` is about
*quantities extracted from a built tree* and this is about *set membership*.
Folding it in would mean its 27-quantity floor growing a second, unrelated
meaning.

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

- **`docs/_config.yml` `nav` as the source of truth.** It is the list most likely
  to be edited when a page is added, which is exactly why it cannot be the
  reference: a page added to disk and forgotten in `nav` is the failure already
  seen here, and a check reading `nav` would report it as absent rather than as
  unreachable.
- **Folding the check into `readme-counts.sh`.** Its floor asserts 27 quantities
  are accounted for. Set membership is not a quantity, and overloading the floor
  weakens the guarantee it exists to give.
- **A count-based check** — "README links 33 manual pages". CLAUDE.md §4: a count
  only says a number moved. It would go red without saying which page, and a
  rename that swaps one page for another would keep it green.
- **Fixing all 15 unchecked counts here.** See scope above.
- **Mirroring the site's prose into README.** The intent forbids it; two copies
  of the same paragraph is the drift this issue is about, not the cure.
- **Correcting `444` to `445` without widening the capture.** That fixes the
  instance and leaves the blindness, which CLAUDE.md §1 calls a green light.

## Risks

- **The check must be run by a workflow or it checks nothing** (CLAUDE.md §4:
  `checks.installer-ui` was wired into `checks` and named by no workflow, and its
  PR went green without it ever executing). Naming it in a workflow is a CI-gate
  change and needs a human (§11) — the plan raises it rather than wiring it.
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

1. **A published page README does not name.** `touch docs/manual/zzz-probe.md`,
   `git add` it (a flake in a worktree sees only tracked files, §5). Expect red
   naming `zzz-probe.md`. Delete, expect green.
2. **A README link to a page that does not exist.** Point one README link at
   `docs/manual/nonexistent.md`. Expect red naming that path — this is the
   direction a page rename breaks, and the direction a count-based check cannot
   see at all.
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
