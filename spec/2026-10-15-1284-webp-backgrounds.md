---
status: approved
issue: 1284
intent: intent/2026-10-15-1284-webp-backgrounds.md
---

# Spec: WebP desktop backgrounds draw instead of rendering black

## Design

### The fix: Qt's image-format plugins in the shell

`flake.nix` overrides quickshell (~:941) with three branches:

- 0.3.2 gets the unlock-signal patch;
- 0.3.1 and later are used as they come;
- anything older is pinned to 0.3.1.

The whole expression gains one outer override:

```nix
quickshell = (
  if … then … else …          # the three branches, unchanged
).overrideAttrs (old: {
  buildInputs = (old.buildInputs or [ ]) ++ [ final.qt6.qtimageformats ];
});
```

`wrapQtAppsHook` then puts `qtimageformats`' plugin directory on the shell
wrapper's `QT_PLUGIN_PATH`. That covers both `quickshell` and `qs`, which
are the same wrapper. Verified on the edge branch: the wrapper names
`…-qtimageformats-6.11.2/lib/qt-6/plugins`, which holds
`imageformats/libqwebp.so`. A comment above the override says why, in one
line plus a pointer to #1284.

This is the edge carry `1d915088`, applied to `main`. Edge's next merge of
`main` brings the same lines, and the carry either merges cleanly or drops
out as already present.

### Cost, measured

The shell's closure gains about 16 MiB of store paths:
`qtimageformats` (0.44 MiB), `libheif`, `libde265`, `jasper` and `libmng`,
plus the rebuilt quickshell itself.

There is **no new build cost**. The 0.3.2 branch already patches
quickshell, so it was never substituted from cache.nixos.org. Every machine
and CI already build it, and this changes only what they build.
`.github/scripts/cache-allowlist.sh` does not carry quickshell today, so
nothing about the cache changes. `checks.iso-budget` holds the ISO's size
in CI.

### The checks: one cheap, one end to end

1. **`checks.shell-image-formats` (new, `runCommand`, every PR).** It runs
   Qt's own `qml` runner from `qt6.qtdeclarative`, offscreen
   (`QT_QPA_PLATFORM=offscreen`), with **the shell wrapper's own
   `QT_PLUGIN_PATH`** read out of the built quickshell wrapper.
   - **Why the wrapper's path:** it is the decoder set the shell itself
     will see, not one the check assembles.
   - **What it loads:** a one-line QML `Image` of a small WebP generated at
     build time (`libwebp`'s `cwebp` from a PNG). It asserts
     `status == Image.Ready` and a non-zero size.
   - **It must read the path, not assume it.** If no `QT_PLUGIN_PATH` can
     be read out of the wrapper, it refuses rather than passes (§4: a check
     that cannot run must not read as one that passed).
   - **It tracks the shell automatically.** It takes quickshell from the
     omarchy package's own `runtimeDeps` (by `pname`), so it follows
     whatever the shell is.
2. **A `session` probe (VM, CI).** Set a WebP background with
   `omarchy-theme-bg-set` and compare the screen's average colour with the
   image's. This uses the same colour-delta comparison
   `tests/coexist.nix` (~:179) already uses, with a WebP made solid in one
   distinctive colour so the delta is meaningful. Then restore the
   original background, so later sections see what they expect. This is
   the CLAUDE.md §2 probe at the highest layer that can see the bug, the
   way the user met it.

### Docs

- `docs/internals/design.md`'s "What is left" item 1 says the recorded build
  against `quattro` brought `coexist` and `plugin` up to a black desktop,
  and that the cause "was not chased down". It gains the answer: a WebP
  default wallpaper, and no WebP decoder (#1284).
- **No manual change.** This makes a documented feature (WebP backgrounds,
  which Omarchy's own scripts accept) work. Nothing about it was
  documented as broken.

### Coexistence

The change is to nixarchy's own quickshell override, which only nixarchy's
shell uses. No NixOS option is set, so there is no fixture, for the same
reason as #1278 and #1283.

## Alternatives rejected

- **Adding `qt6.qtimageformats` to `environment.systemPackages`.**
  `QT_PLUGIN_PATH` comes from the wrapper, not from the system profile, so
  the shell would not see it. A profile-wide plugin path would also leak
  into every Qt app.
- **Converting WebP backgrounds to JPEG when a theme is applied.** That
  patches Omarchy's theme scripts to work around a missing decoder, and
  every `omarchy-theme-*` change upstream would have to be re-checked.
- **Only the cheap check.** It proves the decoder is reachable, not that a
  background draws. The colour probe is what would have caught the
  `quattro` black desktop.
- **Only the VM probe.** It runs only in `session`'s budget. The cheap
  check names the cause in seconds, on every PR.

## Risks

- **`qml` and quickshell must share a Qt.** The check runs Qt's `qml`
  runner, which must be built against the same Qt as quickshell, or the
  plugin will not load ("built with a different Qt"). Take `qtdeclarative`
  from the same package set the omarchy package uses, and the check proves
  this by working: with the decoder present it must go green, and without
  it, red.
- **Offscreen Qt in a sandbox.** It needs a writable `HOME` and
  `XDG_RUNTIME_DIR`, the same setup the existing `tests/qml.nix` uses.
- **The session probe's colour comparison on llvmpipe.** `coexist` already
  measures this way in the same VM.

## Verification

| Check | Proves | Fails when |
|---|---|---|
| `checks.shell-image-formats` | the shell's own Qt plugin path decodes a WebP | the override's `qtimageformats` is removed (red proof) |
| `checks.session` probe | a WebP background draws on a booted desktop | the same removal: the screen stays near-black (red proof, VM; when CI is idle, or CI's own run) |
| `checks.options`, `checks.reference-toplevel` | nothing else moved | — |
