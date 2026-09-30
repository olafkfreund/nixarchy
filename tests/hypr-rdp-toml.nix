{ inputs, pkgs }:
let
  options = {
    bind = "host\"\\name:3389";
    username = "user\"\\name";
    output = "DP-\"\\1";
    cert = "/tmp/cert\"\\x.pem";
    key = "/tmp/key\"\\x.pem";
  };
  machine = inputs.self.nixosConfigurations.reference.extendModules {
    modules = [
      {
        programs.nixarchy.services.hypr-rdp = {
          enable = true;
          passwordSecret = "rdp-password";
          inherit (options) bind username output;
          certFile = options.cert;
          keyFile = options.key;
        };
        sops = {
          validateSopsFiles = false;
          age.keyFile = "/var/lib/sops-nix/key.txt";
          defaultSopsFile = ../flake.nix;
          secrets.rdp-password = { };
        };
      }
    ];
  };
  cfg = machine.config;
  unit = cfg.systemd.user.services.hypr-rdp.serviceConfig;
  guardArgs = pkgs.lib.splitString " " unit.ExecStartPre;
in
pkgs.runCommand "nixarchy-hypr-rdp-toml"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    expectedOptions = builtins.toJSON options;
    guard = builtins.elemAt guardArgs 0;
    publicConfig = builtins.elemAt guardArgs 2;
    template = cfg.sops.templates."hypr-rdp.toml".file;
    execStart = unit.ExecStart;
    preOutput = builtins.elemAt guardArgs 3;
    runtimeDirectory = unit.RuntimeDirectory;
    runtimeMode = unit.RuntimeDirectoryMode;
  }
  ''
    python3 - <<'PY'
    import json
    import os
    from pathlib import Path
    import re
    import subprocess
    import tempfile
    import tomllib

    def need(ok, message):
        if not ok:
            raise SystemExit("FAIL: " + message)

    template = Path(os.environ["template"]).read_text()
    need(re.fullmatch(r"<SOPS:[^>]+>\n?", template) is not None,
         "store template is not just a sops placeholder")
    need(os.environ["runtimeDirectory"] == "hypr-rdp", "wrong runtime directory")
    need(os.environ["runtimeMode"] == "0700", "runtime directory is not private")
    need(os.environ["preOutput"] == "%t/hypr-rdp/hypr-rdp.toml",
         "guard writes the wrong runtime path")
    need(os.environ["execStart"].endswith(" --config %t/hypr-rdp/hypr-rdp.toml"),
         "daemon reads a different config path")

    expected = json.loads(os.environ["expectedOptions"])
    password = 'quote"back' + chr(92) + 'q' + chr(92) + 'b'
    with tempfile.TemporaryDirectory(dir=os.getcwd()) as sandbox:
        root = Path(sandbox)
        runtime = root / "hypr-rdp"
        runtime.mkdir(mode=0o700)
        output = runtime / "hypr-rdp.toml"
        stage = root / "password"

        def run(raw):
            if raw is None:
                stage.unlink(missing_ok=True)
            else:
                stage.write_bytes(raw)
            return subprocess.run(
                [os.environ["guard"], str(stage), os.environ["publicConfig"], str(output)],
                capture_output=True, text=True,
                env={**os.environ, "PATH": "/nonexistent"},
            )

        result = run(password.encode())
        need(result.returncode == 0, "guard refused quoted password: " + result.stderr)
        parsed = tomllib.loads(output.read_text())
        need(parsed.pop("password") == password,
             "parsed password differs from the raw secret")
        need(parsed == expected, "parsed nonsecret fields changed value")
        need(output.stat().st_mode & 0o777 == 0o400, "final config is not 0400")
        need(runtime.stat().st_mode & 0o777 == 0o700, "runtime directory is not 0700")
        print("hypr-rdp TOML preserves quotes, backslashes, and all option values")

        for label, raw in [
            ("missing", None), ("empty", b""),
            ("newline", b"bad\nline"), ("tab", b"bad\tline"),
            ("carriage return", b"bad\rline"), ("NUL", b"bad\x00line"),
            ("DEL", b"bad\x7fline"),
        ]:
            output.unlink(missing_ok=True)
            result = run(raw)
            need(result.returncode != 0, label + " password was accepted")
            need(not output.exists(), label + " left a final config")
            need("Refusing to start" in result.stderr,
                 label + " refusal lacks a clear error")
            need("bad" not in result.stderr, label + " leaked the password")
        print("hypr-rdp refuses absent, empty, and control-byte passwords")
    PY
    touch "$out"
  ''
