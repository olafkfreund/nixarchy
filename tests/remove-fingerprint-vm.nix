{ pkgs }:
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-remove-fingerprint-vm";

  nodes.machine =
    { lib, ... }:
    {
      services.fprintd.enable = true;
      users.users = {
        alice = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          password = "secret";
        };
        bob.isNormalUser = true;
      };
      security.sudo.wheelNeedsPassword = false;
      security.pam.services.omarchy-lock-password = { };
      environment.systemPackages = [ pkgs.pamtester ];
      systemd.services.fprintd = {
        environment.FP_VIRTUAL_DEVICE_STORAGE = "/run/fprintd-virt/sock";
        serviceConfig = {
          RuntimeDirectory = "fprintd-virt";
          # The unit file has its own ExecStart, so the empty entry clears it first.
          ExecStart = lib.mkForce [
            ""
            "${pkgs.fprintd}/libexec/fprintd --no-timeout"
          ];
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    # The first D-Bus request activates fprintd.
    machine.execute("${pkgs.fprintd}/bin/fprintd-list alice")
    machine.wait_until_succeeds("test -S /run/fprintd-virt/sock", timeout=60)

    def send(command):
        machine.succeed("${pkgs.python3}/bin/python3 -c 'import socket, sys; s = socket.socket(socket.AF_UNIX); s.connect(\"/run/fprintd-virt/sock\"); s.sendall((sys.argv[1] + \"\\n\").encode()); s.close()' " + command)

    def stored():
        return machine.succeed("${pkgs.python3}/bin/python3 -c 'import socket; s = socket.socket(socket.AF_UNIX); s.connect(\"/run/fprintd-virt/sock\"); s.sendall(b\"LIST\\n\"); print(s.recv(4096).decode())'")

    send("SET_ENROLL_STAGES 1")
    for user in ("alice", "bob"):
        machine.succeed(f"sudo ${pkgs.fprintd}/bin/fprintd-enroll -f right-index-finger {user} > /tmp/enroll-{user} 2>&1 < /dev/null &")
        send(f"SCAN {user}-id")
        machine.wait_until_succeeds(f"grep -q 'enroll-completed' /tmp/enroll-{user}")
        machine.succeed(f"test -d /var/lib/fprint/{user}")
    before = stored()
    assert "alice-id" in before and "bob-id" in before, before

    status, out = machine.execute("su - alice -c 'PATH=${shipped}/share/omarchy/bin:${pkgs.fprintd}/bin:$PATH bash ${shipped}/share/omarchy/bin/omarchy-remove-security-fingerprint' 2>&1")
    assert status == 0, out
    assert "Deleted alice's saved fingerprints" in out, out
    machine.succeed("test ! -e /var/lib/fprint/alice")
    machine.succeed("test -d /var/lib/fprint/bob")
    listed = machine.succeed("${pkgs.fprintd}/bin/fprintd-list alice")
    assert "has no fingers enrolled" in listed, listed

    second = machine.succeed("${pkgs.fprintd}/bin/fprintd-delete alice")
    print(second)
    assert "No fingerprints to delete on" in second, second

    send("REMOVE alice-id")
    machine.wait_until_succeeds("journalctl -u fprintd --no-pager | grep -E 'alice-id.*not found in storage|not found in storage.*alice-id'")
    send("REMOVE bob-id")
    machine.succeed("sleep 1")
    assert "bob-id" not in stored(), "bob's reader print was not removed by the control command"
    journal = machine.succeed("journalctl -u fprintd --no-pager")
    assert not any("bob-id" in line and "not found in storage" in line for line in journal.splitlines()), journal

    for service in ("sudo", "omarchy-lock-password"):
        command = f"su - alice -c \"printf 'secret\\n' | pamtester {service} alice authenticate\""
        machine.succeed(command)
        wrong = f"su - alice -c \"printf 'wrong\\n' | pamtester {service} alice authenticate\""
        machine.fail(wrong)
  '';
}
