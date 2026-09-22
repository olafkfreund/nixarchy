---
status: draft
issue: 856
author: olafkfreund
---

# Intent: the numbers the README and the site state are true, or say why not

Closes #856.

## Problem

`readme-counts.sh` compares 28 quantities against what they count. About fifteen
more are typed by hand in README and on the site, and nothing compares them. It
is the shape of the `444` that opened #831: a figure in a file that claims to be
kept honest, drifting with nothing to notice.

Two are wrong today, and measuring them showed that each is wrong in a way a
pattern alone would not fix.

### The search index count claims a precision it cannot have

README and `docs/index.md` say **137,599 rows**. README's own breakdown on the
same line (25,102 options + 112,443 packages + 65 apps) adds up to **137,610**.
So the figure disagrees with itself before it disagrees with anything else.

It cannot be corrected to a better exact number either. `modules/apps.nix`
builds the index **on each machine, at runtime**, from that system's
`options.json` and its nixpkgs package set. The row count depends on the
configuration and the pin, so no single exact figure is true of every machine,
and CI cannot derive one without evaluating one.

`getting-started.md`'s **137,526** is not the same claim. It reads "137,526 rows
in that screenshot", which is a caption, and it is correct for the picture it
describes.

### "Seven are on by default" counts neither set there is

`docs/index.md:75`. The defaults are one list in `modules/home.nix`
(`resolvedDefaults`, entries at `:1558–1624`), and it has **eight** entries:

| always on (5) | on only when their feature is (3) |
| --- | --- |
| Packages, GitLab Pipelines, GitHub Actions, Herdr, MicroVMs | Podman (podman), Distrobox (Boxes), Dev environments (devenv) |

Seven is neither eight nor five. The plugin table in `docs/manual/plugins.md`
has the same gap: it has no **Dev environments** row, although the page has a
*Dev environments* section. A list naming things that exist elsewhere, with
nothing comparing them (AGENTS.md §4, "a hand-maintained list fails OPEN").

## Proposed outcome

Decided by the maintainer on 2026-09-22:

1. **The index count is rounded and says it is per machine**, e.g. "about
   137,000 rows on a default install". The breakdown is rounded the same way. The
   screenshot caption stays exact. The figure is **deliberately unchecked**, and
   that decision is written down where the check would have been, because a
   documented hole beats an undocumented one (AGENTS.md §3).
2. **The default-plugin sentence says eight, and says what the eight are**: five
   always on, three with their feature. The plugin table gains its Dev
   environments row. Both are **compared against the module's list**, so a
   ninth default goes red rather than going unmentioned.
3. **The rest of #856's table** follows the issue's order: first what can be
   derived from files already in the tree (the manual-page split, language
   toolchains, Install rows), then what needs the built tree (themes, libretro
   cores), then a written decision for what is deliberately left unchecked
   (`2,221` ISO store paths needs a full ISO build).

Observable: every number in README and on the site either has a check that goes
red naming it, or a sentence saying why it has none.

## Affected users and systems

- `README.md`, `docs/index.md`, `docs/manual/plugins.md`, and wherever else a
  figure in #856's table appears
- `.github/scripts/readme-counts.sh`: new quantities, the floor it asserts
  (28 today), and `word_for` for any number spelled as a word
- possibly `build.yml`, if a comparison belongs in a step rather than the script
- readers of the site and README. Nothing installed on a machine changes.

## Constraints

- **No invented precision.** A figure that varies per machine is not checked
  against one machine's value.
- **Name the item, not the count** (§4). The default-plugin comparison reports
  *which* plugin is missing from the prose or the table.
- **`readme-counts.sh` can fail closed** (§4). It refuses a number it has no word
  for, so every new worded number is taught to `word_for` in the same change,
  along with every alternation carrying the old range.
- **Prove each new comparison fails** (§1): break it, capture the red, restore
  it. Confirm the break landed by reading the file, not by `git diff` against
  `HEAD`.
- Nothing here needs a VM or an install slot. The derivations that need the
  built tree use the `omarchy` package the job already builds.

## Open questions

1. **One pull request or two?** Items 1 and 2 are small and settled. Item 3 is
   the bulk, and each quantity is its own derivation. The spec proposes landing
   1 and 2 first and item 3 after, unless you would rather have one change.
2. **Where does the default-plugin comparison live?** In `readme-counts.sh`,
   next to the other quantities, or as an evaluation over `modules/home.nix`'s
   list? The first is cheap and textual. The second cannot drift from the
   module, but costs an evaluation. For the spec.
