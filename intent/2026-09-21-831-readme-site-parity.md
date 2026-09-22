---
status: approved
issue: 831
author: olafkfreund
---

# Intent: the README names every page the site publishes

Closes #831.

## Problem

The site publishes **33 manual pages**. README links or names **20** of them.
The thirteen it does not are not obscure corners: `plugins.md` is the site's hub
for the eight panels README lists row by row in *What works*, and README links it
nowhere. `secrets.md`, `security.md`, `system-snapshots.md`, `updates.md`,
`updating-nixos.md`, `unattended-installs.md`, `dotfiles.md`,
`making-your-own-theme.md`, `development-tools.md`, `gaming.md`,
`prebuilt-binaries.md`, `troubleshooting.md` and `manual/index.md` are the rest.

Several README rows describe a page's content while linking nothing — the Themes
row beside `making-your-own-theme.md`, the "13 language toolchains" row beside
`development-tools.md`. One links the wrong page: the Prebuilt binaries row
points at `python.md`, and `prebuilt-binaries.md` is a separate page README never
references.

**Two features are absent from README entirely**: `ai-mirror` and
`nixarchy-voice`. Both are carried in `docs/manual/plugins.md` and advertised on
`docs/index.md`; README has zero occurrences of either.

**README uses none of `docs/img/`.** It embeds eight stills from
`docs/screenshots/` and `img/features/install.gif`. Sitting unused: nine of the
ten feature GIFs — pkg, podman, herdr, microvm, boxes, devenv, themes, menus,
plugin — the entire panel set under `img/plugins/`, and all seven installer step
PNGs. README names every one of those panels in prose. Nothing here needs
recording; the assets exist today.

**The gap runs both ways.** The site does not cover `nix run .#try` and its
flags, `#verify`, the prebuilt-ISO download and `cat …part-*` reassembly, the
release versioning scheme, the app-update-ownership table, or the vendoring
contract. A reader who arrives at the site rather than the repository cannot
find out how to try nixarchy in a VM.

### Why it drifted, which is the part worth fixing

README says **445** shell commands at L16, L422, L442 and L449, and **444** at
L393. `docs/index.md:28` and `docs/llms.txt:5` both say 444.

`readme-counts.sh` carries a `pacman-scripts` pattern over `**32 of 444
scripts**` and compares **only the 32**. The `444` is rewritten by `--fix` and
never compared; neither docs copy of the command count is checked at all. So the
number disagreed with itself inside one file, through every pull request, and
nothing could go red.

That is the shape of the whole issue rather than a detail of it. Fifteen further
numbers are unchecked — `137,599` search rows against `getting-started.md`'s
`137,526`, 22 themes, 13 libretro cores, 13 language toolchains, "Seven are on by
default" against README's eight panel rows, the `51 / 38 / 13` split in
`manual/index.md`. CLAUDE.md §4 already names this failure mode: a
hand-maintained list fails open, the thing still works, nothing goes red, and the
only detector is a human happening to look. A human happened to look.

The parity that *is* checked shows the fix works. `readme-counts.sh` compares
every shipped `SKILL.md` against a table row in both README and
`docs/manual/ai.md`, and the sixteen skills agree in all four places they are
written. The page list has no such comparison, and it is the list that drifted.

## Outcome

- README is an index: it names every published manual page and links it, with
  the depth staying in the manual. No prose is duplicated from the site.
- A check compares README against the site and fails a pull request that
  publishes a manual page README does not name — **naming the missing page**,
  because a count only says a number moved.
- `ai-mirror` and voice appear in README, marked as the site marks them.
- The imagery already under `docs/img/` is used where README describes what it
  depicts.
- The reverse gaps get a home: each README-only subject either becomes a manual
  page or a README section the site links.
- 444 and 445 resolve to one number, checked wherever it is written.

## Affected

- `README.md`
- `.github/scripts/readme-counts.sh`, or a sibling script for the page parity
- `docs/_config.yml`, `docs/llms.txt`, `docs/manual/index.md` — the three lists,
  if the check reads them as the source of what is published
- possibly new pages under `docs/manual/` for the README-only subjects
- a workflow must name any new check (CLAUDE.md §4 — and that edit is a CI-gate
  change, so it is raised for a human rather than wired here, §11)

## Constraints

- **No new screenshots or GIFs.** Recording new scenes is #816. This task uses
  only assets that exist.
- **The Roadmap table stays empty.** No epic is open, and the roadmap guard
  enforces it both ways. It is correct as it stands.
- **The wiki is out of scope.** CLAUDE.md §12: it is a separate repository no
  check here can see, so nothing load-bearing belongs in it. Mirroring the
  feature list there would create a fourth hand-maintained list with no
  comparison behind it — the problem, not the fix.
- README must not become a second copy of the manual. If a section would restate
  a page, it links the page instead.
- The new check must be proven to fail before it is believed (§1): delete a
  README row for a page that exists, watch it go red, capture the output.

## Open questions

1. **What is the source of truth for "published"?** `docs/_config.yml`'s `nav`,
   the files on disk under `docs/manual/`, or `manual/index.md`? The three agree
   today at 33 entries, which makes now the cheap moment to pick one and have the
   check compare the other two against it.
2. **Does every manual page deserve a README row?** Thirty-three rows is a long
   index. The alternative is that README names every page but groups them, and
   the check asserts presence rather than a row per page.
3. **Where do the README-only subjects go?** `#try` in a VM is the one a site
   reader most visibly cannot find. New manual page, or a section on
   `docs/index.md`?
4. **Is 444 or 445 correct?** `omarchy commands --check` decides it, and it needs
   a built tree to answer.
5. **Should the unchecked counts be checked in this task or listed as follow-up?**
   Fifteen quantities is a larger change to `readme-counts.sh` than the page
   parity, and its 27-quantity floor has to move with them.
