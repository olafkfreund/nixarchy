# Your machine, as the installer wrote it. This directory is yours to edit.
#
# The three commands that matter:
#
#   nh os switch            rebuild and activate after editing these files
#   nixarchy-app-enable X   pick an app (the Install menu does this for you)
#   nixarchy-apply          copy the selection here and rebuild
#
# It is a git repository because a flake inside a worktree sees only tracked or
# staged files -- an untracked nixarchy-apps.nix produces "path does not exist"
# the first time you apply. The installer staged everything; it deliberately
# made no commit, because git needs an identity and choosing yours is not the
# installer's business.
{
  # Pinned to the nixarchy revision this machine was installed from. Bump it
  # deliberately with `nix flake update nixarchy`, then `nh os switch`.
  inputs.nixarchy.url = "@nixarchy_url@";

  outputs =
    { nixarchy, ... }:
    {
      nixosConfigurations."@hostname@" = nixarchy.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        # The module takes `inputs` and reads inputs.self for its own outputs,
        # so hand it nixarchy's inputs with nixarchy standing in as self.
        specialArgs = {
          inputs = nixarchy.inputs // {
            self = nixarchy;
          };
        };
        modules = [
          nixarchy.nixosModules.nixarchy
          nixarchy.inputs.home-manager.nixosModules.home-manager
          nixarchy.inputs.disko.nixosModules.disko
          (import "${nixarchy}/installer/host.nix" {
            hostname = "@hostname@";
            username = "@username@";
          })
          (import ./disk-config.nix {
            device = "@device@";
            # Quoted deliberately: the bare token is not valid Nix -- the
            # file would not parse, let alone format -- so the installer
            # substitutes the quotes away along with it. The autologin flag in
            # configuration.nix is quoted for the same reason.
            encrypt = "@encrypt@";
          })
          ./configuration.nix
        ];
      };
    };
}
