{ inputs, pkgs }:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  machine =
    enabled:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.nixarchy
        {
          programs.nixarchy.enable = enabled;
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;
  on = machine true;
  off = machine false;
  guard = on.systemd.user.services.bt-agent.serviceConfig.ExecStartPre or null;
in
assert pkgs.lib.assertMsg (
  (on.hardware.bluetooth.settings.General.PairableTimeout or null) == 120
) "Bluetooth pairing timeout is not 120 seconds";
assert pkgs.lib.assertMsg (guard != null) "Bluetooth agent has no startup pairing guard";
assert pkgs.lib.assertMsg (
  !(off.systemd.user.services ? bt-agent)
) "disabled Nixarchy still installs the Bluetooth agent";
assert pkgs.lib.assertMsg (
  (off.hardware.bluetooth.settings.General.PairableTimeout or null) == null
) "disabled Nixarchy still sets a Bluetooth pairing timeout";
pkgs.runCommand "bluetooth-pairing" { } ''
  grep -Fq 'set -euo pipefail' ${guard} || { echo 'Bluetooth guard does not fail closed' >&2; exit 1; }
  grep -Fq 'pairable off' ${guard} || { echo 'Bluetooth guard does not disable incoming pairing' >&2; exit 1; }
  grep -Fq 'Pairable: no' ${guard} || { echo 'Bluetooth guard does not verify adapter state' >&2; exit 1; }
  touch "$out"
''
