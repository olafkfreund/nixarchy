{
  inputs,
  pkgs,
  # Passed alongside inputs and pkgs where flake.nix registers this check next to session.
  ...
}:
let
  resolution = {
    x = 1280;
    y = 1024;
  };

  blueWallpaper =
    pkgs.runCommand "greeter-blue-wallpaper.png"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
      }
      ''
        magick -size 64x64 xc:'#0000ff' -depth 8 PNG24:$out
      '';

  common =
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
          "wheel"
          "video"
          "input"
        ];
      };

      virtualisation = {
        inherit resolution;
        memorySize = 3072;
        cores = 2;
      };

      system.activationScripts.testFlakeDir = ''
        mkdir -p /etc/nixos
        chmod 0777 /etc/nixos
      '';
    };
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-greeter-theme";

  nodes = {
    machine = common;

    broken = {
      imports = [ common ];
      programs.nixarchy.package =
        let
          base = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy;
        in
        base.overrideAttrs (old: {
          postInstall = (old.postInstall or "") + ''
            chmod u+w "$out/share/sddm/themes/omarchy/Tinted.qml"
            printf '%s\n' 'import QtQuick' 'Item { broken syntax !!!' > "$out/share/sddm/themes/omarchy/Tinted.qml"
          '';
        });
    };
  };

  testScript = ''
    import os
    import re
    import shlex
    import subprocess
    import time

    RESOLUTION = (${toString resolution.x}, ${toString resolution.y})
    PUBLISH_UNIT = "nixarchy-greeter-publish.service"
    INBOX = "/var/lib/nixarchy-greeter/inbox"
    OUT = "/var/lib/nixarchy-greeter/out"

    def hex_rgb(value):
        h = value.lstrip("#")
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))

    def image_size(path):
        out = subprocess.run(
            ["${pkgs.imagemagick}/bin/magick", path, "-format", "%w %h", "info:"],
            capture_output=True,
            text=True,
            check=True,
        )
        w, h = out.stdout.strip().split()
        return (int(w), int(h))

    def close_rgb(got, want, tol=8):
        return all(abs(a - b) <= tol for a, b in zip(got, want))

    def region_colors(path, box):
        """Unique 8-bit colours inside box = (x, y, w, h): one magick call."""
        x, y, w, h = box
        out = subprocess.run(
            [
                "${pkgs.imagemagick}/bin/magick", path,
                "-crop", f"{w}x{h}+{x}+{y}", "+repage",
                "-depth", "8", "-unique-colors", "txt:-",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        found = re.findall(r"^\d+,\d+:.*?#([0-9A-Fa-f]{6})", out.stdout, re.M)
        assert found, f"no pixels in {box} of {path}"
        return [hex_rgb(c) for c in found]

    def regions(path):
        """Boxes from Main.qml's centred Column, at 1x scale, from the screenshot's own size.

        The greeter's Hyprland picks its own mode (1280x800 under QEMU), so only a minimum is
        asserted: the boxes below need at least 1024x600.

        - corner: 16x16 at the origin, outside the central panel.
        - logo: the whole bounding box; width = min(800, 0.8 * W), height = width * 185 / 800.
        - lock: 34x38, vertically centred against the 48px entry slot in a Row, spacing 15.
        - frame: the top 4 rows of the 286x48 entry frame.
        """
        w, h = image_size(path)
        assert w >= 1024 and h >= 600, f"screenshot is {w}x{h}, smaller than the 1024x600 the layout needs"
        logo_w = min(800, round(w * 0.8))
        logo_h = round(logo_w * 185 / 800)
        row_w = 34 + 15 + 286
        row_h = 48
        col_top = (h - (logo_h + 40 + row_h)) // 2
        row_left = (w - row_w) // 2
        row_top = col_top + logo_h + 40
        return {
            "corner": (0, 0, 16, 16),
            "logo": ((w - logo_w) // 2, col_top, logo_w, logo_h),
            "lock": (row_left, row_top + (row_h - 38) // 2, 34, 38),
            "frame": (row_left + 34 + 15, row_top, 286, 4),
        }

    def read_cursor(node, unit="display-manager"):
        out = node.succeed(f"journalctl -u {unit} --show-cursor -n0 --no-pager")
        for line in reversed(out.splitlines()):
            if line.startswith("-- cursor: "):
                return line.split("-- cursor: ", 1)[1].strip()
        raise AssertionError(f"no journal cursor in: {out!r}")

    def start_greeter(node):
        cursor = read_cursor(node)
        # display-manager allows 3 starts per 30 s; the cases restart it faster.
        node.succeed("systemctl reset-failed display-manager")
        node.succeed("systemctl restart display-manager")
        node.wait_for_unit("display-manager.service")
        node.wait_until_succeeds("loginctl list-sessions | grep -q greeter")
        return cursor

    def wait_for_pixels(node, label, expected, tol=8):
        """Poll screenshots until each region holds a pixel within tolerance of its colour."""
        shot = os.path.join(os.environ["out"], f"{label}.png")
        last = {}
        for attempt in range(15):
            node.sleep(2)
            node.screenshot(label)
            boxes = regions(shot)
            last = {}
            for name, want_hex in expected.items():
                want = hex_rgb(want_hex)
                colors = region_colors(shot, boxes[name])
                last[name] = (want_hex, any(close_rgb(c, want, tol) for c in colors), len(colors))
            print(f"{label} attempt {attempt}: {last}")
            if all(ok for _, ok, _ in last.values()):
                return shot
        raise AssertionError(f"{label}: regions never matched after 30s: {last}")

    def login_and_logout(node, cursor):
        node.send_chars("omarchy\n")
        node.wait_until_succeeds(
            f"journalctl -u display-manager --after-cursor='{cursor}' --no-pager "
            "| grep -q 'Authentication for user .*omarchy.* successful'"
        )
        node.wait_until_succeeds(
            "loginctl list-sessions --no-legend | awk '$3 == \"omarchy\" { found = 1 } END { exit !found }'"
        )
        node.succeed("loginctl terminate-user omarchy")
        node.wait_until_succeeds(
            "! loginctl list-sessions --no-legend | awk '$3 == \"omarchy\" { found = 1 } END { exit !found }'"
        )

    def current_gen(node):
        return node.succeed(
            "readlink /var/lib/nixarchy-greeter/out/current || true"
        ).strip()

    def invocation(node):
        return node.succeed(f"systemctl show -p InvocationID --value {PUBLISH_UNIT}").strip()

    def trigger_publish(node, kind="ok"):
        """Write a fresh ready nonce and prove a new publisher run handled it.

        kind: "ok" (new generation whose request is the nonce), "defaults" (new
        generation, empty request: a wrong-owner input) or "unsafe" (abort: current
        unchanged and a rejection line in the unit's journal).
        """
        # The path unit also watches the inbox directory, so writing the inputs
        # has already started runs; let them finish before taking the baseline.
        # A rename of `ready` during a run is then picked up by the publisher's
        # own catch-up loop rather than a new invocation, so the proof is the
        # result (request == nonce) or the logged rejection, not an InvocationID.
        # Not `is-active`: a oneshot that is still starting reports "activating".
        idle = (
            f"systemctl show -p ActiveState --value {PUBLISH_UNIT} "
            "| grep -qxE 'inactive|failed'"
        )
        node.wait_until_succeeds(idle, timeout=60)
        node.sleep(1)
        node.wait_until_succeeds(idle, timeout=60)
        before = current_gen(node)
        cursor = read_cursor(node, PUBLISH_UNIT)
        nonce = str(time.time_ns())
        node.succeed(
            "su - omarchy -c '"
            f"inbox={INBOX}; "
            f"echo {nonce} > \"$inbox/.tmp.ready\" && "
            "chmod 0644 \"$inbox/.tmp.ready\" && "
            "mv -f -- \"$inbox/.tmp.ready\" \"$inbox/ready\"'"
        )
        if kind == "unsafe":
            node.wait_until_succeeds(
                f"journalctl -u {PUBLISH_UNIT} --after-cursor='{cursor}' --no-pager "
                "| grep -q 'nixarchy-greeter-publish: '",
                timeout=30,
            )
            after = current_gen(node)
            assert after == before, (
                f"unsafe inbox input changed out/current from {before!r} to {after!r}"
            )
            return
        want = nonce if kind == "ok" else ""
        node.wait_until_succeeds(
            f"test \"$(readlink {OUT}/current)\" != '{before}' "
            f"&& test \"$(cat {OUT}/current/request)\" = '{want}'",
            timeout=30,
        )

    def inbox_as_user(node, body):
        node.succeed(
            "su - omarchy -c "
            + shlex.quote(f'inbox={INBOX}; rm -f "$inbox"/*; {body}')
        )

    machine.wait_for_unit("multi-user.target")
    broken.wait_for_unit("multi-user.target")

    # A fresh sddm user has never seen this Hyprland, so the greeter's
    # compositor opens its "Hyprland updated" news window (and may nag) over
    # the login form. Record the running version and a recent nag time, as a
    # long-lived host already has, before the first greeter is started.
    for node in (machine, broken):
        node.succeed(
            "d=/var/lib/sddm/.local/share/hyprland; "
            "install -d -o sddm -g sddm -m 0700 \"$d\"; "
            "v=$(Hyprland --version | head -1 | awk '{print $2}'); "
            "test -n \"$v\"; "
            "printf '%s' \"$v\" > \"$d/lastVersion\"; "
            "date +%s > \"$d/lastNag\"; "
            "chown sddm:sddm \"$d/lastVersion\" \"$d/lastNag\""
        )

    # Ensure the initial boot service (if any) has settled and no theme data exists yet.
    machine.wait_until_succeeds(
        "! systemctl is-active --quiet nixarchy-greeter-publish.service"
    )
    machine.succeed("rm -rf /var/lib/nixarchy-greeter/inbox/* /var/lib/nixarchy-greeter/out/*")

    # ---- Case 1: no theme data ----------------------------------------------
    cursor = start_greeter(machine)
    wait_for_pixels(
        machine,
        "case1-defaults",
        {
            "corner": "#1a1b26",
            "lock": "#c0caf5",
            "logo": "#a8cd76",
            "frame": "#c0caf5",
        },
    )
    login_and_logout(machine, cursor)

    # ---- Case 2: full theme + 64x64 blue PNG --------------------------------
    machine.succeed(
        "su - omarchy -c '"
        "inbox=/var/lib/nixarchy-greeter/inbox; "
        "rm -f \"$inbox\"/*; "
        "printf \"%s\\n\" "
        "  \"background = \\\"#ff0000\\\"\" "
        "  \"foreground = \\\"#00ff00\\\"\" "
        "  \"accent = \\\"#ffff00\\\"\" "
        "  \"red = \\\"#ff00ff\\\"\" "
        "  > \"$inbox/colors.toml\"; "
        "install -m 0644 ${blueWallpaper} \"$inbox/background\"'"
    )
    trigger_publish(machine)

    cursor = start_greeter(machine)
    wait_for_pixels(
        machine,
        "case2-themed",
        {
            "corner": "#0000ff",
            "lock": "#00ff00",
            "logo": "#ffff00",
            "frame": "#00ff00",
        },
    )

    # ---- Case 3: wrong password -> failed tint -> key press -> fg -----------
    machine.send_chars("wrongpass\n")
    wait_for_pixels(
        machine,
        "case3-failed",
        {
            "corner": "#0000ff",
            "lock": "#ff00ff",
            "logo": "#ffff00",
            "frame": "#ff00ff",
        },
    )
    # One key press clears loginFailed while handing the key to the TextInput;
    # Backspace then removes that character so login_and_logout can type cleanly.
    machine.send_chars("x")
    wait_for_pixels(
        machine,
        "case3-recovered",
        {
            "corner": "#0000ff",
            "lock": "#00ff00",
            "logo": "#ffff00",
            "frame": "#00ff00",
        },
    )
    machine.send_key("backspace")
    login_and_logout(machine, cursor)

    # ---- Case 4: bad colour ("red;") and no image ---------------------------
    machine.succeed(
        "su - omarchy -c '"
        "inbox=/var/lib/nixarchy-greeter/inbox; "
        "rm -f \"$inbox\"/*; "
        "printf \"%s\\n\" \"background = \\\"red;\\\"\" > \"$inbox/colors.toml\"'"
    )
    trigger_publish(machine)

    cursor = start_greeter(machine)
    wait_for_pixels(
        machine,
        "case4-bad-colour",
        {
            "corner": "#1a1b26",
            "lock": "#c0caf5",
            "logo": "#a8cd76",
        },
    )
    login_and_logout(machine, cursor)

    # ---- Case 5: symlink colors.toml -> /etc/shadow (abort) -----------------
    machine.succeed(
        "su - omarchy -c '"
        "inbox=/var/lib/nixarchy-greeter/inbox; "
        "rm -f \"$inbox\"/*; "
        "ln -s /etc/shadow \"$inbox/colors.toml\"'"
    )
    trigger_publish(machine, "unsafe")

    cursor = start_greeter(machine)
    wait_for_pixels(
        machine,
        "case5-symlink",
        {
            "corner": "#1a1b26",
            "lock": "#c0caf5",
        },
    )
    login_and_logout(machine, cursor)

    # ---- Case 6: FIFO background (abort within TimeoutStartSec) -------------
    machine.succeed(
        "su - omarchy -c '"
        "inbox=/var/lib/nixarchy-greeter/inbox; "
        "rm -f \"$inbox\"/*; "
        "mkfifo \"$inbox/background\"'"
    )
    trigger_publish(machine, "unsafe")

    cursor = start_greeter(machine)
    wait_for_pixels(
        machine,
        "case6-fifo",
        {
            "corner": "#1a1b26",
            "lock": "#c0caf5",
        },
    )
    login_and_logout(machine, cursor)

    # ---- Case 7: oversized 60 MiB background (abort) ------------------------
    machine.succeed(
        "su - omarchy -c '"
        "inbox=/var/lib/nixarchy-greeter/inbox; "
        "rm -f \"$inbox\"/*; "
        "truncate -s 60M \"$inbox/background\"'"
    )
    trigger_publish(machine, "unsafe")

    cursor = start_greeter(machine)
    wait_for_pixels(
        machine,
        "case7-oversized",
        {
            "corner": "#1a1b26",
            "lock": "#c0caf5",
        },
    )
    login_and_logout(machine, cursor)

    # ---- Case 8: a root-owned colors.toml is another owner's file: defaults --
    inbox_as_user(machine, "true")
    machine.succeed(
        f"printf '%s\\n' 'background = \"#ff0000\"' > {INBOX}/colors.toml"
    )
    trigger_publish(machine, "defaults")

    cursor = start_greeter(machine)
    wait_for_pixels(
        machine,
        "case8-wrong-owner",
        {
            "corner": "#1a1b26",
            "lock": "#c0caf5",
        },
    )
    login_and_logout(machine, cursor)

    # ---- Case 9: a non-default background and no wallpaper ------------------
    inbox_as_user(machine, 'printf "%s\\n" \'background = "#00aa00"\' > "$inbox/colors.toml"')
    trigger_publish(machine)

    cursor = start_greeter(machine)
    wait_for_pixels(
        machine,
        "case9-background-only",
        {
            "corner": "#00aa00",
        },
    )
    login_and_logout(machine, cursor)

    # ---- Broken node: a syntax error in Tinted.qml falls back to the PNGs ---
    # The fallback ignores the tint (lock stays #c0caf5) while Main.qml still
    # paints the themed background (#004400): that proves the Loader fallback.
    broken.wait_until_succeeds(f"! systemctl is-active --quiet {PUBLISH_UNIT}")
    broken.succeed(f"rm -rf {INBOX}/* {OUT}/*")
    inbox_as_user(
        broken,
        'printf "%s\\n" \'foreground = "#00ff00"\' \'background = "#004400"\' > "$inbox/colors.toml"',
    )
    trigger_publish(broken)

    cursor = start_greeter(broken)
    wait_for_pixels(
        broken,
        "broken-fallback",
        {
            "corner": "#004400",
            "lock": "#c0caf5",
            "frame": "#c0caf5",
        },
    )
    # The greeter logs QML errors under its own identifier, not the unit.
    broken.wait_until_succeeds(
        "journalctl -b -t sddm-greeter-qt6 --no-pager | grep -q 'Tinted.qml.*Expected token'",
        timeout=60,
    )
    login_and_logout(broken, cursor)
  '';
}
