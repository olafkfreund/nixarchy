---
status: approved
issue: 1153
spec: spec/2026-10-02-1153-owe-video-backgrounds.md
---

# Plan: video backgrounds through owe, backported onto v4.0.4 and on by default

## Approved decisions (self-contained; you need not open the spec)

- **Licence.** Package owe 0.2.8 (omacom/owe, tag `v0.2.8`) as
  `meta.license = lib.licenses.mit`, on the PKGBUILD's declaration. Add a
  comment that the repository has no LICENSE file. **Do not** add it to
  `.github/scripts/cache-allowlist.sh`.
- **Audio** plays as upstream does. Do not seed `~/.config/owe/config.toml`.
- **On by default** for installer-managed machines.
  `programs.nixarchy.owe.enable`, `default = true`, does nothing unless
  `programs.nixarchy.enable` is set. Mode A gets nothing.
- **The backport.** Upstream omacom/omarchy#6792 (video selection, squash
  commit `41b6cc69`) and #12429 (owe), carried as **one** patch on v4.0.4,
  applied to the tree **before** nixarchy's own `substituteInPlace` edits.
  The `quattro` bump deletes the patch; the package and the module stay.
- **Not taken:** `install/`, `migrations/`, `manual/`, `test/` and
  `bin/omarchy-upgrade-to-quattro` from either PR. The first-run units script
  is already replaced by nixarchy's own. Do not wire `owe-idle` into hypridle.
- **The off state** keeps the backported shell, so video files are listed and
  choosing one shows an empty desktop layer. Document it; do not work around
  it.

## Repo traps that apply throughout

- **A hook may rewrite `.nix` files.** On this machine a hook runs
  `nixpkgs-fmt` after every `.nix` edit. After each edit run `nix fmt`, then
  read `git diff --stat` before committing (AGENTS.md §5, #897).
- **The flake only sees tracked files.** A new file must be `git add`ed before
  any `nix build` or `nix eval`, or it "does not exist" (§5).
- **Build tiers (§6).**
  - Cheap checks: any time, one at a time, under
    `flock /mnt/data/vmtest/codex-build.lock`.
  - Package builds (`.#owe`, `.#omarchy`): only with no p620 system build
    running (`pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'` is 0)
    and the 1-minute load below 12.
  - `checks.options` and `checks.session`: **CI only**, unless
    `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
    prints `0`.
- **No `pkill` by name.** Kill only the pid you started.
- **Proving a check fails (§1):** prove each break landed with `git diff` or
  `grep` before reading a green result. Restore with `git checkout HEAD --
  <path>`, not `git checkout -- <path>`, and commit a baseline before any
  break loop.
- **Heredocs in Nix strings:** none inside an indented `''…''` string. Use
  `printf '%s\n'` (§5).

## Steps

Each step ends in its own commit on `feat/1153-owe-video-backgrounds`, with a
full-sentence subject and `Refs #1153`.

1. **The package: `pkgs/apps/owe.nix` (new); `flake.nix:769`.**
   - Write a `stdenv.mkDerivation (finalAttrs: …)`, modelled on
     `pkgs/apps/omacut.nix`:
     - `fetchFromGitHub { owner = "omacom"; repo = "owe"; tag = "v${finalAttrs.version}"; hash = …; }`;
     - `nativeBuildInputs`: `meson ninja pkg-config cmake wayland-scanner makeWrapper`;
     - `buildInputs`: `mpv-unwrapped ffmpeg wayland wayland-protocols libglvnd libepoxy systemd qt6.qtbase qt6.qtdeclarative`;
     - `dontWrapQtApps = true`, since no binary is a Qt app; the QML plugin is
       a library;
     - `passthru.updateScript = nix-update-script { };`.
   - **Two builds in one derivation.** The meson build runs through the
     default phases. In `postBuild`, configure and build `qml-plugin/` with
     cmake into a separate directory, passing
     `-DCMAKE_INSTALL_LIBDIR=lib`. In `postInstall`:
     - run `cmake --install` for it;
     - move `$out/lib/qt6/qml` to `$out/${qt6.qtbase.qtQmlPrefix}` if the
       prefix differs, and remove the empty directory;
     - `install -Dm755 hooks/owe-idle $out/bin/owe-idle`;
     - `install -Dm755 hooks/theme-set.d/10-owe-sync $out/share/owe/10-owe-sync`;
     - `install -Dm644 config/config.toml $out/share/doc/owe/config.toml.example`;
     - `wrapProgram $out/bin/owed --prefix PATH : ${lib.makeBinPath [ ffmpeg ]}`.
   - **Store paths in the hooks.** `substituteInPlace` with `--replace-fail`
     on `$out/share/owe/10-owe-sync` and `$out/bin/owe-idle`, turning
     `socat -` into `${socat}/bin/socat -`. Grep both files first for every
     command they call, and patch each one.
   - **Tests.** `doCheck = true` (`meson test`). Also run the QML `ctest` in
     `postCheck`. If a test needs a display, disable that test **by name** with
     a comment; never set `doCheck = false`.
   - **`doInstallCheck` asserts:**
     - `$out/bin/{owed,owe-render,owe,owe-idle}` exist;
     - `$out/${qt6.qtbase.qtQmlPrefix}/Owe/LockFeed/qmldir` exists;
     - `$out/bin/owe --version` contains `0.2.8`.
   - **`meta`:** description, homepage, `license = lib.licenses.mit` (with the
     comment), `platforms = lib.platforms.linux`, `mainProgram = "owe"`.
   - **Register it** next to omacut at `flake.nix:769`
     (`owe = final.callPackage ./pkgs/apps/owe.nix { };`), and wherever
     omacut is exposed as a package (`flake.nix:1216`). Follow omacut's
     pattern exactly. Do **not** add a row to `data/apps.nix`.
   - **Verify:** `nix build .#owe -L` builds (package tier), and the install
     check passes. To see the install check fail, change the asserted
     version to `9.9.9`, watch it go red, then revert.
   - **Traps:**
     - The meson `test/` directory may need python: add `python3` to
       `nativeCheckInputs`, as the PKGBUILD's `checkdepends`.
     - Get the `hash` from the first failed build. Never guess it.

   - **Done (deviations).** (a) After `mesonBuildPhase` the working directory
     is `build/` inside the source, so the cmake `-S`, hook and config paths
     are `../…`. (b) meson defines no suites, so the excluded test (`daemon`,
     which needs a live Wayland display) is dropped through a positional
     allowlist in `mesonCheckFlags`. A test a later owe adds does not run until
     it is named, so the comment there says to diff `test/meson.build` on
     every bump. `egl-context` and `transition` self-skip (exit 77). The QML
     `ctest` runs in `postCheck`. Built: `nix build .#owe` →
     `…n80zj1jm…-owe-0.2.8`. Proof: the install check with `9.9.9` exits 1
     ("owe --version did not report 9.9.9"), and is green once reverted.

2. **The backport patch: `pkgs/omarchy/1153-owe-video-backgrounds.patch`
   (new); `pkgs/omarchy/default.nix:422-427` and `:510-527`.**
   - **Generate it** from the tested tree at `/mnt/data/vmtest/owe/omarchy`,
     branch `backport`, which is v4.0.4 plus `41b6cc69` plus #12429:
     ```
     git -C /mnt/data/vmtest/owe/omarchy diff v4.0.4 backport -- bin/omarchy-bar-text-color bin/omarchy-menu-images bin/omarchy-theme-bg-next bin/omarchy-theme-bg-set bin/omarchy-theme-set bin/omarchy-theme-switcher shell/Commons/Util.qml shell/Ui/BackgroundMedia.qml shell/Ui/qmldir shell/plugins/background/Background.qml shell/plugins/image-picker/list.sh shell/plugins/lock/LockFeedSurface.qml shell/plugins/lock/LockView.qml shell/plugins/lock/Service.qml shell/plugins/lock/poster.sh shell/plugins/services/battery/Service.qml shell/shell.qml
     ```
     If that tree is gone, recreate it: clone omacom/omarchy, `checkout -B
     backport v4.0.4`, `cherry-pick 41b6cc69`, then
     `gh pr diff 12429 -R omacom/omarchy | git apply -3 --index`. Both apply
     cleanly (measured 2026-10-02).
   - **Prepend a header** of comment lines before the first `diff --git`
     (`patch` ignores leading text). It names both upstream PRs, says it is
     CARRIED, and says the `quattro` bump deletes it.
   - **Apply it** in `default.nix` right after `:424`, the `rm -rf …` line
     after `cp -r . $out/share/omarchy/`, and before the first
     `substituteInPlace` at `:427`:
     `patch -d "$out/share/omarchy" -p1 --forward --fuzz=0 < ${./1153-owe-video-backgrounds.patch}`.
     Add a short comment that it goes here, not with 901/902 at `:2086`,
     because nixarchy's edits below must target the backported text.
   - **Retarget the 4096 cap at `:521-527`:**
     - drop `displayedBackground` from the `for prop in …` list, keeping
       `oldBackground incomingBackground`;
     - add a `substituteInPlace` on
       `$out/share/omarchy/shell/Ui/BackgroundMedia.qml` with `--replace-fail`
       `'sourceSize.width: root.version > 0 ? width : 0'` →
       `'sourceSize.width: root.version > 0 ? width : 4096'`;
     - extend the comment by one line: the base layer now draws through
       `BackgroundMedia` (#1153).
   - **Verify:**
     - `nix build .#omarchy -L` (package tier): the patch applies with
       `--fuzz=0` and every `--replace-fail` still matches;
     - `grep -c 'width : 4096' result/share/omarchy/shell/Ui/BackgroundMedia.qml` is `1`;
     - `test ! -e result/share/omarchy/shell/Ui/BackgroundVideo.qml`;
     - `test -x result/share/omarchy/shell/plugins/lock/poster.sh`.
   - **Traps:**
     - Read the build's patch output. "Reversed (or previously applied) patch
       detected" under `--forward` means it hit the wrong base.
     - `poster.sh` must keep its executable bit: a `git diff` patch carries
       `new file mode 100755`, and GNU patch honours it. Check the result.

3. **Ledger, inventory and carried-patch notes: `tests/bin-ledger.nix`,
   `tests/patched-files.nix`, `pkgs/AGENTS.md`.**
   - Read `pkgs/AGENTS.md:365-390` and add whatever rows the ledger requires
     for each patched `bin/` script:
     - `omarchy-bar-text-color`, `omarchy-menu-images`,
       `omarchy-theme-bg-next`, `omarchy-theme-bg-set`, `omarchy-theme-set`
       and `omarchy-theme-switcher`.
   - If `tests/patched-files.nix` lists patched files, add the patch's files
     the way 901/902's are listed.
   - Add a section to `pkgs/AGENTS.md`, next to the 901/902 carried-patch
     sections, covering:
     - what the patch is, and the two PRs;
     - why it is applied first;
     - the retargeted 4096 cap;
     - upstream's 2-second `powerprofilesctl get` poll, carried as is;
     - "deleted by the quattro bump".
   - **Verify:** `nix build .#checks.x86_64-linux.bin-ledger` and
     `.#checks.x86_64-linux.patched-files` (cheap tier).
   - **Traps:** the ledger's own failure message names the missing row, so
     read it rather than guessing the format.

4. **The option, the service, the hook and the import path:
   `modules/nixos.nix`, `modules/home.nix`.**
   - **`nixos.nix`, beside `aiMirror` (`:743`):**
     ```nix
     owe.enable = lib.mkOption {
       type = lib.types.bool;
       default = true;
       description = "Video and GIF desktop backgrounds through owe …";
     };
     ```
     The description says: what owe is; that a video plays its sound; that
     off leaves video files selectable but shown as an empty desktop; and that
     owe is experimental upstream.
   - **`nixos.nix`, in the session-variables block at `:1176` (beside
     `OMARCHY_PATH`):**
     `QML_IMPORT_PATH = lib.mkIf cfg.owe.enable "${pkgs.nixarchy-apps.owe}/${pkgs.qt6.qtbase.qtQmlPrefix}";`.
     Use the attribute path step 1 created. If that block is a plain attrset
     where `mkIf` does not merge, use a separate
     `environment.sessionVariables = lib.mkIf …` definition, as
     `INPUT_METHOD` does at `:1997`. **Corrected after review:** the value
     is a one-element list, not a plain string -- `environment
     .sessionVariables` merges list-valued entries colon-joined, like
     `PATH`, so this definition is appended to by anything else that sets
     `QML_IMPORT_PATH` rather than silently overwriting it. Confirmed by
     eval that the final `config.environment.sessionVariables
     .QML_IMPORT_PATH` is still the plain path string either way.
   - **`home.nix`.** Define
     `oweOn = osConfig.programs.nixarchy.owe.enable or false;` near the other
     `osConfig` reads (`:50-55`). **Corrected after review:** this reads only
     `owe.enable`, which defaults to `true` on its own -- a module's option
     defaults exist whether or not `programs.nixarchy.enable` turned the
     feature on, since only the latter's `config = lib.mkIf cfg.enable { … }`
     is gated, never the option declarations. So a machine with nixarchy's
     NixOS side off (Mode A) but this Home Manager module on regardless
     would still get `owed`, the package and the hook. `oweOn` is
     `(osConfig.programs.nixarchy.enable or false) && (osConfig.programs
     .nixarchy.owe.enable or false)`, the same two-condition shape
     `home.packages`'s own ai-mirror gate already uses two lines below.
     `tests/options.nix` gained `oweServiceModeAInert` (on =
     `defaultHomeOn`, off = `fixtureNixarchyOff`) to hold this. Inside the
     `cfg.enable` block (`:775`):
     - `home.packages = lib.optional oweOn owe;`. Add it to the existing list
       the way ai-mirror is at `:998-1000`.
     - `systemd.user.services.owed = lib.mkIf oweOn { … }`, modelled on
       `omarchy-theme-gnome` (`:1258-1277`):
       - `Unit.Description`, `Unit.PartOf = [ "graphical-session.target" ]`,
         `Unit.After = [ "graphical-session.target" ]`;
       - `Service.ExecStart = "${owe}/bin/owed"`, `Restart = "on-failure"`,
         `RestartSec = 2`;
       - `Service.Environment = [ "PATH=${lib.makeBinPath [ cfg.package pkgs.coreutils ]}" "OMARCHY_PATH=${omarchyPath}" ]`,
         copying whatever `omarchy-theme-gnome` uses for `omarchyPath`;
       - `Install.WantedBy = [ "graphical-session.target" ]`.
     - `xdg.configFile."omarchy/hooks/theme-set.d/10-owe-sync" = lib.mkIf oweOn { executable = true; text = …; }`,
       modelled on the `cursor` hook (`:1280-1291`). Its text is
       `#!/usr/bin/env bash` then `exec ${owe}/share/owe/10-owe-sync "$@"`.
   - **Verify (cheap tier):**
     - `nix eval .#nixosConfigurations.reference.config.environment.sessionVariables.QML_IMPORT_PATH`
       prints the store path, and that path's `Owe/LockFeed/qmldir` exists
       after building;
     - `nix eval` of the reference home's `systemd.user.services.owed.Service.ExecStart`.
   - **Traps:**
     - `osConfig … or false` is mandatory, because standalone Home Manager
       has `osConfig = null`.
     - **Do not `mkDefault` a list or an attrset** (`modules/services/default.nix`
       header): plain assignment for lists and attrsets.
     - **A module argument cannot have a `?` default** (§5).

5. **Option tests: `tests/options.nix`.**
   - Add a fixture `oweOffHome = homeOn { owe.enable = false; } { };` beside
     `aiMirrorMcpHome` (`:200`). Add the matching NixOS-side fixture if the
     file has one for machine options (look at how `modeAInert` and the NixOS
     cases are built).
   - Add cases next to `aiMirrorPackage` (`:711`), each `{ on = …; off = …; }`
     with `on` from `defaultHomeOn` and `off` from `oweOffHome`:
     - `owePackage`;
     - `oweService` (`systemd.user.services ? owed`);
     - `oweHook` (`xdg.configFile ? "omarchy/hooks/theme-set.d/10-owe-sync"`);
     - and on the NixOS side `oweQmlPath`
       (`environment.sessionVariables ? QML_IMPORT_PATH`).
   - Confirm `modeAInert` still covers the NixOS side with the new option.
   - **Verify:** CI's `system` job runs `checks.options` (CI-only tier).
     Before pushing, break one case on purpose (e.g. invert `oweService`'s
     `off`), let CI or an idle-CI local run show red, restore it, and record
     the red output for the PR.
   - **Traps:** `checks.options` peaks at about 11.5 GB of memory and takes
     about 4 minutes on CI. Never run it locally while CI has anything in
     flight.

6. **The VM probe: `tests/session.nix`.**
   - **A test video at evaluation time** (top of the file, beside the other
     store inputs at `:9`): a `runCommand` that runs
     `ffmpeg -f lavfi -i testsrc=size=640x360:rate=25 -t 3 -pix_fmt yuv420p $out/loop.mp4`
     with `pkgs.ffmpeg`. `testsrc` moves frame to frame, which the probe
     relies on.
   - **The probe** is a new `# ---- owe (#1153) ----` block appended after the
     ai-mirror block (`:1901` onwards). Use the existing `user % "cmd"` helper
     (`:832`), or a local helper that exports `HYPRLAND_INSTANCE_SIGNATURE`
     like `aim()` (`:1909-1914`). Poll with
     `for _ in range(N): … machine.sleep(…)`, never a bare sleep.
     1. `systemctl --user is-active owed` is `active` within 30 s.
     2. Copy the test video into `~/.config/omarchy/backgrounds/<theme>/` (or
        wherever the backported `omarchy-theme-bg-set` accepts it), then run
        `omarchy-theme-bg-set <path>` as the user. Poll `owe status` until it
        reports a video source with the renderer alive (parse the JSON with
        `json.loads`). Then take two `machine.screenshot()` captures 1 s apart.
        Assert, with "why" messages:
        - the frames differ (the average-colour difference, using the
          `avg()` helper already at `:1858-1862`, is above a small
          threshold);
        - neither frame is near-black.
     3. `omarchy-theme-bg-set` back to the theme's original still. Poll
        `owe render-status` until the renderer is not running, and check the
        shell's background plugin is enabled. If the shell exposes plugin state
        over IPC, use that; otherwise use the existing wallpaper pixel probe's
        approach.
     4. Lock with the video set (find how the session already locks, if it
        does). Assert the lock view's `lockFeedLoader` reached `Ready`. If
        that cannot be read over the shell's IPC, assert instead that the
        shell's journal (`journalctl --user -t` the shell's identifier) has no
        `module "Owe.LockFeed" is not installed` line. Say which one was
        possible in the PR. Unlock and restore the still.
   - **Verify:** CI only.
   - **Breaks to record (§1), each shown landed with `grep` before being run:**
     - (a) remove `QML_IMPORT_PATH` from step 4's change → probe 4 fails;
     - (b) remove the service's `PATH` entry → probe 2 fails, because owed
       cannot hand the layer over. **Doubt recorded at step 6 (deviation):**
       owed also finds `omarchy-shell` under `$OMARCHY_PATH/bin`
       (`src/daemon/shell.c:33`), and `owe-render` next to its own binary, so
       with `OMARCHY_PATH` still set this break may stay green. If it does,
       the PR says so, and the break becomes "remove both `PATH` and
       `OMARCHY_PATH`", which is the property that matters: owed can reach
       the shell.;
     - (c) revert step 2's 4096 retarget → the **existing** wallpaper probe
       (`:1864-1898`) may now fail: its message names exactly this. Record
       whether it did. The spec expected that no VM sees this, so a red here
       is a deviation to note in the PR and in this plan.
   - **Deviations, as actually implemented:**
     - **The test video is flat colours, not `testsrc`.** `testsrc`'s moving
       bars barely shift the whole-screen average `avg()` reads, so a single
       pair of screenshots 1 s apart could pass on a correct build and fail
       on a flaky one, or the reverse. The video is instead two 1 s segments,
       plain red then plain blue, concatenated into a 2 s loop
       (`ffmpeg -f lavfi -i color=c=red:... -f lavfi -i color=c=blue:...
       -filter_complex concat`), which the screen-filling average cannot
       miss.
     - **Five screenshots over 2 s, not two 1 s apart.** A single pair can
       land on the same half of a 2 s loop by bad luck; a `shot_series()`
       helper takes five, 0.4 s apart (`time.sleep`, since this samples a
       fixed span rather than polling a condition), and a `spread()` helper
       asserts the largest pairwise `avg()` delta among them exceeds 60 --
       at least one pair must straddle a colour change over that span.
     - **Step 2 also asserts `engine == "renderer"`** (from `owe status`)
       and that `omarchy-plugin-list --json` reports `omarchy.background`
       **disabled** while the video plays -- not just that a video source
       and a live renderer are reported, which does not by itself prove
       owed took the layer from the shell.
     - **Step 4's lock assertion is positive, not only the journal check
       the plan allowed as a fallback.** The same `shot_series`/`spread`
       pair, pointed at the locked screen: `owed` starts the LockFeed for
       every locked session by default (no config needed), so a moving
       series there is the real assertion, and what makes break (a) go red.
       The journal check for `Owe.LockFeed" is not installed` is kept, but
       only as a secondary diagnostic `print()` before the real assertion --
       it explains *why* when it fires, it does not gate the check. No IPC
       route for the feed Loader's own state exists (`Service.qml`'s
       `IpcHandler` names only `lock`/`isLocked`/`status`/`preview`/
       `hidePreview`), confirming the plan's own fallback was necessary.
   - **Traps:**
     - `checks.session` boots a desktop: CI only (§6 tiers).
     - Evaluate the drvPath first and build `'<drv>^*'`, so a break is not
       evaluated from a stale tree (§5): `nix eval --raw .#checks.x86_64-linux.session.drvPath`.
     - A probe that cannot run reads as one that passed (§4): every step
       asserts something.

7. **The hardware hole: `pkgs/verify.sh`, `tests/AGENTS.md`.**
   - **`pkgs/verify.sh`:** add a row in the file's existing style:
     - with a video background set, `owe render-status` reports a hardware
       decoder (`hwdec` is not `no`);
     - with `battery_mode = "pause"` in `~/.config/owe/config.toml` and AC
       pulled, `owe status` reports the battery pause.
   - **`tests/AGENTS.md`:** one paragraph, in the right existing section,
     naming the hole. VMs decode in software and have no battery or DPMS, so
     only `verify.sh` covers those.
   - **Verify:** `bash -n pkgs/verify.sh`. If a check covers `verify.sh`'s
     structure, run it (cheap tier).
   - **Deviation:** `flake.nix`'s `nixarchy-verify` `writeShellApplication`
     needed `nixarchy-apps.owe` added to its `runtimeInputs`, not named in
     the plan, because the new row calls `owe` by bare name
     (`writeShellApplication`'s own trap: an undeclared command depends on
     whatever the caller's PATH happens to supply). It is declared
     unconditionally, the same as `podman` for the Boxes section above it,
     because `programs.nixarchy.owe` can be off on the machine running
     `nixarchy verify` -- the row's `command -v owe` guard therefore always
     succeeds, and the real "off" signal is `owe status` coming back empty
     (owed has no socket to answer on).
   - **The row also reads `engine` from `owe status`, not from
     `owe render-status`.** `render-status` PROXIES the renderer process's
     own reply once one is running (`daemon_ipc.c`'s handler, when
     `owed_app_renderer_expected()` is true), and that reply has no
     `engine` field at all -- only owed's own synthetic shell-engine reply
     names one. `owe status` always carries it. The row reads `engine` from
     `owe status` first (`shell` → no video set, `hmm`; `renderer` → go on
     to read `hwdec` from `owe render-status` and judge `ok`/`bad`).

8. **Docs: `docs/manual/`, and the README counts.**
   - Find the manual page that covers backgrounds (start at
     `docs/manual/making-your-own-theme.md:19`, `:79`). Add a "Video
     backgrounds" section covering:
     - the formats (`mp4 m4v mov webm mkv avi`, plus GIF);
     - where to drop the files;
     - "plays its sound through the default audio output", upstream's wording;
     - the power cost;
     - `owe status`, `owe pause` and `owe resume`;
     - `programs.nixarchy.owe.enable = false`, and what off means.
   - Add the option wherever the manual lists `programs.nixarchy.*` options.
     If that list has its own check, run it.
   - **Counts:** run `.github/scripts/readme-counts.sh`, which should report
     no change. If it reports one, read why before touching anything (§4, a
     derived number).
   - **Verify:** the docs checks in `build.yml` that the page touches.

9. **Proof, PR and announcement.**
   - `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .` and
     `nix run nixpkgs#deadnix -- --fail .`.
   - Check `git diff --stat origin/main` and `git merge-base origin/main HEAD`
     (§5, #922).
   - Squash or retitle so that no `wip:` subject lands (§8).
   - **The PR body** links intent, spec and plan, and:
     - pastes every red output from steps 1, 5 and 6;
     - says which steps the coder did;
     - names the hardware hole;
     - uses `closes #1153`;
     - contains no skip-CI marker.
   - **On p620, after merge:** set a real video and check it plays on all
     monitors, the lock screen shows it muted, a fullscreen window pauses it,
     and `owe render-status` shows hardware decoding.
   - Post the Discussions announcement (what was added, what changed, what is
     coming).

## Tests

| step | command | expected |
|---|---|---|
| 1 | `nix build .#owe -L` | builds; meson tests, ctest and the install check pass |
| 2 | `nix build .#omarchy -L` | patch applies with `--fuzz=0`; every `--replace-fail` matches; the greps in step 2 hold |
| 3 | `nix build .#checks.x86_64-linux.{bin-ledger,patched-files}` | green (run separately, so one eval error does not hide the other, §13) |
| 4 | the `nix eval`s in step 4 | store paths printed |
| 5 | `checks.options` (CI) | green; the deliberate break is red |
| 6 | `checks.session` (CI) | green; breaks (a) and (b) are red; (c) is recorded either way |
| 7–8 | `bash -n`, docs checks, `readme-counts.sh` | green, no count change |
| 9 | the p620 hand check | plays, locks muted, pauses, uses hardware decoding |

## Rollback

- **Per machine:** `programs.nixarchy.owe.enable = false`. This removes the
  service, the hook and the import path; the backported shell stays.
- **Whole feature:** revert the squash commit. The patch, the package and the
  module are all in it, and nothing persists outside the user's
  `~/.cache/owe`, `~/.cache/omarchy/lock-poster` and an optional
  `~/.config/owe/`. Those are harmless to leave behind.

## Deviations found by CI on #1156 (2026-10-02)

- **Step 1.** The install check's `owe --version | grep -q` tripped
  `checks.grep-q-pipefail`, so it compares the string directly.
- **Step 1, a carried owe patch.** `owed` gave `owe-render` 1 s to open its
  socket (`supervisor.c`, `while (waited < 1000)`). Under llvmpipe, start-up
  measured about 1.3 s, so the VM never got a renderer: owed killed it and
  retried every 30 s. A `postPatch` `--replace-fail` raises it to 10 s.
- **Step 4.** owed's unit `PATH` was the Omarchy package plus coreutils.
  `omarchy-shell` finds the shell through `qs`, so every handoff logged
  "omarchy-shell is not running", and the desktop stayed `#111212` with a
  spread of 0. The `PATH` is now the package's `runtimeDeps`. checks.session
  step 2 was the probe that caught it, which is what break (b) existed to
  show; it went red on the real configuration rather than a deliberate break.
