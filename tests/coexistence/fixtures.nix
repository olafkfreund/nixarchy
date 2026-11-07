# Plain NixOS modules a user might carry alongside nixarchy, some with a
# programs.nixarchy.* of their own. checks.coexistence (tests/coexistence/
# default.nix) runs nixarchy's reference config through each and checks it
# still works, per AGENTS.md#14. See #1162 -> #1163 for the worked example of
# what a coexistence bug looks like without one of these.
{
  # The commonest pattern: add a package to the merged graphics-drivers env.
  # Use nixarchy's selected package: its Mesa follows Hyprland's own nixpkgs,
  # not necessarily this configuration's pkgs.mesa.
  graphics-own-mesa =
    { config, ... }:
    {
      hardware.graphics.extraPackages = [ config.hardware.graphics.package ];
    };

  # p620's original pattern: 32-bit drivers added the same way.
  graphics-32bit =
    { config, ... }:
    {
      hardware.graphics.enable32Bit = true;
      hardware.graphics.extraPackages32 = [ config.hardware.graphics.package32 ];
    };

  # The documented escape hatch from #1163: replace nixarchy's package
  # outright rather than add beside it.
  graphics-own-package =
    { pkgs, ... }:
    {
      hardware.graphics.package = pkgs.mesa;
    };

  # Rusticl: mesa.opencl shares pname "mesa" with the main output but ships
  # no egl_vendor.d file, so it must not collide (#1165's review).
  graphics-opencl =
    { pkgs, ... }:
    {
      hardware.graphics.extraPackages = [ pkgs.mesa.opencl ];
    };

  # nixarchy adds ffmpeg to environment.systemPackages via the omarchy
  # package's runtimeDeps (pkgs/omarchy/default.nix). A user who installs
  # ffmpeg-full of their own must get THEIR bin/ffmpeg, not nixarchy's.
  systempkg-own-ffmpeg =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.ffmpeg-full ];
    };

  # A person's own mise and a file at the path nixarchy used to own (#1625).
  mise-own =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (pkgs.mise.overrideAttrs (o: {
          pname = o.pname + "-coexist";
        }))
      ];
      environment.etc."mise/conf.d/omarchy.toml".text = "# theirs\n";
    };

  systempkg-own-vi =
    { pkgs, ... }:
    {
      environment.systemPackages = [ (pkgs.writeShellScriptBin "vi" "echo own-vi-marker") ];
    };

  neovim-vialias = {
    programs.neovim = {
      enable = true;
      viAlias = true;
    };
  };

  # #1612: a machine that already opted out of an app Omarchy 4.5 retired.
  preinstalls-exclude-retired = {
    programs.nixarchy.preinstallsExclude = [
      "obs-studio"
      "kdenlive"
      "xournalpp"
    ];
  };

  # #1612: the seven default apps are unasked, so a user's own binary wins.
  systempkg-own-hype =
    { pkgs, ... }:
    {
      environment.systemPackages = [ (pkgs.writeShellScriptBin "hype" "echo own-hype-marker") ];
    };

  # #1612: a user's own PDF handler wins over nixarchy's default.
  xdg-mime-own-pdf = {
    xdg.mime.defaultApplications."application/pdf" = "own.desktop";
  };

  # #1613: a person's own portable Superwhisper on PATH, the app off. Nixarchy
  # adds no package, no unit, and no second copy of the name.
  superwhisper-own-copy =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "superwhisper" "echo own-superwhisper-marker")
      ];
    };

  # #1613: their own ALT + SPACE, in the hypr file they own. Nothing of
  # nixarchy's may bind that key beside it.
  superwhisper-own-alt-space = {
    home-manager.users.omarchy.xdg.configFile."hypr/bindings.lua".text = ''
      o.bind("ALT + SPACE", "Their launcher", "own-launcher")
    '';
  };

  # #1613: dictation.enable keeps Voxtype whatever a seeded selection file says,
  # and the file is theirs: nixarchy does not manage it.
  superwhisper-dictation-selection = {
    programs.nixarchy.dictation.enable = true;
  };

  superwhisper-unfree-off = {
    programs.nixarchy.allowUnfree = false;
  };

  superwhisper-forced-on = {
    programs.nixarchy.allowUnfree = true;
    programs.nixarchy.apps.superwhisper.enable = true;
  };

  # #1613: their own association for the vendor's sign-in scheme.
  superwhisper-own-scheme = {
    xdg.mime.defaultApplications."x-scheme-handler/superwhisper" = "own-superwhisper.desktop";
  };

  # A user who swaps Hyprland (their own pin, a patched build). The titlebars
  # plugin loads into the session's compositor, so it must be built against
  # THAT one, not the flake's input (#1572). Only the pname changes, so the
  # package is distinguishable without a rebuild.
  hyprland-own-package =
    { lib, pkgs, ... }:
    {
      # mkForce: the reference config sets it plainly, as a user's flake would.
      programs.hyprland.package = lib.mkForce (
        pkgs.hyprland.overrideAttrs (o: {
          pname = o.pname + "-coexist";
        })
      );
    };

  # A user's own connectivity check, or none: nixarchy's is mkDefault (#1428).
  nm-connectivity-own = {
    networking.networkmanager.settings.connectivity = {
      uri = "http://example.invalid/check";
      enabled = false;
    };
  };

  # A user's own programs.chromium writes policies/managed/extra.json;
  # nixarchy's policy is omarchy.json beside it, not the same file (#1491).
  chromium-own-policy = {
    programs.chromium = {
      enable = true;
      extraOpts.BookmarkBarEnabled = true;
    };
  };

  # Omarchy's local model runner on a machine whose owner already runs podman
  # their way (#1577). agent-local only mkDefaults podman on, so their
  # dockerCompat must stand and nothing may assert.
  podman-own-config =
    { lib, ... }:
    {
      programs.nixarchy.user = lib.mkDefault "omarchy";
      programs.nixarchy.services.agent-local.enable = true;
      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
      };
    };

  # The same service on an NVIDIA machine whose owner turned the container
  # toolkit off: theirs wins over agent-local's mkDefault (#1577).
  nvidia-ctk-own =
    { lib, ... }:
    {
      programs.nixarchy.user = lib.mkDefault "omarchy";
      programs.nixarchy.services.agent-local.enable = true;
      services.xserver.videoDrivers = [ "nvidia" ];
      # nixpkgs' NVIDIA module asserts this is chosen, as a real machine does.
      hardware.nvidia.open = true;
      hardware.nvidia-container-toolkit.enable = false;
    };

  # A user who chooses IBus outright (#1614): no fcitx5 addons or unit.
  input-own-ibus = {
    i18n.inputMethod.type = "ibus";
  };

  # Another module (e.g. GNOME) setting IBus at mkDefault beats nixarchy's
  # mkOverride 1250 (#1614).
  input-default-ibus =
    { lib, ... }:
    {
      i18n.inputMethod.type = lib.mkDefault "ibus";
    };

  # Input methods turned off outright (#1614): no fcitx5 addons or unit.
  input-disabled = {
    i18n.inputMethod.enable = false;
  };

  # An extra fcitx5 addon merges with nixarchy's five (#1614).
  input-own-addon =
    { pkgs, ... }:
    {
      i18n.inputMethod.fcitx5.addons = [ pkgs.fcitx5-rime ];
    };

  # Shedding nixarchy's default addons with mkForce (#1614).
  input-no-addons =
    { lib, ... }:
    {
      i18n.inputMethod.fcitx5.addons = lib.mkForce [ ];
    };

  # Declarative fcitx5 profile settings skip the ExecStartPre alignment (#1614).
  input-own-profile = {
    i18n.inputMethod.fcitx5.settings.inputMethod = {
      GroupOrder."0" = "Default";
    };
  };

  # The owner's razer (modules/common/networking.nix there): mkDefault on four,
  # plain on one. Its values equal ours, so this proves it evaluates, not who won.
  sysctl-razer =
    { lib, ... }:
    {
      boot.kernel.sysctl = {
        "net.core.default_qdisc" = lib.mkDefault "fq";
        "net.ipv4.tcp_congestion_control" = lib.mkDefault "bbr";
        "net.ipv4.tcp_notsent_lowat" = lib.mkDefault 16384;
        "net.ipv4.tcp_mtu_probing" = 1;
        "net.ipv4.tcp_fastopen" = lib.mkDefault 3;
      };
    };

  # A user's own mkDefault with different values: only this sees who won.
  sysctl-own-mkdefault =
    { lib, ... }:
    {
      boot.kernel.sysctl = {
        "net.core.default_qdisc" = lib.mkDefault "fq_codel";
        "net.ipv4.tcp_congestion_control" = lib.mkDefault "cubic";
        "vm.swappiness" = lib.mkDefault 10;
      };
    };

  # The advice in pkgs/omarchy/skills/nixos-performance/SKILL.md.
  sysctl-own-plain = {
    boot.kernel.sysctl = {
      "net.core.default_qdisc" = "cake";
      "net.ipv4.tcp_congestion_control" = "cubic";
    };
  };

  openssh-on-reference =
    { lib, ... }:
    {
      programs.nixarchy.user = lib.mkDefault "omarchy";
      programs.nixarchy.services.openssh.enable = true;
    };

  openssh-own-passwords =
    { lib, ... }:
    {
      programs.nixarchy.user = lib.mkDefault "omarchy";
      programs.nixarchy.services.openssh.enable = true;
      services.openssh.settings.PasswordAuthentication = true;
    };

  openssh-own-null =
    { lib, ... }:
    {
      programs.nixarchy.user = lib.mkDefault "omarchy";
      programs.nixarchy.services.openssh.enable = true;
      services.openssh.settings.PasswordAuthentication = null;
    };

  openssh-own-mkdefault =
    { lib, ... }:
    {
      programs.nixarchy.user = lib.mkDefault "omarchy";
      programs.nixarchy.services.openssh.enable = true;
      services.openssh.settings.PasswordAuthentication = lib.mkDefault true;
    };

  openssh-plain-line =
    { lib, ... }:
    {
      programs.nixarchy.user = lib.mkDefault "omarchy";
      services.openssh.enable = true;
    };

  keyboard-own-xkb = {
    services.xserver.xkb.layout = "fr";
  };

  keyboard-own-options = {
    services.xserver.xkb = {
      layout = "us,ru";
      options = "grp:caps_toggle";
    };
  };

  keyboard-own-vconsole =
    { lib, ... }:
    {
      services.xserver.xkb.layout = "de";
      environment.etc."vconsole.conf".text = lib.mkForce "KEYMAP=own\n";
    };

  keyboard-xkb-console = {
    console.useXkbConfig = true;
    services.xserver.xkb.layout = "de";
  };

  keyboard-imperative = {
    i18n.imperativeLocale = true;
    services.xserver.xkb.layout = "de";
  };

  keyboard-kwin-greeter = {
    services.displayManager.sddm.wayland.compositor = "kwin";
    services.xserver.xkb.layout = "de";
  };
}
