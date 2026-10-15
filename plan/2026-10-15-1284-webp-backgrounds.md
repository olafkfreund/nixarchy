---
status: approved
issue: 1284
spec: spec/2026-10-15-1284-webp-backgrounds.md
---

# Plan: WebP desktop backgrounds draw instead of rendering black

## Approved decisions (from the spec; implement against these)

- **One outer `.overrideAttrs`** on the whole `quickshell = (if … then … else
  …)` expression in `flake.nix` (~:941), adding `final.qt6.qtimageformats`
  to `buildInputs`. The three branches stay unchanged. A one-line comment
  above it gives the reason and #1284.
- **New `checks.shell-image-formats`** (`runCommand`, `{ inputs, pkgs }`,
  registered in `uniformChecks`):
  1. Take quickshell out of
     `inputs.self.packages.${system}.omarchy.passthru.runtimeDeps` by
     `pname`.
  2. Read `QT_PLUGIN_PATH` from its `bin/quickshell` wrapper; refuse when
     none can be read.
  3. Make a small solid-colour WebP with `libwebp`'s `cwebp`.
  4. Run `qt6.qtdeclarative`'s `qml` with `QT_QPA_PLATFORM=offscreen` and
     that `QT_PLUGIN_PATH`.
  5. Assert the `Image` reaches `Image.Ready` with a non-zero size.
- **A `session` probe:**
  1. Set a solid, distinctively coloured WebP with `omarchy-theme-bg-set`.
  2. Compare the screen's average colour with it, the `tests/coexist.nix`
     ~:162-191 way (imagemagick `-resize 1x1`, delta threshold).
  3. Restore the original background.
- **`docs/internals/design.md`'s "What is left" item 1** gains the cause of
  the `quattro` black desktop.
- **No cache, allowlist or manual change.**

## Steps

1. **`flake.nix` ~:941.** Wrap the quickshell conditional in parentheses and
   apply the outer `.overrideAttrs`, exactly as the edge carry `1d915088`
   does: `git show 1d915088 -- flake.nix` on the `edge-candidate` branch. A
   one-line comment carries the why.

   **Verify:** build the omarchy package's quickshell (by `drvPath`, from
   `runtimeDeps`), then grep its `bin/quickshell` for a
   `qtimageformats…/lib/qt-6/plugins` entry, and `ls` that entry's
   `imageformats/` for `libqwebp.so`.

   **Traps:**
   - Run `nix fmt` and read `git diff --stat`; an editor hook may reformat
     (§5).
   - The package build tier: check load and any p620 build first (§6).

2. **`tests/shell-image-formats.nix` (new) and `flake.nix` `uniformChecks`.**
   - The QML: one file, written with `printf` (no heredoc in an indented
     string, §5). An `Item` with an `Image { source: …webp; onStatusChanged
     … }` that prints `ready <w>x<h>` or `error <errorString>`, then calls
     `Qt.quit()`.
   - A timer fallback of 10 s prints `timeout` and exits non-zero, so a hang
     cannot read as a pass.
   - The check asserts `ready` with `w > 0`.
   - Environment: a writable `HOME` and `XDG_RUNTIME_DIR` (mode 0700), set
     the way `tests/qml.nix` does.
   - The refusals each print a clear message:
     - no `QT_PLUGIN_PATH` in the wrapper;
     - no quickshell in `runtimeDeps`.

   **Verify:** `nix build .#checks.x86_64-linux.shell-image-formats`.

   **Red proof:** remove the outer override from `flake.nix` (copy aside
   first; restore from the copy, not `git checkout --`, §5). The check
   fails with the decode error, not with a refusal. Capture that output for
   the PR.

   **Traps:**
   - `qml` must come from the same Qt as quickshell: take
     `pkgs.qt6.qtdeclarative` from the same `pkgs`.
   - A check that cannot run reads as one that passed (§4); the refusals
     prevent that.
   - Run it under bash, one check at a time under
     `flock /mnt/data/vmtest/codex-build.lock`.

3. **`tests/session.nix`: the probe (lead).** Place it right after the
   existing owe block's "Back to the original still" restore. The theme's
   background is the still there, and later sections expect it.
   1. Generate a solid `#2E8B57` 1920x1080 WebP at build time
      (`pkgs.runCommand` with imagemagick or `cwebp`) and pass its store
      path into the test script.
   2. `omarchy-theme-bg-set <that path>` as the user.
   3. Poll screenshots, up to 12 × 5 s, averaging to 1x1 and comparing with
      the WebP's own average, with delta < 120 as in coexist.
   4. Restore the original background (`original_background`, already in
      scope there) and wait for it the same way.

   **Verify:** CI's `session` (or locally only when `gh run list` shows
   nothing in flight, §6).

   **Red proof:** the same flake revert makes the probe fail near-black.
   That's a VM run: do it locally when CI is idle, or say in the PR that
   it was not run.

4. **`docs/internals/design.md`, "What is left" item 1 (lead).** Replace
   "That cause was not chased down…" with the cause:
   - `quattro`'s default theme ships a WebP wallpaper;
   - nixpkgs' quickshell has no `qtimageformats`;
   - fixed by #1284;
   - found by the edge channel's first seeding (#1278).

   **Verify:** `checks.docs-lists`.

## Tests

| Command | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.shell-image-formats` | green; red with the override removed (decode error) |
| `nix build .#checks.x86_64-linux.session` | green, with the WebP probe; red with the override removed (VM, CI-idle only) |
| `nix build .#checks.x86_64-linux.docs-lists` | green |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Model split

There are four steps over four files. Steps 1–2 go to the `coder` agent;
steps 3–4 stay with the lead, since the VM probe and the internals text
both depend on what the edge seeding found. A fresh Opus agent reviews the
diff against this plan.

## Rollback

Revert the merge. WebP backgrounds go black again; nothing else changes.

## Deviations recorded during implementation

- **Step 2: reading the plugin path.** `bin/quickshell` is a compiled makeCWrapper. The check greps the `--prefix QT_PLUGIN_PATH` entries out of it and refuses when it finds none.
- **Step 2: the error branch.** `Image` has no `errorString`, so that branch prints the status, and Qt logs the decode error itself.
- **Step 2: environment.** `QT_FORCE_STDERR_LOGGING=1` is needed for `console.log` to reach the build log. `QML_IMPORT_PATH` and `FONTCONFIG_FILE` are set as `tests/bar-keyed-sync.nix` sets them.
- **Step 2: the red proof** removed `qt6.qtimageformats` from the outer override, leaving the override applied but empty, rather than removing the override. That is the same property: no decoder.
- **Step 3, after review.** Without the decoder the shell keeps the
  *previous* background, because its reveal waits for a decode that never
  comes; it shows black only at boot. The probe therefore uses yellow
  `#FFFF00`, more than 400 from every lumon still and 510 from black, not
  sea green, which was only 162 from the previous still. It also asserts
  the screen moved more than 120 from a screenshot taken before. The
  restore sleeps 3 s rather than polling. The review confirmed that a
  still-to-still switch writes nothing to `shell.json`, so the #847 block
  after it is unaffected. The VM red proof was not run locally; the PR says
  so.

