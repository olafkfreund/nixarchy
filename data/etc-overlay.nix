# Every file in upstream's /etc overlay, and what answers it here.
#
# Omarchy's Arch package copies `etc/` straight into `/etc`. This port copies
# the same tree into `$out/share/omarchy/etc` -- the `cp -r .` in
# pkgs/omarchy/default.nix -- and, until #649, NOTHING INSTALLED IT. Not one
# of these 40 files was read on a running nixarchy machine, and until this
# file existed nothing in the repository said so, or said what took each
# one's place. Now the rows classed `installed` are the exception, and this
# file is what installs them: modules/nixos.nix reads it and declares
# environment.etc.<path> for each, pointing at the shipped file.
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
#   installed   the file itself, at its upstream path, through environment.etc
#               in modules/nixos.nix -- which reads this class from this file
#   seed        modules/home.nix seeds it per user
#   covered     another mechanism satisfies it -- the reason names which
#   na          Arch-stack specific, nothing here to answer it
#   divergent   meaningful on NixOS, deliberately NOT adopted
#
# `divergent` is not in #642's four classes, and is the reason this file is
# worth reading: a row that would do something here and that we deliberately do
# not do, with the measured reason. #642 found fourteen. #649 adopted eleven as
# NixOS options (`native`), found nixpkgs already sets the file-watcher limit
# (`covered`), and kept the two passwordless sudoers rules `divergent` -- on
# NixOS they name an envfs path resolved through the caller's PATH, and change
# state a rebuild reverts. Calling any of them `na` would have made the
# inventory the rubber stamp #642 warns about.
#
# No row is `seed`: modules/home.nix seeds `config/` and `default/`, never
# `etc/`. Two files here (fastfetch and kitty) are the system half of a pair
# whose user half IS seeded, and both were `divergent` until #649 made them
# `installed`; mise's alias went with them. Those three were the user-visible
# symptoms -- a stub config pointing at a file that did not exist, an About
# screen in fastfetch's stock layout, a `mise use` that could not resolve --
# and a file whose program reads it by path is the same shape of change: turn
# the row's class, and modules/nixos.nix installs it.
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
    class = "native";
    reason = "wifi.powersave = 2 turns the driver's power saving off, which stops the latency spikes and dropped links on idle wifi. modules/nixos.nix sets networking.networkmanager.wifi.powersave = false at mkDefault, which NetworkManager's module writes as that same value.";
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
    class = "native";
    reason = "json-file log rotation at 10m x 5, set on the rootless daemon Docker runs as here through virtualisation.docker.rootless.daemon.settings at mkDefault. The bip/dns half pins the rooted bridge to the resolved stub, and rootless Docker (slirp4netns) has no such bridge, so that half is not carried.";
  };

  "fastfetch/config.jsonc" = {
    class = "installed";
    reason = "Upstream's About layout, which omarchy-launch-about renders through fastfetch and fastfetch finds at /etc/fastfetch/config.jsonc when ~/.config has none. Installed as the shipped file, so the one patch this repository applies to the etc tree (pkgs/omarchy/default.nix, the Nixarchy OS line) is read. #649.";
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
    class = "installed";
    reason = "A mise tool_alias so `mise use -g cursor-agent` resolves, which is how upstream's omarchy-mise-install wrapper installs the Cursor CLI. mise reads /etc/mise/conf.d, and this is the shipped file at that path, so that agent installs like the others. #649.";
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
    class = "native";
    reason = "`options usbcore autosuspend=-1` stops the kernel suspending USB devices, which keeps a keyboard or dock from waking slowly or dropping. modules/nixos.nix writes the same line through boot.extraModprobeConfig; lines merge, so it is a plain assignment.";
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
    reason = "NOPASSWD for `/usr/bin/omarchy-dns Cloudflare|Google|DHCP`. Not adopted, for two measured reasons: /usr/bin here is envfs, which resolves each name through the CALLING process's PATH, so a passwordless rule on that path would run whatever the user's PATH puts first as root; and the script writes /etc/systemd/resolved.conf, which services.resolved regenerates, so the switch does not survive a rebuild (data/bin-ledger.nix). `omarchy dns` keeps its password prompt.";
  };

  "sudoers.d/omarchy-passwd-tries" = {
    class = "native";
    reason = "`Defaults passwd_tries=10`, the sudo half of the lockout Omarchy loosens, so a mistyped password does not end the attempt at three. modules/nixos.nix carries the same line through security.sudo.extraConfig.";
  };

  "sudoers.d/omarchy-theme-browser" = {
    class = "covered";
    reason = "NOPASSWD for omarchy-theme-set-browser-policy, which writes an accent colour into each browser's policy directory. modules/nixos.nix creates those directories owned by programs.nixarchy.browserThemeUser through systemd.tmpfiles instead, so the script needs no root at all.";
  };

  "sudoers.d/omarchy-tzupdate" = {
    class = "divergent";
    reason = "NOPASSWD for `timedatectl set-timezone`. Not adopted: every machine the installer writes sets time.timeZone (installer/template/host/configuration.nix), which makes /etc/localtime NixOS's to own, so the command cannot change it here and a passwordless root grant would buy nothing; and the rule names /usr/bin, which is envfs, resolved through the caller's PATH.";
  };

  "sysctl.d/90-omarchy-file-watchers.conf" = {
    class = "covered";
    reason = "fs.inotify.max_user_watches=524288, the limit that stops a watcher in a large checkout failing with ENOSPC. nixpkgs' own nixos/modules/config/sysctl.nix already sets exactly 524288 by default, on every NixOS machine, so nothing here needs to.";
  };

  "sysctl.d/99-omarchy-sysctl.conf" = {
    class = "native";
    reason = "Desktop memory and writeback tuning, value for value: tcp_mtu_probing, swappiness 150 for the zramSwap modules/nixos.nix enables, vfs_cache_pressure, page-cluster, watermarks and dirty bytes. modules/nixos.nix sets each through boot.kernel.sysctl at mkDefault, so a machine's own value wins.";
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
    class = "native";
    reason = "systemd-oomd kills at 50% memory pressure held for 20s rather than nixpkgs' 60% and systemd's 30s, so one runaway app goes before the session thrashes. modules/nixos.nix sets both through systemd.oomd.settings.OOM at mkDefault.";
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
    class = "native";
    reason = "DefaultTimeoutStopSec=5s, so power-off does not wait out systemd's 90 seconds on a hung unit. modules/nixos.nix sets it through systemd.settings.Manager at mkDefault; a unit that declares its own TimeoutStopSec keeps it.";
  };

  "systemd/system.conf.d/20-omarchy-nofile.conf" = {
    class = "native";
    reason = "DefaultLimitNOFILE=65536:524288, the descriptor limit every system unit inherits instead of systemd's soft 1024. modules/nixos.nix sets it through systemd.settings.Manager at mkDefault.";
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
    class = "native";
    reason = "ConditionACPower=true keeps the locate database rebuild off a laptop on battery. NixOS names the unit update-locatedb, not plocate-updatedb, so modules/nixos.nix sets the condition on that unit, only while services.locate.enable is on.";
  };

  "systemd/system/user@.service.d/10-faster-shutdown.conf" = {
    class = "native";
    reason = "TimeoutStopSec=5s on the user manager, the per-user half of the faster shutdown, so logout and power-off do not wait on a stuck user service. modules/nixos.nix sets it on systemd.services.\"user@\" at mkDefault.";
  };

  "systemd/user.conf.d/20-omarchy-nofile.conf" = {
    class = "native";
    reason = "DefaultLimitNOFILE=65536:524288 for the user manager, the limit every graphical application actually inherits. modules/nixos.nix sets it through systemd.user.settings.Manager at mkDefault.";
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
    class = "installed";
    reason = "Omarchy's kitty defaults -- font, padding, the CSI-u bindings for shift+enter, the remote-control socket. kitty reads $XDG_CONFIG_DIRS/kitty/kitty.conf and NixOS sets that to /etc/xdg, so the shipped file is the system half; modules/home.nix seeds upstream's config/kitty/kitty.conf, the stub whose comment points at this one. #649.";
  };
}
