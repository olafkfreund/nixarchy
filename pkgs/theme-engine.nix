{ inputs, pkgs }:
# Keep the engine on the consumer's package set, as the input's module does.
(pkgs.callPackage (inputs.nixarchy-omatheme + "/pkgs/hyprchroma.nix") {
  src = inputs.nixarchy-omatheme.inputs.omarchroma;
}).overrideAttrs
  (old: {
    # Quiet: omatheme's own package makes this substitution from f1e93d76 on, and a
    # second, failing one stopped every host that pins it. theme-gnome-gtk checks the lookup.
    postPatch = (old.postPatch or "") + ''
      substituteInPlace lib/sync-gtk-theme lib/sync-qt-kde-theme \
        --replace-quiet /usr/share/icons /run/current-system/sw/share/icons
      substituteInPlace lib/sync-gtk-theme \
        --replace-quiet /usr/share/themes /run/current-system/sw/share/themes
    '';
  })
