{ pkgs, ... }:
let
  keys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-sshd-login";

  nodes = {
    hardened =
      { lib, ... }:
      {
        imports = [ ../modules/services/openssh.nix ];
        options.programs.nixarchy.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        config = {
          programs.nixarchy.enable = true;
          programs.nixarchy.services.openssh.enable = true;
          users.users.alice = {
            isNormalUser = true;
            password = "secret";
            openssh.authorizedKeys.keys = [ keys.snakeOilEd25519PublicKey ];
          };
        };
      };

    plain = {
      services.openssh.enable = true;
      users.users.alice = {
        isNormalUser = true;
        password = "secret";
        openssh.authorizedKeys.keys = [ keys.snakeOilEd25519PublicKey ];
      };
    };

    client.environment.systemPackages = [ pkgs.sshpass ];
  };

  testScript =
    { nodes, ... }:
    ''
      start_all()
      for m in (hardened, plain):
          m.wait_for_unit("sshd.service")
          m.wait_for_open_port(22)
      client.wait_for_unit("multi-user.target")
      client.succeed("install -D -m600 ${keys.snakeOilEd25519PrivateKey} /root/.ssh/id_ed25519")

      opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
      def with_password(host, method):
          return (f"sshpass -p secret ssh {opts} -o PubkeyAuthentication=no "
                  f"-o PreferredAuthentications={method} -o NumberOfPasswordPrompts=1 alice@{host} true 2>&1")

      # Without these two, a broken client makes every refusal below read as a pass.
      client.succeed(with_password("plain", "password"))
      client.succeed(with_password("plain", "keyboard-interactive"))

      client.succeed(f"ssh {opts} -o BatchMode=yes alice@hardened true")

      # The method list is the assertion: a network failure also makes `fail` pass.
      for method in ("password", "keyboard-interactive"):
          out = client.fail(with_password("hardened", method))
          assert "Permission denied (publickey)" in out, out

      t = hardened.succeed("${nodes.hardened.services.openssh.package}/bin/sshd -T").lower()
      assert "passwordauthentication no" in t, t
      assert "kbdinteractiveauthentication no" in t, t
    '';
}
