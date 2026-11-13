{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  pkg-config,
  ffmpeg,
  libjpeg_turbo,
  libpulseaudio,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "monologue";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "monologue";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ItL5WqPYJo7gr6uSd9FHVFbvtnJE51tUR4EXVCFeLk4=";
  };

  # Omarchy 4.5 default app, on through omarchyApps.enable, built like pkgs/apps/omawrite.nix.
  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
    pkg-config
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtmultimedia
    libjpeg_turbo
    libpulseaudio
  ];

  # ffmpeg/ffprobe are exec'd at runtime (PKGBUILD depends=).
  qtWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ ffmpeg ]}" ];

  installPhase = ''
    runHook preInstall

    install -Dm755 monologue $out/bin/monologue
    install -Dm644 $src/pkgbuild/monologue.desktop \
      $out/share/applications/monologue.desktop
    install -Dm644 $src/pkgbuild/monologue.svg \
      $out/share/icons/hicolor/scalable/apps/monologue.svg
    install -Dm644 $src/LICENSE $out/share/licenses/monologue/LICENSE

    runHook postInstall
  '';

  # Same shape as omawrite's; the reasoning lives there.
  passthru.updateScript = writeShellApplication {
    name = "update-monologue";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "monologue: run from the repo root" >&2; exit 1; }
      nix-update --flake monologue
    '';
  };

  meta = {
    description = "A simple, theme-synced webcam recorder for Omarchy";
    homepage = "https://github.com/omacom/monologue";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "monologue";
  };
})
