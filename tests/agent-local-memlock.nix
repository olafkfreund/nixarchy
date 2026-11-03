# services.agent-local raises the memlock hard limit for its user, because
# omarchy-local-ai's Quadlet units ask for Ulimit=memlock=-1:-1 and rootless
# Podman cannot exceed its parent's limit. The NixOS default is 8 MB (razer
# measured 8388608), which fails every model container at start (#1577).
#
# One setting carries both places: the PAM login limit. The user manager logs
# in through PAM as systemd-user, so it gets the limit too. Measured here: with
# user@.service's LimitMEMLOCK also set and then removed, both places still read
# unlimited, and with loginLimits removed the login shell falls back to 8192.
{ inputs, pkgs }:
pkgs.testers.runNixOSTest {
  name = "nixarchy-agent-local-memlock";

  nodes.machine = {
    imports = [ inputs.self.nixosModules.nixarchy ];

    programs.nixarchy = {
      enable = true;
      session = false;
      displayManager = false;
      user = "tester";
      services.agent-local.enable = true;
    };

    users.users.tester = {
      isNormalUser = true;
      uid = 1000;
    };
    # Naming the user gives them a Home Manager config, which needs this.
    home-manager.users.tester.home.stateVersion = "25.05";

    virtualisation.memorySize = 2048;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Linger starts the user manager without a graphical login.
    machine.succeed("loginctl enable-linger tester")
    machine.wait_for_unit("user@1000.service")

    manager = machine.succeed(
        "su - tester -c 'XDG_RUNTIME_DIR=/run/user/1000 systemctl --user show -P DefaultLimitMEMLOCK'"
    ).strip()
    login = machine.succeed("su - tester -c 'ulimit -Hl'").strip()
    print(f"user manager DefaultLimitMEMLOCK={manager}; login shell ulimit -Hl={login}")

    assert manager == "infinity", (
        f"the user manager's memlock limit is {manager}, so the model containers' "
        "Ulimit=memlock=-1:-1 cannot be granted"
    )
    assert login == "unlimited", (
        f"a login shell's memlock hard limit is {login}; security.pam.loginLimits did not apply"
    )
  '';
}
