{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  makeFontsConf,
  mesa,
  libglvnd,
  bash,
  xvfb-run,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "checkmate";
  version = "0.1.4";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "checkmate";
    tag = "v${finalAttrs.version}";
    hash = "sha256-90LJx6Sp5L++YpflMqTr01SGQOSEhcN0PQPtKpSQlY8=";
  };

  postUnpack = ''
    mv source checkmate-${finalAttrs.version}
    sourceRoot=checkmate-${finalAttrs.version}
  '';

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
    xvfb-run
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtquick3d
    qt6.qtsvg
  ];

  # The suite writes a fake hyprctl with a /bin/bash shebang, absent in the sandbox.
  postPatch = ''
    substituteInPlace tests/checkmate_tests.cpp \
      --replace-fail '#!/bin/bash' '#!${lib.getExe bash}'
  '';

  # The suite renders the real Main.qml under xvfb-run with software GL.
  doCheck = true;
  nativeCheckInputs = [ mesa ];
  preCheck = ''
    export HOME=$TMPDIR
    export FONTCONFIG_FILE=${makeFontsConf { fontDirectories = [ ]; }}
    export QML2_IMPORT_PATH=${qt6.qtdeclarative}/${qt6.qtbase.qtQmlPrefix}:${qt6.qtquick3d}/${qt6.qtbase.qtQmlPrefix}
    export LD_LIBRARY_PATH=${
      lib.makeLibraryPath [
        libglvnd
        mesa
      ]
    }
    export LIBGL_DRIVERS_PATH=${mesa}/lib/dri
    export __EGL_VENDOR_LIBRARY_FILENAMES=${mesa}/share/glvnd/egl_vendor.d/50_mesa.json
  '';

  passthru.updateScript = writeShellApplication {
    name = "update-checkmate";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "checkmate: run from the repo root" >&2; exit 1; }
      nix-update --flake checkmate
    '';
  };

  meta = {
    description = "3D chess for Omarchy";
    homepage = "https://github.com/omacom/checkmate";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "checkmate";
  };
})
