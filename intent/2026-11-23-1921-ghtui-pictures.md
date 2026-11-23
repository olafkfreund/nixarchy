---
status: draft
issue: 1921
author: olafkfreund
---

# Intent: the GitHub Actions section shows the current panel

## Problem

`docs/manual/plugins.md#github-actions` shows three pictures copied from
nixarchy-ghtui#21 in 2026-09 (#889): `docs/img/features/github-actions.gif`
(1.06 MB) and the stills `docs/img/plugins/github-actions-{list,steps}.webp`.
They predate the theme-sized text and the pull-request view, so they no longer
match the panel nixarchy ships (ghtui v1.3.0, pinned by #1920).

olafkfreund/nixarchy-ghtui#25 (PR #68, merged as `21cdd23`) retook them on
razer at the theme text size:

- `github-actions.gif`: 680×514, 579 KB, filtered to `olafkfreund/nixarchy`,
  drilling into a running workflow down to the steps of its prepare job and
  back out.
- `github-actions-{list,steps}.webp`: 900×680 stills of the same views.
- New: `github-actions-prs.webp`, the pull-request view (`p`) with one pull
  request expanded to its four passing checks.

Every image was checked by OCR and by eye to show only public repositories.

## Proposed outcome

The section shows the new GIF, the list and steps stills, and the
pull-request still, with alt text that describes each, and one sentence
saying `p` switches to open pull requests. The page reads correctly on
https://olafkfreund.github.io/nixarchy/manual/plugins.

## Affected users and systems

- `docs/manual/plugins.md` and `docs/img/{features,plugins}/`: three files
  replaced, one added. GitHub Pages build.
- No module, package, pin or host change.

## Constraints

- Only public repositories and no personal desktop content in any image.
  Files are copied byte-for-byte from nixarchy-ghtui `21cdd23`, not re-cropped.
- Keep the site's conventions: the GIF in `docs/img/features/`, WebP stills in
  `docs/img/plugins/`, alt text describing what happens.
- Keep the provenance line ("Recorded on an authenticated desktop, in
  Gruvbox, showing public repositories only."); #889 approved razer as the
  source.

## Open questions

1. **Pull-request still.** Add it (recommended: it is the feature v1.3.0
   brought), or keep the section to the three existing pictures?
2. **Pin bump.** `21cdd23` changes only ghtui's README and images. Leave
   `nixarchy-ghtui` at `cdc49ac` (recommended: no package change), or bump it
   so the pin matches the source of the pictures?
