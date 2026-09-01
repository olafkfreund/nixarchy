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
{
  imports = [
    ./syncthing.nix
  ];
}
