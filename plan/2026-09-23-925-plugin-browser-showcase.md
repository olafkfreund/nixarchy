---
status: draft
issue: 925
spec: spec/2026-09-23-925-plugin-browser-showcase.md
---

# Plan: the Plugin Browser is shown on the plugins page, and links its own site

This plan is self-contained: it carries every approved spec decision.

**Decisions**

- **Provenance:** captured on razer in Tokyo Night (not the demo VM), with a
  caption saying so, as #889 did for GitHub Actions.
- **Media:** three stills plus one GIF.
  - `docs/img/plugins/plugin-browser-list.webp`,
    `plugin-browser-details.webp` (hyprmoncfg: review required / needs
    review) and `plugin-browser-pass.webp` (Display Watcher: passed /
    likely ok): 1280×800, WebP q82.
  - `docs/img/features/plugin-browser.gif`: 900×563, 4 fps, under 1 MB.
- **Frame, per `docs/AGENTS.md`:**
  - the panel box is 1018×786 at +451+98 on the 1920×1080 capture;
  - the backdrop is `docs/screenshots/00-desktop.jpg`, cropped to 1400×875
    (+100+0), with a baked shadow;
  - the panel is scaled to 924×713 (66%), masked with 9 px rounded corners,
    and placed at +238+88.
- **The GIF pipeline:**
  - the panel-open window, 1.5 s to 36.5 s;
  - `-framerate 4` before `-loop 1`, and `-t` on the looped inputs;
  - `mpdecimate`, then `tpad` cloning the last frame for 3 s;
  - 64 colours and `diff_mode=rectangle`. 96 colours came to 1,128 KB.
- **The page:** the repository line gains "· its own site"; the section
  ends with the GIF, then the three stills, each with alt text; then the
  caption "*Recorded on a real desktop in Tokyo Night, composed onto the
  default wallpaper. The plugins shown are public marketplace entries.*"
- **razer is restored exactly:** theme, wallpaper, and
  `nixarchy-theme.nix` (same sha256, git-clean).

## Steps

Steps 1–4 were carried out before this plan was written (the owner chose
recapture, "option 1", on 2026-09-23). Their evidence is recorded here and
re-checked in step 5.

1. **Capture on razer** (owner-granted, recorded, announced on the bus).
   *Done:*
   - the start state was Osaka Jade / Glowing City, with `nixarchy-theme.nix`
     sha256 `7b21f51f…`, clean;
   - Tokyo Night and Winding Road were set;
   - the take and three stills were captured;
   - Osaka Jade / Glowing City were restored, and the theme file was
     `7b21f51f…` again, clean.
2. **Compose the stills.**
   *Done:* 60, 72 and 32 KB, each 1280×800.
3. **Compose the GIF.**
   *Done:* 920 KB, 900×563, 36 frames, 38 s.
4. **The page.**
   *Done in `f5e12ac`:* the link, the four figures and the caption.
5. **Re-verify on the branch** (this plan's first action once approved):
   - `verify-frames.sh docs/img/features/plugin-browser.gif --expect 'Plugin Browser' --expect hyprmoncfg --expect 'review required|Needs review' --expect 'passed|Likely ok'`
     reports "looks like a real recording";
   - `identify` gives 900×563 for the GIF and 1280×800 for each still, and
     `du` puts the GIF under 1024 KB;
   - every image path in the section exists (`ls` each `../img/…`
     reference).
6. **Mark #926 ready.** Its CI goes green; the install check runs only
   now, not while it's a draft.
7. **Merge** by nixarchy's rules.
   → verify: #925 closes, and the page on the site shows the GIF and stills.

## Tests

| Command | Expected |
|---------|----------|
| `verify-frames.sh` with the four `--expect`s | "looks like a real recording" |
| `magick identify` on the four files | 900×563 GIF; 1280×800 stills |
| `du -k docs/img/features/plugin-browser.gif` | < 1024 |
| every `](../img/…)` path in the section | exists |
| PR CI | green |
| after the merge: `curl -sI …/nixarchy/img/features/plugin-browser.gif` | 200 |

## Rollback

- Revert the PR. It only adds four image files and changes one section of
  one page.
- razer needs nothing: its theme and theme file were restored during
  capture.
