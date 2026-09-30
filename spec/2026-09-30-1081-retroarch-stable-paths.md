---
status: approved
issue: 1081
intent: intent/2026-09-30-1081-retroarch-stable-paths.md
---

# Spec: Stable RetroArch resource paths

## Design

When `programs.nixarchy.apps.retroarch.enable` is on, put
`libretro-core-info`, `libretro-shaders-slang`, and
`retroarch-joypad-autoconfig` in `environment.systemPackages` beside the
selected RetroArch package. Add `/share/retroarch/cores` and
`/share/libretro` to `environment.pathsToLink` in `modules/apps.nix` near the
existing app package list (`modules/apps.nix:116-121,1199-1205,3907-3908`).
The existing NixOS system profile already links `/lib`, so it needs no new
entry for cores. Keep this conditional to avoid adding these resources when
RetroArch is disabled. This also follows a user's overridden RetroArch package:
`data/apps.nix:236-250` permits the override and `modules/apps.nix:117-120`
places that selected package in the system profile.

Patch only the persistent writes in `omarchy-install-gaming-retroarch` at
`pkgs/omarchy/default.nix:623-626,700-722` to use:

| Saved resource | Stable path |
| --- | --- |
| Cores | `/run/current-system/sw/lib/retroarch/cores` |
| Core info | `/run/current-system/sw/share/retroarch/cores` |
| Slang shaders | `/run/current-system/sw/share/libretro/shaders/shaders_slang` |
| Joypad profiles | `/run/current-system/sw/share/libretro/autoconfig` |
| CRT Royale preset in `global.slangp` | `/run/current-system/sw/share/libretro/shaders/shaders_slang/crt/crt-royale.slangp` |

The paths follow the active system generation. The core directory is real in
the built `retroarch-with-cores` package selected by `flake.nix:777-793`;
nixpkgs' `mkLibretroCore.nix` installs cores under `/lib/retroarch/cores`.
The three other package outputs contain the listed directories. NixOS's
`system-path.nix` includes `/lib` in its default `pathsToLink`, but not either
share path. I built a `pkgs.buildEnv` with these four packages and
`pathsToLink = [ "/bin" "/lib" "/share/libretro"
"/share/retroarch/cores" ]`; all five paths above existed in its output.
The actual package content, rather than the package name alone, supports each
path choice.

Leave `omarchy-games-retro-install`'s runtime core lookup and
`pkgs/omarchy/nix-bin/omarchy-retroarch-cores:12-22` in place: their output is
used immediately and its store path is not saved in user config. Keep the
user-owned overlay and database paths already set at
`pkgs/omarchy/default.nix:707-716`.

Existing config is repaired **only when the user reruns**
`omarchy-install-gaming-retroarch` after rebuilding. No activation script
rewrites `retroarch.cfg`. In the packaged installer, `set_cfg` matches an
existing `^key = ` line and runs `sed -i` to replace it; it appends only when
the key is absent. The CRT preset is written with `>` to `global.slangp`, so
it too is replaced on a rerun. I exercised `omarchy-pkg-add` with all 51
arguments from the packaged installer and a present `retroarch` command; it
exited 0, allowing the rerun to reach these writes. Add an actionable line to
`docs/manual/gaming.md:81-89` and to the implementation commit subject, which
the generated release notes print: affected users should rerun the RetroArch
install after updating.

## Alternatives rejected

- Keep store paths in saved config and retain old generations: garbage
  collection remains a hidden dependency and the issue persists.
- Rewrite users' config automatically on activation: the owner chose an
  installer rerun, which preserves user control over existing files.
- Change `omarchy-retroarch-cores` to print a profile path: other callers use
  its resolved store path immediately, and changing it would not address core
  info, shaders, or joypad settings.
- Point at `/usr/share/libretro`: NixOS does not provide these Arch paths.

## Risks

- The stable paths exist only while the RetroArch app is enabled; disabling
  RetroArch removes the selected package and its resource links. That matches
  the app selection.
- NixOS's `buildEnv` ignores collisions in the system profile. A package
  supplying the same relative resource path could win; a check should assert
  the intended directories and representative files in a profile made from
  the selected packages.
- Existing files remain stale until the owner reruns the installer. The
  release note and manual must make this recovery step explicit.
- Rerunning the installer also rewrites the settings it already owns,
  including the global shader preset; this is existing installer behavior.

## Verification

- Add a cheap `runCommand` check for the patched installer: its persistent
  RetroArch resource settings and `global.slangp` reference must contain the
  stable paths, with no `/nix/store/` path. Check that the selected packages
  expose the referenced directories and representative files in a profile
  with the declared `pathsToLink`.
- Prove the new check fails with the old substitutions restored, capture the
  failing output for the PR, restore the fix, and show the check passes.
- Exercise an installer rerun against a fixture `retroarch.cfg` containing
  stale keys, and assert replacement rather than duplicate appended keys.
  Confirm `global.slangp` is overwritten with the stable preset reference.
- Run `nix fmt`, inspect `git diff --stat`, then require
  `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and
  `nix run nixpkgs#deadnix -- --fail .` to pass. Build the relevant package
  and cheap check when no install job is running in CI. No local VM checks.
