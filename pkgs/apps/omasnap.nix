{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  wayland-scanner,
  wayland-protocols,
  wayland,
  libdeflate,
  qt6,
  kdePackages,
  tesseract,
  wl-clipboard,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omasnap";
  version = "1.21.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omasnap";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kpoPb5F5yqcczBRUfENsEfv+BD67zQsTG9Ur6Bi3viE=";
  };

  # Omarchy's screenshot tool from quattro on: omarchy-capture-screenshot,
  # omarchy-clipboard-open and imv's edit binding all exec it by name (#1278).
  # CMakeLists names its protocol XMLs by Arch path.
  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail /usr/share/wayland-protocols ${wayland-protocols}/share/wayland-protocols
  '';

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    wayland-scanner
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
    kdePackages.layer-shell-qt
    wayland
    libdeflate
  ];

  # OCR and the clipboard are exec'd, not linked: upstream's depends= carries
  # them, and without them on PATH those two actions fail at the click.
  qtWrapperArgs = [
    "--prefix PATH : ${
      lib.makeBinPath [
        tesseract
        wl-clipboard
      ]
    }"
  ];

  meta = {
    description = "Omarchy's screenshot, annotation and OCR tool";
    homepage = "https://github.com/omacom/omasnap";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omasnap";
  };
})
