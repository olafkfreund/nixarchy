---
status: draft
issue: 839
author: olafkfreund
---

# Intent: show bound devenv environments on the site

Closes #839.

## Problem

nixarchy-devenv now lists directories bound with `devenv --from`
(olafkfreund/nixarchy-devenv#4). A bound directory has a working environment
but no `devenv.nix` of its own; before this change it was invisible in the
Dev environments panel. On the plugin's own site it has a section, a recording
and two stills.

The nixarchy site says nothing about it. `docs/manual/plugins.md` ("Dev
environments") describes the panel as "every devenv project under your project
roots", which a bound directory is not, and its only picture is
`img/features/devenv.gif`: `nixarchy dev init` in a terminal, which predates the
panel. `docs/manual/per-project-environments.md` uses the same GIF and does not
mention `--from` either. The owner asked for the bound environment to be shown
on the nixarchy site as well as the plugin's.

## Proposed outcome

- The "Dev environments" section of `docs/manual/plugins.md` says that bound
  directories are listed, what their row shows (`from <source>`), and that
  removal offers only revoke, and it links the plugin site's section.
- It shows a real recording of the panel in the house style. The recording
  shows `demo-bound` listed with its source, removal offering revoke only, a
  shell whose `hello` answers from `demo-shared`, and revoking it from the
  menu, after which the row leaves the list.
- A still of the panel with the bound row, at the house still size.

## Affected users and systems

- Site readers only. There is no module, package or host change.
- `docs/img/plugins/` (a new GIF and still), and `docs/manual/plugins.md`.
  Perhaps also `docs/manual/per-project-environments.md` (a sentence and a
  link), and `docs/llms.txt`, if its Dev environments line should mention
  bound directories. No new manual page, so the three lists that must agree
  (`_config.yml`, `llms.txt`, `manual/index.md`) do not change.

## Constraints

- **Real captures only, in the house style** (`docs/AGENTS.md`):
  - a whole desktop at 16:10, in Tokyo Night with the Winding Road
    wallpaper;
  - `demo-*` objects only, on an empty workspace;
  - the desktop put back afterwards.

  These already exist. They were taken on razer on 2026-09-21 with
  nixarchy-devenv's `docs/capture.sh`, and razer was restored afterwards
  (theme, wallpaper, Do Not Disturb, workspace, `shell.json` byte-identical,
  and no leftover allow entries):
  - `devenv-bound.gif`: 900x563, 4 fps, 96 colours, 127 frames, 908 KB. It
    is cropped from x=0, because the proof lines start at the terminal's
    left edge.
  - `devenv-bound.jpg`: 1280x800.

  They are kept untracked in this worktree (`.captures-839/`) until the plan
  places them.
- **The recording must not show the owner's data.** Every frame was checked.
  The owner's shell start-up (splashboard's calendar and mail) runs between
  the two recorded segments and is not in the file.
- **The GIF stays under 1 MB.**
- **"Status claims age badly"**: if the panel description changes, it changes
  in the same places that carry it (`plugins.md`, the front page, and
  `llms.txt`), or not at all.
- It lands after olafkfreund/nixarchy-devenv#4 merges, so the site never
  describes a behaviour the pinned plugin lacks. The pin bump that brings #4
  to nixarchy is part of this task or a prerequisite of it: to be decided in
  the spec.

## Decisions

Answered by the owner on 2026-09-21:

1. **The new GIF replaces `img/features/devenv.gif` in the plugins section.**
   `per-project-environments.md` keeps its `nixarchy dev init` GIF, which
   shows the command that page is about.
2. **The pin bump is a separate task:** #849 bumps `nixarchy-devenv` from
   `e003f00` to `72c0a47` or later (the merge of nixarchy-devenv#4). It is a
   prerequisite: this change lands after it.
3. **Bound directories are mentioned in all three places:**
   `docs/manual/plugins.md`, `docs/manual/per-project-environments.md` and
   `docs/llms.txt`.

## Open questions

None.
