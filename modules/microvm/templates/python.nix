# The `python` template. Ephemeral like `shell` -- modules/microvm/guest.nix's
# tmpfs root is thrown away every boot, same as it is there -- and the only
# two things this adds beyond that are `python3` and `uv` on PATH, plus more
# memory than the 1 GiB default, since resolving a venv routinely wants it.
#
# `uv venv` writes into the guest's own tmpfs root by default, and that venv
# is gone at the next boot along with everything else outside /mnt/host --
# `uv venv /mnt/host/.venv` is what makes one outlive the VM, onto the same
# host directory `nixarchy vm run` shares in.
{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.python3
    pkgs.uv
  ];

  # microvm.nix's own default (nixos-modules/microvm/options.nix) is 512;
  # modules/microvm/guest.nix does not raise it, so a template that wants
  # more says so itself. 3072 is enough headroom to resolve a
  # dependency-heavy lockfile without swapping on a share as slow as 9p.
  microvm.mem = 3072;
}
