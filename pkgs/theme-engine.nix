{ inputs, pkgs }:
# Keep the engine on the consumer's package set, as the input's module does.
(pkgs.callPackage (inputs.nixarchy-omatheme + "/pkgs/hyprchroma.nix") {
  src = inputs.nixarchy-omatheme.inputs.omarchroma;
}).overrideAttrs
  (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace lib/sync-gtk-theme lib/sync-qt-kde-theme \
        --replace-fail /usr/share/icons /run/current-system/sw/share/icons
      substituteInPlace lib/sync-gtk-theme \
        --replace-fail /usr/share/themes /run/current-system/sw/share/themes
    '';
  })
