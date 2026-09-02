# One machine.
#
# Everything here is what the installer asked, or what only this machine can
# know. Anything true of every machine belongs in nixarchy's host module, not
# in a copy of this file.
#
# The directory name is the hostname: ../../flake.nix reads ./hosts to find
# machines, so renaming the directory renames the configuration.
{ inputs, ... }:
{
  imports = [
    # Read from the nixarchy store path rather than copied in, so it tracks the
    # pinned revision instead of going stale here. inputs.self is nixarchy --
    # flake.nix substitutes it in specialArgs.
    (import "${inputs.self}/installer/host.nix" {
      hostname = "@hostname@";
      username = "@username@";
    })

    # Shared between every machine in this repo, because the layout is the same
    # everywhere the installer writes one. A machine that partitions
    # differently gets its own file here instead.
    (import ../../disk-config.nix {
      device = "@device@";
      # Quoted deliberately: the bare token is not valid Nix -- the file would
      # not parse, let alone format -- so the installer substitutes the quotes
      # away along with it. The autologin flag in configuration.nix is quoted
      # for the same reason.
      encrypt = "@encrypt@";
    })

    ./configuration.nix
  ];
}
