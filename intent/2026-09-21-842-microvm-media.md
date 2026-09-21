---
status: draft
issue: 842
author: olafkfreund
---

# Intent: the MicroVMs section shows the plugin as it works now

Closes #842.

## Problem

`docs/manual/plugins.md` §MicroVMs shows two pictures of the nixarchy.microvm
panel: `img/features/microvm.gif` (900×563, from #353) and
`img/plugins/microvm-panel.jpg` (1280×800). Both predate nixarchy#762 and
nixarchy-pkg#19, which shipped on 2026-09-19. So they can't show what the
section's own text now promises: a VM started in the background with its
build streaming into the panel, and a permanent VM written from the panel,
waiting for apply.

## Proposed outcome

- The GIF shows a disposable VM started from the bar popup with `s`, its
  build streaming into the panel and ending `exit 0 · done`.
- The still shows the full-screen menu with two running disposable VMs and a
  permanent VM *pending apply* in one list.
- The two alt texts (`plugins.md:129`, `:131`) describe exactly that.
  Nothing else on the page changes.

## Affected users and systems

- `docs/img/features/microvm.gif` and `docs/img/plugins/microvm-panel.jpg`,
  both replaced.
- Two lines of `docs/manual/plugins.md`.
- Readers of the manual. No code, no build inputs.

## Constraints

- **House style (`docs/AGENTS.md`).** Each picture is a whole desktop at
  16:10: the panel cut at its own border, given rounded corners and a soft
  shadow, and composed onto `docs/screenshots/00-desktop.jpg` where it really
  opens. The popup goes top-right under the bar, the menu centred. The GIF
  follows `tests/demo/encode-gif.sh`: 900 px, 4 fps, lanczos, 96 colours,
  under 1 MB. The still stays 1280×800.
- **Real captures only.** The sources are the verified run in
  olafkfreund/nixarchy-microvm#3 (PR olafkfreund/nixarchy-microvm#10). They
  are card crops from razer at 1920×1080 and show only the plugin, `demo-*`
  VMs and a test `p1`, with no SSH key.
- A coalesced frame sheet of the GIF, and the still, are looked at before
  committing.

## Open questions

1. The sources were recorded on razer's theme, Gruvbox, not Tokyo Night. A panel in
   another theme on the Tokyo Night backdrop could read as a different
   product, which is #789's failure again. Is that acceptable, or should the
   two captures be retaken on a Tokyo Night session first? That means one
   popup recording and one menu still.
