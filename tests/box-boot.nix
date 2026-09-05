# Creates and enters a real box. checks.box-template reads the catalogue and
# `nixarchy box` structurally, and deliberately stops short of the one step
# that can fail offline: the first-start package-manager update inside a
# freshly created box. This is the other half of #262 -- the same split
# #224/#228 used for microvm.
#
# ## Why this can run with no network
#
# The epic's own audit (#230), each point verified from nixpkgs source by
# tests/box-template.nix already: `dockerTools.pullImage` is fixed-output, so
# the pinned base image is in the store before the test starts; `podman load`
# registers it inside the VM; and `distrobox create` skips its own pull once
# `podman inspect --type image` finds it (the catalogue's `pull=false`).
# Rootless podman inside a NixOS test VM is what nixpkgs' own podman test
# proves; the `su -l` + linger arrangement below is copied from it.
#
# ## What is asserted
#
#   * `nixarchy box create` -- the real command, which calls
#     `distrobox-assemble` by BARE NAME -- creates a container from the
#     preloaded image, with no network. Breaking this looks like skipping the
#     preload: create tries to pull and fails (proved red exactly that way
#     for the PR).
#   * the created container's recorded distrobox-init mount does NOT point
#     into /nix/store -- pkgs/box.nix's header rule (nixpkgs#478154),
#     observed on a real container rather than grepped off a script the way
#     checks.box-template does. Breaking this looks like calling
#     distrobox-assemble through its literal store path.
#   * what `distrobox enter <name> -- true` does with NO network at all --
#     the epic's stated unknown, answered by observation: it does not reach
#     a shell (see the last block below for the measured behaviour and why
#     it is asserted as a loud, named failure rather than a success).
{
  inputs,
  pkgs,
  imagePin,
}:
let
  # The same pin checks.box-template builds -- one entry, the default
  # template's. finalImageTag matters: the tarball's RepoTags must say
  # `latest` so the tag below can name it.
  image = pkgs.dockerTools.pullImage {
    inherit (imagePin) imageName imageDigest sha256;
    finalImageTag = imagePin.tag or "latest";
  };
  fullImage = "docker.io/library/${imagePin.imageName}:${imagePin.tag or "latest"}";
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-box-boot";

  nodes.machine = {
    imports = [ inputs.self.nixosModules.nixarchy ];

    # A minimal host: no desktop. What is under test is the boxes service.
    programs.nixarchy = {
      enable = true;
      session = false;
      displayManager = false;
      services.boxes.enable = true;
    };

    # Rootless: a plain normal user, nothing more -- NixOS allocates the
    # subuid/subgid ranges automatically, which is half of #230's argument
    # for podman over docker here.
    users.users.alice.isNormalUser = true;

    # An OCI userland unpacked into ~alice/.local/share/containers does not
    # fit the test driver's 1 GiB default disk.
    virtualisation.diskSize = 8192;
    virtualisation.memorySize = 3072;
  };

  testScript = ''
    import shlex

    def alice(cmd):
        return f"su alice -l -c {shlex.quote(cmd)}"

    machine.wait_for_unit("multi-user.target")
    # The systemd user session rootless podman wants -- nixpkgs' own podman
    # test does exactly this before its rootless subtests.
    machine.succeed("loginctl enable-linger alice")

    # Preload the pinned image. The tarball's RepoTags is the short
    # "${imagePin.imageName}:${imagePin.tag or "latest"}"; the catalogue INI names ${fullImage},
    # so tag it under the full name too (podman may already have normalised
    # it -- the || true covers that, and the inspect below is the assertion).
    machine.succeed(alice("podman load -i ${image}"))
    machine.succeed(alice("podman tag ${imagePin.imageName}:${imagePin.tag or "latest"} ${fullImage} || true"))
    machine.succeed(alice("podman inspect --type image ${fullImage} >/dev/null"))

    # The real command, end to end: nixarchy box -> distrobox-assemble (bare
    # name) -> distrobox create. pull=false plus the preload above is what
    # makes this work with no network at all.
    machine.succeed(alice("nixarchy box create scratch --template archlinux"), timeout=600)

    # The rule pkgs/box.nix exists to enforce, observed on the container
    # podman actually recorded: the distrobox-init entrypoint mount must
    # survive a generation change plus nix-collect-garbage, so it must not
    # be a /nix/store path (nixpkgs#478154). Both halves asserted -- that an
    # init mount exists at all, and that it is not a store path -- so this
    # cannot go green by the mount disappearing.
    inspect = machine.succeed(alice("podman inspect scratch"))
    assert "distrobox-init" in inspect, "no distrobox-init mount recorded at all:\n" + inspect[:2000]
    import re
    stores = re.findall(r"/nix/store/\S*distrobox\S*", inspect)
    assert not stores, "the container records a store path to distrobox: " + repr(stores)

    # First start, offline -- the epic's stated unknown, ANSWERED by this
    # check rather than assumed: with no resolvable network at all,
    # distrobox-init's first-start `pacman -Syy` fails ("Could not resolve
    # host: geo.mirror.pkgbuild.com"), init aborts, and enter reports "could
    # not start entrypoint". It does NOT reach a shell. That contradicts the
    # branch-tested note data/box-templates.nix carried (amended in the same
    # commit as this file) -- the branch test evidently had DNS.
    #
    # Asserted as observed, not as hoped, so this stays honest either way:
    # a real user creates a box online (the image pull needs the network
    # anyway), so first-start with working DNS is the shipped path -- what
    # this pins is that the failure is LOUD and named, not a hang or a
    # half-initialised shell. If a distrobox bump ever makes offline
    # first-start survive, this goes red and gets retargeted to succeed(),
    # with a PR that says so.
    out = machine.fail(alice("distrobox enter scratch -- true 2>&1"), timeout=600)
    assert "could not start entrypoint" in out, (
        "offline first enter failed some OTHER way than the entrypoint abort this pins:\n" + out
    )
  '';
}
