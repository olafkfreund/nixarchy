{
  lib,
  fetchFromGitHub,
  cmake,
  mkHyprlandPlugin,
  nix-update,
  writeShellApplication,
}:
mkHyprlandPlugin (finalAttrs: {
  pluginName = "omarchy-hyprland-titlebars";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omarchy-hyprland-titlebars";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Y1fZCyhTxCb3x7xJ2TSmVN5bKZY+u+ObjYe76/yoj5k=";
  };

  nativeBuildInputs = [ cmake ];

  # CMakeLists installs titlebars.so to lib/omarchy-hyprland-titlebars/, the
  # directory the tree's workspace-modes.lua is rewritten to load from.
  postInstall = ''
    install -Dm644 -t $out/share/licenses/omarchy-hyprland-titlebars \
      $src/LICENSE $src/LICENSE.MIT
  '';

  passthru.updateScript = writeShellApplication {
    name = "update-omarchy-hyprland-titlebars";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "omarchy-hyprland-titlebars: run from the repo root" >&2; exit 1; }
      nix-update --flake omarchy-hyprland-titlebars
    '';
  };

  meta = {
    description = "Titlebars for Omarchy's floating workspace mode, a Hyprland plugin";
    homepage = "https://github.com/omacom/omarchy-hyprland-titlebars";
    # A fork of hyprbars (BSD-3-Clause); Omarchy's changes are MIT.
    license = with lib.licenses; [
      bsd3
      mit
    ];
    platforms = lib.platforms.linux;
  };
})
