---
status: draft
issue: 1434
intent: intent/2026-10-24-1434-docs-nixi-showcase.md
---

# Spec: The site, manual and README show nixi's new features and the companion

## Design

This lands after #1432 (whose P4 adds a short companion paragraph to `ai.md`) and after p620
is rebuilt with the companion on.

### Media (`docs/img/features/companion.gif`)

- One GIF: press SUPER+ALT+H and the snowflake appears; it answers a question (its caption
  bubble shows the spoken answer); it melts to the screen edge.
- **House style (`docs/AGENTS.md`):**
  - a whole desktop at 16:10, recorded with `wl-screenrec -g "<x>,<y> 2304x1440"`;
  - encoded with `tests/demo/encode-gif.sh` (4 fps, 900 px wide, palette ≤ 96);
  - **< 1 MB**, so 900×563.
- Recorded on p620 (intent answer 1):
  - `screencast-prep` first, which hides third-party bar widgets and refuses if windows or
    notifications are open;
  - switched to the default theme (Tokyo Night, Winding Road);
  - `screencast-restore` after, and the theme and wallpaper put back from
    `omarchy-theme-current` / `omarchy-theme-bg-current`.
- **"What a recording may show"** applies: an empty workspace, herdr out of shot, Do Not
  Disturb, nothing translucent over private content.
- The same take serves nixi#108. If one recording meets both repos' rules, record once and use
  the file in both, each at its own path.
- **Who drives:** the lead, through ai-mirror after the user grants control. Otherwise the user
  records from the shot list in the plan.

### Text

- **`docs/manual/ai.md`, "Nixi, on SUPER + H":**
  - The #1432 paragraph grows into a `### The snowflake companion` subsection with the GIF. It
    covers:
    - what it is;
    - turning it on: `services.nixi.companion.enable = true;`;
    - the keys (`o.bind` lines for SUPER+ALT+H / J);
    - that it follows Guide/Mechanic;
    - asking about and opening herdr agent sessions by voice (sending always needs a click);
    - what it leaves out (link to nixi's README).
  - The Guide/Mechanic paragraph gains one or two sentences:
    - Guide keeps secret files (`~/.ssh`, credentials, `.env`, `/run/agenix`) away from the
      agent's file tools and shell commands;
    - Codex isn't offered at Guide;
    - a turn that goes silent ends instead of hanging.
- **`docs/manual/getting-started.md`, "The guide" (`:212`):**
  - One sentence and a link to the companion subsection.
  - **Fix a naming clash:** this page calls nixi's bar button "the snowflake" (`:220`), but the
    button is ✨ since nixi#15 (`ai.md:262` already says ✨), and "the snowflake" is now the
    companion. Change it to "the ✨ in the bar".
- **`docs/index.md` (the site front page):** a short "The guide" block naming nixi and the
  companion, with `companion.gif` in the front page's `[![…](…gif)](…gif)` form, placed among
  the other feature GIFs.
- **`README.md:526`, the guide row:**
  - add "and an optional snowflake companion that listens and talks, through the same trust
    levels", linking to `manual/ai#the-snowflake-companion`;
  - fix "the snowflake in the bar" → "the ✨ in the bar" here too.
- **`docs/llms.txt:74`:** the same naming fix, and one clause for the companion. No new page is
  added, so the three lists `build.yml` checks don't change.

## Alternatives rejected

- **A manual page of its own for the companion.** It's an option of the guide, so it sits in the
  guide's section. A new page would also mean editing the three lists `build.yml` checks.
- **Recording in a VM.** It has no microphone, so voice can't be shown (intent answer 1).
- **A README row of its own.** It's off by default and part of the guide (intent answer 2).
- **A wider docs pass.** #1425 just did one (intent answer 3).

## Risks

- **Private data in the recording.** Mitigation: `screencast-prep`, an empty workspace, and a
  frame-by-frame review before commit.
- **The desktop isn't fully restored** (theme, widgets). Mitigation: `screencast-restore`, then
  compare with the recorded starting state; `screencast-recover` for a take that died.
- **The anchor `#the-snowflake-companion` drifts** if the heading changes. Link checks in CI
  (if any) catch it. Otherwise it's checked by hand on Pages.
- **The naming fix misses an occurrence.** Mitigation: `grep -rn "snowflake" docs README.md` and
  check each hit.

## Verification

| Check | Expected |
|---|---|
| `ls -l docs/img/features/companion.gif`; `identify` | < 1 MB, 900×563 |
| `grep -rn -i "snowflake" docs README.md` | refers only to the companion |
| `nix flake check` and PR CI, including `build.yml` "Every manual page is in the sidebar" | green |
| Pages after merge | `manual/ai#the-snowflake-companion` resolves; the GIFs load on the front page and in the manual |
| The desktop after recording | theme, wallpaper and bar widgets match the starting state |
