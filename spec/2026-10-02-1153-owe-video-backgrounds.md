---
status: approved
issue: 1153
intent: intent/2026-10-02-1153-owe-video-backgrounds.md
---

# Spec: video backgrounds through owe, backported onto v4.0.4 and on by default

## Two defaults for the owner to settle on approval

The intent left these open. The spec proposes an answer for each, and approving
the spec accepts it.

- **Licence: package it on the PKGBUILD's word.** owe's PKGBUILD declares
  `license=('MIT')`, and upstream Omarchy ships it to every install. The
  package sets `meta.license = lib.licenses.mit`, with a comment that the
  repository has no LICENSE file. owe is **not** added to the cachix allowlist:
  it is a small C build, so every machine builds it locally and the public
  cache never serves it. If the owner later wants a LICENSE file, asking for
  one is the owner's call (no upstream posting).
- **Audio: as upstream.** A video's sound plays through the default output,
  and the manual says so in the same words upstream uses. Muting is one line in
  `~/.config/owe/config.toml` that the user owns. nixarchy does not seed that
  file.

## What was measured before writing this

- **Both upstream PRs apply to v4.0.4 cleanly.** omacom/omarchy#6792 (the squash
  commit `41b6cc69`, video selection) cherry-picks with no conflicts, and
  #12429 (owe) applies on top of it with `git apply -3`. Tried in
  `/mnt/data/vmtest/owe/omarchy`, branch `backport`.
- **The net change, leaving out `test/`, `install/`, `migrations/` and
  `manual/`,** is 18 files, +486/−76. `bin/omarchy-upgrade-to-quattro` is
  dropped too, which leaves 17:
  - bin: `omarchy-bar-text-color`, `omarchy-menu-images`,
    `omarchy-theme-bg-next`, `omarchy-theme-bg-set`, `omarchy-theme-set`,
    `omarchy-theme-switcher`;
  - shell: `Commons/Util.qml`, `Ui/BackgroundMedia.qml` (new), `Ui/qmldir`,
    `plugins/background/Background.qml`, `plugins/image-picker/list.sh`,
    `plugins/lock/{LockFeedSurface.qml (new), LockView.qml, Service.qml,
    poster.sh (new)}`, `plugins/services/battery/Service.qml`, `shell.qml`.
- **v4.0.4 already has what owed calls.** owed runs
  `omarchy-shell shell setPluginEnabled omarchy.background <bool>`
  (`src/daemon/shell.c`), and v4.0.4 has `setPluginEnabled` at
  `shell/shell.qml:1620`. It finds `owe-render` next to `/proc/self/exe`, so
  the store layout works. It runs `ffmpeg` from `PATH` to convert GIFs.
- **owed's Hyprland connection works on nixarchy.** owed reads
  `HYPRLAND_INSTANCE_SIGNATURE`. nixarchy starts the session through uwsm
  (`modules/nixos.nix:101`, `:986`), and upstream's `autostart.lua` imports the
  environment into the systemd user manager.
- **Every command the patched scripts add is already on the runtime list:**
  `ffmpegthumbnailer` (`pkgs/omarchy/default.nix:307`), `vips` (`:308`),
  `file` (`:312`), `ffmpeg` (`:213`), `util-linux` for `flock` (`:187`) and
  `socat` (`:198`).

## Design

### D1. The `owe` package: `pkgs/apps/owe.nix`

Modelled on `pkgs/apps/omacut.nix`: an omacom repo, `fetchFromGitHub` by
`tag = "v${version}"` (0.2.8), and a `passthru.updateScript`. It is registered
beside omacut in `flake.nix:753-777`, but is **not** a row in `data/apps.nix`.
It is part of the desktop, not an app a user picks, so it moves no count in
the README or in `docs/manual/other-packages.md`.

- **Build.** meson + ninja for the C binaries, then cmake for `qml-plugin/`,
  mirroring the PKGBUILD's `build()`. The inputs are:
  - `mpv-unwrapped` (libmpv) and `ffmpeg`;
  - `wayland`, `wayland-protocols`, `libglvnd` and `libepoxy`;
  - `systemd` (libsystemd) and `qt6.qtbase` / `qt6.qtdeclarative`.
- **QML install path.** The CMake file installs to
  `${CMAKE_INSTALL_LIBDIR}/qt6/qml/Owe/LockFeed`. nixpkgs' Qt uses
  `qt6.qtbase.qtQmlPrefix` (`lib/qt-6/qml`). Pass the prefix to cmake, or move
  the directory in `postInstall`. Either way, the import path in D3 names the
  same directory, and the package's own check asserts that `qmldir` exists
  there.
- **Tests.** `doCheck = true` runs `meson test` and the QML `ctest`, as the
  PKGBUILD's `check()` does. If one needs a display or a GPU the sandbox does
  not have, it is disabled **by name** with a comment, never wholesale.
- **Runtime.** `wrapProgram $out/bin/owed --prefix PATH : ${ffmpeg}/bin`, so
  GIF conversion does not depend on the caller (`pkgs/AGENTS.md`'s
  runtimeInputs note). `owe-render` needs nothing on `PATH`.
- **Also installed:** `hooks/owe-idle` to `$out/bin`,
  `hooks/theme-set.d/10-owe-sync` to `$out/share/owe/`, and the example
  `config.toml`, as the PKGBUILD does. `10-owe-sync` calls `socat`, so it is
  patched to the store `socat` rather than relying on `PATH`.
- `systemd/owed.service` is **not** installed. Home Manager declares the unit
  (D3), so there is exactly one copy of it.

### D2. The backport: one carried patch, applied before nixarchy's own edits

- **The file.** `pkgs/omarchy/1153-owe-video-backgrounds.patch` is generated
  as `git diff v4.0.4 backport` over the 17 files above. Its header names both
  upstream PRs and says the `quattro` bump deletes it.
- **Where it applies.** It is applied to the **source, before** the
  `substituteInPlace` edits (`default.nix:428` onwards), not at the end next to
  901/902 (`:2086`). That way the edits nixarchy already makes target the
  backported text, and `--replace-fail` fails the build loudly if an anchor
  moved. Applying it last would put it on text the edits had already changed,
  and `--fuzz=0` would fail for reasons that read as a broken patch.
  `--fuzz=0`, as for 901/902.
- **One existing edit must be retargeted.** The 4096 `sourceSize` cap
  (`default.nix:510-527`) anchors on
  `source: root.imageUrl(root.displayedBackground)`. After the backport, the
  desktop's base still draws through `BackgroundMedia.qml`, whose image sets
  `sourceSize.width: root.version > 0 ? width : 0`. On the desktop that
  `version` is 0, so with the cap left where it was, the base layer would
  decode at full size again. That is exactly the 8K-background black desktop
  the cap was written for.
  - **Change:** on `shell/Ui/BackgroundMedia.qml`,
    `root.version > 0 ? width : 0` → `root.version > 0 ? width : 4096`.
    Height stays `0` so the aspect ratio holds.
  - **The other two anchors still hold:** `oldBackground` and
    `incomingBackground`, the transition layers, are still in `Background.qml`
    (each matches once in the backported tree).
- **Anchors confirmed unaffected:**
  - both `omarchy-theme-set` substitutions (`:458`, `:493`);
  - the `shell-state-ipc` anchor in `shell.qml` (`:1841`).
- **Not taken from either PR:**
  - `install/omarchy-base.packages` and `migrations/*`: nixarchy installs from
    the module, and `omarchy-migrate` is a stub;
  - `install/user/first-run/enable-user-units.sh`: already replaced by
    nixarchy's own script, so first-run must not enable NixOS units;
  - `bin/omarchy-upgrade-to-quattro`;
  - the upstream tests.
- **The bin ledger.** Every patched `bin/` script gets its row in
  `tests/bin-ledger` in the same change (`pkgs/AGENTS.md:365-390`).
- **`pkgs/AGENTS.md`** gets a short carried-patch section, like the 901/902
  ones: what it is, the two upstream PRs, and that the `quattro` bump deletes
  it.

### D3. The option, the service, the hook and the import path

- **The option** (`modules/nixos.nix`, beside `aiMirror`):
  `programs.nixarchy.owe.enable = lib.mkOption { type = lib.types.bool;
  default = true; }`. It only does anything under `programs.nixarchy.enable`.
  Mode A, a configuration that only imports the module, therefore gets
  nothing.
- **Home Manager** (`modules/home.nix`), gated by
  `osConfig.programs.nixarchy.owe.enable or false` inside the existing
  `cfg.enable` block:
  - `home.packages`: `owe`, so `owe status` works in a terminal.
  - `systemd.user.services.owed`:
    - `PartOf` and `After` `graphical-session.target`;
    - `WantedBy = [ "graphical-session.target" ]`;
    - `Restart = on-failure` and `RestartSec = 2`, as upstream's unit;
    - `Environment`: `PATH` containing `cfg.package`'s `bin`, so owed can run
      `omarchy-shell`; plus `OMARCHY_PATH`. This follows
      `omarchy-theme-gnome` (`home.nix:1258-1277`), because "a user unit does
      not inherit the login PATH".
  - `xdg.configFile."omarchy/hooks/theme-set.d/10-owe-sync"`: executable,
    `exec ${owe}/share/owe/10-owe-sync "$@"`. This follows the `cursor` hook
    (`home.nix:1280-1291`).
- **The QML import path** (`modules/nixos.nix:1175`
  `environment.sessionVariables`, beside `OMARCHY_PATH`): under the same gate,
  `QML_IMPORT_PATH` names `${owe}/${qt6.qtbase.qtQmlPrefix}`. Quickshell is not
  wrapped here (`default.nix:430-433`), and session variables reach Hyprland
  and therefore the shell through PAM. It is an additional search path, so
  nothing else that Qt loads changes.
- **The off state.** With the option off, the package and its backported shell
  are unchanged: video files still appear in the picker, but choosing one shows
  an empty desktop layer, as upstream does without owe. This is stated in the
  option's description and the manual rather than worked around.
  Varying the omarchy package per option would mean two shells to build and
  test.

### D4. Checks (AGENTS.md §1–§3)

- **`tests/options.nix`.** The cases below take both states, each on
  `defaultHomeOn` / `homeOn { owe.enable = false; }`. The two NixOS cases are
  evaluated on the machine config, not the home fixtures.
  - `owePackage`;
  - `oweService`: `systemd.user.services ? owed`;
  - `oweHook`: `xdg.configFile ? "omarchy/hooks/theme-set.d/10-owe-sync"`;
  - `oweQmlPath` (NixOS): `environment.sessionVariables ? QML_IMPORT_PATH`;
  - `modeAInert` (NixOS): already covers the NixOS side. The new option's
    default must not leak into it.
- **The package's own check.** `installCheckPhase` asserts:
  - `owed`, `owe-render`, `owe` and `owe-idle` exist;
  - `$out/${qtQmlPrefix}/Owe/LockFeed/qmldir` exists;
  - `owe --version` prints `0.2.8`.
- **`checks.session`**, a new `# ---- owe (#1153) ----` block. It is the only
  layer that can see a blank desktop, which is the failure upstream has no
  fallback for.
  1. `systemctl --user is-active owed` is `active` within 30 s of login.
  2. A 2-second `ffmpeg -f lavfi testsrc` mp4 is built at evaluation time and
     set with `omarchy-theme-bg-set` (the backported script). Then:
     - `owe status` reports a video source and a live renderer;
     - the existing wallpaper pixel-delta probe (`tests/session.nix:1865-1880`)
       reads non-blank pixels **and** two frames 1 s apart differ, so the video
       is actually playing.
  3. `omarchy-theme-bg-set` back to a still: `owe render-status` shows the
     renderer stopped, and the shell's background plugin is enabled again.
  4. Locking: `Owe.LockFeed` loads, and the lock view's
     `lockFeedLoader.status` is `Ready`, read through the shell's IPC. A
     missing import path otherwise shows only as "no lock video".
- **Real hardware only.** The VM decodes in software. VAAPI hardware decoding,
  pausing on battery, and DPMS cannot be reached here, so they become a
  `pkgs/verify.sh` row: set a video, check `owe render-status` shows `hwdec`
  not `no`, and check that pulling AC with `battery_mode` set pauses it. They
  also get a sentence in `tests/AGENTS.md` naming the gap (§3).
- **Proving the checks fail** (§1). Each is shown red before it is shown green,
  and the output goes in the PR:
  - drop `QML_IMPORT_PATH` → step 4 fails;
  - remove the service's `PATH` → step 2 fails, because owed cannot hand the
    layer over;
  - revert the 4096 retarget → **no check sees it in a VM** (llvmpipe at the
    test resolution decodes fine). That is stated in the PR rather than
    claimed covered, and the existing comment's reasoning carries it.

### D5. Docs

- **`docs/manual/`:**
  - a backgrounds section: videos and GIFs, where to drop them, that the sound
    plays (upstream's wording), the power cost, `owe pause` / `owe status`,
    and the option to turn it off;
  - a row in the option reference.
- **README:** no count moves (owe is not a default plugin and not an
  `apps.nix` row). The plan confirms this with `readme-counts.sh`, not by
  assumption.
- **A Discussions announcement** when it ships (the owner's standing rule).

## Alternatives rejected

- **Wait for the `quattro` bump.** The owner chose "ready to use now".
- **Package owe only, with no shell backport.** v4.0.4's shell keeps drawing
  the still image behind a video, so two layers compete on the background
  layer. It cannot select a video either (`omarchy-theme-bg-next` lists images
  only).
- **Re-implement the shell side in nixarchy's own style.** The constraint is
  to match upstream, so that the `quattro` bump deletes our copy instead of
  conflicting with it.
- **Apply the patch at the end beside 901/902.** That puts the patch on text
  nixarchy's own edits have already changed (see D2).
- **Wrap quickshell for the import path.** That rebuilds the wrapper and fixes
  the path for every user regardless of the option. A session variable follows
  the option.
- **Seed `~/.config/owe/config.toml`.** It is user-owned. Seeding it now would
  make every later default a merge question.
- **Wire `owe-idle` into hypridle.** Upstream does not; owe pauses on lock and
  DPMS without it.

## Risks

- **A blank desktop when owed is down.** With a video background, the shell
  leaves its layer empty and owe draws nothing. `Restart=on-failure` covers a
  crash, the session check covers "never started", and a stopped service is
  visible to `nixarchy-doctor`. Nothing covers owe failing on one machine's GPU
  driver; that is the `verify.sh` row.
- **Experimental upstream.** owe is at 0.2.8 and calls itself experimental.
  The option is the escape hatch, and its description says so.
- **An always-on poll.** The backported battery service polls
  `powerprofilesctl get` every 2 s for the lock screen's power-saver rule.
  That is upstream's choice; it is carried as-is and noted in the carried-patch
  section.
- **The carried patch's lifetime.** Each v4.0.x bump re-applies it with
  `--fuzz=0`, so a bump that touches the same lines fails the build. That is
  the intended signal. At `quattro` the patch is deleted, and the owe package
  and module stay.
- **Store space.** libmpv and ffmpeg are already in the closure through `mpv`
  (`default.nix:215`), so owe adds little.

## Verification

"Done" means all of the following:

1. `nix build .#owe` (or the attribute registered in D1) builds, its own
   tests pass, and its install check passes.
2. `nix build .#omarchy` applies the patch with `--fuzz=0`, and every
   `--replace-fail` still matches.
3. `checks.options`, `checks.patched-files`, `checks.session` and the bin-ledger
   check pass. Under the build tiers (§6) the VM and options checks run in CI.
4. Each new assertion is shown failing first (D4), with the output in the PR.
5. `nix fmt -- --ci`, statix and deadnix are clean. Check `git diff --stat`
   after the formatter hook (§5).
6. On p620: set a real video background and see it play on all monitors.
   Then confirm that locking shows it muted, that a fullscreen window pauses it
   (`owe status`), and that `owe render-status` shows hardware decoding.
