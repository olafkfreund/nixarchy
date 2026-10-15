---
status: approved
issue: 1284
author: olafkfreund
---

# Intent: WebP desktop backgrounds draw instead of rendering black

## Problem

A WebP desktop background renders black on nixarchy, with nothing on screen
to say why. The only trace is the shell's log:

    QQuickImage at @Ui/BackgroundMedia.qml: Error decoding:
    …/<file>.webp: Unsupported image format

nixpkgs' quickshell, which nixarchy runs as the Omarchy shell (overridden in
`flake.nix`, ~:941), carries no `qt6.qtimageformats`. That package is Qt's
decoder for WebP, TIFF and a few other formats.

**Stable:** no shipped theme has a WebP background. But Omarchy's own
`omarchy-theme-bg-next` and `omarchy-theme-set` accept `*.webp` explicitly,
so a user's theme, or an extra theme, with a WebP background goes black
today.

**Edge:** Omarchy `quattro`'s default theme switched to `0-liftoff.webp`. That
was the black desktop `coexist` and `plugin` showed on quattro
(`docs/internals/design.md`, "What is left"). The edge carry (`1d915088`,
#1278) fixed it with the same one-line change.

**No check could see it.** `checks.session`'s backgrounds are JPEGs, so
nothing here decodes a WebP. Under CLAUDE.md §2, a bug found by hand is not
fixed until something can see it.

## Proposed outcome

- A WebP desktop background draws on stable, as it does on edge.
- A check fails when the shell cannot decode WebP. It does so whatever the
  shipped themes happen to use, so it can't drift green the way the JPEG-only
  session did.
- `docs/internals/design.md`'s unexplained "black desktop on quattro" item
  is answered.

## Affected users and systems

- **Who:** every nixarchy machine (the shell package changes), and users of
  WebP backgrounds directly.
- **Code:**
  - `flake.nix` (the quickshell override);
  - a check, either `checks.session` or a cheaper one if it can decode in a
    sandbox;
  - `docs/internals/design.md`.
- **Edge:** its carry `1d915088` becomes redundant once this is on `main`.
  It falls away in edge's next merge of `main`.

## Constraints

- **The quickshell override keeps its existing branches.** These are the
  0.3.2 unlock patch and the 0.3.1 floor. The decoder is added to all of
  them, not just one.
- **Closure size.** `qtimageformats` adds a little to every machine. The
  spec measures it, and `checks.iso-budget` holds the ISO under its limit.
- **Cache.** quickshell is no longer a cache hit from cache.nixos.org, so
  every machine and CI builds it once. The spec weighs that, and the cache
  allowlist rule (CLAUDE.md §6) decides whether nixarchy.cachix.org carries
  it.
- **The check is proven red** without the decoder (CLAUDE.md §1).

## Open questions

1. **The check's layer.**
   - A cheap sandbox check: a headless QML app, run with the shell's own Qt
     environment, loads a WebP and asserts it decoded.
   - Or a `session` VM probe: set a WebP background and assert the screen
     is not black.

   The cheap one runs on every PR. The VM one proves the whole path. The
   spec picks, possibly both.
2. **Cache.** Do we push quickshell to nixarchy.cachix.org, or accept a
   one-time build on every machine? Resolve in the spec, with the size
   measured.
