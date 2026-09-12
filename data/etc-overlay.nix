# Every file in upstream's /etc overlay, and what answers it here.
#
# Omarchy's Arch package copies `etc/` straight into `/etc`. This port copies
# the same tree into `$out/share/omarchy/etc` -- the `cp -r .` in
# pkgs/omarchy/default.nix -- and NOTHING INSTALLS IT. Not one of these 40
# files is read on a running nixarchy machine, and until this file existed
# nothing in the repository said so, or said what took each one's place.
#
# So the risk is not that a file is ignored. It is that a file is ignored
# WITHOUT A DECISION: upstream adds a sysctl, a modprobe quirk, a sudoers
# rule, and the desktop quietly behaves differently from Omarchy's with
# nothing to notice it.  A row here is that decision, written down.
#
# ## The rule that keeps this file honest
#
# tests/etc-overlay.nix diffs these keys against the shipped tree and fails in
# BOTH directions: a file upstream ships with no row is unclassified, and a row
# for a file upstream dropped is stale. So a source bump cannot be merged by
# editing this file alone -- the same argument data/bin-ledger.nix makes about
# classification, applied to an inventory.
#
# ## The classes
#
#   native      a NixOS option in modules/ declares the equivalent
#   seed        modules/home.nix seeds it per user
#   covered     another mechanism satisfies it -- the reason names which
#   na          Arch-stack specific, nothing here to answer it
#   divergent   meaningful on NixOS, deliberately NOT adopted
#
# `divergent` is not in #642's four classes, and is the reason this file is
# worth reading. Seventeen of these are neither native, nor covered, nor
# inapplicable: they would do something here and we do not do it. Calling those
# `na` would have made the inventory the rubber stamp #642 warns about. Each
# `divergent` row names the NixOS option that would carry it, so adopting one
# later is a rebuild rather than an investigation.
#
# No row is `seed`: modules/home.nix seeds `config/` and `default/`, never
# `etc/`, and that is itself a finding rather than an omission -- two files
# here (fastfetch and kitty) are the system half of a pair whose user half IS
# seeded, and both say so.
#
# ## What a reason is for
#
# One or two sentences a reader can check after an Omarchy release, naming the
# option, the file, or the mechanism. "Not applicable to NixOS" is true of the
# whole tree and therefore distinguishes nothing; the check enforces a floor on
# reason length for that reason alone.
#
# The fail-closed manifest and the both-direction inventory diff are ideas from
# zicochaos/omarchy-nix (MIT), an independent port that built the comparison
# this repository had only written down. The code here is ours.
{
  "NetworkManager/conf.d/omarchy-wifi-powersave.conf" = {
    class = "divergent";
    reason = "wifi.powersave = 2 turns the driver's power saving off, which is what stops the multi-second stalls after an idle wifi link. networking.networkmanager.wifi.powersave is the option and nothing here sets it, so NetworkManager's own default stands.";
  };

  "cups/cups-browsed.conf" = {
    class = "covered";
    reason = "services.printing.browsed.enable = false in modules/nixos.nix, so cups-browsed never runs and has no configuration to read. Discovery is avahi's here, enabled in the same block with nssmdns4.";
  };

  "cups/cups-files.conf" = {
    class = "native";
    reason = "services.printing.enable generates /etc/cups/cups-files.conf from the module. The User/Group 209 in upstream's copy is Arch's cups uid, which is exactly the kind of number a NixOS machine must not be handed.";
  };

  "docker/daemon.json" = {
    class = "divergent";
    reason = "Sets json-file log rotation and pins bip/dns to 172.17.0.1 to pair with the resolved stub listener. modules/nixos.nix runs docker ROOTLESS by default, whose network is slirp4netns and not that bridge, so neither half transfers; the log limits would, through virtualisation.docker.rootless.daemon.settings, and are not set.";
  };

  "fastfetch/config.jsonc" = {
    class = "divergent";
    reason = "Upstream's About layout, installed to /etc/fastfetch/config.jsonc by the Arch package. Nothing writes that path here, so fastfetch and omarchy-launch-about fall back to fastfetch's stock layout -- and the one patch this repository applies to the etc tree (pkgs/omarchy/default.nix, the Nixarchy OS line) is applied to a file nothing reads.";
  };

  "gnupg/dirmngr.conf" = {
    class = "na";
    reason = "Keyserver fallbacks and a short connect timeout for the system dirmngr, which on Arch exists to keep `pacman-key --refresh-keys` working. There is no system keyring to refresh here; a user's own gpg reads ~/.gnupg/dirmngr.conf, which is theirs.";
  };

  "limine-entry-tool.d/omarchy-defaults.conf" = {
    class = "covered";
    reason = "limine-entry-tool is Arch-only and installer/host.nix boots systemd-boot. The half that is not about the bootloader -- a quiet splash -- is nixpkgs': boot.plymouth adds `splash` and NixOS already passes loglevel and udev.log_level. The snapshot entries are snapper's, which this port does not use.";
  };

  "limine-entry-tool.d/omarchy-uki.conf" = {
    class = "na";
    reason = "Turns on unified-kernel-image generation in limine-entry-tool. NixOS builds its boot entries from the system closure, so there is no equivalent switch to set.";
  };

  "mise/conf.d/omarchy.toml" = {
    class = "divergent";
    reason = "A mise tool_alias so `mise use -g cursor-agent` resolves, which is how upstream's omarchy-mise-install wrapper installs the Cursor CLI. mise reads /etc/mise/conf.d and nothing writes it here, so that one agent install fails while the others work.";
  };

  "mkinitcpio.conf.d/omarchy_hooks.conf" = {
    class = "na";
    reason = "HOOKS for mkinitcpio, including dropping kms on an NVIDIA-only machine. NixOS builds its initrd from boot.initrd.*; there is no hook list to order.";
  };

  "mkinitcpio.conf.d/thunderbolt_module.conf" = {
    class = "covered";
    reason = "MODULES+=(thunderbolt) for mkinitcpio. modules/nixos.nix feeds boot.initrd.availableKernelModules the whole nixpkgs all-hardware list, so an initrd here carries the Thunderbolt drivers without being told.";
  };

  "modprobe.d/omarchy-usb-autosuspend.conf" = {
    class = "divergent";
    reason = "`options usbcore autosuspend=-1` stops the kernel suspending USB devices, which is what keeps a keyboard or a dock from waking slowly or dropping. boot.extraModprobeConfig is the option and nothing here sets it.";
  };

  "nsswitch.conf" = {
    class = "native";
    reason = "NixOS generates /etc/nsswitch.conf from system.nssModules and system.nssDatabases. services.avahi.nssmdns4 in modules/nixos.nix adds the mdns entry this file's hosts line exists for.";
  };

  "plymouth/plymouthd.conf" = {
    class = "native";
    reason = "boot.plymouth.theme = \"omarchy\" in modules/nixos.nix, with themePackages naming the package that carries share/plymouth/themes/omarchy. programs.nixarchy.bootSplash chooses between mkDefault and mkForce for it.";
  };

  "profile.d/omarchy.sh" = {
    class = "covered";
    reason = "Sources /usr/share/omarchy/default/bash/env-bootstrap. programs.bash.interactiveShellInit sources the same default/bash/rc chain into /etc/bashrc, and modules/nixos.nix records that the two /usr paths that chain mentions are behind `[ -r ]` guards whose jobs this module and NixOS already do.";
  };

  "sddm.conf.d/10-theme.conf" = {
    class = "native";
    reason = "services.displayManager.sddm.theme = \"omarchy\" in modules/nixos.nix, which names the theme the package installs under share/sddm/themes.";
  };

  "sddm.conf.d/10-wayland.conf" = {
    class = "native";
    reason = "services.displayManager.sddm.wayland.enable = true in modules/nixos.nix. The CompositorCommand naming /usr/share/sddm/hyprland.lua is Arch's path; nixpkgs' sddm module supplies its own compositor command, so taking this file would break the greeter rather than configure it.";
  };

  "security/faillock.conf" = {
    class = "covered";
    reason = "Raises Arch's three failed passwords before a lockout to ten. NixOS' pam stack wires pam_faillock only as the logFailures audit module, never the preauth/authfail pair that locks an account, so there is no lockout limit to raise.";
  };

  "sudoers.d/omarchy-dns" = {
    class = "divergent";
    reason = "NOPASSWD for `omarchy-dns Cloudflare|Google|DHCP`, so the DNS panel switches without a prompt. The rule names /usr/bin/omarchy-dns, which does not exist here; a security.sudo.extraRules entry would have to name the store path or /run/current-system/sw/bin. Unadopted, so `omarchy dns` asks for a password.";
  };

  "sudoers.d/omarchy-passwd-tries" = {
    class = "divergent";
    reason = "`Defaults passwd_tries=10`, the sudo half of the lockout Omarchy loosens. security.sudo.extraConfig would carry it; nothing here does, so sudo's three attempts stand.";
  };

  "sudoers.d/omarchy-theme-browser" = {
    class = "covered";
    reason = "NOPASSWD for omarchy-theme-set-browser-policy, which writes an accent colour into each browser's policy directory. modules/nixos.nix creates those directories owned by programs.nixarchy.browserThemeUser through systemd.tmpfiles instead, so the script needs no root at all.";
  };

  "sudoers.d/omarchy-tzupdate" = {
    class = "divergent";
    reason = "NOPASSWD for `timedatectl set-timezone`, so the timezone picker applies without a prompt. Same shape as omarchy-dns: the rule names /usr/bin/timedatectl and no security.sudo.extraRules entry replaces it, so setting a timezone from the menu asks for a password.";
  };

  "sysctl.d/90-omarchy-file-watchers.conf" = {
    class = "divergent";
    reason = "fs.inotify.max_user_watches=524288, which is what stops a file watcher in a large checkout failing with ENOSPC. boot.kernel.sysctl is the option and nothing here sets it, so the kernel's 8192-per-user default stands.";
  };

  "sysctl.d/99-omarchy-sysctl.conf" = {
    class = "divergent";
    reason = "Desktop memory and writeback tuning. vm.swappiness=150 is the one that matters most here, because modules/nixos.nix turns zramSwap on for exactly the reason upstream raises it -- compressed swap in RAM is cheap to page to -- and then leaves swappiness at the kernel's 60. boot.kernel.sysctl would carry the whole file.";
  };

  "sysusers.d/omarchy-cups-browsed.conf" = {
    class = "covered";
    reason = "Allocates the cups-browsed system user. cups-browsed is off here (services.printing.browsed.enable = false), and NixOS declares users through users.users rather than sysusers.d in any case.";
  };

  "systemd/logind.conf.d/10-ignore-power-button.conf" = {
    class = "native";
    reason = "services.logind.settings.Login.HandlePowerKey = \"ignore\" in modules/nixos.nix, which is what lets Omarchy's own power menu answer the button instead of NixOS shutting the machine down.";
  };

  "systemd/logind.conf.d/20-inhibit-delay.conf" = {
    class = "native";
    reason = "services.logind.settings.Login.InhibitDelayMaxSec = 15 in modules/nixos.nix, giving omarchy-sleep-lock time to secure the screen before logind suspends anyway.";
  };

  "systemd/oomd.conf.d/10-omarchy.conf" = {
    class = "divergent";
    reason = "Tightens systemd-oomd to kill at 50% memory pressure held for 20s. nixpkgs' oomd module sets DefaultMemoryPressureLimit to 60% and leaves the duration at systemd's 30s; modules/nixos.nix adds the app.slice ManagedOOM drop-in but not these defaults, so a desktop here is killed later than on Omarchy.";
  };

  "systemd/resolved.conf.d/10-disable-multicast.conf" = {
    class = "covered";
    reason = "Turns LLMNR and resolved's MulticastDNS off so they do not race avahi. services.resolved is not enabled by this module at all -- avahi answers mDNS here -- so there is no second responder to silence.";
  };

  "systemd/resolved.conf.d/20-docker-dns.conf" = {
    class = "covered";
    reason = "A resolved stub listener on the docker bridge, the other half of etc/docker/daemon.json. Neither resolved nor the rooted docker daemon is enabled here, and rootless docker does not use that bridge.";
  };

  "systemd/system.conf.d/10-faster-shutdown.conf" = {
    class = "divergent";
    reason = "DefaultTimeoutStopSec=5s, the difference between a desktop that powers off at once and one that waits out systemd's 90 seconds on a hung unit. systemd.settings.Manager would carry it and nothing here does.";
  };

  "systemd/system.conf.d/20-omarchy-nofile.conf" = {
    class = "divergent";
    reason = "DefaultLimitNOFILE=65536:524288, raising the soft descriptor limit every system unit inherits from systemd's 1024. NixOS sets neither half, so a bundler, a watcher or a language server started by a system unit gets the low soft limit.";
  };

  "systemd/system/cups-browsed.service.d/10-omarchy.conf" = {
    class = "covered";
    reason = "Sandboxing for cups-browsed -- its own user, ProtectSystem=strict, NoNewPrivileges. The service is off here (services.printing.browsed.enable = false), so there is nothing to harden.";
  };

  "systemd/system/docker.service.d/no-block-boot.conf" = {
    class = "covered";
    reason = "DefaultDependencies=no so a rooted docker.service does not hold up boot. modules/nixos.nix leaves virtualisation.docker.enable at false and runs the rootless daemon as a user unit, which is not in the boot path at all.";
  };

  "systemd/system/plocate-updatedb.service.d/ac-only.conf" = {
    class = "divergent";
    reason = "ConditionACPower=true keeps the locate database rebuild off a laptop on battery. services.locate.enable is on in modules/nixos.nix and its timer runs the update unconditioned, so that rebuild can fire on battery here.";
  };

  "systemd/system/user@.service.d/10-faster-shutdown.conf" = {
    class = "divergent";
    reason = "TimeoutStopSec=5s on the user manager, the per-user half of system.conf.d/10-faster-shutdown.conf. A systemd.services.\"user@\" drop-in would carry it; unadopted, so logout and shutdown wait on a stuck user service.";
  };

  "systemd/user.conf.d/20-omarchy-nofile.conf" = {
    class = "divergent";
    reason = "DefaultLimitNOFILE=65536:524288 for the user manager -- the limit every graphical application actually inherits, since the session's units are started by it. systemd.user.extraConfig would carry it and nothing here does.";
  };

  "tmpfiles.d/omarchy-nopasswd-sudo.conf" = {
    class = "covered";
    reason = "Reaps /etc/sudoers.d/99-omarchy-nopasswd-* at boot so a temporary passwordless sudo cannot outlive it. pkgs/omarchy/nix-bin/omarchy-sudo-passwordless replaces the command that writes those files with a message pointing at security.sudo, so the file this cleans up is never written.";
  };

  "tmpfiles.d/omarchy-zswap.conf" = {
    class = "covered";
    reason = "Writes N to zswap's enabled parameter so it cannot compete with zram. nixpkgs' kernels leave CONFIG_ZSWAP_DEFAULT_ON off and nothing here turns zswap on, so zram -- enabled in modules/nixos.nix -- is already the only compressed swap.";
  };

  "xdg/kitty/kitty.conf" = {
    class = "divergent";
    reason = "Omarchy's kitty defaults -- font, padding, the CSI-u bindings for shift+enter, the remote-control socket -- installed to /etc/xdg/kitty/kitty.conf. modules/home.nix seeds upstream's config/kitty/kitty.conf into ~/.config, and that file is a five-line stub whose own comment points at this one for the real settings, so kitty here is themed but otherwise stock.";
  };
}
