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
          initialPassword = password;
          hashedPasswordFile = pkgs.lib.mkForce null;
          hashedPassword = pkgs.lib.mkForce null;
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
        boot.initrd.systemd.enable = true;
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

  testScript = ''
    def encrypted_boot(machine, passphrase, keys, physical=True):
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed(f"printf %s {passphrase} | cryptsetup luksFormat -q --iter-time=1 /dev/vdb -")
        machine.succeed(f"printf %s {passphrase} | cryptsetup luksOpen -q /dev/vdb cryptroot")
        machine.succeed("mkfs.ext4 /dev/mapper/cryptroot")
        machine.succeed("bootctl set-default nixos-generation-1-specialisation-boot-luks.conf")
        machine.succeed("sync")
        machine.crash()
        machine.start()
        machine.wait_for_console_text("Please enter passphrase for disk cryptroot")
        if physical:
            machine.send_chars(keys + "\n")
        else:
            machine.send_console(keys + "\n")
        machine.wait_for_unit("display-manager.service")
        machine.wait_until_succeeds("loginctl list-sessions | grep -q greeter")
        machine.succeed("test -b /dev/mapper/cryptroot")

    def session_cmd(cmd):
        return ("su omarchy -c 'XDG_RUNTIME_DIR=/run/user/1000 "
                "HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1) "
                + cmd + "'")

    encrypted_boot(de, "zy", "yz")
    de.send_chars("yz\n")
    de.wait_until_succeeds("journalctl -b -u display-manager --no-pager | grep 'Authentication for user .*omarchy.* successful' >/dev/null")
    de.wait_until_succeeds("pgrep -u 1000 -f Hyprland")
    de.succeed(session_cmd('hyprctl dispatch exec "foot -e ${pkgs.writeShellScript "keyboard-capture" "cat >/tmp/typed"}"'))
    de.send_chars("yz\n")
    de.wait_until_succeeds("grep -qx zy /tmp/typed")
    de.succeed(session_cmd("omarchy-shell lock lock"))
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

    encrypted_boot(ru, "omarchy", "omarchy", physical=False)
    ru.send_chars("abc")
    ru.send_key("alt-alt_r")
    ru.send_chars("q\n")
    ru.wait_until_succeeds("journalctl -b -u display-manager --no-pager | grep 'Authentication for user .*omarchy.* successful' >/dev/null")
    ru.wait_until_succeeds("pgrep -u 1000 -f Hyprland")
    ru.succeed(session_cmd('hyprctl devices | grep "us,ru" >/dev/null'))
  '';
}
