# Flatpaks worth curating, which is fewer than you would expect.
#
# The third catalogue, and the one with the highest bar. data/apps.nix lists
# what nixpkgs installs; data/services.nix lists what NixOS turns on. This
# lists software that neither can reach, and the test for an entry is exactly
# that:
#
#   A flatpak belongs here only when nixpkgs genuinely cannot carry the thing.
#
# Not "is easier as a flatpak", not "is newer on Flathub". A flatpak of
# software already in nixpkgs is strictly worse for someone on this system: it
# lives outside the store, no generation rolls it back, it updates on a
# schedule that is not yours, and `nixos-rebuild --rollback` restores the fact
# that you asked for it rather than the version you had.
#
# Measured against that bar, most of what people reach for does not qualify.
# Bottles, Zoom and OBS are all in nixpkgs. GeForce NOW is not, and there is
# no plausible way to package it -- which is why it is here and why this file
# starts with one entry rather than twenty.
#
# ## What "declared" means here, and what it does not
#
# The app ids below end up in the user's configuration and travel to their
# next machine. The BITS do not: the same id resolves to whatever Flathub is
# serving that day, unless an entry pins a commit. That is a weaker promise
# than anything else in this repo makes, and the generated file says so where
# a person will read it.
#
# ## Fields
#   appId     The reverse-DNS application id. Not a package name --
#             `com.usebottles.bottles`, never `bottles`. That is the mistake
#             to expect.
#   label     Shown in the generated template and the menu.
#   category  Groups rows in the template.
#   note      Why this one cannot come from nixpkgs. Every entry has to answer
#             that, because the bar above is the whole point of the file.
#   remote    Optional. Only for software that is NOT on Flathub, and it comes
#             as a pair: the remote's `name` and its `location`, the
#             .flatpakrepo URL that defines it. Omit for anything on Flathub,
#             which is the common case.
#
# ## Not everything worth having is on Flathub
#
# GeForce NOW is the first entry and it is not a Flathub app: NVIDIA publishes
# it from their own repository. So an entry can name a remote, and the module
# declares it alongside Flathub rather than instead of it -- nix-flatpak's
# `remotes` option defaults to a list containing only Flathub, and setting it
# REPLACES that list rather than adding to it, which is the sort of thing that
# removes Flathub from somebody's machine if nobody notices.
{
  geforce-now = {
    appId = "com.nvidia.geforcenow";
    label = "GeForce NOW";
    category = "Gaming";
    note = "Streams games from NVIDIA's servers. Not in nixpkgs and not packageable: a proprietary binary NVIDIA ships as a Flatpak. Not on Flathub either -- it comes from NVIDIA's own repository, which enabling this adds.";
    remote = {
      name = "GeForceNOW";
      location = "https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo";
    };
  };
}
