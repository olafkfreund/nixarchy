---
status: approved
issue: 889
author: olafkfreund
---

# Intent: the GitHub Actions panel is shown on the plugins page

## Problem

`docs/manual/plugins.md#github-actions` describes the panel in words only. It
ends with *"Not shown moving … unauthenticated, the panel holds one message
still"*: the demo VM that records every other picture on the site has no
GitHub login, so it can only show the "authenticate first" screen. A reader
can't see what the panel does (repositories → runs → jobs → steps, running
first) before enabling it.

olafkfreund/nixarchy-ghtui#20 has since tested the panel on an authenticated
desktop (razer) and recorded it. Those files are in nixarchy-ghtui#21:

- `github-actions.gif`: a 27 s, 1.06 MB, 680 px showcase. It opens on a search
  for `nixarchy`, narrows it, drills into a running `install check` run down
  to its steps, and backs out.
- Four WebP stills: the running-first list, a job's steps, search, and the
  keybindings sheet.

Only public repositories appear: every frame was OCR-checked against the 14
public repositories matching `nixarchy`. The images are cropped to the panel's
card, so no wallpaper, bar or desktop widget is in them.

## Proposed outcome

The GitHub Actions section shows the GIF and at least one still, like its
neighbours, and the "Not shown moving" line is gone. The page reads correctly
on https://olafkfreund.github.io/nixarchy/manual/plugins.

## Affected users and systems

- `docs/manual/plugins.md`, plus new files in `docs/img/features/` and
  `docs/img/plugins/`. `docs/llms.txt` already says the page has screenshots.
- GitHub Pages build for the site. No module, package or host changes, unless
  the pin is bumped (question 2).

## Constraints

- Only public repositories and no personal desktop content in any image.
  This is already true of the files, and must stay true of any recrop.
- Match the site's image conventions: GIFs in `docs/img/features/`, WebP
  stills in `docs/img/plugins/`, and alt text describing what happens.
- The GitLab pipelines section has the same "Not shown moving" line. It is
  out of scope here: no GitLab recording exists.

## Open questions

1. **Provenance.** Every other picture on the site comes from the demo VM, on
   one desktop, gated by the recorder's frame-diversity check, and #797/#825
   replaced pictures taken elsewhere. These come from razer, card-cropped, and
   were checked by OCR and by eye rather than by the recorder gate. Is that
   acceptable for this section, with a line saying where they come from, or
   should the panel wait for a demo-VM scene with GitHub authentication?
2. **Pin.** `flake.nix` pins `nixarchy-ghtui` at `dfba799`. #19 (the
   `menu.managed` marker) and #21 (a clearer offline error message) are newer.
   Should the pin be bumped in this change, after #21 merges, or separately?

## Decisions (at approval)

1. Provenance: accepted. The razer recordings are used, card-cropped, with a
   line saying where they come from.
2. Pin: bumped in this change to `4f51f7f` (nixarchy-ghtui `main` after #21).
