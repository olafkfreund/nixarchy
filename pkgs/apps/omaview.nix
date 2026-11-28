{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  pkg-config,
  wayland,
  wayland-protocols,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omaview";
  version = "0.1.2";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omaview";
    tag = "v${finalAttrs.version}";
    hash = "sha256-+ZuJPfMCNDM2UT1+fXPCu9IAw3pn0HLzTJVa5MQ2SNs=";
  };

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
    pkg-config
  ];

  # find_package(Qt6 ... Multimedia DBus Concurrent Test) and wayland-client;
  # imageformats and wayland are runtime plugins (HEIF, AVIF, JXL pictures).
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtmultimedia
    qt6.qtimageformats
    qt6.qtwayland
    wayland
    wayland-protocols
  ];

  # nix-update-script is a list that only works under nixpkgs' update.nix;
  # `nix run .#update` calls getExe on every updateScript, as for folio.
  passthru.updateScript = writeShellApplication {
    name = "update-omaview";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "omaview: run from the repo root" >&2; exit 1; }
      nix-update --flake omaview
    '';
  };

  meta = {
    description = "Omarchy's picture viewer and media player";
    homepage = "https://github.com/omacom/omaview";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omaview";
  };
})
