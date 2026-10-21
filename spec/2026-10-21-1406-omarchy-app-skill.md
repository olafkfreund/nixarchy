---
status: draft
issue: 1406
intent: intent/2026-10-21-1406-omarchy-app-skill.md
---

# Spec: the omarchy-app skill tells an agent on nixarchy how to build and run an app the NixOS way

Approved in the intent:
1. **Patch in place**, keeping upstream's portable sections verbatim.
2. **A guard across all shipped skills.**

## Design

### 1. One patch file, applied with `--fuzz=0`

The Arch parts span several lines, and `--replace-fail` takes one line.
So the edit is `pkgs/omarchy/1406-omarchy-app-nix.patch`, applied the
way #1192 and #902 are:

```sh
patch -d "$out/share/omarchy" -p1 --forward --fuzz=0 < ${./1406-omarchy-app-nix.patch}
```

The command goes in the skills block of `pkgs/omarchy/default.nix`,
~:1180-1260, with a one-line `# Why:` pointer. `--fuzz=0` makes any
upstream rewording around a hunk fail the build. It never ships Arch text
again silently.

**What the patch changes in `SKILL.md`** (everything else stays upstream's):

| upstream (4.5.0-rc1) | becomes |
|---|---|
| :32-34 "Everything an app needs is part of Omarchy … If `qmake6` is missing, install the set with `omarchy-pkg-add base-devel qt6-base …`" | the same toolchain list, then: on nixarchy it comes from the project's `flake.nix` dev shell (`nix develop`), with Qt 6 base, declarative, multimedia, svg and wayland, and ffmpeg |
| Shape: `bin/install  makepkg -fsi, so the app lands in the launcher` | `flake.nix  the dev shell and the app as a package` |
| Shape: `pkgbuild/PKGBUILD  pkgbuild/<name>.desktop  pkgbuild/<name>.svg` | `package.nix  dist/<name>.desktop  dist/<name>.svg` |
| Loop step 5: "`bin/install` builds the package with `makepkg -fsi` … appears in the Omarchy app launcher" | `nix run` to try it as installed. To keep it, add the flake as an input and the package to `environment.systemPackages` (or `home.packages`), then rebuild. It then appears in the launcher (`Super + Space`). |
| "README and release": the bullet about `omacom/omarchy-pkgs`, `install/omarchy-base.packages` and the migration | to share it: tag a GitHub release, and others add the flake. omarchy-pkgs is upstream's own release path for Omarchy's apps, not a user's. |

**What the patch changes in `templates.md`:**
- `## bin/install` (`exec makepkg -fsi`) is replaced by `## flake.nix`:
  a `devShells.default` with the Qt 6 modules and ffmpeg, and
  `packages.default = callPackage ./package.nix`.
- `## pkgbuild/PKGBUILD` is replaced by `## package.nix`: a
  `stdenv.mkDerivation` using `qt6.wrapQtAppsHook` and `qmake`, which
  installs `bin/<name>`, `share/applications/<name>.desktop` and
  `share/icons/hicolor/scalable/apps/<name>.svg`.
- `pkgbuild/<name>.desktop` and `.svg` move to `dist/`, with the same
  content.

The templates are written once, here, and are proved by the check below.

### 2. The guard: no shipped skill names an Arch install tool

`build.yml`'s step "agent skills are NixOS-aware" (~:986-1019, after the
skill-set assertion) gains one scan. Any occurrence of
`omarchy-pkg-add`, `makepkg` or `PKGBUILD`, in prose or code, in any
`*.md` under `share/omarchy/default/agents/skills`, fails the step and
names `file:line`.

- **Prose too**, not only code blocks: `SKILL.md:33` names
  `omarchy-pkg-add` in prose, and an agent follows prose.
- **Measured:** no other shipped skill contains any of the three words
  today, so the rule is absolute rather than allowlisted.

### 3. The templates are real: a check builds them

`checks.omarchy-app-template` is a `runCommand` over the patched tree's
`templates.md`. It extracts `flake.nix`'s inputs-free `package.nix` and
the C++/QML sources into a scratch project, named `tally`, and builds
`package.nix` with `pkgs.callPackage`. It then asserts that `bin/tally`,
the `.desktop` file and the icon exist in the output.

This is what stops the replacement from being plausible-looking text:
a template that does not build is the Arch-instruction bug in another
form. If extracting from markdown proves fragile, the plan may keep the
template files under `pkgs/omarchy/skills/omarchy-app/` and splice them
into `templates.md` at build time. Either way, the check builds the
shipped text.

## Alternatives rejected

- **Replacing the whole skill:** 80% is portable and worth receiving
  from upstream (intent decision 1).
- **One `--replace-fail` per line:** the Arch blocks are multi-line, and
  `default.nix` forbids multi-line patterns (`nix fmt` reindents them).
- **Fenced-code-only scanning:** misses the prose at `SKILL.md:33`.
- **A guard in the install phase:** it has about 3 KB of budget left
  (#1398). `build.yml`'s step already scans the built tree.

## Risks

- **The patch fails on the next upstream reword.** Intended: the bump PR
  shows it, as it would any patch.
- **The guard runs on `main`'s PRs only**, because `build.yml` does not
  run on edge. Edge follows `main` nightly, and since #1405 `main` and
  edge share the 4.5 skills, so a new Arch-shaped skill is caught at the
  next `main` bump. `checks.omarchy-app-template` is a flake check, so
  edge runs it too.
- **The template build needs Qt** in the check's closure: minutes, not
  seconds. That is fine for a cheap-tier `runCommand` that CI runs.

## Verification (§1)

| piece | red | green |
|---|---|---|
| guard | the step on today's tree (unpatched skill): `omarchy-app/SKILL.md:33 … omarchy-pkg-add`, plus the `makepkg` and `PKGBUILD` lines | after the patch: no hits |
| patch | `--fuzz=0` against a tree with a reworded line: the build fails | applies to 4.5.0-rc1 |
| template | `package.nix` without `wrapQtAppsHook`, or a wrong install path: the check fails | builds `tally`, and its `.desktop` and icon exist |
