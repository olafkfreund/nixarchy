---
status: approved
issue: 842
intent: intent/2026-09-21-842-microvm-media.md
---

# Spec: the MicroVMs section shows the plugin as it works now

## Design

Both files are composed from olafkfreund/nixarchy-microvm's verified
captures, which are merged there with the corrected hero (#10, #11). They are
used as they are, in Gruvbox (the owner's decision in the intent), following
`docs/AGENTS.md`.

**Compose.** The card is cut at its own border: the border colour
`rgb(125,174,163)` is sampled from the captures, and an edge counts as a
border only where it runs for over half the row or 30% of the column, so
stray wallpaper pixels are ignored. The card gets 10 px rounded corners and a
soft shadow (offset 6 px, blur 14), and is placed on
`docs/screenshots/00-desktop.jpg`, cropped to its right-hand 16:10
(1400×875 → 1280×800, keeping the bar's right end as #797 did).

| File | Source | Placement | Result |
| --- | --- | --- | --- |
| `docs/img/plugins/microvm-panel.jpg` | `menu.png` (the full-screen menu, two running and `p1` *pending apply*) | centred, scale 1.0 | 1280×800, JPEG q85, 90 KB (was 104 KB) |
| `docs/img/features/microvm.gif` | the 1× `rec-start` take at 4 fps from where the log opens (the list with #4's false hint is excluded), every third build frame, then a 3 s hold on `exit 0 · done` | top-right under the bar, scale 1.44 | 900×563, 29 frames, 4 fps, 96 colours, 740 KB (was 313 KB; limit 1 MB) |

The GIF is encoded with `tests/demo/encode-gif.sh`'s filter plus
`palettegen=max_colors=96` (the 96-colour cap `docs/AGENTS.md` names) and
`paletteuse=diff_mode=rectangle`. Without the cap it came out at 2.7 MB. A
coalesced frame sheet of all 29 frames and the last frame at full size have
been looked at.

The files are ready in `~/.cache/nixarchy-842-media/`, together with
`compose.py`, which is scratch tooling and isn't committed.

**Text.** `docs/manual/plugins.md`:

- `:129` alt → "A MicroVM started from the bar popup, its build streaming
  into the panel until it runs in the background"
- `:131` alt → "The MicroVMs menu: two disposable VMs running and a permanent
  one pending apply, in one list"

## Alternatives rejected

- **Committing `compose.py`.** It's a one-off. The rules it follows are
  already in `docs/AGENTS.md`, and a second caller would be speculative.
- **Every frame at 4 fps.** 42–72 frames came out at 1.1–2.7 MB, over the
  1 MB rule. Scrolling log text is what costs, and palette or dither settings
  didn't bring it under.
- **Retaking on Tokyo Night.** The owner declined.

## Risks

- `00-desktop.jpg` has a loading cursor baked in at about (270, 213) of the
  1280×800 crop. It shows in the GIF, beside the popup, and in every other
  capture composed on this backdrop. It is left alone here, because it's the
  site's shared backdrop, and is worth its own issue.
- Gruvbox on the Tokyo Night backdrop, accepted by the owner.

## Verification

- `identify` of both files: 1280×800, and 900×563 with 29 frames.
- The GIF under 1,048,576 bytes.
- `build.yml` passes on the PR (the sidebar-list and link checks).
- The page renders on the deployed site, with both images loading.
