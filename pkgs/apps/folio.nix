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
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "folio";
    tag = "v${finalAttrs.version}";
    hash = "sha256-EYOdr8DiE06aF8he1kGzK0n7Nhal67kN7f6sX/D2U0g=";
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

  # The packaged plugins live in the store, not /usr/share/folio/plugins.
  postPatch = ''
    substituteInPlace src/plugins.cpp \
      --replace-fail '"/usr/share/folio/plugins"' "\"$out/share/folio/plugins\""
  '';

  # Upstream's CMakeLists has no install rules; this installs what its
  # packaging does, plus the file-chooser portal (#1793).
  installPhase = ''
    runHook preInstall

    install -Dm755 folio $out/bin/folio
    install -Dm644 ../share/folio.desktop $out/share/applications/folio.desktop
    install -Dm644 ../share/folio-chooser.desktop $out/share/applications/folio-chooser.desktop
    install -Dm644 ../share/folio.svg $out/share/icons/hicolor/scalable/apps/folio.svg
    install -Dm644 ../share/folio.portal $out/share/xdg-desktop-portal/portals/folio.portal
    install -Dm644 ../share/org.freedesktop.impl.portal.desktop.folio.service \
      $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.folio.service
    substituteInPlace $out/share/dbus-1/services/org.freedesktop.impl.portal.desktop.folio.service \
      --replace-fail "Exec=/usr/bin/folio" "Exec=$out/bin/folio"
    mkdir -p $out/share/folio
    cp -r ../plugins $out/share/folio/plugins
    install -Dm644 ../LICENSE $out/share/licenses/folio/LICENSE

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
