---
status: draft
issue: 925
author: olafkfreund
---

# Intent: the Plugin Browser is shown on the plugins page, and links its own site

## Problem

The Plugin Browser became a default plugin in #915 (#913), and it is what
Setup ▸ Plugins ▸ Add Plugin opens. Its section in `docs/manual/plugins.md`
describes it in words only, while its neighbours (Package manager, Podman,
GitHub Actions, MicroVMs) show the panel. A reader can't see the thing the
section is about before they meet it: a searchable marketplace, a plugin's
preview, and the two verdicts (security, and NixOS) that an audit gives
before anything is installed.

The plugin now has its own site,
https://olafkfreund.github.io/nixarchy-plugin-browser/ (built in the plugin
repo's #12). The section doesn't link it, although nixarchy-pkg's section
links its site the same way ("its own site").

## Proposed outcome

- The Plugin Browser section shows a feature GIF and a few stills, like its
  neighbours, and its repository line links "its own site".
- The page reads correctly on
  https://olafkfreund.github.io/nixarchy/manual/plugins.

## Affected users and systems

- `docs/manual/plugins.md`, plus new files in `docs/img/features/` and
  `docs/img/plugins/`.
- The GitHub Pages build for the site. No module, package or host changes.
- razer, only as the machine the panel is captured on (a recorded,
  owner-granted session; its theme is switched for the capture and
  restored).

## Constraints

- **`docs/AGENTS.md`'s picture rules:**
  - every image is a whole 16:10 desktop in the default Tokyo Night theme
    (Winding Road), with the panel cut at its border and composed centred
    on `docs/screenshots/00-desktop.jpg`, with rounded corners and a shadow;
  - stills are 1280×800;
  - GIFs are 900×563 at 4 fps, under 1 MB;
  - the panel takes 64–80% of the frame, so `tests/demo/verify-frames.sh`
    can read it.
- **Nothing private:**
  - only public marketplace plugins;
  - nothing from the capture machine's bar, notifications or wallpaper
    (the backdrop is the repo's own);
  - no menu search (its Files section), browser or clipboard.
- **The capture machine is put back exactly:** its theme and wallpaper,
  and the flake's `nixarchy-theme.nix`, which the theme-set hook rewrites.
- **Alt text says what happens**, and a caption says where the pictures come
  from, as the GitHub Actions section's does.

## Open questions

1. **Provenance** (the question #889 asked). Every other picture comes
   from the demo VM, gated by the recorder. These are captured on razer in
   Tokyo Night and composed onto the repo's backdrop, then checked with
   `verify-frames.sh` and by eye. That is acceptable with a caption saying
   so, as for GitHub Actions? Or should the panel wait for a demo-VM
   scene? (It needs the network for the catalog, and bwrap for the audit.)
2. **How many stills.** The proposal is three (the list, a plugin that
   needs review, a plugin that passes), plus the GIF. One still and the GIF
   would match Podman's page weight.
