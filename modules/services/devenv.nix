# devenv: a per-project environment that activates when you cd into it.
#
# Bundled rather than plain because there is no upstream option at all --
# devenv is a package, and a package alone does nothing. What makes it work is
# the activation hook, and that hook has to be added by hand to each of the
# three shells nixarchy already manages, in three different dialects. Plus the
# substituter, without which the first `cd` into a project compiles a toolchain
# that Cachix has already built.
#
# From nixpkgs (2.2.2 at the time of writing, tracked within weeks of
# upstream), not from `inputs.devenv`. A flake input would put a fast-moving
# pin in this repo's lock for everyone who imports nixosModules.nixarchy,
# including people who never enable this. The escape hatch for someone who
# needs a newer devenv is `package`, which costs them a line and costs nobody
# else anything.
#
# Not enabled by default and not a small closure: devenv bundles its own Nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
  svc = cfg.services.devenv;

  # `devenv`, not the store path, on purpose. The store path would keep working
  # in a shell that outlived a deselect, which sounds like a kindness and is
  # not: it would pin a generation the machine no longer has. The bare name
  # plus the guard means such a session degrades to nothing instead.
  #
  # The guard is the whole reason these are written out rather than being a
  # one-liner. Without it, every prompt in a session that started before the
  # package went away prints "devenv: command not found" -- once per prompt,
  # forever, with nothing on screen to say why.
  posixHook = shell: ''
    if command -v devenv >/dev/null 2>&1; then
      eval "$(devenv hook ${shell})"
    fi
  '';

  # fish is not a POSIX shell and none of the above is valid there.
  # `command -q` is fish's own test; `| source` is what `devenv hook --help`
  # documents. devenv's nixpkgs output ships share/fish/vendor_completions.d
  # and nothing in vendor_conf.d, so fish does NOT pick the hook up by itself
  # here despite what its help text suggests -- checked against 2.2.2.
  fishHook = ''
    if command -q devenv
        devenv hook fish | source
    end
  '';
in
{
  options.programs.nixarchy.services.devenv = {
    enable = lib.mkEnableOption ''
      devenv, with per-project environments activating on `cd` in bash, zsh
      and fish.

      A project is a `devenv.nix`; `devenv init` writes that and a
      `devenv.yaml`, and the first shell writes the `devenv.lock` that pins
      it. Nothing activates until you run `devenv allow` in that directory
      once -- consent is per-user and stays interactive, which is why this
      module does not pre-seed it.

      Note what the lockfile means: a second set of pins beside the
      system's, one per project, on its own update schedule. That is the
      cost of a per-project environment and it is worth knowing before the
      second nixpkgs is downloaded
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.devenv;
      defaultText = lib.literalExpression "pkgs.devenv";
      description = ''
        Which devenv. The default is nixpkgs', which is the point -- it
        moves with the system's nixpkgs and nothing extra lands in this
        repo's lock.

        Override it if a feature you need has not reached nixpkgs yet. That
        is one line in your own configuration rather than a flake input
        every nixarchy user carries.
      '';
    };

    binaryCache = lib.mkOption {
      type = lib.types.bool;
      default = cfg.binaryCaches;
      defaultText = lib.literalExpression "config.programs.nixarchy.binaryCaches";
      description = ''
        Add Cachix's devenv.cachix.org as a substituter, so the first `cd`
        into a project downloads what devenv's authors already built rather
        than compiling it.

        Follows programs.nixarchy.binaryCaches, because someone who turned
        that off said something about trust and not about Hyprland. Its own
        option so that decision can still be made per cache.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && svc.enable) {
    environment.systemPackages = [ svc.package ];

    programs = {
      # `lines`, which merges -- so this composes with the Omarchy rc chain
      # that modules/nixos.nix already puts here, and with anything the user
      # has written. mkDefault on a merging type would drop it entirely the
      # moment anything else defined the option, which on a nixarchy machine
      # is always.
      #
      # Deliberately NOT gated on programs.nixarchy.bashIntegration: that
      # option is about Omarchy's aliases and functions, and someone who
      # brings their own shell config still asked for devenv.
      bash.interactiveShellInit = posixHook "bash";

      # zsh and fish only when they are actually enabled, matching what
      # modules/nixos.nix does for the same reason: writing an rc for a shell
      # the machine does not have is a line nothing ever reads, and turning
      # the shell on for someone who did not ask is not this module's call.
      zsh.interactiveShellInit = lib.mkIf config.programs.zsh.enable (posixHook "zsh");
      fish.interactiveShellInit = lib.mkIf config.programs.fish.enable fishHook;
    };

    # Lists, so plain assignment -- see the header of modules/services. These
    # merge into whatever the machine already trusts.
    #
    # Whose cache this is: Cachix's, run by the same people who write devenv.
    # Trusting it is the same decision as trusting nixarchy.cachix.org, made
    # separately because it is a different party. See
    # programs.nixarchy.services.devenv.binaryCache to decline it and compile
    # locally instead.
    nix.settings = lib.mkIf svc.binaryCache {
      substituters = [ "https://devenv.cachix.org" ];
      trusted-public-keys = [
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ];
    };
  };
}
