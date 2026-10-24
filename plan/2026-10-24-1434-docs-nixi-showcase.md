---
status: approved
issue: 1434
spec: spec/2026-10-24-1434-docs-nixi-showcase.md
---

# Plan: The site, manual and README show nixi's new features and the companion

## Approved decisions (from the spec, so this file stands alone)

- **Order:** after #1432 is merged (its P4 adds a short companion paragraph to `ai.md`) and after
  p620 is rebuilt with the companion on.
- **One GIF, `docs/img/features/companion.gif`:**
  - SUPER+ALT+S summons the snowflake, it answers a question (caption bubble), and it melts to
    the edge;
  - house style (`docs/AGENTS.md`): a whole desktop at 16:10, 900×563, 4 fps, palette ≤ 96,
    **< 1 MB**, the default theme (Tokyo Night, Winding Road).
  - It's recorded once on p620 by nixi#108's plan (R0–R4) and copied here. That plan follows this
    repo's rules: `screencast-prep` before, `screencast-restore` after, an empty workspace, herdr
    out of shot, DND on, frame review.
- **`docs/manual/ai.md`:**
  - the #1432 paragraph becomes `### The snowflake companion` with the GIF. It covers:
    - what it is;
    - `services.nixi.companion.enable = true;`;
    - the `o.bind` lines for SUPER+ALT+S / SUPER+ALT+SHIFT+S;
    - that it follows Guide/Mechanic;
    - herdr sessions by voice (asking and opening; sending needs a click);
    - a link to nixi's README for what it leaves out.
  - The Guide/Mechanic paragraph gains: secret files (`~/.ssh`, credentials, `.env`,
    `/run/agenix`) stay away from the agent's file tools and shell; Codex isn't offered at
    Guide; a silent turn ends instead of hanging.
- **`docs/manual/getting-started.md` "The guide":**
  - one sentence and a link to the subsection;
  - **naming fix** `:220`: "the snowflake in the bar" → "the ✨ in the bar".
- **`docs/index.md`:** a short guide block naming nixi and the companion, with the GIF in the
  `[![alt](img/features/companion.gif)](img/features/companion.gif)` form.
- **`README.md:526`:** the companion clause and link added; naming fix "the snowflake in the bar"
  → "the ✨ in the bar". **`README.md:465`** ("the menu button wears the snowflake") is the NixOS
  logo on the menu button, so it stays.
- **`docs/llms.txt:75`:** the naming fix and one clause for the companion.
- **No new page**, so `_config.yml` nav, `llms.txt`'s Manual list and `manual/index.md` don't
  change.

## Steps

**D0. Preconditions:** #1432 is merged, the worktree is rebased onto `origin/main` (so the
#1432 paragraph is in `ai.md`), and nixi#108's R4 has produced a reviewed `companion.gif`.
- Verify:
  - `git -C … log origin/main --oneline | grep 1432`;
  - `stat -c %s companion.gif` is < 1048576;
  - `identify` shows 900×563.

**D1. The GIF:** copy it to `docs/img/features/companion.gif`. Verify the same as D0.

**D2. `docs/manual/ai.md`** (the "## Nixi, on SUPER + H" section, `:260` up to the
"### If you installed Claude some other way" heading)
- Turn #1432's paragraph into `### The snowflake companion`, with the GIF in the section's existing
  image form (`![alt](../img/features/companion.gif)`) and the content decided above. Show the
  key lines in a ```lua block.
- Extend the Guide/Mechanic paragraph (the one starting "It has two trust levels") with the
  sentences decided above.
- Verify: `grep -n "the-snowflake-companion\|companion.gif" docs/manual/ai.md`.
- Trap: Jekyll's slug for `### The snowflake companion` is `the-snowflake-companion`. Other
  pages link to that.

**D3. `docs/manual/getting-started.md`** `:212-240`
- `:220`: "Click the snowflake in the bar" → "Click the ✨ in the bar".
- After the paragraph that names Claude Code (`:222-224`), add: "It can also come as a snowflake
  on your desktop that listens and talks back, off by default: see
  [the snowflake companion](ai#the-snowflake-companion)."
- Verify: `grep -n "snowflake" docs/manual/getting-started.md` shows only the companion.

**D4. `docs/index.md`**
- Before `## Panels, not terminals` (`:76`), add a `## A guide that knows this machine` block:
  - 3–4 lines: nixi on ✨ / SUPER+H, answers from the manual on disk, Guide changes nothing,
    Mechanic asks;
  - the optional snowflake companion that listens and talks;
  - the GIF;
  - a link: `See **[Nixi](manual/ai#nixi-on-super--h)**.`
- Verify the anchor with `grep -n "## Nixi, on SUPER + H" docs/manual/ai.md`. Jekyll slugs `+` away,
  giving `nixi-on-super--h`, which `ai.md:285` already uses.

**D5. README and llms.txt**
- `README.md:526`: "from the snowflake in the bar" → "from the ✨ in the bar". Before "—
  [the page]", add: "and an optional [snowflake companion](https://olafkfreund.github.io/nixarchy/manual/ai#the-snowflake-companion)
  that listens and talks, through the same trust levels".
- `docs/llms.txt:75`: "from the snowflake in the bar" → "from the ✨ in the bar", and add ", with an
  optional snowflake companion (off by default)".
- Verify: `grep -rn -i "snowflake" README.md docs --include=*.md --include=*.txt`. Every hit is
  the companion, plus `README.md:465` (the menu button logo).

**D6. Checks and PR (lead)**
- Run `nix flake check`, at least the docs checks `build.yml` runs (the manual-in-sidebar check).
- Optionally build Pages locally with Jekyll, if it's available.
- The last commit subject is a full sentence, with no conventional prefix (`AGENTS.md` §8). PR title:
  "The manual, site and README show nixi's snowflake companion and Guide's secret protection
  (#1434)".
- Fill in the PR template, link intent, spec and plan, and embed the GIF.
- Merge only after the user has seen the GIF in the PR.

## Deviations

- **The GIF is deferred to #1441** (the owner's choice, 2026-10-24).
  - Recording it needs someone to ask the companion a question aloud, and
    `screencast-prep` refuses while any window is open, which the owner's
    p620 session had.
  - So **D0's GIF precondition and D1 are skipped**.
  - **D2's** `### The snowflake companion` subsection is written without the
    image line.
  - **D4's** guide block is written without the GIF.
  - **D6's** merge condition ("only after the user has seen the GIF") becomes
    "once CI is green".
  - #1441 adds the GIF to both places.
- **p620 already runs the companion** (olafkfreund/nixos_config#2468), which
  meets D0's "p620 is rebuilt with the companion on".
- **Line references after merging `main`:** `docs/index.md`'s
  `## Panels, not terminals` is at line 77, not 76. The others are unchanged.

## Tests

| Check | Expected |
|---|---|
| `stat`/`identify` on `companion.gif` | < 1 MB, 900×563 |
| The snowflake grep (D5) | only the companion, plus the menu-button logo |
| PR CI, including "Every manual page is in the sidebar" | green |
| Pages after merge | `manual/ai#the-snowflake-companion` and `manual/ai#nixi-on-super--h` resolve; the GIF loads on the front page and in the manual |

## Rollback

Revert the merge. Docs only.
