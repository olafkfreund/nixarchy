---
status: draft
issue: 1081
spec: spec/2026-09-30-1081-retroarch-stable-paths.md
---

# Plan: Keep RetroArch resources at stable profile paths

## Approved decisions

The Omarchy RetroArch installer currently saves generation-specific Nix store
paths in `~/.config/retroarch/retroarch.cfg` and `config/global.slangp`. Once
that generation is garbage-collected, its cores, core info, shaders, and
joypad profiles disappear from the saved configuration. The fix saves paths
through `/run/current-system/sw`, which follows the active system generation.

When `programs.nixarchy.apps.retroarch.enable` is on, add
`libretro-core-info`, `libretro-shaders-slang`, and
`retroarch-joypad-autoconfig` to `environment.systemPackages` beside the
selected RetroArch package. Add `/share/retroarch/cores` and
`/share/libretro` to `environment.pathsToLink` under the same condition. NixOS
already links `/lib`. This keeps the paths tied to the selected app, including
a user override of its core set; disabling the app removes them.

The saved values must be exactly:

| Key or file | Value |
| --- | --- |
| `libretro_directory` | `/run/current-system/sw/lib/retroarch/cores` |
| `libretro_info_path` | `/run/current-system/sw/share/retroarch/cores` |
| `video_shader_dir` | `/run/current-system/sw/share/libretro/shaders/shaders_slang` |
| `joypad_autoconfig_dir` | `/run/current-system/sw/share/libretro/autoconfig` |
| `config/global.slangp` reference | `/run/current-system/sw/share/libretro/shaders/shaders_slang/crt/crt-royale.slangp` |

The profile layout is verified: the selected `retroarch-with-cores` package
has `/lib/retroarch/cores`; the three resource outputs have their respective
share paths; and a `pkgs.buildEnv` of those four packages, using those
`pathsToLink`, built with all five targets present. The NixOS `system-path.nix`
default includes `/lib` but not the two share paths.

Keep `omarchy-games-retro-install` and
`pkgs/omarchy/nix-bin/omarchy-retroarch-cores`'s immediate store-path lookup,
the existing user-owned overlay and database locations, and the user's
RetroArch core selection. Do not add an activation-time rewrite. Existing
users recover by rerunning `omarchy-install-gaming-retroarch` after rebuilding:
its `set_cfg` replaces an existing `^key = ` line with `sed -i` and appends
only a missing key, while `>` replaces the `global.slangp` preset. With all
51 arguments from the packaged installer and a present `retroarch` command,
`omarchy-pkg-add` exited 0, so a rerun reaches these writes. The installer
continues to rewrite the settings it already owns, including the global
shader preset.

The generated release notes print commit subjects. The implementation commit
subject must contain the actionable instruction to rerun Install > Gaming >
RetroArch after updating; the manual must carry the same instruction. The
paths exist only while RetroArch is selected. A system profile may have
collisions because `buildEnv` ignores them, so the check must prove the named
paths and representative files actually resolve.

## Steps

1. `modules/apps.nix:116-121,1199-1205,3907-3908`: add the three resource
   packages and two `pathsToLink` entries conditional on
   `cfg.apps.retroarch.enable`; keep the existing selected package in
   `appPackages` → verify by evaluating the enabled and disabled module states
   and by the profile path assertions in step 3.
   Traps: plain list assignments merge; do not use `mkDefault` on lists. Do
   not add the packages when the app is off or replace a user's overridden
   RetroArch package.
2. `pkgs/omarchy/default.nix:623-626,700-722`: patch only
   `omarchy-install-gaming-retroarch` to write the five values above; keep
   `omarchy-games-retro-install`'s immediate core lookup and user-owned
   overlay/database paths → verify by building `packages.x86_64-linux.omarchy`
   and checking its installed script.
   Traps: preserve `--replace-fail`; the install phase has an argument-length
   budget, so avoid adding a long explanation there. Run `nix fmt` after this
   `.nix` edit and inspect `git diff --stat` for formatter noise.
3. `tests/retroarch-paths.nix` and `flake.nix:1750-1900,2414-2423`: add one
   `runCommand` check of the built installer and a `buildEnv` containing the
   selected RetroArch package plus three resources. Assert exact stable values
   for the four keys and preset, no store path in those writes, and existence
   of core `.so`, core `.info`, shader preset, and joypad profile through the
   declared profile paths. Run the installer with a fixture home containing
   stale keys and preset, stub its package and launcher commands, and assert
   the keys are replaced once and the preset is overwritten → verify by
   `nix build .#checks.x86_64-linux.retroarch-paths --print-build-logs`.
   Traps: stage the new test before evaluating the flake; use bash in the
   derivation, do not hide a failing command in a pipeline, and ensure each
   assertion can fail on the old behavior. Add the check to the existing
   flake check mechanism; CI's generated-checks step picks up new checks
   without a workflow edit. No local VM check.
4. `tests/retroarch-paths.nix`, `pkgs/omarchy/default.nix:623-626`: prove the
   new check fails. First copy the fixed file aside **inside this worktree**
   (`cp pkgs/omarchy/default.nix .retroarch-default.nix.good`); reintroduce
   the old installer core substitution, confirm the break landed with
   `git diff`, run the named check, and capture its specific failing output.
   Restore with `cp .retroarch-default.nix.good pkgs/omarchy/default.nix` and
   remove the copy; **never use `git checkout` for this restore**. Run the
   same check again and require green → verify by the red and green logs and
   `git diff` showing only the intended fix.
   Traps: the flake sees staged/tracked changes; a no-op break or a stale
   evaluation is not evidence. Never let a temporary copy enter a commit.
5. `docs/manual/gaming.md:81-89`: add one recovery line telling affected
   users to update and rerun Install > Gaming > RetroArch (or
   `omarchy-install-gaming-retroarch`) to replace stale keys and preset →
   verify by reviewing the rendered sentence and confirming the implementation
   commit subject carries the same release-note instruction.
   Traps: do not promise automatic repair; do not add a new manual page or
   navigation entry.

## Tests

- Before any Nix build longer than seconds, run
  `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`.
  If it is positive and an install job is running, wait. Never run VM checks
  locally.
- Run the negative control in step 4 and keep its failing output for the PR.
  Then require the same `retroarch-paths` check to pass on the restored fix.
- Build `.#packages.x86_64-linux.omarchy` and the new check. Evaluate the
  module with RetroArch on and off; the three resources and two profile links
  should appear only in the on state. Check that a user's overridden RetroArch
  package is still the selected one.
- After every `.nix` edit, run `nix fmt` and read `git diff --stat`. Require
  `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and
  `nix run nixpkgs#deadnix -- --fail .` to pass. Run `git diff --check`.
- Fill `.github/PULL_REQUEST_TEMPLATE.md`, link intent, spec, and plan,
  paste the red check output, show the green result, and include `Closes #1081`.
  Do not change workflows, labels, or repository settings; do not merge.

## Rollback

Revert the implementation commit and rebuild to restore the old package and
profile behavior. Previously saved configs are user-owned and are not rewritten
by either deployment or rollback. A user who reran the fixed installer and
then rolled back can rerun the rolled-back installer to restore its prior
settings, or edit the five resource references in RetroArch's config files.
