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

  # The hash is NOT in this file, and that is the point: this directory is a
  # git repository, nixarchy-config-repo exists to push it to GitHub, and a
  # crypt hash is offline-crackable at leisure by anyone who reads it. So it
  # lives outside the repo and this file names where.
  #
  # /var/lib rather than /etc/nixarchy, which is a NixOS-managed directory --
  # an unmanaged file dropped among generated symlinks survives today only
  # because the /etc overlay is off, and the failure if that changes is that
  # nobody can log in.
  users.users."@username@".hashedPasswordFile = "/var/lib/nixarchy/password.hash";

  # A usable emergency shell, when the installer was given a recovery
  # passphrase. null when it was not, which is the NixOS default: the initrd's
  # shadow becomes `root:*` and sulogin refuses to open a console.
  #
  # This hash IS in this file, unlike the login hash above, and that is not an
  # oversight. The option takes a literal string which nixpkgs splices into the
  # initrd's /etc/shadow, and the initrd lives on the ESP -- unencrypted, by
  # necessity, since it runs before anything is unlocked. There is no version
  # of this that keeps the hash secret, so the installer asks for a passphrase
  # that is worth nothing if it leaks rather than pretending otherwise, and
  # refuses one that matches the login password.
  boot.initrd.systemd.emergencyAccess = "@recovery@";
}
