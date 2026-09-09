# A single machine that keeps its own package set current, unattended.
#
# The sibling of fleet.nix and deliberately not the same thing. fleet.nix
# points a machine at a REMOTE flake, which is right for a fleet and wrong for
# a laptop: its own warning says local edits under /etc/nixos "are reverted at
# the next pull, silently and without asking". For a machine whose
# configuration IS /etc/nixos, that is not a trade-off, it is data loss.
#
# So this pulls nothing. It moves ONE input in the flake the machine already
# has, and rebuilds from it.
#
# ## Why nixpkgs only, and not "update everything"
#
# The two axes are independent by design (installer/mkFlake.nix makes nixpkgs a
# root input and has nixarchy follow it), and they mean different things:
#
#   nixpkgs   your package set -- kernel, openssl, browsers. Security updates.
#   nixarchy  the desktop
#
# An unattended nixpkgs bump is what "follow NixOS" means to most people. An
# unattended nixarchy bump changes the desktop under someone who did not ask,
# possibly while they are using it. One of those is a background task and the
# other is a decision, so only the first is on offer here. `omarchy update
# --nixarchy` remains the way to take the other, when you choose to.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy.autoUpdate;
  fleet = config.programs.nixarchy.fleet;
in
{
  options.programs.nixarchy.autoUpdate = {
    enable = lib.mkEnableOption ''
      moving this machine's nixpkgs forward on a timer and rebuilding.

      OFF by default. A machine that rebuilds itself unattended is not
      something to switch on for somebody.

      Only nixpkgs moves -- your package set, which is where security updates
      live. Nixarchy itself is left where it is, because changing the desktop
      under someone who did not ask is a decision rather than maintenance;
      `omarchy update --nixarchy` takes that one deliberately.

      Nothing is pulled from anywhere: this rebuilds the flake already on the
      machine
    '';

    dates = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      example = "Sun 04:00";
      description = "systemd calendar expression for when to update.";
    };

    flake = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      description = "The machine's own flake directory. Rebuilt in place, never replaced.";
    };

    allowDirty = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Rebuild even when the flake directory has uncommitted changes.

        Off by default, and this is the safety that matters. /etc/nixos is a
        git repository the user edits by hand, so an unattended rebuild of a
        dirty tree deploys whatever was half-finished when they walked away --
        at 03:00, with nobody watching, and the failure arrives as a machine
        that booted into an edit nobody meant to apply.

        Refusing is recorded, not silent: the reason lands in
        /var/lib/nixarchy/upgrade-failed and the doctor reads it.
      '';
    };
  };

  config = lib.mkIf (config.programs.nixarchy.enable && cfg.enable) {
    assertions = [
      {
        # Both would drive this machine from two different flakes on two
        # timers. Whichever ran last would win and the other would look
        # intermittently broken.
        assertion = !fleet.enable;
        message =
          "programs.nixarchy.autoUpdate and .fleet are both enabled. "
          + "fleet pulls a REMOTE flake and reverts local edits; autoUpdate "
          + "rebuilds this machine's OWN flake. Pick one.";
      }
    ];

    systemd = {
      services.nixarchy-auto-update = {
        description = "Move nixpkgs forward and rebuild this machine";
        # Not wantedBy anything: the timer is the only thing that starts it. A
        # boot-time trigger would rebuild a machine somebody just booted because
        # they needed it.
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "nixarchy";
        };
        unitConfig.OnFailure = "nixarchy-upgrade-failed.service";

        path = with pkgs; [
          nix
          git
          config.system.build.nixos-rebuild
          coreutils
          gnutar
          gzip
          openssh
        ];

        script = ''
          set -euo pipefail
          flake=${lib.escapeShellArg cfg.flake}

          note() {
            printf '%s %s\n' "$(date -Is)" "$1" >> /var/lib/nixarchy/upgrade-failed
          }

          if [ ! -d "$flake" ]; then
            note "auto-update: $flake does not exist"
            echo "no flake at $flake" >&2
            exit 1
          fi

          ${lib.optionalString (!cfg.allowDirty) ''
            # The whole reason this is off by default. A dirty tree is somebody's
            # unfinished edit, and rebuilding it unattended deploys that edit.
            # Reported rather than ignored: an unattended job that stops working
            # and says nothing looks exactly like one that is up to date.
            if [ -d "$flake/.git" ] && ! git -C "$flake" diff --quiet HEAD 2>/dev/null; then
              note "auto-update: $flake has uncommitted changes; not rebuilding"
              echo "$flake is dirty; commit it or set autoUpdate.allowDirty" >&2
              exit 1
            fi
          ''}

          # ONE input. A bare flake update moves nixarchy too, which is the
          # decision this module deliberately does not make.
          nix flake update nixpkgs --flake "$flake"

          # switch, not boot: a package-set update that needs a reboot to take
          # effect is one the user never notices they received.
          nixos-rebuild switch --flake "$flake"
        '';
      };

      # Same failure the sibling exists to survive, for the same reason: an
      # unattended job that starts failing stops delivering security updates and
      # says nothing, and a machine that has quietly stopped updating is
      # indistinguishable from one that is current. A file rather than only a log
      # line, because journald rotates and "when did this last work" should
      # outlive that. See nixpkgs#349734.
      services.nixarchy-upgrade-failed = {
        description = "Record that the unattended update failed";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "nixarchy";
        };
        script = ''
          printf '%s unattended update failed\n' "$(${pkgs.coreutils}/bin/date -Is)" \
            >> /var/lib/nixarchy/upgrade-failed
        '';
      };

      timers.nixarchy-auto-update = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.dates;
          # A laptop asleep at the hour is the machine that most needs to catch
          # up and the one a non-persistent timer never reaches.
          Persistent = true;
          # Not about server load, since this is not a fleet -- about not
          # starting a multi-gigabyte download the same second every machine in
          # the house wakes.
          RandomizedDelaySec = "45min";
        };
      };
    };
  };
}
