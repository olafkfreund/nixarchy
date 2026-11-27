# The commands Omarchy's autostart runs at every login are on the system PATH,
# not only in a per-user profile (#1956). A fresh account the Home Manager seed
# had not reached logged in to `Command not found: "herdr"`, because only the
# herdr plugin installed it. Reads the shipped autostart.lua, so it holds for
# whichever Omarchy pin is built.
{ pkgs, ... }:
let
  inherit (pkgs) lib;
  omarchy = pkgs.nixarchy-omarchy or pkgs.omarchy;
  runtime = map lib.getName omarchy.passthru.runtimeDeps;
  isEdge = lib.hasPrefix "edge-" omarchy.version;
  # command autostart starts -> package that must provide it
  rows = {
    # v4.5.0 starts it; quattro (v4.6.0-rc1) no longer does.
    herdr = {
      package = "herdr";
      edge = "absent";
    };
  };
  gone = lib.filterAttrs (_: r: isEdge && r.edge or "" == "absent") rows;
  started = lib.mapAttrs (_: r: r.package) (removeAttrs rows (lib.attrNames gone));
  missing = lib.filter (c: !(lib.elem started.${c} runtime)) (lib.attrNames started);
in
pkgs.runCommand "nixarchy-autostart-runtime"
  {
    autostart = "${omarchy}/share/omarchy/default/hypr/autostart.lua";
    missing = lib.concatStringsSep " " missing;
  }
  ''
    for c in ${lib.concatStringsSep " " (lib.attrNames started)}; do
      grep -q "$c server" "$autostart" || { echo "autostart.lua no longer starts $c; drop its row" >&2; exit 1; }
    done
    for c in ${lib.concatStringsSep " " (lib.attrNames gone)}; do
      if grep -q "$c server" "$autostart"; then
        echo "autostart.lua starts $c again; its row says this pin does not" >&2
        exit 1
      fi
    done
    if [ -n "$missing" ]; then
      echo "autostart.lua starts these at every login, and the package does not ship them: $missing" >&2
      exit 1
    fi
    touch $out
  ''
