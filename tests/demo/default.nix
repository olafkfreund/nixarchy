{
  inputs,
  pkgs,
  microvmRunner ? null,
}:
# The demo recorder, scene by scene.
#
# This grew out of tests/demo.nix, which recorded one five-minute tour in one
# VM run. That shape rotted the moment a single menu changed: re-recording
# anything meant re-recording everything, so nothing got re-recorded, and the
# feature GIFs in docs/ drifted until one of them showed a wallpaper where a
# microvm was claimed. Two changes follow from that failure:
#
#   * Scenes. Each feature is its own VM run producing its own GIF, sized for
#     a README (900px wide, under 1MB), rebuilt alone when its feature
#     changes: `nix run .#demo-record -- <scene>`. The old full tour is still
#     here as `nix build .#demo`, composed from the same segments.
#
#   * Verification, in the tool. Every scene's GIF goes through
#     verify-frames.sh before the build is allowed to succeed: sampled frames
#     must actually change over the GIF's length, and their OCR text must
#     contain the strings the scene claims to show. A recording of a
#     wallpaper cannot pass the microvm scene's gate no matter how it was
#     produced. The sampled frames are kept in the output so a human can
#     look at them too -- the gate is a floor, not a substitute for eyes.
#
# Everything else -- the su/shlex quoting, the wallpaper wait, the idle
# toggle, pkill vs hyprctl -- is inherited from tests/demo.nix and its
# hard-won comments, kept next to the code they explain.
let
  inherit (pkgs) lib;

  # A real published plugin, pinned, so the plugin scene shows the plugin
  # system working on something somebody actually wrote rather than a fixture.
  barToggle = pkgs.fetchgit {
    url = "https://github.com/r3mcos3/omarchy-bar-toggle.git";
    rev = "586750d0fa902b8774d1559fff954da540742a1e";
    hash = "sha256-K45Qwgdf+K943nPHxrgS0IE9slsno9uZjIkr3XnfVBM=";
  };

  # The machine every scene runs on. One node definition, so a scene records
  # the same desktop the session test proves, not a variant that quietly
  # diverges.
  baseNode = {
    imports = [
      inputs.self.nixosModules.nixarchy
      inputs.home-manager.nixosModules.home-manager
    ];

    programs.nixarchy = {
      enable = true;
      flake = "/etc/nixos";
    };

    boot.plymouth.enable = lib.mkForce false;
    environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";

    # Deliberately the same display the session test uses. A larger one was
    # tried first and is exactly the sort of unverified change that turns a
    # five minute run into a fourteen minute hang with nothing to show.
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;

    # nixarchy-apply refuses to do anything without a flake directory to copy
    # the selection into, and exits before it prints a word about it.
    # fetchgit hands over a plain directory with no .git, and the machine has
    # no network, so the plugin repo's history is rebuilt here and cloned over
    # file:// -- a real transport in omarchy-git-url-check's allowlist.
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

  # ---- the shared prelude ---------------------------------------------------
  # Frame helpers, the session-environment dance, login, and a settled
  # desktop. Every scene starts here; the tour additionally photographs the
  # greeter and the fresh desktop on its way through.
  prelude =
    {
      greeterShots ? false,
    }:
    ''
      import os
      import shlex

      # Frames are numbered because ffmpeg stitches them in glob order, and
      # "10" sorting before "2" would play the scene out of sequence.
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

      def user(cmd, timeout=90):
          """Run `cmd` as the logged-in user, bounded.

          Bounded because machine.succeed() waits forever, and several of
          these do hang: omarchy-theme-set ends by running its whole
          post_theme_commands list, and a screencast is not worth blocking a
          build on one of them stalling. A step that times out leaves the
          frames captured up to that point.

          The environment exports are load-bearing, all three learned the
          hard way in tests/demo.nix: XDG_RUNTIME_DIR and the D-Bus address
          because `su` inherits none of the session environment,
          HYPRLAND_INSTANCE_SIGNATURE because hyprctl finds the compositor
          through it, and WAYLAND_DISPLAY because without it foot exited
          with "no compositor running?" and the terminal frames were of an
          empty desktop.
          """
          full = ("export XDG_RUNTIME_DIR=/run/user/1000 "
                  "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
                  "export HYPRLAND_INSTANCE_SIGNATURE="
                  "$(ls -t /run/user/1000/hypr 2>/dev/null | head -1); "
                  "export WAYLAND_DISPLAY=$(basename "
                  "$(ls -t /run/user/1000/wayland-* 2>/dev/null "
                  "| grep -v '\\.lock$' | head -1)); "
                  + cmd)
          status, out = machine.execute(
              "su omarchy -c " + shlex.quote(full), timeout=timeout)
          if status != 0:
              print(f"  (step returned {status}: {cmd})")
          return out

      def terminal(script, label_holds, settle=6, tail=60):
          """Run a shell script inside a real foot terminal and photograph it.

          Everything runs *inside* the terminal rather than being typed at
          it: send_chars goes to whatever the compositor has focused, and a
          script passed to foot cannot miss. `label_holds` is a list of
          (label, hold, sleep_after) tuples paced against the script's own
          sleeps.
          """
          user(f"setsid foot -a demo.term bash -lc "
               f"{shlex.quote(script + f' ; sleep {tail}')} "
               ">>/tmp/foot.log 2>&1 &", timeout=20)
          machine.sleep(settle)
          for label, hold, after in label_holds:
              shot(label, hold=hold)
              if after:
                  machine.sleep(after)

      machine.wait_for_unit("multi-user.target")

      # ---- the greeter ---------------------------------------------------
      machine.wait_for_unit("display-manager.service")
      machine.wait_until_succeeds("loginctl list-sessions | grep -q greeter")
      # Retried, not slept at: typing a password at a greeter that has not
      # drawn yet sends it nowhere.
      drawn = ""
      for attempt in range(10):
          machine.sleep(4)
          machine.screenshot("greeter-probe")
          drawn = machine.get_screen_text().strip()
          print(f"  greeter attempt {attempt}: {drawn!r}")
          if drawn:
              break
      assert drawn, "the greeter never drew anything in 40s"
      ${lib.optionalString greeterShots ''shot("greeter", hold=8)''}

      machine.send_chars("omarchy\n")
      machine.wait_until_succeeds(
          "journalctl -b -u display-manager --no-pager"
          " | grep -q 'Authentication for user .*omarchy.* successful'")

      # ---- the desktop ---------------------------------------------------
      # systemd-logind starts user@1000.service asynchronously once the
      # session opens, and wait_for_unit raises "is inactive and there are no
      # pending jobs" the moment it looks during that window -- so poll.
      machine.wait_until_succeeds("systemctl is-active user@1000.service")
      # -f, matching the whole command line: on NixOS the running binary is a
      # wrapper, so its name is not literally "quickshell" and -x waits
      # forever on a shell that is up and logging happily.
      machine.wait_until_succeeds("pgrep -u 1000 -f quickshell")

      # Omarchy dims at 150s idle and locks at 300s, and a scene spends
      # minutes waiting for things to settle without touching the keyboard.
      user("omarchy-toggle-idle stay-awake", timeout=30)

      # The bar and the wallpaper do not arrive together; wait for the
      # wallpaper the session test checks for, then let the bar settle.
      machine.wait_until_succeeds(
          "test -s $(readlink -f "
          "/home/omarchy/.local/state/omarchy/current/background)")
      machine.sleep(20)

      # The first-run notifications ("Update System", "Learn Keybindings")
      # sat in the corner of every previously shipped GIF as noise. Dismiss
      # them; `|| true` because a desktop with no notification daemon up yet
      # is not a reason to lose the recording.
      user("makoctl dismiss -a || true", timeout=20)
      machine.sleep(2)
      ${lib.optionalString greeterShots ''shot("desktop", hold=10)''}
    '';

  epilogue = ''
    print(f"captured {frame} frames")
    # os.environ.get, not os.environ[]: an online scene's driver runs
    # outside the sandbox with no $out, writing frames into -o's directory,
    # and a KeyError on the very last line would throw away a finished
    # recording.
    with open(os.path.join(os.environ.get("out", os.getcwd()),
                           "frame-count"), "w") as fh:
        fh.write(str(frame))
  '';

  # ---- the segments ---------------------------------------------------------
  # Python snippets that assume the prelude ran. A scene is one or two of
  # these; the tour is all of them in order.
  segments = {
    menus = ''
      # ---- the menus -----------------------------------------------------
      # SUPER + SPACE opens the root menu for real, so the recording shows
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
      for route, label in [
          ("apps", "menu-apps"),
          ("install", "menu-install"),
          ("install.terminal", "menu-install-terminal"),
          ("install.editor", "menu-install-editor"),
          ("remove", "menu-remove"),
          ("update", "menu-update"),
          ("style", "menu-style"),
          ("system", "menu-system"),
          ("setup.default.agent", "menu-default-agent"),
          ("trigger", "menu-trigger"),
      ]:
          user(f"omarchy-menu summon {route}", timeout=30)
          machine.sleep(5)
          shot(label, hold=8)
      user("omarchy-menu close", timeout=20)

      # Escape as well as close: some routes summon separate layers that
      # omarchy-menu close leaves up, and a stray layer pins itself over
      # every later frame.
      machine.send_key("esc")
      machine.sleep(3)
    '';

    themes = ''
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
    '';

    shell = ''
      # ---- the shell tools -----------------------------------------------
      terminal(" ; ".join([
          "echo '$ ls -la ~' ; ls -la ~ ; sleep 6",
          "echo '$ omarchy version' ; omarchy version ; sleep 6",
          "echo '$ omarchy theme list' ; omarchy theme list ; sleep 6",
      ]), [
          ("terminal", 6, 6),
          ("shell-eza", 8, 7),
          ("shell-cli-version", 8, 7),
          ("shell-cli-themes", 8, 0),
      ])
      user("hyprctl dispatch killactive", timeout=20)
      machine.sleep(3)
    '';

    install = ''
      # ---- installing an app ---------------------------------------------
      # The story that separates nixarchy from Omarchy: an Install menu row
      # does not run a package manager, it edits a declarative selection in
      # ~/.config/nixarchy/apps.nix which a rebuild then realises. Menu
      # first, then the same flow in a terminal where the file edit is
      # visible.
      user("omarchy-menu summon install", timeout=30)
      machine.sleep(5)
      shot("install-menu", hold=8)
      user("omarchy-menu summon install.editor", timeout=30)
      machine.sleep(5)
      shot("install-menu-editor", hold=8)
      user("omarchy-menu close", timeout=20)
      machine.send_key("esc")
      machine.sleep(3)

      # nixarchy-apply is answered "no": this VM has no flake at /etc/nixos
      # and no network, so a real switch cannot run inside the recording, and
      # a screencast that appeared to complete one would be a lie. What it
      # does show is the selection being copied and the exact nixos-rebuild
      # command it hands you.
      terminal(" ; ".join([
          "echo '$ nixarchy-app-enable helix' ; nixarchy-app-enable helix ; sleep 8",
          "echo ; echo '$ grep helix ~/.config/nixarchy/apps.nix'"
          " ; grep -n helix ~/.config/nixarchy/apps.nix ; sleep 8",
          "echo ; echo '$ nixarchy-apply' ; echo n | nixarchy-apply ; sleep 10",
          "echo ; echo '$ nixarchy-app-disable helix' ; nixarchy-app-disable helix ; sleep 8",
      ]), [
          ("install-enable", 8, 9),
          ("install-selection", 8, 9),
          ("install-apply-prompt", 10, 9),
          ("install-apply-done", 10, 6),
          ("install-disable", 8, 0),
      ])
      user("hyprctl dispatch killactive", timeout=20)
      machine.sleep(3)

      # The recording is only worth keeping if the flow really edited the
      # selection and nixarchy-apply really copied it: the first run of the
      # old tour typed into the wrong window and the selection came back
      # empty, with every frame still captured and the build still green.
      machine.succeed("test -f /etc/nixos/nixarchy-apps.nix")
      machine.succeed("test -f /etc/nixos/nixarchy/apps.nix")
      print("selection reached /etc/nixos/nixarchy/apps.nix")
    '';

    devenv = ''
      # ---- devenv --------------------------------------------------------
      # `nixarchy dev init <preset>`: upstream devenv's scaffold with the
      # preset's language lines flipped in. Offline-safe by design -- the
      # scaffold is files, and the recording stops before the first
      # activation, which is the step that needs the network.
      terminal(" ; ".join([
          "echo '$ nixarchy dev init' ; nixarchy dev init ; sleep 8",
          "mkdir -p ~/demo-api && cd ~/demo-api",
          "echo ; echo '$ nixarchy dev init python' ; nixarchy dev init python ; sleep 10",
          "echo ; echo '$ cat devenv.nix' ; cat devenv.nix ; sleep 10",
      ]), [
          ("devenv-presets", 8, 9),
          ("devenv-init", 10, 11),
          ("devenv-nix", 12, 0),
      ], tail=90)
      user("hyprctl dispatch killactive", timeout=20)
      machine.sleep(3)

      # The scaffold really landed, with the preset's lines in it.
      machine.succeed("test -f /home/omarchy/demo-api/devenv.nix")
      machine.succeed("grep -q 'languages.python' /home/omarchy/demo-api/devenv.nix")
    '';

    microvm = ''
      # ---- microvm sandboxes ---------------------------------------------
      # The scene that replaces the shipped GIF which never showed a guest.
      # A real guest, booting on screen: `nixarchy vm create`, then the
      # template's own runner attached to the terminal, TCG so it works on
      # any builder, and the recording waits for the guest's autologin
      # prompt before it claims anything.
      #
      # One honest asterisk, stated here and in the scene's docs:
      # `nixarchy vm run` starts by `nix build`ing the runner from GitHub,
      # and this VM has no network. The scene pre-places the very out-link
      # that build would have produced (the same store path, built by the
      # same flake) and then runs exactly what run_vm execs. The boot, the
      # console and the guest are real; the elided step is a download.
      terminal(" ; ".join([
          "echo '$ nixarchy vm templates' ; nixarchy vm templates ; sleep 8",
          # --template shell spelled out even though it is the default: the
          # owner's ask is "working from the given templates", so the
          # template is the visible subject of the create, not an implied
          # default. The templates listing above is data/microvm-templates.nix
          # verbatim -- every entry, not a fixture.
          "echo ; echo '$ nixarchy vm create demo --template shell'"
          " ; nixarchy vm create demo --template shell ; sleep 4",
          "echo ; echo '$ nixarchy vm list' ; nixarchy vm list ; sleep 6",
          "cd ~/.local/state/nixarchy/microvm/demo",
          "ln -sfn ${microvmRunner} current",
          "echo ; echo '$ nixarchy vm run demo'",
          "./current/bin/microvm-run 2>&1 | tee /tmp/microvm-console.log",
      ]), [
          ("vm-templates", 8, 7),
          ("vm-create", 8, 6),
          ("vm-list", 8, 0),
      ], tail=0)

      # TCG boots this guest in a couple of minutes; wait on the console
      # log for the autologin prompt rather than on a clock. The hostname
      # is 'demo' because create wrote it and the guest's oneshot read it --
      # seeing dev@demo is seeing that whole mechanism work.
      machine.wait_until_succeeds(
          "grep -q 'dev@demo' /tmp/microvm-console.log", timeout=600)
      machine.sleep(4)
      shot("vm-guest-prompt", hold=10)

      # Type into the guest through the terminal: the console is the door.
      machine.send_chars("uname -a && hostname\n")
      machine.wait_until_succeeds(
          "grep -q 'GNU/Linux' /tmp/microvm-console.log", timeout=60)
      machine.sleep(3)
      shot("vm-guest-shell", hold=12)

      # The claim, asserted: a guest booted and answered.
      out = machine.succeed("cat /tmp/microvm-console.log")
      assert "dev@demo" in out, "no guest prompt ever reached the console"
    '';

    boxes = ''
      # ---- boxes (distrobox) ---------------------------------------------
      # Not command output ABOUT a box -- a distro installed, entered, and
      # visibly running: pacman installing a package inside the Arch
      # userland, on a NixOS host, which is the entire point of the feature.
      #
      # This scene runs with a NETWORK, and that is honest rather than a
      # concession: `nixarchy box create` pulls the image with podman over
      # the real network -- the one step checks.box-template deliberately
      # does not attempt -- and tests/box-boot.nix pins that the offline
      # first `distrobox enter` fails loudly at the entrypoint. A real user
      # creates a box online; so does this recording. It therefore cannot be
      # a sandboxed `nix build`: demo-record runs this scene's driver
      # outside the sandbox, where qemu's user-mode netdev reaches out.
      terminal(" ; ".join([
          "echo '$ nixarchy box templates' ; nixarchy box templates ; sleep 8",
          "echo ; echo '$ nixarchy box create demo --template archlinux'"
          # tee, because foot's own log only carries foot's stderr: the wait
          # below needs the create's last line, and the screen alone cannot
          # be grepped.
          " ; nixarchy box create demo --template archlinux 2>&1"
          " | tee /tmp/box-create.log",
          # `script` keeps the enter interactive -- a plain pipe through tee
          # would take the TTY away from the container shell -- while still
          # logging everything typed and printed for the waits below.
          "echo ; echo '$ nixarchy box enter demo'"
          " ; script -qfc 'distrobox enter demo' /tmp/box-tty.log",
      ]), [
          ("box-templates", 8, 0),
      ], tail=0)

      # The image pull is real and takes minutes; wait for create's own
      # closing line, not a clock.
      machine.wait_until_succeeds(
          "grep -q 'nixarchy box enter' /tmp/box-create.log", timeout=900)
      shot("box-created", hold=8)

      # First enter provisions the container (distrobox-init) before it
      # hands over a prompt; its completion banner is the condition.
      machine.wait_until_succeeds(
          "grep -qi 'container setup complete' /tmp/box-tty.log", timeout=900)
      machine.sleep(4)
      shot("box-entered", hold=8)

      # Now type into the Arch userland through the terminal.
      machine.send_chars("cat /etc/os-release | head -3\n")
      machine.wait_until_succeeds(
          "grep -q 'Arch Linux' /tmp/box-tty.log", timeout=60)
      machine.sleep(2)
      shot("box-os-release", hold=10)

      machine.send_chars("sudo pacman -S --noconfirm figlet\n")
      machine.wait_until_succeeds(
          "grep -qiE 'installing figlet|figlet.*is up to date' /tmp/box-tty.log",
          timeout=600)
      machine.sleep(4)
      shot("box-pacman", hold=10)

      machine.send_chars("figlet 'Arch on NixOS'\n")
      machine.sleep(4)
      shot("box-figlet", hold=12)
      machine.send_chars("exit\n")
      machine.sleep(2)

      # The claim, asserted: an Arch userland answered, and pacman ran in it.
      out = machine.succeed("cat /tmp/box-tty.log")
      assert "Arch Linux" in out, "the box never showed an Arch userland"
      assert "pacman" in out, "nothing was installed inside the box"
    '';

    plugin = ''
      # ---- plugins --------------------------------------------------------
      # The one deliberately imperative corner of Omarchy: a plugin is cloned
      # at runtime and the running shell picks it up, with no rebuild
      # anywhere. Shown as bar-before, install, bar-after, because the result
      # is a single icon appearing in the bar and would mean nothing alone.
      user("omarchy-hyprland-window-close-all", timeout=60)
      machine.sleep(4)
      left = user("hyprctl clients -j | jq -r 'length'", timeout=30).strip()
      print(f"  windows still open: {left}")
      assert left == "0", (
          f"{left} windows are still on screen; the plugin frames below would "
          "be a picture of them rather than the bar")

      shot("plugin-bar-before", hold=6)

      # OMARCHY_SHELL_IPC_TIMEOUT because two seconds is upstream's budget
      # for a real desktop and this is a VM under emulation with software
      # rendering.
      out = user("OMARCHY_SHELL_IPC_TIMEOUT=30s omarchy plugin add "
                 "file:///srv/bar-toggle --enable --yes 2>&1", timeout=240)
      print(out)
      assert "Enabled remco.bar-toggle" in out, (
          f"the plugin did not install, so the frame below shows nothing: {out!r}")
      machine.sleep(8)
      shot("plugin-bar-after", hold=12)
    '';

    apps = ''
      # ---- applications --------------------------------------------------
      # Actually start things. Everything below is installed by the module,
      # so this is the real desktop launching real applications, not a mock.
      # pkill -x on the process name: -f also matches the su running it.
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
    '';
  };

  # ---- scenes ---------------------------------------------------------------
  # What each scene records, what its GIF must show to be allowed to exist,
  # and anything its machine needs beyond the base node.
  #
  # `expects` are case-insensitive extended regexes matched against the OCR
  # text of frames sampled across the finished GIF -- the check that rejects
  # a recording of the wrong thing. `minDistinct` is how many of ~11 sampled
  # transitions must differ by >2% RMSE -- the check that rejects a frozen
  # one. Measured floor: a real terminal scene holding still measures 2.
  sceneDefs = {
    menus = {
      script = segments.menus;
      expects = [
        "install"
        "style"
      ];
      minDistinct = 4;
    };
    themes = {
      script = segments.themes;
      # Themes have no stable text to demand -- the whole point is that
      # everything changes -- so this scene leans on a high diversity floor:
      # five theme switches and two backgrounds must actually repaint.
      expects = [ ];
      minDistinct = 5;
    };
    install = {
      script = segments.install;
      expects = [
        "nixarchy-app-enable"
        "apps\\.nix"
      ];
      minDistinct = 3;
    };
    devenv = {
      script = segments.devenv;
      expects = [
        "devenv"
        "languages"
      ];
      minDistinct = 2;
      extraNode.programs.nixarchy.services.devenv.enable = true;
    };
    plugin = {
      script = segments.plugin;
      # The payoff is one icon appearing in the bar -- no OCR-able text, and
      # barely any pixels, so the honesty here is the in-script assert on
      # "Enabled remco.bar-toggle" rather than the GIF gate.
      expects = [ ];
      minDistinct = 1;
    };
    boxes = {
      script = segments.boxes;
      expects = [
        "Arch Linux"
        "pacman"
      ];
      minDistinct = 3;
      # Online: the image pull and the first `distrobox enter` need the real
      # network, so this scene cannot be a sandboxed `nix build`.
      # demo-record builds this attr -- which is the scene's test DRIVER, not
      # a GIF -- runs it outside the sandbox where qemu's user-mode netdev
      # reaches out, and encodes and gates the result itself, with the same
      # encoder and the same verify gate as every sandboxed scene.
      online = true;
      extraNode = {
        programs.nixarchy.services.boxes.enable = true;
        # The SLIRP interface, made usable: qemu's user netdev serves DHCP
        # and a DNS proxy at 10.0.2.3, but the test instrumentation leaves
        # interfaces static. Both lines are inert in the sandbox (no route
        # out) and load-bearing outside it.
        networking.interfaces.eth0.useDHCP = lib.mkForce true;
        networking.nameservers = [ "10.0.2.3" ];
      };
    };
    microvm = {
      script = segments.microvm;
      expects = [
        "nixarchy vm"
        "dev@demo"
      ];
      minDistinct = 2;
      extraNode = {
        # The guest's whole closure has to be in this VM's store: the runner
        # 9p-shares the host store into the guest, and here the "host" is
        # the recording VM.
        virtualisation.additionalPaths = [ microvmRunner ];
        # Room for a TCG guest beside a full desktop. mkForce because the
        # base node pins the session test's 4096 and both land at the same
        # priority otherwise.
        virtualisation.memorySize = lib.mkForce 6144;
      };
    };
  };

  tourOrder = [
    "menus"
    "themes"
    "shell"
    "install"
    "apps"
    "plugin"
  ];

  # ---- machinery ------------------------------------------------------------
  mkTest =
    name:
    {
      script,
      extraNode ? { },
      greeterShots ? false,
    }:
    pkgs.testers.runNixOSTest {
      name = "nixarchy-demo-${name}";
      # The greeter wait reads the screen, and get_screen_text needs this.
      enableOCR = true;
      nodes.machine.imports = [
        baseNode
        extraNode
      ];
      testScript = (prelude { inherit greeterShots; }) + script + epilogue;
    };

  verifyScript = ./verify-frames.sh;

  verifyInputs = [
    pkgs.ffmpeg
    pkgs.imagemagick
    # English only: the default wrapper bundles every language tesseract has,
    # which is a gigabyte of training data to OCR English terminal text.
    (pkgs.tesseract.override { enableLanguages = [ "eng" ]; })
  ];

  encodeScript = ./encode-gif.sh;

  # The verify invocation for one scene, shared verbatim between the
  # sandboxed build below and demo-record's online path -- two gates that
  # drifted apart would let a GIF pass a bar its sibling was never held to.
  verifyArgs =
    { minDistinct, expects, ... }:
    lib.concatStringsSep " " (
      [
        "--max-bytes 1000000"
        "--min-distinct ${toString minDistinct}"
      ]
      ++ map (e: "--expect ${lib.escapeShellArg e}") expects
    );

  # One scene, encoded and gated. The GIF is 900px wide -- the size the
  # README's existing good recording uses -- and the build FAILS if the
  # result is over 1MB (split the scene instead of degrading it), if the
  # sampled frames barely change, or if the OCR never shows what the scene
  # claims. The sampled frames land in $out/verify for human eyes.
  #
  # An online scene (needs the real network in the VM) cannot record inside
  # the sandbox, so its attr is the test DRIVER for demo-record to run
  # outside it; everything else is the finished, gated GIF.
  mkScene =
    name: def:
    if def.online or false then
      (mkTest name {
        inherit (def) script;
        extraNode = def.extraNode or { };
      }).driver
    else
      let
        test = mkTest name {
          inherit (def) script;
          extraNode = def.extraNode or { };
        };
      in
      pkgs.runCommand "nixarchy-demo-${name}"
        {
          nativeBuildInputs = verifyInputs;
        }
        ''
          mkdir -p $out/screenshots $out/verify
          cp ${test}/*.png $out/screenshots/

          bash ${encodeScript} $out/screenshots $out/${name}.gif

          bash ${verifyScript} $out/${name}.gif \
            ${verifyArgs def} \
            --dump $out/verify

          ls -lh $out/${name}.gif >&2
        '';

  scenes = lib.mapAttrs mkScene sceneDefs;

  # The full tour: every segment in one VM run, plus the mp4 the GIF is cut
  # from. Verified for life (diversity) but not for per-feature text -- the
  # per-scene gates are where the claims live.
  tourTest = mkTest "tour" {
    script = lib.concatMapStrings (s: segments.${s}) tourOrder;
    greeterShots = true;
  };

  tour =
    pkgs.runCommand "nixarchy-demo"
      {
        nativeBuildInputs = verifyInputs;
      }
      ''
        mkdir -p $out/screenshots $out/verify
        cp ${tourTest}/*.png $out/screenshots/

        ffmpeg -hide_banner -loglevel error \
          -framerate 4 -pattern_type glob -i "$out/screenshots/*.png" \
          -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p" \
          -movflags +faststart $out/nixarchy-demo.mp4

        # A GitHub README will not play an mp4 inline, so ship a GIF too.
        ffmpeg -hide_banner -loglevel error \
          -framerate 4 -pattern_type glob -i "$out/screenshots/*.png" \
          -vf "fps=4,scale=960:-1:flags=lanczos,split[a][b];\
        [a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer" \
          $out/nixarchy-demo.gif

        bash ${verifyScript} $out/nixarchy-demo.gif \
          --min-distinct 8 --dump $out/verify

        ls -lh $out/nixarchy-demo.* >&2
      '';

  # `nix run .#demo-verify -- some.gif --expect 'dev@'` -- the gate as a
  # standalone tool, for auditing a GIF somebody hands you.
  verifier = pkgs.writeShellApplication {
    name = "demo-verify";
    runtimeInputs = verifyInputs;
    # The script does its own argument handling and its unchecked variables
    # are all its own; writeShellApplication's checkPhase runs shellcheck on
    # the wrapper below, and the script itself is shellchecked in CI.
    text = ''
      exec bash ${verifyScript} "$@"
    '';
  };

  onlineScenes = lib.filterAttrs (_: d: d.online or false) sceneDefs;

  # `nix run .#demo-record -- <scene>` -- rebuild one scene's GIF and put it
  # where the README looks for it. Builds from the flake in the current
  # directory, on purpose: re-recording after a change is the whole use case.
  #
  # Two paths through it. An offline scene is a sandboxed `nix build` whose
  # derivation already encoded and gated the GIF. An online scene (boxes:
  # the image pull and first enter need the real network) builds the same
  # test's DRIVER instead and runs it right here, outside the sandbox, where
  # qemu's user netdev reaches the internet -- then encodes and gates the
  # frames with the same scripts the sandboxed path uses.
  recorder = pkgs.writeShellApplication {
    name = "demo-record";
    runtimeInputs = verifyInputs;
    text = ''
      scenes="${lib.concatStringsSep " " (builtins.attrNames sceneDefs)}"
      online_scenes="${lib.concatStringsSep " " (builtins.attrNames onlineScenes)}"

      usage() {
        cat <<EOF
      usage: demo-record <scene> [--out DIR]
             demo-record --list

      Boots a VM, records the scene, verifies the GIF actually shows what it
      claims (frame diversity + OCR content), and copies it to
      docs/img/features/<scene>.gif. Run it from the repo root. The sampled
      verification frames are left next to the build result -- LOOK at them
      before committing; the gate is a floor, not a reviewer.

      scenes: $scenes
      (need the network, recorded outside the sandbox: $online_scenes)
      EOF
        exit 2
      }

      verify_args() {
        case "$1" in
      ${lib.concatStrings (
        lib.mapAttrsToList (n: d: ''
          ${n}) echo ${lib.escapeShellArg (verifyArgs d)} ;;
        '') onlineScenes
      )}
          *) echo ""; return 1 ;;
        esac
      }

      scene=""
      outdir="docs/img/features"
      while [ $# -gt 0 ]; do
        case "$1" in
          --list) echo "$scenes" | tr ' ' '\n'; exit 0 ;;
          --out) outdir="''${2:?}"; shift 2 ;;
          -h|--help) usage ;;
          *) scene="$1"; shift ;;
        esac
      done
      [ -n "$scene" ] || usage
      case " $scenes " in
        *" $scene "*) ;;
        *) echo "demo-record: no scene '$scene' (try --list)" >&2; exit 1 ;;
      esac

      if [ ! -f flake.nix ]; then
        echo "demo-record: run from the repo root -- it builds .#demo-scene-$scene" >&2
        exit 1
      fi

      link=".demo-record-$scene"
      echo "recording '$scene' -- this boots a VM and takes minutes..."
      nix build ".#demo-scene-$scene" --out-link "$link" --print-build-logs

      case " $online_scenes " in
        *" $scene "*)
          # The built attr is the test driver. Run it here, unsandboxed, so
          # the VM's user-mode network reaches out; frames land in a scratch
          # directory and go through the very same encode and gate.
          work=$(mktemp -d "demo-record-$scene.XXXXXX")
          echo "'$scene' needs the network in the VM (a real image pull);"
          echo "running its driver outside the sandbox, frames in $work..."
          "$link/bin/nixos-test-driver" --no-interactive -o "$work"

          mkdir -p "$work/verify"
          bash ${encodeScript} "$work" "$work/$scene.gif"
          # The args string carries shell quoting ("--expect 'Arch Linux'"),
          # so it is re-parsed into an array rather than word-split raw.
          declare -a vargs=()
          eval "vargs=($(verify_args "$scene"))"
          bash ${verifyScript} "$work/$scene.gif" \
            "''${vargs[@]}" --dump "$work/verify"
          gif="$work/$scene.gif"
          frames="$work/verify"
          ;;
        *)
          gif="$link/$scene.gif"
          frames="$(readlink -f "$link")/verify"
          ;;
      esac

      mkdir -p "$outdir"
      install -m 0644 "$gif" "$outdir/$scene.gif"
      echo
      echo "wrote $outdir/$scene.gif ($(stat -c %s "$outdir/$scene.gif") bytes)"
      echo "verification frames to LOOK at: $frames/"
    '';
  };
in
{
  demo = tour;
  demo-record = recorder;
  demo-verify = verifier;
}
// lib.mapAttrs' (name: scene: lib.nameValuePair "demo-scene-${name}" scene) scenes
