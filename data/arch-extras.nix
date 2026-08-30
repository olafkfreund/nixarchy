# Arch package names that reach omarchy-pkg-add without being apps.
#
# data/apps.nix already maps every Install-menu row that names a package, and
# CI holds it to that. These are the ones nothing in the menu selects: fonts
# picked from Style > Font, and the system packages omarchy-install-dev-env
# adds behind a language. They end up at the same `omarchy-pkg-add`, where the
# only thing that helps is being told what the package is called here.
#
# `kind` decides which option the advice names, because they are not
# interchangeable: a font in environment.systemPackages is installed and still
# not found by fontconfig.
#
# `binary` is optional and only needed when the command a package provides is
# not its own name -- openssh provides sshd, not openssh. omarchy-pkg-add uses
# it to tell "already installed" from "missing"; without it a package whose
# name is not a command can never be found, and the caller aborts before the
# configuration it was about to do. See #41.
{
  # ── Style > Font ────────────────────────────────────────────────────────
  # Each row also calls omarchy-font-set with the family name, which works
  # once the font is installed -- see nix-bin/omarchy-install-font.
  ttf-cascadia-mono-nerd = {
    attr = "nerd-fonts.caskaydia-mono";
    kind = "font";
  };
  ttf-meslo-nerd = {
    attr = "nerd-fonts.meslo-lg";
    kind = "font";
  };
  ttf-firacode-nerd = {
    attr = "nerd-fonts.fira-code";
    kind = "font";
  };
  ttf-victor-mono-nerd = {
    attr = "nerd-fonts.victor-mono";
    kind = "font";
  };
  ttf-bitstream-vera-mono-nerd = {
    attr = "nerd-fonts.bitstream-vera-sans-mono";
    kind = "font";
  };
  ttf-iosevka-nerd = {
    attr = "nerd-fonts.iosevka";
    kind = "font";
  };

  # ── omarchy-install-dev-env ─────────────────────────────────────────────
  # php and symfony-cli are apps already, so they are not repeated here.
  # omarchy-audio-tuning wants the LSP limiter, and install/hardware's
  # speaker-tuning.sh reaches for it by Arch name. Not a runtime dependency
  # here: its closure is over 500MB, which is a lot to hand everyone for a
  # feature that matters on some laptops. Mapped so the advice is right for
  # anyone who does want it.
  lsp-plugins-lv2 = {
    attr = "lsp-plugins";
    kind = "package";
  };
  composer = {
    attr = "php.packages.composer";
    kind = "package";
  };
  libyaml = {
    attr = "libyaml";
    kind = "package";
  };
  rlwrap = {
    attr = "rlwrap";
    kind = "package";
  };

  # PHP extensions are not packages you add beside PHP on NixOS; they are
  # built into the interpreter, so naming environment.systemPackages here
  # would send someone looking for something that does not exist.
  php-sqlite = {
    attr = "php.withExtensions (e: e.enabled ++ [ e.all.pdo_sqlite ])";
    kind = "php-extension";
  };
  xdebug = {
    attr = "php.withExtensions (e: e.enabled ++ [ e.all.xdebug ])";
    kind = "php-extension";
  };

  # ── Install > Gaming ────────────────────────────────────────────────────
  # Battle.net runs a Windows installer under umu-launcher. The launcher is
  # packaged; the rest of that script is wine prefixes under $HOME and works
  # unchanged.
  umu-launcher = {
    attr = "umu-launcher";
    kind = "package";
  };

  # omarchy-install-gaming-gpu-lib32 adds the 32-bit halves of whichever
  # driver it detects. NixOS does not install those as packages -- one option
  # turns the 32-bit graphics stack on for every driver at once.
  lib32-nvidia-utils = {
    attr = "hardware.graphics.enable32Bit = true";
    kind = "nixos-option";
  };
  lib32-vulkan-intel = {
    attr = "hardware.graphics.enable32Bit = true";
    kind = "nixos-option";
  };
  lib32-vulkan-radeon = {
    attr = "hardware.graphics.enable32Bit = true";
    kind = "nixos-option";
  };

  # GeForce NOW ships as a Flatpak. Flatpak on NixOS is a service, not just a
  # package: without the service there is no system-wide installation for it
  # to land in.
  flatpak = {
    attr = "services.flatpak.enable = true";
    kind = "nixos-option";
    note = "then: flatpak install flathub com.nvidia.geforcenow";
  };

  # omarchy-setup-security-sshd opens with `omarchy-pkg-add openssh`, then
  # configures sshd. On NixOS installing the package is not what starts the
  # daemon, so the package advice would have been wrong even if it had been
  # given -- and `binary` is what lets the guard see an already-running sshd.
  openssh = {
    attr = "services.openssh.enable = true";
    kind = "nixos-option";
    binary = "sshd";
  };

  # ── Install > AI ────────────────────────────────────────────────────────
  # The row picks ollama-cuda or ollama-rocm from what it detects; nixpkgs
  # splits the same way.
  ollama = {
    attr = "ollama";
    kind = "package";
    note = "ollama-cuda and ollama-rocm exist too, for NVIDIA and AMD.";
  };
}
