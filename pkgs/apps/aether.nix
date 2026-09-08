{
  lib,
  stdenv,
  buildGoModule,
  buildNpmPackage,
  applyPatches,
  fetchFromGitHub,
  nodejs,
  wails,
  pkg-config,
  webkitgtk_4_1,
  gtk3,
  wrapGAppsHook3,
  makeDesktopItem,
  copyDesktopItems,
  nix-update,
  writeShellApplication,
}:
let
  pname = "aether";
  version = "4.29.8";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "aether";
    tag = "v${version}";
    hash = "sha256-gB6vRNoo309eAWhAhDFDiIzHjSBalKpOjafnx8wzZP0=";
  };

  # The Svelte frontend, built on its own and handed to the Go build finished.
  #
  # Not `npmDeps` on the buildGoModule below, which is the obvious shape and
  # does not work: nativeBuildInputs reach the go-modules derivation too, so
  # npmConfigHook runs where there is no package-lock.json and the vendor
  # fetch dies with "ERROR: no dependencies were specified" -- a message about
  # npm, printed by a derivation that is fetching Go modules.
  #
  # Two derivations also means the npm tree is fetched once and cached, rather
  # than re-fetched whenever a Go dependency moves.
  # The frontend source with its lock file corrected.
  #
  # Upstream's package-lock.json is out of sync with its package.json, and
  # `npm ci` -- which buildNpmPackage uses, correctly, because it is the only
  # npm mode that installs exactly what is locked -- refuses outright:
  #
  #   npm error `npm ci` can only install packages when your package.json and
  #   package-lock.json ... are in sync.
  #   npm error Missing: @emnapi/core@ from lock file
  #   npm error Missing: @emnapi/runtime@ from lock file
  #
  # Those are optional native transitive dependencies npm omitted when the lock
  # was generated on another platform. Regenerating needs a network, which a
  # sandboxed build has not got, so the corrected lock is carried as a patch --
  # produced with `npm install --package-lock-only` against the tagged source,
  # 146 lines adding what npm was missing.
  #
  # Patched HERE rather than inside buildNpmPackage, and that is the point:
  # fetchNpmDeps reads the lock from `src`, so a patch applied within the
  # package fetches against the old lock and builds against the new one --
  # which surfaces as a hash mismatch that looks like a stale npmDepsHash and
  # is not.
  #
  # It comes off the moment upstream's lock is in sync: the build fails loudly
  # if the patch stops applying, which is the notification.
  frontendSrc = applyPatches {
    # applyPatches cannot derive a name from a string src.
    name = "${pname}-frontend-source";
    src = "${src}/frontend";
    patches = [ ./aether-lockfile.patch ];
    # -p2: the patch was made against frontend/package-lock.json from the
    # repository root, and this source IS frontend/.
    patchFlags = [ "-p2" ];
  };

  frontend = buildNpmPackage {
    pname = "${pname}-frontend";
    inherit version;
    src = frontendSrc;

    npmDepsHash = "sha256-Ry8BEmGVVL+RjkLFZTdsC9/M37DtjGw3m5zDtAcPj7s=";

    # `npm run build` writes dist/, which is what wails embeds.
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
in
buildGoModule {
  inherit pname version src;

  # Sibling of pkgs/apps/omawrite.nix, omacalc.nix and omacut.nix: the fourth
  # of the applications Omarchy writes itself, none of which nixpkgs carries.
  # Available through programs.nixarchy.apps.aether rather than added to the
  # preinstalls, because a Wails binary is not something to give every machine
  # whether or not anyone asked for it.
  #
  # Unlike its three siblings this is not a shell script or a small Qt program:
  # a Go backend and a Svelte frontend compiled into one binary and rendered
  # through webkitgtk, so there are two dependency graphs to pin.

  vendorHash = "sha256-0cNNFCI/hFYM/BmuHEDDunKf7byj8JCb0lRElsWWaT0=";

  nativeBuildInputs = [
    nodejs
    wails
    pkg-config
    copyDesktopItems
    wrapGAppsHook3
  ];

  buildInputs = [
    webkitgtk_4_1
    gtk3
  ];

  # -m skips the `go mod tidy` wails runs first. Tidy resolves the imports of
  # every package including test-only ones, which vendor/ deliberately does not
  # contain, so it fails on golang.org/x/image/font -- imported by a _test.go
  # file that is never built here. The module graph is already pinned by
  # vendorHash; re-tidying it in a sandbox could only fail or change the pin.
  #
  # -skipbindings because the binding generator cannot run in a sandbox: it
  # invokes `go list` from a scratch directory of its own, outside the source
  # tree, so the vendor/ that buildGoModule provides is not visible and every
  # import fails with "module lookup disabled by GOPROXY=off" -- a network
  # error, from the one step that needs a network.
  #
  # Nothing is lost: upstream commits the generated bindings at
  # frontend/wailsjs/{go,runtime}, and they are generated from the Go source of
  # this same tag, so regenerating them here could only reproduce them. The
  # frontend derivation above has already compiled against them.
  #
  # -s skips wails' own `npm install && npm run build`, which cannot run here:
  # the sandbox has no network and npm would want one. The finished dist/ from
  # the derivation above is dropped in its place first.
  #
  # -tags webkit2_41 matches what upstream's Makefile computes:
  #
  #   WEBKIT_TAGS := $(shell pkg-config --exists webkit2gtk-4.0 || echo "-tags webkit2_41")
  #
  # nixpkgs carries webkitgtk_4_1 and not the 4.0 series, so the tag is always
  # required here. Hardcoded rather than computed, because a silently-absent
  # tag builds against an API that is not present and fails deep inside cgo.
  buildPhase = ''
    # Upstream does not commit frontend/dist, and main.go embeds it with
    # `//go:embed all:frontend/dist`. The finished dist from the derivation
    # above goes in before wails is asked to skip building it.
    #
    # Inline rather than in preBuild, because buildPhase is replaced here and
    # preBuild is a hook OF the phase being replaced -- it would never run, and
    # the build would still succeed: wails creates an empty frontend/dist when
    # one is missing, so the binary links, installs, and opens a blank window.
    # That is exactly the failure installCheckPhase below exists to catch.
    rm -rf frontend/dist
    cp -r ${frontend} frontend/dist
    chmod -R u+w frontend/dist

    wails build -s -m -skipbindings -tags webkit2_41 -o ${pname}
    runHook postBuild
  '';

  # buildGoModule's checkPhase calls getGoDirs, a shell function its buildPhase
  # defines -- and buildPhase is replaced above, so the function does not exist
  # and the phase prints "getGoDirs: command not found" and passes. A check that
  # cannot fail is worse than no check, so it is turned off and said out loud:
  # the tests import golang.org/x/image/font, which vendor/ does not carry
  # because it is a test-only dependency, so they could not run here regardless.
  doCheck = false;

  installPhase = ''
    runHook preInstall
    install -Dm755 build/bin/${pname} $out/bin/${pname}

    # The desktop item below names icon = "aether", which resolves to nothing
    # unless a file of that name is in the icon theme -- the entry would show
    # a generic placeholder in the launcher. Upstream's Makefile installs
    # assets/aether-icon-512.png; so does this.
    install -Dm644 assets/aether-icon-512.png \
      $out/share/icons/hicolor/512x512/apps/${pname}.png
    runHook postInstall
  '';

  # The one failure this package can have that still exits 0.
  #
  # go:embed writes the embedded file's path into the binary, so a build that
  # embedded the real dist contains "frontend/dist/index.html" and one that
  # embedded wails' empty placeholder does not. The first build here passed
  # every phase, produced a 20M ELF linked against webkit, and had nothing
  # inside it -- an app that starts and shows a white rectangle.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # -r over bin/, not the binary by name: wrapGAppsHook3 has already run by
    # installCheck time, so $out/bin/${pname} is a wrapper script and the ELF is
    # the hidden .${pname}-wrapped beside it.
    grep -qra "frontend/dist/index.html" $out/bin || {
      echo "ERROR: the frontend was not embedded; the window would be blank"
      exit 1
    }
    runHook postInstallCheck
  '';

  # Upstream's Makefile writes one into ~/.local/share/applications at install
  # time. A package cannot do that, so it is built here -- the same thing
  # pkgs/apps/omacalc.nix does, for the same reason.
  desktopItems = [
    (makeDesktopItem {
      name = pname;
      exec = pname;
      icon = pname;
      desktopName = "Aether";
      comment = "Native Omarchy theming";
      categories = [
        "Utility"
        "Settings"
      ];
    })
  ];

  passthru.updateScript = writeShellApplication {
    name = "update-aether";
    runtimeInputs = [ nix-update ];
    text = "nix-update aether";
  };

  meta = {
    description = "Native Omarchy theming made easy";
    homepage = "https://github.com/omacom/aether";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = lib.platforms.linux;
    broken = !stdenv.hostPlatform.isLinux;
  };
}
