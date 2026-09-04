# The `persistent` template: `shell` plus a `/home` that survives a restart.
#
# The volume goes in the VM's own directory (a RELATIVE image path, same rule
# as `podman`'s), so `nixarchy vm rm <name>` deleting that directory is what
# makes the image go too -- there is no separate cleanup step, and no image
# left behind for a template this repo later drops.
#
# The root filesystem is NOT part of that promise: modules/microvm/guest.nix
# gives every template a tmpfs root, and this template does not change that.
# Everything outside /home is thrown away at every boot, exactly as it is on
# `shell`.
{
  imports = [ ./shell.nix ];

  microvm.volumes = [
    {
      image = "home.img";
      mountPoint = "/home";
      size = 10 * 1024;
      fsType = "ext4";
      autoCreate = true;
    }
  ];
}
