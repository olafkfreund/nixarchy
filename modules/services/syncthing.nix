# Syncthing: folders kept in step between your own machines.
#
# Bundled rather than plain because `services.syncthing.enable = true` alone
# gives you a daemon running as the `syncthing` user, syncing into
# /var/lib/syncthing, which is not where anybody's files are. It has to run as
# the person using the desktop, and upstream cannot know who that is -- this
# module does, because nixarchy already asks.
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.nixarchy;
  svc = cfg.services.syncthing;
in
{
  options.programs.nixarchy.services.syncthing = {
    enable = lib.mkEnableOption ''
      Syncthing, running as the desktop user rather than as a system account.

      The web interface is at http://127.0.0.1:8384 once it is up. Folders and
      devices are configured there, or declaratively through upstream's own
      `services.syncthing.settings` -- which works alongside this and is not
      re-declared here, because upstream's option is better than a copy of it
      would be
    '';

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = cfg.user;
      defaultText = lib.literalExpression "config.programs.nixarchy.user";
      description = ''
        Who Syncthing runs as. Defaults to the desktop user, which is the
        answer in every case this module exists for.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = svc.enable;
      defaultText = lib.literalExpression "config.programs.nixarchy.services.syncthing.enable";
      description = ''
        Open the ports Syncthing needs to reach your other machines: 22000 for
        sync traffic and 21027 for discovery on the local network.

        A separate option with its own default rather than a branch inside the
        one above, so that a machine which syncs only over Tailscale can turn
        this half off without turning Syncthing off.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && svc.enable) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = svc.user != null;
            message = ''
              programs.nixarchy.services.syncthing is enabled but no user is set,
              and a Syncthing that runs as a system account syncs a directory
              nobody keeps files in.

              Set programs.nixarchy.user, which is what this follows, or set
              programs.nixarchy.services.syncthing.user directly.
            '';
          }
        ];

        # Scalars, so mkDefault: someone who already runs Syncthing their way
        # keeps their configuration and this yields to it silently.
        services.syncthing = {
          enable = lib.mkDefault true;
          user = lib.mkDefault svc.user;
          dataDir = lib.mkDefault "/home/${svc.user}";
          configDir = lib.mkDefault "/home/${svc.user}/.config/syncthing";

          # The VALUE is the decision here: upstream defaults these to true,
          # and true means "delete any folder or device the Nix configuration
          # does not mention" -- which silently discards everything added
          # through the web interface, the way most people actually use
          # Syncthing.
          #
          # mkDefault, though this once said "NOT mkDefault" -- that comment
          # conflated the value with the priority. mkDefault (1000) still
          # outranks the option's own default (1500), so everyone who writes
          # nothing keeps the protection; what plain assignment added on top
          # was a "defined multiple times" error for the user who explicitly
          # asks for upstream's declarative mode, whose only exit was
          # mkForce -- the one-way door this directory's header forbids.
          # Someone who writes `overrideFolders = true` themselves has
          # accepted the deletion; the shield is only for those who didn't
          # choose.
          overrideFolders = lib.mkDefault false;
          overrideDevices = lib.mkDefault false;
        };
      }

      # Lists, so plain assignment. mkDefault here would drop these entirely the
      # moment the user opens a port of their own.
      (lib.mkIf svc.openFirewall {
        networking.firewall.allowedTCPPorts = [ 22000 ];
        networking.firewall.allowedUDPPorts = [
          22000
          21027
        ];
      })
    ]
  );
}
