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
  # passphrase. `{ }` when it was not, which leaves the NixOS default: the
  # initrd's /etc/shadow is `root:*` and sulogin refuses to open a console.
  #
  # The hash is NOT in this file. boot.initrd.systemd.emergencyAccess would
  # have put it here -- it takes a literal string, spliced into the initrd's
  # /etc/shadow -- and this directory is a git repository that
  # nixarchy-config-repo pushes to GitHub. boot.initrd.secrets instead names a
  # path on the live filesystem, appended to the initrd by systemd-boot at
  # bootloader-install time. systemd-boot sets supportsInitrdSecrets, so the
  # file is not copied into the store either.
  #
  # The initrd still ends up holding the hash, and the initrd is on the ESP,
  # unencrypted -- unavoidably, since it runs before anything is unlocked.
  # That is why the installer asks for a passphrase of its own and refuses one
  # that matches the login password: this credential is meant to be spendable.
  #
  # If the append ever fails, the generated `root:*` stands and the machine is
  # locked out of emergency mode rather than open to it.
  boot.initrd.secrets = "@recoverysecret@";
}
