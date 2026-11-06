{ inputs, pkgs }:
let
  iso = inputs.self.nixosConfigurations.iso-net.config;
  sources = inputs.self.lib.inputSources { flake = inputs.self; };
  included = builtins.all (source: builtins.elem source iso.system.extraDependencies) sources;
  etc = iso.environment.etc;
in
pkgs.runCommand "nixarchy-iso-source"
  {
    inherit included;
    noOfflineMarker = !(builtins.hasAttr "nixarchy-iso" etc);
    noReferenceMarkers =
      !(builtins.hasAttr "nixarchy-reference-true" etc)
      && !(builtins.hasAttr "nixarchy-reference-false" etc);
    networkMarker = builtins.hasAttr "nixarchy-iso-net" etc;
  }
  ''
    [ "$included" = 1 ] || { echo "the image is missing inputSources" >&2; exit 1; }
    [ "$noOfflineMarker" = 1 ] || { echo "the offline image marker is present" >&2; exit 1; }
    [ "$noReferenceMarkers" = 1 ] || { echo "a reference marker is present" >&2; exit 1; }
    [ "$networkMarker" = 1 ] || { echo "the network marker is missing" >&2; exit 1; }
    touch $out
  ''
