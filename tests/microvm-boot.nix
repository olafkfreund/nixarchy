# Boots a MicroVM. checks.microvm-template reads a runner without ever
# starting a kernel; this is the other half of #228 -- a declared machine
# (modules/services/microvm.nix) actually reaching multi-user inside a NixOS
# test VM, on GitHub's own runners.
#
# ## Why this can run in CI at all
#
# ubuntu-latest x86_64 runners have had /dev/kvm since 2023, so the test node
# (L1) runs accelerated. The MicroVM inside it (L2) cannot: there is no
# nested virtualisation, and `-enable-kvm` is passed hard by the default
# runner with no TCG fallback -- which is exactly why the `-tcg` variant
# (`microvm.cpu = "max"`; the same `cpu != null` branch that changes `-cpu`
# also removes `-enable-kvm`) is a shipped artifact and the one this check
# boots. The KVM path -- what nearly every user runs -- is pkgs/verify.sh's
# job, on real hardware; #221 says outright it is not provable here.
#
# ## What is asserted, from inside a running guest
#
#   * `microvm@sandbox.service` comes up under systemd -- the declarative
#     half's whole promise. Breaking this looks like `autostart = false`
#     (proved red exactly that way for the PR).
#   * ssh over the forwarded SLiRP port reaches the guest -- `sshPort` is
#     compiled into this machine's own closure (#221's argument for why SSH
#     belongs only to the declarative half), so this is the door working.
#   * `ro-store on /nix/.ro-store type 9p` appears in the guest's mounts --
#     the claim that the store is SHARED and no image was built, verified
#     from a running guest rather than by reading a command line the way
#     checks.microvm-template does. Breaking this looks like mkForce'ing the
#     ro-store share away, which builds an erofs and still boots: ssh
#     succeeds, this grep fails.
#
# Timeout sizing, measured on the machine that matters this time. The first
# real CI execution of this check (run 33940632899, the #309 repair run --
# every earlier "run" died at workflow startup) showed the guest kernel at
# 13.2 guest-seconds after 74.8 host-seconds: a ~5.7x TCG slowdown in KERNEL
# boot on a 4-core runner, and syscall-heavy userspace init runs far slower
# than that under TCG. The old 600s wait was reasoned from a 70.8s ssh wait
# observed on a 128-core dev box with KVM at L1 -- the wrong machine. 1200s
# fits the job's 30-minute budget beside the ~5 minutes of setup the failed
# run measured, with margin.
{ inputs, pkgs }:
let
  # nixpkgs' own test-only snakeoil keypair (RFC 9500) -- reused rather than
  # minting one here, because a keypair generated at build time would need
  # `builtins.readFile` on a derivation output (IFD) to reach the guest's
  # authorized_keys at evaluation.
  keys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;

  sshPort = 2222;
  # -n matters: without it ssh reads the test driver's own stdin, and the
  # second ssh call in the script deadlocks the backdoor shell (observed --
  # the first call exited before it could eat anything, the second hung for
  # twelve minutes on `mount`).
  ssh = "ssh -n -i /root/snakeoil -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p ${toString sshPort} dev@localhost";
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-microvm-boot";

  nodes.machine = {
    imports = [ inputs.self.nixosModules.nixarchy ];

    # A minimal host: no desktop, no Hyprland. What is under test is the
    # microvm service, and the session has its own checks.
    programs.nixarchy = {
      enable = true;
      session = false;
      displayManager = false;
      services.microvm = {
        enable = true;
        # No session user on this host to grant `kvm` to -- and L1 has no
        # working /dev/kvm anyway; the guest below is the -tcg runner.
        user = null;
        machines.sandbox = {
          template = "shell";
          inherit sshPort;
          modules = [
            {
              # The -tcg runner, exactly as flake.nix builds `microvm-*-tcg`:
              # this is the one artifact a host without /dev/kvm can boot,
              # and CI is such a host (no nested virtualisation).
              microvm.cpu = "max";
              users.users.dev.openssh.authorizedKeys.keys = [ keys.snakeOilEd25519PublicKey ];
            }
          ];
        };
      };
    };

    # Room for a 1 GiB guest plus the host itself, and a second core so the
    # emulated guest does not starve the node running it.
    virtualisation.memorySize = 4096;
    # All four of the runner's cores: the single TCG vCPU thread, qemu's
    # I/O threads and the host's own userspace were sharing two.
    virtualisation.cores = 4;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # The declared machine came up under systemd. `autostart = true` (the
    # default) wants it from microvms.target; a machine that fails to exec
    # its runner fails this unit, loudly.
    # 300s, not the driver's 900s default: the unit is started at boot, so
    # three minutes late is already "not coming", and an autostart regression
    # should fail in five minutes rather than fifteen.
    machine.wait_for_unit("microvm@sandbox.service", timeout=300)

    # A TCG guest boots in minutes, not seconds. sshd is one of the last
    # things multi-user brings up, so this wait covers the whole guest boot.
    machine.succeed("install -m 600 ${keys.snakeOilEd25519PrivateKey} /root/snakeoil")
    machine.wait_until_succeeds("${ssh} true", timeout=1200)

    # The store is shared, not imaged -- asserted from inside the guest.
    mounts = machine.succeed("${ssh} mount")
    assert "ro-store on /nix/.ro-store type 9p" in mounts, (
        "the guest's store is not the host's 9p share:\n" + mounts
    )
  '';
}
