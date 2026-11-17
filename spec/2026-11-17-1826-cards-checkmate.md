---
status: draft
issue: 1826
intent: intent/2026-11-17-1826-cards-checkmate.md
---

# Spec: package Omarchy's Cards and Checkmate

## Design

Two new files, `pkgs/apps/cards.nix` and `pkgs/apps/checkmate.nix`, built like
`pkgs/apps/monologue.nix`: `fetchFromGitHub` at a release tag, CMake,
`qt6.wrapQtAppsHook`, and the upstream `cmake --install` rules (binary,
`share/<app>.desktop`, hicolor scalable icon, licence). No custom
installPhase is needed: both CMakeLists carry `install()` rules.

- Cards: tag `v0.1.0` (two later commits only redraw the icon). Qt6 Core Gui
  Network Qml Quick QuickControls2 (`qtbase`, `qtdeclarative`).
- Checkmate: tag `v0.1.2`. Adds Quick3D and Concurrent (`qtquick3d`, in
  `qtbase`), and its CMake does `find_program(xvfb-run REQUIRED)`, so
  `xvfb-run` joins nativeBuildInputs. Its version comes from the source
  directory name `checkmate-<version>`; fetchFromGitHub unpacks to `source`, so
  a `postUnpack` renames it, otherwise `--version` reports `dev`.
- Both add `qt6.qtsvg` (upstream's window icons need Qt's SVG engine).
- `doCheck = true` where the sandbox allows it: Cards' tests run offscreen;
  Checkmate's need `xvfb-run` and software GL (`mesa`). If the sandbox cannot
  run them, `doCheck = false` with the reason in a comment, and the launch
  smoke below stands in.
- Both carry the `updateScript` writeShellApplication of monologue.

Wiring, one row per place `monologue` appears:
`flake.nix` (overlay `nixarchy-apps` and the exported package set),
`data/apps.nix` (`ours`, `preinstall = true`, `arch`), `pkgs/review.sh` pin
list, `tests/review-pins.nix` list, `tests/options.nix` `omarchyAppPnames`,
`tests/session.nix` on-PATH loop, the "seven apps" counts in
`modules/apps.nix`, `modules/nixos.nix` descriptions and
`docs/manual/other-packages.md`.

No `data/omarchy-packages.nix` rows: main's pin does not list the packages and
the ledger fails on a row with no name. Edge handles them when it moves.

## Alternatives rejected

- Pin Cards to HEAD: no release exists for it, and the tag is what upstream
  calls a release.
- Patch xvfb-run out of Checkmate's CMake: a patch carried at every bump;
  a build-time input costs one line.
- Not preinstalled (opt-in rows): Omarchy ships them, and #1572 set the policy.

## Risks

- Default-on adds two Qt closures to every default machine; qtquick3d is
  already part of qtbase's outputs, so the delta is small.
- Mode A: preinstall rows only apply under `programs.nixarchy.enable`.
- Count words in docs and README must follow (`readme-counts.sh`).

## Coexistence

Both install under `$out/bin` and `share`; no file names shared with other
packages (`cards`, `checkmate`). Fixture: none needed, no collision found in
the env; `omarchyApps` options case covers the default set.

## Verification

- `nix build .#cards .#checkmate` (package tier; the flake exports them individually).
- Launch smoke: each binary started under `QT_QPA_PLATFORM=offscreen` (Checkmate with
  `QT_QUICK_BACKEND=software`) under `timeout`, alive after a few seconds; plus
  `checkmate --version`, which alone never constructs QGuiApplication.
- `options-*` shards with cards/checkmate in `omarchyAppPnames`; break proof:
  drop `preinstall = true` from a row and watch `omarchyApps.on` fail.
- `review-pins`, `app-selection`, statix, deadnix, nix fmt, and every target
  `generated-checks.sh` prints.
