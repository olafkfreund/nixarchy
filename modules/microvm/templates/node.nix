# The `node` template: python.nix's JavaScript counterpart, and nothing more.
# `nodejs` is nixpkgs' default, which tracks the active LTS line; `pnpm`
# because it is what a lockfile-heavy install wants. Same memory as python
# for the same reason: resolving a dependency tree on a share as slow as 9p
# is the expensive part.
#
# node_modules written into the guest's tmpfs root are gone at the next
# boot; `pnpm install` inside /mnt/host writes them onto the host directory
# `nixarchy vm run` shares in, which is what makes them outlive the VM.
{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.nodejs
    pkgs.pnpm
  ];

  microvm.mem = 3072;
}
