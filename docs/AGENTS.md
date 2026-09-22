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

## Status claims age badly

`manual/plugins.md` says which panels are on by default and which are coming.
A PR that ships one moves it in that table, on the front page, and in
`llms.txt` — #804 found all three still saying "coming" for panels #803 had
already turned on. The plugin pages also carry the migration note for a
hand-installed plugin directory, which the declarative install refuses to
replace.
