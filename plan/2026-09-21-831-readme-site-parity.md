---
status: approved
issue: 831
spec: spec/2026-09-21-831-readme-site-parity.md
---

# Plan: the README names every page the site publishes

Branch `docs/831-readme-site-parity`, already carrying the intent and spec. One
commit per step, each subject a full sentence (AGENTS.md §8). A deviation
updates this file in the same commit as the code.

## Approved decisions

Copied from the spec so this file stands alone.

- **The check exists.** `build.yml:714`, the step *"Every manual page is in the
  sidebar"*, already takes `docs/manual/*.md` as the source of truth and
  compares three lists against it — `_config.yml` `nav`, `llms.txt`, and
  `manual/index.md` — naming the page, not a count. README is the fourth
  consumer it does not cover. **No new script, no new workflow entry**, so §4's
  coverage guard does not apply; it is still a `build.yml` edit and the PR says
  so.
- **README gains a grouped index, not 33 table rows.** The curated 13-row
  *What you can do with it* table stays. The check asserts a page is *linked*,
  not that it has a row.
- **445 is correct**, measured: `omarchy commands --check` on `main`'s tree
  answers `445 commands`. README L393's `444` is stale, as are
  `docs/index.md:28` and `docs/llms.txt:5`.
- **One new page**, `docs/manual/try-it-in-a-vm.md`, for `nix run .#try`,
  `#verify` and `installer/try-nixarchy.sh`. Other README-only subjects are
  linked from `docs/index.md`'s *Elsewhere*, not duplicated.
- **The other ~15 unchecked quantities are a follow-up issue**, filed with this
  work.

## Measured before planning

- **33** pages under `docs/manual/` (excluding `index`).
- README links **19** of them, and in two spellings: 7 by relative path
  (`docs/manual/boxes.md`) and 19 by published URL
  (`https://olafkfreund.github.io/nixarchy/manual/boxes`), the former a subset
  of the latter.
- **13 are named nowhere**: `development-tools`, `dotfiles`, `gaming`,
  `making-your-own-theme`, `plugins`, `prebuilt-binaries`, `secrets`,
  `security`, `system-snapshots`, `troubleshooting`, `unattended-installs`,
  `updates`, `updating-nixos`.

The two spellings are the open question the spec flagged, and step 1 settles it.

## Steps

**1. Settle the link spelling, then add the fourth loop.** The three existing
lists each have one syntax, which is why each is one `grep`. README has two.

Decision to make in this step, and to record in the commit: **normalise README
on the published-URL form** — it already accounts for 19 of the 19 links, it is
what a reader on github.com can click through to the rendered page, and it
keeps the new grep a single line matching the siblings:

```sh
readme=$(grep -oE 'nixarchy/manual/[a-z-]+' README.md |
  sed 's|.*manual/||' | sort -u)
```

The seven relative links are rewritten to that form in the same commit, so the
check never needs a second pattern. Then a fourth `comm -23` loop beside the
three, erroring with *"published but not linked from README.md"*.

→ verify by §1, two breaks, both at the cheapest layer — this is shell over the
worktree, seconds, no VM and no evaluation:

  a. Delete one README link (say `boxes`). Expect red naming **only**
     `boxes.md`; the three sibling loops must stay quiet, which is what proves
     the new loop fired rather than an old one.
  b. Add `docs/manual/zzz-probe.md`, `git add` it (a flake sees only tracked
     files, §5). Expect red naming it — and the three siblings red too, which
     shows the new loop was wired into the same `rc` rather than bolted beside
     it.

Confirm each break landed before believing a red result (§1: a silent no-op
break and a blind check are indistinguishable from an exit status). Run the
step's shell under `bash`, not the interactive zsh.

**Deviations, recorded with the code that caused them.**

1. **Steps 1 and 2 land in one commit.** A commit that adds a check README
   cannot yet satisfy leaves the branch red between the two, and a red commit
   in a branch's history is a trap for whoever bisects it later.
2. **There are 32 pages, not 33.** `docs/manual/` holds 33 files; the check
   excludes `index.md`, as this plan's own quoted `grep -v '^index$'` does. The
   generator asserts its group map equals what is on disk, which is what caught
   it.
3. **The *Prebuilt binaries* row linked `python.md`.** `prebuilt-binaries.md`
   was one of the 13 pages nothing named, and the row describing it pointed at
   the wrong page — so the fix belongs to the same edit, and the missing list
   became 12.
4. **`git diff` is the wrong way to confirm a break in an uncommitted block.**
   Removing a line from a section that is not yet in `HEAD` produces no `-`
   line to match, so the check for the break reported nothing and the `&&`
   chain stopped before the check ran. Confirm against the *file*
   (`grep -c` on the working tree), not against a diff with `HEAD`.

**2. README gains the index.** A grouped section linking all 33 pages, in the
settled spelling. The 13 above stop being invisible; `plugins.md` in
particular, which is the site's hub for the eight panels README already lists
row by row.

→ verify by step 1's check passing, having failed in 1a before the section
existed.

**3. `ai-mirror` and voice.** Two rows in *What works*, marked as the site
marks them — `coming`, and `opt-in, coming`. No new status vocabulary.

→ verify by `grep -c 'ai-mirror\|nixarchy-voice' README.md` and by reading the
rows against `docs/manual/plugins.md`.

**4. The imagery already under `docs/img/`.** Panel shots from `img/plugins/`
and feature GIFs from `img/features/` used where README already describes what
they depict. Nothing recorded — #816 owns new scenes — and each asset stays
under the 1 MB rule.

→ verify by every referenced path existing (`ls`), and by no asset over 1 MB.

**5. `445`, and the capture that hid it.** README L393, `docs/index.md:28`,
`docs/llms.txt:5`. Then widen `readme-counts.sh`'s `pacman-scripts` entry so
the second number is compared, not just rewritten:

```sh
quantity "pacman-scripts" "$pac" \
  '.*\*\*([0-9]+) of [0-9]+ scripts\*\*.*' \   # only the 32 is captured today
```

→ verify by §1: set L393 back to `**32 of 444 scripts**` and run
`readme-counts.sh --check`. Expect red on the `444`. **This is the regression
test for the defect that opened the issue, and today it passes with the bug
present** — that failing-then-passing pair is the evidence the PR must carry.
Re-read `word_for` and every alternation before touching the table (§4: the
guard can fail closed on a number it cannot spell).

**6. `docs/manual/try-it-in-a-vm.md`, and the reverse gaps.** The new page for
`#try`, `#verify` and `installer/try-nixarchy.sh`; the rest linked from
`docs/index.md`'s *Elsewhere* to their README anchors.

→ verify by the new page being caught by step 1's check if README does not name
it — which is the intended proof that the check works on a page added after it —
and by the three existing lists (`nav`, `llms.txt`, `manual/index.md`) gaining
it too, since the step at `build.yml:714` already requires that.

**7. The follow-up issue** for the ~15 unchecked quantities: `137,599` against
`getting-started.md`'s `137,526`, 22 themes, 13 libretro cores, 13 language
toolchains, "Seven are on by default" against README's eight panel rows, the
`51 / 38 / 13` split in `manual/index.md`.

→ verify by the issue existing with a milestone and an area label (§12), and by
this plan linking it.

## Tests

```
bash .github/scripts/readme-counts.sh --check      # needs OMARCHY_TREE or ./result
# the build.yml step's shell, run by hand over the worktree
nix fmt -- --ci && nix run --inputs-from . nixpkgs#statix -- check . \
  && nix run --inputs-from . nixpkgs#deadnix -- --fail .
```

No VM check is touched, so nothing here needs `/dev/kvm` or an install slot.
The lint trio runs over **`.`, not the changed files** — #829 was `main` going
red because the new line was fine and its neighbours were not.

`build.yml` is edited, so check `gh run list` before assuming a red is yours,
and expect the step to run in the `omarchy` job on pull requests.

## Rollback

`git revert` the merge. The check returns to three consumers, README keeps
whatever links it had, and no state lives outside the repository. The one
thing a revert does not undo is a reader who has found `plugins.md` — which is
the intended direction, not a risk.
