---
status: draft
issue: 839
intent: intent/2026-09-21-839-devenv-bound-showcase.md
---

# Spec: show bound devenv environments on the site

## Design

Two new media files and three short text changes. There is no new page, so
the three lists that must agree (`_config.yml` nav, `llms.txt` Manual,
`manual/index.md`) keep their entries. `llms.txt` changes only the wording
of an existing line.

### Media: `docs/img/plugins/`

Both files come from the captures of 2026-09-21 (razer, Tokyo Night, the
Winding Road wallpaper, `demo-*` only), kept in `.captures-839/` until now:

| File | What | Format |
| --- | --- | --- |
| `devenv-bound.gif` | The whole flow: the list with `demo-bound` reading `from path:…/demo-shared`, `x` offering revoke only, `enter` → a shell where `ls -A` shows no `devenv.nix` and `hello` prints `hello from demo-shared`, then revoking it from the menu and the row leaving | 900x563, 4 fps, 96 colours, bayer dither, 127 frames, 908 KB |
| `devenv-bound.jpg` | The menu listing the demo projects, `demo-bound` first with its source and no edit button | 1280x800, JPEG q88, 91 KB |

The GIF follows `tests/demo/encode-gif.sh`'s recipe (4 fps, 900 px, lanczos,
a palette per GIF with `stats_mode=diff`) plus the `docs/AGENTS.md` palette
cap of 96 colours. The one departure is `bayer_scale=5`, which brought it
from 1.17 MB to 908 KB, under the 1 MB rule. The 16:10 region was cropped
from x=0, not centred: the terminal's proof lines start at its left edge.

The files are named after the plugin and the thing shown, like
`microvm-panel.jpg` and `pkg-search.jpg`.

### `docs/manual/plugins.md` — "Dev environments"

- **"What it does."** gains one sentence after "…the ones you allowed
  first.": *"Directories bound to a configuration elsewhere with `devenv
  --from` are listed too, reading **from &lt;source&gt;**; they have nothing
  of their own to edit or delete, so removal offers only revoke."*
- **The image** `../img/features/devenv.gif` (`nixarchy dev init` in a
  terminal) is replaced by `../img/plugins/devenv-bound.gif` (decision 1).
  Its alt text describes the recording.
- **The still** `../img/plugins/devenv-bound.jpg` goes below it, with alt
  text, as the other plugin sections show theirs.

### `docs/manual/per-project-environments.md` — "The panel"

"It lists every `devenv.nix` under your project roots … come first." gains
a sentence: *"A directory bound with `devenv --from <source> allow` is
listed too, with its source; see [the plugin's
manual](https://olafkfreund.github.io/nixarchy-devenv/usage#bound-environments)."*
The page keeps its own `devenv.gif`: it shows `nixarchy dev init`, which is
what that page teaches.

### `docs/llms.txt`

The Per-Project Environments line becomes *"…nixarchy dev init, the Dev
environments panel (Super+Alt+E), which also lists directories bound with
`devenv --from`, and devenv — …"*. The front page (`docs/index.md`) does not
describe the devenv panel's contents, so it does not change. That satisfies
"status claims age badly".

### Order

This lands after #849. Until nixarchy pins nixarchy-devenv at `72c0a47` or
later, the site would describe behaviour the shipped plugin lacks. The PR
says so, and is not merged before #849.

## Alternatives rejected

- **Keeping `devenv.gif` beside the new one in `plugins.md`.** Rejected by
  decision 1: the old recording shows a command, not the panel.
- **Compositing a cut-out panel onto `00-desktop.jpg`**, as `docs/AGENTS.md`
  describes for panel stills. These captures are already whole-desktop
  pictures of the default theme and wallpaper, taken live, which is what the
  compositing exists to imitate.
- **Re-recording at `2304x1440`**, as the house style suggests. razer's panel
  is 1920x1080; a 1728x1080 crop is 16:10, and scaled to 900 px it matches the
  other GIFs.
- **A new manual page for bound environments.** Two sentences and a link
  carry it. A page would add three list entries to keep in agreement for
  nothing more.

## Risks

- **Stale claims** if the plugin's wording changes. The text says only what
  #4 shipped, and links the plugin's own manual for detail.
- **GIF weight:** 908 KB, just under the rule. A later re-encode must keep
  `bayer_scale=5`, or trim frames.
- **The link anchor** `usage#bound-environments` must exist on the plugin
  site. The heading "Bound environments" is in `docs/usage.md` as merged, and
  it is checked in verification.
- **Hosts:** none. Site only.

## Verification

- `nix build .#checks.x86_64-linux.<docs/site checks>`, or the repository's
  documented docs check (`build.yml`'s "Every manual page is in the sidebar"),
  still passes with no list changes.
- `identify` confirms 900x563 and 1280x800; `stat` confirms the GIF is under
  1 MB. A coalesced frame sheet of the GIF is inspected: only the plugin,
  demo objects and wallpaper.
- The Jekyll build (or the Pages preview) renders both images on
  `manual/plugins`, and the link resolves to the heading on the plugin site.
- The PR is merged only after #849.
