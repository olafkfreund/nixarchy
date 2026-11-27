{
  pkgs,
  reference,
  omarchySource,
}:
let
  rules = reference.config.environment.etc."udev/rules.d".source;
  expected = builtins.pathExists "${
    reference.config.programs.nixarchy.package.src or omarchySource
  }/default/udev/shure-mv7plus.rules";
in
pkgs.runCommand "nixarchy-mv7plus-udev" { inherit rules; } ''
  rule="$rules/62-shure-mv7plus.rules"
  if [ "${if expected then "1" else "0"}" = 1 ]; then
    test -f "$rule" || { echo "MV7+ udev rule missing from reference system" >&2; exit 1; }
    grep -q 'SUBSYSTEM=="hidraw".*ATTRS{idVendor}=="14ed".*ATTRS{idProduct}=="1019".*TAG+="uaccess"' "$rule" || {
      echo "MV7+ udev rule does not grant active-session access" >&2
      exit 1
    }
  elif [ -e "$rule" ]; then
    echo "MV7+ udev rule appeared on a pin without it" >&2
    exit 1
  fi
  touch "$out"
''
