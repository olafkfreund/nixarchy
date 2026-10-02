{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  cmake,
  wayland-scanner,
  makeWrapper,
  python3,
  mpv-unwrapped,
  ffmpeg,
  wayland,
  wayland-protocols,
  libglvnd,
  libepoxy,
  systemd,
  qt6,
  socat,
  nix-update-script,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "owe";
  version = "0.2.8";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "owe";
    tag = "v${finalAttrs.version}";
    hash = "sha256-2GfzL66OQ2r7UwBQ09dSFW2pw6wH84+m1VsBBvyxIaA=";
  };

  # No binary here is a Qt app -- owed/owe-render/owe/owe-idle are plain
  # Wayland/mpv clients. The Qt bits are the LockFeed QML plugin, a library
  # loaded by the shell's own Qt process, so there is nothing for
  # wrapQtAppsHook to wrap.
  dontWrapQtApps = true;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    cmake
    wayland-scanner
    makeWrapper
  ];

  nativeCheckInputs = [
    python3
  ];

  buildInputs = [
    mpv-unwrapped
    ffmpeg
    wayland
    wayland-protocols
    libglvnd
    libepoxy
    systemd
    qt6.qtbase
    qt6.qtdeclarative
  ];

  doCheck = true;

  # "daemon" (test/daemon.py) starts owed for real and waits for it to spawn
  # owe-render, which needs a live Wayland display -- there is none in the
  # sandbox, so supervisor.c's spawn fails and the test times out waiting for
  # a socket that never appears. "egl-context" and "transition" already
  # self-skip (meson reports them SKIP, exit 77) for the same reason. meson
  # defines no suites, so this is an allowlist: a test a later owe adds does
  # NOT run until it is named here. Diff test/meson.build on every bump.
  mesonCheckFlags = [
    "ipc-clients"
    "egl-context"
    "wayland-lifecycle"
    "render-feed"
    "unit"
    "supervisor"
    "power"
    "feed"
    "lock-policy"
    "benchmark"
    "uninstall"
    "transition"
    "media"
    "decode"
    "regression"
  ];

  # CARRIED (#1153): owed gave owe-render 1 s to open its socket, then killed
  # it and retried 30 s later. Under software GL (llvmpipe) start-up takes about
  # 1.3 s, so a VM, or a slow first start, never got a renderer at all.
  postPatch = ''
    substituteInPlace src/daemon/supervisor.c \
      --replace-fail 'while (waited < 1000) {' 'while (waited < 10000) {'
  '';

  # The qml-plugin/ subtree is a second, separate CMake project (the LockFeed
  # QML module) that meson does not build. Configured and built here, into its
  # own directory, and installed in postInstall below. mesonBuildPhase leaves
  # the cwd at the "build" dir it created inside the source root, one level
  # below qml-plugin/ -- hence "../qml-plugin".
  postBuild = ''
    cmake -S ../qml-plugin -B qml-plugin-build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=${placeholder "out"} \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_TESTING=ON
    cmake --build qml-plugin-build
  '';

  postCheck = ''
    ctest --test-dir qml-plugin-build --output-on-failure
  '';

  postInstall = ''
    cmake --install qml-plugin-build

    # cmake installs the QML module under lib/qt6/qml regardless of this
    # Qt's actual qtQmlPrefix; move it there if the two differ.
    builtQml=$out/lib/qt6/qml
    wantQml=$out/${qt6.qtbase.qtQmlPrefix}
    if [ "$builtQml" != "$wantQml" ] && [ -d "$builtQml" ]; then
      mkdir -p "$(dirname "$wantQml")"
      mv "$builtQml" "$wantQml"
      rmdir --ignore-fail-on-non-empty "$(dirname "$builtQml")" 2>/dev/null || true
    fi

    install -Dm755 ../hooks/owe-idle $out/bin/owe-idle
    install -Dm755 ../hooks/theme-set.d/10-owe-sync $out/share/owe/10-owe-sync
    install -Dm644 ../config/config.toml $out/share/doc/owe/config.toml.example

    # Both hooks shell out to socat by bare name; pin it to the store so it
    # resolves regardless of the caller's PATH.
    substituteInPlace $out/share/owe/10-owe-sync $out/bin/owe-idle \
      --replace-fail 'socat -' '${socat}/bin/socat -'

    wrapProgram $out/bin/owed --prefix PATH : ${lib.makeBinPath [ ffmpeg ]}
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    for bin in owed owe-render owe owe-idle; do
      [ -x "$out/bin/$bin" ] || {
        echo "owe: $out/bin/$bin missing or not executable" >&2
        exit 1
      }
    done

    [ -f "$out/${qt6.qtbase.qtQmlPrefix}/Owe/LockFeed/qmldir" ] || {
      echo "owe: $out/${qt6.qtbase.qtQmlPrefix}/Owe/LockFeed/qmldir missing" >&2
      exit 1
    }

    version=$("$out/bin/owe" --version)
    [[ $version == *0.2.8* ]] || {
      echo "owe: owe --version did not report 0.2.8" >&2
      exit 1
    }

    runHook postInstallCheck
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Video and GIF desktop backgrounds and a lock-screen video feed for Omarchy";
    homepage = "https://github.com/omacom/owe";
    # Upstream carries no LICENSE file; the PKGBUILD declares MIT.
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "owe";
  };
})
