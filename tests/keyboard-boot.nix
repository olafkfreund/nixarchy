{
  inputs,
  pkgs,
}:
pkgs.testers.runNixOSTest {
  name = "nixarchy-keyboard-boot";
  globalTimeout = 115 * 60;

  nodes =
    let
      keyboard = console: layout: password: {
        imports = [
          inputs.self.nixosModules.nixarchy
          inputs.home-manager.nixosModules.home-manager
          ../installer/keyboard.nix
        ];

        programs.nixarchy.enable = true;
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
          hashedPasswordFile = pkgs.lib.mkForce null;
          # Hashes, because update-users-groups.pl dies on a non-ASCII initialPassword
          # ("Wide character in crypt") and creates no users.
          hashedPassword =
            pkgs.lib.mkForce
              {
                zy = "$6$nixarchytestsalt$8CJytf1kVAqS4JhE2fZQPJbCWLbWxXC1VUkfKJDaCeyB4C/tzoFr1MzArhcfliI9AelKPtKL0C0FqmuOQZSUK0";
                "abcй" =
                  "$6$nixarchytestsalt$2fG49ftcrX9TZEt56I2wp3hD9Tzs9p47Mw0CTYf9i6jlhGkQLDYmciKw.cMwxFtXEKu1..IaU6dNgs.ADkjNI.";
              }
              .${password};
          extraGroups = [
            "video"
            "input"
          ];
        };
        console.keyMap = console;
        services.xserver.xkb.layout = layout;
        environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE = "1";
        environment.systemPackages = [ pkgs.cryptsetup ];

        boot.loader.systemd-boot.enable = true;
        boot.plymouth.enable = true;
        virtualisation = {
          emptyDiskImages = [ 512 ];
          useBootLoader = true;
          useEFIBoot = true;
          mountHostNixStore = true;
          memorySize = 6144;
          cores = 4;
        };
        specialisation.boot-luks.configuration = {
          boot.initrd.luks.devices = pkgs.lib.mkVMOverride {
            cryptroot.device = "/dev/vdb";
          };
          virtualisation.rootDevice = "/dev/mapper/cryptroot";
        };
      };
    in
    {
      de = keyboard "de-latin1" "de" "zy";
      ru = keyboard "ru" "us,ru" "abcй";
    };

  testScript =
    { nodes, ... }:
    ''
      # Runs on the machine's first boot, whose session is what a real one gets. The root this
      # formats has no Nix database, so Home Manager fails on it and seeds no Omarchy config.
      def encrypted_boot(machine, system, passphrase, keys, physical=True):
          machine.succeed(f"printf %s {passphrase} | cryptsetup luksFormat -q --iter-time=1 /dev/vdb -")
          machine.succeed(f"printf %s {passphrase} | cryptsetup luksOpen -q /dev/vdb cryptroot")
          machine.succeed("mkfs.ext4 /dev/mapper/cryptroot")
          # As nixpkgs' own LUKS test does, once the disk is ready: bootctl's default did not hold.
          machine.succeed(f"{system}/bin/switch-to-configuration boot")
          machine.succeed("sync")
          machine.crash()
          machine.start()
          machine.wait_for_console_text("Please enter passphrase for disk cryptroot", timeout=240)
          if physical:
              machine.send_chars(keys + "\n")
          else:
              machine.send_console(keys + "\n")
          # A wrong passphrase re-prompts for ever, and wait_for_unit blocks on the shell before its
          # own timeout starts. The root device appears only once the disk is unlocked.
          machine.wait_for_console_text("Reached target Initrd Root Device", timeout=300)
          machine.wait_for_unit("display-manager.service")
          machine.wait_until_succeeds("loginctl list-sessions | grep greeter >/dev/null")
          machine.succeed("test -b /dev/mapper/cryptroot")

      def session_cmd(cmd):
          return ("su omarchy -c 'XDG_RUNTIME_DIR=/run/user/1000 "
                  "HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1) "
                  + cmd + "'")

      def greeter_login(machine, type_password):
          # logind has a greeter session a second before the greeter can read a key,
          # and a key sent then goes nowhere. A stray one is cleared before each try.
          for _ in range(12):
              machine.sleep(3)
              for _ in range(12):
                  machine.send_key("backspace")
              type_password()
              machine.sleep(2)
              if machine.execute("pgrep -u 1000 -f Hyprland")[0] == 0:
                  return
          raise AssertionError("the greeter never took the password")

      def first_boot(machine):
          machine.start()
          machine.wait_for_unit("multi-user.target")
          # A VM's first boot can start it before the user exists, as tests/session.nix found.
          machine.succeed("systemctl restart home-manager-omarchy.service")
          machine.wait_for_unit("display-manager.service")
          machine.wait_until_succeeds("loginctl list-sessions | grep greeter >/dev/null")

      first_boot(de)
      greeter_login(de, lambda: de.send_chars("yz\n"))
      de.wait_until_succeeds("journalctl -b -u display-manager --no-pager | grep 'Authentication for user .*omarchy.* successful' >/dev/null")
      # Not pgrep: it matches the session's preloader, seconds before the socket exists.
      de.wait_until_succeeds(session_cmd("hyprctl monitors >/dev/null"))
      de.succeed(session_cmd('hyprctl dispatch "hl.dsp.exec_cmd(\\"foot -e ${pkgs.writeShellScript "keyboard-capture" "cat >/tmp/typed"}\\")"'))
      # Typing before the terminal has focus sends the keys nowhere.
      de.wait_until_succeeds("test -e /tmp/typed", timeout=60)
      de.wait_until_succeeds(session_cmd('hyprctl activewindow | grep "class: foot" >/dev/null'), timeout=60)
      de.send_chars("yz\n")
      de.sleep(5)
      typed = de.succeed("cat /tmp/typed")
      assert typed == "zy\n", f"typed {typed!r}, layout " + de.succeed(session_cmd("hyprctl -j getoption input:kb_layout"))
      de.wait_until_succeeds(session_cmd("omarchy-shell lock lock"), timeout=120)
      locked = "su omarchy -c 'XDG_RUNTIME_DIR=/run/user/1000 omarchy-shell lock status' | python3 -c \"import json,sys; sys.exit(0 if json.load(sys.stdin)['locked'] else 1)\""
      unlocked = "su omarchy -c 'XDG_RUNTIME_DIR=/run/user/1000 omarchy-shell lock status' | python3 -c \"import json,sys; sys.exit(1 if json.load(sys.stdin)['locked'] else 0)\""
      de.wait_until_succeeds(locked)
      for attempt in range(4):
          de.send_key("shift")
          de.sleep(1)
          for _ in range(12):
              de.send_key("backspace")
          de.send_chars("yz\n")
          for _ in range(10):
              if de.execute(unlocked)[0] == 0:
                  break
              de.sleep(1)
          else:
              continue
          break
      de.succeed(unlocked)

      encrypted_boot(de, "${nodes.de.specialisation.boot-luks.configuration.system.build.toplevel}", "zy", "yz")

      def ru_password():
          ru.send_chars("abc")
          ru.send_key("alt-alt_r")
          ru.send_chars("q\n")
          # The next try starts from the Latin group again.
          ru.send_key("alt-alt_r")

      first_boot(ru)
      greeter_login(ru, ru_password)
      ru.wait_until_succeeds("journalctl -b -u display-manager --no-pager | grep 'Authentication for user .*omarchy.* successful' >/dev/null")
      ru.wait_until_succeeds(session_cmd("hyprctl monitors >/dev/null"))
      ru.succeed(session_cmd('hyprctl devices | grep "us,ru" >/dev/null'))
      encrypted_boot(ru, "${nodes.ru.specialisation.boot-luks.configuration.system.build.toplevel}", "omarchy", "omarchy", physical=False)
    '';
}
