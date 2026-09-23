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
  environment.systemPackages = with pkgs; [
    hyprland
    grim # capture; nixarchy-voice pipes `grim -t ppm` into tesseract
    tesseract
    wtype
    wl-clipboard
    foot # something to open, and the smallest thing that proves a window works
  ];

  # A GPU, and no window on the host. `enable` alone is not enough: the backend
  # enum defaults to `gtk` on Linux, which opens a GTK window on the host's
  # desktop and defeats a VM meant to run unattended. `headless` is
  # `-display egl-headless -device virtio-gpu-gl` (microvm.nix
  # lib/runners/qemu.nix), which upstream documents as the value that exists so
  # a VM can run under a systemd job.
  microvm.graphics.enable = true;
  microvm.graphics.backend = "headless";

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
  # mesa ships virtio_gpu_dri.so, which is the driver this device wants.
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

  # microvm.nix's own default is 512 and modules/microvm/guest.nix does not
  # raise it, so a template that wants more says so itself. A compositor plus a
  # browser under test wants more than python.nix's 3072.
  # Accessibility, on. Measured on p620 while scoping #821: without these an
  # AT-SPI tree exposes ZERO actionable elements in every application, so a
  # caller testing window targeting gets an empty tree and no error -- the
  # failure looks like the tool rather than the guest. at-spi2-core is what
  # makes org.a11y.Bus activatable at all; #823 found the same thing one layer
  # down, where the bus answered "not activatable" and nothing AT-SPI was
  # observable in any guest.
  services.gnome.at-spi2-core.enable = true;
  environment.sessionVariables = {
    QT_ACCESSIBILITY = "1";
    GTK_MODULES = "gail:atk-bridge";
  };

  microvm.mem = 4096;

  environment.etc."hypr/hyprland.conf".text = ''
    # Name the connector. A catch-all `monitor = ,` does not match it -- the
    # guest's output is Virtual-1 ("Red Hat, Inc. QEMU Monitor"), and Hyprland
    # warns "No rule found for Virtual-1" and picks its own size, which
    # silently changes every OCR measurement taken against this VM.
    monitor = Virtual-1, 1920x1080@60, 0x0, 1

    misc {
      disable_hyprland_logo = true
      disable_splash_rendering = true
    }

    # Hyprland disables stdout logs by default and writes to a file in a tmpfs
    # that dies with the VM. Under a systemd user service stdout is the
    # journal, so this is what makes `journalctl --user -u hyprland` say why a
    # dead compositor died -- the one question a caller will actually ask.
    debug {
      disable_logs = false
      enable_stdout_logs = true
    }
  '';

  systemd.user.services.hyprland = {
    description = "Hyprland compositor";
    wantedBy = [ "default.target" ];

    # systemd.user units are generated for every user's manager, including
    # root's. ConditionUser is how this tree already scopes one to a single
    # user (the rootless Docker unit does the same).
    unitConfig.ConditionUser = "dev";

    serviceConfig = {
      ExecStart = "${pkgs.hyprland}/bin/Hyprland --config /etc/hypr/hyprland.conf";

      # Deliberately not Restart=always. A compositor that flaps looks exactly
      # like one that works until a capture comes back empty; a failure that
      # stays failed is discoverable with `systemctl --user status hyprland`.
      Restart = "no";
    };
  };
}
