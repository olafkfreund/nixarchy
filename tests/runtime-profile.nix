# The profile a standalone Home Manager user gets: the Omarchy package plus
# every runtime dependency, which modules/home.nix adds to home.packages when
# there is no NixOS module to install them. Built, not inspected, because a
# collision only exists once buildEnv runs (AGENTS.md §2).
#
# #1485 found the shape: the native screensaver installed
# bin/omarchy-launch-screensaver, the Omarchy package ships a script of the
# same name, and buildEnv refused with "two given paths contain a conflicting
# subpath". tests/home-profile.nix cannot see it, because it evaluates with
# nixarchy enabled on the NixOS side, where the runtime list is not added.
{ inputs, pkgs }:
let
  omarchy = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy;
in
pkgs.buildEnv {
  name = "nixarchy-runtime-profile";
  paths = [ omarchy ] ++ omarchy.passthru.runtimeDeps;
  ignoreCollisions = false;
}
