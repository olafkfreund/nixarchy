# The `shell` template, and the plainest thing data/microvm-templates.nix's
# bar allows: nothing beyond what modules/microvm/guest.nix already gives
# every guest. Its whole job is proving that a template CAN be this small --
# every option a user meets typing at the prompt this produces comes from
# NixOS itself or from microvm.nix, not from a line written here.
#
# #225 grows `python`, `podman` and `persistent` from this file; each adds
# exactly the packages or options its name promises and nothing this repo
# would have to keep matching upstream forever.
{
  # Nothing else. modules/microvm/guest.nix already supplies the shared
  # store, the host-directory share, user networking, autologin and the
  # runtime hostname -- see that file for why each one is there.
}
