{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omawrite";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omawrite";
    tag = "v${finalAttrs.version}";
    hash = "sha256-yS3GOL/kc03qx4naWzUdSZwAYxMuCjvrgmhexpwjsfA=";
  };

  # One of the four applications Omarchy writes itself and installs as a
  # preinstall. nixpkgs carries none of them, which is why modules/nixos.nix
  # lists omawrite among the preinstalls it cannot reproduce. Built here so it
  # is at least available to anyone who wants it.
  #
  # Not added to the preinstall set: upstream installs it by default, but a
  # NixOS user who never asked for a Markdown editor should not get one from a
  # desktop port. Enable programs.nixarchy.apps.omawrite for it.
  nativeBuildInputs = [
    qt6.qmake
    qt6.wrapQtAppsHook
  ];

  # QT += ... in omawrite.pro: core gui widgets printsupport dbus come from
  # qtbase; qml quick quickcontrols2 quickdialogs2 from qtdeclarative.
  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
  ];

  # Upstream's bin/build is qmake + make with no arguments, which is what the
  # qmake hook already does. Running their script instead would need a writable
  # $ROOT/build and buy nothing.
  #
  # Fonts are compiled in through src/resources.qrc, so nothing has to be
  # installed beside the binary for them -- the PKGBUILD copies fonts/OFL.txt
  # only as a licence.
  installPhase = ''
    runHook preInstall

    install -Dm755 omawrite $out/bin/omawrite
    install -Dm644 $src/pkgbuild/omawrite.desktop \
      $out/share/applications/omawrite.desktop
    install -Dm644 $src/pkgbuild/omawrite.svg \
      $out/share/icons/hicolor/scalable/apps/omawrite.svg

    runHook postInstall
  '';

  # Found and run by `nix run .#update` (see .#update.pinned in flake.nix).
  #
  # Unlike once's and hey-cli's hand-rolled fetch-and-sed, this delegates to
  # nix-update: the pin is a plain GitHub tag plus a source hash, exactly the
  # case it handles structurally. It rewrites version and hash by nix position
  # rather than by grepping a release manifest, so there is no pattern to
  # anchor and nothing for upstream growing a new file beside its artefacts to
  # collide with -- which is how hey-cli's updater broke on 1.4.1's SBOMs.
  # once and hey-cli keep their own scripts on purpose: their hashes come from
  # upstream's signed checksums.txt, a provenance nix-update cannot give.
  #
  # Proven by winding version back to 0.4.0 and watching it restore the exact
  # committed hash for 0.5.0. Its siblings (omacalc, omacut, ttfx) carry the
  # same script and point here.
  passthru.updateScript = writeShellApplication {
    name = "update-omawrite";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "omawrite: run from the repo root" >&2; exit 1; }
      nix-update --flake omawrite
    '';
  };

  meta = {
    description = "Dead-simple Markdown writing app built with Qt Quick";
    homepage = "https://github.com/omacom/omawrite";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omawrite";

    # The PKGBUILD also depends on xdg-desktop-portal, for the file dialogs
    # quickdialogs2 opens. That is a system service on NixOS (xdg.portal), not
    # something to put in buildInputs, and Omarchy's own module already enables
    # one -- so it is named here rather than depended on.
    longDescription = ''
      File dialogs go through xdg-desktop-portal. Nixarchy's session enables a
      portal already; on a machine without one, the app runs but Open and Save
      do nothing.
    '';
  };
})
