# The `hyprland` template: a Wayland compositor in a disposable VM, for the
# callers that automate a desktop -- capture with `grim`, read it with
# `tesseract`, type into it with `wtype`. Plain NixOS, like every other
# template here: no omarchy shell, no bar, no plugins. #821.
#
# Why: modules/microvm/AGENTS.md -- in short, every one of the four settings
# below is load-bearing, and dropping any of them produces the SAME Hyprland
# message, `CBackend::create() failed!`, which names none of them. That string
# is thrown from two different call sites in Compositor.cpp and stood for three
# unrelated causes while this template was being written. The real reason is
# always the CRIT line above it in Hyprland's own log.
{ pkgs, ... }:
{
  environment = {
    systemPackages = with pkgs; [
      hyprland
      grim # capture; nixarchy-voice pipes `grim -t ppm` into tesseract
      tesseract
      wtype
      wl-clipboard
      foot # something to open, and the smallest thing that proves a window works

      # Chromium, forced to expose its render tree and to run on Wayland: without
      # `--ozone-platform=wayland` it tries X11, and this guest has no Xwayland
      # (#1509). Chromium builds the AT-SPI tree lazily and a headless guest
      # gives it nothing to react to, so an
      # unwrapped one answers an a11y query with an empty tree and no error --
      # the same zero-element failure the session variables above were measured
      # against, one layer up. `commandLineArgs` is nixpkgs' own argument; it
      # ends up as `--add-flags` on chromium's existing wrapper, so there is no
      # second wrapper here to keep in step.
      #
      # This is the opinionated part of the template and the `note` in
      # data/microvm-templates.nix says so: somebody expecting stock Chromium
      # should not have to discover the flag by reading this file. An Electron
      # application added by a caller needs the same flag passed itself --
      # Electron is a runtime bundled per application, not a package here to
      # wrap.
      (chromium.override { commandLineArgs = "--force-renderer-accessibility --ozone-platform=wayland"; })
    ];

    # The other two thirds of the accessibility story; the third,
    # services.gnome.at-spi2-core, is below with the reasoning for all three.
    # They are split because statix wants one `environment` key, not because
    # they are separable -- none of the three works without the other two.
    sessionVariables = {
      QT_ACCESSIBILITY = "1";
      GTK_MODULES = "gail:atk-bridge";
    };
    etc."hypr/hyprland.lua".text = ''
      -- Name the connector: a catch-all rule does not match Virtual-1 ("Red Hat,
      -- Inc. QEMU Monitor"), so Hyprland warns "No rule found for Virtual-1" and
      -- picks its own size, silently changing every OCR measurement.
      hl.monitor({ output = "Virtual-1", mode = "1920x1080@60", position = "0x0", scale = 1 })

      -- Hyprland disables stdout logs by default and writes to a tmpfs file that
      -- dies with the VM. Under a systemd user service stdout is the journal, so
      -- this makes `journalctl --user -u hyprland` say why a dead compositor died.
      hl.config({
        misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
        debug = { disable_logs = false, enable_stdout_logs = true },
      })
    '';
  };

  # A GPU for the guest, and no GL on the host. The guest needs a DRM device for
  # aquamarine/GBM, but nothing behind it. The host-GL path
  # (`graphics.backend = "headless"`: `-display egl-headless -device
  # virtio-gpu-gl`) crashed qemu in radeonsi on every exit on p620, and each
  # crash raised a notification (#1506). `graphics.enable` stays at microvm.nix's
  # default `false`, which is `-nographic`: no host window, and the serial
  # console on stdio. So the device is added by hand. The guest renders in
  # software, so GL-heavy apps under test are slow.
  microvm = {
    qemu.extraArgs = [
      "-device"
      "virtio-gpu-pci"
    ];

    # microvm.nix's own default is 512 and modules/microvm/guest.nix does not
    # raise it, so a template that wants more says so itself. A compositor plus a
    # browser under test wants more than python.nix's 3072.
    mem = 4096;
  };

  # Without this nothing can OPEN the DRM device, and aquamarine reports it as
  # "drm: Skipping device ..., not a KMS device" -- which is misleading:
  # supportsKMS() returns early on `deviceID < 0` and never calls drmIsKMS.
  # The guest's session is Type=tty with an empty Seat, so logind's libseat
  # backend declines it; seatd runs as root, holds the VT, and makes the seat
  # question irrelevant. It is also what lets a lingering user manager -- which
  # has no session at all -- run the compositor.
  services.seatd.enable = true;

  # Without this the device opens and `gbm_create_device` fails: GBM is
  # aquamarine's only allocator and it needs a mesa driver, which a NixOS guest
  # has none of under /run/opengl-driver until this option provides one.
  # There is no virgl behind the device, so Mesa renders in software on the
  # virtio_gpu KMS device.
  hardware.graphics.enable = true;

  users.users.dev = {
    # video and render to open the DRM nodes; seat to talk to seatd.
    extraGroups = [
      "video"
      "render"
      "seat"
    ];

    # So the compositor comes up whether or not anyone is attached to the
    # console. Without it the user manager starts only because guest.nix
    # autologins on ttyS0, which makes a background VM depend on a login
    # nobody performs.
    linger = true;
  };

  # Accessibility, on: this and the two session variables above. Measured on
  # p620 while scoping #821: without all three an
  # AT-SPI tree exposes ZERO actionable elements in every application, so a
  # caller testing window targeting gets an empty tree and no error -- the
  # failure looks like the tool rather than the guest. at-spi2-core is what
  # makes org.a11y.Bus activatable at all; #823 found the same thing one layer
  # down, where the bus answered "not activatable" and nothing AT-SPI was
  # observable in any guest.
  services.gnome.at-spi2-core.enable = true;

  systemd.user.services.hyprland = {
    description = "Hyprland compositor";
    wantedBy = [ "default.target" ];

    # systemd.user units are generated for every user's manager, including
    # root's. ConditionUser is how this tree already scopes one to a single
    # user (the rootless Docker unit does the same).
    unitConfig.ConditionUser = "dev";

    serviceConfig = {
      # --path: start-hyprland finds Hyprland on PATH, which a user unit lacks;
      # without it, it fails execvp and still exits 0 (measured live, #1510).
      ExecStart = "${pkgs.hyprland}/bin/start-hyprland --path ${pkgs.hyprland}/bin/Hyprland -- --config /etc/hypr/hyprland.lua";

      # The unit itself does not restart; start-hyprland (#1510) restarts a
      # compositor that exits uncleanly, possibly in --safe-mode, which drops
      # the monitor rule. And it exits 0 even when Hyprland failed, so the unit
      # reads `inactive (dead)`, never `failed`: a dead or restarted compositor
      # shows only in `journalctl --user -u hyprland` and as a wrong output size.
      Restart = "no";
    };
  };
}
