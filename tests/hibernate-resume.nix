{ inputs, pkgs }:
# The Hibernate row on a machine with resume configured, and without (#1303).
# Why: tests/AGENTS.md#menu-conditions-and-hibernate-resume
let
  omarchy = (pkgs.extend inputs.self.overlays.default).omarchy;
  # Only the script, so the guest does not carry the whole tree.
  avail = pkgs.runCommand "omarchy-hibernation-available" { } ''
    install -m755 ${omarchy}/share/omarchy/bin/omarchy-hibernation-available $out
  '';
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-hibernate-resume";
  nodes.machine = {
    virtualisation.memorySize = 1024;
    virtualisation.emptyDiskImages = [ 2048 ];
    zramSwap.enable = true;
    boot.resumeDevice = "/dev/vdb";
  };
  testScript = ''
    q = "busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate"
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkswap /dev/vdb && swapon /dev/vdb")
    answer = machine.succeed(q).strip()
    assert answer == 's "yes"', f"resume configured: CanHibernate said {answer}"
    status, _ = machine.execute("${avail}")
    assert status == 0, f"omarchy-hibernation-available exited {status} with resume configured"
    machine.succeed("swapoff /dev/vdb")
    answer = machine.succeed(q).strip()
    assert answer == 's "na"', f"zram only: CanHibernate said {answer}"
    status, _ = machine.execute("${avail}")
    assert status != 0, "omarchy-hibernation-available exited 0 with only zram"
  '';
}
