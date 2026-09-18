# The `k3s` template: a single-node Kubernetes that survives a restart.
#
# `/var/lib/rancher` is the volume -- a RELATIVE image path, podman.nix's
# rule -- and it is what makes this a cluster rather than a demo: the
# datastore, the images containerd pulled, the CA and the node token k3s
# generated on first boot all live under it. No token is written here:
# services.k3s passes --token only when one is set, and a server given none
# generates its own into that directory. That is the whole answer to "no
# secret in a template".
#
# traefik and servicelb are off, as in the flake this replaces. Both exist
# to expose Services outward, and nothing outward exists: guest.nix's SLiRP
# interface forwards nothing in, so kubectl inside the guest is the API in
# v1 (a permanent machine's forwarded ports are how that changes).
#
# The firewall is off for the same reason the owner's hand-kept flake turned
# it off: SLiRP already answers inbound, and nixos-fw only ever stood between
# pods on cni0 and the node's own services.
{
  services.k3s = {
    enable = true;
    role = "server";
    disable = [
      "traefik"
      "servicelb"
    ];
    # The kubeconfig k3s writes is root-only by default; `dev` is who sits at
    # the console. 644 is fine on a guest with one user and no network in.
    extraFlags = [ "--write-kubeconfig-mode=644" ];
  };

  # `kubectl` is the k3s package's own symlink (it is on PATH via
  # services.k3s); this is the one thing it needs to be told.
  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

  networking.firewall.enable = false;

  microvm = {
    volumes = [
      {
        image = "var-lib-rancher.img";
        mountPoint = "/var/lib/rancher";
        size = 20 * 1024;
        fsType = "ext4";
        autoCreate = true;
      }
    ];

    # The control plane alone idles near 1 GiB; 4 GiB leaves room for
    # workloads, and a second vCPU is the difference between a scheduler that
    # keeps up and one that does not.
    mem = 4096;
    vcpu = 2;
  };
}
