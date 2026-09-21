---
status: draft
issue: 842
spec: spec/2026-09-21-842-microvm-media.md
---

# Plan: the MicroVMs section shows the plugin as it works now

## Approved decisions (from the spec)

- Both files are composed from nixarchy-microvm's verified captures (its
  #10 and #11), used as they are, in Gruvbox. The owner doesn't mind the
  theme.
- Card cut at its border (`rgb(125,174,163)`), 10 px corners, a soft
  shadow, on `docs/screenshots/00-desktop.jpg`'s right-hand 16:10 crop at
  1280×800.
- `docs/img/plugins/microvm-panel.jpg`: the menu card centred, JPEG q85,
  90,554 bytes.
- `docs/img/features/microvm.gif`: the popup top-right under the bar, the
  build log from where it opens (no list, and so no false hint), every
  third build frame, then a 3 s hold on `exit 0 · done`. 900×563, 29
  frames, 4 fps, 96 colours, 740,378 bytes (limit 1 MB).
- The composed files are ready in `~/.cache/nixarchy-842-media/`.
  `compose.py` is not committed.
- Alt text only, at `plugins.md:129` and `:131`. Nothing else changes.
- The loading cursor baked into `00-desktop.jpg` is out of scope, and gets
  its own issue.

## Steps

1. Copy `microvm.gif` to `docs/img/features/microvm.gif` and `panel.jpg` to
   `docs/img/plugins/microvm-panel.jpg`. → Verify: `identify` gives
   900×563 with 29 frames, and 1280×800; the GIF is under 1,048,576 bytes;
   `git status` shows exactly two modified files.
2. `docs/manual/plugins.md:129` alt → "A MicroVM started from the bar
   popup, its build streaming into the panel until it runs in the
   background"; `:131` alt → "The MicroVMs menu: two disposable VMs running
   and a permanent one pending apply, in one list". → Verify with
   `git diff docs/manual/plugins.md` showing exactly two changed lines.
3. Open an issue for the loading cursor in `00-desktop.jpg`, with its crop
   coordinates and the pictures affected. There's no commit. → Verify that
   the issue URL exists.
4. Push `docs/842-microvm-media` and open a PR linking intent, spec and
   plan, with "Closes #842". → Verify that `build.yml` passes on the PR.
5. After merge, check that the deployed manual page loads both images
   (HTTP 200, and a byte size matching the files). → Verify with `curl`.

## Tests

`identify` and size checks (step 1) · `git diff` (step 2) · CI
`build.yml` · the deployed page (step 5).

## Rollback

Revert the PR. The two old files and the alt text return.
