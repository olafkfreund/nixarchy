{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zstd,
  makeWrapper,
  python3,
  gtk4,
  gtk4-layer-shell,
  glib,
  cairo,
  gdk-pixbuf,
  graphene,
  libnotify,
  librsvg,
  libxkbcommon,
  wayland,
  alsa-lib,
  pipewire,
  libpulseaudio,
  vulkan-loader,
  openssl,
  zlib,
  fontconfig,
  freetype,
}:
let
  python = python3.withPackages (ps: [
    ps.pygobject3
    ps.pycairo
  ]);
in
stdenv.mkDerivation {
  pname = "superwhisper";
  version = "1.2.0";

  src = fetchurl {
    url = "https://github.com/superultrainc/superwhisper-linux-releases/releases/download/v1.2.0/superwhisper-linux-x86_64-1.2.0.tar.zst";
    hash = "sha256-KLxXWO1s9CRouX75QOwqlrEU5rbqA7yywEvGeIV9AvA=";
  };
  sourceRoot = "superwhisper-omarchy-x86_64-1.2.0";

  nativeBuildInputs = [
    autoPatchelfHook
    zstd
    makeWrapper
  ];
  buildInputs = [
    gtk4
    gtk4-layer-shell
    glib
    cairo
    gdk-pixbuf
    graphene
    libnotify
    librsvg
    libxkbcommon
    wayland
    alsa-lib
    pipewire
    libpulseaudio
    vulkan-loader
    openssl
    zlib
    zstd
    fontconfig
    freetype
    stdenv.cc.cc.lib
  ];

  # The fcitx5 plugin is loaded by fcitx5 itself, which brings these.
  autoPatchelfIgnoreMissingDeps = [
    "libFcitx5Core.so.7"
    "libFcitx5Utils.so.2"
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/superwhisper $out/bin
    cp -a . $out/share/superwhisper/
    makeWrapper $out/share/superwhisper/app/run.sh $out/bin/superwhisper \
      --prefix PATH : ${lib.makeBinPath [ python ]}
    runHook postInstall
  '';

  meta = {
    description = "Voice dictation for Linux";
    homepage = "https://superwhisper.com/linux";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "superwhisper";
  };
}
