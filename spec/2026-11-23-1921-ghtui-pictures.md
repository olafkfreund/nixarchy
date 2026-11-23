---
status: draft
issue: 1921
intent: intent/2026-11-23-1921-ghtui-pictures.md
---

# Spec: the GitHub Actions section shows the current panel

## What was found before designing

- **The intent's "copied byte-for-byte" constraint conflicts with the house
  style.** `docs/AGENTS.md:31-50` says every image on the site is a capture of
  the desktop, not a cropped widget: a panel is composed onto
  `docs/screenshots/00-desktop.jpg` cropped to 16:10, cut at its border, with
  rounded corners and a soft shadow, centred for a menu panel. Feature GIFs
  are 900×563, 4 fps, under 1 MB, at most 96 colours; stills are 1280×800.
  The current pictures follow it (`magick identify`: GIF 900×563, both stills
  1280×800), and #797 corrected pictures that didn't. The ghtui#25 files are
  card crops (GIF 680×514, stills 900×680), so they can be the *source* but
  not the published file. This spec composes them, and needs your OK on that
  departure from the approved intent.
- **The original recording is gone.** `/tmp/g25.mp4` is no longer on razer,
  and no MP4 or PNG of the retake is kept locally. The sources are the
  published ghtui `21cdd23` files: a 680×514 GIF and three 900×680 lossy
  WebPs. Re-recording on razer is not proposed: it disrupts that desktop
  again for a quality gain the composition doesn't need (see Risks).
- **#889 left the recipe** (`plan/2026-09-22-889-github-actions-showcase.md`
  steps 1-3 and its deviation note): a 1400×875 canvas from the backdrop, the
  card at native 900×680 centred at (250,97), scaled to 900×563 (card ≈ 64%
  of the width; at 900/1920 the text was too small for OCR), the backdrop
  read at `-framerate 4`, `mpdecimate` for holds, palette ≤96 colours with
  `stats_mode=diff`. `docs/AGENTS.md` records the ffmpeg traps it hit.

## Design

### 1. Compose from the ghtui `21cdd23` files

One scratchpad script (`compose.sh`, not committed, as in #889):

- Backdrop: `00-desktop.jpg` cropped to 1400×875, centred.
- Card: cut at its border (the files already are), rounded corners at the
  theme radius, soft shadow, centred at (250,97) on the canvas at 900×680
  (#889's placement). The GIF's 680×514 frames are scaled up to 900×680
  before placing, so the published card is the same size as today's; the
  whole frame is then scaled to 900×563 (net 680→579 px, a downscale).
- GIF: the source GIF (66 frames, 9.43 s) re-sampled to 4 fps, encoded per `tests/demo/encode-gif.sh` rules: 900×563, lanczos,
  `palettegen=max_colors=96:stats_mode=diff`, under 1 MB.
- Stills: `github-actions-{list,steps,prs}.webp` composed at 1280×800.

### 2. Publish on the plugins page

In `docs/manual/plugins.md` (`## GitHub Actions`, lines 216-237):

- Replace `docs/img/features/github-actions.gif` and
  `docs/img/plugins/github-actions-{list,steps}.webp`; add
  `docs/img/plugins/github-actions-prs.webp` after the steps still.
- Alt text, from ghtui's README and checked against each capture:
  - GIF: *The GitHub Actions panel opening filtered to olafkfreund/nixarchy,
    then drilling into a running workflow down to the steps of its prepare
    job and back out*
  - list: *Repositories matching nixarchy, the one with a running workflow
    first*
  - steps: *A running omarchy-edge run expanded to its prepare job, and the
    job to its steps*
  - prs: *The pull-request view for olafkfreund/nixarchy-hyprflip, with pull
    request #12 expanded to its four passing status checks*
- Text: "with running workflows first" → "failing repositories first, then
  running ones"; add "**p** switches to open pull requests and their status
  checks." before the stills.
- The provenance line stays as it is.

No pin change (intent decision 2).

## Alternatives rejected

- **Ship the card crops as they are** (the intent's wording): breaks
  `docs/AGENTS.md`; #797 is the precedent for correcting exactly that.
- **Re-record on razer at the house sizes:** disrupts razer's desktop again
  (ai-mirror control, a GIF take) for a sharper source; the composite is a
  downscale of the existing files, so it isn't needed.
- **Composite only the stills and keep today's GIF:** the old GIF shows the
  pre-1.3 text size, which is what the issue is about.

## Risks

- **OCR on the GIF:** the source GIF is already 680 px and 256-colour;
  re-palettising onto a gradient may soften text. `verify-frames.sh` is the
  gate; if it can't read the expected words, fall back to placing the card
  larger (as #889's deviation did) and record it in the plan.
- **Size:** a backdrop gradient costs bytes; the 96-colour cap and
  `mpdecimate` kept #889's 46.75 s take at 1,020,375 bytes, just under the
  1,048,576 limit. The new take is 9.43 s, so it should fit easily; if not, cap
  colours lower, never below 4 fps or 900 px.
- **Privacy:** compositing adds only the stock backdrop. The same allow-list
  OCR check runs on the composites (every `owner/name` must be one of the
  public repositories already checked), plus a check by eye.
- No module, package or host is touched; nothing to deploy.

## Verification

- `magick identify`: GIF 900×563, stills 1280×800; `stat`: GIF under 1 MB.
- `tests/demo/verify-frames.sh docs/img/features/github-actions.gif
  --max-bytes 1048576 --expect 'olafkfreund/nixarchy' --expect
  'prepare|omarchy-edge' --expect 'running|in_progress'` passes.
- OCR allow-list check on GIF frames (2 fps) and the three stills finds no
  repository outside the public list; frames and stills checked by eye.
- `grep` shows the four image paths and the `p` sentence in the section, and
  no "running workflows first".
- The PR's checks are green; after merge (Pages deploys from `main`), `curl` returns 200 for
  each image URL under https://olafkfreund.github.io/nixarchy/.
