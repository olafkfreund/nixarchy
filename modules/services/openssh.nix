# OpenSSH from the menu: key logins only.
#
# Bundled rather than plain because services.openssh.enable alone accepts
# passwords, and the menu must not. Why: modules/AGENTS.md#openssh-from-the-menu
{ config, lib, ... }:
let
  cfg = config.programs.nixarchy;
  svc = cfg.services.openssh;
in
{
  options.programs.nixarchy.services.openssh.enable = lib.mkEnableOption ''
    the OpenSSH server with password logins off.

    Add a key first: Setup > Security > SSHD asks for one. Upstream's own
    `services.openssh` options work alongside this one, and a value you set
    there wins
  '';

  # Scalars, so mkDefault: a user's own value wins silently.
  config = lib.mkIf (cfg.enable && svc.enable) {
    services.openssh = {
      enable = lib.mkDefault true;
      settings.PasswordAuthentication = lib.mkDefault false;
      settings.KbdInteractiveAuthentication = lib.mkDefault false;
    };
  };
}
