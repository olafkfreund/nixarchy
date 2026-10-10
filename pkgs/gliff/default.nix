# Not in nixpkgs, and upstream ships no flake.nix, so `src` is a non-flake input.
# Why: docs/internals/flake.md#gliff-from-a-non-flake-input-pinned-to-a-tag
# vulkan-loader goes on the RUNPATH: ash dlopens libvulkan.so.1 by name, and
# without it gliff silently falls back to the CPU tier.
{
  lib,
  rustPlatform,
  src,
  pkg-config,
  nasm,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  libva,
  libdrm,
  libgbm,
  wayland,
  libxkbcommon,
  dbus,
  vulkan-loader,
  openssh,
}:
rustPlatform.buildRustPackage {
  pname = "gliff";
  version = "0.3.1";
  inherit src;
  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [
    pkg-config
    nasm
    wrapGAppsHook4
  ];
  buildInputs = [
    gtk4
    libadwaita
    libva
    libdrm
    libgbm
    wayland
    libxkbcommon
    dbus
    vulkan-loader
  ];

  doCheck = true;
  dontWrapGApps = true;

  postInstall = ''
    install -Dm644 pkgbuild/gliff.desktop -t $out/share/applications
    install -Dm644 pkgbuild/gliff.svg -t $out/share/icons/hicolor/scalable/apps
  '';

  postFixup = ''
    for b in gliff gliff-server gliff-probe; do
      patchelf --add-rpath ${lib.makeLibraryPath [ vulkan-loader ]} $out/bin/$b
    done
    wrapGApp $out/bin/gliff --prefix PATH : ${lib.makeBinPath [ openssh ]}
  '';

  meta = {
    description = "Remote desktop over SSH for Wayland";
    homepage = "https://github.com/omacom/gliff";
    license = with lib.licenses; [
      mit
      bsd2
    ];
    mainProgram = "gliff";
    platforms = [ "x86_64-linux" ];
  };
}
