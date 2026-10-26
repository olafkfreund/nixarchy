{ inputs, pkgs }:
# A host that declares a sops secret can be DESCRIBED: setupSecrets evaluates,
# which forces sops-nix's sops-install-secrets (#1030). checks.options never
# forces the closure. hypr-rdp, removed in #1462, was the feature that met
# this; sops-nix stays, so the probe does too (data/pin-fix.nix, #1459). An
# integer, not a drvPath: see tests/AGENTS.md on drvPaths as build inputs.
let
  withSecret = inputs.self.nixosConfigurations.reference.extendModules {
    modules = [
      {
        sops = {
          validateSopsFiles = false;
          age.keyFile = "/var/lib/sops-nix/key.txt";
          defaultSopsFile = ../flake.nix;
          secrets.probe = { };
        };
      }
    ];
  };
in
pkgs.runCommand "nixarchy-sops-evaluates"
  { proof = builtins.stringLength withSecret.config.system.activationScripts.setupSecrets.text; }
  ''
    if [ "''${proof:-0}" -lt 32 ]; then
      echo "FAIL: setupSecrets is $proof characters; this no longer forces sops-install-secrets."
      exit 1
    fi
    echo "a host with a sops secret evaluates: setupSecrets is $proof characters"
    touch $out
  ''
