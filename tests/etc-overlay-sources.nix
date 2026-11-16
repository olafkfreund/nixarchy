{ inputs, pkgs, ... }:
let
  inherit (pkgs) lib;
  cfg = inputs.self.nixosConfigurations.reference.config;
  pkg = cfg.programs.nixarchy.package;
  prefix = "${pkg}/share/omarchy/etc/";
  sources = lib.filterAttrs (_: row: lib.hasPrefix prefix (toString row.source)) cfg.environment.etc;
in
assert lib.assertMsg (sources != { }) "etc-overlay-sources: no installed /etc sources found";
pkgs.runCommand "nixarchy-etc-overlay-sources" { } ''
  fail=0
  check() {
    echo "etc-overlay-sources: /etc/$1 -> $2"
    if [ ! -e "$2" ]; then
      echo "FAIL: /etc/$1 source is missing: $2" >&2
      fail=1
    fi
  }
  ${lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: row: ''
      check ${lib.escapeShellArg name} ${lib.escapeShellArg (toString row.source)}
    '') sources
  )}
  [ "$fail" -eq 0 ] || exit 1
  touch "$out"
''
