# Every command this port does not ship verbatim, and why.
#
# Omarchy is 444 commands. This port ships all of them and 10 of its own, and
# 386 of the 444 are byte-identical below the shebang -- patchShebangs rewrites
# line 1 and nothing else touches them. So the interesting surface is the 58
# rows here, and CI derives the rest rather than trusting a hand list.
#
# ## The rule that keeps this file honest
#
# A vendored command does NOT get a row. A row is a CLAIM that the shipped file
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
  "nixarchy-ask" = {
    class = "new";
    reason = "Not in upstream. Wraps omarchy-agent-prompt with prompts that name the skill and insist on measure-then-propose, so routing is fixed here rather than re-guessed on every invocation.";
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
  "nixarchy-rollback" = {
    class = "new";
    reason = "Not in upstream, whose undo is omarchy-snapshot via snapper and limine. Lists and switches NixOS system generations, which are the bootable snapshot every rebuild already leaves behind.";
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
  "omarchy-apply-lock" = {
    class = "patch";
    reason = "Its root PATH reset points at /usr/bin, which holds nothing here, so it lost tee and getent while writing lock-screen PAM files; and its `-x /usr/bin/fprintd-list` probe was never true.";
  };
  "omarchy-audio-tuning" = {
    class = "patch";
    reason = "It tests for the LSP limiter at a fixed path under /usr/lib/lv2. NixOS keeps LV2 plugins in the store and points hosts at them with LV2_PATH, so the search is over LV2_PATH and the system profile.";
  };
  "omarchy-clipboard-open" = {
    class = "patch";
    reason = "It execs tensaku-edit, which is packaged nowhere here, so the image editor is pointed at the satty-edit wrapper instead.";
  };
  "omarchy-cursor-set" = {
    class = "new";
    reason = "Not in upstream, which sets a cursor size but never a theme, because on Arch one arrives with the desktop packages. Picks Bibata Ice or Classic from the mode in the theme's colors.toml.";
  };
  "omarchy-default-agent" = {
    class = "replace";
    reason = "Upstream installs the agent with `mise use -g`: imperative, its shims only reach an interactive shell (the menu launches through `bash -c`), and its npm backend needs a node that is not in this closure.";
  };
  "omarchy-default-browser" = {
    class = "patch";
    reason = "It names chromium.desktop, which nixpkgs calls chromium-browser.desktop, so setting the browser exited 1 having set nothing and the no-argument read printed the raw desktop id.";
  };
  "omarchy-games-retro-cores" = {
    class = "replace";
    reason = "Upstream filters a hardcoded list of 23 preferred cores against /usr/lib/libretro. Lists whatever the built retroarch package actually carries, labelled from libretro-core-info.";
  };
  "omarchy-games-retro-install" = {
    class = "patch";
    reason = "It hardcodes /usr/lib/libretro. nixpkgs puts the cores inside the retroarch wrapper's own store path, so the directory is resolved at runtime with `omarchy-retroarch-cores`.";
  };
  "omarchy-hw-vulkan" = {
    class = "patch";
    reason = "It looks in /usr/share/vulkan/icd.d, which does not exist on NixOS -- hardware.graphics puts the ICD manifests under /run/opengl-driver -- so it answered no Vulkan on every machine.";
  };
  "omarchy-install-font" = {
    class = "replace";
    reason = "Upstream runs `omarchy-pkg-add <package> && sleep 2 && omarchy-font-set`, so the && meant the switch never ran either. Asks fontconfig first, and defers to omarchy-pkg-add only if the family is absent.";
  };
  "omarchy-install-gaming-retroarch" = {
    class = "patch";
    reason = "Nine /usr/share/libretro paths it writes into retroarch.cfg: core info, shaders and joypad autoconfig now point at nixpkgs packages, and the rest, which have none, at ~/.local/share/retroarch.";
  };
  "omarchy-install-service-1password" = {
    class = "patch";
    reason = "It drops a JSON stub into /usr/share/chromium/extensions with sudo; that is a store path here, so the write fails. Replaced by a message naming programs.chromium.extensions.";
  };
  "omarchy-launch-browser" = {
    class = "patch";
    reason = "It reads the browser's .desktop from {~/.local,~/.nix-profile,/usr}/share/applications. On NixOS those live under /run/current-system/sw and /etc/profiles/per-user, so the lookup found nothing.";
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
    reason = "Four edits: the desktop-file search paths, the chromium-browser.desktop fallback name, `chromium*` added to the browser case, and `env -u BROWSER` around xdg-settings -- the last upstream's own bug.";
  };
  "omarchy-migrate" = {
    class = "replace";
    reason = "Upstream's 86 migration scripts use sudo, write under /usr and call pacman, and with no state directory every one counts as pending. --pending reports nothing to do; a bare run is told why.";
    pacman = "Ours, in pkgs/omarchy/nix-bin. The pacman line is heredoc prose or upstream code left dead after an early exit -- neither of which comment-stripping can see.";
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
  "omarchy-pkg-install" = {
    class = "replace";
    reason = "Upstream offers a fuzzy picker over `pacman -Slq` and installs with `pacman -S`. Points at ~/.config/nixarchy/apps.nix and nixarchy-apply, since an imperative install would not survive a rebuild.";
  };
  "omarchy-pkg-missing" = {
    class = "replace";
    reason = "Same reason as omarchy-pkg-present: there is no package database to query, so this asks whether the command is runnable, with the -bin and -stable suffixes stripped.";
  };
  "omarchy-pkg-present" = {
    class = "replace";
    reason = "Upstream asks `pacman -Q`. There is no package database here, so the closest honest answer is whether the command is runnable; menu rows needing exactness check the app selection themselves.";
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
  "omarchy-provision-user" = {
    class = "patch";
    reason = "Two edits: `xdg-settings set default-web-browser chromium.desktop` exits 2 under `set -euo pipefail` and aborted provisioning, and the shipped HEY.desktop is installed prefixed as omarchy-HEY.desktop.";
  };
  "omarchy-refresh-applications" = {
    class = "patch";
    reason = "Its two copies land 17 desktop files at the store's 444, so the next run cannot rewrite them; under `set -euo pipefail` that aborted omarchy-provision-user before it marked finalize-user.";
  };
  "omarchy-refresh-plymouth" = {
    class = "replace";
    reason = "Upstream copies its theme into /usr/share/plymouth/themes with sudo and runs mkinitcpio. boot.plymouth.themePackages already puts it in the initrd, so this says so rather than failing on a cp.";
  };
  "omarchy-refresh-sddm" = {
    class = "replace";
    reason = "Upstream removes and re-copies the theme into /usr/share/sddm/themes with sudo. It ships inside the package at share/sddm/themes/omarchy and services.displayManager.sddm.theme already names it.";
  };
  "omarchy-remove-browser" = {
    class = "patch";
    reason = "It writes chromium.desktop as the fallback default browser, a name nixpkgs does not use, and its `|| true` swallowed the failure -- so removing Chrome left a default resolving to nothing.";
  };
  "omarchy-remove-launcher-entry" = {
    class = "patch";
    reason = "Its last branch uninstalls a package-owned .desktop with `pacman -Qqo` and `pacman -Rns`, so the App Library said it did not know how. Only that dead end is replaced, with the apps.nix route.";
    pacman = "A menu row modules/apps.nix overrides away, so nothing on this system reaches the pacman path inside it.";
  };
  "omarchy-remove-security-fido2" = {
    class = "patch";
    reason = "Its remove_pam_config seds /etc/pam.d/sudo, a symlink into /etc/static/pam.d that `sed -i` replaces with a stale regular file -- and its grep guard fires for anyone who set u2fAuth declaratively.";
  };
  "omarchy-remove-security-fingerprint" = {
    class = "patch";
    reason = "Same PAM edit as omarchy-remove-security-fido2: `sed -i` over a symlink into /etc/static/pam.d detaches the stack. The function goes; dropping the packages and the omarchy-lock file stays.";
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
    reason = "Same as fido2: setup_pam_config and setup_lock_fingerprint_pam edit NixOS-managed PAM stacks. fprintd-enroll stays; the PAM step names services.fprintd and the fprintAuth options instead.";
    pacman = "A menu row modules/apps.nix overrides away, so nothing on this system reaches the pacman path inside it.";
  };
  "omarchy-snapshot" = {
    class = "replace";
    reason = "Upstream drives snapper through limine, which is neither the bootloader here nor packaged, and `@` holds almost no system anyway. Snapshots /home and /var/lib, and restores from the running system.";
  };
  "omarchy-sudo-passwordless" = {
    class = "replace";
    reason = "Upstream writes /etc/sudoers.d/99-omarchy-nopasswd-$USER, a directory /etc/sudoers does not include here, then reports success regardless. Names security.sudo.extraRules and exits non-zero.";
  };
  "omarchy-system-factory-reset" = {
    class = "replace";
    reason = "Upstream clones the Quattro ISO's @factory snapshot and then re-keys LUKS. This uses the nixarchy installer's @factory/@factory-home baseline, restores /home and /var/lib only, and stops if it is absent.";
  };
  "omarchy-theme-set" = {
    class = "patch";
    reason = "Two edits: `cp -r` from $OMARCHY_THEMES_PATH preserves the store's read-only directory modes, so the next switch cannot clean up; and omarchy-theme-set-zed is appended, which upstream has no equivalent of.";
  };
  "omarchy-theme-set-browser-policy" = {
    class = "patch";
    reason = "New in 4.0.2, it escalates with sudo or pkexec, pins PATH to FHS directories and installs color.json as root under an /etc/sudoers.d rule naming /usr/bin. The escalation goes; the write is the user's.";
  };
  "omarchy-theme-set-zed" = {
    class = "new";
    reason = "Not in upstream, which ships theme setters for vscode, obsidian and others but none for Zed, pointing at the AUR's omazed instead -- which cannot work on v4. Reads the palette from colors.toml.";
  };
  "omarchy-update" = {
    class = "replace";
    reason = "Upstream's updater prunes pacman packages, takes a snapper snapshot and refreshes the keyring, demanding 10 GiB before it starts. This moves the flake inputs forward with `nh os switch --update`.";
  };
  "omarchy-update-available" = {
    class = "replace";
    reason = "Upstream asks pacman and counts commits behind a git checkout of $OMARCHY_PATH, which here is a store path with no history. Exits 1, because the bar widget lights up on exit 0 alone.";
  };
  "omarchy-update-restart" = {
    class = "patch";
    reason = "It infers a kernel change from /usr/lib/modules/*/vmlinuz and `pacman -Qo`; the glob matches nothing, so it prompted a reboot every time. Compares /run/booted-system with /run/current-system.";
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
  "omarchy-voxtype-config" = {
    class = "replace";
    reason = "Upstream runs `voxtype configure` in a floating terminal. voxtype is opt-in here, so the bar's Dictation click produced `voxtype: command not found`; this says how to enable it instead.";
  };
  "omarchy-channel-current" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-channel-set" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-debug" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Reads pacman state for display only; nothing is installed or removed.";
  };
  "omarchy-dev-pkg-test" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Development tooling, not on any user path.";
  };
  "omarchy-pkg-drop" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "A menu row modules/apps.nix overrides away, so nothing on this system reaches the pacman path inside it.";
  };
  "omarchy-pkg-remove" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "A menu row modules/apps.nix overrides away, so nothing on this system reaches the pacman path inside it.";
  };
  "omarchy-provision-owner" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Reads pacman state for display only; nothing is installed or removed.";
  };
  "omarchy-refresh-pacman" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-reinstall-pkgs" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
  };
  "omarchy-remove-dev-env" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "A menu row modules/apps.nix overrides away, so nothing on this system reaches the pacman path inside it.";
  };
  "omarchy-update-aur-pkgs" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Update, channel, keyring and mirror plumbing. Unreachable here because pkgs/omarchy/nix-bin replaces the entry points the UI calls -- omarchy-update and omarchy-update-available.";
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
  };
  "omarchy-upload-log" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Reads pacman state for display only; nothing is installed or removed.";
  };
  "omarchy-version-pkgs" = {
    class = "vendor";
    reason = "Vendored unchanged. This row exists only to record why an Arch-only package path is carried and unreachable -- see `pacman` below.";
    pacman = "Reads pacman state for display only; nothing is installed or removed.";
  };
}
