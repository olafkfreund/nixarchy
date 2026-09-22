---
status: approved
issue: 839
spec: spec/2026-09-21-839-devenv-bound-showcase.md
---

# Plan: show bound devenv environments on the site

Branch `docs/839-devenv-bound-showcase`. One commit per step, citing the
step, for example `docs(site): … (#839, step 1)`.

## Approved decisions (self-contained)

- **Media**, from the razer captures of 2026-09-21 (Tokyo Night, the Winding
  Road wallpaper, `demo-*` only, and razer restored afterwards), now
  untracked in `.captures-839/`:
  - `docs/img/plugins/devenv-bound.gif`: 900x563, 4 fps, 96 colours,
    `bayer_scale=5`, 127 frames, 908 KB, a 16:10 crop taken from x=0. It
    shows the list with `demo-bound` reading `from path:…/demo-shared`, `x`
    offering revoke only, `enter` → a shell where `ls -A` has no `devenv.nix`
    and `hello` prints `hello from demo-shared`, then revoking it from the
    menu and the row leaving;
  - `docs/img/plugins/devenv-bound.jpg`: 1280x800, 91 KB, the menu listing
    the demo projects with `demo-bound` first.
- **`docs/manual/plugins.md`, "Dev environments":**
  - one sentence after "…the ones you allowed first.": *Directories bound to
    a configuration elsewhere with `devenv --from` are listed too, reading
    **from &lt;source&gt;**; they have nothing of their own to edit or
    delete, so removal offers only revoke.*
  - `../img/features/devenv.gif` is **replaced** by
    `../img/plugins/devenv-bound.gif`, and the still goes below it.
- **`docs/manual/per-project-environments.md`, "The panel":** after "…come
  first.": *A directory bound with `devenv --from <source> allow` is listed
  too, with its source; see [the plugin's
  manual](https://olafkfreund.github.io/nixarchy-devenv/usage#bound-environments).*
  That page keeps `img/features/devenv.gif`.
- **`docs/llms.txt`:** the Per-Project Environments line's panel clause
  becomes "the Dev environments panel (Super+Alt+E), which also lists
  directories bound with `devenv --from`".
- **No new page**, so `_config.yml`, `llms.txt`'s Manual list and
  `manual/index.md` keep their entries. The front page does not change.
- **Order:** merged only after #849 bumps the nixarchy-devenv pin to
  `72c0a47` or later.

## Steps

1. **Media:**
   - `git mv` is not possible for untracked files, so move them:
     `mv .captures-839/devenv-bound.gif .captures-839/devenv-bound.jpg docs/img/plugins/`,
     then `rmdir .captures-839`;
   - re-inspect before committing: `identify` (900x563 GIF, 1280x800 JPEG),
     `stat` (the GIF under 1,048,576 bytes), and a coalesced frame sheet
     (`magick devenv-bound.gif -coalesce` → tile), looked at frame by frame:
     only the plugin, demo objects and wallpaper.

   → verify by those three checks, and `git status` showing only the two new
   files.

2. **`docs/manual/plugins.md`:** the sentence, the image swap
   (`![The Dev environments menu listing a directory bound with devenv --from, offering only revoke, entering its shell, then revoking it](../img/plugins/devenv-bound.gif)`),
   and the still
   (`![The Dev environments menu: demo projects, demo-bound first, reading from its source with no edit button](../img/plugins/devenv-bound.jpg)`).

   → verify by `grep -c 'features/devenv.gif' docs/manual/plugins.md` being
   0, and both new paths resolving (`ls docs/img/plugins/devenv-bound.*`).

3. **`docs/manual/per-project-environments.md`** (the sentence) and
   **`docs/llms.txt`** (the clause).

   → verify by running `build.yml`'s "Every manual page is in the sidebar"
   script locally (the `pages`/`nav`/`llms`/`index` `comm` checks) with no
   errors, and by `curl -sL https://olafkfreund.github.io/nixarchy-devenv/usage`
   containing `id="bound-environments"` (live since nixarchy-devenv#5).

4. **Site render:** build locally with the repository's Jekyll setup, if
   `docs/` has one runnable here (`nix shell nixpkgs#jekyll`, then
   `jekyll build -s docs -d <tmp>`). If not, rely on the Pages preview of the
   PR. Check `manual/plugins/index.html` references both images.

   → verify by the images present in the built HTML (or the preview).

5. **PR:**
   - link all three artifacts, and say `Closes #839`;
   - state that it **depends on #849**, and do not merge before #849;
   - include the step 1 inspection results.

## Tests

| Check | Expected |
| --- | --- |
| `identify` / `stat` | 900x563, 1280x800; the GIF < 1 MB |
| frame sheet | only the plugin, demo objects and wallpaper |
| sidebar/llms/index agreement (build.yml) | no errors |
| the plugin site's anchor | `id="bound-environments"` present |
| the rendered page | both images shown |

## Rollback

Revert the commits. The two images are new files, and the text edits are
one sentence each plus one image line. `img/features/devenv.gif` stays in
the repository (per-project-environments.md still uses it), so restoring its
reference in `plugins.md` is a one-line revert.
