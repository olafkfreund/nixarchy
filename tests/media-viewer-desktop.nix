{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  pkg = inputs.self.nixosConfigurations.reference.config.programs.nixarchy.package;
  desktop = pkg.passthru.mediaViewerDesktop or null;
in
pkgs.runCommand "nixarchy-media-viewer-desktop" { } (
  if desktop == null then
    ''
      echo "media-viewer-desktop: no media viewer desktop declared"
      touch "$out"
    ''
  else
    ''
      desktop=${lib.escapeShellArg desktop}
      found=0
      for dep in ${
        lib.concatMapStringsSep " " (d: lib.escapeShellArg (toString d)) pkg.passthru.runtimeDeps
      }; do
        path="$dep/share/applications/$desktop"
        echo "media-viewer-desktop: looking for $path"
        if [ -e "$path" ]; then found=1; fi
      done
      if [ "$found" -ne 1 ]; then
        echo "FAIL: $desktop is absent from every runtimeDeps share/applications directory" >&2
        exit 1
      fi
      touch "$out"
    ''
)
