---
status: approved
issue: 1406
spec: spec/2026-10-21-1406-omarchy-app-skill.md
---

# Plan: the omarchy-app skill tells an agent on nixarchy how to build and run an app the NixOS way

## Decisions (approved spec)

- **Patch in place** with `pkgs/omarchy/1406-omarchy-app-nix.patch`,
  applied with `patch -d "$out/share/omarchy" -p1 --forward --fuzz=0`,
  as #1192 and #902 are, in the skills block of `pkgs/omarchy/default.nix`
  (~:1180-1260). Only these change, and upstream's other text stays:
  - `SKILL.md`:
    - the toolchain sentence (:32-34): `nix develop` instead of
      `omarchy-pkg-add`;
    - the Shape rows for `bin/install` and `pkgbuild/` (:43, :50):
      `flake.nix`, `package.nix`, `dist/`;
    - Loop step 5 (:146-149): `nix run`, then add the flake to the
      configuration and rebuild;
    - the "To ship" bullet (:175-181): tag a release, and others add the
      flake.
  - `templates.md`:
    - `## bin/install` becomes `## flake.nix` (a dev shell with Qt 6
      base, declarative, multimedia, svg, wayland and ffmpeg, plus
      `packages.default = callPackage ./package.nix`);
    - `## pkgbuild/PKGBUILD` becomes `## package.nix`
      (`stdenv.mkDerivation`, `qt6.qmake` and `qt6.wrapQtAppsHook`,
      installing `bin/<name>`, the `.desktop` file and the icon);
    - `pkgbuild/<name>.desktop` and `.svg` move to `dist/`.
- **Guard:** `build.yml`'s "agent skills are NixOS-aware" step (~:986)
  fails on `omarchy-pkg-add`, `makepkg` or `PKGBUILD` anywhere in any
  shipped skill `*.md`, prose included, naming `file:line`.
- **`checks.omarchy-app-template`:** builds the shipped template as
  `tally`.

## Repo traps

- `.patch` hunks need exact context. Generate the patch with
  `diff -u` against the real `share/omarchy` tree from
  `nix build .#omarchy`, never by hand.
- The Nix code inside the templates is markdown. The check extracts it,
  so keep the template fences consistently tagged.
- §5: `git add` new files; `nix fmt`; build `.#omarchy` only when the
  1-minute load is below 12; cheap checks under the flock.
- The install-phase budget has about 3 KB left. One `patch` line plus a
  `# Why:` pointer is about 150 bytes. Check `install-phase-budget`.

## Steps (coder, one at a time; the lead commits)

1. **The patch and its application.**
   - Copy the upstream skill out of a built `.#omarchy`.
   - Edit the copy as above, then `diff -u` it into
     `pkgs/omarchy/1406-omarchy-app-nix.patch` with
     `share/omarchy`-relative paths, so it applies with `-p1`.
   - Add the `patch` line to `default.nix`, with a pointer comment.
   - Verify: `.#omarchy` builds, and
     `grep -rnE 'omarchy-pkg-add|makepkg|PKGBUILD' result/share/omarchy/default/agents/skills/`
     is empty.
   - Red: the patch applied with one context line altered fails at
     `--fuzz=0`.
2. **`checks.omarchy-app-template`.**
   - A `runCommand`: extract the patched `templates.md`'s code blocks
     into a project named `tally` (all files under `src/`, `tests/`,
     `<name>.pro`, `package.nix`, `dist/`), substitute `<name>` with
     `tally`, `callPackage ./package.nix` through IFD-free means (build
     it inside the runCommand with the same inputs, or pass
     `callPackage` a source dir produced by a separate derivation), and
     assert `bin/tally`, `share/applications/tally.desktop` and the icon
     exist.
   - If extraction from markdown is fragile, fall back as the spec
     allows: keep the template files under
     `pkgs/omarchy/skills/omarchy-app/templates/`, splice them into
     `templates.md` at build time, and build them directly.
   - Register it in `flake.nix` after `omarchy-newest`.
   - Red: drop `wrapQtAppsHook`, or install the `.desktop` file to the
     wrong path, and the check fails. Green: it builds.
3. **The `build.yml` guard.**
   - Add the scan to the step.
   - Red: run the step's scan on rc1's unpatched skills tree
     (`/nix/store/…-omarchy-4.5.0-rc1/share/omarchy/default/agents/skills`).
     It names `omarchy-app/SKILL.md:33`, and others.
   - Green: the patched tree prints nothing.
4. **Docs.** Reword the `omarchy-app` rows in `docs/manual/ai.md` and the
   README (from #1403) to say it builds apps the Nix way. Run
   `readme-counts.sh --check`.

## Lead

- Full generated list, one at a time by drvPath, plus `.#omarchy`.
- The PR changes `build.yml`, a CI gate, so the owner merges, with a
  **squash** merge: this PR carries no other branch.
- Close #1406 on merge.

## Rollback

Revert the PR. The skill ships as upstream wrote it again, and
`build.yml` still lists it (#1405).

## Deviations during implementation

- **Step 1 also edits `SKILL.md`'s frontmatter** ("installed as an Arch
  package", trigger "PKGBUILD for my app"), which the guard would refuse, and
  the `.gitignore` template (makepkg output dirs become `/result`).
  `package.nix` builds into `build/` explicitly. `install-phase-budget`:
  120086 of 123000 bytes. Red: one altered context line → `Hunk #1 FAILED`
  at `--fuzz=0` (a first red attempt whose sed matched nothing was caught
  by diffing the two patches).
- **Step 2: the template check reads the Nix text from the patch's added
  lines** and evaluates it with `builtins.toFile` plus `callPackage` (no
  import-from-derivation), then `cmp`s it against the shipped `package.nix`
  so the two cannot drift. The template flake covers x86_64 and aarch64
  (4.5 runs on Snapdragon, N1x and Apple Silicon). Reds: without
  `wrapQtAppsHook`, nixpkgs refuses ("no wrapping behavior was specified");
  with the `.desktop` file at `share/apps/`, "No such file". Not covered:
  `bin/build`, `bin/test`, and the template `flake.nix` itself.
