---
status: approved
issue: 925
intent: intent/2026-09-23-925-plugin-browser-showcase.md
---

# Spec: the Plugin Browser is shown on the plugins page, and links its own site

## Decisions on the intent's open questions

The intent was approved with its two questions open. This spec takes one
answer each; approving the spec approves these.

1. **Captures from razer, with a caption saying so.** This is the same
   answer #889 accepted for GitHub Actions. It goes further in one respect:
   #889 composed a Gruvbox panel onto the Tokyo Night backdrop, while this
   panel is captured **in Tokyo Night**, so the picture is uniformly the
   default look. A demo-VM scene would need network access (the catalog,
   previews, the audit's clone) and bwrap in the VM; that is not worth
   building for one section.
2. **Three stills plus the GIF:** the list, a plugin that needs review, and
   one that passes. The two verdicts are the point of the panel, and one
   still cannot show both.

## What was found before designing

- `docs/AGENTS.md` asks for the whole 16:10 desktop: the panel cut at its
  border and composed centred on `docs/screenshots/00-desktop.jpg` (Tokyo
  Night, Winding Road), with rounded corners and a soft shadow, and taking
  64–80% of the frame. Stills are 1280×800; GIFs are 900×563 at 4 fps,
  under 1 MB, gated by `tests/demo/verify-frames.sh`.
- The plugin site's media (plugin repo #12) are Osaka Jade card crops, so
  they can't be reused as they are.
- On nixarchy, `omarchy theme set` also rewrites the flake's
  `nixarchy-theme.nix` (through the theme-set hook). A theme switched for a
  capture must restore that file byte for byte.

## Design

### Capture (razer, owner-granted, recorded, announced)

1. Record the starting state: `omarchy-theme-current` (Osaka Jade),
   `omarchy-theme-bg-current` (Glowing City), and the sha256 and git status
   of `/etc/nixos/nixarchy-theme.nix`.
2. `omarchy theme set "Tokyo Night"`, which brings the Winding Road
   wallpaper.
3. Open the panel with `nixarchy-plugin <id>`. The take is:
   1. type `monitor`;
   2. open hyprmoncfg (preview, then review required / needs review);
   3. scroll;
   4. Esc, then open Display Watcher (passed / likely ok).

   Stills are taken at the list, the review verdicts and the pass verdicts.
   The recording uses gpu-screen-recorder at 30 fps.
4. `omarchy theme set "Osaka Jade"`. Then check the theme, the wallpaper,
   and that the theme file's sha256 and git status match step 1.

### Compose (off the machine)

- The panel box is found by sampling its border colour along a middle row
  and column: 1018×786 at +451+98 on a 1920×1080 capture.
- The backdrop is `00-desktop.jpg`, cropped to 1400×875 (+100+0), with a
  blurred, offset shadow baked in.
- The panel is scaled to 924×713 (66% of the width), masked with 9 px
  rounded corners, and placed at +238+88.
- **Stills:** composed at 1400×875, resized to 1280×800, WebP q82:
  `docs/img/plugins/plugin-browser-{list,details,pass}.webp`.
- **GIF** (`docs/img/features/plugin-browser.gif`): the recording's
  panel-open window (1.5 s to 36.5 s) at 4 fps, overlaid on the backdrop
  (`-framerate 4` before `-loop 1`, and `-t` on the looped inputs), then:
  - `mpdecimate`;
  - `tpad` cloning the last ("passed") frame for 3 s;
  - 900×563, a 64-colour palette, and `diff_mode=rectangle`.

  The 96-colour cap alone came out over 1 MB here.

### The page (`docs/manual/plugins.md`, the Plugin Browser section)

- The repository line gains
  `· [its own site](https://olafkfreund.github.io/nixarchy-plugin-browser/)`.
- The section ends with the GIF, then the three stills, each with alt text
  saying what happens.
- Then the caption: *"Recorded on a real desktop in Tokyo Night, composed
  onto the default wallpaper. The plugins shown are public marketplace
  entries."*

## Alternatives rejected

- **Reuse the plugin site's Osaka Jade crops.** They break the frame rule
  and put a green panel on the purple backdrop.
- **Compose Osaka Jade panels onto the backdrop** (the #889 route). It
  works, but mixes two themes when a Tokyo Night capture costs one short,
  restored switch.
- **A demo-VM scene.** See decision 1.
- **96 colours as the rule states.** The result was 1,128 KB. The rule's
  aim is under 1 MB, and 64 colours reaches it with text that still passes
  OCR.

## Risks

- **Private data.** The backdrop is the repo's own, so nothing of razer's
  bar or wallpaper is in frame. Only public plugins appear, and there's no
  menu search, browser or clipboard.
- **razer left altered.** Mitigated by step 1's snapshot and step 4's
  checks.
- **The GIF looks too short at the end.** A VFR GIF's last frame gets one
  frame interval, which is why `tpad` holds it.

## Verification

- `verify-frames.sh docs/img/features/plugin-browser.gif --expect 'Plugin Browser' --expect hyprmoncfg --expect 'review required|Needs review' --expect 'passed|Likely ok'`
  reports "looks like a real recording".
- The GIF's frame size is 900×563 and its file size under 1 MB. Each still
  is 1280×800.
- razer after the capture: the theme is Osaka Jade, the wallpaper is Glowing
  City, and `nixarchy-theme.nix` has the same sha256 as before and is
  git-clean.
- The PR's CI is green, and the page renders on the site after the merge.
