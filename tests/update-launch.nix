{ inputs, pkgs }:
let
  probes = builtins.fromJSON (builtins.readFile ../data/update-launch.json);
  pinned = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.update.pinned;
in
assert pkgs.lib.assertMsg (
  builtins.attrNames probes == pinned
) "data/update-launch.json must map every pinned app";
pkgs.runCommand "nixarchy-update-launch" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${./update-launch-fixture.py} ${../.github/scripts/update-launch.py}
  touch $out
''
