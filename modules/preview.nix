{ config, lib, ... }:
{
  # What `nixos-rebuild build-vm` needs so a nixarchy desktop actually
  # renders in the preview VM, instead of a black screen. #487, child of
  # #485 -- `nixarchy-preview` runs the resulting VM.
  #
  # `virtualisation.vmVariant` is this configuration re-evaluated with
  # qemu-vm.nix layered on, so everything set below reaches ONLY the VM;
  # the host these defaults would be wrong for never sees them.
  config = lib.mkIf config.programs.nixarchy.enable {
    virtualisation.vmVariant = {
      # Software rendering. qemu's virgl path hands out no usable EGLConfig
      # -- "EGL: No EGLConfigs returned" -- so without these, wlroots
      # refuses to start and every GL app dies on launch. Diagnosed for the
      # smoke VM in vm/configuration.nix:67-86; a user's config booted
      # verbatim has none of them and shows a black screen.
      #
      # VM-only by construction, which matters for LIBGL_ALWAYS_SOFTWARE:
      # on a machine with a real GPU it would force every GL app onto the
      # CPU. mkDefault throughout, so a vmVariant of the user's own wins.
      environment.sessionVariables = {
        WLR_RENDERER_ALLOW_SOFTWARE = lib.mkDefault "1";
        WLR_NO_HARDWARE_CURSORS = lib.mkDefault "1";
        LIBGL_ALWAYS_SOFTWARE = lib.mkDefault "1";
      };

      virtualisation = {
        # qemu-vm.nix's defaults are 1024 MB and one core, which a
        # software-rendered Hyprland session cannot live on. 8192/4 is the
        # house standard for a desktop guest (vm/configuration.nix:102-104);
        # 4096 is the stated floor.
        memorySize = lib.mkDefault 8192;
        cores = lib.mkDefault 4;

        # ssh -p 2223 <user>@localhost, IF the previewed config runs sshd --
        # nothing here enables it, because the preview should show the user's
        # config, not a doctored one. A list, so a plain assignment that
        # merges with the user's own forwards (modules/services/default.nix
        # header: mkDefault on a merging type drops the whole contribution the
        # moment they add an element).
        #
        # 2223, and the number is not free choice. qemu cannot bind a host
        # port twice, so a forward that collides fails the SECOND VM to start
        # -- with an error about binding, not about ports being a shared
        # resource. Every guest this repository can run, in one place, because
        # the next person adding one will look for exactly this list:
        #
        #   2222  vm/configuration.nix   `nix run .#vm`, the smoke VM
        #   2223  here                   a user previewing their own config
        #   2224  flake.nix              `nix run .#vm-big`
        #   set   modules/services/microvm.nix  per machine, `sshPort`
        #
        # The collision this avoids is specifically a nixarchy DEVELOPER's:
        # a user previewing their own machine has no smoke VM running. It is
        # still worth avoiding, because the person who hits it is whoever is
        # working on this feature.
        forwardPorts = [
          {
            from = "host";
            host.port = 2223;
            guest.port = 22;
          }
        ];

        # The display backend is deliberately NOT pinned here. Hardcoding
        # `-device virtio-vga-gl -display gtk,gl=on` makes the VM refuse to
        # start anywhere without a GL-capable display; leave it to
        # QEMU_OPTS at runtime -- vm/configuration.nix:128-135.
      };
    };
  };
}
