{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
  makeDesktopItem,
  copyDesktopItems,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omacalc";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omacalc";
    tag = "v${finalAttrs.version}";
    hash = "sha256-I+WxkMz/2hCf4OpJKu99+30c0CxyxFD0M6eSLFDLs1I=";
  };

  # Sibling of pkgs/apps/omawrite.nix, and the same reasoning: one of the four
  # applications Omarchy writes itself, none of which are in nixpkgs. Available
  # through programs.nixarchy.apps.omacalc rather than added to the preinstalls,
  # because upstream installing it by default is not a reason to put a
  # calculator on a machine that did not ask for one.
  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
    copyDesktopItems
  ];

  # QT += core gui qml quick quickcontrols2 dbus -- qtbase and qtdeclarative
  # between them. One module short of omawrite, which also pulls widgets,
  # printsupport and quickdialogs2.
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
  ];

  # Unlike omawrite, this repo ships no pkgbuild/ -- no .desktop, no icon, only
  # a screenshot. So the entry is written here. Without one the app installs as
  # a bare binary: nothing in the launcher, nothing in Omarchy's app menu, and
  # a GUI calculator you can start only from a terminal is not much of one.
  #
  # No Icon= because there is no icon to point at. An entry naming a missing
  # icon renders as a broken tile; one naming none falls back to the generic,
  # which looks deliberate.
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

  meta = {
    description = "Calculator built with Qt Quick, from the Omarchy family";
    homepage = "https://github.com/omacom/omacalc";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omacalc";
  };
})
