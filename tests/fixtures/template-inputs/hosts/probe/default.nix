# A host as a user writes one after following the template's own advice: an
# input nixarchy does not have (nixpkgs-other), reached through `inputs`.
# tests/other-channel.nix evaluates the real installer template against it.
{ inputs, pkgsOther, ... }:
{
  imports = [ "${inputs.self}/vm/configuration.nix" ];
  programs.nixarchy.otherChannel.flake = inputs.nixpkgs-other;
  environment.systemPackages = [ pkgsOther.btop ];
}
