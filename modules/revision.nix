self: {
  # Why: docs/internals/flake.md#which-nixarchy-built-this-machine-208-for-nixarchy
  shortRev = self.shortRev or self.dirtyShortRev or "unknown";
  # `lastModifiedDate` is absent, not empty, when a lock node has no
  # `lastModified` -- which is what installer/mkFlake.nix used to write,
  # and is why the offline install broke the first time this landed: the
  # generated flake evaluated a DIFFERENT omarchy than the installer had
  # seeded, for want of one field. mkFlake now writes it. The fallback
  # stays for the machines whose flake.lock was generated before it did:
  # they get "unknown" and a rebuild that has a network, rather than an
  # evaluation error on a system they cannot rebuild to fix.
  date =
    let
      d = self.lastModifiedDate or "";
    in
    if d == "" then
      "unknown"
    else
      "${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}";
}
