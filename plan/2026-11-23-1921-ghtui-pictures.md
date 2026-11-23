---
status: draft
issue: 1921
spec: spec/2026-11-23-1921-ghtui-pictures.md
coders:
  1: codex   # small, fiddly ffmpeg/magick geometry and timing; Codex is the default for tricky logic
  3: agy     # prose edit in one section; agy wrote the matching README text in nixarchy-ghtui#25
reviewers:
  - codex    # independent read of the diff against this plan
  - agy      # second provider; caught the corner and resampling issues in the spec
---

# Plan: the GitHub Actions section shows the current panel

## Approved decisions

- **Sources:** nixarchy-ghtui `21cdd23` (local checkout
  `/mnt/code/Source-home/GitHub/nixarchy-ghtui-25`, `docs/img/`):
  `github-actions.gif` (680×514, 66 frames, 9.43 s, variable delays) and
  `github-actions-{list,steps,prs}.webp` (900×680, lossy). No re-recording;
  razer is not touched.
- **Composed, not copied** (`docs/AGENTS.md:31-50`; intent amended at spec
  approval):
  - Backdrop: `docs/screenshots/00-desktop.jpg` (1600×875) cropped to
    1400×875 at +100+0, then scaled once to the output size.
  - Card resampled once, straight into the output frame, at #889's
    placement (64% of the width): GIF card 579×437 at (161,62) on 900×563;
    still card 823×622 at (229,89) on 1280×800.
  - Corners stay square (Gruvbox radius 0). Soft shadow: `magick … \(
    +clone -background black -shadow 60x12+0+8 \) +swap -layers merge`
    under the card. Gruvbox on Tokyo Night is #889's approved exception.
  - GIF: coalesce the source with its own delays, `fps=4`, backdrop read
    with `-framerate 4 -loop 1`, `mpdecimate` + `-fps_mode vfr`,
    `palettegen=max_colors=96:stats_mode=diff`,
    `paletteuse=dither=bayer`, lanczos. Under 1,048,576 bytes; if over, cut
    the scene, never fewer than 96 colours, 4 fps or 900 px.
  - Stills: WebP quality 90.
- **Page** (`docs/manual/plugins.md`, `## GitHub Actions`, lines 216-237):
  replace the three images, add the PR still after the steps still, new alt
  text (below), "with running workflows first" → "failing repositories
  first, then running ones", and end the "What it does" paragraph with
  "**p** switches to open pull requests and their status checks." The
  provenance line stays.
- **No pin change** (`nixarchy-ghtui` stays at `cdc49ac`).
- **Privacy:** every `olafkfreund/<name>` OCR reads from each distinct GIF
  frame and each still must be one of the ten public repositories:
  nixarchy, nixarchy-ghtui, nixarchy-flea, nixarchy-flatsnap,
  nixarchy-podman, nixarchy-pkg, nixarchy-gltui, nixarchy-herdr,
  nixarchy-meetingai, nixarchy-hyprflip. Plus a check by eye.

Alt text:

- GIF: *The GitHub Actions panel filtered to olafkfreund/nixarchy, drilling
  into a running omarchy-edge workflow down to the steps of its prepare job
  and back out*
- list: *Repositories matching nixarchy, the one with a running workflow
  first*
- steps: *A running omarchy-edge run expanded to its prepare job, and the job
  to its steps*
- prs: *The pull-request view for olafkfreund/nixarchy-hyprflip, with pull
  request #12 expanded to its four passing status checks*

## Steps

1. **Compose the images** (codex). Write `$SCRATCH/compose.sh` (scratchpad,
   not committed) implementing the decisions above, and run it to write
   `docs/img/features/github-actions.gif` and
   `docs/img/plugins/github-actions-{list,steps,prs}.webp` in the worktree
   → verify: `magick identify` gives 900×563 for every GIF frame and
   1280×800 for each still; `stat -c %s` of the GIF < 1048576;
   `ffprobe -count_frames` frame count is in the tens, not hundreds (the
   25 fps trap); `magick identify -format '%T\n'` delays are all ≥ 25.
   Traps: `-framerate 4` before `-loop 1` (`docs/AGENTS.md:150`); one
   resample per image; square corners; work only in the worktree
   `/mnt/data/vmtest/nixarchy-1921`; no staging or commits.
2. **Gates on the images** (lead, no file edits).
   - `tests/demo/verify-frames.sh docs/img/features/github-actions.gif
     --max-bytes 1048575 --expect 'olafkfreund/nixarchy' --expect 'prepare'
     --expect 'Set up job' --dump $SCRATCH/vf` passes.
   - The dumped frames, in order, show list → steps → back to the list.
   - OCR allow-list (tesseract on each distinct GIF frame, 2× upscaled and
     inverted, and on each still) prints no `olafkfreund/` name outside the
     list.
   - Look at all three stills and a frame per state.
   If OCR fails, place the card larger, re-run step 1, and record the
   deviation here in the same commit as the images.
3. **Edit the page** (agy). Before handing off, the lead runs the text check
   below and confirms it finds "running workflows first" (so it can fail).
   agy edits only `docs/manual/plugins.md` lines 216-237 as decided above
   → verify:
   `sed -n '/^## GitHub Actions/,/^## Plugin Browser/p' docs/manual/plugins.md | tr -s ' \n' ' '`
   contains the four image paths (`../img/features/github-actions.gif`,
   `../img/plugins/github-actions-{list,steps,prs}.webp`), the `p` sentence
   and "failing repositories first", and not "running workflows first";
   `git diff --stat` shows only that file besides the images.
   Traps: edit with file tools only; no other section changes.
4. **Review and PR** (lead). Commit images and page together:
   `docs: refresh the GitHub Actions pictures from nixarchy-ghtui#25 (#1921)`.
   Codex `review --base origin/main` and agy (diff + this plan), read-only,
   in parallel; an Opus code-reviewer on the final diff. Fix confirmed
   findings, recording any deviation here. Push and open the PR linking
   intent, spec and plan, saying step 1 was Codex and step 3 agy → verify
   the PR's checks are green and the four image URLs on the branch return
   200 (`raw.githubusercontent.com`).
5. **After merge** (lead, on your "merge"). Once Pages deploys,
   https://olafkfreund.github.io/nixarchy/manual/plugins#github-actions
   references the four images, each returns 200 with `curl`, and the `p`
   sentence and provenance line are on the page. Close #1921.

## Tests

```sh
tests/demo/verify-frames.sh docs/img/features/github-actions.gif --max-bytes 1048575 \
  --expect 'olafkfreund/nixarchy' --expect 'prepare' --expect 'Set up job' --dump "$SCRATCH/vf"
magick identify docs/img/plugins/github-actions-{list,steps,prs}.webp   # 1280x800 each
sed -n '/^## GitHub Actions/,/^## Plugin Browser/p' docs/manual/plugins.md | tr -s ' \n' ' '
```

Plus the OCR allow-list printing nothing.

## Rollback

Docs only. Before merge, close the PR. After merge, revert the commit; the
old images come back with it.
