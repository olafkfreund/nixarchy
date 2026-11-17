{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  makeFontsConf,
  bash,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "cards";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "cards";
    tag = "v${finalAttrs.version}";
    hash = "sha256-tOwGozKCQDBtB5Fm+BrYTIj2gPWniaPH5h898/Q0fsY=";
  };

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtsvg
  ];

  doCheck = true;

  # The suite writes a fake hyprctl with a /bin/bash shebang, absent in the sandbox.
  postPatch = ''
    substituteInPlace tests/cards_tests.cpp \
      --replace-fail '#!/bin/bash' '#!${lib.getExe bash}'
  '';

  # The suite loads the real Main.qml from the build tree, which the Qt wrapper
  # has not wrapped yet; fontconfig wants a writable cache.
  preCheck = ''
    export HOME=$TMPDIR
    export FONTCONFIG_FILE=${makeFontsConf { fontDirectories = [ ]; }}
    export QML2_IMPORT_PATH=${qt6.qtdeclarative}/${qt6.qtbase.qtQmlPrefix}
  '';

  passthru.updateScript = writeShellApplication {
    name = "update-cards";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "cards: run from the repo root" >&2; exit 1; }
      nix-update --flake cards
    '';
  };

  meta = {
    description = "Klondike solitaire for Omarchy";
    homepage = "https://github.com/omacom/cards";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "cards";
  };
})
