# The flatpak catalogue, as options.
#
# data/flatpaks.nix says what is on offer; this turns a selection into
# services.flatpak.packages, and declares any remote those entries need.
#
# The bar for an entry lives in the data file's header and is the interesting
# part: a flatpak belongs there only when nixpkgs cannot carry the thing. This
# file just wires up whatever survived that test.
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.nixarchy;
  flatpaks = import ../data/flatpaks.nix;

  enabled = lib.filterAttrs (name: _: cfg.flatpaks.apps.${name}.enable) flatpaks;

  # Flathub, plus whatever the enabled entries bring with them.
  #
  # The `++` is the whole point. nix-flatpak's `remotes` defaults to a list
  # holding only Flathub, and it is a plain option default -- setting it
  # REPLACES that list rather than adding to it. An entry from NVIDIA's
  # repository declared carelessly would therefore remove Flathub from the
  # machine, and nothing would say so: the apps already installed from it keep
  # working, and the next one simply cannot be found.
  flathub = {
    name = "flathub";
    location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
  };

  extraRemotes = lib.unique (
    lib.mapAttrsToList (_: fp: fp.remote) (lib.filterAttrs (_: fp: fp ? remote) enabled)
  );
in
{
  options.programs.nixarchy.flatpaks.apps = lib.mapAttrs (
    _: fp:
    lib.mkOption {
      type = lib.types.submodule {
        options.enable = lib.mkEnableOption "${fp.label} (${fp.category}), as a Flatpak";
      };
      default = { };
      description = fp.note;
    }
  ) flatpaks;

  config = lib.mkIf (cfg.enable && enabled != { }) {
    # Only when something is actually selected. Turning the daemon on for a
    # machine that has picked nothing would add a service, a set of portals
    # and a system user to every install, for nothing.
    services.flatpak = {
      enable = true;
      remotes = [ flathub ] ++ extraRemotes;
      packages = lib.mapAttrsToList (_: fp: {
        inherit (fp) appId;
        origin = if fp ? remote then fp.remote.name else "flathub";
      }) enabled;
    };
  };
}
