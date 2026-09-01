# Services and system settings a desktop user actually asks for, mapped to how
# NixOS turns them on.
#
# The companion to data/apps.nix, and deliberately shaped differently. An app is
# a package: install it and it is there. A service is a decision about the
# machine, and the useful ones are rarely a single option -- Docker without
# group membership is a Docker you have to sudo at, printing without avahi finds
# no printers, Tailscale without a trusted interface has a firewall in the way.
#
# ## Two kinds, and the difference is the whole design
#
#   kind = "plain"     A one-to-one toggle. nixarchy has nothing to add, so it
#                      adds nothing: the generated file gets the real upstream
#                      line, `services.openssh.enable = true;`, and there is no
#                      nixarchy option at all. That line is what every wiki
#                      page, forum answer and tutorial will show them, and a
#                      second vocabulary is a thing to unlearn later.
#
#   kind = "bundled"   nixarchy genuinely integrates several options, so it
#                      earns an option of its own in modules/services/<id>.nix.
#                      The file gets `programs.nixarchy.services.docker.enable`.
#
# The bar for "bundled" is high on purpose. RFC 42 makes the argument against
# copying upstream options: they go stale, upstream removals break the wrapper,
# and an option cannot realistically be removed once added. So a wrapper has to
# pay for itself in integration a newcomer would not find alone. If the answer
# is one line, it is "plain".
#
# ## Fields
#   label      Shown in the generated template and the menu.
#   category   Groups rows in the template.
#   kind       "plain" or "bundled", as above.
#   option     Required for "plain": the upstream option path, written into the
#              template as `<path>.enable = true;`. Meaningless for "bundled",
#              whose module decides what to set.
#   note       Anything a reader would otherwise discover the hard way. This is
#              the field that does the teaching -- say what turning it on costs
#              or opens, not what it is.
#   unfree     Marks a service pulling unfree packages.
# ## Not listed here, because they are already on
#
# modules/nixos.nix enables these for every nixarchy machine, at mkDefault, so
# a catalogue entry would be an option that changes nothing:
#
#   virtualisation.docker.enable        nixos.nix:705
#   services.printing.enable            nixos.nix:634
#   services.avahi.{enable,nssmdns4}    nixos.nix:635-639
#
# If one of those should become a choice rather than a default, that is a
# change to nixos.nix and an announcement, not a row added here.
#
# Tailscale is also absent, for a different reason: data/apps.nix still owns
# it, and moving it means moving its menu row, which is #94. Adding it here
# first would generate a template line for an option that does not exist yet.
{
  # ── Network ─────────────────────────────────────────────────────────────
  openssh = {
    label = "OpenSSH server";
    category = "Network";
    kind = "plain";
    option = [
      "services"
      "openssh"
    ];
    note = "Remote login. Opens port 22 and NixOS defaults to keys only, not passwords.";
  };

  # ── Hardware ────────────────────────────────────────────────────────────

  graphics32 = {
    label = "32-bit graphics";
    category = "Hardware";
    kind = "plain";
    option = [
      "hardware"
      "graphics"
    ];
    optionAttr = "enable32Bit";
    note = "Wanted by Steam, Wine and older games. One switch covers every driver.";
  };

  # ── Desktop ─────────────────────────────────────────────────────────────
  flatpak = {
    label = "Flatpak";
    category = "Desktop";
    kind = "plain";
    option = [
      "services"
      "flatpak"
    ];
    note = "For software nixpkgs does not carry. Then: flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo";
  };

  syncthing = {
    label = "Syncthing";
    category = "Desktop";
    kind = "bundled";
    note = "Syncs folders between your machines. Bundled because it runs as you, and upstream cannot know which user that is.";
  };
}
