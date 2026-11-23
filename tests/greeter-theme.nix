{
  inputs,
  pkgs,
  # Passed alongside inputs and pkgs where flake.nix registers this check next to session.
  ...
}:
let
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
    import subprocess

    NAMED_COLORS = {
        "black": (0, 0, 0),
        "white": (255, 255, 255),
        "red": (255, 0, 0),
        "lime": (0, 255, 0),
        "green": (0, 128, 0),
        "blue": (0, 0, 255),
        "yellow": (255, 255, 0),
        "magenta": (255, 0, 255),
        "fuchsia": (255, 0, 255),
        "cyan": (0, 255, 255),
        "aqua": (0, 255, 255),
    }

    def hex_rgb(value):
        h = value.lstrip("#")
        return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))

    def parse_pixel(raw):
        text = raw.strip().lower()
        if text in NAMED_COLORS:
            return NAMED_COLORS[text]
        m = re.match(
            r"srgba?\(\s*(\d+(?:\.\d+)?%?)\s*,\s*(\d+(?:\.\d+)?%?)\s*,\s*(\d+(?:\.\d+)?%?)",
            text,
        )
        if m:
            channels = []
            for group in m.groups():
                if group.endswith("%"):
                    channels.append(round(float(group[:-1]) * 255.0 / 100.0))
                else:
                    channels.append(round(float(group)))
            return tuple(channels)
        m = re.match(r"graya?\(\s*(\d+(?:\.\d+)?%?)", text)
        if m:
            group = m.group(1)
            val = (
                round(float(group[:-1]) * 255.0 / 100.0)
                if group.endswith("%")
                else round(float(group))
            )
            return (val, val, val)
        raise AssertionError(f"cannot parse magick pixel output: {raw!r}")

    def pixel(path, x, y):
        out = subprocess.run(
            [
                "${pkgs.imagemagick}/bin/magick",
                path,
                "-format",
                f"%[pixel:p{{{x},{y}}}]",
                "info:",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        return parse_pixel(out.stdout)

    def image_size(path):
        out = subprocess.run(
            [
                "${pkgs.imagemagick}/bin/magick",
                path,
                "-format",
                "%w %h",
                "info:",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        w, h = out.stdout.strip().split()
        return (int(w), int(h))

    def close_rgb(got, want, tol=8):
        return all(abs(a - b) <= tol for a, b in zip(got, want))

    def spots(path):
        """Compute pixel sample coordinates from Main.qml's centred Column geometry.

        - corner: (16, 16), well outside the central panel.
        - logo: width = min(800, 0.8 * W), height = round(width * 185 / 800),
          sampled inside the solid vertical stroke of 'M' (139/800, 87/185).
        - lock: 34x38, vertically centred against the 48px entry slot in a
          Row with spacing 15; sampled in its solid body at local (8, 25).
        - frame: 286x48, top border at local y = 1, x = 143.
        """
        w, h = image_size(path)
        logo_w = min(800, round(w * 0.8))
        logo_h = round(logo_w * 185 / 800)
        row_w = 34 + 15 + 286
        row_h = 48
        col_h = logo_h + 40 + row_h
        col_top = (h - col_h) // 2

        logo_left = (w - logo_w) // 2
        logo_pt = (
            logo_left + round(logo_w * 139 / 800),
            col_top + round(logo_h * 87 / 185),
        )

        row_left = (w - row_w) // 2
        row_top = col_top + logo_h + 40

        lock_left = row_left
        lock_top = row_top + (row_h - 38) // 2
        lock_pt = (lock_left + 8, lock_top + 25)

        frame_left = row_left + 34 + 15
        frame_top = row_top
        frame_pt = (frame_left + 143, frame_top + 1)

        return {
            "corner": (16, 16),
            "logo": logo_pt,
            "lock": lock_pt,
            "frame": frame_pt,
        }

    def read_spot(path, coord, want, radius=0, tol=8):
        cx, cy = coord
        best = pixel(path, cx, cy)
        if close_rgb(best, want, tol):
            return best
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                got = pixel(path, cx + dx, cy + dy)
                if close_rgb(got, want, tol):
                    return got
        return best

    def read_cursor(node):
        out = node.succeed(
            "journalctl -u display-manager --show-cursor -n0 --no-pager"
        )
        for line in reversed(out.splitlines()):
            if line.startswith("-- cursor: "):
                return line.split("-- cursor: ", 1)[1].strip()
        raise AssertionError(f"no journal cursor in: {out!r}")

    def start_greeter(node):
        cursor = read_cursor(node)
        node.succeed("systemctl restart display-manager")
        node.wait_for_unit("display-manager.service")
        node.wait_until_succeeds("loginctl list-sessions | grep -q greeter")
        return cursor

    def wait_for_pixels(node, label, expected, tol=8):
        """Poll screenshots until every requested spot matches within tolerance."""
        shot = os.path.join(os.environ["out"], f"{label}.png")
        last = {}
        coords = {}
        for attempt in range(15):
            node.sleep(2)
            node.screenshot(label)
            coords = spots(shot)
            last = {}
            ok = True
            for name, want_hex in expected.items():
                want = hex_rgb(want_hex)
                radius = 0 if name == "corner" else 2
                got = read_spot(shot, coords[name], want, radius=radius, tol=tol)
                last[name] = (coords[name], got, want)
                if not close_rgb(got, want, tol):
                    ok = False
            print(
                f"{label} attempt {attempt}: "
                + ", ".join(
                    f"{k}@{xy}=#{g[0]:02x}{g[1]:02x}{g[2]:02x} (want #{w[0]:02x}{w[1]:02x}{w[2]:02x})"
                    for k, (xy, g, w) in last.items()
                )
            )
            if ok:
                return shot
        raise AssertionError(f"{label}: pixels never matched after 30s: {last}")

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

    def trigger_publish(node, expect_change):
        before = current_gen(node)
        node.succeed(
            "su - omarchy -c '"
            "inbox=/var/lib/nixarchy-greeter/inbox; "
            "date +%s%N > \"$inbox/.tmp.ready\" && "
            "chmod 0644 \"$inbox/.tmp.ready\" && "
            "mv -f -- \"$inbox/.tmp.ready\" \"$inbox/ready\"'"
        )
        if expect_change:
            node.wait_until_succeeds(
                f"test \"$(readlink /var/lib/nixarchy-greeter/out/current || true)\" != '{before}' "
                "&& ! systemctl is-active --quiet nixarchy-greeter-publish.service",
                timeout=30,
            )
        else:
            # Wait for the path-triggered service run to start and finish,
            # then confirm out/current did not move.
            node.sleep(1)
            node.wait_until_succeeds(
                "! systemctl is-active --quiet nixarchy-greeter-publish.service",
                timeout=30,
            )
            after = current_gen(node)
            assert after == before, (
                f"unsafe inbox input changed out/current from {before!r} to {after!r}"
            )

    machine.wait_for_unit("multi-user.target")
    broken.wait_for_unit("multi-user.target")

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
    trigger_publish(machine, expect_change=True)

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
    trigger_publish(machine, expect_change=True)

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
    trigger_publish(machine, expect_change=False)

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
    trigger_publish(machine, expect_change=False)

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
    trigger_publish(machine, expect_change=False)

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

    # ---- Broken node: syntax error in Tinted.qml falls back to plain PNGs ---
    cursor = start_greeter(broken)
    wait_for_pixels(
        broken,
        "broken-fallback",
        {
            "corner": "#1a1b26",
            "lock": "#c0caf5",
            "logo": "#a8cd76",
            "frame": "#c0caf5",
        },
    )
    login_and_logout(broken, cursor)
  '';
}
