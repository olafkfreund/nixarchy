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
  agentAbsent = c: !(c.systemd.user.services ? bt-agent);
  timeoutAbsent = c: (c.hardware.bluetooth.settings.General.PairableTimeout or null) == null;
  hasAgentPackage = pkgs.lib.any (
    p: (p.pname or "") == "bluez-tools"
  ) pkgs.omarchy.passthru.runtimeDeps;
in
assert pkgs.lib.assertMsg (
  agentAbsent on && agentAbsent off
) "Nixarchy still installs a permanent Bluetooth auto-accept agent";
assert pkgs.lib.assertMsg (
  timeoutAbsent on && timeoutAbsent off
) "Nixarchy still sets a Bluetooth pairable timeout";
assert pkgs.lib.assertMsg hasAgentPackage "temporary Bluetooth agent is missing from runtimeDeps";
pkgs.runCommand "bluetooth-pairing"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    bash ${./bluetooth-pairing.sh} ${pkgs.omarchy}/share/omarchy/bin/omarchy-bluetooth-device ${pkgs.bash}/bin/bash
    touch "$out"
  ''
