{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  pkg-config,
  kdePackages,
  qpdf,
  nss,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "signed";
  version = "0.3.2";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "signed";
    tag = "v${finalAttrs.version}";
    hash = "sha256-gTaHcPbmHrXbg8qWuWrSgprEyy34imRrQUFPK4uBh0A=";
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
    qt6.qtwayland
    kdePackages.poppler
    qpdf
  ];

  # certutil and pk12util are exec'd at runtime (PKGBUILD depends=nss).
  qtWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nss.tools ]}" ];

  installPhase = ''
    runHook preInstall

    install -Dm755 signed $out/bin/signed
    install -Dm644 $src/pkgbuild/signed.desktop \
      $out/share/applications/signed.desktop
    install -Dm644 $src/pkgbuild/signed.svg \
      $out/share/icons/hicolor/scalable/apps/signed.svg
    install -Dm644 $src/LICENSE $out/share/licenses/signed/LICENSE

    runHook postInstall
  '';

  # Same shape as omawrite's; the reasoning lives there.
  passthru.updateScript = writeShellApplication {
    name = "update-signed";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "signed: run from the repo root" >&2; exit 1; }
      nix-update --flake signed
    '';
  };

  meta = {
    description = "Sign PDFs and fill them in with text and dates";
    homepage = "https://github.com/omacom/signed";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "signed";
  };
})
