---
status: approved
issue: 1826
spec: spec/2026-11-17-1826-cards-checkmate.md
coders:
  1: codex   # two new files copied from a close sibling; small and mechanical
  2: codex   # one-line additions across eight files, each located by grep of "monologue"
reviewers:
  - codex    # independent read of the diff against this plan
  - agy      # second model; skipped while the second-opinion skill says agy is out of use
---

# Plan: package Omarchy's Cards and Checkmate

Approved spec decisions: model both on `pkgs/apps/monologue.nix`
(fetchFromGitHub at a tag, cmake, `qt6.wrapQtAppsHook`, upstream `install()`
rules, no custom installPhase, `updateScript` as monologue's); Cards `v0.1.0`
hash `sha256-tOwGozKCQDBtB5Fm+BrYTIj2gPWniaPH5h898/Q0fsY=`; Checkmate `v0.1.2`
hash `sha256-/araTInVctB1kdZ70qnGyf8NQ7IaTnLvHAKRFhTGADY=`; both add
`qt6.qtsvg`; Checkmate adds `qt6.qtquick3d` and `qt6.qtbase` (Concurrent) as buildInputs, `xvfb-run` to nativeBuildInputs (its CMake requires
it), `postUnpack` renaming `source` to `checkmate-${version}` so `--version`
is not `dev`, and `mesa`-backed software GL for tests; `doCheck = true` where
the sandbox allows (upstream's own setup: `xvfb-run`, `QT_QUICK_BACKEND=rhi`,
`QSG_RHI_BACKEND=opengl`, `LIBGL_ALWAYS_SOFTWARE=1`), else false with a comment. No ledger rows, default on via
`preinstall = true` in `data/apps.nix`. Mode A untouched.

## Steps

1. `pkgs/apps/cards.nix`, `pkgs/apps/checkmate.nix`: new, per the decisions above
   → verify by `nix build .#cards .#checkmate` after step 2 (lead).
   Traps: `git add` new files before any flake build; run `nix fmt` and read
   `git diff --stat`; `runtimeInputs`/deps must be declared, not assumed.
2. Wiring, each next to the `monologue` / `signed` entry:
   `flake.nix` (overlay `cards = final.callPackage ...` and `checkmate`, and the
   package export list ~l.1620), `data/apps.nix` (rows `cards`, `checkmate`:
   label, category Utility, attr, `ours = true`, `preinstall = true`, `arch`),
   `pkgs/review.sh` pin list (`omacom/cards`, `omacom/checkmate`),
   `tests/review-pins.nix` list, `tests/options.nix` `omarchyAppPnames`,
   `tests/session.nix` on-PATH loop and its print line, the app-count wording in
   `modules/apps.nix` (omarchyApps description), `modules/nixos.nix` (preinstalls
   description) and `docs/manual/other-packages.md` (seven -> nine; list)
   → verify by `checks.options-*`, `review-pins`, `app-selection`.
   Traps: no `data/omarchy-packages.nix` rows (ledger fails on a row with no
   name); `.github/scripts/readme-counts.sh --fix` for derived counts and teach
   it new words if it refuses; a mkDefault is not wanted on lists.
3. Lead: build, launch smoke offscreen, break proof, all generated checks.

## Tests

- `nix build .#cards .#checkmate`; smoke: binaries alive under `timeout` with
  `QT_QPA_PLATFORM=offscreen`; `checkmate --version`. For Checkmate run under
  `xvfb-run` with the rhi/opengl/software-Mesa env above; the upstream test
  suite (which loads the real Main.qml and renders) is the rendered-board
  assertion and is run by hand if `doCheck` is off.
- Break proof: remove `preinstall = true` from one new row; `options-*` case
  `omarchyApps.on` must fail; restore.
- `nix fmt -- --ci`, statix, deadnix, `readme-counts.sh`, `review-pins`,
  `app-selection`, every `generated-checks.sh generated` target.

## Rollback

Revert the commits; no data or state is touched.

## Deviations (step 1, found building)

Both recipes run upstream's suites (`doCheck = true`). The sandbox needed three
test-only additions, none of which touch the installed files: `postPatch` swaps the
tests' fake-hyprctl `#!/bin/bash` shebang for the store bash; `preCheck` sets
`HOME`, a fonts conf and `QML2_IMPORT_PATH` (the suite loads Main.qml from the
build tree, before the Qt wrapper exists); Checkmate adds software Mesa
(`LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, EGL vendor file). The launch smoke
(offscreen, alive after 8 s) and `checkmate --version` also passed.
