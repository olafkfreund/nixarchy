# The `hyprland-ai-mirror` template: the `hyprland` template with ai-mirror
# inside, so an MCP agent on the host drives a disposable desktop instead of
# the real one. #1504.
#
# Why each piece is here (measured 2026-10-29, see the spec):
# - Control is granted without asking: starting the VM is the consent, so a
#   user service confirms every pending request through the guest's own CLI.
#   It is a polling loop, not a path unit -- a path unit missed the first
#   request after a cold boot, before Hyprland was up.
# - The host reaches the guest over vsock only, port 7000. There is no SSH.
#   The CID is per VM, chosen at run time by vsock-cid.sh and kept in the VM's
#   directory, so several of these can run at once. #1508.
#
# The ai-mirror half lives in ai-mirror-guest.nix, shared with nixarchy-desktop.
{
  # Order matters: it fixes the order of systemPackages, so the toplevel hash.
  imports = [
    ./ai-mirror-guest.nix
    ./hyprland.nix
  ];
}
