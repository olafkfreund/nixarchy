# Every command this port does not ship verbatim, and why.
#
# Omarchy is 444 commands. This port ships all of them and 10 of its own, and
# 386 of the 444 are byte-identical below the shebang -- patchShebangs rewrites
# line 1 and nothing else touches them. So the interesting surface is the rows
# here, and CI derives the rest rather than trusting a hand list.
#
# ## The rule that keeps this file honest
#
# A vendored command does NOT get a row, unless it carries a `pacman` or an
# `allow` field -- see below, and note that neither of those restates the
# comparison. Otherwise a row is a CLAIM that the shipped file
# differs from upstream, and .github/scripts/check-bin-ledger.py fails in BOTH
# directions: a file that differs with no row is unclassified, and a row whose
# derived class no longer matches is stale. Neither can be satisfied by editing
# this file alone.
#
# That matters because a hand-maintained list that only agrees with itself
# proves nothing -- the same argument omarchy-patched-files.sh already makes,
# applied to classification instead of to file names.
#
# ## The classes, all derived and then checked against the row
#
#   vendor    identical to upstream below line 1. Gets no row.
#   patch     differs below the shebang, via substituteInPlace in
#             pkgs/omarchy/default.nix
#   replace   a file in pkgs/omarchy/nix-bin with an upstream name
#   new       a file in pkgs/omarchy/nix-bin with no upstream counterpart
#   shim      pacman, from pacman-shim.sh
#
# The diff-based derivation is strictly stronger than grepping for
# substituteInPlace: it catches the sed sites that no grep can see.
#
# ## What the file DOES, beside what changed
#
# The classes above answer "did this file change". They cannot answer "what
# does this file do", and on NixOS that is the question that bites: a vendored
# command that gains `systemctl enable`, `usermod`, a write under /etc or an
# initramfs regeneration at the next Omarchy bump is byte-identical to the new
# upstream, derives as `vendor`, and passes.
#
# So a row may also carry `allow`, a space-separated list of the behaviour
# groups .github/scripts/check-bin-ledger.py finds in the shipped script --
# ufw, systemctl-system, systemctl-user, etc-write, boot-write, modprobe,
# account-tools, kernel-ctl, initrd-boot, rfkill, nmcli-radio, ctl-set. Same
# biconditional as everything else here: a script matching a group with no
# allowance fails, and an allowance the script no longer matches fails too, so
# an upstream cleanup is reported rather than assumed.
#
# `allow` is a STRING and not a list because the ledger is read by regex over
# quoted strings; a list-valued key would be invisible to the parser and the
# allowance would silently mean nothing.
#
# The patterns over-match on purpose -- `cp /etc/skel/. ~/` reads /etc and
# still counts -- because a false positive costs one row saying so, and a false
# negative costs the whole point. That is also why a vendor row may carry
# `allow`: unlike a bare vendor row it restates nothing the comparison already
# proves.
#
# The fail-closed pattern-group scheme is zicochaos/omarchy-nix's idea (MIT).
# The patterns, the groups and the code are ours.
#
# ## What a reason is for
#
# One or two sentences saying WHY the file differs, specific enough that a
# reader can tell whether it is still true after an Omarchy release. "Adapted
# for NixOS" is true of everything here and therefore distinguishes nothing;
# naming upstream's actual command or path is what makes a row checkable.
#
# When upstream adopts one of our patches, this file is where that shows up --
# the row goes stale, CI says so, and the row is deleted. Being told is the
# point.
{
  "nixarchy-android" = {
    class = "new";
    reason = "Not in upstream. scrcpy over Wi-Fi needs adb pair and adb connect on two different ports, one of them regenerated every time the pairing dialog opens, with a code valid for seconds; and `adb mdns services` cannot find them because nixpkgs' android-tools is built without an mDNS backend. This discovers both through avahi, which nixarchy already runs.";
  };
  "nixarchy-ask" = {
    class = "new";
    reason = "Not in upstream. Wraps omarchy-agent-prompt with prompts that name the skill and insist on measure-then-propose, so routing is fixed here rather than re-guessed on every invocation.";
  };
  "nixarchy-channel" = {
    class = "new";
    reason = "Not in upstream. The generated flake documents following stable as prose telling you to hand-edit nixpkgs AND home-manager; this does both or neither, because moving one without the other is the pairing that breaks.";
  };
  "nixarchy-config-repo" = {
    class = "new";
    reason = "Not in upstream. The installer leaves /etc/nixos as a git repository with a staged tree and no commit; this commits it, adds a remote and CI, and is idempotent on a re-run.";
  };
  "nixarchy-home-backup" = {
    class = "new";
    reason = "Not in upstream. modules/home.nix seeds ~/.config with `cp -rn`, so those files sit outside generations and /etc/nixos; this backs an allowlisted slice of $HOME into a second git repository.";
  };
  "nixarchy-local-ai" = {
    class = "new";
    reason = "Not in upstream. programs.nixarchy.localAi enables the service but deliberately downloads no weights; this pulls a model at runtime and sizes it against VRAM, which Nix cannot read.";
  };
  "nixarchy-preview" = {
    class = "new";
    reason = "Not in upstream, where a config change is a pacman transaction with no dry run to look at. Builds nixosConfigurations.<host>.config.system.build.vm -- the same configuration re-evaluated under qemu-vm.nix -- and boots it in a window, on a managed disk that is refused when stale rather than silently reused.";
  };
  "nixarchy-reinstall-iso" = {
    class = "new";
    reason = "Not in upstream, whose recovery story is snapper snapshots on the same disk. Builds a bootable image from this machine's own configuration -- the system closure and /etc/nixos, never /home or secrets -- after refusing on low disk, an uncommitted tree, or a running system that drifted from the flake.";
  };
  "nixarchy-rollback" = {
    class = "new";
    reason = "Not in upstream, whose undo is omarchy-snapshot via snapper and limine. Lists and switches NixOS system generations, which are the bootable snapshot every rebuild already leaves behind.";
  };
  "nixarchy-try" = {
    class = "new";
    reason = "Not in upstream, where trying an app IS installing it (pacman, then remove). Runs a catalogue app or nixpkgs attribute once from the machine's own pinned nixpkgs -- nix shell -f with the catalogue's binary field, never nix run's mainProgram guess -- and prints the app-enable/pkg-add hand-off when it exits.";
  };
  "nixarchy-unfreeze" = {
    class = "new";
    reason = "Not in upstream. Machines installed before the fix pin nixarchy by commit in flake.nix and in the lock's `original`, so `nix flake update` can never move; this rewrites those two lines only.";
  };
  "nixarchy-version" = {
    class = "new";
    reason = "Not in upstream, whose `omarchy --version` answers only which Omarchy. Prints the nixarchy revision and date, spliced in by pkgs/omarchy/default.nix from what the flake actually built.";
  };
  "omarchy-agent" = {
    class = "patch";
    reason = "Two edits: mise's shims are prepended to PATH, because the menu launches through `bash -c` which sources no rc; and an `antigravity` case is added, which upstream's launcher has no arm for.";
  };
  "omarchy-agent-crash" = {
    class = "patch";
    reason = "The prompt is retargeted from `this Omarchy machine` and `reporting upstream to Omarchy` to Nixarchy or Omarchy, so the agent does not reach reporting.md already pointed at Basecamp.";
  };
  "omarchy-agent-account-exec" = {
    class = "patch";
    reason = "Its mise install fallback refuses with exit 127 instead: nixarchy installs claude, codex and grok through Nix, and one it did not install (unfree off) stays not installed (#1386).";
  };
  "omarchy-install-ai-chatgpt" = {
    class = "patch";
    reason = "The install command launches /usr/bin/chatgpt, which is absent on NixOS; launch the installed command from PATH.";
  };
  "omarchy-install-service-signal" = {
    class = "patch";
    reason = "The install command launches /usr/bin/signal-desktop, which is absent on NixOS; launch the installed command from PATH.";
  };
  "omarchy-install-service-spotify" = {
    class = "patch";
    reason = "The install command launches /usr/bin/spotify, which is absent on NixOS; launch the installed command from PATH.";
  };
  "omarchy-apply-lock" = {
    class = "patch";
    reason = "Its root PATH reset points at /usr/bin, which holds nothing here, so it lost tee and getent while writing lock-screen PAM files; and its `-x /usr/bin/fprintd-list` probe was never true. On quattro (#1285) it also copies a resume hook into /usr/lib and a stop timeout into /etc/systemd; modules/nixos.nix declares both, so those copies are dropped.";
    allow = "etc-write";
  };
  "omarchy-apply-pacman" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Renders /etc/pacman.conf and the mirrorlist from channel templates and a regional profile. Not reached by nixarchy's flows: its callers are omarchy-refresh-pacman (unreachable, see its row), the Arch installer's post-install, and omarchy-channel-set, which is patched to delegate to nixarchy-channel (#1431).";
  };
  "omarchy-apply-system" = {
    class = "vendor";
    reason = "Vendored unchanged, and the account-tools match is prose: `usermod` appears only in the --defer-provisioning paragraph of the usage heredoc, which comment-stripping cannot see. The script is upstream's chroot entry point for an Arch install; the installer here is installer/, which never calls it.";
    allow = "account-tools";
  };
  "omarchy-audio-tuning" = {
    class = "patch";
    reason = "It tests for the LSP limiter at a fixed path under /usr/lib/lv2. NixOS keeps LV2 plugins in the store and points hosts at them with LV2_PATH, so the search is over LV2_PATH and the system profile.";
    allow = "systemctl-user";
  };
  "omarchy-bluetooth-device" = {
    class = "patch";
    reason = "Upstream pairs without an agent lifecycle. For #1085, the pair action starts a temporary NoInputNoOutput bt-agent, waits until the adapter is pairable, then stops that agent after pairing and trust but before connect; the other actions keep upstream behavior.";
  };
  "omarchy-bluetooth-power" = {
    class = "vendor";
    reason = "Vendored unchanged. `rfkill block/unblock bluetooth` sets the radio's soft block, which is runtime kernel state rather than configuration, so it behaves here as it does upstream and is meant not to survive a reboot.";
    allow = "rfkill";
  };
  "omarchy-channel-current" = {
    class = "patch";
    reason = "Upstream reads pacman packages to name the channel. The body is replaced by a delegation to `nixarchy-channel omarchy --current`, which reads the machine's flake.nix. The shebang and `# omarchy:` header lines are kept.";
  };
  "omarchy-channel-set" = {
    class = "patch";
    reason = "Upstream switches channels with pacman and mirrors. The body is replaced by a delegation to `nixarchy-channel omarchy`, which edits the machine's flake.nix (stable, edge, or a checkout of your own; rc is refused). The shebang and `# omarchy:` header lines are kept, minus requires-sudo.";
  };
  "omarchy-cursor-set" = {
    class = "new";
    reason = "Not in upstream, which sets a cursor size but never a theme, because on Arch one arrives with the desktop packages. Picks Bibata Ice or Classic from the mode in the theme's colors.toml.";
  };
  "omarchy-debug" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Reads pacman state for display only; nothing is installed or removed.";
  };
  "omarchy-debug-idle" = {
    class = "vendor";
    reason = "Vendored unchanged. Reads `systemctl --user status omarchy-sleep-lock.service` for a diagnostic dump; nothing is started, stopped or enabled.";
    allow = "systemctl-user";
  };
  "omarchy-default-agent" = {
    class = "replace";
    reason = "Upstream installs the agent with `mise use -g`: imperative, its shims only reach an interactive shell (the menu launches through `bash -c`), and its npm backend needs a node that is not in this closure.";
  };
  "omarchy-default-browser" = {
    class = "patch";
    reason = "It names chromium.desktop, which nixpkgs calls chromium-browser.desktop, so setting the browser exited 1 having set nothing and the no-argument read printed the raw desktop id. It also names zen.desktop; nixarchy's Zen is the zen-browser flake's beta, which installs zen-beta.desktop, so the setter set a desktop id that does not exist and the reader never answered zen (#1303). Quattro also probes `zen-browser` before setting, and nixarchy's binary is `zen-beta` (#1398).";
  };
  "omarchy-default-editor" = {
    class = "patch";
    reason = "quattro's setter installs an editor it thinks is missing, and probes `helix`, which nixpkgs installs as `hx`. So choosing an installed Helix tried an Arch install and set nothing (#1398).";
  };
  "omarchy-dev-install-ydoo" = {
    class = "vendor";
    reason = "Vendored unchanged. Upstream adds $USER to the input group with pkexec usermod, loads uinput with modprobe, and starts ydotool.service as a user unit. The first two are declarative here -- users.users.<name>.extraGroups and boot.kernelModules -- so a run does not survive the next rebuild.";
    allow = "account-tools modprobe systemctl-user";
  };
  "omarchy-dev-link" = {
    class = "vendor";
    reason = "Vendored unchanged. Points /etc/omarchy.conf at a development checkout with `sudo tee`, after validating a sudoers fragment with `visudo -cf`. OMARCHY_PATH is a store path here, so the file it writes contradicts the one the session reads.";
    allow = "account-tools etc-write";
  };
  "omarchy-dev-pkg-test" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Development tooling, not on any user path.";
  };
  "omarchy-dev-unlink" = {
    class = "vendor";
    reason = "Vendored unchanged. The other half of omarchy-dev-link: rewrites /etc/omarchy.conf back to the default target with `sudo tee`, and is wrong here for the same reason.";
    allow = "etc-write";
  };
  "omarchy-dns" = {
    class = "patch";
    reason = "Writes resolved.conf and NetworkManager state imperatively; exits 1 with the networking.nameservers route at require_root, before any write (#1304).";
    allow = "etc-write";
  };
  "omarchy-display-text-size" = {
    class = "patch";
    reason = "Its terminal-font step edits ~/.config/{alacritty,ghostty,foot,kitty} with `sed -i`. On Arch those are ordinary files; here they can be Home Manager symlinks into the store, so sed dies with `couldn't open temporary file /nix/store/sedXXXXXX: Read-only file system` while the shell and GTK sizes still apply -- a partial result and an error nobody can act on (#948). A guard returns early and names the files instead, so an unmanaged config keeps today's behaviour.";
  };
  "omarchy-font-list" = {
    class = "patch";
    reason = "Its fc-list :spacing=100 also matches X11's cursor glyph font, which fontconfig reports as family `cursor.pcf` wherever font-cursor-misc is installed -- NixOS adds it with services.xserver.enable. The grep -v that already drops emoji fonts also drops that family (#1303).";
  };
  "omarchy-games-retro-cores" = {
    class = "replace";
    reason = "Upstream filters a hardcoded list of 23 preferred cores against /usr/lib/libretro. Lists whatever the built retroarch package actually carries, labelled from libretro-core-info.";
  };
  "omarchy-games-retro-install" = {
    class = "patch";
    reason = "It hardcodes /usr/lib/libretro. nixpkgs puts the cores inside the retroarch wrapper's own store path, so the directory is resolved at runtime with `omarchy-retroarch-cores`.";
  };
  "omarchy-hibernation-available" = {
    class = "patch";
    reason = "It decided hibernation was set up by testing for /etc/mkinitcpio.conf.d/omarchy_resume.conf, which only Omarchy's Arch installer writes, so a NixOS machine with swap and boot.resumeDevice never saw the Hibernate row. That term asks logind's CanHibernate instead -- the same authority `systemctl hibernate` uses. Upstream's image_size, swap-size and zram terms stay (#1303).";
  };
  "omarchy-hibernation-remove" = {
    class = "vendor";
    reason = "Vendored unchanged. Removes the swap file, edits /etc/fstab in place and reruns limine-mkinitcpio. /etc/fstab is generated from fileSystems here and there is no mkinitcpio, so it has nothing correct to undo.";
    allow = "etc-write initrd-boot";
  };
  "omarchy-hibernation-setup" = {
    class = "vendor";
    reason = "Vendored unchanged. Creates a swap file and writes /etc/mkinitcpio.conf.d and /etc/limine-entry-tool.d drop-ins before regenerating the initramfs. The initrd is built from the configuration here, so hibernation is a swapDevices plus boot.resumeDevice change rather than this.";
    allow = "etc-write initrd-boot";
  };
  "omarchy-hw-vulkan" = {
    class = "patch";
    reason = "It looks in /usr/share/vulkan/icd.d, which does not exist on NixOS -- hardware.graphics puts the ICD manifests under /run/opengl-driver -- so it answered no Vulkan on every machine.";
  };
  "omarchy-install-font" = {
    class = "replace";
    reason = "Upstream runs `omarchy-pkg-add <package> && sleep 2 && omarchy-font-set`, so the && meant the switch never ran either. Asks fontconfig first, and defers to omarchy-pkg-add only if the family is absent; on the missing-font path with no terminal it reopens itself in one (#1304).";
  };
  "omarchy-install-gaming-retroarch" = {
    class = "patch";
    reason = "Nine /usr/share/libretro paths it writes into retroarch.cfg: core info, shaders and joypad autoconfig now point at the system profile, and the rest, which have none, at ~/.local/share/retroarch.";
  };
  "omarchy-install-gaming-xbox-controllers" = {
    class = "vendor";
    reason = "Vendored unchanged. Blacklists xpad in /etc/modprobe.d, loads hid_xpadneo, and adds $USER to the input group. All three are declarative here -- boot.blacklistedKernelModules, boot.kernelModules and extraGroups -- so the imperative run does not survive a rebuild.";
    allow = "account-tools etc-write modprobe";
  };
  "omarchy-install-hermes-cli" = {
    class = "vendor";
    reason = "Vendored unchanged. Stops omarchy-hermes-theme.service only after a --now set-up, before re-running the theme setter; stopping a user unit is session state and carries no configuration.";
    allow = "systemctl-user";
  };
  "omarchy-install-openclaw-cli" = {
    class = "vendor";
    reason = "Vendored unchanged. Stops, disables, queries and restarts the openclaw-<role> user units it installed; user-unit state, not configuration.";
    allow = "systemctl-user";
  };
  "omarchy-install-preinstalls" = {
    class = "replace";
    reason = "Upstream reseeds through omarchy-refresh-applications and its mise stubs, then exits on omarchy-pkg-add so the marker never clears. Seeds through nix-bin's omarchy-refresh-applications, writes no stubs, and clears the marker (#1304, #1319).";
  };
  "omarchy-install-service-1password" = {
    class = "patch";
    reason = "It drops a JSON stub into /usr/share/chromium/extensions with sudo; that is a store path here, so the write fails. Replaced by a message naming programs.chromium.extensions.";
  };
  "omarchy-install-service-nordvpn" = {
    class = "vendor";
    reason = "Vendored unchanged. `systemctl enable --now nordvpnd` plus `usermod -aG nordvpn`. data/apps.nix carries nordvpn as a package; the daemon and the group belong in the configuration, not in an enable call.";
    allow = "account-tools systemctl-system";
  };
  "omarchy-install-service-once" = {
    class = "vendor";
    reason = "Vendored unchanged. `systemctl enable --now once-background.service`, for a unit no module here defines, so the enable fails rather than half-succeeding.";
    allow = "systemctl-system";
  };
  "omarchy-install-service-sunshine" = {
    class = "vendor";
    reason = "Vendored unchanged. Opens ports with `ufw allow` and enables sunshine as a user unit. There is no ufw on this system -- modules/nixos.nix uses networking.firewall -- and no sunshine module, so both halves are imperative paths with no declarative counterpart yet.";
    allow = "systemctl-user ufw";
  };
  "omarchy-install-service-tailscale" = {
    class = "vendor";
    reason = "Vendored unchanged. Enables tailscaled.service and a user receive unit. modules/services/tailscale.nix already declares the daemon, so the system half duplicates a service the configuration owns.";
    allow = "systemctl-system systemctl-user";
  };
  "omarchy-launch-browser" = {
    class = "patch";
    reason = "It refuses a default browser entry that runs the launcher itself, which recursed without bound when a 4.0.4 session met 4.0.5's mimeapps list (#1342). The desktop-file search-path edit went with quattro 1381fa0, which reads XDG_DATA_DIRS (#1447).";
  };
  "omarchy-launch-editor" = {
    class = "patch";
    reason = "omarchy-default-editor saves `helix`, but nixpkgs' helix installs only `hx`, so the launcher's omarchy-cmd-present fell back to nvim. A saved `helix` is read as `hx` (#1303).";
  };
  "omarchy-launch-openclaw" = {
    class = "vendor";
    reason = "Vendored unchanged, and read-only: `systemctl --user is-enabled openclaw-gateway.service` decides whether to launch the gateway or the client.";
    allow = "systemctl-user";
  };
  "omarchy-launch-signal" = {
    class = "patch";
    reason = "It decides Signal is installed by testing `-x /usr/bin/signal-desktop`, never true here, so the menu offered to install an app already on PATH. Uses `command -v` and launches by name.";
  };
  "omarchy-launch-spotify" = {
    class = "patch";
    reason = "Same as omarchy-launch-signal: `-x /usr/bin/spotify` is never true on NixOS, so clicking Spotify offered to install it. Uses `command -v` and hands uwsm-app the bare name.";
  };
  "omarchy-launch-webapp" = {
    class = "patch";
    reason = "Three edits: the chromium-browser.desktop fallback name, `chromium*` added to the browser case, and quoting `$browser_exec` for uwsm-app. The search-path and no-browser edits went with quattro 1381fa0, which reads XDG_DATA_DIRS and refuses an empty browser itself (#1447); the `env -u BROWSER` edit went in 4.0.5.";
  };
  "omarchy-menu" = {
    class = "patch";
    reason = "`close` asks the menu to dismiss() over `shell call` before falling back to upstream's `shell hide`: hide reaches the menu's close(), which nixarchy-menu turns into dictation when voice is on (the hotkey's second tap), so a script that closed the menu started a recording (#1070). `call` exits 0 with \"unknown\" when the enabled menu has no dismiss(), so the reply is matched, not the status.";
  };
  "omarchy-menu-keybindings" = {
    class = "patch";
    reason = "Bound the Lua scan of a user's hyprland.lua to three seconds so a loop cannot leave a CPU pinned when the keybindings menu opens, and drop undescribed submap binds so a hint plugin's thousands of them cannot push the list past the 128 KiB argument limit (#1181).";
  };
  "omarchy-menu-select" = {
    class = "patch";
    reason = "Summon the menu with a 10 s IPC timeout instead of omarchy-shell's 2 s: from a key bind the shell answers later than that, and the script would exit and leave the menu it opened doing nothing (#1189).";
  };
  "omarchy-menu-timezone" = {
    class = "patch";
    reason = "timedatectl from a terminal-less menu row, with no sudoers rule, where time.timeZone is always set; notifies with the time.timeZone line and exits 1 (#1304).";
  };
  "omarchy-migrate" = {
    class = "replace";
    reason = "Upstream's 86 migration scripts use sudo, write under /usr and call pacman, and with no state directory every one counts as pending. --pending reports nothing to do; a bare run is told why.";
    pacman = "Ours, in pkgs/omarchy/nix-bin. The pacman line is heredoc prose or upstream code left dead after an early exit -- neither of which comment-stripping can see.";
  };
  "omarchy-mise-install" = {
    class = "patch";
    reason = "Writes no launcher when a command outside ~/.local/bin already provides the tool. Upstream's launchers sit ahead of the Nix profiles on PATH, so a Nix-installed codex or claude never ran (#707). Never removes or replaces an existing ~/.local/bin entry, which may be a home-manager link (#1319).";
  };
  "omarchy-mise-unshadow" = {
    class = "new";
    reason = "Not in upstream. Run on every activation: removes upstream's exact mise wrapper from ~/.local/bin when a Nix profile has the same command, for launchers written before omarchy-mise-install's patch (#707).";
  };
  "omarchy-openclaw-onboard" = {
    class = "vendor";
    reason = "Vendored unchanged, and read-only: reads MainPID off openclaw-gateway.service with `systemctl --user show`.";
    allow = "systemctl-user";
  };
  "omarchy-pkg-add" = {
    class = "replace";
    reason = "Upstream runs `sudo pacman -S`. Nothing is installed imperatively here, so this prints the nixpkgs name from a build-time table plus the declarative route, and exits non-zero.";
  };
  "omarchy-pkg-aur-add" = {
    class = "replace";
    reason = "Upstream installs from the AUR with yay. There is no AUR on NixOS, so this says where those packages come from instead and exits non-zero.";
  };
  "omarchy-pkg-aur-install" = {
    class = "replace";
    reason = "Upstream shows an fzf picker over `yay -Slqa` and installs the selection with yay. There is no AUR on NixOS, so this says so and points at the Install menu.";
  };
  "omarchy-pkg-drop" = {
    class = "vendor";
    reason = "Vendored unchanged. Reached from live menu rows; its pacman -Qq comes back empty here, so it drops nothing.";
    pacman = "Reached, and inert: `pacman -Qq` answers nothing on NixOS, so the -Rns branch never runs. The remove rows nixarchy has not ported are also kept hidden by the generator (`when = \"false\"`, #1301).";
  };
  "omarchy-pkg-install" = {
    class = "replace";
    reason = "Upstream offers a fuzzy picker over `pacman -Slq` and installs with `pacman -S`. Points at ~/.config/nixarchy/apps.nix and nixarchy-apply, since an imperative install would not survive a rebuild.";
  };
  "omarchy-pkg-missing" = {
    class = "replace";
    reason = "Same reason as omarchy-pkg-present: there is no package database to query, so this asks whether the command is runnable, with the -bin and -stable suffixes stripped. The stock menu does not call this command: its guard batch defines a function of the same name, which #1301 makes answer by the same rule, inside the shell.";
  };
  "omarchy-pkg-present" = {
    class = "replace";
    reason = "Upstream asks `pacman -Q`. There is no package database here, so the closest honest answer is whether the command is runnable; menu rows needing exactness check the app selection themselves. The stock menu does not call this command: its guard batch defines a function of the same name, which #1301 makes answer by the same rule, inside the shell.";
  };
  "omarchy-pkg-remove" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "A menu row modules/apps.nix overrides away, so nothing on this system reaches the pacman path inside it. The remove rows nixarchy has not ported are kept hidden by the generator (`when = \"false\"`, #1301) until #1304 ports them.";
  };
  "omarchy-plugin-clone" = {
    class = "patch";
    reason = "It copies a first-party plugin out of $OMARCHY_PATH with `cp -aL`, which preserves the store's read-only modes, so its staging directory could not be cleaned up and the clone never completed.";
  };
  "omarchy-plymouth-current" = {
    class = "replace";
    reason = "Upstream deduces the splash by comparing /usr/share/plymouth/themes/omarchy/logo.png with each theme's unlock.png, which does not exist here, so it printed nothing. Reads Theme= from plymouthd.conf.";
  };
  "omarchy-plymouth-set" = {
    class = "replace";
    reason = "Upstream stages a recoloured theme into /usr/share with sudo and rebuilds the initramfs with mkinitcpio. The initrd is built from the configuration here, so this names boot.plymouth and exits non-zero.";
  };
  "omarchy-provision-owner" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Reads pacman state for display only; nothing is installed or removed.";
    allow = "account-tools boot-write ctl-set etc-write initrd-boot";
  };
  "omarchy-provision-user" = {
    class = "patch";
    reason = "Two edits: `xdg-settings set default-web-browser chromium.desktop` exits 2 under `set -euo pipefail` and aborted provisioning, and the shipped HEY.desktop is installed prefixed as omarchy-HEY.desktop.";
  };
  "omarchy-refresh-applications" = {
    class = "replace";
    reason = "Upstream's cp -f replaces an edited launcher or a home-manager link, and it reruns install/user/mise.sh, whose stubs replaced a home-manager ~/.local/bin entry. Copies only missing launchers and runs no mise.sh; provisioning already runs it from install/user/all.sh (#1319).";
  };
  "omarchy-refresh-limine" = {
    class = "vendor";
    reason = "Vendored unchanged. Replaces /boot/limine.conf from the package default and runs limine-update and limine-snapper-sync. The bootloader here is generated from boot.loader, so this writes over a file nothing reads.";
    allow = "boot-write";
  };
  "omarchy-refresh-pacman" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
    allow = "etc-write";
  };
  "omarchy-refresh-plymouth" = {
    class = "replace";
    reason = "Upstream copies its theme into /usr/share/plymouth/themes with sudo and runs mkinitcpio. boot.plymouth.themePackages already puts it in the initrd, so this says so rather than failing on a cp.";
  };
  "omarchy-refresh-sddm" = {
    class = "replace";
    reason = "Upstream removes and re-copies the theme into /usr/share/sddm/themes with sudo. It ships inside the package at share/sddm/themes/omarchy and services.displayManager.sddm.theme already names it.";
  };
  "omarchy-reinstall-configs" = {
    class = "vendor";
    reason = "Vendored unchanged, and the etc-write match is a read -- `cp -af /etc/skel/. ~/` -- which is the acceptable over-match the pattern header names. /etc/skel is empty on NixOS, so it copies nothing.";
    allow = "etc-write";
  };
  "omarchy-reinstall-pkgs" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-reminder" = {
    class = "vendor";
    reason = "Vendored unchanged. Lists and stops the omarchy-reminder-*.timer user units it created itself, under ~/.config/systemd/user, which is the user's own tree rather than the system's.";
    allow = "systemctl-user";
  };
  "omarchy-remove-ai-hermes" = {
    class = "vendor";
    reason = "Vendored unchanged. Stops omarchy-hermes-theme.service on the way out; session state, no configuration.";
    allow = "systemctl-user";
  };
  "omarchy-remove-ai-openclaw" = {
    class = "vendor";
    reason = "Vendored unchanged. Disables the openclaw user units it installed under ~/.config/systemd/user, which is the user's own tree.";
    allow = "systemctl-user";
  };
  "omarchy-remove-browser" = {
    class = "patch";
    reason = "It writes chromium.desktop as the fallback default browser, a name nixpkgs does not use, and its `|| true` swallowed the failure -- so removing Chrome left a default resolving to nothing. Its Zen fallback compared against zen.desktop, which nixarchy's Zen does not install; it names zen-beta.desktop (#1303).";
    allow = "etc-write";
  };
  "omarchy-remove-gaming-xbox-controllers" = {
    class = "vendor";
    reason = "Vendored unchanged. Deletes the /etc/modprobe.d and /etc/modules-load.d files omarchy-install-gaming-xbox-controllers wrote. Neither exists here, because both settings are declarative.";
    allow = "etc-write modprobe";
  };
  "omarchy-remove-launcher-entry" = {
    class = "patch";
    reason = "Its last branch uninstalls a package-owned .desktop with `pacman -Qqo` and `pacman -Rns`, so the App Library said it did not know how. Only that dead end is replaced, with the apps.nix route.";
    pacman = "A menu row modules/apps.nix overrides away, so nothing on this system reaches the pacman path inside it.";
  };
  "omarchy-remove-preinstalls" = {
    class = "replace";
    reason = "Upstream deletes every web app and TUI launcher and rm -f's named ~/.local/bin entries whoever made them. Deletes only an unmodified, regular-file seed of a shipped web app or TUI, and only an exact omarchy-mise-install stub (#1304).";
  };
  "omarchy-remove-security-fido2" = {
    class = "patch";
    reason = "Its remove_pam_config seds /etc/pam.d/sudo, a symlink into /etc/static/pam.d that `sed -i` replaces with a stale regular file -- and its grep guard fires for anyone who set u2fAuth declaratively. The script exits 1 before dropping packages or deleting the registration (#1304). Its etc-write match is only the guidance text naming `sudo rm -rf /etc/fido2`; nothing here runs it.";
    allow = "etc-write";
  };
  "omarchy-remove-security-fingerprint" = {
    class = "patch";
    reason = "Same PAM edit as omarchy-remove-security-fido2: `sed -i` over a symlink into /etc/static/pam.d detaches the stack. The function goes, and the script exits 1 with the services.fprintd route before dropping packages or deleting the omarchy-lock file (#1304). quattro's remove_resume_hook deletes a /usr/lib sleep hook and an fprintd drop-in the build declares instead (#1288), so here it has nothing to remove.";
    allow = "etc-write";
  };
  "omarchy-remove-security-sshd" = {
    class = "vendor";
    reason = "Vendored unchanged. `systemctl disable --now sshd.service` and a `ufw delete` of the rate limit. services.openssh owns sshd here and there is no ufw, so neither half is the way this is turned off.";
    allow = "systemctl-system ufw";
  };
  "omarchy-remove-security-sudoless-docker" = {
    class = "patch";
    reason = "`gpasswd -d $USER docker` removes a group membership that users.users.<name>.extraGroups owns on NixOS; prints that route and exits 1 before any write (#1304).";
    allow = "account-tools";
  };
  "omarchy-remove-service-sunshine" = {
    class = "vendor";
    reason = "Vendored unchanged. The undo of omarchy-install-service-sunshine, imperative for the same two reasons: no ufw on this system, and no sunshine module to disable.";
    allow = "systemctl-user ufw";
  };
  "omarchy-remove-service-tailscale" = {
    class = "vendor";
    reason = "Vendored unchanged. Disables tailscaled.service, which modules/services/tailscale.nix declares, so the disable is undone by the next rebuild rather than by a mistake.";
    allow = "systemctl-system systemctl-user";
  };
  "omarchy-restart-audio" = {
    class = "vendor";
    reason = "Vendored unchanged. Restarts pipewire, pipewire-pulse and wireplumber as user units, which is session state and exactly what a restart command should do.";
    allow = "systemctl-user";
  };
  "omarchy-restart-bluetooth" = {
    class = "vendor";
    reason = "Vendored unchanged. `rfkill unblock bluetooth` and a `rfkill list`: runtime radio state, same as omarchy-bluetooth-power.";
    allow = "rfkill";
  };
  "omarchy-install-t3code-app" = {
    class = "patch";
    reason = "It ran the downloaded AppImage with --appimage-extract. On nixarchy an AppImage runs through appimage-run, which passes that flag to the app instead of extracting, so the install failed. The patch extracts with `appimage-run -x squashfs-root` (#1368).";
  };
  "omarchy-restart-shell" = {
    class = "patch";
    reason = "Resolve the running tree before stopping the shell, then launch the current-system tree through its absolute launcher path. Neither stopping nor relaunching depends on an inherited OMARCHY_PATH or PATH.";
    allow = "systemctl-user";
  };
  "omarchy-restart-terminal" = {
    class = "patch";
    reason = "It found kitty and ghostty with `pgrep -x kitty` and `killall`, which match a process's comm. nixpkgs wraps kitty, so the running process is .kitty-wrapped, and a wrapped ghostty is .ghostty-wrappe (comm is cut at 15 characters). Neither was signalled, so a theme change never reached them (#1370).";
  };
  "omarchy-restart-trackpad" = {
    class = "vendor";
    reason = "Vendored unchanged. `modprobe -r intel_quicki2c && modprobe intel_quicki2c` reloads one driver at runtime. That is a reload rather than configuration, and works here as it does upstream.";
    allow = "modprobe";
  };
  "omarchy-restart-wifi" = {
    class = "vendor";
    reason = "Vendored unchanged. `rfkill unblock wifi` and `nmcli radio wifi on`. NetworkManager is the network stack here too, so both calls do what they do upstream.";
    allow = "nmcli-radio rfkill";
  };
  "omarchy-restart-xcompose" = {
    class = "vendor";
    reason = "Vendored unchanged. Stops and starts omarchy-fcitx5.service, a user unit. modules/nixos.nix configures fcitx5, but the restart itself is session state.";
    allow = "systemctl-user";
  };
  "omarchy-retroarch-cores" = {
    class = "new";
    reason = "Not in upstream, which hardcodes /usr/lib/libretro. Resolves the core directory from the retroarch on PATH, because nixpkgs carries the cores inside the wrapper's own store path.";
  };
  "omarchy-setup-security-fido2" = {
    class = "patch";
    reason = "Its setup_pam_config seds NixOS-managed /etc/pam.d files and inserts a bare `pam_u2f.so`, which is inert here. pamu2fcfg registration stays; the PAM step names security.pam.u2f and exits non-zero.";
  };
  "omarchy-setup-security-fingerprint" = {
    class = "patch";
    reason = "Same as fido2: setup_pam_config and setup_lock_fingerprint_pam edit NixOS-managed PAM stacks. fprintd-enroll stays; the PAM step names services.fprintd and the fprintAuth options instead. The pacman install becomes the services.fprintd.enable line (#1304).";
  };
  "omarchy-setup-security-sshd" = {
    class = "vendor";
    reason = "Vendored unchanged. `systemctl enable --now sshd.service` and `ufw limit 22/tcp`. services.openssh and networking.firewall are the declarative route, and there is no ufw here for the second half to reach.";
    allow = "systemctl-system ufw";
  };
  "omarchy-setup-security-sudoless-docker" = {
    class = "patch";
    reason = "`usermod -aG docker $USER` adds a group membership that users.users.<name>.extraGroups owns on NixOS, and rootless Docker needs no group; prints that route and exits 1 before any write (#1304).";
    allow = "account-tools";
  };
  "omarchy-shell" = {
    class = "patch";
    reason = "Resolve the live shell by PID on the caller’s Wayland display through nixarchy-shell-session, independent of stale or collected caller trees. Refuse ambiguous instances rather than sending IPC to an arbitrary shell.";
  };
  "omarchy-shell-config" = {
    class = "patch";
    reason = "refresh_shell_config drops the rescanPlugins fallback (#901). When a shell still rebuilding its bar from the previous save missed the 2 s reloadConfig IPC timeout, upstream fell back to reloading every plugin; the shell applies the write through its own file watch anyway.";
  };
  "omarchy-snapshot" = {
    class = "replace";
    reason = "Upstream drives snapper through limine, which is neither the bootloader here nor packaged, and `@` holds almost no system anyway. Manual create snapshots /home; restore points to its files. A separate root snapshot at boot covers /var/lib, which this command can list but neither creates nor restores.";
  };
  "omarchy-sudo-passwordless" = {
    class = "replace";
    reason = "Upstream writes /etc/sudoers.d/99-omarchy-nopasswd-$USER, a directory /etc/sudoers does not include here, then reports success regardless. Names security.sudo.extraRules and exits non-zero.";
  };
  "omarchy-system-factory-reset" = {
    class = "replace";
    reason = "Upstream clones the Quattro ISO's @factory snapshot and then re-keys LUKS. This uses the nixarchy installer's @factory/@factory-home baseline, restores /home and /var/lib only, and stops if it is absent.";
  };
  "omarchy-system-factory-reset-finish" = {
    class = "vendor";
    reason = "Vendored unchanged. Runs as root from a sysinit unit and clears machine identity: userdel, the /etc/ssh host keys, NetworkManager connections, the sddm autologin drop-in and /etc/machine-id. Most of those paths are generated on NixOS, and the unit it removes itself from does not exist here.";
    allow = "account-tools etc-write";
  };
  "omarchy-theme-set" = {
    class = "patch";
    reason = "Three edits: `cp -r` from $OMARCHY_THEMES_PATH preserves the store's read-only directory modes, so the next switch cannot clean up; omarchy-theme-set-zed is appended, which upstream has no equivalent of; and the #1153 video-backgrounds backport (omacom/omarchy #6792, #12429) adds is_video_path and the staged-background lookups it needs, carried as a patch and deleted by the quattro bump with the rest of it.";
  };
  "omarchy-theme-set-browser-policy" = {
    class = "patch";
    reason = "New in 4.0.2, it escalates with sudo or pkexec, pins PATH to FHS directories and installs color.json as root under an /etc/sudoers.d rule naming /usr/bin. The escalation goes; the write is the user's.";
  };
  "omarchy-theme-set-vscode" = {
    class = "patch";
    reason = "Cursor was named as `/usr/bin/cursor`, which nixpkgs' code-cursor is not -- it ships bin/cursor. The guard is `command -v`, so an absolute path that does not exist skipped Cursor silently while VS Code, VSCodium and Insiders themed correctly. The Install menu offers Cursor, so this was user-visible with nothing printed. (#653)";
  };
  "omarchy-theme-set-zed" = {
    class = "new";
    reason = "Not in upstream, which ships theme setters for vscode, obsidian and others but none for Zed, pointing at the AUR's omazed instead -- which cannot work on v4. Reads the palette from colors.toml.";
  };
  "omarchy-toggle-crash-capture" = {
    class = "vendor";
    reason = "Vendored unchanged. Starts and stops omarchy-crash-watch.service, a user unit; session state, no configuration.";
    allow = "systemctl-user";
  };
  "omarchy-toggle-hybrid-gpu" = {
    class = "vendor";
    reason = "Vendored unchanged. Writes /etc/supergfxd.conf, edits it with `sed -i`, drops a unit override under /etc/systemd/system and enables supergfxd. Nothing here packages supergfxd and /etc/systemd/system is generated, so the whole path is Arch-only.";
    allow = "etc-write systemctl-system";
  };
  "omarchy-update" = {
    class = "replace";
    reason = "Upstream's updater prunes pacman packages, takes a snapper snapshot and refreshes the keyring, demanding 10 GiB before it starts. This moves the flake inputs forward with `nh os switch --update`.";
  };
  "omarchy-update-aur-pkgs" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-update-available" = {
    class = "replace";
    reason = "Upstream asks pacman and counts commits behind a git checkout of $OMARCHY_PATH, which here is a store path with no history. The replacement checks the installed flake lock against Nixarchy's release refs in one bounded Git call; the bar lights only for a proven newer release.";
  };
  "omarchy-update-firmware" = {
    class = "vendor";
    reason = "Vendored unchanged. `install -D /usr/lib/fwupd/efi/fwupdx64.efi /boot/EFI/arch/fwupdx64.efi` stages the fwupd EFI binary from a path that does not exist on NixOS, where services.fwupd owns this.";
    allow = "boot-write";
  };
  "omarchy-update-keyring" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-update-orphan-pkgs" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-update-pacman-guard" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available. Its whole job is PRINTING advice about pacman, so the word is the output rather than a call.";
  };
  "omarchy-update-restart" = {
    class = "patch";
    reason = "It infers a kernel change from /usr/lib/modules/*/vmlinuz and `pacman -Qo`; the glob matches nothing, so it prompted a reboot every time. Compares /run/booted-system with /run/current-system.";
  };
  "omarchy-update-system-pkgs" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-update-system-pkgs-when-conflicted" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-upgrade-to-quattro" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
    allow = "etc-write initrd-boot modprobe systemctl-system systemctl-user ufw";
  };
  "omarchy-upload-log" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Reads pacman state for display only; nothing is installed or removed.";
  };
  "omarchy-version" = {
    class = "patch";
    reason = "It reads the version from `pacman -Q omarchy` and treats an OMARCHY_PATH outside /usr/share as a git checkout, so it printed a bare `dev`. The build splices the real version in instead.";
    pacman = "Ours, in pkgs/omarchy/nix-bin. The pacman line is heredoc prose or upstream code left dead after an early exit -- neither of which comment-stripping can see.";
  };
  "omarchy-version-channel" = {
    class = "patch";
    reason = "It greps /etc/pacman.conf and the mirrorlist for Omarchy's mirrors to choose stable or edge; with no pacman both fell through to `unknown`. Prints `nixos-version` before the first grep.";
    pacman = "Ours, in pkgs/omarchy/nix-bin. The pacman line is heredoc prose or upstream code left dead after an early exit -- neither of which comment-stripping can see.";
  };
  "omarchy-version-pkgs" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Reads pacman state for display only; nothing is installed or removed.";
  };
  "omarchy-voxtype-config" = {
    class = "replace";
    reason = "Upstream runs `voxtype configure` in a floating terminal. voxtype is opt-in here, so the bar's Dictation click produced `voxtype: command not found`; this says how to enable it instead.";
  };
  "omarchy-windows-vm" = {
    class = "vendor";
    reason = "Vendored unchanged, and the modprobe match is prose: the two `sudo modprobe kvm-*` lines are inside the help text printed when KVM is unavailable, which comment-stripping cannot see. modules/nixos.nix loads the KVM modules declaratively.";
    allow = "modprobe";
  };
  "nixarchy-shell-session" = {
    class = "new";
    reason = "Resolve the live Quickshell process on the selected Wayland display and publish its tree and PATH to Hyprland, D-Bus and the systemd user manager, and offer a shell restart when a switch activated a different tree.";
    allow = "systemctl-user";
  };
  "omarchy-launch-shell" = {
    class = "patch";
    reason = "Synchronize the desktop environment after each supervised shell launch, including automatic relaunches.";
  };
  "omarchy-system-sleep-monitor" = {
    class = "patch";
    reason = "Use the packaged lock helper and re-execute the monitor itself instead of following an inherited tree across rebuilds.";
  };
  "omarchy-system-sleep-lock" = {
    class = "patch";
    reason = "Use the packaged IPC helper so a long-lived monitor can lock a shell from either generation without following stale PATH entries.";
  };
  "omarchy-dictation-superwhisper" = {
    class = "vendor";
    reason = "Vendored unchanged. Asks whether superwhisper.service, a user unit, is active before toggling it: session state, no configuration.";
    allow = "systemctl-user";
  };
  "omarchy-install-dictation-voxtype" = {
    class = "vendor";
    reason = "Vendored unchanged. Enables voxtype.service, a user unit the install writes under the user's own tree.";
    allow = "systemctl-user";
  };
  "omarchy-remove-dictation-superwhisper" = {
    class = "vendor";
    reason = "Vendored unchanged. Disables superwhisper.service, a user unit installed under the user's own tree, and asks whether fcitx5 is running.";
    allow = "systemctl-user";
  };
  "omarchy-remove-dictation-voxtype" = {
    class = "vendor";
    reason = "Vendored unchanged. Disables voxtype.service, a user unit installed under the user's own tree.";
    allow = "systemctl-user";
  };
  "omarchy-remove-service-ssh-agent" = {
    class = "vendor";
    reason = "Vendored unchanged. Disables the gcr-ssh-agent socket for this user; the enable symlink lives in the user's own tree, as on Arch.";
    allow = "systemctl-user";
  };
  "omarchy-setup-security-ssh-agent" = {
    class = "vendor";
    reason = "Vendored unchanged. Enables the gcr-ssh-agent socket for this user; the enable symlink lives in the user's own tree, as on Arch.";
    allow = "systemctl-user";
  };
  "omarchy-system-lid-inhibit" = {
    class = "vendor";
    reason = "Vendored unchanged. Starts and stops its own transient user unit to hold a lid-switch inhibitor: session state, no configuration.";
    allow = "systemctl-user";
  };
  "omarchy-lifecycle-dispatch" = {
    class = "patch";
    reason = "Patched (#1278 edge): first-run reaches it at every login, so its clean PATH and env -i are pointed at /run/current-system/sw. The /usr left is the aarch64-apple implementation path, which x86_64 never selects.";
    pacman = "Reads a platform package's pacman record, but only aarch64-apple registers any operation: on x86_64 every operation, including first-run's setup-user, is a no-op before that read.";
  };
  "omarchy-provision-hardware" = {
    class = "vendor";
    reason = "Vendored unchanged. Finishes hardware setup an Omarchy image build deferred; reached only from omarchy-apply-hardware, which only the ISO's provisioning service and omarchy-apply-system call. nixarchy runs neither.";
    pacman = "The image build's keyring and package steps, on the same unreachable path.";
    allow = "initrd-boot modprobe";
  };
  "omarchy-update-pacman" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Called only by omarchy-update-system-pkgs, -refresh-pacman, -reinstall-pkgs and -channel-set. pkgs/omarchy/nix-bin replaces the update entry points and modules/apps.nix overrides the Channel rows, so none reaches it.";
  };
  "omarchy-kernel" = {
    class = "vendor";
    reason = "Vendored unchanged (#1423, quattro be54892). Switches the kernel Limine boots by default, through /etc/default/limine and an initramfs rebuild: Arch-only. Its one caller, the Update > Kernel menu row, shows only when `omarchy-kernel list` prints more than one kernel, and that list reads /usr/lib/modules/*/pkgbase, which NixOS does not have -- so the row never appears and nothing reaches `set`.";
    allow = "initrd-boot";
  };
  "omarchy-remove-ai-ollama" = {
    class = "vendor";
    reason = "Vendored unchanged. Reached only by upstream's remove.ai.ollama row, which modules/apps.nix hides: Ollama here is services.ollama under programs.nixarchy.localAi, and disabling its unit by hand would only last until the next switch.";
    allow = "systemctl-system";
  };
  "omarchy-font-cjk" = {
    class = "patch";
    reason = "Patched (#1278 edge): runs its stdlib-only Python helper with nixpkgs' python3, not /usr/bin/python3.";
  };
  "omarchy-hw-platform" = {
    class = "patch";
    reason = "Patched (#1278 edge): re-execs itself under /run/current-system/sw's env and bash with that PATH; /bin/bash and /usr/bin hold nothing here.";
  };
  "omarchy-input-method" = {
    class = "patch";
    reason = "Patched (#1278 edge): runs its stdlib-only Python helper with nixpkgs' python3, not /usr/bin/python3.";
  };
  "omarchy-locale-generate" = {
    class = "patch";
    reason = "Upstream uncomments /etc/locale.gen and runs locale-gen as root. NixOS builds locales with the system (i18n.extraLocales), so this refuses and names nixarchy-language-select (#1289).";
  };
  "omarchy-language" = {
    class = "patch";
    reason = "Patched (#1278 edge): its Python helper runs with nixpkgs' python3. A locale the system has not built is recorded with nixarchy-language-select for the next rebuild, and the switch stops before LANG changes, instead of running locale-gen as root (#1289).";
  };
  "omarchy-setup-input" = {
    class = "patch";
    reason = "Patched (#1278 edge): runs its stdlib-only Python helper with nixpkgs' python3, not /usr/bin/python3.";
  };
  "omarchy-setup-keyboard" = {
    class = "patch";
    reason = "Patched (#1278 edge): runs its stdlib-only Python helper with nixpkgs' python3, not /usr/bin/python3.";
  };
  "omarchy-theme-set-fcitx5" = {
    class = "patch";
    reason = "Patched (#1278 edge): the packaged fcitx5 theme default points at /run/current-system/sw/share.";
  };
}
