# Machines that keep themselves current with a configuration repository.
#
# NixOS already does this. `system.autoUpgrade` with a flake URL is pull-based
# GitOps, and nixos-rebuild resolves the attribute from the hostname -- so one
# option value serves every machine in a fleet, and nothing here needs to know
# how many there are or what they are called.
#
# So this is not a mechanism. It is an opt-in wrapper that fixes the two things
# system.autoUpgrade gets wrong when nobody is watching, and otherwise gets out
# of the way. No comin, no colmena, no clan: the native rung holds, and a
# GitOps daemon on top of it would be re-solving a solved problem with a
# dependency attached.
#
# Push deploy needs no code from us at all and gets none:
#
#   nixos-rebuild switch --flake github:me/config#laptop --target-host root@laptop
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy.fleet;
in
{
  options.programs.nixarchy.fleet = {
    enable = lib.mkEnableOption ''
      pulling this machine's configuration from a git repository on a timer.

      OFF by default and deliberately so: a machine that rebuilds itself from
      somewhere else is not a thing to switch on for somebody. Adding nixarchy
      to a configuration you already run changes nothing here.

      Note what enabling it means. The running system comes from the REMOTE
      flake, so local edits under /etc/nixos that were never pushed are
      reverted at the next pull, silently and without asking. That is the
      point of a fleet and it is also the way to lose an afternoon's work
    '';

    url = lib.mkOption {
      type = lib.types.str;
      example = "github:me/config";
      description = ''
        The flake to pull from. Anything nixos-rebuild --flake accepts.

        No default. A fleet URL is a decision about where this machine's
        configuration lives, and a default would be a guess at somebody's
        repository that fails at the first timer rather than at evaluation.
      '';
    };

    dates = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd calendar expression, as system.autoUpgrade.dates.";
    };
  };

  config = lib.mkIf (config.programs.nixarchy.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.url != "";
        message = "programs.nixarchy.fleet.enable is on but fleet.url is empty; there is nowhere to pull from.";
      }
    ];

    system.autoUpgrade = {
      enable = true;
      flake = cfg.url;
      inherit (cfg) dates;

      # --refresh, or a flakeref that names a branch is resolved from whatever
      # is already in the evaluation cache and the machine "upgrades" to what
      # it already has, indefinitely.
      flags = [ "--refresh" ];

      # persistent is NOT set here: nixpkgs already defaults it true, and a
      # second definition saying the same thing is dead config that reads like
      # a decision. checks.options asserts the value anyway -- the reasoning
      # still has to hold, it just is not ours to state. A laptop asleep at the
      # hour is the machine that most needs to catch up and the one a
      # non-persistent timer never reaches.

      # Spread a fleet out. Fifty machines waking at 03:00 to build the same
      # closure is fifty times the load on whatever they are pulling from, for
      # no gain to any of them.
      randomizedDelaySec = "45min";
    };

    # The failure mode this option exists to survive.
    #
    # An unattended upgrade that starts failing stops delivering configuration,
    # and nothing says so: the machine keeps running the system it already had,
    # which looks exactly like a machine that is up to date. A fleet that has
    # quietly stopped converging is worse than one that never started, because
    # nobody is looking at it. See nixpkgs#349734 and nixpkgs#468878.
    #
    # A file, not just a log line: journald rotates, and the question "when did
    # this machine last fail to update" should survive that and be answerable
    # by nixarchy-doctor without parsing a journal.
    systemd.services.nixos-upgrade.unitConfig.OnFailure = "nixarchy-upgrade-failed.service";

    systemd.services.nixarchy-upgrade-failed = {
      description = "Record that the unattended upgrade failed";
      serviceConfig = {
        Type = "oneshot";
        # StateDirectory rather than mkdir: systemd creates it with the right
        # ownership before the unit runs, and it is the same /var/lib/nixarchy
        # the password hash lives in.
        StateDirectory = "nixarchy";
      };
      script = ''
        printf '%s upgrade from %s failed\n' \
          "$(${pkgs.coreutils}/bin/date -Is)" "${cfg.url}" \
          >> /var/lib/nixarchy/upgrade-failed
      '';
    };
  };
}
