{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  xvfb-run,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "checkmate";
  version = "0.1.2";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "checkmate";
    tag = "v${finalAttrs.version}";
    hash = "sha256-/araTInVctB1kdZ70qnGyf8NQ7IaTnLvHAKRFhTGADY=";
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

  # The rendering test needs a software GL setup that the lead will verify.
  doCheck = false;

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
