{
  inputs,
  pkgs,
  names ? [ "omacut" ],
}:
let
  table = builtins.fromJSON (builtins.readFile ../data/update-launch.json);
  system = pkgs.stdenv.hostPlatform.system;
  apps = map (
    name:
    let
      row = table.${name} or (throw "update-launch-vm: unmapped ${name}");
      package = inputs.self.packages.${system}.${name};
    in
    assert pkgs.lib.assertMsg (row.kind == "gui") "update-launch-vm: ${name} is not a GUI probe";
    {
      inherit name package;
      inherit (row) class;
      command = "${package}/bin/${package.meta.mainProgram}";
    }
  ) names;
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-update-launch-vm";
  nodes.machine =
    { config, lib, ... }:
    {
      imports = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
      ];
      programs.nixarchy = {
        enable = true;
        greeterThemeUser = "omarchy";
        flake = "/etc/nixos";
      };
      services.displayManager.sddm.wayland.compositorCommand = lib.mkForce (
        "${config.programs.hyprland.package}/bin/Hyprland --config "
        + "${config.programs.nixarchy.package}/share/omarchy/default/sddm/hyprland.lua"
      );
      boot.plymouth.enable = lib.mkForce false;
      environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";
      environment.systemPackages = map (app: app.package) apps;
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
        users.omarchy = {
          programs.nixarchy.enable = true;
          home.stateVersion = "25.05";
        };
      };
      users.users.omarchy = {
        isNormalUser = true;
        uid = 1000;
        password = "omarchy";
        extraGroups = [
          "video"
          "input"
        ];
      };
      virtualisation = {
        memorySize = 3072;
        cores = 2;
      };
      system.activationScripts.testFlakeDir = ''
        mkdir -p /etc/nixos
        chmod 0777 /etc/nixos
      '';
    };

  testScript = ''
    import importlib.util
    import json
    import shlex
    import time

    spec = importlib.util.spec_from_file_location("update_launch", "${../.github/scripts/update-launch.py}")
    launch = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(launch)
    apps = json.loads(${
      builtins.toJSON (builtins.toJSON (map (app: { inherit (app) name class command; }) apps))
    })

    machine.start()
    machine.wait_for_unit("display-manager.service")
    machine.wait_until_succeeds("loginctl list-sessions | grep -q greeter")
    machine.send_chars("omarchy\n")
    machine.wait_until_succeeds("loginctl list-sessions --no-legend | awk '$3 == \"omarchy\" {found=1} END {exit !found}'")
    machine.wait_until_succeeds("test -S /run/user/1000/hypr/$(ls -t /run/user/1000/hypr | head -1)/.socket.sock", timeout=90)

    def desktop(command):
        prefix = ("export XDG_RUNTIME_DIR=/run/user/1000 "
                  "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
                  "HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1); ")
        return "su omarchy -c " + shlex.quote(prefix + command)

    def clients():
        return json.loads(machine.succeed(desktop("hyprctl clients -j")))

    failures = []
    for app in apps:
        name = app["name"]
        before = clients()
        script = "/tmp/launch-" + name + ".sh"
        log = "/tmp/launch-" + name + ".log"
        command = ("#!/bin/sh\n"
                   "echo $$ > /tmp/launch-" + name + ".pid\n"
                   "export XDG_CONFIG_HOME=/tmp/profile-" + name + "/config\n"
                   "export XDG_DATA_HOME=/tmp/profile-" + name + "/data\n"
                   "exec " + shlex.quote(app["command"]) + " >" + log + " 2>&1\n")
        machine.succeed("printf '%s' " + shlex.quote(command) + " > " + script + " && chmod 755 " + script)
        machine.succeed(desktop("hyprctl dispatch exec " + shlex.quote(script)))
        pid = 0
        opened = []
        try:
            machine.wait_for_file("/tmp/launch-" + name + ".pid", timeout=15)
            pid = int(machine.succeed("cat /tmp/launch-" + name + ".pid"))
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                opened = clients()
                if any(c.get("address") not in {b.get("address") for b in before}
                       and c.get("class", "").lower() == app["class"].lower()
                       and c.get("pid") == pid for c in opened):
                    break
                time.sleep(1)
            else:
                raise AssertionError("no new app-owned window within 45 seconds")
            time.sleep(10)
            settled = clients()
            alive = {pid} if machine.execute("kill -0 " + str(pid))[0] == 0 else set()
            assert launch.observed(before, opened, settled, app["class"], alive), "window or process did not survive settle"
            print("launch-verdict " + name + " PASS")
        except Exception as exc:
            print("launch-verdict " + name + " FAIL: " + str(exc))
            print("launcher log: " + machine.succeed("cat " + log + " || true"))
            print("clients: " + json.dumps(clients()))
            failures.append(name)
        finally:
            if pid:
                machine.succeed("pkill -P " + str(pid) + " || true; kill " + str(pid) + " 2>/dev/null || true")
    assert not failures, "launch failures: " + ", ".join(failures)
  '';
}
