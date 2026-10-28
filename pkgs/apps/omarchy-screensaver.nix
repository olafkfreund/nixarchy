{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  makeWrapper,
  libxkbcommon,
  wayland,
  fontconfig,
  nix-update,
  writeShellApplication,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "omarchy-screensaver";
  version = "1.3.1";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omarchy-screensaver";
    tag = "v${finalAttrs.version}";
    hash = "sha256-9uvcYUXPExFEUZq2VdvSZz6n2foqiPqyD9CMphgBCTw=";
  };

  cargoHash = "sha256-GnXuI+ceJpNz9npfLE9KpoQHU7MgYD9SnUKgNwfmTgM=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];
  buildInputs = [
    libxkbcommon
    wayland
  ];

  # The /usr/share/fonts lookup cannot work on NixOS, so fc-match must be on PATH.
  postFixup = ''
    wrapProgram $out/bin/omarchy-launch-screensaver --prefix PATH : ${lib.makeBinPath [ fontconfig ]}
  '';

  passthru.updateScript = writeShellApplication {
    name = "update-omarchy-screensaver";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "omarchy-screensaver: run from the repo root" >&2; exit 1; }
      nix-update --flake omarchy-screensaver
    '';
  };

  meta = {
    description = "Omarchy's native Wayland screensaver";
    homepage = "https://github.com/omacom/omarchy-screensaver";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omarchy-launch-screensaver";
  };
})
