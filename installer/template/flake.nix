# Your machines, as the installer wrote them. This directory is yours to edit.
#
# The three commands that matter:
#
#   nh os switch            rebuild and activate after editing these files
#   nixarchy-app-enable X   pick an app (the Install menu does this for you)
#   nixarchy-apply          copy the selection here and rebuild
#
# It is a git repository because a flake inside a worktree sees only tracked or
# staged files -- an untracked file produces "path does not exist" the first
# time you apply. The installer staged everything; it deliberately made no
# commit, because git needs an identity and choosing yours is not the
# installer's business.
#
# Machines are directories under ./hosts, and this file finds them by reading
# that directory rather than naming them. Adding a second machine is adding a
# second directory -- copy one, change what differs, `git add` it. There is
# nothing to edit here.
#
# `git add` is not optional and not a tidiness rule: an unstaged hosts/<name>/
# does not exist as far as evaluation is concerned, and the error says the path
# is missing rather than that it is untracked.
{
  inputs = {
    # Your package set. Locked at install time; `nix flake update nixpkgs` (or
    # `omarchy update`) moves it forward when you decide to.
    #
    # To follow STABLE nixpkgs instead, point this at the release branch (e.g.
    # "github:NixOS/nixpkgs/nixos-25.05") -- and move home-manager with it, as
    # the two are developed as a pair. Add this inside the `nixarchy` block
    # below, beside the `follows`:
    #
    #   inputs.home-manager.url =
    #     "github:nix-community/home-manager/release-25.05";
    #
    # then `nix flake update nixpkgs` and `nh os switch` (the changed
    # home-manager override is re-locked in the same pass).
    nixpkgs.url = "@nixpkgs_url@";

    # Nixarchy itself, locked at the revision this machine was installed from.
    # `nix flake update nixarchy` moves it to the latest release, deliberately
    # -- nothing moves until you run it. Then `nh os switch`.
    nixarchy = {
      url = "@nixarchy_url@";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixarchy, ... }:
    let
      inherit (nixarchy.inputs.nixpkgs) lib;

      # Directories only. A stray file under hosts/ -- a README, an editor's
      # backup -- is not a machine, and would otherwise become a configuration
      # that fails to evaluate for reasons nothing explains.
      hosts = lib.attrNames (lib.filterAttrs (_: kind: kind == "directory") (builtins.readDir ./hosts));
    in
    {
      nixosConfigurations = lib.genAttrs hosts (
        name:
        lib.nixosSystem {
          system = "x86_64-linux";
          # The module takes `inputs` and reads inputs.self for its own outputs,
          # so hand it nixarchy's inputs with nixarchy standing in as self.
          # hosts/<name>/default.nix reaches installer/host.nix through it.
          specialArgs = {
            inputs = nixarchy.inputs // {
              self = nixarchy;
            };
          };
          modules = [
            nixarchy.nixosModules.nixarchy
            nixarchy.inputs.home-manager.nixosModules.home-manager
            nixarchy.inputs.disko.nixosModules.disko
            ./hosts/${name}
          ];
        }
      );

      # `nixarchy reinstall-iso` builds this: a bootable image carrying THIS
      # machine, so it can be rebuilt on new hardware after a disk is lost.
      #
      # Read the honesty in the command before you rely on it. The image
      # carries the system closure and this repository; it carries no /home,
      # no service state and no secrets, and booting it ERASES the target
      # disk. Files come back from your backups, not from here.
      #
      # One per machine, named for it, because `hosts/` can hold several and
      # an image is of one of them. `self` rather than a path so the image
      # embeds the flake as git sees it -- which is also why the command
      # refuses on an uncommitted tree.
      packages.x86_64-linux =
        lib.genAttrs hosts (
          name:
          nixarchy.lib.mkUserIso {
            flake = self;
            host = name;
          }
        )
        // {
          # The bare name, for the common case of one machine. With several,
          # the command names the one it means.
          reinstall-iso =
            if lib.length hosts == 1 then
              nixarchy.lib.mkUserIso {
                flake = self;
                host = lib.head hosts;
              }
            else
              throw ''
                This repository has ${toString (lib.length hosts)} machines, so
                "reinstall-iso" does not say which one. Name it:
                ${lib.concatStringsSep "\n" (map (h: "  nix build .#${h}") hosts)}
              '';
        };
    };
}
