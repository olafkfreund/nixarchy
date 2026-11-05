# Every Arch package name Omarchy's install lists name, and what this port does
# about it.
#
# Omarchy installs from install/*.packages. A name added there upstream is a
# decision for this port: ship it, let a NixOS option provide it, or leave it
# out knowingly. #1572 found Omarchy 4.5 adding Hype, Monologue, Signed,
# Disktree and the titlebars plugin, and nothing here saying so -- the delta
# script only reports a name changing, and nobody had decided about the new ones.
#
# ## The rule
#
# Each row is a decision. It has exactly ONE of:
#
#   nix     the attribute path in pkgs (with the nixarchy overlay) that
#           provides it, and nixarchy ships it: a runtime dependency, a
#           systemPackages entry, a font, or an app behind
#           programs.nixarchy.omarchyApps.enable.
#   module  the NixOS option that provides it, which modules/*.nix sets.
#   skip    a one-line reason it is knowingly absent. When unsure, say so here:
#           an honest skip is reviewed, a guess is trusted.
#
# tests/omarchy-package-ledger.nix fails in three ways and names every offender
# in one pass: a name in the lists with no row (unclassified), a row for a name
# no list has any more (stale), and a `nix` attribute that does not evaluate
# (unresolvable). It does NOT check that a `module` option is set; that is
# read by hand against modules/*.nix.
{

  # ── Shipped as a package ──────────────────────────────────────────────────
  "aether" = {
    nix = "nixarchy-apps.aether";
  };
  "alsa-utils" = {
    nix = "alsa-utils";
  };
  "bat" = {
    nix = "bat";
  };
  "bluez-tools" = {
    nix = "bluez-tools";
  };
  "brightnessctl" = {
    nix = "brightnessctl";
  };
  "btop" = {
    nix = "btop";
  };
  "btrfs-progs" = {
    nix = "btrfs-progs";
  };
  "chromium" = {
    nix = "chromium";
  };
  "cliamp" = {
    nix = "cliamp";
  };
  "cups-pk-helper" = {
    nix = "cups-pk-helper";
  };
  "ddcutil" = {
    nix = "ddcutil";
  };
  "disktree-bin" = {
    nix = "disktree";
  };
  "dosfstools" = {
    nix = "dosfstools";
  };
  "evince" = {
    nix = "evince";
  };
  "eza" = {
    nix = "eza";
  };
  "fastfetch" = {
    nix = "fastfetch";
  };
  "fd" = {
    nix = "fd";
  };
  "ffmpeg" = {
    nix = "ffmpeg";
  };
  "ffmpegthumbnailer" = {
    nix = "ffmpegthumbnailer";
  };
  "fontconfig" = {
    nix = "fontconfig";
  };
  "foot" = {
    nix = "foot";
  };
  "fzf" = {
    nix = "fzf";
  };
  "git" = {
    nix = "git";
  };
  "gliff" = {
    nix = "gliff";
  };
  "gnome-disk-utility" = {
    nix = "gnome-disk-utility";
  };
  "gnome-keyring" = {
    nix = "gnome-keyring";
  };
  "gnome-themes-extra" = {
    nix = "gnome-themes-extra";
  };
  "gpu-screen-recorder" = {
    nix = "gpu-screen-recorder";
  };
  "grim" = {
    nix = "grim";
  };
  "gum" = {
    nix = "gum";
  };
  "hype" = {
    nix = "nixarchy-apps.hype";
  };
  "hyprland-guiutils" = {
    nix = "hyprland-guiutils";
  };
  "hyprland-preview-share-picker" = {
    nix = "hyprland-preview-share-picker";
  };
  "hyprpicker" = {
    nix = "hyprpicker";
  };
  "hyprsunset" = {
    nix = "hyprsunset";
  };
  "imagemagick" = {
    nix = "imagemagick";
  };
  "imv" = {
    nix = "imv";
  };
  "inotify-tools" = {
    nix = "inotify-tools";
  };
  "inxi" = {
    nix = "inxi";
  };
  "jq" = {
    nix = "jq";
  };
  "lazygit" = {
    nix = "lazygit";
  };
  "less" = {
    nix = "less";
  };
  "libpulse" = {
    nix = "pulseaudio";
  };
  "libreoffice-fresh" = {
    nix = "libreoffice";
  };
  "libvips" = {
    nix = "vips";
  };
  "libyaml" = {
    nix = "libyaml";
  };
  "localsend" = {
    nix = "localsend";
  };
  "man-db" = {
    nix = "man-db";
  };
  "mise-bin" = {
    nix = "mise";
  };
  "monologue" = {
    nix = "nixarchy-apps.monologue";
  };
  "moonlight-qt" = {
    nix = "moonlight-qt";
  };
  "mpv" = {
    nix = "mpv";
  };
  "nautilus" = {
    nix = "nautilus";
  };
  "noto-fonts" = {
    nix = "noto-fonts";
  };
  "noto-fonts-cjk" = {
    nix = "noto-fonts-cjk-sans";
  };
  "noto-fonts-emoji" = {
    nix = "noto-fonts-color-emoji";
  };
  "nvim" = {
    nix = "neovim";
  };
  "obsidian" = {
    nix = "obsidian";
  };
  "omacalc" = {
    nix = "nixarchy-apps.omacalc";
  };
  "omacut" = {
    nix = "nixarchy-apps.omacut";
  };
  "omarchy-hyprland-titlebars" = {
    nix = "nixarchy-apps.omarchy-hyprland-titlebars";
  };
  "omarchy-nvim" = {
    nix = "omarchy-nvim-config";
  };
  "omasnap" = {
    nix = "nixarchy-apps.omasnap";
  };
  "omawrite" = {
    nix = "nixarchy-apps.omawrite";
  };
  "owe" = {
    nix = "nixarchy-apps.owe";
  };
  "pamixer" = {
    nix = "pamixer";
  };
  "pciutils" = {
    nix = "pciutils";
  };
  "pinta" = {
    nix = "pinta";
  };
  "qrencode" = {
    nix = "qrencode";
  };
  "quickshell" = {
    nix = "quickshell";
  };
  "ripgrep" = {
    nix = "ripgrep";
  };
  "signed" = {
    nix = "nixarchy-apps.signed";
  };
  "slurp" = {
    nix = "slurp";
  };
  "snapper" = {
    nix = "snapper";
  };
  "socat" = {
    nix = "socat";
  };
  "starship" = {
    nix = "starship";
  };
  "sushi" = {
    nix = "sushi";
  };
  "tesseract" = {
    nix = "tesseract";
  };
  "tldr" = {
    nix = "tldr";
  };
  "tmux" = {
    nix = "tmux";
  };
  "tree-sitter-cli" = {
    nix = "tree-sitter";
  };
  "ttf-jetbrains-mono-nerd-basic" = {
    nix = "nerd-fonts.jetbrains-mono";
  };
  "ttfx" = {
    nix = "nixarchy-apps.ttfx";
  };
  "udiskie" = {
    nix = "udiskie";
  };
  "unzip" = {
    nix = "unzip";
  };
  "uwsm" = {
    nix = "uwsm";
  };
  "wl-clipboard" = {
    nix = "wl-clipboard";
  };
  "woff2-font-awesome" = {
    nix = "font-awesome";
  };
  "wtype" = {
    nix = "wtype";
  };
  "xdg-desktop-portal-gtk" = {
    nix = "xdg-desktop-portal-gtk";
  };
  "xdg-desktop-portal-hyprland" = {
    nix = "xdg-desktop-portal-hyprland";
  };
  "xdg-terminal-exec" = {
    nix = "xdg-terminal-exec";
  };
  "yaru-icon-theme" = {
    nix = "yaru-theme";
  };
  "yt-dlp" = {
    nix = "yt-dlp";
  };
  "zbar" = {
    nix = "zbar";
  };
  "zoxide" = {
    nix = "zoxide";
  };

  # ── Provided by a NixOS option the module sets ────────────────────────────
  "avahi" = {
    module = "services.avahi.enable";
  };
  "bash-completion" = {
    module = "programs.bash.completion.enable";
  };
  "bluez" = {
    module = "hardware.bluetooth.enable";
  };
  "bluez-utils" = {
    module = "hardware.bluetooth.enable";
  };
  "cups" = {
    module = "services.printing.enable";
  };
  "cups-filters" = {
    module = "services.printing.enable";
  };
  "docker" = {
    module = "virtualisation.docker.rootless.enable";
  };
  "fcitx5" = {
    module = "i18n.inputMethod.enable";
  };
  "fcitx5-chewing" = {
    module = "i18n.inputMethod.fcitx5.addons";
  };
  "fcitx5-chinese-addons" = {
    module = "i18n.inputMethod.fcitx5.addons";
  };
  "fcitx5-gtk" = {
    module = "i18n.inputMethod.enable";
  };
  "fcitx5-hangul" = {
    module = "i18n.inputMethod.fcitx5.addons";
  };
  "fcitx5-mozc" = {
    module = "i18n.inputMethod.fcitx5.addons";
  };
  "fcitx5-qt" = {
    module = "i18n.inputMethod.enable";
  };
  "fcitx5-table-extra" = {
    module = "i18n.inputMethod.fcitx5.addons";
  };
  "gvfs-mtp" = {
    module = "services.gvfs.enable";
  };
  "gvfs-nfs" = {
    module = "services.gvfs.enable";
  };
  "gvfs-smb" = {
    module = "services.gvfs.enable";
  };
  "hyprland" = {
    module = "programs.hyprland.enable";
  };
  "linux-firmware" = {
    module = "hardware.enableRedistributableFirmware";
  };
  "networkmanager" = {
    module = "networking.networkmanager.enable";
  };
  "nss-mdns" = {
    module = "services.avahi.nssmdns4";
  };
  "omarchy-power-profiles-daemon" = {
    module = "services.power-profiles-daemon.enable";
  };
  "pipewire" = {
    module = "services.pipewire.enable";
  };
  "pipewire-alsa" = {
    module = "services.pipewire.alsa.enable";
  };
  "pipewire-jack" = {
    module = "services.pipewire.jack.enable";
  };
  "pipewire-pulse" = {
    module = "services.pipewire.pulse.enable";
  };
  "plocate" = {
    module = "services.locate.enable";
  };
  "plymouth" = {
    module = "boot.plymouth.enable";
  };
  "rtkit" = {
    module = "security.rtkit.enable";
  };
  "sddm" = {
    module = "services.displayManager.sddm.enable";
  };
  "ufw" = {
    module = "networking.firewall.enable";
  };
  "wireless-regdb" = {
    module = "hardware.wirelessRegulatoryDatabase";
  };
  "wireplumber" = {
    module = "services.pipewire.wireplumber.enable";
  };
  "zram-generator" = {
    module = "zramSwap.enable";
  };

  # ── Arch-only tooling and packaging ───────────────────────────────────────
  "autoconf-archive" = {
    skip = "Arch build dependency; not installed by default.";
  };
  "base" = {
    skip = "Arch base meta-package; NixOS has its own base system.";
  };
  "base-devel" = {
    skip = "Arch build meta-package; makepkg is not used here.";
  };
  "dkms" = {
    skip = "Arch out-of-tree module build; NixOS builds modules into the kernel package set.";
  };
  "expac" = {
    skip = "pacman helper.";
  };
  "fakeroot" = {
    skip = "makepkg helper; not used on NixOS.";
  };
  "kernel-modules-hook" = {
    skip = "Arch kernel-upgrade hook; NixOS boots a generation that carries its own modules.";
  };
  "limine" = {
    skip = "Arch boot-loader choice; the installer picks the boot loader.";
  };
  "limine-mkinitcpio-hook" = {
    skip = "Arch limine/mkinitcpio integration.";
  };
  "limine-snapper-sync" = {
    skip = "Arch limine/snapper integration.";
  };
  "pacman-contrib" = {
    skip = "pacman tooling; nixarchy ships a pacman shim instead.";
  };
  "ufw-docker" = {
    skip = "Arch ufw/docker glue; the firewall is a NixOS option.";
  };
  "yay" = {
    skip = "AUR helper; no AUR here.";
  };
  "yay-debug" = {
    skip = "AUR helper debug package.";
  };

  # ── Hardware this port does not target ────────────────────────────────────
  "apple-bcm-firmware-fetcher" = {
    skip = "Apple Silicon hardware; this port targets x86_64.";
  };
  "apple-t2-audio-config" = {
    skip = "Intel T2 Mac hardware; not targeted.";
  };
  "asahi-bless" = {
    skip = "Apple Silicon hardware; this port targets x86_64.";
  };
  "asdcontrol" = {
    skip = "Apple Studio Display brightness; not shipped.";
  };
  "asus-proart-p14-speaker-firmware" = {
    skip = "One ASUS laptop; not targeted.";
  };
  "asusctl" = {
    skip = "ASUS laptops; services.asusd is the user choice.";
  };
  "avd-fw" = {
    skip = "Apple Silicon hardware; this port targets x86_64.";
  };
  "bolt" = {
    skip = "Thunderbolt authorisation; services.hardware.bolt is not enabled here.";
  };
  "broadcom-wl-dkms" = {
    skip = "Proprietary Broadcom Wi-Fi; a user hardware choice.";
  };
  "dell-xps-touchpad-haptics" = {
    skip = "Dell XPS hardware; not targeted.";
  };
  "dell-xps13-sidecar-amps" = {
    skip = "Dell XPS hardware; not targeted.";
  };
  "egl-wayland" = {
    skip = "NVIDIA EGL glue; comes with the user NVIDIA driver choice.";
  };
  "intel-ipu7-camera" = {
    skip = "Intel IPU7 camera; unsure whether nixpkgs hardware.ipu7 covers it, not enabled.";
  };
  "intel-lpmd" = {
    skip = "Intel low-power daemon; not enabled.";
  };
  "intel-media-driver" = {
    skip = "Intel VA-API driver: a host gets it from nixos-hardware's common-gpu-intel or its own hardware.graphics.extraPackages, not from this port.";
  };
  "lib32-nvidia-580xx-utils" = {
    skip = "As nvidia-open-dkms.";
  };
  "lib32-nvidia-utils" = {
    skip = "As nvidia-open-dkms; 32-bit is hardware.graphics.enable32Bit, left to the user.";
  };
  "libva-intel-driver" = {
    skip = "Old Intel VA-API driver; not listed.";
  };
  "libva-nvidia-driver" = {
    skip = "As nvidia-open-dkms.";
  };
  "libva-v4l2_request-avd" = {
    skip = "Apple Silicon hardware; this port targets x86_64.";
  };
  "libvpl" = {
    skip = "Intel video library; not listed.";
  };
  "linux-firmware-cirrus-dx13260" = {
    skip = "Cirrus codec firmware for one laptop; not targeted.";
  };
  "linux-firmware-marvell" = {
    module = "hardware.enableRedistributableFirmware"; # linux-firmware carries Marvell's blobs
  };
  "linux-firmware-qcom" = {
    skip = "Qualcomm (aarch64); not targeted.";
  };
  "linux-omarchy" = {
    skip = "Omarchy own kernel for n1x; nixarchy uses the NixOS kernel.";
  };
  "linux-omarchy-headers" = {
    skip = "As linux-omarchy.";
  };
  "linux-t2" = {
    skip = "Intel T2 Mac kernel; not targeted.";
  };
  "linux-t2-headers" = {
    skip = "Intel T2 Mac kernel; not targeted.";
  };
  "macbook12-spi-driver-dkms" = {
    skip = "MacBook12 hardware; not targeted.";
  };
  "nsight-compute" = {
    skip = "GB10 (aarch64) only.";
  };
  "nsight-systems" = {
    skip = "GB10 (aarch64) only.";
  };
  "nvidia-580xx-dkms" = {
    skip = "As nvidia-open-dkms.";
  };
  "nvidia-580xx-utils" = {
    skip = "As nvidia-open-dkms.";
  };
  "nvidia-container-toolkit" = {
    skip = "GB10 (aarch64) only.";
  };
  "nvidia-dkms" = {
    skip = "As nvidia-open-dkms.";
  };
  "nvidia-open-dkms" = {
    skip = "The NVIDIA driver is the user own hardware.nvidia choice; Omarchy picks an Arch package by detection, nixarchy does not.";
  };
  "nvidia-utils" = {
    skip = "As nvidia-open-dkms.";
  };
  "omarchy-mac" = {
    skip = "Apple Silicon hardware; this port targets x86_64.";
  };
  "omarchy-mac-boot" = {
    skip = "Apple Silicon hardware; this port targets x86_64.";
  };
  "pipewire-libcamera" = {
    skip = "Qualcomm/other camera path; not shipped.";
  };
  "qcom-firmware-extract" = {
    skip = "Qualcomm (aarch64); not targeted.";
  };
  "qmk-hid" = {
    skip = "Keyboard firmware tool; not shipped.";
  };
  "rdma-core" = {
    skip = "GB10 (aarch64) only.";
  };
  "sof-firmware" = {
    module = "hardware.enableRedistributableFirmware"; # nixos/modules/hardware/all-firmware.nix lists it
  };
  "systemd-ukify" = {
    skip = "Qualcomm (aarch64) boot tooling; not targeted.";
  };
  "t2fanrd" = {
    skip = "Intel T2 Mac fan daemon; not targeted.";
  };
  "thermald" = {
    skip = "Intel thermal daemon; services.thermald is not enabled here.";
  };
  "tuxedo-drivers-nocompatcheck-dkms" = {
    skip = "Tuxedo laptops; hardware.tuxedo-drivers is the user choice.";
  };
  "vpl-gpu-rt" = {
    skip = "Intel video runtime; not listed.";
  };
  "vulkan-asahi" = {
    skip = "Apple Silicon hardware; this port targets x86_64.";
  };
  "vulkan-freedreno" = {
    skip = "Qualcomm GPU; Mesa on NixOS covers freedreno.";
  };
  "vulkan-intel" = {
    skip = "Mesa on NixOS covers Intel Vulkan.";
  };
  "vulkan-radeon" = {
    skip = "Mesa on NixOS covers Radeon Vulkan.";
  };
  "wf-recorder" = {
    skip = "nixpkgs has it; this port ships gpu-screen-recorder and wl-screenrec instead.";
  };
  "widevine" = {
    skip = "aarch64 Widevine for Apple Silicon.";
  };

  # ── Libraries and language packages that dependants bring ─────────────────
  "dotnet-runtime" = {
    skip = "Language runtime; the dotnet app installs the SDK.";
  };
  "gst-plugin-pipewire" = {
    skip = "GStreamer plugin; not shipped separately.";
  };
  "gtk4-layer-shell" = {
    skip = "Library; comes with the programs that link it.";
  };
  "libsecret" = {
    skip = "Library; comes with the programs that link it.";
  };
  "lua51" = {
    skip = "Arch Neovim plugin dependency; Neovim comes from nixpkgs.";
  };
  "luarocks" = {
    skip = "Arch Neovim plugin dependency; Neovim comes from nixpkgs.";
  };
  "mariadb-libs" = {
    skip = "Library for Arch language bindings.";
  };
  "nautilus-python" = {
    skip = "Nautilus extension host; not shipped.";
  };
  "postgresql-libs" = {
    skip = "Library for Arch language bindings.";
  };
  "python-gobject" = {
    skip = "Arch python bindings; nautilus-python and friends not shipped.";
  };
  "python-poetry-core" = {
    skip = "Arch python build dependency.";
  };
  "qt6-base" = {
    skip = "Qt runtime; our Qt apps carry theirs through wrapQtAppsHook.";
  };
  "qt6-declarative" = {
    skip = "As qt6-base.";
  };
  "qt6-imageformats" = {
    skip = "As qt6-base.";
  };
  "qt6-multimedia" = {
    skip = "As qt6-base.";
  };
  "qt6-svg" = {
    skip = "As qt6-base.";
  };
  "qt6-wayland" = {
    skip = "As qt6-base.";
  };
  "ruby" = {
    skip = "Language runtime; installed on request through the language rows.";
  };
  "webp-pixbuf-loader" = {
    skip = "gdk-pixbuf loader; not shipped separately.";
  };

  # ── nixpkgs has it; this port does not install it by default ──────────────
  "docker-buildx" = {
    skip = "nixpkgs docker bundles it.";
  };
  "docker-compose" = {
    skip = "Not installed by default; installable with the Install menu.";
  };
  "exfatprogs" = {
    skip = "Not installed by default.";
  };
  "herdr" = {
    skip = "Carried as nixarchy's own herdr plugin (nixarchy-plugin nixarchy.herdr, SUPER+ALT+H), not as this package.";
  };
  "inetutils" = {
    skip = "Not installed by default.";
  };
  "lsp-plugins-lv2" = {
    skip = "Mapped for pkg-add advice only (data/arch-extras.nix); not installed.";
  };
  "mpv-mpris" = {
    skip = "Unsure; mpv-with-scripts may carry it.";
  };
  "qemu-user-static-binfmt" = {
    skip = "Not installed by default.";
  };
  "superwhisper-bin" = {
    skip = "Unfree binary, not packaged here.";
  };
  "system-config-printer" = {
    skip = "Not installed by default.";
  };
  "tesseract-data-eng" = {
    skip = "nixpkgs tesseract bundles English data.";
  };
  "tobi-try" = {
    skip = "Not packaged here.";
  };
  "ttf-ia-writer" = {
    skip = "Not packaged here.";
  };
  "tzupdate" = {
    skip = "services.tzupdate is not enabled here.";
  };
  "usage" = {
    skip = "Not installed by default.";
  };
  "v4l2-relayd" = {
    skip = "Upstream's Cam Link 4K relay. Not ported yet; an opt-in module would use boot.extraModulePackages and services.v4l2-relayd (#1610).";
  };
  "v4l2loopback-dkms" = {
    skip = "Upstream's Cam Link 4K relay. Not ported yet; an opt-in module would use boot.extraModulePackages and services.v4l2-relayd (#1610).";
  };
  "v4l2loopback-utils" = {
    skip = "Upstream's Cam Link 4K relay. Not ported yet; an opt-in module would use boot.extraModulePackages and services.v4l2-relayd (#1610).";
  };
  "vi" = {
    skip = "Neovim provides vi/vim aliases where wanted.";
  };
  "whois" = {
    skip = "Not installed by default.";
  };
  "xorg-xsetroot" = {
    skip = "X11 tool; the session is Wayland.";
  };
}
