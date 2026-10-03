{ inputs }:
# The one place tests/install.nix, tests/free-space.nix,
# tests/install-encrypted.nix and tests/install-seed-shape.nix name what
# machine each test is about -- the exact arguments
# tests/lib/installed-target.nix's helper takes, plus `name` and `diskMode`
# for the check's own rendering. Before this, the four files carried the
# same five values by hand (AGENTS.md §4: a hand-maintained list fails
# open) -- a hand-edit to one that missed the others tested the wrong
# machine, silently.
{
  install = {
    name = "install";
    diskMode = "whole";
    diskConfig = import ../../installer/disk-config.nix {
      device = "/dev/vdb";
      encrypt = false;
    };
    reference = inputs.self.nixosConfigurations.reference-unencrypted.config;
    encrypt = false;
    recoverySecret = false;
    extraInstrumentationText = "";
  };

  "free-space" = {
    name = "free-space";
    diskMode = "free";
    diskConfig = import ../../installer/disk-config.nix {
      mode = "free";
      device = "/dev/vdb";
      encrypt = false;
    };
    reference = inputs.self.nixosConfigurations.reference-unencrypted.config;
    encrypt = false;
    recoverySecret = false;
    extraInstrumentationText = "";
  };

  "install-encrypted" = {
    name = "install-encrypted";
    diskMode = "whole";
    diskConfig = import ../../installer/disk-config.nix {
      device = "/dev/vdb";
      encrypt = true;
    };
    reference = inputs.self.nixosConfigurations.reference.config;
    encrypt = true;
    recoverySecret = true;
    extraInstrumentationText = ''
      boot.kernelParams = [ "console=ttyS0,115200" ];
      boot.plymouth.enable = lib.mkForce false;
    '';
  };
}
