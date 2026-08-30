# Your machine. Everything Omarchy needs is in nixarchy's host module; this
# file holds what the installer asked you, and whatever you add later.
#
# Edit, then run `nh os switch`.
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    # nixarchy-apply copies your app selection here. Without this line the
    # menu marks apps enabled and nothing is ever installed.
    ./nixarchy-apps.nix
  ];

  time.timeZone = "@timezone@";
  console.keyMap = "@keymap@";

  # Most of what the Install menu offers is unfree. nixarchy defaults this on
  # already; it is repeated here because it is your file, and a licence policy
  # you cannot see is one you cannot change. Set it false for nixpkgs' own.
  nixpkgs.config.allowUnfree = true;

  # An encrypted disk has already authenticated you by the time the greeter
  # would ask, so the installer turns this on for encrypted installs and off
  # for unencrypted ones. Quoted for the same reason as the encrypt flag in
  # flake.nix: the bare token would not parse.
  services.displayManager.autoLogin = {
    enable = "@autologin@";
    user = "@username@";
  };

  users.users."@username@".hashedPassword = "@password_hash@";
}
