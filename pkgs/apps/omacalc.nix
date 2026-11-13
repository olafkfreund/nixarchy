{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  makeDesktopItem,
  copyDesktopItems,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omacalc";
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omacalc";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7VnysQdDX9I/a1hQZjcZlvLy9ioxeC4UDls/FSYIQtw=";
  };

  # Sibling of pkgs/apps/omawrite.nix, and the same reasoning: one of the four
  # applications Omarchy writes itself, none of which are in nixpkgs. Available
  # by default through omarchyApps.enable.
  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
    copyDesktopItems
  ];

  # Core, Gui, Qml, Quick, QuickControls2 and DBus in CMakeLists.txt -- qtbase
  # and qtdeclarative between them.
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
  ];

  # Upstream now ships pkgbuild/omacalc.desktop and .svg; this keeps its own
  # entry so the move to CMake changes no installed file. It has no Icon=,
  # because an entry naming a missing icon renders as a broken tile.
  desktopItems = [
    (makeDesktopItem {
      name = "omacalc";
      desktopName = "Omacalc";
      comment = "Calculator";
      exec = "omacalc";
      categories = [
        "Utility"
        "Calculator"
      ];
      keywords = [
        "calculator"
        "math"
      ];
    })
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 omacalc $out/bin/omacalc
    runHook postInstall
  '';

  # Same shape as omawrite's, and the reasoning lives there. One note of its
  # own: this repo has no GitHub releases, only tags -- nix-update still
  # resolves the newest (GitHub's releases.atom is fed by tags), proven by
  # winding version back to 0.2.1 and watching it restore 0.2.2's exact hash.
  passthru.updateScript = writeShellApplication {
    name = "update-omacalc";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "omacalc: run from the repo root" >&2; exit 1; }
      nix-update --flake omacalc
    '';
  };

  meta = {
    description = "Calculator built with Qt Quick, from the Omarchy family";
    homepage = "https://github.com/omacom/omacalc";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omacalc";
  };
})
