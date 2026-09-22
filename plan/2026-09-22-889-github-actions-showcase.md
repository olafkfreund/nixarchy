---
status: approved
issue: 889
spec: spec/2026-09-22-889-github-actions-showcase.md
---

# Plan: the GitHub Actions panel is shown on the plugins page

## Approved decisions

- **Sources:** the razer recordings from nixarchy-ghtui#20, in Gruvbox; there's
  no re-recording, and razer isn't touched. They are the 920×700 MP4 (card
  on screen 3.6–52.4 s, card at +10+10, 900×680) and the full-screen PNGs
  `s1-list` and `s2-steps` (card at +510+200, 900×680). All are in the
  session scratchpad.
- **House style (`docs/AGENTS.md`) is followed except for the theme:**
  - Backdrop: `docs/screenshots/00-desktop.jpg` cropped to 16:10 (1400×875,
    centred).
  - The card is scaled to 900/1920 of the backdrop width, cut at its border,
    and centred with a soft shadow. Its corners stay as razer draws them:
    Gruvbox's radius is 0, and rounding a square card would misstate the
    theme.
  - GIF: 4 fps, 900×563, lanczos, one palette of ≤96 colours, under 1 MB.
  - Stills: WebP at 1280×800.
  - A Gruvbox panel on the Tokyo Night desktop is the one approved exception.
- **Page:** the GIF plus two stills (list, and steps), stacked at full width,
  in `docs/manual/plugins.md#github-actions`. The "Not shown moving" line is
  replaced by a provenance line. The GitLab section is unchanged.
- **Pin:** `nixarchy-ghtui` goes to `4f51f7f9114bc959976aa227ea8e6cf4ea91d68d`
  through the documented bump procedure. This is the first pin at which
  `menu.managed` is honoured.
- **Privacy:** the OCR allow-list is the 14 public repositories matching
  `nixarchy`, and the composites are also checked by eye.

## Steps

1. Scratchpad `compose.sh`: build the backdrop (`00-desktop.jpg` → 1400×875
   crop) and the shadow layer. Overlay the card on the MP4 frames with
   ffmpeg (`crop` → `scale` → `overlay` centred), then encode at 4 fps,
   900×563, `palettegen=max_colors=96:stats_mode=diff`, bayer dither →
   verify with `magick identify` (900×563) and `stat` (under 1 MB). If it's
   over 1 MB, speed the take up (`setpts`), and never drop below 4 fps or
   900 px.
   **Deviation, recorded at implementation:** at 900/1920 (656 px) the
   card's caption text was too small for `verify-frames.sh` to OCR
   `install` or `running`, although both were on screen. The site's own
   panel GIFs give their panels about 70–80% of the frame (Podman about
   79%, packages about 72%), so the card is placed at its native 900×680
   (64%), centred at (250,97), and nothing is rescaled. The looping
   backdrop has to be read at `-framerate 4`; at ffmpeg's default of 25 the
   output ran at 25 fps. Frames the H.264 source's noise made
   near-identical are merged with `mpdecimate` (`-fps_mode vfr`), which
   turns holds into longer frames. Result: 187 frames, 46.75 s, 1,020,375
   bytes, and no speed-up was needed.
2. The same script composes `s1-list` and `s2-steps` at 1280×800 as WebP →
   verify 1280×800 with `magick identify`, and check both by eye.
3. Gates:
   - `tests/demo/verify-frames.sh docs/img/features/github-actions.gif
     --max-bytes 1048576 --expect 'olafkfreund/nixarchy' --expect
     'install|build' --expect 'running|in_progress' --dump $SCRATCH/vf` must
     pass.
   - Tesseract on 2 fps GIF frames and on both stills, every `owner/name`
     compared against `allow.txt`, must find no repository outside it.
   - Check the dumped frames by eye.
4. `docs/manual/plugins.md`: add the GIF and the two stills to the GitHub
   Actions section, with alt text, and replace the "Not shown moving" line
   with: *Recorded on an authenticated desktop, in Gruvbox, showing public
   repositories only.* → verify with `grep` that the three images are
   referenced and the old line is gone from that section.
5. `flake.nix`: change the rev to `4f51f7f…`, then `nix flake lock` → verify
   `git diff flake.lock` touches only the `nixarchy-ghtui` node.
6. Pin procedure checks: the manifest id is `olafkfreund.github-actions`
   (`nix eval` or `cat` the input's `manifest.json`), and the input's
   `menu.py` contains the `menu.managed` check → verify with `grep`.
7. `nix build .#checks.x86_64-linux.options .#checks.x86_64-linux.menu-verbs
   .#checks.x86_64-linux.plugin` → all three green.
8. Commit in two parts: `docs: show the GitHub Actions panel moving (#889)`
   (images and page), and `chore(flake): bump nixarchy-ghtui to 4f51f7f
   (#889)`. Push, and open a PR linking intent, spec and plan → verify the
   image URLs on the branch return 200.
9. The PR waits for your review; merging it is your call, as for #21. After
   merge, check that the Pages site shows the images at
   `/manual/plugins#github-actions`.

## Tests

```sh
tests/demo/verify-frames.sh docs/img/features/github-actions.gif --max-bytes 1048576 \
  --expect 'olafkfreund/nixarchy' --expect 'install|build' --expect 'running|in_progress'
nix build .#checks.x86_64-linux.options .#checks.x86_64-linux.menu-verbs .#checks.x86_64-linux.plugin
git diff --stat origin/main -- flake.lock   # one input
```

Plus the OCR allow-list check printing nothing outside the list.

## Rollback

Revert the pin commit to return to `dfba799`, or the docs commit to remove
the images. The two are independent. Before merge, close the PR.
