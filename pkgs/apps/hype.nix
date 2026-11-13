{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
  qt6,
  ffmpeg,
  # nixos-26.05 only has the old name; unstable warns on it (checks.stable-eval).
  source-highlight ? sourceHighlight,
  sourceHighlight ? null,
  zlib,
  libwebp,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "hype";
  version = "0.7.1";

  src = fetchFromGitHub {
    # CMakeLists reads HYPE_VERSION from a hype-<version> source dir, else git describe, else dev.
    name = "hype-${finalAttrs.version}";
    owner = "omacom";
    repo = "hype";
    tag = "v${finalAttrs.version}";
    hash = "sha256-LeON8trdFa2xlLkSnBDXkuXs2pL9wKzh/FQFay47+Rw=";
  };

  # Omarchy 4.5 default app, on through omarchyApps.enable, built like pkgs/apps/omawrite.nix.
  nativeBuildInputs = [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtmultimedia
    qt6.qtsvg
    qt6.qtimageformats
    zlib
    libwebp
  ];

  # ffmpeg/ffprobe and source-highlight are exec'd at runtime (PKGBUILD depends=).
  qtWrapperArgs = [
    "--prefix PATH : ${
      lib.makeBinPath [
        ffmpeg
        source-highlight
      ]
    }"
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 hype $out/bin/hype
    install -Dm644 $src/pkgbuild/hype.desktop \
      $out/share/applications/hype.desktop
    install -Dm644 $src/pkgbuild/hype.svg \
      $out/share/icons/hicolor/scalable/apps/hype.svg
    install -Dm644 $src/LICENSE $out/share/licenses/hype/LICENSE

    runHook postInstall
  '';

  # Same shape as omawrite's; the reasoning lives there.
  passthru.updateScript = writeShellApplication {
    name = "update-hype";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "hype: run from the repo root" >&2; exit 1; }
      nix-update --flake hype
    '';
  };

  meta = {
    description = "Simple Markdown presentations with a visual slide editor";
    homepage = "https://github.com/omacom/hype";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hype";
  };
})
