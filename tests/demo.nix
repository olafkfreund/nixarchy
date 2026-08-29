{ inputs, pkgs }:
# A guided tour of a real Omarchy session, captured frame by frame.
#
# This is the session test's machinery pointed at a different question. That
# one asks "did it come up"; this one asks "what does it look like while
# somebody uses it", and leaves behind PNGs plus a video that can go in the
# README.
#
# Frames come from machine.screenshot(), which goes through qemu's own
# screendump rather than a compositor screencopy -- the same reason the
# wallpaper check in tests/session.nix uses it. That works with no display
# backend, where grim would block forever waiting for a frame consumer.
#
# Every state change is driven by the omarchy-* commands rather than by
# keystrokes. A screencast that silently records the wrong thing because a
# keybinding did not land is worse than no screencast, and the commands are
# what the keybindings call anyway. The menu is the exception: it is a picture
# of the menu that is wanted, so that one is opened for real.
let
  # A real published plugin, pinned, so the tour shows the plugin system
  # working on something somebody actually wrote rather than a fixture.
  barToggle = pkgs.fetchgit {
    url = "https://github.com/r3mcos3/omarchy-bar-toggle.git";
    rev = "586750d0fa902b8774d1559fff954da540742a1e";
    hash = "sha256-K45Qwgdf+K943nPHxrgS0IE9slsno9uZjIkr3XnfVBM=";
  };

  test = pkgs.testers.runNixOSTest {
    name = "nixarchy-demo";

    # The greeter wait below reads the screen, and get_screen_text needs this.
    # Without it the tour died on the first probe -- borrowed from
    # tests/session.nix, which sets it, without noticing that it does.
    enableOCR = true;

    nodes.machine = {
      imports = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
      ];

      programs.nixarchy = {
        enable = true;
        flake = "/etc/nixos";
      };

      boot.plymouth.enable = pkgs.lib.mkForce false;
      environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";

      # Deliberately the same display the session test uses. A larger one was
      # tried first and is exactly the sort of unverified change that turns a
      # five minute run into a fourteen minute hang with nothing to show.
      virtualisation.memorySize = 4096;
      virtualisation.cores = 4;

      # nixarchy-apply refuses to do anything without a flake directory to copy
      # the selection into, and exits before it prints a word about it. Without
      # this the whole install flow was a no-op no matter what was on screen --
      # tests/session.nix has had this from the start and the demo did not.
      # fetchgit hands over a plain directory with no .git, and the machine has
      # no network, so the history is rebuilt here and cloned over file:// --
      # a real transport in omarchy-git-url-check's allowlist.
      system.activationScripts.pluginRepo = ''
        if [ ! -d /srv/bar-toggle/.git ]; then
          mkdir -p /srv/bar-toggle
          cp -r --no-preserve=mode,ownership ${barToggle}/. /srv/bar-toggle/
          cd /srv/bar-toggle
          export HOME=/root
          ${pkgs.git}/bin/git init -q -b main
          ${pkgs.git}/bin/git -c user.email=t@t -c user.name=t add -A
          ${pkgs.git}/bin/git -c user.email=t@t -c user.name=t commit -q -m plugin
        fi
        chmod -R a+rX /srv/bar-toggle
      '';

      system.activationScripts.demoFlakeDir = ''
        mkdir -p /etc/nixos
        chmod 0777 /etc/nixos
      '';

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

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        sharedModules = [ inputs.self.homeManagerModules.nixarchy ];
        users.omarchy = {
          programs.nixarchy.enable = true;
          home.stateVersion = "25.05";
        };
      };
    };

    testScript = ''
      import os

      # Frames are numbered because ffmpeg stitches them in glob order, and
      # "10" sorting before "2" would play the tour out of sequence.
      frame = 0

      def shot(label, hold=6):
          """Capture `hold` frames of the current screen.

          One screenshot per step would produce a video that flashes past
          unreadably. Holding each state for a few frames is what makes it
          watchable at the low frame rate a screendump-based capture allows.
          """
          global frame
          print(f"  frame {frame:04d}: {label}")
          for _ in range(hold):
              machine.screenshot(f"{frame:04d}-{label}")
              frame += 1

      import shlex

      def user(cmd, timeout=90):
          """Run `cmd` as the logged-in user, bounded.

          Bounded because machine.succeed() waits forever, and several of
          these do hang: omarchy-theme-set ends by running its whole
          post_theme_commands list -- a browser policy refresh, a switcher
          preload, a background cache warm -- and a screencast is not worth
          blocking a build on one of them stalling. A step that times out
          leaves the frames captured up to that point.

          The command is quoted with shlex rather than by hand: a theme name
          like "Catppuccin Latte" has to survive as one word, and pasting it
          into a hand-rolled single-quoted string closes the quote at the
          wrong place and silently runs something else.
          """
          # HYPRLAND_INSTANCE_SIGNATURE too: hyprctl finds the compositor
          # through it, and `su` inherits none of the session environment, so
          # every `hyprctl dispatch` returned 1 and the app windows were never
          # closed -- leaving later steps typing into whatever ended up on top.
          full = ("export XDG_RUNTIME_DIR=/run/user/1000 "
                  "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
                  "export HYPRLAND_INSTANCE_SIGNATURE="
                  "$(ls -t /run/user/1000/hypr 2>/dev/null | head -1); "
                  # WAYLAND_DISPLAY, without which a Wayland client has no
                  # compositor to talk to: foot exited immediately with
                  # "failed to connect to wayland; no compositor running?"
                  # every single time, and the terminal frames were of an
                  # empty desktop.
                  "export WAYLAND_DISPLAY=$(basename "
                  "$(ls -t /run/user/1000/wayland-* 2>/dev/null "
                  "| grep -v '\\.lock$' | head -1)); "
                  + cmd)
          status, out = machine.execute(
              "su omarchy -c " + shlex.quote(full), timeout=timeout)
          if status != 0:
              print(f"  (step returned {status}: {cmd})")
          return out

      machine.wait_for_unit("multi-user.target")

      # ---- the greeter ---------------------------------------------------
      machine.wait_for_unit("display-manager.service")
      machine.wait_until_succeeds("loginctl list-sessions | grep -q greeter")
      # Retried, not slept at. Eight seconds was a guess about how fast the
      # machine is, and typing a password at a greeter that has not drawn yet
      # sends it nowhere -- the same shape that failed the session check on a
      # CI runner and the coexist check before that.
      drawn = ""
      for attempt in range(10):
          machine.sleep(4)
          machine.screenshot("greeter-probe")
          drawn = machine.get_screen_text().strip()
          print(f"  greeter attempt {attempt}: {drawn!r}")
          if drawn:
              break
      assert drawn, "the greeter never drew anything in 40s"
      shot("greeter", hold=8)

      machine.send_chars("omarchy\n")
      machine.wait_until_succeeds(
          "journalctl -b -u display-manager --no-pager"
          " | grep -q 'Authentication for user .*omarchy.* successful'")

      # ---- the desktop ---------------------------------------------------
      # Poll rather than wait_for_unit, and not for the reason this comment
      # used to give. The failure here was never a timeout -- wait_for_unit
      # defaults to fifteen minutes and no workstation takes that long to start
      # a user manager. systemd-logind starts user@1000.service asynchronously
      # once the session opens, and wait_for_unit raises "is inactive and there
      # are no pending jobs" the moment it looks during that window. The
      # timeout=180 that used to be here addressed the wrong mechanism.
      machine.wait_until_succeeds("systemctl is-active user@1000.service")
      # -f, matching the whole command line, not -x, matching the process name
      # exactly: on NixOS the running binary is a wrapper, so its name is not
      # literally "quickshell" and -x waits forever on a shell that is up and
      # logging happily. tests/session.nix uses the loose form for this reason.
      # -u 1000: run as root, `pgrep -f quickshell` matches the root shell
      # running it, since the pattern is in that shell's own command line. It
      # returned instantly and waited for nothing.
      machine.wait_until_succeeds("pgrep -u 1000 -f quickshell")

      # Omarchy dims at 150s idle and locks at 300s, and this tour spends
      # minutes waiting for themes to settle without ever touching the
      # keyboard -- so the session locked itself partway through and the rest
      # of the frames were of a lock screen. This is the toggle the manual
      # documents for exactly this, and it is a demo, not a real desktop.
      user("omarchy-toggle-idle stay-awake", timeout=30)

      # The bar and the wallpaper do not arrive together; wait for the
      # wallpaper the session test checks for, then let the bar settle.
      machine.wait_until_succeeds(
          "test -s $(readlink -f "
          "/home/omarchy/.local/state/omarchy/current/background)")
      machine.sleep(20)
      shot("desktop", hold=10)

      # ---- the menus -----------------------------------------------------
      # SUPER + SPACE opens the root menu for real, so the screencast shows
      # the binding the manual leads with actually working.
      machine.send_key("meta_l-spc")
      machine.sleep(6)
      shot("menu-root", hold=8)
      user("omarchy-menu close", timeout=20)
      machine.sleep(2)

      # Every other menu is summoned by route rather than by walking the tree
      # with arrow keys. Blind keystrokes record whatever happens to be
      # focused, which is how a screencast ends up quietly showing the wrong
      # screen; `omarchy-menu summon <route>` lands on a known one.
      #
      # Install and Remove are the interesting pair here: upstream's rows run
      # pacman, and these are the rewritten ones that edit the app selection.
      for route, label in [
          ("apps", "menu-apps"),
          ("install", "menu-install"),
          ("install.terminal", "menu-install-terminal"),
          ("install.editor", "menu-install-editor"),
          ("install.gaming", "menu-install-gaming"),
          ("remove", "menu-remove"),
          ("update", "menu-update"),
          ("style", "menu-style"),
          ("system", "menu-system"),
      ]:
          user(f"omarchy-menu summon {route}", timeout=30)
          machine.sleep(5)
          shot(label, hold=8)
      user("omarchy-menu close", timeout=20)
      # Escape as well as close: `style.theme` summons the theme *switcher*, a
      # separate carousel that omarchy-menu close leaves up. It stayed pinned
      # over every later frame -- a shot labelled theme-gruvbox showing the
      # carousel captioned "Catppuccin Latte" -- so the route is gone from the
      # list above and this is the belt to its braces.
      machine.send_key("esc")
      machine.sleep(3)

      # ---- themes --------------------------------------------------------
      # Every theme restyles the desktop, the bar, the menu and the wallpaper
      # at once, which is the single most demonstrable thing Omarchy does.
      # Driven by the command the theme picker itself calls, so the switch is
      # the real one and not a keystroke that may or may not have landed.
      for theme in ["Catppuccin Latte", "Gruvbox", "Nord", "Rose Pine", "Tokyo Night"]:
          user(f'omarchy-theme-set "{theme}"')
          machine.sleep(12)
          shot("theme-" + theme.lower().replace(" ", "-"), hold=8)

      # ---- backgrounds ---------------------------------------------------
      for n in range(2):
          user("omarchy-theme-bg-next")
          machine.sleep(8)
          shot(f"background-{n}", hold=6)

      # ---- the shell tools -----------------------------------------------
      # Everything from here runs *inside* the terminal rather than being typed
      # at it. send_chars goes to whatever the compositor has focused, and when
      # an earlier window failed to close it went there instead -- the install
      # flow ran into a file manager and the app selection came back empty.
      # A script passed to foot cannot miss.
      tour = " ; ".join([
          "echo '$ ls -la ~' ; ls -la ~ ; sleep 6",
          "echo '$ omarchy version' ; omarchy version ; sleep 6",
          "echo '$ omarchy theme list' ; omarchy theme list ; sleep 6",
      ])
      user(f"setsid foot -a demo.term bash -lc {shlex.quote(tour + ' ; sleep 60')} "
           ">>/tmp/foot.log 2>&1 &", timeout=20)
      machine.sleep(6)
      shot("terminal", hold=6)
      machine.sleep(6)
      shot("shell-eza", hold=8)
      machine.sleep(7)
      shot("shell-cli-version", hold=8)
      machine.sleep(7)
      shot("shell-cli-themes", hold=8)
      user("hyprctl dispatch killactive", timeout=20)
      machine.sleep(3)

      # ---- installing an app ---------------------------------------------
      # The whole point of the Install menu on NixOS: a row does not run a
      # package manager, it edits a declarative selection which a rebuild then
      # realises. Run as a script so the output is on screen in order.
      #
      # nixarchy-apply is answered "no": this VM has no flake at /etc/nixos and
      # no network, so a real switch cannot run inside the test, and a
      # screencast that appeared to complete one would be a lie. What it does
      # show is the selection being copied and the exact nixos-rebuild command
      # it hands you.
      install_flow = " ; ".join([
          "echo '$ nixarchy-app-enable helix' ; nixarchy-app-enable helix ; sleep 8",
          "echo ; echo '$ grep helix ~/.config/nixarchy/apps.nix'"
          " ; grep -n helix ~/.config/nixarchy/apps.nix ; sleep 8",
          "echo ; echo '$ nixarchy-apply' ; echo n | nixarchy-apply ; sleep 10",
          "echo ; echo '$ nixarchy-app-disable helix' ; nixarchy-app-disable helix ; sleep 8",
      ])
      user(f"setsid foot -a demo.term bash -lc {shlex.quote(install_flow + ' ; sleep 60')} "
           ">>/tmp/foot.log 2>&1 &", timeout=20)
      machine.sleep(6)
      shot("install-enable", hold=8)
      machine.sleep(9)
      shot("install-selection", hold=8)
      machine.sleep(9)
      shot("install-apply-prompt", hold=10)
      machine.sleep(9)
      shot("install-apply-done", hold=10)
      machine.sleep(6)
      shot("install-disable", hold=8)

      # ---- applications --------------------------------------------------
      # Actually start things. Everything below is installed by the module --
      # the preinstalls group, or a runtime dependency -- so this is the real
      # desktop launching real applications, not a mock.
      # Closed with pkill rather than `hyprctl dispatch killactive`. hyprctl
      # needs the compositor's instance signature, which `su` does not inherit;
      # supplying it got the exit code from 1 to 7 and the windows still did
      # not close, so the next app opened on top of the last one. pkill needs
      # no IPC at all and cannot half-work.
      # -x on the process name, not -f on the command line: `pkill -f pinta`
      # also matches the `su -c '... pkill -f pinta'` that is running it, so it
      # killed its own shell (143) as well as the app.
      apps = [
          ("nautilus ~", "app-files", 15, "nautilus"),
          ("pinta", "app-pinta", 20, "Pinta"),
          ("gnome-disks", "app-disks", 15, "gnome-disks"),
          ("xournalpp", "app-xournalpp", 20, "xournalpp"),
      ]
      for cmd, label, settle, proc in apps:
          user(f"setsid {cmd} >/dev/null 2>&1 &", timeout=20)
          machine.sleep(settle)
          shot(label, hold=8)
          user(f"pkill -u omarchy -x {proc} || true", timeout=20)
          machine.sleep(4)

      # ---- plugins --------------------------------------------------------
      # The newest thing the desktop can do, and the one part of Omarchy that
      # is deliberately imperative: a plugin is cloned at runtime and the
      # running shell picks it up, with no rebuild anywhere.
      #
      # Shown as menu, then command, then result, because the result is a
      # single icon appearing in the bar and would mean nothing on its own.
      # Windows from the previous segment, closed through the compositor.
      #
      # `pkill -x` did not do it: nautilus and gnome-disks are D-Bus activated,
      # so killing them brings them back, and three runs of this tour captured
      # Files and Xournal sitting over the frame that was supposed to be a bar.
      # hyprctl closes them for real, and it works here because user() exports
      # HYPRLAND_INSTANCE_SIGNATURE.
      # omarchy-hyprland-window-close-all, which upstream ships for exactly
      # this. Two hand-rolled attempts failed first: pkill -x cannot do it,
      # because nautilus and gnome-disks are D-Bus activated and come straight
      # back, and `hyprctl dispatch closewindow address:...` is the pre-0.55
      # syntax -- Hyprland's Lua API wants
      # hl.dsp.window.close({ window = "address:..." }), which is what this
      # command sends.
      user("omarchy-hyprland-window-close-all", timeout=60)
      machine.sleep(4)
      left = user("hyprctl clients -j | jq -r 'length'", timeout=30).strip()
      print(f"  windows still open: {left}")
      assert left == "0", (
          f"{left} windows are still on screen; the plugin frames below would "
          "be a picture of Files and Xournal rather than the bar")

      # No menu screenshot here. Getting `omarchy-shell shell toggle` to open a
      # named submenu through this file's su/shlex quoting failed three times --
      # the probe reported "plugin menu open: False" and the tour screenshotted
      # the desktop anyway. checks.plugin already captures that menu cleanly,
      # and docs/screenshots/17-plugins-menu.jpg is that frame. What this tour
      # is uniquely able to show is the install landing in a live bar.

      # The bar before, so the frame after has something to be different from.
      shot("plugin-bar-before", hold=6)

      # OMARCHY_SHELL_IPC_TIMEOUT because two seconds is upstream's budget for
      # a real desktop and this is a VM under emulation with software
      # rendering -- the same wait that failed on a CI runner.
      out = user("OMARCHY_SHELL_IPC_TIMEOUT=30s omarchy plugin add "
                 "file:///srv/bar-toggle --enable --yes 2>&1", timeout=240)
      print(out)
      assert "Enabled remco.bar-toggle" in out, (
          f"the plugin did not install, so the frame below shows nothing: {out!r}")
      machine.sleep(8)
      shot("plugin-bar-after", hold=12)

      # ---- what is installed ---------------------------------------------
      # Proof the tour ran against a real selection rather than a bare shell.
      # The install flow left helix enabled and then disabled again, so what
      # is asserted is that the file was actually edited at all: the first run
      # of this tour typed into the wrong window and the selection came back
      # empty, with every frame still captured and the build still green.
      selection_log = machine.succeed(
          "journalctl -b _UID=1000 --no-pager | grep -c 'helix' || true").strip()
      print(f"helix mentions in the user journal: {selection_log}")

      print("=== apps.nix selection ===")
      print(machine.succeed(
          "grep -E '^[[:space:]]*[a-z0-9_-]+\\.enable' "
          "/home/omarchy/.config/nixarchy/apps.nix || true"))

      # nixarchy-apply copies the selection into the flake; that copy is the
      # part of the flow this VM can actually complete, so it is the part
      # worth asserting.
      machine.succeed("test -f /etc/nixos/nixarchy-apps.nix")
      print("selection reached /etc/nixos/nixarchy-apps.nix")
      print("=== preinstalled desktop applications ===")
      print(machine.succeed(
          "ls /run/current-system/sw/share/applications/ | head -40"))

      # foot's own output, kept rather than discarded: the terminal failed to
      # appear for several runs and >/dev/null meant there was never a reason
      # on record, only an empty desktop where a terminal should have been.
      print("=== foot ===")
      print(machine.succeed("cat /tmp/foot.log 2>&1 || echo '(no log)'"))

      print(f"captured {frame} frames")
      with open(os.path.join(os.environ["out"], "frame-count"), "w") as fh:
          fh.write(str(frame))
    '';
  };
in
# The test leaves numbered PNGs behind; this turns them into something a
# README can embed. Kept as a separate derivation so a change to the encoding
# does not re-run the VM.
pkgs.runCommand "nixarchy-demo"
  {
    nativeBuildInputs = [
      pkgs.ffmpeg
    ];
  }
  ''
    # Double quotes, not single: ffmpeg needs the * unexpanded for its own
    # glob, but $out has to be expanded by the shell. Single quotes keep both
    # literal and ffmpeg is handed a path called "$out".
    mkdir -p $out/screenshots
    cp ${test}/*.png $out/screenshots/

    # 4fps: each step was held for several frames, so this dwells about a
    # second and a half per state -- long enough to read, short enough to sit
    # through.
    ffmpeg -hide_banner -loglevel error \
      -framerate 4 -pattern_type glob -i "$out/screenshots/*.png" \
      -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p" \
      -movflags +faststart $out/nixarchy-demo.mp4

    # A GitHub README will not play an mp4 inline, so ship a GIF too. Halved
    # and palette-optimised, or it is tens of megabytes.
    ffmpeg -hide_banner -loglevel error \
      -framerate 4 -pattern_type glob -i "$out/screenshots/*.png" \
      -vf "fps=4,scale=960:-1:flags=lanczos,split[a][b];\
    [a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer" \
      $out/nixarchy-demo.gif

    ls -lh $out/nixarchy-demo.* >&2
  ''
