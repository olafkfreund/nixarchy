# The services nixarchy bundles, one module each.
#
# A module here has to earn its option. The catalogue in data/services.nix
# splits every entry into "plain" and "bundled" precisely so that most of them
# never reach this directory: if turning something on is one upstream line, the
# user's file gets that line and nixarchy declares nothing. RFC 42 makes the
# argument -- copied options go stale, an upstream removal breaks the wrapper,
# and an option cannot realistically be removed once it exists.
#
# What earns a module is integration a newcomer would not find alone. Syncthing
# needs to know which user it runs as, and upstream cannot know that.
#
# ## The rules, which exist because Mode A is real
#
# Someone may add nixarchy to a machine they already run and already configure.
# Everything here composes with configuration that is theirs and predates ours:
#
#   scalars, bools, enums   lib.mkDefault, always. Their plain definition
#                           outranks ours and wins silently, which is the
#                           correct outcome and the one they expect.
#
#   lists and attrsets      plain assignment. mkDefault on a merging type is a
#                           silent bug: lower-priority definitions are dropped
#                           BEFORE the merge, so our contribution disappears
#                           the moment the user adds an element of their own.
#
#   mkForce                 never. It is a one-way door -- the user then needs
#                           mkOverride 49 to get past us, and no error message
#                           NixOS produces will ever tell them that.
#
# The failure this prevents is documented rather than hypothetical: disko #441
# and home-manager #5870 are both a module setting a scalar at plain priority
# and the user having to mkForce their own configuration to escape it.
#
# ## Why this file takes `inputs`, and why the obvious simplification is wrong
#
# Almost every module here configures options NixOS already has, so `pkgs` is
# all it needs. hypr-rdp is the exception: nixpkgs does not carry the daemon,
# so its package comes from `self.overlays.default` -- and reaching `self`
# from a NixOS module means being handed it.
#
# The tempting cleanup is to delete this argument and write `pkgs.hypr-rdp`.
# It does not work, and it does not work in EITHER mode, which is the part
# worth writing down because it is invisible from inside this directory:
# nixarchy sets `nixpkgs.overlays` nowhere at all. Not here, not in
# installer/host.nix, not in the flake the installer generates. Checked, not
# assumed -- the installer-built host evaluates to
#
#   { hasHyprRdp = false; host = "installer-vm"; overlaysSet = [ ]; }
#
# and a Mode A machine is the same by construction. `pkgs.hypr-rdp` therefore
# fails at evaluation with "attribute 'hypr-rdp' missing. Did you mean
# hyprprop?", which is how this was found.
#
# That absence is a decision rather than an oversight. `nixpkgs.overlays` is
# global: setting it rewrites the package set for every module on the machine,
# including all of somebody else's in Mode A, to deliver one package that one
# option needs. So nixarchy reaches overlay packages one at a time instead --
# `(pkgs.extend inputs.self.overlays.default).<name>` as the default of a
# `package` option -- which is what modules/nixos.nix and modules/home.nix
# already do for omarchy and omarchy-nvim-config. hypr-rdp follows them.
#
# Only that one module is applied to `inputs`. The others keep the ordinary
# module signature, because giving them an argument they do not use would
# suggest they use it.
inputs: {
  imports = [
    ./boxes.nix
    ./devenv.nix
    (import ./hypr-rdp.nix inputs)
    ./syncthing.nix
    ./tailscale.nix
  ];
}
