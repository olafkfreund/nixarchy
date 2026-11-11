{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
  pkg-config,
  glib,
  zlib,
  libarchive,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "folio";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "folio";
    tag = "v${finalAttrs.version}";
    hash = "sha256-y1ZV9a5XlR4qCI/vdqzIkiTBDhXhhyMZAvcMnfmT4+8=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
    pkg-config
  ];

  # QT += core gui qml quick quickcontrols2 dbus concurrent; gio-2.0 via
  # pkg-config, -lz, libarchive per upstream's PKGBUILD. imageformats,
  # multimedia and wayland are runtime plugins. No WebEngine (optional PDF
  # previews).
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtimageformats
    qt6.qtmultimedia
    qt6.qtwayland
    glib
    zlib
    libarchive
  ];

  # Upstream's bin/build runs qmake in build/; the nixpkgs qmake hook builds in
  # the source root, so the binary (TARGET = folio) is here, not in build/.
  installPhase = ''
    runHook preInstall

    install -Dm755 folio $out/bin/folio
    install -Dm644 pkgbuild/folio.desktop $out/share/applications/folio.desktop
    install -Dm644 pkgbuild/folio.svg $out/share/icons/hicolor/scalable/apps/folio.svg
    install -Dm644 LICENSE $out/share/licenses/folio/LICENSE

    runHook postInstall
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
