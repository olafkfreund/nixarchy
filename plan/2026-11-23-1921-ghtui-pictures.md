---
status: approved
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
  - Backdrop: `docs/screenshots/00-desktop.jpg` (1600×875) cropped exactly
    to 1400×875 at +100+0 and resized exactly (`!`) once to the output size:
    900×563 for the GIF, 1280×800 for stills.
  - The soft shadow is drawn **on the backdrop** with `magick`, under where
    the card goes (a black rectangle of the card's size at the card's
    position, offset +0+8, blurred σ12, 60% opacity), so the card raster is
    then placed at its exact offset with no shadow-origin shift.
  - Card resampled once, to an exact size (no `-1`), at #889's placement
    (64% of the width): GIF card 579×437 at (161,62) on 900×563; still card
    823×622 at (229,89) on 1280×800. Corners stay square (Gruvbox radius 0).
    Gruvbox on Tokyo Night is #889's approved exception.
  - Stills: `magick` composite, WebP quality 90.
  - GIF: ffmpeg reads the source GIF directly (its decoder keeps each
    frame's timestamp; do not dump to PNGs, which drops the delays):
    `[1:v]scale=579:437:flags=lanczos` overlaid on the shadowed backdrop
    (`-framerate 4 -loop 1 -i backdrop.png`) with
    `overlay=161:62:shortest=1:format=rgb`, then `fps=4`, `mpdecimate`,
    `-fps_mode vfr`, `palettegen=max_colors=96:stats_mode=diff`,
    `paletteuse=dither=bayer`. The last state (back on the list) must keep
    its hold: set `-final_delay` so the total duration matches the source
    9.43 s within 0.25 s. Under 1,048,576 bytes; if over, cut the scene,
    never fewer than 96 colours, 4 fps or 900 px.
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

`SCRATCH=/tmp/claude-1000/-mnt-code-Source-home-GitHub-nixarchy-gltui/c0f708dd-6c63-4a98-9840-0764fb6fa28c/scratchpad/1921`
(the session scratchpad; `mkdir -p` it). All commands run in the worktree
`/mnt/data/vmtest/nixarchy-1921`.

1. **Compose the images** (codex). Write `$SCRATCH/compose.sh` (not
   committed) implementing the decisions above, and run it to write
   `docs/img/features/github-actions.gif` and
   `docs/img/plugins/github-actions-{list,steps,prs}.webp` → verify:
   - `magick identify -format '%Wx%H\n'` (the canvas, not the frame: ffmpeg
     stores later GIF frames as smaller update rectangles) prints only
     900x563 for the GIF; `magick identify` gives 1280x800 for each still;
   - `stat -c %s` of the GIF < 1048576;
   - frame count from `ffprobe -count_frames` is in the tens, not hundreds
     (the 25 fps trap), every delay from `magick identify -format '%T\n'`
     is ≥ 25, and the delays sum to 918–968 cs (9.43 s ± 0.25 s);
   - pixel probe: the card's top-left border pixel is at (161,62) in the
     GIF's first frame and at (229,89) in each still.
   Traps: `-framerate 4` before `-loop 1` (`docs/AGENTS.md:150`);
   `shortest=1`; one exact resample per image; square corners; no staging
   or commits.
2. **Gates on the images** (lead, no file edits).
   - `rm -rf $SCRATCH/vf` first (the helper reuses stale samples), then
     `tests/demo/verify-frames.sh docs/img/features/github-actions.gif
     --max-bytes 1048575 --expect 'olafkfreund/nixarchy' --expect 'prepare'
     --expect 'Set up job' --dump $SCRATCH/vf` passes; the same run with an
     extra `--expect 'zz-not-there'` fails (the content check can fail).
   - Every coalesced frame of the output GIF, viewed in order (contact
     sheet), shows list → steps → back to the list, and the last frame is
     the list.
   - OCR allow-list: tesseract (2× upscaled, inverted) on every coalesced
     GIF frame and each still; the `olafkfreund/…` tokens go to
     `$SCRATCH/ocr-tokens.txt`. Fails if any image yields no `olafkfreund/`
     token at all (OCR failure), or if a token is outside the ten names.
     An out-of-list token that is a misread (e.g. `nixarchy-gltul`) is
     resolved by looking at that frame, and noted in the PR. The matcher is
     shown to flag a planted `olafkfreund/private-test` line.
   - Every distinct frame and all three stills checked by eye.
   If OCR fails, place the card larger, re-run step 1, and record the
   deviation here in the same commit as the images.
   **Deviation, recorded at implementation:** on the whole composite,
   tesseract read no `olafkfreund/` name from the list still (the backdrop
   disturbs it), so the gate crops to the card (579×437+161+62 for GIF
   frames, 823×622+229+89 for stills) and upscales 3× before inverting.
   With that, all 13 GIF frames and 3 stills yield names; the only
   out-of-list tokens (`nixarchy-gltul`, `nlxarchy`, `nixarchy-meetingal`,
   `nixarchy-podsan`) were misreads of listed names, confirmed by eye on
   frames 0, 1, 2 and 12. The planted `olafkfreund/private-test` was
   flagged. The images are committed before step 3, not with the page,
   because `herdr-team up` refuses a dirty worktree.
3. **Edit the page** (agy). Before handing off, the lead runs the text check
   below and confirms it finds "running workflows first" (wrapped over lines
   222-223 today), so it can fail. agy edits only `docs/manual/plugins.md`
   lines 216-237 as decided above → verify, on
   `sed -n '/^## GitHub Actions/,/^## Plugin Browser/p' docs/manual/plugins.md | tr -s ' \n' ' '`:
   - "failing repositories first, then running ones" and the `p` sentence
     are present; "running workflows first" is not;
   - the four image entries appear in order GIF, list, steps, prs, each
     with exactly its approved alt text (`grep -F` on the full
     `![alt](path)` string);
   - the provenance line is unchanged;
   - `git status --porcelain` lists only `docs/manual/plugins.md` and the
     four image files (untracked included).
   Traps: edit with file tools only; no other section changes.
4. **Review and PR** (lead). Commit images and page together:
   `docs: refresh the GitHub Actions pictures from nixarchy-ghtui#25 (#1921)`.
   Codex `review --base origin/main` and agy, read-only, in parallel; both
   are also given `$SCRATCH/compose.sh` and the step 1-2 outputs, since the
   images are binary. An Opus code-reviewer on the final diff. Fix confirmed
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
rm -rf "$SCRATCH/vf"
tests/demo/verify-frames.sh docs/img/features/github-actions.gif --max-bytes 1048575 \
  --expect 'olafkfreund/nixarchy' --expect 'prepare' --expect 'Set up job' --dump "$SCRATCH/vf"
magick identify -format '%Wx%H\n' docs/img/features/github-actions.gif | sort -u   # 900x563
magick identify docs/img/plugins/github-actions-{list,steps,prs}.webp             # 1280x800 each
sed -n '/^## GitHub Actions/,/^## Plugin Browser/p' docs/manual/plugins.md | tr -s ' \n' ' '
```

Plus the OCR allow-list gate (passes on the images, flags the planted name).

## Rollback

Docs only. Before merge, close the PR. After merge, revert the commit; the
old images come back with it.
