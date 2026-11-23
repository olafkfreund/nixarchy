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

One scratchpad script (`compose.sh`, not committed, as in #889). Each card
is resampled **once**, straight into the output frame, at #889's placement
(900×680 at (250,97) on a 1400×875 canvas, i.e. 64% of the width):

- Backdrop: `00-desktop.jpg` cropped to 16:10 (1400×875, centred), then
  scaled once to the output size (900×563 for the GIF, 1280×800 for stills).
- Card: already cut at its border. Corners stay **square**: Gruvbox's radius
  is 0, and #889 decided that rounding the card would misstate the theme; the
  Gruvbox card on the Tokyo Night backdrop is #889's approved exception,
  carried over. Soft shadow as in #889.
- GIF: each 680×514 frame scaled once to 579×437, overlaid at (161,62) on the
  900×563 backdrop. Source timing kept (coalesced frames with their own
  delays), then `fps=4`; backdrop input read at `-framerate 4`;
  `mpdecimate` with `-fps_mode vfr` so holds become longer frames;
  `palettegen=max_colors=96:stats_mode=diff`, `paletteuse=dither=bayer`,
  lanczos (the `tests/demo/encode-gif.sh` and #889 recipe).
- Stills: each 900×680 WebP scaled once to 823×622, overlaid at (229,89) on
  the 1280×800 backdrop, written as WebP at quality 90 (the sources are
  already lossy; one more high-quality generation).

### 2. Publish on the plugins page

In `docs/manual/plugins.md` (`## GitHub Actions`, lines 216-237):

- Replace `docs/img/features/github-actions.gif` and
  `docs/img/plugins/github-actions-{list,steps}.webp`; add
  `docs/img/plugins/github-actions-prs.webp` after the steps still.
- Alt text, checked against each capture:
  - GIF: *The GitHub Actions panel filtered to olafkfreund/nixarchy,
    drilling into a running omarchy-edge workflow down to the steps of its
    prepare job and back out*
  - list: *Repositories matching nixarchy, the one with a running workflow
    first*
  - steps: *A running omarchy-edge run expanded to its prepare job, and the
    job to its steps*
  - prs: *The pull-request view for olafkfreund/nixarchy-hyprflip, with pull
    request #12 expanded to its four passing status checks*
- "What it does" paragraph: "with running workflows first" (wrapped over
  lines 222-223) becomes "failing repositories first, then running ones",
  and the paragraph ends with "**p** switches to open pull requests and
  their status checks."
- The provenance line stays as it is.

No pin change (intent decision 2). On approval of this spec, the intent's
"copied byte-for-byte" constraint is amended to "composed from" in the same
commit, citing `docs/AGENTS.md`.

## Alternatives rejected

- **Ship the card crops as they are** (the intent's wording): breaks
  `docs/AGENTS.md`; #797 is the precedent for correcting exactly that.
- **Upscale the GIF card to 900×680 first, as #889 placed it:** two
  non-integer resamples soften text; one downscale gives the same layout.
- **Re-record on razer at the house sizes:** disrupts razer's desktop again
  for a sharper source that the composite, a downscale, doesn't need.
- **Composite only the stills and keep today's GIF:** the old GIF shows the
  pre-1.3 text size, which is what the issue is about.

## Risks

- **OCR on the GIF:** the card ends up 579 px wide from a 256-colour source.
  #889 needed 64% width for OCR and this keeps it. If `verify-frames.sh`
  still can't read the expected words, place the card larger and record the
  deviation in the plan.
- **Timing:** the source GIF has variable delays (66 frames, 9.43 s). Brief
  states could be dropped at 4 fps; the steps view is held for 13 frames
  (OCR of source frames 35-47 shows "Set up job"), so it survives.
- **Size:** #889's 46.75 s take was 1,020,375 bytes; this one is 9.43 s. If it
  is over anyway, `verify-frames.sh` says cut the scene, not the encoding:
  never below 96 colours, 4 fps or 900 px.
- **Privacy:** compositing adds only the stock backdrop. The OCR allow-list
  check covers every distinct GIF frame and the three stills.
- No module, package or host is touched; nothing to deploy.

## Verification

- `magick identify`: GIF 900×563, stills 1280×800. Frame delays ≥ 25 cs
  (4 fps, longer for merged holds).
- `tests/demo/verify-frames.sh docs/img/features/github-actions.gif
  --max-bytes 1048575 --expect 'olafkfreund/nixarchy' --expect 'prepare'
  --expect 'Set up job' --dump $SCRATCH/vf` passes (`Set up job` only
  appears once a job is expanded to its steps).
- The dumped frames, viewed in order, show list → steps → back to the list.
- OCR allow-list: every `olafkfreund/<name>` read from each distinct GIF frame
  and the three stills is one of the ten public repositories checked in the
  intent. Action references (`actions/checkout`, `cachix/cachix-action`) and
  the upstream `thisisgm/flea` in a description are not account repositories
  and are excluded by matching only `olafkfreund/`. Checked by eye as well.
- Text, with whitespace collapsed (the old phrase wraps):
  `tr -s ' \n' ' '` of the section contains the four image paths, the `p`
  sentence and "failing repositories first", and not "running workflows
  first". The same command run before the edit finds the old phrase, so the
  check can fail.
- The PR's checks are green. After merge (Pages deploys from `main`), the
  page https://olafkfreund.github.io/nixarchy/manual/plugins#github-actions
  references all four images, each image URL returns 200 with `curl`, and
  the `p` sentence and provenance line are on the page.
