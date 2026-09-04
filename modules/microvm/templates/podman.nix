# The `podman` template. Root is still tmpfs -- like every other template,
# it is thrown away every boot -- but pulled images are the expensive part of
# a container workflow, and losing those on every restart would make this
# template worse than useless. So `/var/lib/containers` gets its own 20 GiB
# volume, a RELATIVE image path in the VM's own directory
# (data/microvm-templates.nix's rule: this is what lets one closure serve
# every VM of this template, each with its own image).
#
# Containers inside a MicroVM is the case that justifies a kernel of your
# own: podman's own rootless mode already gets you most of an isolated
# container without one, but a MicroVM boundary is a real one -- podman
# inside it can be handed CAP_SYS_ADMIN, `--privileged`, or a kernel module
# nobody would grant on the host.
{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  microvm.volumes = [
    {
      image = "var-lib-containers.img";
      mountPoint = "/var/lib/containers";
      size = 20 * 1024;
      fsType = "ext4";
      autoCreate = true;
    }
  ];
}
