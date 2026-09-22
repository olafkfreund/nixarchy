---
status: approved
issue: 856
spec: spec/2026-09-22-856-derived-numbers.md
---

# Plan: the numbers the README and the site state are true, or say why not

PR 1 of 2, on branch `docs/856-derived-numbers`, which already carries the
approved intent and spec. The PR body says `Refs #856`, not `Closes`: PR 2 (the
rest of #856's table) closes it (AGENTS.md §8). A deviation updates this file in
the same commit as the code.

## Approved decisions

Copied from the spec so this file stands alone.

- **Search index count:** rounded and described as per machine in `README.md:140`
  and `docs/index.md:37` ("about 137,000 rows on a default install", with the
  breakdown rounded the same way). It is **deliberately unchecked**, and a comment
  in `readme-counts.sh`'s quantity list says why: the index is built at runtime
  from each machine's `options.json` and nixpkgs (`modules/apps.nix`).
- **`and 65 of the 67 apps` stays word for word**, because `apps-indexed` reads
  it with `and ([0-9]+) of the [0-9]+ apps`.
- **`getting-started.md:180` is untouched.** It captions a screenshot.
- **Default plugins:** `docs/index.md:75` reads *"Eight ship by default: five are
  always on, and three turn on with their feature."* That is true of
  `programs.nixarchy.defaultPluginSet` in `modules/home.nix`: eight entries,
  three with a `gate`.
- **`plugins.md` gains a Dev environments row.** Every default-plugin row carries
  a trailing `<!-- <module id> -->`.
- **The counts are three quantities in `readme-counts.sh`**, with the floor moving
  28 → 31 and `word_for` learning 1–4. **Membership is a new step in the `lint`
  job**, beside *Every manual page is in the sidebar*, naming the missing id in
  each direction.
- **Both read `home.nix` as text**, bounded to `^      defaultPluginSet = \{` …
  the next `^      \};`. They refuse fewer than five ids. No evaluation.

## Measured before planning

- The Dev environments row's *Open it* cell is **Apps ▸ Dev environments ·
  Super+Alt+E**: the section says the menu row (`plugins.md:170`), and
  `modules/apps.nix:677` seeds the binding.
- `readme-counts.sh` checks a file other than README by reassigning `$readme`
  (`:284–300` does this for `docs/llms.txt`, `ai.md` and `docs/index.md`).
- Its existing patterns match a fixed list of number words (`Ten|Eleven|…`),
  which is the fail-closed trap in §4. The new patterns capture any single word
  instead, `([A-Z][a-z]+)` and `([a-z]+)`, so only `word_for` has to learn new
  numbers, not a second list beside it.
- `word_for` covers 5–20 (`:171`). Three is below it.

## Steps

**1. `readme-counts.sh`: derive, then compare.** Beside the other derivations:

```sh
plugins_block=$(awk '/^      defaultPluginSet = \{/{f=1} f; f && /^      \};/{exit}' "$root/modules/home.nix")
p_total=$(grep -c 'id = "' <<<"$plugins_block")
p_gated=$(grep -c 'gate = ' <<<"$plugins_block")
```

- If `p_total` is under 5, refuse, naming the anchor. `quantity` already refuses
  0, but 1–4 would read as plausible.
- `p_on=$((p_total - p_gated))`.
- `word_for` learns 1–4.
- Three quantities against `docs/index.md` (reassign `$readme`, then restore it):
  `default-plugins` (capitalised), `default-plugins-on` and
  `default-plugins-gated` (lower-case), each capturing one word from
  `^([A-Z][a-z]+) ship by default: ([a-z]+) are always on, and ([a-z]+) turn on`.
- Move the floor to 31, in the check **and** in its comment.
- Add the comment recording why the index count has no quantity.

→ verify by spec Verification 3 and 5 (below).

**2. The prose.** `README.md:140` and `docs/index.md:37` are rounded as decided,
and `docs/index.md:75` is reworded.

→ verify by `readme-counts.sh --check` passing: the new quantities, and
`apps-indexed` on the rewritten line (spec Verification 4).

**3. `plugins.md`: the row and the markers.** Add the Dev environments row between
Distrobox and GitHub Actions, following the order of the page's sections. Put a
trailing `<!-- id -->` on the eight default rows. ai-mirror and Voice get none:
they are not defaults.

→ verify by rendering the page with the Jekyll build the `pages` workflow runs,
if it is cheap here. Otherwise `grep -c '<!-- ' docs/manual/plugins.md` should be
8, and an HTML comment at the end of a table row is valid in kramdown.

**4. `build.yml`: the membership step in `lint`.** Placed after *Every manual
page is in the sidebar*. It reads ids with the same `awk` bounds, refuses fewer
than five, reads `<!-- ([a-z.-]+) -->` from `plugins.md`, and runs one
`comm -23` per direction, emitting `::error::` with the id named.

→ verify by spec Verification 1 and 2. The step's shell is extracted and run
under `bash`, as #747's step was, because `lint` cannot be run locally.

**Deviation, recorded with the code that caused it.** The markers go **inside**
the last cell (`… Super+Alt+N <!-- nixarchy.pkg --> |`), not after the final
`|` as step 3 says. Rendered with kramdown's GFM parser, as the site's Pages
build does, a marker after the pipe became a **fifth, empty column for the whole
table**, header included. GitHub's own renderer drops excess cells, which is why
the placement looked safe. Inside the cell it stays a comment: 4 columns, 40
cells, 8 comments.

**And a second one: the step is in the `omarchy` job, not `lint`.** *Every
manual page is in the sidebar* lives there, and #831's spec said so. This plan
and its spec named the wrong job, and the new step sits beside it as intended.
`omarchy` runs on every pull request. This was caught because the first
extraction asked yq for `jobs.lint`, got an empty script, and **passed**. A
check run against nothing is §1's green light, so the extraction is now
confirmed by its line count before its result is read.

Steps 1–4 land in **one commit**. A commit adding a check that the prose cannot
yet satisfy would leave the branch red in between (#831's plan, deviation 1).

## Tests

Every break is confirmed by reading the file before believing its result. The
restore is `git checkout HEAD -- <file>` after committing, never
`git checkout -- <file>` (AGENTS.md §5).

| # | break | expected |
|---|---|---|
| 1 | remove `<!-- nixarchy.devenv -->` | red naming `nixarchy.devenv` only (the state on `main` today) |
| 2 | add `<!-- nixarchy.gone -->` to a row | red naming `nixarchy.gone` |
| 3 | `docs/index.md:75` back to `Seven` | `default-plugins` red, the other two silent |
| 4 | `65 of the 67` → `64 of the 67` | `apps-indexed` red |
| 5 | rename the `defaultPluginSet` anchor in a copy of `home.nix` | refusal, in both the script and the step |

```sh
OMARCHY_TREE=<main's built tree> bash .github/scripts/readme-counts.sh --check
bash <the extracted lint step>
nix fmt -- --ci
nix run --inputs-from . nixpkgs#statix -- check .
nix run --inputs-from . nixpkgs#deadnix -- --fail .
nix run --inputs-from . nixpkgs#actionlint -- .github/workflows/build.yml   # compared with main's findings
```

`readme-counts.sh` needs a built Omarchy tree for its other quantities. Use the
store path `main` built, or `nix build .#omarchy` if it is gone. That is the
only build here. There is no VM and no evaluation of a configuration.

## Rollback

`git revert` the commit. The prose returns to its old figures, the quantities
and the step disappear, and nothing outside the repository holds state.
