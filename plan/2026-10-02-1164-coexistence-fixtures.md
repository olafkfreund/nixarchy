---
status: draft
issue: 1164
spec: spec/2026-10-02-1164-coexistence-fixtures.md
---

# Plan: nixarchy is tested beside the user configurations it promises to coexist with

## Approved decisions (self-contained)

- **Five user fixtures.** Each is a plain NixOS module, with no
  `programs.nixarchy.*`, in `tests/coexistence/fixtures.nix`:
  - `graphics-own-mesa`: `hardware.graphics.extraPackages = [ pkgs.mesa ]`;
  - `graphics-32bit`: `enable32Bit = true; extraPackages32 = [ pkgs.driversi686Linux.mesa ]`;
  - `graphics-own-package`: `hardware.graphics.package = pkgs.mesa`;
  - `graphics-opencl`: `extraPackages = [ pkgs.mesa.opencl ]`;
  - `systempkg-own-ffmpeg`: `environment.systemPackages = [ pkgs.ffmpeg-full ]`.
    nixarchy adds `ffmpeg` at `modules/nixos.nix:1066` and in the Omarchy
    `runtimeDeps` (`pkgs/omarchy/default.nix:213`).
- **The fonts fixture is dropped,** by the owner's decision: no failing case
  exists to assert.
- **`checks.coexistence`:**
  - graphics fixtures must evaluate with no nixarchy assertion failing, and
    their `graphics-drivers(-32bit)` must build and contain a Mesa
    `egl_vendor.d` json;
  - `systempkg-own-ffmpeg`'s built `system.path` must resolve `bin/ffmpeg`
    into the user's `ffmpeg-full`.
- **Runs in the `system` job** (the `build.yml` edit is owner-signed): one
  step after "Build the installed-machine closure" (`build.yml:1380`), plus
  `coexistence` in `generated-checks.sh`'s `claimed` list (`:37`).
  - **Stop rule:** if the step adds more than about 2 minutes warm, stop and
    report.
- **AGENTS.md §14, "Coexist with the user's own config",** appended at the
  end; §1–§13 untouched.
- **§1 by staged reds on probe branches:**
  - graphics: #1163's assertion removed, plus a different Mesa;
  - `systemPackages`: nixarchy's `ffmpeg` raised to `hiPrio`.
- **If `systempkg-own-ffmpeg` is already red on `main`:** stop and report it
  as a bug; never flip the expectation.

## Repo traps

- **Work only in `/mnt/data/vmtest/wt-1164`.** Scratch trees are
  `git worktree add --detach`. Never touch `~/.config/nixos`.
- **The check builds real environments,** so the `system` closure must be
  warm. Do **not** build `checks.coexistence` locally while CI is busy; it is
  package tier at least, and `system.path` needs the full closure (§6). For
  local iteration, build only the graphics part
  (`graphics-drivers` is about 1.1 GB of substitutable Mesa), and only with
  `gh run list` showing nothing in flight and the load below 12.
- **Evaluating fixture configs** (`extendModules`) is cheap, under the flock.
- **No heredocs inside Nix strings** (§5). Capture exit status with
  `if …; then`, never through a pipe.
- **AGENTS.md:** append only. Verify no `§N` reference elsewhere changed:
  `grep -rn '§1[0-4]\|section 1[0-4]' .github/ tests/` before and after.
- **`build.yml` is a CI gate (§11):** only the signed-off step and the
  `claimed` entry. Nothing else in workflows.
- **After `.nix` edits:** `nix fmt`, then `git diff --stat`; then statix and
  deadnix.

## Steps

1. **Fixtures: `tests/coexistence/fixtures.nix` (new).**
   - An attrset `{ name = { pkgs, ... }: { … }; }` of the five modules, each
     with a one-line comment saying why it exists.
   - **Verify (cheap):** evaluate every fixture through
     `nixosConfigurations.reference.extendModules`. Count failing assertions
     per fixture: all must be 0. A fixture with a failing assertion is a
     finding: stop and report.

2. **The check: `tests/coexistence/default.nix` (new), plus `flake.nix`'s
   entry** beside `graphics-mesa-clash` (or `graphics-glibc`).
   - **Arguments:** `{ pkgs, reference }`.
   - **Per fixture:** `c = (reference.extendModules { modules = [ fixture ]; }).config`.
   - **Assertions:** `builtins.filter (a: !a.assertion) c.assertions`.
     Non-empty means FAIL, with the messages printed.
   - **Graphics fixtures:** the drivers env path comes from
     `c.systemd.tmpfiles.settings.graphics-driver."/run/opengl-driver"."L+".argument`,
     and `"/run/opengl-driver-32"` when `c.hardware.graphics.enable32Bit`.
     Make both inputs of the `runCommand`, so it builds them, then
     `ls "$env"/share/glvnd/egl_vendor.d/` must hold a `*mesa*.json`.
   - **`systempkg-own-ffmpeg`:** pass `c.system.path` and
     `pkgs.ffmpeg-full` in. `readlink -f "$path/bin/ffmpeg"` must start with
     the `ffmpeg-full` store path; else FAIL, naming the target.
   - **Output:** one line per fixture; exit 1 on any FAIL.
   - **Verify:**
     - evaluating `.drvPath` succeeds (cheap);
     - build only the graphics fixtures locally, under the rules above;
     - the full check runs in CI (step 4).
   - **If `systempkg-own-ffmpeg` is red at this point,** stop and report.

3. **AGENTS.md §14** (append at the end of `AGENTS.md`).
   - **Title:** "## 14. Coexist with the user's own config". Tight, in the
     file's own voice:
     - **why:** #1162 → #1163, the risk described in a PR paragraph, then
       found on the owner's own machine;
     - **the two failure modes, with their NixOS sources:** `buildEnv` without
       `ignoreCollisions` fails the build; `system.path` shadows silently;
     - **the rule:** a *Coexistence* section in the spec, answered by a
       fixture in `tests/coexistence/fixtures.nix` (plus an assertion or a
       warning where needed), and never only a PR sentence;
     - **announcing changed defaults** in the release notes and Discussions,
       with the migration step.
   - Add one line to `tests/AGENTS.md` pointing at `checks.coexistence` and
     saying what it cannot see: fonts, and real host configs.
   - **Verify:** the `§`-reference grep (traps) is unchanged.

4. **CI wiring: `.github/workflows/build.yml` and
   `.github/scripts/generated-checks.sh`.**
   - **After the "Build the installed-machine closure" step (`build.yml:1380`),
     add:**
     ```yaml
     - name: The user configs nixarchy promises to coexist with still build
       if: needs.gate.outputs.relevant == 'true'
       run: .github/scripts/build-unless-proven.sh .#checks.x86_64-linux.coexistence
     ```
     Match the neighbouring steps' `if:` and shape exactly.
   - **Add `coexistence`** to the `claimed` list at `generated-checks.sh:37`,
     spacing as the file's comment at `:79` requires.
   - **Verify:**
     - `actionlint`, with `-shellcheck=` and a timeout (the owner's notes:
       actionlint can hang on `build.yml`);
     - `bash .github/scripts/generated-checks.sh claimed` lists it;
     - `bash .github/scripts/generated-checks.sh generated` no longer does.

5. **The staged reds and the PR.**
   - **(a) graphics,** probe branch: remove #1163's two assertions, and point
     `graphics-own-mesa` at a Mesa from a different, substitutable nixpkgs pin
     (e.g. Hyprland's previous pin, or `nixpkgs-stable`'s Mesa if this flake
     has that input; check `flake.lock`). It must be red with buildEnv's
     collision line.
   - **(b) shadowing,** probe branch: `lib.hiPrio pkgs.ffmpeg` at
     `modules/nixos.nix:1066`. It must be red, naming whose `bin/ffmpeg` won.
   - Dispatch `build.yml` on each, record the run IDs and outputs, then delete
     the probe branches.
   - **Measure** the new step's wall time on the PR's own `system` run (warm).
     Over about 2 minutes: stop and report.
   - **The PR body:**
     - links intent, spec and plan;
     - the reds, the step time, the owner's `build.yml` sign-off quoted from
       the spec;
     - uses `closes #1164`;
     - contains no skip-CI marker;
     - says which steps the coder did.

## Tests

| step | command | expected |
|---|---|---|
| 1 | per-fixture failing-assertion count | 0 for all five |
| 2 | check `drvPath` evaluates; graphics part built locally under the rules | green |
| 3 | `§`-reference grep | unchanged |
| 4 | actionlint, `generated-checks.sh claimed`/`generated` | clean; listed or not as expected |
| 5 | probe (a), probe (b), PR CI | red, red, green; step time ≤ about 2 minutes |

## Rollback

Revert the squash commit. That removes the check, the `build.yml` step and
§14 together.
