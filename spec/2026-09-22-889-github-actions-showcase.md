---
status: draft
issue: 889
intent: intent/2026-09-22-889-github-actions-showcase.md
---

# Spec: the GitHub Actions panel is shown on the plugins page

## What was found before designing

- **The site has a written house style** (`docs/AGENTS.md`): *"Every image on
  this site is a capture of the desktop, not a cropped widget"*. A panel is
  **composed onto the default desktop**: `docs/screenshots/00-desktop.jpg`
  (Tokyo Night, Winding Road) cropped to 16:10, with the panel cut at its
  border, given rounded corners and a soft shadow, and centred where a menu
  panel opens. Feature GIFs are 900×563 at 4 fps, under 1 MB, with at most 96
  colours. Stills are 760×475 or 1280×800. #797 corrected pictures that broke
  this.
- The nixarchy-ghtui#21 files are **card crops in Gruvbox** (razer's theme).
  Shipping them as they are breaks the house style, and composing them onto
  the Tokyo Night backdrop would show a Gruvbox panel on a Tokyo Night desktop,
  which *"reads as a different product"*.
- The site has a gate for GIFs: `tests/demo/verify-frames.sh`, which checks
  frame diversity and requires every `--expect` regex to match in OCR of the
  sampled frames.
- **The pin bump matters more than a docs refresh.** At `dfba799`, upstream's
  `menu.py register` doesn't check for the `menu.managed` marker that
  `modules/home.nix` adds, so the marker has no effect and the panel writes
  its own menu rows on top of the ones nixarchy declares. `4f51f7f` adds that
  check (#19), ships `LICENSE` in the package (which makes nixarchy's
  fallback copy a no-op), and fixes the offline error message (#21). The
  manifest id is unchanged (`olafkfreund.github-actions`).

## Design

### 1. Re-record on razer in the default theme

This keeps the approved provenance (razer, authenticated) and follows the
house style. The procedure is the one proven in nixarchy-ghtui#20:

- Record the starting state (`omarchy-theme-current`,
  `omarchy-theme-bg-current`, and do-not-disturb), switch to **Tokyo Night**,
  and silence notifications.
- Use the same storyboard: open on an existing `nixarchy` search, narrow it
  to `nixarchy-p` and back, drill `olafkfreund/nixarchy` → a running run → a
  job → its steps, back out, and close with Super+Alt+A (not Esc, which would
  clear the filter and list every repository).
- Record the card region with `wf-recorder`, trim to the frames where the
  card border is on screen, and cut at the card border.
- Put razer back afterwards: theme, wallpaper, do-not-disturb, and the test
  terminal.

If no `olafkfreund/nixarchy` run is in progress at recording time, the
steps view shows the most recent completed run instead. The GIF is still
valid, but its alt text says so.

### 2. Compose onto the default desktop

Use one small script in the scratchpad, not committed; it's a one-off.

- Backdrop: `00-desktop.jpg` cropped to 16:10 (1400×875, centred).
- The card is scaled by its true share of razer's screen (900/1920 of the
  width), given rounded corners at the theme's radius and a soft shadow, and
  centred.
- GIF: every frame is overlaid on the backdrop, then encoded as the house
  style says: 4 fps, 900×563, lanczos, one palette of ≤96 colours, under
  1 MB.
- Two WebP stills at 1280×800, the section's usual count: the running-first
  list, and a run expanded to a job's steps.

### 3. Publish on the plugins page

In `docs/manual/plugins.md#github-actions`:

- Add the GIF (`docs/img/features/github-actions.gif`) and the two stills
  (`docs/img/plugins/github-actions-list.webp`, `github-actions-steps.webp`),
  stacked at full width, each with alt text describing what happens.
- Replace *"Not shown moving …"* with one line on provenance: recorded on an
  authenticated desktop, showing public repositories only.

The GitLab section's identical line stays, since there's no GitLab recording.

### 4. Bump the pin (`docs/internals/flake.md`, "Bumping the pin")

1. The diff `dfba799...4f51f7f` has been read (summarised above).
2. Set `flake.nix` to `…/4f51f7f9114bc959976aa227ea8e6cf4ea91d68d`, then
   `nix flake lock`. The lock diff touches `nixarchy-ghtui` alone.
3. Confirm the manifest id is unchanged.
4. Confirm `menu.py` checks for `menu.managed`. It now does, for the first
   time.
5. Build `checks.options`, `checks.menu-verbs` and `checks.plugin`.

`docs/internals/flake.md` says "Measured at dfba799"; that remains a true
statement, so it's left alone.

## Alternatives rejected

- **Ship the #21 card crops as they are:** this breaks the written house
  style; #797 is the precedent for correcting exactly that.
- **Compose the Gruvbox crops onto the Tokyo Night backdrop:** a panel in
  one theme on a desktop in another reads as a different product.
- **A demo-VM scene with GitHub auth:** it needs a token inside the VM and a
  secrets path, which is out of scope. You accepted razer provenance.
- **Bump the pin in a separate PR:** you decided on this change, and the pin
  is what makes `menu.managed` work.

## Risks

- **razer:** switching the theme restarts the shell (seen in #20). The
  panel's cache resets and the recording waits for its scan. The desktop is
  restored afterwards, as the house style requires.
- **Privacy:** only public repositories appear. The same OCR allow-list gate
  as #20 applies (the 14 public repositories matching `nixarchy`), plus a
  check by eye. The composite shows only the card on the stock backdrop, so
  no desktop widgets can appear.
- **Legibility:** a card that is about 47% of a 900 px GIF is small. That is
  the same trade-off as the site's other panel GIFs. The 1280×800 stills
  carry the detail.
- **Pin:** once `menu.managed` works, the panel stops writing its own rows,
  so menu entries come only from `modules/apps.nix`. That's intended (#772),
  and `checks.menu-verbs` covers it.

## Verification

- `tests/demo/verify-frames.sh` on the GIF passes, with `--expect` for
  `olafkfreund/nixarchy`, `install|build` and `running|in_progress`.
- `magick identify` shows the GIF at 900×563 and under 1 MB, and the stills at
  1280×800.
- The OCR allow-list check finds no repository outside the list.
- `nix build .#checks.x86_64-linux.{options,menu-verbs,plugin}` is green, and
  the `flake.lock` diff is limited to `nixarchy-ghtui`.
- After merge, the page at
  https://olafkfreund.github.io/nixarchy/manual/plugins#github-actions shows
  the images, and `curl` returns 200 for each image URL.
