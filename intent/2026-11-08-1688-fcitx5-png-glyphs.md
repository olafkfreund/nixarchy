---
status: draft
issue: 1688
author: olafkfreund
---

# Intent: the Fcitx candidate window has its arrows on NixOS 26.05 too

## Problem

`omarchy-theme-set-fcitx5` links the packaged default theme's glyphs into
`~/.local/share/fcitx5/themes/omarchy` with
`for glyph in "$PACKAGED_THEME"/*.svg`. `PACKAGED_THEME` is
`/run/current-system/sw/share/fcitx5/themes/default`, substituted in
`pkgs/omarchy/default.nix:883-885`. Omarchy's template names the images as
SVG (`default/themed/fcitx5-theme.conf.tpl:48,57,87,90`).

fcitx5 5.1.23 (nixos-unstable) ships `arrow.svg next.svg prev.svg radio.svg`.
fcitx5 5.1.19 (nixos-26.05) ships the same four as `.png`. On 26.05 the loop
links nothing, and the theme names four images that do not exist, so the
candidate window draws without page or menu arrows. The weekly
`stable-session` is red on it (`tests/session.nix:3413`, run 42466135557).

Two checks encode the unstable layout as a fixed `.svg` path:
`tests/session.nix:3413` and `tests/input-methods.nix:342`.

## Proposed outcome

- On both channels, every image the generated `theme.conf` names exists in
  the theme directory.
- The probes assert that property ("each `Image=` names a file that
  exists"), not a fixed extension, so they hold on both channels and fail on
  either if a glyph goes missing.
- The weekly `stable-session` is green again.

## Affected users and systems

- Everyone on a 26.05 (stable) nixarchy with input methods, which means
  anyone who picked Mozc, Hangul, Pinyin and so on.
- `omarchy-theme-set-fcitx5` (an upstream script, patched here by
  `substituteInPlace`), and the two probes.

## Constraints

- An upstream script: the smallest edit, by `substituteInPlace
  --replace-fail` beside the existing one, or a carried patch.
- Upstream (Arch) always has SVG, so this is a NixOS-channel difference.
  It is not an upstream bug, and nothing goes upstream.
- §1, read backwards: the probes change because they encoded the
  arrangement (`.svg`) rather than the property.
- §1: proven to fail on stable before the fix and pass after.

## Decisions (owner, 2026-11-08)

1. The script is fixed. It links the packaged glyphs whatever their extension, and rewrites an `Image=X.svg` to `X.png` in the copied `theme.conf` when only the PNG exists. The system's own fcitx5 files stay the source.

## Open questions (as drafted)

1. Fix in the script: link `*.svg` and `*.png`, and rewrite `Image=X.svg`
   to `X.png` in the copied `theme.conf` when only the PNG exists? Or fix
   the source: build the theme against unstable's fcitx5 SVGs everywhere?
   The first is the recommendation. It keeps the system's own fcitx5 files.
