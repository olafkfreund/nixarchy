---
status: draft
issue: 1434
author: olafkfreund
---

# Intent: The site, manual and README show nixi's new features and the companion

## Problem

Once #1432 merges, every nixarchy machine runs nixi at current master, and the snowflake
companion is one line away. The docs a user reads still describe nixi as of `5ae2ca4`:

- **README feature table** (`README.md:526`): "The guide" row. The companion isn't in it.
- **Site front page** (`docs/index.md`): it doesn't mention nixi or the companion at all.
- **The manual:**
  - `docs/manual/ai.md` "Nixi, on SUPER + H" (`:260`) shows the card (`img/features/nixi.gif`),
    Guide and Mechanic. #1432's P4 adds only a short companion paragraph.
  - `docs/manual/getting-started.md` "The guide" (`:212`).
- **Not shown anywhere in nixarchy:**
  - the snowflake companion;
  - asking about and opening agent sessions by voice;
  - Guide keeping secret files from shell commands, Codex and opencode;
  - a turn that stops on its own instead of hanging.

The last broad docs pass (#1425, "The site, the manual and the README match what ships on
main and edge") is days old. Apart from nixi, the docs already match what ships.

## Proposed outcome

- **The manual** has a companion section in `ai.md`, with a GIF in the house style: the whole
  desktop at 16:10, 900×563, under 1 MB, recorded on a real nixarchy desktop. It covers:
  - what it is and how to turn it on;
  - the keys;
  - that it follows Guide/Mechanic;
  - what it leaves out.
- **The Guide/Mechanic text** in `ai.md` and `getting-started.md` names what Guide now keeps out
  of the agent's reach.
- **The site front page** shows the companion among the features, with its GIF.
- **The README** feature table names the companion in the guide row, or in a row of its own,
  linking the manual section.
- `llms.txt` and the three lists `build.yml` checks stay in agreement (only relevant if a page is
  added).

## Affected users and systems

- nixarchy `docs/`: `index.md`, `manual/ai.md`, `manual/getting-started.md`, `img/features/`,
  possibly `llms.txt`.
- `README.md`.
- People reading the README, the Pages site or the manual.
- No code changes.

## Constraints

- **Follow `docs/AGENTS.md`:**
  - whole-desktop captures at 16:10, never a cropped widget;
  - the default theme;
  - GIFs at 4 fps, 900 px, under 1 MB;
  - recorded with `tests/demo/screencast/`.
- Media need the companion running, so this comes after #1432 merges and p620 is rebuilt
  (or a nixarchy VM with the companion on).
- No secrets or personal data in any recording.
- `build.yml`'s "Every manual page is in the sidebar" check must stay green.

## Open questions

1. **Record on p620 or in a VM?**
   - p620 is the real desktop, but its theme and wallpaper may not be the default the house
     style asks for, and `screencast-prep` hides third-party widgets.
   - A nixarchy VM (`nix run .#vm`) is the default desktop, but it has no microphone, so voice
     can't be shown live.
   - Recommendation: p620, with `screencast-prep`, temporarily on the default theme.
2. **Does the README get a row of its own for the companion, or a mention in the guide row?**
   Recommendation: a mention in the guide row, since it's an option of the guide and off by
   default.
3. **"The latest features" beyond nixi.** #1425 just aligned the docs with main and edge, so this
   intent covers only nixi and the companion. Say if you want a wider pass.
