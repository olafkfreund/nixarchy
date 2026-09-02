#!/usr/bin/env bash
# What to change before adding nixarchy to a machine you already run.
#
# Reads the running system and prints the configuration it would need. Changes
# nothing: every conflict nixarchy can cause is an evaluation failure, so the
# cost of finding out the hard way is a failed rebuild rather than a broken
# machine -- but a failed rebuild with five errors in it is a bad first
# impression, and they are all knowable in advance.
#
# Deliberately inspects the live system rather than evaluating a flake: this
# has to be useful *before* nixarchy is an input, and `nix run` on a flake that
# is not yet imported anywhere is the only entry point a new user has.
set -uo pipefail

sw=/run/current-system/sw
sessions=$sw/share/wayland-sessions
config_home=${XDG_CONFIG_HOME:-$HOME/.config}

bold=$(printf '\033[1m')
dim=$(printf '\033[2m')
warn=$(printf '\033[33m')
ok=$(printf '\033[32m')
off=$(printf '\033[0m')

say() { printf '%s\n' "$*"; }
finding() { printf '  %s%s%s %s\n' "$2" "$1" "$off" "$3"; }

# Every line that has to go into their configuration, collected as we go and
# printed together at the end -- a snippet to paste beats a list of prose
# instructions to translate.
declare -a snippet=()
declare -a notes=()

say ""
say "${bold}nixarchy: what this machine needs${off}"
say "${dim}Reading the running system. Nothing is modified.${off}"
say ""

# ---- Hyprland ------------------------------------------------------------
# programs.hyprland.package is the one option nixarchy sets outright rather
# than with mkDefault: nixpkgs defines it at mkDefault priority, so matching
# that ties instead of yielding. Anyone who already sets it therefore collides.
say "${bold}Compositor${off}"
if [ -e "$sessions/hyprland.desktop" ]; then
  # No `... | grep | head` here. writeShellApplication runs this under
  # `set -euo pipefail`, and `head -1` exiting first sends SIGPIPE up the
  # pipeline, which pipefail turns into a failure and errexit turns into a
  # dead script -- this one stopped after printing "Compositor". It survived
  # by luck on a workstation where grep finished before head closed the pipe.
  hypr_bin=$(sed -n 's/^Exec=//p' "$sessions/hyprland.desktop" | awk '{print $1}')
  # Read from the store path rather than by running the binary: Hyprland
  # --version wants more of a session than this has, and answered "unknown
  # version" on a machine whose Hyprland was plainly installed. The path
  # carries it: /nix/store/...-hyprland-0.56.0+date=...
  hypr_ver=$(
    awk 'match($0, /hyprland-[0-9]+\.[0-9]+\.[0-9]+/) {
           print substr($0, RSTART + 9, RLENGTH - 9); exit
         }' <<<"$hypr_bin"
  )
  finding "Hyprland already configured" "$warn" "(${hypr_ver:-unknown version})"
  say "     nixarchy pins its own Hyprland and does not defer, so this collides."
  snippet+=(
    "  # You already set programs.hyprland.package; nixarchy sets it too, and"
    "  # neither defers. Keep yours -- anything from 0.55 satisfies nixarchy."
    "  programs.hyprland.package = lib.mkForce pkgs.hyprland;"
    "  programs.hyprland.portalPackage = lib.mkForce pkgs.xdg-desktop-portal-hyprland;"
  )
  case "$hypr_ver" in
    "" ) notes+=("Could not read your Hyprland version; nixarchy needs >= 0.55.") ;;
    0.5[0-4]* | 0.[0-4]* )
      notes+=("Your Hyprland ${hypr_ver} is older than the 0.55 Lua API Omarchy is written against. Nixarchy will refuse to evaluate until you move up, or drop the mkForce and take its pin.") ;;
  esac
else
  finding "No Hyprland yet" "$ok" "nixarchy brings its own"
fi
say ""

# ---- the greeter ---------------------------------------------------------
say "${bold}Display manager${off}"
# NixOS puts sddm, gdm, lightdm and ly behind one display-manager.service and
# names the actual greeter only in its ExecStart -- so asking for sddm.service
# told a machine running SDDM that it had no display manager at all. greetd
# does get a unit of its own.
found_dm=""
# is-active as well as is-enabled: a NixOS display-manager.service can report
# "static", which is not an enabled state, and asking only is-enabled reported
# "No display manager" on a machine that was greeting through SDDM right then.
dm_on() { systemctl is-enabled "$1" >/dev/null 2>&1 || systemctl is-active "$1" >/dev/null 2>&1; }

if dm_on greetd.service; then
  found_dm=greetd
elif dm_on display-manager.service; then
  # The whole unit, not just ExecStart: NixOS wraps the greeter, so the name
  # can be in an Environment= or a script path rather than the exec line, and
  # matching only ExecStart left this reporting "a display manager" on a
  # machine plainly running SDDM.
  exec_line=$(systemctl cat display-manager.service 2>/dev/null || true)
  for dm in sddm gdm lightdm ly; do
    case "$exec_line" in
      *"$dm"*)
        found_dm=$dm
        break
        ;;
    esac
  done
  [ -n "$found_dm" ] || found_dm="a display manager"
fi
if [ -n "$found_dm" ] && [ "$found_dm" != sddm ]; then
  finding "$found_dm is greeting" "$warn" ""
  say "     Two display managers is not a working configuration."
  snippet+=(
    "  # $found_dm already greets; nixarchy's SDDM would be a second one."
    "  # Your greeter picks up the \"Omarchy\" session from wayland-sessions."
    "  programs.nixarchy.displayManager = false;"
  )
elif [ "$found_dm" = sddm ]; then
  finding "SDDM is greeting" "$ok" "nixarchy themes it"
else
  finding "No display manager" "$ok" "nixarchy enables SDDM"
fi
say ""

# ---- the Hyprland config -------------------------------------------------
# The seed never overwrites a file the user owns, so an existing hyprland.lua
# is kept and Omarchy's is not installed. The session entry is what makes that
# survivable, and it is on by default -- this is here to say so, because the
# failure it prevents is silent.
say "${bold}Hyprland config${off}"
if [ -e "$config_home/hypr/hyprland.lua" ]; then
  if [ -L "$config_home/hypr/hyprland.lua" ]; then
    finding "$config_home/hypr/hyprland.lua is managed" "$warn" "(a symlink -- home-manager, probably)"
  else
    finding "$config_home/hypr/hyprland.lua exists" "$warn" "(your own file)"
  fi
  say "     nixarchy will not overwrite it, so Omarchy's own config is not"
  say "     installed. Log in through the ${bold}Omarchy${off} session instead: it runs"
  say "     Hyprland against Omarchy's config with --config and needs no file"
  say "     of yours. It is registered by default."
  notes+=("Both sessions share ~/.config/hypr/{monitors,input,bindings,looknfeel,autostart}.lua. Omarchy's bootstrap builds Hyprland's Lua module path from \$HOME/.config and nothing else, so only the entry point differs. Editing those changes both.")
else
  finding "No Hyprland config" "$ok" "Omarchy's is installed as-is"
fi
say ""

# ---- the boot splash -----------------------------------------------------
# nixarchy sets boot.plymouth.theme to its own, with mkDefault. Anyone who
# already chose one keeps it and needs no mkForce -- but they will not get
# Omarchy's splash either, and finding that out at the next boot rather than
# here is the sort of surprise this script exists to prevent.
say "${bold}Boot splash${off}"
plymouth_theme=$( (grep -h '^Theme=' /etc/plymouth/plymouthd.conf 2>/dev/null |
  head -1 | cut -d= -f2) || true)
if [ -n "$plymouth_theme" ]; then
  finding "Plymouth is showing '$plymouth_theme'" "$warn" ""
  say "     nixarchy defaults boot.plymouth.theme to its own splash, so yours"
  say "     wins and nothing collides. To take Omarchy's instead:"
  say "       programs.nixarchy.bootSplash = \"force\";"
  notes+=("Your Plymouth theme '${plymouth_theme}' is kept -- nixarchy only defaults its own. programs.nixarchy.bootSplash = \"force\" takes Omarchy's instead; mkForce on boot.plymouth.theme alone fails the build, because themePackages stays yours and the named theme is then missing from it.")
else
  finding "No Plymouth theme set" "$ok" "you get Omarchy's splash"
fi
say ""

# ---- is the running session actually on the installed build? -------------
# A rebuild cannot change the environment of a graphical session that is
# already running. OMARCHY_PATH and PATH are set at login and keep pointing at
# whichever store path was current then, so every omarchy-* command the session
# runs -- every keybinding, every menu row -- comes from the old package until
# the user logs out and back in.
#
# On Arch this cannot happen: the files live at a fixed /usr/share/omarchy that
# is overwritten in place, so a running session picks up a new version
# immediately. Here the path itself changes, which is why this needs saying.
#
# It cost an evening to find. A web-app keybinding kept failing after the bug
# behind it had been fixed and the system rebuilt, because the session was
# still executing the previous build's copy of the script.
if [ -n "${OMARCHY_PATH:-}" ] && [ -e "$sw/bin/omarchy" ]; then
  say "${bold}Session${off}"
  installed=$(readlink -f "$sw/bin/omarchy" | sed 's|/bin/omarchy$||')
  if [ "$OMARCHY_PATH" != "$installed" ]; then
    finding "This session is running an older build" "$warn" ""
    say "     ${dim}session:   $OMARCHY_PATH${off}"
    say "     ${dim}installed: $installed${off}"
    say "     Log out and back in. A rebuild cannot change a running session's"
    say "     environment, so until you do, every keybinding and menu row still"
    say "     runs the old package -- including anything you just fixed."
    notes+=("Your session's OMARCHY_PATH points at an older store path than the installed package. Log out and back in; until then every omarchy-* command the desktop runs comes from the previous build, which is the usual reason a fix 'did not work'.")
  else
    finding "Session is on the installed build" "$ok" ""
  fi
  say ""
fi

# ---- snapper configured against a layout that cannot hold a snapshot -----
# Only ever true on a machine the nixarchy installer built: services.snapper is
# set in installer/host.nix, which nothing but a generated flake imports. Such
# a machine pulls the current host.nix at its next rebuild -- but its
# disk-config.nix is a verbatim copy in its own repo, made at install time, and
# a copy made before @snapshots existed does not grow one. disko runs once.
#
# So snapper is configured, its timers fire, and nothing is snapshotted: the
# NixOS module does not create the `.snapshots` directories itself
# (nixpkgs#34595, PR #368449 unmerged). The owner has a safety net in the menu
# and none on the disk, which is worse than having neither, and they find out
# at the moment they reach for it.
#
# Read from /proc/self/mountinfo rather than findmnt: this script's runtime
# inputs are systemd, sed, grep, awk and coreutils, and util-linux is not among
# them.
mounted_btrfs() {
  awk -v target="$1" '
    { for (i = 7; i <= NF; i++) if ($i == "-") { if ($5 == target && $(i + 1) == "btrfs") found = 1 } }
    END { exit !found }
  ' /proc/self/mountinfo
}

# Keyed on the snapper configs installer/host.nix declares, so this stays
# silent on every machine that has no snapper -- which is every machine reading
# this report to decide whether to adopt nixarchy.
if [ -d /etc/snapper/configs ] && [ -n "$(ls -A /etc/snapper/configs 2>/dev/null)" ]; then
  declare -a no_snapshots=()
  [ ! -e /etc/snapper/configs/root ] || mounted_btrfs /.snapshots || no_snapshots+=(/.snapshots)
  [ ! -e /etc/snapper/configs/home ] || mounted_btrfs /home/.snapshots || no_snapshots+=(/home/.snapshots)

  say "${bold}Snapshots${off}"
  if [ ${#no_snapshots[@]} -gt 0 ]; then
    finding "snapper is configured and snapshotting nothing" "$warn" ""
    say "     ${dim}not a mounted subvolume: ${no_snapshots[*]}${off}"
    say "     Snapper writes into those and cannot create them. This machine was"
    say "     installed before the disk layout declared them, so the timers have"
    say "     been running against a layout with nowhere to put a snapshot."
    say "     Nothing is lost -- but nothing was kept. The fix, in this order:"
    say ""
    root_source=$(awk '$5 == "/" { for (i = 7; i <= NF; i++) if ($i == "-") { print $(i + 2); exit } }' /proc/self/mountinfo)
    say "       ${dim}sudo mount -o subvol=/ ${root_source:-<your root device>} /mnt${off}"
    say "       ${dim}sudo btrfs subvolume create /mnt/@snapshots${off}"
    say "       ${dim}sudo btrfs subvolume create /mnt/@home-snapshots${off}"
    say "       ${dim}sudo umount /mnt${off}"
    say ""
    say "     Then declare them in ${bold}/etc/nixos/disk-config.nix${off} -- your copy, which"
    say "     nothing but you maintains -- inside its ${dim}subvolumes${off} block:"
    say ""
    say "       ${dim}\"@snapshots\" = { mountpoint = \"/.snapshots\"; mountOptions = [ \"noatime\" ]; };${off}"
    say "       ${dim}\"@home-snapshots\" = { mountpoint = \"/home/.snapshots\"; mountOptions = [ \"noatime\" ]; };${off}"
    say ""
    say "     and rebuild -- ${dim}nh os switch${off} -- which is what mounts them. That"
    say "     order matters: a mount unit for a subvolume that does not exist"
    say "     fails at boot. ${dim}omarchy snapshot${off} prints the same fix and refuses"
    say "     to pretend until it is done."
    notes+=("snapper is configured on this machine but ${no_snapshots[*]} is not a mounted btrfs subvolume, so every snapshot it has 'taken' went nowhere. The subvolumes are created by hand once -- disko ran at install time only -- and declared in your own disk-config.nix so the next reinstall keeps them.")
  else
    finding "snapper has its subvolumes" "$ok" "/home is being snapshotted"
  fi
  say ""
fi

# ---- the default browser, and whether the menu can change it -------------
# Setup > Default browser runs omarchy-default-browser, which ends in
#
#   env -u BROWSER xdg-settings set default-web-browser "$desktop_id" || exit 1
#
# On a machine where mimeapps.list is a store symlink -- which is what
# xdg.mimeApps in Home Manager produces, and the right way to declare this --
# xdg-settings writes "Read-only file system" to stderr and STILL EXITS 0. The
# `|| exit 1` never fires, the menu reports success, and the default does not
# change. Nothing is broken and nothing says so, which is the only reason this
# is worth a section: the failure is silent, and the fix lives in a file the
# menu cannot reach.
#
# Only the two paths xdg-utils actually consults are checked. ~/.local/share/
# mimeapps.list is NOT one of them -- it looks plausible and is never read.
say "${bold}Default browser${off}"
managed_mime=""
for f in "$config_home/mimeapps.list" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/applications/mimeapps.list"; do
  if [ -L "$f" ] && case "$(readlink -f "$f")" in /nix/store/*) true ;; *) false ;; esac; then
    managed_mime="$f"
    break
  fi
done

if [ -n "$managed_mime" ]; then
  finding "${managed_mime/#$HOME/\~} is store-managed" "$warn" "(home-manager, probably)"
  say "     That is the correct way to declare it, and it means ${bold}Setup >${off}"
  say "     ${bold}Default browser${off} cannot change it: xdg-settings fails on the"
  say "     read-only file, exits 0 anyway, and the menu reports success while"
  say "     nothing happens. Set it where it is declared instead:"
  say "       xdg.mimeApps.defaultApplications.\"x-scheme-handler/https\" = \"firefox.desktop\";"
  notes+=("Your mimeapps.list is a store symlink, so 'omarchy default browser' and any 'xdg-settings set' report success and change nothing. Declare the handler in xdg.mimeApps.defaultApplications; it is the same setting, in the place that survives a rebuild.")
else
  current_browser=$(env -u BROWSER xdg-settings get default-web-browser 2>/dev/null || true)
  if [ -n "$current_browser" ]; then
    finding "Default browser is $current_browser" "$ok" "the menu can change it"
  else
    finding "No default browser set" "$warn" ""
    say "     Web app keybindings -- Email, Calendar -- resolve the browser"
    say "     through it, and fall back to chromium without one."
  fi
fi

# $BROWSER makes `xdg-settings get` skip the mime database entirely: it treats
# the value as a command name and returns the first .desktop under
# ~/.local/share/applications whose Exec matches. A Chrome user has one of
# those per installed web app, so this reliably answers with whichever web app
# sorts first. Observed on a real machine: it named a Lidarr web app, and every
# web app keybinding opened that instead of a browser.
if [ -n "${BROWSER:-}" ]; then
  browser_via_env=$(xdg-settings get default-web-browser 2>/dev/null || true)
  browser_via_mime=$(env -u BROWSER xdg-settings get default-web-browser 2>/dev/null || true)
  if [ -n "$browser_via_env" ] && [ "$browser_via_env" != "$browser_via_mime" ]; then
    finding "\$BROWSER=$BROWSER is shadowing it" "$warn" ""
    say "     xdg-settings answers ${bold}$browser_via_env${off} with it set, and"
    say "     ${bold}${browser_via_mime:-nothing}${off} without. Scripts that forget"
    say "     ${dim}env -u BROWSER${off} get the first one -- usually a web app, not a"
    say "     browser. Unset BROWSER; tools that want it fall back to xdg-open."
    notes+=("\$BROWSER is set, and xdg-settings resolves it by scanning ~/.local/share/applications for the first Exec that matches -- which on a machine with Chrome web apps is one of those, not a browser. Changing its value does not help: google-chrome.desktop's own Exec is the same binary. Unset it.")
  fi
fi
say ""

# ---- things nixarchy defers on -------------------------------------------
say "${bold}Services${off}"
if systemctl is-enabled tlp.service >/dev/null 2>&1; then
  finding "TLP is managing power" "$warn" ""
  say "     nixarchy leaves power-profiles-daemon off; NixOS forbids both."
  say "     ${dim}omarchy powerprofiles stops working. Nothing else does.${off}"
else
  finding "No TLP" "$ok" "power-profiles-daemon is enabled"
fi

if systemctl is-active pulseaudio.service >/dev/null 2>&1 ||
  systemctl --user is-active pulseaudio.service >/dev/null 2>&1; then
  finding "PulseAudio is the sound server" "$warn" ""
  say "     ${bold}This one nixarchy cannot fix.${off} NixOS enables PipeWire for any"
  say "     graphical session and asserts the two conflict -- a bare"
  say "     programs.hyprland.enable fails the same way. Move to PipeWire"
  say "     first, or nixarchy will not evaluate."
else
  finding "PipeWire" "$ok" ""
fi

# Unit names as systemd spells them, not lowercased: NetworkManager.service is
# capitalised, and lowercasing it returned not-found -- which this reported as
# "NetworkManager is off here" on a machine where it was enabled.
# ---- what a laptop or a shared machine will want to know ----------------
say "${bold}Worth turning on${off}"
if [ -d /sys/class/bluetooth ] && [ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
  finding "This machine has Bluetooth" "$ok" "nixarchy enables the service"
else
  say "  ${dim}No Bluetooth radio here; nixarchy enables the service anyway,"
  say "  which costs nothing on a machine without one.${off}"
fi

# The input group is the one thing upstream's installer does that needs a name,
# and the module cannot guess it -- so the doctor is where a user finds out.
if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx input; then
  finding "You are in the input group" "$ok" "dictation and controllers can read their devices"
else
  finding "You are not in the input group" "$warn" ""
  say "     Omarchy's dictation tools and controllers need it. nixarchy adds"
  say "     it for the user you name:"
  say "       programs.nixarchy.user = \"$USER\";"
fi
say ""

say "  ${dim}programs.nixarchy.browserThemeUser = \"$USER\" tints Chromium with"
say "  the current theme. Off by default: it hands that user the browsers'"
say "  policy directories, which on a shared machine is policy for everyone."
say "  Light and dark already follow the theme without it.${off}"

case "${SHELL##*/}" in
  bash | zsh | fish)
    finding "Omarchy's shell chain covers ${SHELL##*/}" "$ok" ""
    ;;
  *)
    finding "Your shell is ${SHELL##*/}" "$warn" ""
    say "     The chain reaches bash, zsh and fish. You would keep the menus"
    say "     and the desktop, and lose the aliases and functions."
    ;;
esac

# devenv, and specifically the rebuild-vs-session gap the README documents.
# The hook line lands in /etc/bashrc (or /etc/zshrc, or fish's config) at
# rebuild time; a shell that was already open when that happened has neither
# read it nor picked up the package. The symptom is `cd` into a project doing
# nothing at all, which reads as devenv being broken rather than as the
# session being older than the configuration.
#
# This runs in its own process, so it cannot see whether the parent shell has
# the hook function defined. What it CAN see is the pair that actually
# disagrees: the rc the current system installed, against the PATH this
# session inherited.
devenv_rc=""
case "${SHELL##*/}" in
  bash) devenv_rc=/etc/bashrc ;;
  zsh) devenv_rc=/etc/zshrc ;;
  fish) devenv_rc=/etc/fish/config.fish ;;
esac
if [ -n "$devenv_rc" ] && [ -r "$devenv_rc" ] && grep -q 'devenv hook' "$devenv_rc"; then
  if command -v devenv >/dev/null 2>&1; then
    finding "devenv activates in ${SHELL##*/}" "$ok" "cd into a devenv allow'ed project"
  else
    finding "devenv is selected but not on this session's PATH" "$warn" ""
    say "     ${devenv_rc} has the activation hook, so the rebuild landed."
    say "     This shell started before it. Log out and back in; until then"
    say "     cd into a project does nothing and says nothing."
    notes+=("devenv is in your configuration but not in this session. The hook is guarded, so a stale shell stays silent rather than erroring at every prompt -- which also means nothing tells you to log out. This is that.")
  fi
fi
say ""

for unit in docker.service NetworkManager.service; do
  if ! systemctl is-enabled "$unit" >/dev/null 2>&1; then
    say "  ${dim}${unit%.service} is off here; nixarchy defaults it on but defers to you.${off}"
  fi
done
say ""

# ---- what you already have -----------------------------------------------
# The question nixarchy could not answer before: of the applications Omarchy
# offers, which are already on this machine?
#
# It matters in both directions. Selecting one you already have writes a second
# declaration for something your own configuration installs -- harmless in Nix,
# but confusing, and the Install menu used to offer it as though you had
# nothing. And a NixOS user evaluating this repo mostly wants to know how much
# of it they would be adopting versus already running.
#
# Answered by looking for the command on PATH, which is the same evidence the
# menu uses, so what this prints and what the menu dims agree. The table is
# generated at build time from data/apps.nix.
say "${bold}Omarchy apps you already have${off}"
already=()
while IFS=$'\t' read -r binary label; do
  [ -n "$binary" ] || continue
  if command -v "$binary" >/dev/null 2>&1; then
    already+=("$label")
  fi
done <<'APPS'
@apps@
APPS

if [ ${#already[@]} -gt 0 ]; then
  say "  ${dim}${#already[@]} of them, and nixarchy will not install a second copy:${off}"
  printf '    %s\n' "${already[@]}"
  say ""
  say "  ${dim}Their Install rows show dimmed rather than offering to add what you"
  say "  already run. Selecting one anyway is allowed -- it just means nixarchy"
  say "  manages it too, and your own declaration still wins.${off}"
else
  say "  ${dim}None of them, so nothing here overlaps with what you run today.${off}"
fi
say ""

# ---- the snippet ---------------------------------------------------------
say "${bold}Add this to your configuration${off}"
say ""
say "  programs.nixarchy.enable = true;"
if [ ${#snippet[@]} -gt 0 ]; then
  printf '%s\n' "${snippet[@]}"
fi
say ""
say "  ${dim}# and, for the user who will run the desktop:${off}"
say "  home-manager.users.<you> = {"
say "    imports = [ inputs.nixarchy.homeManagerModules.nixarchy ];"
say "    programs.nixarchy.enable = true;"
say "  };"
say ""

if [ ${#notes[@]} -gt 0 ]; then
  say "${bold}Worth knowing${off}"
  for n in "${notes[@]}"; do
    say "  - $n"
  done
  say ""
fi

say "${dim}Nixarchy also adds two binary caches. Without them, enabling it means"
say "compiling a compositor. programs.nixarchy.binaryCaches = false to decline.${off}"
say ""
