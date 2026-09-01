# Tailscale: a private network between machines you own.
#
# Bundled rather than plain because `services.tailscale.enable = true` on its
# own gives you a host that can reach the tailnet and cannot be reached from
# it. The firewall is still in the way, and the symptom -- outbound works,
# inbound times out -- reads like a Tailscale problem rather than a local one.
# Trusting the interface is the part upstream leaves to you and nobody finds
# on the first try.
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.nixarchy;
  svc = cfg.services.tailscale;
in
{
  options.programs.nixarchy.services.tailscale = {
    enable = lib.mkEnableOption ''
      Tailscale, with this host reachable from the rest of your tailnet.

      Run `sudo tailscale up` once after the rebuild to log in. Upstream's own
      options work alongside this one and are not re-declared here --
      `services.tailscale.authKeyFile` for an unattended join,
      `services.tailscale.useRoutingFeatures` for an exit node
    '';

    trustInterface = lib.mkOption {
      type = lib.types.bool;
      default = svc.enable;
      defaultText = lib.literalExpression "config.programs.nixarchy.services.tailscale.enable";
      description = ''
        Treat the tailnet as trusted, so other machines on it can reach this
        one rather than only the other way round.

        Its own option with its own default rather than a branch inside
        `enable`, so a host that wants Tailscale for outbound access only --
        a laptop on someone else's network, say -- can turn this half off
        without turning Tailscale off.

        This is a real decision, not a formality: a trusted interface bypasses
        the firewall for everything arriving on it. That is the point on a
        network of your own machines, and worth knowing before you leave it on
        for a tailnet you share with someone else.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && svc.enable) (
    lib.mkMerge [
      {
        # A scalar, so mkDefault: someone already running Tailscale their way
        # keeps their configuration and this yields to it.
        services.tailscale.enable = lib.mkDefault true;
      }

      (lib.mkIf svc.trustInterface {
        # Lists, so plain assignment. mkDefault here would drop both entirely
        # the moment the user trusts an interface or opens a port of their own.
        networking.firewall.trustedInterfaces = [ "tailscale0" ];
        networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];
      })
    ]
  );
}
