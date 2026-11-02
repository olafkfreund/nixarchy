{
  pkgs,
  reference,
}:
# #1549: two tmpfiles.d files naming one path apply the lexically first file.
# Upstream microvm.nix's 10-microvm declares a declared machine's directories
# 0775; ours must sort first or our 0750/0770/0750 never apply. Evaluation
# only -- checks.microvm-boot asserts the modes in a VM, but only nightly.
let
  inherit (pkgs) lib;
  host = reference.extendModules {
    modules = [
      {
        programs.nixarchy.services.microvm = {
          enable = true;
          user = null;
          machines.sandbox.template = "shell";
        };
      }
    ];
  };
  settings = host.config.systemd.tmpfiles.settings;
  ours = lib.filter (lib.hasSuffix "-nixarchy-microvm") (lib.attrNames settings);
  beaten = lib.concatMap (
    key:
    lib.concatMap (
      path:
      map (other: "${other} sorts before ${key} and declares ${path}") (
        lib.filter (other: other < key && settings.${other} ? ${path}) (lib.attrNames settings)
      )
    ) (lib.attrNames settings.${key})
  ) ours;
in
assert lib.assertMsg (
  ours != [ ]
) "no *-nixarchy-microvm tmpfiles settings: the check reads nothing";
assert lib.assertMsg (beaten == [ ])
  "nixarchy's microvm directory modes lose to an earlier tmpfiles file (#1549):\n${lib.concatStringsSep "\n" beaten}";
pkgs.runCommand "nixarchy-microvm-tmpfiles-order" { } "touch $out"
