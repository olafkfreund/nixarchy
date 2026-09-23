# The site and the manual

## Intent

`docs/` is the GitHub Pages site (classic Pages, built from `main`'s `/docs`
with Jekyll) and the manual it serves. `_config.yml` holds the sidebar,
`_layouts/` the two templates, `manual/` the pages, `img/` and `screenshots/`
the media.

Nothing here is load-bearing for a build, which is exactly why it drifts. Three
lists must agree or CI fails (`build.yml`, "Every manual page is in the
sidebar"): `_config.yml`'s `nav`, `llms.txt`'s Manual section, and the table in
`manual/index.md`. A new page goes in all three.

## The house style is a whole desktop at 16:10, shown big

**Big is part of the rule, and was learned by breaking it.** #820 first put five
whole-desktop stills into a two-up grid on the front page. Each cell came out
near 320px, and a 1885px desktop scaled into that turns a panel's rows into grey
mush -- two terminal shots were indistinguishable from each other. That is
arithmetic, not taste: a screenshot of an interface has a minimum legible
display width, and a whole desktop's is most of the column.

So screenshots **stack at full container width** rather than sharing a row, and
the container is wider than the prose measure (72rem against 46rem). If a
picture has to be small, it should not be a whole desktop -- but the answer that
actually worked was to stop making them small.

## The frame is a whole desktop at 16:10

Every image on this site is a capture of the desktop, not a cropped widget:
feature GIFs at 900x563, desktop stills at 760x475 or 1280x800, the
screenshot set at 1600x875. A panel photographed on its own — portrait, square,
or on somebody else's wallpaper — reads as a different product, and that is
what shipped in #789 before #797 corrected it.

So a new picture of a panel is **composed onto the default desktop**:

- the backdrop is `docs/screenshots/00-desktop.jpg` (Tokyo Night, the Winding
  Road wallpaper — `programs.nixarchy.defaultTheme`), cropped to 16:10;
- the panel is cut at its own border (sample the border colour along a middle
  row and column to find the edges; the detection tools match stray wallpaper
  pixels), given rounded corners and a soft shadow;
- it sits where it really opens: a bar popup top-right under the bar, a menu
  panel centred.

Recordings follow `tests/demo/encode-gif.sh`: 4 fps, 900 px wide, lanczos, a
palette per GIF. The recorder's rule is **under 1 MB**; capping the palette at
96 colours is what keeps a desktop gradient under it. Record at a 16:10 region
(`wl-screenrec -g "<x>,<y> 2304x1440"`) so nothing needs cropping afterwards.

## Recording a real desktop is a script now, not an afternoon

`tests/demo/screencast/` (#930). The rules above still hold — they are what it
automates. What changed is that a take is repeatable and the desktop it
borrowed is provably given back.

```
screencast-prep        snapshot, then hide third-party bar widgets
screencast-record OUT  capture + drive + restore, in one command
verify-beats           does the recording show what the shot list promised?
screencast-edit OUT    both cuts from one master
screencast-restore     put it back; screencast-recover for a take that died
```

Four things about it that were learned rather than designed:

- **Prep refuses; it does not tidy.** It will not close your windows or dismiss
  your notifications — it stops and names them. Neither is recoverable, and a
  harness that costs somebody unsaved work has cost more than it saved.
- **Restore goes through the shell's IPC**, never by writing `shell.json`, and
  re-reads the live state after a settle delay. A plugin whose kind is `bar`
  takes no placement: `omarchy plugin enable <id> right` leaves it disabled,
  which is how the first real run put every third-party plugin back except the
  machine's actual bar.
- **`OMARCHY_PATH` must be the tree the shell was LAUNCHED from.**
  `omarchy-shell` selects the instance with `qs ipc -p "$OMARCHY_PATH/shell"`,
  so a session that predates a rebuild and an SSH shell that inherits the new
  one never match — and the symptom is `omarchy-shell is not running` against a
  shell that plainly is. The driver derives it from the running process.
- **The video gate is not the GIF gate.** `verify-frames.sh`'s diversity half
  cannot fail at 60 fps, so the video path samples a window per beat at its
  OBSERVED time and OCRs each beat separately. It refuses a file carrying
  subtitles, because otherwise a caption satisfies the expectation it captions.

A video is **16:9**, which the whole-desktop-at-16:10 rule above does not
cover. That is a deliberate departure for a different medium rather than an
oversight: a hero video is not a still, and cropping a 1920x1080 capture to
16:10 would throw away picture to satisfy a rule about screenshots.

## What a recording may show

A capture of a real desktop shows whatever is on it.

- **Translucent windows show what is behind them.** A screenshot taken for
  #764 caught an email with a verification code through the terminal's own
  transparency. Hyprland's opacity rule wins over the terminal's own setting,
  so "make it opaque" is not a fix. Compose on a known backdrop instead, or
  work on an empty workspace.
- **Panels list real data.** herdr shows every running session and what each
  agent is doing; Podman's Images and Volumes tabs list the machine's own.
  Before recording, create `demo-*` containers, boxes and VMs, and keep the
  panels that cannot be faked (herdr) out of shot.
- **Put the desktop back.** Theme, wallpaper, Do Not Disturb, workspaces, and
  every demo object. Record the starting state first; `omarchy-theme-current`
  and `omarchy-theme-bg-current` print what to restore.

## ImageMagick 7 traps

- **`info:` mid-command is an INPUT.** `magick x.png -format '%w ' info: -trim
  -format '%w' info:` fails with *"no decode delegate for this image format
  `INFO'"*. One output per call: use `identify` for the first number.
- **A GIF's frames are deltas.** `magick a.gif[30] out.png` gives the changed
  rectangle, not the frame a viewer sees. `-coalesce` first.
- **`find` does not follow `result`.** The same trap as AGENTS.md §5, and the
  reason `readme-counts.sh` once counted zero skills.

## ffmpeg compositing traps

- **A looped still runs at 25 fps, and `overlay` takes its timing from it.**
  Composing a recording onto `-loop 1 -i backdrop.png` makes a 25 fps GIF,
  even with `fps=4` on the recording's input. For #889, 195 frames became
  about 1160, and the file size read like a palette problem. Put
  `-framerate 4` before `-loop 1`, then count the frames with
  `ffprobe -count_frames`.
- **A lossy source makes held frames differ.** H.264 noise re-encodes the
  whole panel in every frame, so speeding the take up made #889's GIF
  *bigger*. `mpdecimate` with `-fps_mode vfr` merges near-duplicate frames
  into longer ones, the way `shot()` holds a state.
- **Small panels fail the OCR gate honestly.** At 47% of a 900 px frame,
  caption text was on screen, but `verify-frames.sh` couldn't read it.
  Panels on this site take about 64–80% of the frame. Fix the size, not
  the `--expect`.

## Status claims age badly

`manual/plugins.md` says which panels are on by default and which are coming.
A PR that ships one moves it in that table, on the front page, and in
`llms.txt` — #804 found all three still saying "coming" for panels #803 had
already turned on. The plugin pages also carry the migration note for a
hand-installed plugin directory, which the declarative install refuses to
replace.
