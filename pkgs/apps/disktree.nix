{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  gcc-unwrapped,
  wayland,
  libxkbcommon,
  libxcb,
  libglvnd,
  vulkan-loader,
  fontconfig,
}:
let
  sources = {
    x86_64-linux = {
      arch = "x86_64";
      hash = "sha256-fnWvoig8i0+SkNUurb/ADZ8UwTrtLSJMzfD3gm/MBbI=";
    };
    aarch64-linux = {
      arch = "aarch64";
      hash = "sha256-PHX5yCBp5AMQyCE1elKu4vEanD4rRUUsmJPb98teRUo=";
    };
  };
  source = sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation (finalAttrs: {
  pname = "disktree";
  version = "0.11.0";

  src = fetchurl {
    url = "https://github.com/tobi/disktree/releases/download/v${finalAttrs.version}/disktree-${finalAttrs.version}-${source.arch}-linux.tar.gz";
    inherit (source) hash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    gcc-unwrapped.lib
    wayland
    libxkbcommon
    libxcb
    libglvnd
  ];

  # gpui dlopens its windowing and GPU libraries, which autoPatchelf cannot see
  # in the ELF's NEEDED list; runtimeDependencies puts them on the RUNPATH.
  runtimeDependencies = [
    wayland
    libxkbcommon
    libxcb
    libglvnd
    vulkan-loader
    fontconfig.lib
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 disktree $out/bin/disktree
    install -Dm644 disktree.svg \
      $out/share/icons/hicolor/scalable/apps/disktree.svg
    install -Dm644 LICENSE $out/share/licenses/disktree/LICENSE
    mkdir -p $out/share/applications
    sed -e "s|@BINDIR@|$out/bin|g" -e "s|@VERSION@|${finalAttrs.version}|g" \
      disktree.desktop.in > $out/share/applications/disktree.desktop

    runHook postInstall
  '';

  # Not nix-update: it cannot rewrite a per-architecture hash. To bump, change
  # version and both hashes above (the sha256s are in the AUR PKGBUILD
  # disktree-bin, as `nix hash convert --hash-algo sha256 --to sri <hex>`).
  meta = {
    description = "Disk usage explorer";
    homepage = "https://github.com/tobi/disktree";
    license = lib.licenses.mit;
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "disktree";
  };
})
