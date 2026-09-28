{ inputs, pkgs }:
# A host with remote desktop enabled can be DESCRIBED. Nothing more, and the
# "nothing more" is the point.
#
# `programs.nixarchy.services.hypr-rdp` was unbuildable from 2026-09-15 to
# 2026-09-27 and the suite was green throughout (#1030). nixarchy pinned
# sops-nix at a8627b21; nixpkgs removed `buildGo125Module` that day; the
# pinned sops-install-secrets still called it. Since this feature REQUIRES a
# sops secret -- hypr-rdp reads its password from a file and nothing else --
# every configuration with it enabled died, and the error named Go.
#
# ## Why checks.options could not see it, although it tries
#
# tests/options.nix is not thin here: it has a sops fixture, an `rdpOn`
# fixture that enables hypr-rdp with a real `passwordSecret`, and cases for
# the unit, the template, the firewall and both refusals. It still could not
# catch this, for the reason its own comment gives:
#
#   "Read as a list of failed assertions rather than by forcing
#    system.build.toplevel: the point is that THIS assertion fires, and a
#    config that fails to build for some unrelated reason would look
#    identical from outside."
#
# Correct for what it was written about, and it means checks.options never
# forces the closure. A package that cannot be built -- or, as here, cannot
# be EVALUATED -- is invisible to it.
#
# ## Why this costs an evaluation rather than a VM
#
# `buildGo125Module` is an alias that `throw`s, so the failure arrives while
# the drvPath is being computed. Forcing that string is the whole check: if
# the closure cannot be described, this cannot be built. No VM, no runner
# minutes, and it runs on the pull request that would introduce the problem
# rather than in a nightly.
#
# Deliberately NOT a case in checks.options: that check peaks at 12.9 GB on
# the hosted runner and is the subject of #747. Its fixtures are tempting;
# adding a whole system closure evaluation to it is not.
#
# ## What this does NOT cover, so it is not mistaken for coverage
#
# It proves the closure is describable. It says nothing about the daemon
# running. Two live defects sit past it and are named in tests/AGENTS.md:
#
#   #1031  hypr-rdp cannot create its headless output on Hyprland 0.56 --
#          needs a live compositor
#   #1033  enabling it takes effect only at next login, so the unit is not
#          running and the menu row is absent -- needs a session
let
  # The same shape of declaration options.nix already uses. Nothing is ever
  # decrypted: this only has to satisfy the module's assertions so the
  # closure can be described.
  withRdp = inputs.self.nixosConfigurations.reference.extendModules {
    modules = [
      {
        programs.nixarchy.services.hypr-rdp = {
          enable = true;
          passwordSecret = "rdp-password";
        };
        sops = {
          validateSopsFiles = false;
          age.keyFile = "/var/lib/sops-nix/key.txt";
          defaultSopsFile = ../flake.nix;
          secrets.rdp-password = { };
        };
      }
    ];
  };
in
pkgs.runCommand "nixarchy-hypr-rdp-builds"
  {
    # A NUMBER, not a store path, and that distinction is the whole cost of
    # this check.
    #
    # The first version passed `config.system.build.toplevel.drvPath`. A .drv
    # path in a derivation's environment is a build INPUT, so nix did not
    # evaluate the closure -- it BUILT the entire system. On CI that took the
    # `omarchy` job from its usual 6-13 minutes to 45 and a timeout, twice
    # (#1030). Measured against three passing runs of the same step before
    # blaming it, because "my change made it slow" is a claim like any other.
    #
    # The bug this exists for throws during EVALUATION -- `buildGo125Module`
    # is an alias that `throw`s -- so evaluating is sufficient and building
    # buys nothing. Taking the length of the activation script forces the
    # script, which forces sops-install-secrets, and leaves an integer in the
    # environment with no store reference for nix to chase.
    proof = builtins.stringLength withRdp.config.system.activationScripts.setupSecrets.text;
  }
  ''
    set -o pipefail
    if [ "''${proof:-0}" -lt 32 ]; then
      echo "FAIL: the secrets activation script is $proof characters."
      echo "  That is too short to be real, so this check has stopped"
      echo "  forcing what it was written to force."
      exit 1
    fi
    echo "a host with hypr-rdp enabled evaluates: its secrets activation"
    echo "script is $proof characters, which required sops-install-secrets."
    echo
    echo "This proves the configuration EVALUATES. It does not build it, and"
    echo "it does not prove the daemon runs -- see #1031 and #1033, and"
    echo "tests/AGENTS.md."
    touch $out
  ''
