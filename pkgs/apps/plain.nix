{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "plain";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "plain";
    tag = "v${finalAttrs.version}";
    hash = "sha256-KQzTyjH+LgU/gmFoSxAeC4msF+CsG1ttglNhnit2yV0=";
  };

  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
  ];

  # QT += core gui qml quick quickcontrols2 dbus; qtwayland is the platform plugin.
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtwayland
  ];

  # Upstream's bin/build runs qmake in build/; the nixpkgs qmake hook builds in
  # the source root, so the binary (TARGET = plain) is here, not in build/.
  installPhase = ''
    runHook preInstall

    install -Dm755 plain $out/bin/plain
    install -Dm644 pkgbuild/plain.desktop $out/share/applications/plain.desktop
    install -Dm644 pkgbuild/plain.svg $out/share/icons/hicolor/scalable/apps/plain.svg
    install -Dm644 LICENSE $out/share/licenses/plain/LICENSE

    runHook postInstall
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
