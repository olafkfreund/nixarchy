# What `nixarchy box create --template <t>` feeds to `distrobox-assemble`, and
# what `nixarchy box promote` prints as a
# `programs.nixarchy.services.boxes.machines.<name>` snippet.
#
# The fifth catalogue: data/apps.nix installs, data/services.nix turns on,
# data/flatpaks.nix reaches what nixpkgs cannot, data/devenv-presets.nix seeds a
# project file, and this one assembles a container. Same bar
# data/devenv-presets.nix already sets for itself, for the same reason: `ini` is
# pasted into a `distrobox-assemble` block verbatim, in the exact shape
# distrobox's own manual and INI examples show, with no nixarchy vocabulary in
# it. A user who outgrows a template grows it from distrobox's own
# documentation, and ecosystem drift -- a new base image, a renamed field --
# stays upstream's problem rather than a thing this file has to track.
#
# ## What is checked, and what is not
#
# `ini` is a string; a typo in a field name is a string with a typo in it and
# Nix will never say a word. `checks.box-template` (a later issue) reads the
# generated INI structurally -- does it parse, does it name an `image` -- but
# does not create a container from it, because the one step that can fail is
# the first-start package manager update inside the box, which needs a live
# network `checks.box-template` intentionally does not have. That live check is
# `checks.box-boot`, also a later issue.
#
# ## Fields
#   label   Shown by `nixarchy box templates`.
#   ini     The distrobox-assemble block, written flush left: `image`, and any
#           of `additional_packages`, `init_hooks`, `volume`, `exported_apps`,
#           `exported_bins`, `entry`, `start_now`, `replace`, `pull` a template
#           needs. Verbatim upstream syntax -- see the bar above.
#   note    What the box is for and what it costs, the way data/services.nix's
#           `note` field does -- not what distrobox is.
{
  archlinux = {
    label = "Arch Linux";
    note = "distrobox's own default base image. AUR packages, and Arch-only tooling nixpkgs does not carry.";
    ini = ''
      image=docker.io/library/archlinux:latest
      pull=false
      replace=false
      start_now=false
    '';
  };
}
