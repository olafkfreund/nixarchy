{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
  ffmpeg,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omacut";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omacut";
    tag = "v${finalAttrs.version}";
    hash = "sha256-g6xtaj6XSkP4B49H6McLQXV2pK9y0i2MwSF8R341mxw=";
  };

  # Third of the four applications Omarchy writes itself; see
  # pkgs/apps/omawrite.nix for why they are packaged here and why none of them
  # joins programs.nixarchy.preinstalls.
  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
  ];

  # One module more than its siblings: omacut.pro asks for multimedia, for the
  # video preview it trims against.
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtmultimedia
  ];

  # ffmpeg is a runtime dependency, not a build one -- upstream's PKGBUILD puts
  # it in depends= rather than makedepends=, because the app shells out to it to
  # do the actual cut. Left off PATH it builds, installs, launches, previews the
  # video, and then fails at the one thing it exists for. Wrapped rather than
  # added to the module's systemPackages: nothing a user types needs ffmpeg
  # here, only this binary does.
  qtWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ ffmpeg ]}" ];

  installPhase = ''
    runHook preInstall

    install -Dm755 omacut $out/bin/omacut
    install -Dm644 $src/pkgbuild/omacut.desktop \
      $out/share/applications/omacut.desktop
    install -Dm644 $src/pkgbuild/omacut.svg \
      $out/share/icons/hicolor/scalable/apps/omacut.svg

    runHook postInstall
  '';

  meta = {
    description = "Cut a video to the right trim, built with Qt Quick";
    homepage = "https://github.com/omacom/omacut";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omacut";
  };
})
