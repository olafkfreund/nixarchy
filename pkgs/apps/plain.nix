{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "plain";
  version = "0.4.2";

  src = fetchFromGitHub {
    # CMake reads the version from the source directory's name (plain-<version>).
    name = "plain-${finalAttrs.version}";
    owner = "omacom";
    repo = "plain";
    tag = "v${finalAttrs.version}";
    hash = "sha256-q6CgaS0pO2Hx7jcET9+cePSpaemlzD8c89wQekZfqno=";
  };

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
  ];

  # find_package(Qt6 Core Gui Qml Quick QuickControls2 DBus Network Test);
  # qtwayland is the platform plugin.
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland
  ];

  # Since 0.4 it builds with CMake, which has no install rules; the cmake hook
  # builds in build/, so the sources are one level up.
  installPhase = ''
    runHook preInstall

    install -Dm755 plain $out/bin/plain
    install -Dm644 ../pkgbuild/plain.desktop $out/share/applications/plain.desktop
    install -Dm644 ../pkgbuild/plain.svg $out/share/icons/hicolor/scalable/apps/plain.svg
    install -Dm644 ../LICENSE $out/share/licenses/plain/LICENSE

    runHook postInstall
  '';

  # The version is read from the source directory's name; a fetch that unpacks
  # under another name builds a plain that calls itself "dev".
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    version=$(QT_QPA_PLATFORM=offscreen "$out/bin/plain" --version)
    [[ $version == "plain ${finalAttrs.version}" ]] || {
      echo "plain: --version printed '$version', not plain ${finalAttrs.version}" >&2
      exit 1
    }
    runHook postInstallCheck
  '';

  # nix-update-script is a list that only works under nixpkgs' update.nix;
  # `nix run .#update` calls getExe on every updateScript, as for owe.
  passthru.updateScript = writeShellApplication {
    name = "update-plain";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "plain: run from the repo root" >&2; exit 1; }
      nix-update --flake plain
    '';
  };

  meta = {
    description = "Omarchy's text editor for config and text files";
    homepage = "https://github.com/omacom/plain";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "plain";
  };
})
