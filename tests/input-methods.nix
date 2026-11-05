{ pkgs, reference }:
let
  tree = reference.config.programs.nixarchy.package;
  real = reference.config.i18n.inputMethod.package;
  bare = pkgs.qt6Packages.fcitx5-with-addons;
  python = pkgs.python3.withPackages (p: [ p.pygobject3 ]);
  ledger = pkgs.writeText "input-method-ledger.json" (
    builtins.toJSON (import ../data/omarchy-packages.nix)
  );
  pre = pkgs.writeText "input-method-exec-start-pre" reference.config.systemd.user.services.omarchy-fcitx5.serviceConfig.ExecStartPre;
  driver = pkgs.writeText "input-methods-check.py" ''
    import json
    import os
    from pathlib import Path
    import re
    import signal
    import subprocess
    import sys
    import time

    tree, real, bare, ledger_path, closure, pre_path, python = sys.argv[1:]
    root = Path.cwd()
    original_path = os.environ["PATH"]
    os.environ["XDG_DATA_DIRS"] = os.environ.get("ORIGINAL_XDG_DATA_DIRS", "")
    os.environ["OMARCHY_PATH"] = tree + "/share/omarchy"
    os.environ["PYTHONPATH"] = os.environ["OMARCHY_PATH"] + "/default/input-methods"
    sys.path.insert(0, os.environ["PYTHONPATH"])
    import configure as setup

    failures = []
    daemon = None
    log = root / "fcitx5.log"
    pidfile = root / "fcitx5.pid"
    profile = root / "unused"
    stubs = root / "stubs"
    stubs.mkdir()

    def require(ok, reason):
      if not ok:
        raise AssertionError(reason)

    def run(*args, check=True, **kwargs):
      return subprocess.run(args, text=True, capture_output=True, check=check, timeout=15, **kwargs)

    def stopped(pid):
      try:
        return Path(f"/proc/{pid}/stat").read_text().split(") ", 1)[1][0] == "Z"
      except FileNotFoundError:
        return True

    def stop():
      global daemon
      if pidfile.exists():
        pid = int(pidfile.read_text())
        if not stopped(pid):
          os.kill(pid, signal.SIGTERM)
        for _ in range(100):
          if stopped(pid):
            break
          time.sleep(0.1)
        require(stopped(pid), f"fcitx5 pid {pid} did not exit")
        pidfile.unlink()
      if daemon is not None:
        daemon.wait(timeout=10)
        daemon = None

    def start(package):
      global daemon
      with log.open("w") as output:
        daemon = subprocess.Popen([package + "/bin/fcitx5", "--disable", "notificationitem"],
                                  stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT)
      pidfile.write_text(str(daemon.pid))
      for _ in range(100):
        if daemon.poll() is not None:
          break
        result = run("fcitx5-remote", "-q", check=False)
        if result.returncode == 0 and result.stdout.strip():
          return
        time.sleep(0.1)
      raise AssertionError("fcitx5 daemon did not become ready; log: " + log.read_text())

    def reset(name, package=real, path_package=None, fresh=True):
      global profile, log, pidfile
      stop()
      row = root / name
      row.mkdir()
      for variable, suffix in (("HOME", "home"), ("XDG_CONFIG_HOME", "config"),
                               ("XDG_DATA_HOME", "data"), ("XDG_RUNTIME_DIR", "runtime")):
        directory = row / suffix
        directory.mkdir()
        os.environ[variable] = str(directory)
      os.chmod(os.environ["XDG_RUNTIME_DIR"], 0o700)
      os.environ["PATH"] = (path_package or package) + "/bin:" + str(stubs) + ":" + tree + "/bin:" + original_path
      os.environ["STUB_LAYOUT"] = "us"
      os.environ.pop("STUB_FAIL", None)
      log = row / "fcitx5.log"
      pidfile = row / "fcitx5.pid"
      os.environ["DAEMON_LOG"] = str(log)
      os.environ["DAEMON_PID_FILE"] = str(pidfile)
      os.environ["REAL_FCITX"] = real + "/bin/fcitx5"
      profile = row / "config/fcitx5/profile"
      if fresh:
        profile.parent.mkdir(parents=True)
        profile.write_text(setup.profile_text("us", "none"))
      start(package)

    def group():
      name = run("fcitx5-remote", "-q").stdout.strip()
      require(bool(name), "fcitx5-remote -q returned no group")
      response = run("busctl", "--user", "--json=short", "call", "org.fcitx.Fcitx5",
                     "/controller", "org.fcitx.Fcitx.Controller1", "InputMethodGroupInfo", "s", name)
      return json.loads(response.stdout)["data"][:2]

    def names():
      response = run("busctl", "--user", "--json=short", "call", "org.fcitx.Fcitx5",
                     "/controller", "org.fcitx.Fcitx.Controller1", "AvailableInputMethods")
      source = root / "available-input-methods.json"
      source.write_text(response.stdout)
      return {row[0] for row in json.loads(source.read_text())["data"][0]}

    def row(name, fn):
      try:
        fn()
        stop()
        print(name + ": PASS", flush=True)
      except Exception as error:
        failures.append(name)
        print(name + ": FAIL " + str(error), flush=True)
        if pidfile.exists() and log.exists():
          print(name + ": daemon log: " + log.read_text(), flush=True)
        try:
          stop()
        except Exception as error:
          print(name + ": cleanup failed: " + str(error), flush=True)

    hyprctl = stubs / "hyprctl"
    hyprctl.write_text("#!" + python + "/bin/python3\n" + """import json, os, sys
    if os.environ.get("STUB_FAIL"):
      sys.exit(1)
    if sys.argv[1:] == ["-j", "getoption", "input:kb_layout"]:
      print(json.dumps({"str": os.environ["STUB_LAYOUT"]}))
    elif sys.argv[1:] == ["-j", "getoption", "input:kb_variant"]:
      print('{"str":""}')
    else:
      sys.exit(1)
    """)
    hyprctl.chmod(0o755)
    restart = stubs / "omarchy-restart-xcompose"
    restart.write_text("#!" + python + "/bin/python3\n" + """import os, pathlib, signal, subprocess, time
    pidfile = pathlib.Path(os.environ["DAEMON_PID_FILE"])
    pid = int(pidfile.read_text())
    os.kill(pid, signal.SIGTERM)
    for _ in range(100):
      try:
        exited = pathlib.Path(f"/proc/{pid}/stat").read_text().split(") ", 1)[1][0] == "Z"
      except FileNotFoundError:
        exited = True
      if exited:
        break
      time.sleep(0.1)
    else:
      raise SystemExit("old fcitx5 daemon did not exit")
    with open(os.environ["DAEMON_LOG"], "w") as output:
      daemon = subprocess.Popen([os.environ["REAL_FCITX"], "--disable", "notificationitem"],
                                stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                start_new_session=True)
    pidfile.write_text(str(daemon.pid))
    """)
    restart.chmod(0o755)

    def ledger_row():
      presets = json.loads((Path(os.environ["OMARCHY_PATH"]) / "default/input-methods/presets.json").read_text())
      wanted = {package for preset in presets.values() for package in preset["packages"]}
      ledger = json.loads(Path(ledger_path).read_text())
      actual = {key for key, value in ledger.items()
                if value.get("module") == "i18n.inputMethod.fcitx5.addons"}
      require(wanted == actual, "missing ledger rows: " + repr(sorted(wanted - actual)) +
              "; extra ledger rows: " + repr(sorted(actual - wanted)))

    def cost_row():
      result = run("grep", "-q", "qtwebengine", closure, check=False)
      require(result.returncode == 1,
              "qtwebengine is in the fcitx5 closure" if result.returncode == 0 else
              "could not read closure store-paths: " + result.stderr.strip())

    def engines_row():
      reset("engines")
      presets = json.loads((Path(os.environ["OMARCHY_PATH"]) / "default/input-methods/presets.json").read_text())
      missing = set(presets) - {"none"} - names()
      require(not missing, "missing AvailableInputMethods: " + ", ".join(sorted(missing)))

    def command_row():
      reset("command")
      result = run("omarchy-setup-input", "hangul", check=False)
      require(result.returncode == 0, "omarchy-setup-input hangul: " + result.stderr.strip())
      require("hangul" in [item[0] for item in group()[1]], "live group is missing hangul")

    def absent_row():
      reset("absent", bare)
      result = run("omarchy-setup-input", "mozc", check=False)
      require(result.returncode != 0, "omarchy-setup-input mozc succeeded without its engine")
      require("i18n.inputMethod.fcitx5.addons" in result.stdout + result.stderr,
              "missing i18n.inputMethod.fcitx5.addons advice: " + result.stdout + result.stderr)

    def first_save_row():
      reset("first-save", bare, real)
      result = run(python + "/bin/python3", tree + "/share/omarchy/default/input-methods/typing_setup.py",
                   "add", "mozc", check=False)
      require(result.returncode == 0, "typing_setup.py add mozc: " + result.stderr.strip())
      require("mozc" in [item[0] for item in group()[1]], "live group is missing mozc after restart")

    def language_row():
      script = tree + "/share/omarchy/default/input-methods/typing_setup.py"
      reset("language-empty", bare, real)
      result = run(python + "/bin/python3", script, "seed-language", "mozc", check=False)
      require(result.returncode == 0 and not result.stderr,
              "seed-language mozc failed or printed stderr: " + result.stderr.strip())
      require("mozc" in [item[0] for item in group()[1]], "live group is missing mozc")
      reset("language-keeps-hangul", real)
      result = run(python + "/bin/python3", script, "add", "hangul", check=False)
      require(result.returncode == 0, "could not add hangul: " + result.stderr.strip())
      result = run(python + "/bin/python3", script, "seed-language", "mozc", check=False)
      require(result.returncode == 0 and not result.stderr,
              "seed-language mozc failed or printed stderr: " + result.stderr.strip())
      selected = [item[0] for item in group()[1]]
      require("hangul" in selected and "mozc" not in selected,
              "existing hangul was replaced or mozc was added: " + repr(selected))

    def indicator_row():
      reset("indicator")
      script = tree + "/share/omarchy/default/input-methods/typing_setup.py"
      result = run(python + "/bin/python3", script, "add", "mozc", check=False)
      require(result.returncode == 0, "could not add mozc: " + result.stderr.strip())
      qml = (Path(tree) / "share/omarchy/shell/Commons/InputMethodState.qml").read_text()
      match = re.search(r'command: \["([^"]+)",\s*Quickshell.env\("OMARCHY_PATH"\)', qml)
      require(match is not None, "patched QML interpreter not found")
      interpreter = match.group(1)
      output = root / "indicator.jsonl"
      with output.open("w") as stream:
        process = subprocess.Popen([interpreter, tree + "/share/omarchy/default/input-methods/indicator.py"],
                                   stdin=subprocess.DEVNULL, stdout=stream, stderr=stream)
      try:
        for _ in range(100):
          if output.exists() and output.stat().st_size:
            break
          if process.poll() is not None:
            break
          time.sleep(0.1)
        lines = output.read_text().splitlines()
        require(bool(lines), "indicator.py emitted no JSON; output: " + output.read_text())
        require("mozc" in json.loads(lines[0])["methods"],
                "first indicator JSON line is missing mozc: " + lines[0])
      finally:
        process.terminate()
        process.wait(timeout=10)

    def picker_row():
      script = Path(tree) / "share/omarchy/default/input-methods/typing_setup.py"
      source = script.read_text()
      match = re.search(r'on_change = \["([^"]+)",', source)
      require(match is not None, "patched typing_setup.py interpreter not found")
      interpreter = match.group(1)
      require(Path(interpreter).is_file(), "picker interpreter does not exist: " + interpreter)
      result = run(interpreter, "-c", "import typing_setup; assert 'de' in typing_setup.keyboard_catalog()", check=False)
      require(result.returncode == 0, "keyboard_catalog lacks de or picker interpreter failed: " + result.stderr.strip())

    def profile_row():
      pre = Path(pre_path).read_text()
      require(pre.startswith("-"), "ExecStartPre is missing its failure-tolerant '-' prefix: " + pre)
      script = pre[1:]
      require(Path(script).is_file(), "ExecStartPre script does not exist: " + script)
      for label, layout, initial, expected in (("de", "de", "stock", "de"),
                                                ("missing", "de", "missing", "de"),
                                                ("non-latin", "ru", "stock", "us"),
                                                ("custom", "de", "mozc", "us"),
                                                ("hyprctl-fails", "de", "stock", "us")):
        reset("profile-" + label)
        stop()  # Fcitx saves its profile on exit.
        if initial == "missing":
          profile.unlink()
        elif initial == "mozc":
          profile.write_text(setup.profile_text("us", "mozc"))
        before = profile.read_bytes() if profile.exists() else None
        os.environ["STUB_LAYOUT"] = layout
        if label == "hyprctl-fails":
          os.environ["STUB_FAIL"] = "1"
        result = run(script, check=False)
        if label == "hyprctl-fails":
          require(result.returncode != 0, "failing hyprctl did not fail ExecStartPre")
          require(profile.read_bytes() == before, "failing hyprctl changed the profile")
          start(real)
        else:
          require(result.returncode == 0, label + " ExecStartPre failed: " + result.stderr.strip())
          require(profile.exists(), label + " left no profile")
          require(setup.sections(profile.read_text())["Groups/0"]["Default Layout"] == expected,
                  label + " profile has wrong group layout: " + profile.read_text())
          if initial == "mozc":
            require(profile.read_bytes() == before, "custom mozc profile changed")

    print("input-methods: starting assertions", flush=True)
    row("ledger", ledger_row)
    row("closure-cost", cost_row)
    row("engines-exist", engines_row)
    row("command-hangul", command_row)
    row("engine-absent", absent_row)
    row("first-save-after-rebuild", first_save_row)
    row("seed-language", language_row)
    row("indicator", indicator_row)
    row("picker", picker_row)
    row("profile-step", profile_row)
    if failures:
      print("input-methods: FAIL rows: " + ", ".join(failures), flush=True)
      sys.exit(1)
    print("input-methods: PASS", flush=True)
  '';
in
pkgs.runCommand "nixarchy-input-methods"
  {
    nativeBuildInputs = with pkgs; [
      jq
      dbus
      systemd
      procps
      python
    ];
  }
  ''
    echo "input-methods: starting session bus"
    mkdir empty home config data runtime
    chmod 700 runtime
    HOME=$PWD/home XDG_CONFIG_HOME=$PWD/config XDG_DATA_HOME=$PWD/data XDG_RUNTIME_DIR=$PWD/runtime \
      ORIGINAL_XDG_DATA_DIRS="''${XDG_DATA_DIRS-}" XDG_DATA_DIRS=$PWD/empty \
      dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- \
      ${python}/bin/python3 ${driver} ${tree} ${real} ${bare} ${ledger} \
      ${pkgs.closureInfo { rootPaths = [ real ]; }}/store-paths ${pre} ${python}
    touch $out
  ''
