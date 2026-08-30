{
  inputs,
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  # Smoke-test VM. The point is to answer one question cheaply: does the
  # QuickShell bar come up against Hyprland's Lua config? Everything here
  # exists to get to a logged-in session fast, not to be a good NixOS host.
  #
  # qemu-vm.nix is imported directly rather than going through
  # `virtualisation.vmVariant`: this configuration is never anything but a VM,
  # and the import is what supplies the root filesystem and bootloader that a
  # bare nixosSystem is missing.
  imports = [
    "${modulesPath}/virtualisation/qemu-vm.nix"

    # The installed host, unchanged. Everything below this line is the
    # difference between an Omarchy machine and a throwaway qemu guest, which
    # is the only thing this file should still contain.
    #
    # The relative path resolves inside the store copy too, which matters: the
    # activation script below writes a flake importing
    # "${nixarchy}/vm/configuration.nix", and that copy must find
    # ../installer/host.nix beside it. It does -- the flake source is one path.
    (import ../installer/host.nix {
      hostname = "nixarchy-vm";
      username = "omarchy";
    })
  ];

  users.users.root.password = "omarchy"; # VM-only.

  # Merged with host.nix's definition of the same user: it supplies the groups
  # and isNormalUser, this supplies what only a throwaway guest should have.
  users.users.omarchy = {
    description = "Nixarchy smoke test";
    password = "omarchy"; # VM-only; never reachable off the host.
  };

  # Straight to a session -- a login prompt adds nothing to the smoke test.
  services.displayManager.autoLogin = {
    enable = true;
    user = "omarchy";
  };

  # Software rendering: the VM has no GPU, and wlroots refuses to start
  # without one unless told this is acceptable.
  environment.sessionVariables = {
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
    WLR_NO_HARDWARE_CURSORS = "1";

    # GPU-accelerated apps -- kitty, alacritty, LocalSend and anything else
    # built on GL -- die on startup here with
    #
    #   EGL: No EGLConfigs returned
    #   EGL: Failed to find a suitable EGLConfig
    #
    # even though the guest has swrast, virtio_gpu and a render node: qemu's
    # virgl path does not hand out a usable config. llvmpipe does, and with
    # this set the same launch produces no EGL errors at all.
    #
    # VM only. On a machine with a real GPU this would force every GL app
    # onto the CPU, which is exactly what you do not want.
    LIBGL_ALWAYS_SOFTWARE = "1";
  };

  # SSH, so the VM can be driven and inspected from the host. Debugging a
  # desktop that will not come up through screenshots alone is slow, and the
  # journal that explains it lives in a user session nobody can reach.
  #
  # VM-only settings: password auth with a known password, on a port forwarded
  # to localhost. Never copy this into a real host.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  virtualisation = {
    memorySize = 8192;
    cores = 4;
    diskSize = 16384;

    # ssh -p 2222 omarchy@localhost   (password: omarchy)
    forwardPorts = [
      {
        from = "host";
        host.port = 2222;
        guest.port = 22;
      }
    ];

    # Ephemeral root. `nix run .#vm` otherwise creates nixarchy-vm.qcow2 in
    # the working directory and REUSES it on every later run, which makes a
    # smoke test replay the previous run's state.
    #
    # That is not hypothetical: Omarchy persists every notification under
    # ~/.local/state/omarchy/notifications/history/ and its shell replays that
    # directory on start, so failures fixed in the package kept reappearing on
    # screen from a stale disk long after the fix landed.
    #
    # Set this to a path if you want a VM whose state survives, and remember
    # you then own clearing it.
    diskImage = null;
    # The display backend is deliberately NOT pinned here. Hardcoding
    # `-device virtio-vga-gl -display gtk,gl=on` makes the VM refuse to start
    # anywhere without a GL-capable display -- CI, a serial console, an ssh
    # session -- which is precisely where the journal needs reading when the
    # graphical session is the broken thing. Choose one at runtime instead:
    #
    #   headless:  QEMU_OPTS="-display none -serial mon:stdio" nix run .#vm
    #   with GL:   QEMU_OPTS="-device virtio-vga-gl -display gtk,gl=on" nix run .#vm
  };

  # A real flake on disk, so the whole pick -> Apply changes -> switch loop can
  # actually be exercised here rather than only on a physical host.
  #
  # nixarchy-apply copies the app selection into this directory and runs
  # `nixos-rebuild switch --flake` against it. Without somewhere real to copy
  # to, Apply changes can only ever print an error.
  #
  # The inputs are pinned by the same flake.lock this VM was built from, and
  # the nixarchy input is the store path that built it, so a rebuild resolves
  # everything already present and needs no network.
  #
  # programs.nixarchy.flake names this directory; host.nix sets it.
  #
  # Written by an activation script rather than environment.etc, because
  # environment.etc produces read-only symlinks into the store and
  # nixarchy-apply has to copy the app selection into this directory.
  system.activationScripts.nixarchyVmFlake = ''
    mkdir -p /etc/nixos

    # Regenerated every activation: it is scaffolding, not user content.
    cat > /etc/nixos/flake.nix <<'FLAKE'
    {
      inputs.nixarchy.url = "path:${inputs.self}";

      outputs =
        { self, nixarchy, ... }:
        {
          nixosConfigurations.nixarchy-vm = nixarchy.inputs.nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { inputs = nixarchy.inputs // { self = nixarchy; }; };
            modules = [
              nixarchy.nixosModules.nixarchy
              nixarchy.inputs.home-manager.nixosModules.home-manager
              "''${nixarchy}/vm/configuration.nix"
              ./nixarchy-apps.nix
            ];
          };
        };
    }
    FLAKE

    # nixarchy-apply overwrites this with the user's selection. It exists from
    # the start because an `imports` entry pointing at a missing file fails
    # evaluation -- the rebuild would break before the selection ever arrived.
    if [ ! -e /etc/nixos/nixarchy-apps.nix ]; then
      printf '{ ... }:\n{ }\n' > /etc/nixos/nixarchy-apps.nix
    fi

    # Owned by the user, because `nix flake update` runs unprivileged and a
    # root-owned flake makes it fail on the lock file:
    #
    #   error: opening file "/etc/nixos/flake.lock": Permission denied
    #
    # On a real host the flake usually lives in the user's home and is already
    # theirs; /etc/nixos being root-owned is what makes this VM the odd one.
    chown -R omarchy:users /etc/nixos
  '';

  # Passwordless sudo, so a rebuild driven from the menu does not stall on a
  # password prompt in a terminal that may not have focus. Acceptable only
  # because this VM is a throwaway; a real host should keep its prompt.
  security.sudo.wheelNeedsPassword = false;

  # Serial console keeps the journal readable from the host when the
  # graphical session is the thing that is broken.
  boot = {
    kernelParams = [ "console=ttyS0" ];

    # This VM boots through qemu's -kernel (virtualisation.useBootLoader is
    # false) onto a tmpfs root, so there is no disk for a bootloader to live on.
    # NixOS still enables GRUB by default, so `nixos-rebuild switch` inside the
    # VM built the whole system and then died on the very last step:
    #
    #   Failed to get blkid info (returned 512) for / on tmpfs
    #   Failed to install bootloader
    #
    # boot.loader.external satisfies the assertion that some bootloader is
    # configured while installing nothing, which is right here: the next boot
    # comes from the host's run script, not from this disk.
    # Both, for the same reason: host.nix configures systemd-boot because a
    # real machine needs one, and there is no disk here for either to install
    # onto. Left enabled they are two bootloaders and the assertion fires.
    loader = {
      grub.enable = lib.mkForce false;
      systemd-boot.enable = lib.mkForce false;
      external = {
        enable = true;
        installHook = lib.getExe (
          pkgs.writeShellScriptBin "nixarchy-vm-no-bootloader" ''
            echo "nixarchy VM: no bootloader to install (tmpfs root, booted via -kernel)"
          ''
        );
      };
    };
  };

  # The whole point of this VM is diagnosing a session that will not come up,
  # and the interesting logs are in a user journal nobody can reach without
  # logging in. Push them to the serial console instead.
  #
  # omarchy-launch-shell pipes QuickShell through `systemd-cat -t
  # omarchy-shell`, supervises it, and gives up after 5 relaunches inside a
  # minute -- so "the panel shows for a few seconds then dies" leaves its
  # reason here and nowhere else.
  systemd.services.nixarchy-debug-journal = {
    description = "Stream the Omarchy session journal to the serial port";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      # Written straight to the serial PORT, not to "console". Once a GPU
      # device is present the kernel makes tty0 the console and anything sent
      # there never reaches -serial, which is why two earlier attempts to read
      # this over a serial line came back with a login prompt and nothing else.
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/ttyS0";
      Restart = "always";
      RestartSec = 5;
    };
    script = ''
      echo "[nixarchy] streaming omarchy-shell + session journal"
      # omarchy-launch-shell pipes QuickShell through `systemd-cat -t
      # omarchy-shell` and gives up after 5 relaunches inside a minute, so a
      # panel that appears and then vanishes explains itself here.
      exec journalctl -f -b --no-pager -t omarchy-shell -t Hyprland -t uwsm \
        _UID=1000 --output=short-monotonic
    '';
  };

  networking.firewall.enable = lib.mkForce false;

  environment.systemPackages = [ pkgs.kitty ];
}
