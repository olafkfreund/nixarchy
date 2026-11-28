{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  pkg-config,
  glib,
  zlib,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "folio";
  version = "0.7.5";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "folio";
    tag = "v${finalAttrs.version}";
    hash = "sha256-VOLVGgpqnaYuVmDlHOQCTrRff4sOfRA7msDD89ZkYGE=";
  };

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
    pkg-config
  ];

  # find_package(Qt6 Core Gui Qml Quick QuickControls2 DBus Concurrent Test),
  # gio-2.0/gio-unix-2.0 and zlib. imageformats, multimedia and wayland are
  # runtime plugins (previews).
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtimageformats
    qt6.qtmultimedia
    qt6.qtwayland
    glib
    zlib
  ];

  # Since 0.7, `cmake --install` puts everything where a package does: the
  # plugin path is compiled from CMAKE_INSTALL_FULL_DATADIR, and the D-Bus
  # services (the file chooser and FileManager1) name $out/bin/folio.

  # The plugin path is compiled in as a QStringLiteral (UTF-16), so a build that
  # missed CMAKE_INSTALL_FULL_DATADIR would look for /usr/share/folio/plugins.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    [ -d "$out/share/folio/plugins" ] || { echo "folio: no bundled plugins" >&2; exit 1; }
    # The path is ASCII, so its UTF-16LE form is each byte followed by 00.
    want=$(printf '%s' "$out/share/folio/plugins" | od -An -tx1 -v | tr -s ' \n' ' ' | sed 's/ \([0-9a-f][0-9a-f]\)/\100/g; s/ //g')
    od -An -tx1 -v "$out/bin/.folio-wrapped" | tr -d ' \n' > binary.hex
    grep -qF "$want" binary.hex || {
      echo "folio: the binary does not name $out/share/folio/plugins" >&2
      exit 1
    }
    runHook postInstallCheck
  '';

  # nix-update-script is a list that only works under nixpkgs' update.nix;
  # `nix run .#update` calls getExe on every updateScript, as for owe.
  passthru.updateScript = writeShellApplication {
    name = "update-folio";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "folio: run from the repo root" >&2; exit 1; }
      nix-update --flake folio
    '';
  };

  meta = {
    description = "Omarchy's file manager: quiet, keyboard-first, and following the theme";
    homepage = "https://github.com/omacom/folio";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "folio";
  };
})
