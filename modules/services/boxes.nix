# Boxes: distrobox, for software NixOS will not run.
#
# nixpkgs already answers "this is not packaged" three ways -- Flatpak, nix-ld
# for a loose binary, an FHS wrapper for something like Steam -- and none of
# them cover software that wants an entire other distro: a .deb with a
# postinstall script, an AUR package, a vendor installer that writes to /opt.
# distrobox is an OCI container tightly integrated with the host (your $HOME,
# not a sandbox -- see docs/manual/boxes.md for the full "what this is not")
# and rootless podman is what runs it.
#
# Bundled rather than plain for the same reason Docker already is: turning
# podman on by itself gets you a working container runtime, but the point of
# this feature is boxes a desktop user can create with no root and no extra
# setup, and that is this module's job, not upstream's.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
  svc = cfg.services.boxes;

  # The exact type Home Manager's own `programs.distrobox.containers` uses --
  # not a redeclaration, a reuse. distrobox-assemble's INI accepts a bool, a
  # string or a list of strings per key (a list repeats the key), which is
  # what `pkgs.formats.ini { listsAsDuplicateKeys = true; }` already encodes.
  # Building it here rather than importing Home Manager's module for its type
  # alone is the shape modules/local-ai.nix already uses for a value it hands
  # to home-manager rather than applies itself: declare data, let the module
  # that consumes it (modules/home.nix, via Home Manager's own module) own
  # what "valid" means.
  containerIniAtom = (pkgs.formats.ini { listsAsDuplicateKeys = true; }).lib.types.atom;
in
{
  options.programs.nixarchy.services.boxes = {
    enable = lib.mkEnableOption ''
      Boxes: rootless podman plus distrobox, for an Arch or Debian userland
      when nixpkgs, Flatpak, nix-ld and devenv all answer "no". Off by
      default -- see docs/manual/boxes.md for when to reach for this instead
      of those.

      This is a compatibility layer, not a sandbox: a box gets your whole
      $HOME read-write, all of /dev, and the host root at /run/host. It sits
      in the menu next to Flatpak, which *is* a sandbox -- do not expect the
      same isolation
    '';

    machines = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf containerIniAtom);
      default = { };
      example = lib.literalExpression ''
        {
          dev = {
            image = "archlinux:latest";
            additional_packages = "git base-devel";
          };
        }
      '';
      description = ''
        Boxes that come up the same way after every rebuild, instead of
        living only in whatever was typed at a shell. Each attribute name is
        a container; its value is passed straight through to Home Manager's
        `programs.distrobox.containers`, which writes exactly the INI
        `distrobox-assemble` reads -- see that option's own documentation and
        upstream's distrobox-assemble manual for the available fields.

        Read out to Home Manager, not applied here: this is a NixOS option,
        and Home Manager's `containers` are per-user. `modules/home.nix`
        reads this attrset back out of `osConfig` and hands it to
        `programs.distrobox.containers` for the user
        `programs.nixarchy.homeManagerModules.nixarchy` is imported for. An
        empty attrset (the default) writes nothing -- Home Manager's own
        module already gates its INI file and its systemd unit on
        `containers != { }`.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && svc.enable) {
    # A scalar, so mkDefault: someone already running podman their way (or
    # rootful, deliberately) keeps their configuration and this yields to it.
    # virtualisation.docker is left untouched -- rootless podman is additive,
    # not a replacement, and boxes only need podman.
    virtualisation.podman.enable = lib.mkDefault true;

    # NixOS allocates subuid/subgid ranges to every normal user automatically,
    # which is all rootless podman needs; nothing else to declare for that
    # half.

    # A list, so plain assignment -- mkDefault on a list is dropped whole the
    # moment somebody adds a package of their own (modules/services/default.nix
    # explains why).
    #
    # distrobox itself must never be resolved through a literal /nix/store
    # path anywhere this repo runs it: it resolves its own support binaries
    # (distrobox-init, distrobox-export, ...) relative to `dirname "$0"`, so
    # invoking it via a store path bakes a generation-specific path into every
    # container it creates -- nix-collect-garbage can delete that path out
    # from under a running box (nixpkgs#478154, open, no fix). Verified with
    # `distrobox --dry-run` against the installed package: called by bare name
    # (through $PATH, which resolves through the system profile) the recorded
    # entrypoint mount tracks the current generation; called via its own
    # /nix/store/... path directly, the mount is that exact versioned path.
    # environment.systemPackages puts /run/current-system/sw/bin on every
    # interactive shell's PATH, which is sufficient -- so `nixarchy box`
    # (a later issue) must call `distrobox` by bare name too, and must not
    # list it in a writeShellApplication's runtimeInputs, which would put its
    # own store bin/ on PATH ahead of the profile and reintroduce this.
    environment.systemPackages = [ pkgs.distrobox ];
  };
}
