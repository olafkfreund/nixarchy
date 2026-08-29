{ inputs, pkgs }:
# Boots the Omarchy session on a machine whose ~/.config/hypr/hyprland.lua
# belongs to somebody else.
#
# That is the whole reason the session exists. Before it, reaching the desktop
# meant Omarchy owning that file, and a machine already running Hyprland
# through home-manager cannot give it up: the seed keeps the user's file, the
# other seven Omarchy files land beside it read by nothing, and the rebuild
# succeeds into a session with no bar and no keybindings.
#
# The session is launched through its own .desktop Exec rather than picked in
# the greeter, because Omarchy's SDDM theme selects the session whose name
# contains "uwsm" and would never choose this one. What is under test is the
# launcher -- `uwsm start -- Hyprland --config <omarchy hyprland.lua>` -- and
# whether Omarchy's Lua modules still resolve when the entry point is not the
# user's file. Autologin on tty1 gives it a real seat to start from.
pkgs.testers.runNixOSTest {
  name = "nixarchy-coexist";

  nodes.machine = {
    imports = [
      inputs.self.nixosModules.nixarchy
      inputs.home-manager.nixosModules.home-manager
    ];

    programs.nixarchy = {
      enable = true;
      flake = "/etc/nixos";
      # As on a machine that already greets: no SDDM, the session entry is the
      # only way in.
      displayManager = false;
    };

    boot.plymouth.enable = pkgs.lib.mkForce false;
    environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";

    services.getty.autologinUser = "omarchy";

    users.users.omarchy = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "video"
        "input"
      ];
      password = "omarchy";
    };
    security.sudo.wheelNeedsPassword = false;

    system.activationScripts.testFlakeDir = ''
      mkdir -p /etc/nixos
      chmod 0777 /etc/nixos
    '';

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
      users.omarchy = {
        programs.nixarchy.enable = true;
        home.stateVersion = "25.05";

        # Somebody else's hyprland.lua, exactly as home-manager would leave it:
        # a read-only store symlink the seed will not overwrite. It starts no
        # shell and loads none of Omarchy's defaults, so if the session under
        # test picked this file up instead of Omarchy's, the desktop would come
        # up bare and the assertions below would say so.
        xdg.configFile."hypr/hyprland.lua".text = ''
          -- not Omarchy's config
          hl.env("NIXARCHY_FOREIGN_CONFIG", "1")
        '';
      };
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # The seed must have kept the foreign file and installed the rest.
    machine.succeed(
        "grep -q 'not Omarchy' /home/omarchy/.config/hypr/hyprland.lua")
    for module in ["autostart.lua", "bindings.lua", "looknfeel.lua"]:
        machine.succeed(f"test -s /home/omarchy/.config/hypr/{module}")
    print("seed kept the user's hyprland.lua and installed Omarchy's modules")

    # The bus the launch below needs belongs to the user manager, which
    # autologin starts -- so wait for it rather than assume it is up.
    # systemd-logind starts user@1000.service asynchronously once the session
    # opens, so there is a window where the unit is inactive with no job queued
    # yet. wait_for_unit treats exactly that as a hard failure -- it raises
    # "is inactive and there are no pending jobs" immediately rather than
    # waiting -- so on a loaded runner it fails a session that was about to come
    # up fine. Poll for "active" instead, which tolerates the window.
    machine.wait_until_succeeds("systemctl is-active user@1000.service")
    machine.wait_until_succeeds("test -S /run/user/1000/bus")

    # Launch the session the way a greeter would: whatever Exec= says.
    session = "/run/current-system/sw/share/wayland-sessions/omarchy.desktop"
    machine.succeed(f"test -s {session}")
    exec = machine.succeed(f"sed -n 's/^Exec=//p' {session}").strip()
    print(f"session Exec: {exec}")

    machine.succeed(
        "systemd-run --uid=1000 --setenv=XDG_RUNTIME_DIR=/run/user/1000 "
        "--setenv=WLR_RENDERER_ALLOW_SOFTWARE=1 --setenv=XDG_SESSION_TYPE=wayland "
        # uwsm needs a session bus and will not autolaunch one, so without this
        # the session dies on
        #
        #   org.freedesktop.DBus.Error.NotSupported: Unable to autolaunch a
        #   dbus-daemon without a $DISPLAY for X11
        #
        # and the screen stays pure black. It passed here for a while anyway,
        # picking up a bus by luck, and failed on a CI runner that did not --
        # which is the useful kind of flake, since the fix is the same either
        # way.
        "--setenv=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
        f"--unit=omarchy-session --collect {exec}")

    # The compositor, then the shell it is supposed to start.
    # -u 1000, and not merely -f. `pgrep -f quickshell` run as root matches the
    # root shell that is running the pgrep, because the pattern sits in that
    # shell's own command line -- so it returns instantly and waits for
    # nothing. Restricting it to the user the session belongs to is what makes
    # it a wait. (This one was never load-bearing: the wallpaper delta below is
    # what actually proves the desktop came up. tests/plugin.nix had the same
    # line and there it mattered -- the plugin IPC ran before the shell was up.)
    machine.wait_until_succeeds("pgrep -u 1000 -f Hyprland", timeout=120)
    machine.wait_until_succeeds("pgrep -u 1000 -f quickshell", timeout=180)
    print("Hyprland and the Omarchy shell are running")

    # Started under its watchdog, not as a bare binary.
    #
    # Hyprland 0.56 logs
    #
    #   WARNING: Hyprland is being launched without start-hyprland.
    #   This is highly advised against.
    #
    # when the compositor is exec'd directly, which is what this launcher did
    # until somebody booted it on a laptop and read the journal. A warning is
    # not a failure, so every check here passed while it was happening --
    # asserted on the absence of the line, because that is the only thing that
    # distinguishes the two.
    warned = machine.succeed(
        "journalctl -b --no-pager | grep -c 'without start-hyprland' || true"
    ).strip()
    assert warned == "0", (
        "Hyprland is being launched without start-hyprland. The session "
        "should exec start-hyprland and pass --config through its own `--`.")
    print("the session runs Hyprland under start-hyprland")

    # The proof that Omarchy's own config was loaded rather than the foreign
    # one: quickshell is only ever started by Omarchy's autostart.lua, which
    # only runs if the entry point required it.
    machine.wait_until_succeeds(
        "test -s $(readlink -f "
        "/home/omarchy/.local/state/omarchy/current/background)", timeout=120)
    # And that it is actually drawn, not merely running -- the same check the
    # session test uses, for the same reason: every other assertion here passed
    # once while the screen was black.
    import os, subprocess

    def avg(path):
        out = subprocess.run(
            ["${pkgs.imagemagick}/bin/magick", path, "-resize", "1x1",
             "-format", "%[hex:u]", "info:"],
            capture_output=True, text=True, check=True)
        return tuple(int(out.stdout.strip()[i:i + 2], 16) for i in (0, 2, 4))

    paper = machine.succeed(
        "readlink -f /home/omarchy/.local/state/omarchy/current/background").strip()
    machine.copy_from_machine(paper, "")
    local_paper = os.path.join(os.environ["out"], os.path.basename(paper))
    w_r, w_g, w_b = avg(local_paper)

    # Retried rather than slept at. A fixed wait is a guess about how fast the
    # machine is: 20 seconds was enough here and not on a CI runner, where this
    # failed with the desktop still black. Retrying converges on whatever the
    # machine actually needs, and still fails if it never draws.
    delta = None
    for attempt in range(12):
        machine.sleep(5)
        machine.screenshot("coexist-desktop")
        shot = os.path.join(os.environ["out"], "coexist-desktop.png")
        s_r, s_g, s_b = avg(shot)
        delta = abs(s_r - w_r) + abs(s_g - w_g) + abs(s_b - w_b)
        print(f"attempt {attempt}: screen #{s_r:02X}{s_g:02X}{s_b:02X} "
              f"wallpaper #{w_r:02X}{w_g:02X}{w_b:02X} delta {delta}")
        if delta < 120:
            break

    assert delta is not None and delta < 120, (
        f"the Omarchy session came up but never looked like its wallpaper "
        f"(delta {delta} after 60s) -- the entry point loaded, the desktop "
        "did not.")
    print("the Omarchy session renders its desktop beside a foreign hyprland.lua")
  '';
}
