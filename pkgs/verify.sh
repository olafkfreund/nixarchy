#!/usr/bin/env bash
# What a VM cannot tell you. Run this from inside a running Omarchy session.
#
# Everything in this repo's checks runs in a machine with no GPU, no Bluetooth
# radio, no network and no sound. That is enough to catch a great deal -- three
# integration bugs and a first-boot lockout came out of it -- but there is a
# class of question it cannot answer at all:
#
#   does the compositor have hardware acceleration, or is it on llvmpipe?
#   does bluetoothd actually see an adapter?
#   did the RetroArch cores land where RetroArch looks?
#   is the browser tinted, in a browser that is running?
#
# Each check below prints what it found rather than a verdict, because the
# useful output is the value: "llvmpipe" and "AMD Radeon" are both PASS for a
# script and mean opposite things to a person.
set -uo pipefail

bold=$(printf '\033[1m')
dim=$(printf '\033[2m')
red=$(printf '\033[31m')
green=$(printf '\033[32m')
yellow=$(printf '\033[33m')
off=$(printf '\033[0m')

pass=0
fail=0
note=0

ok() {
  printf '  %s✓%s %-34s %s\n' "$green" "$off" "$1" "${2-}"
  pass=$((pass + 1))
}
bad() {
  printf '  %s✗%s %-34s %s\n' "$red" "$off" "$1" "${2-}"
  fail=$((fail + 1))
}
hmm() {
  printf '  %s·%s %-34s %s\n' "$yellow" "$off" "$1" "${2-}"
  note=$((note + 1))
}
head_() { printf '\n%s%s%s\n' "$bold" "$1" "$off"; }

say_dim() { printf '    %s%s%s\n' "$dim" "$1" "$off"; }

printf '\n%snixarchy: what the VM could not check%s\n' "$bold" "$off"
say_dim "Run this inside a running Omarchy session."

# ---- what this machine is ------------------------------------------------
# First, because "what are you actually running" is the first question when
# something is wrong, and every answer below is only meaningful against it.
# A value, not a verdict: 4.0.2 is neither good nor bad, it is the fact the
# rest of this output has to be read against.
head_ "Version"
if command -v nixarchy-version >/dev/null 2>&1; then
  # Two lines, "Omarchy   4.0.2" and "nixarchy  800af40  2026-09-03", printed
  # as two values. Here-string rather than a pipe: a `while read` on the right
  # of a pipe runs in a subshell, and the pass/fail counters it increments
  # would be discarded at the end of it.
  while read -r label value; do
    ok "$label" "$value"
  done <<<"$(nixarchy-version)"
else
  # Not a failure. This script is run on machines that do not have nixarchy at
  # all -- that is what the Omarchy-is-absent handling below exists for -- and
  # on an older one that predates the command.
  hmm "nixarchy-version not on PATH" "nothing here can say which nixarchy this is"
fi

# ---- the session ---------------------------------------------------------
head_ "Session"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  bad "not in a Wayland session" "run this from a terminal inside Omarchy"
  printf '\nNothing below will mean anything. Stopping.\n\n'
  exit 1
fi
ok "Wayland session" "$WAYLAND_DISPLAY"

# Whether this is an Omarchy session at all.
#
# Run on a machine that has a Wayland session but not nixarchy -- which is what
# anyone evaluating this repo has, and what this host turned out to be, running
# niri -- every Omarchy-specific check below is a failure by definition. It
# reported "2 failed" and "a failure here is a real one" for a machine that had
# simply never installed it, which is alarming and untrue.
#
# So the Omarchy-specific checks report as notes instead when it is absent. The
# ones that do not depend on it -- Bluetooth, the portal, the cursor -- still
# pass or fail on their own merits, because those are worth knowing either way.
omarchy_here=1
command -v omarchy >/dev/null 2>&1 || omarchy_here=0

# Note rather than failure when Omarchy is not installed.
maybe_bad() {
  if [ "$omarchy_here" = "1" ]; then
    bad "$1" "${2-}"
  else
    hmm "$1" "${2-}"
  fi
}

if [ "$omarchy_here" = "0" ]; then
  hmm "Omarchy is not installed here" "the checks below that need it will say so"
  say_dim "This machine is running ${XDG_CURRENT_DESKTOP:-something else}."
fi

# `pgrep -x quickshell` first, then read that process's own command line.
#
# Two things make the obvious version wrong. DankMaterialShell is built on
# quickshell as well, so a bare match reports Omarchy's bar as running on a
# machine running somebody else's. And `pgrep -f "quickshell.*omarchy"` also
# matches the shell that invoked this script, because the pattern is sitting
# in that shell's own command line -- which is how it reported a running
# Omarchy bar on a machine with niri on the screen.
# `pgrep -x quickshell` was the third thing tried here and does not work on
# NixOS: the binary is wrapped, so the process name is ".quickshell-wrapped",
# truncated by the kernel to ".quickshell-wra" -- and -x matches the whole
# name. This script reported "Omarchy shell not running" on a laptop with the
# bar plainly on screen, which is the one thing it exists to notice.
#
# Matching comm on a substring catches the wrapper and the bare binary both,
# and keeps the self-match protection that -x was chosen for: this script's own
# process is a shell, so its comm is never quickshell however the pattern is
# spelled.
quickshells=$(ps -eo pid,comm --no-headers 2>/dev/null |
  awk '$2 ~ /quickshell/ { print $1 }')

omarchy_shell=""
for p in $quickshells; do
  if tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -q omarchy; then
    omarchy_shell=$p
    break
  fi
done

if [ -n "$omarchy_shell" ]; then
  ok "Omarchy shell running" "pid $omarchy_shell"
elif [ -n "$quickshells" ]; then
  maybe_bad "a quickshell is running, but not Omarchy's" "another shell owns this session"
else
  maybe_bad "Omarchy shell not running" "the bar is the thing most likely to be missing"
fi

# ---- graphics ------------------------------------------------------------
# The VM runs llvmpipe, so it can never answer this. On real hardware a
# software renderer means something is wrong with the driver, not the desktop.
head_ "Graphics"
# Two sources, because neither one answers the whole question.
#
# `hyprctl systeminfo | grep Renderer` was the first version and was wrong
# twice over. There is no Renderer line in that output at all -- 0.56.2 prints
# "GPU information:" as a bare header with the lspci lines under it -- so the
# grep matched only the header, printed "GPU information:" and nothing else,
# and then fell through to the *) case and said "hardware rendering" purely
# because the string was non-empty. A check that cannot fail. On a laptop
# running llvmpipe it would have said the same thing.
#
# The renderer is in aquamarine's log instead, which is where the EGL context
# it actually created gets named, llvmpipe included. Glob over the instance
# directories rather than $HYPRLAND_INSTANCE_SIGNATURE so a session that did
# not export it still gets an answer; grep -a because the log is not
# guaranteed to stay text. `|| true` on the whole pipeline: under pipefail a
# grep that matches nothing kills the report mid-run, which this section has
# already done once.
renderer=$(
  {
    grep -ah 'Renderer: ' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/*/hyprland.log 2>/dev/null |
      tail -1 |
      sed 's/.*Renderer: //'
  } || true
)
# The lspci lines are still worth printing -- they name the hardware, which the
# renderer string does not on a hybrid machine. Strip the PCI address, the
# vendor:device ids and the (rev ..) noise; keep the model.
gpus=$(
  {
    timeout 5 hyprctl systeminfo 2>/dev/null |
      sed -n 's/^[0-9a-f]\{2\}:[0-9a-f.]* \(VGA compatible controller\|3D controller\|Display controller\)[^:]*: //p' |
      sed -e 's/ \[[0-9a-f]\{4\}:[0-9a-f]\{4\}\].*$//' -e 's/ Corporation / /' -e 's/ Inc\. / /'
  } || true
)

case "$renderer" in
  '')
    hmm "could not read the renderer" "no Renderer line in any hyprland.log"
    ;;
  *llvmpipe* | *softpipe* | *swrast* | *SWR*)
    bad "software rendering" "the driver is not being used"
    say_dim "$renderer"
    ;;
  *)
    ok "hardware rendering" ""
    say_dim "$renderer"
    ;;
esac
if [ -n "$gpus" ]; then
  while IFS= read -r gpu; do say_dim "$gpu"; done <<<"$gpus"
else
  hmm "no GPU listed" "hyprctl systeminfo named no display controller"
fi

# ---- screen sharing ------------------------------------------------------
# #202: screen sharing failed in every application on this desktop, silently.
# No dialog, no error. `config/hypr/xdph.conf` is seeded into ~/.config/hypr
# with `custom_picker_binary = hyprland-preview-share-picker`, a binary
# upstream declares in its Arch package list -- which nothing on NixOS reads.
# The portal execed a command that did not exist, got "SHAREDATA returned
# selection -1", and tore the session down. It was found by a maintainer
# trying to share a screen; no check saw it, and none could have, because the
# failure produces nothing to see.
#
# The portal answering on D-Bus was never the question -- it answered on the
# broken machine too. What was false there is the picker and pipewire, so
# those are asked by name.
head_ "Screen sharing"

screencast=$(
  timeout 5 busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.DBus.Properties Get ss org.freedesktop.portal.ScreenCast version 2>/dev/null
)
case "$screencast" in
  # "v u 6". The version, not just the presence: a backend that drops the
  # interface across a bump is the same silent failure with another cause.
  *"u "[0-9]*) ok "portal offers ScreenCast" "version ${screencast##* }" ;;
  *) bad "portal offers no ScreenCast" "${screencast:-nothing on the bus}" ;;
esac

# Which backend answers is decided by XDG_CURRENT_DESKTOP matching a portal's
# UseIn=; on anything but Hyprland here the request lands on the GTK backend,
# which cannot serve it. Both halves are printed because either can be the one
# that is wrong.
#
# pgrep -f is safe here in a way it was not in the Session section above: this
# runs as a script, so the pattern lives in the file rather than in the
# invoking shell's own command line.
if pgrep -f xdg-desktop-portal-hyprland >/dev/null 2>&1; then
  ok "portal backend running" "xdg-desktop-portal-hyprland, XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset}"
else
  maybe_bad "xdg-desktop-portal-hyprland not running" "the GTK backend cannot serve ScreenCast on Hyprland"
fi

# The #202 failure itself: the config names a binary, and until now nothing
# asked whether that binary exists.
xdph="$HOME/.config/hypr/xdph.conf"
picker=$( { sed -n 's/^[[:space:]]*custom_picker_binary[[:space:]]*=[[:space:]]*//p' "$xdph" 2>/dev/null |
  head -1 | sed 's/[[:space:]]*$//'; } || true)
if [ ! -e "$xdph" ]; then
  hmm "no $xdph" "the portal will use its built-in picker"
elif [ -z "$picker" ]; then
  ok "no custom share picker" "the portal's built-in picker"
elif command -v "${picker%% *}" >/dev/null 2>&1; then
  ok "share picker on PATH" "$picker"
else
  bad "share picker is not installed" "$picker"
  say_dim "the portal execs this, fails, and ends the session with no dialog: #202"
fi

# The stream itself is carried by pipewire. Without it a picker selection ends
# in an absent or black window, which reads to a user as the same bug.
if pgrep -x pipewire >/dev/null 2>&1; then
  ok "pipewire running" "pid $(pgrep -x pipewire | head -1)"
else
  bad "pipewire not running" "there is nothing to carry the stream"
fi

# ---- the rest of the silent ones -----------------------------------------
# Everything here fails the way #202 failed: the subsystem is absent, and says
# so to nobody. You find out when you press the key, close the lid, or click
# the link. Ordered with the lock first, because that one is a security
# failure and the others are annoyances.
head_ "Fails in silence"

# Not `command -v hypridle` and not `command -v hyprlock`. Omarchy 4 dropped
# both -- they are in omarchy-upgrade-to-quattro's removal list -- and moved
# the lock and the idle timer into the shell, so a probe for those binaries
# would report a missing lock on a machine whose lock works. The shell's IPC
# is the source of truth. `lock status` only, never `lock lock`: this script
# must not lock the screen of the person running it.
lock=$(timeout 10 omarchy-shell lock status 2>/dev/null)
case "$lock" in
  *'"passwordPam":true'*) ok "the lock can authenticate" "PAM answers for it" ;;
  '') maybe_bad "the shell did not answer about the lock" "omarchy-shell lock status said nothing" ;;
  *) bad "the lock cannot authenticate" "it would lock this machine and not unlock it" ;;
esac

if systemctl --user is-active omarchy-sleep-lock.service >/dev/null 2>&1; then
  ok "locks before suspend" "omarchy-sleep-lock.service"
else
  maybe_bad "nothing locks before suspend" "the lid closes and the session stays open"
fi

# A value, not a verdict: idle off is a legitimate choice (stay-awake is a
# menu item), and it is also the reason a machine never locks itself.
idle=$(timeout 10 omarchy-shell idle status 2>/dev/null)
case "$idle" in
  *'"enabled":true'*)
    ok "idle timer on" "locks after $( (grep -o '"lock":[0-9]*' <<<"$idle" | head -1 | cut -d: -f2) || true)s"
    ;;
  *'"enabled":false'*) hmm "idle timer off" "nothing will lock this machine on its own" ;;
  *) maybe_bad "the shell did not answer about idle" "${idle:-nothing}" ;;
esac

# The polkit agent is not something pgrep can find, which is how this probe
# was wrong on its first draft: Omarchy 4 removed polkit-gnome and
# hyprpolkitagent and ships the agent as a shell plugin
# (shell/plugins/polkit/PolkitAgent.qml), so it lives inside quickshell and no
# process is named for it. polkitd logs the registration, but below the
# --log-level=notice the unit runs at, so the journal has nothing either.
# Whether the plugin is enabled is the question that can actually be asked.
plugins=$(timeout 10 omarchy-shell shell listPlugins 2>/dev/null)
polkit=$( (grep -o '{"id":"omarchy.polkit"[^}]*}' <<<"$plugins") || true)
case "$polkit" in
  *'"enabled":true'*) ok "polkit agent enabled" "the shell's own" ;;
  '')
    if pgrep -f 'polkit.*agent' >/dev/null 2>&1; then
      ok "a polkit agent is running" "not the shell's"
    else
      maybe_bad "no polkit agent" "every privileged prompt fails with no window"
    fi
    ;;
  *) bad "the shell's polkit agent is disabled" "every privileged prompt fails with no window" ;;
esac

# GetServerInformation rather than Notify: asking who is listening must not
# put a popup on the user's screen. The name of the server is the value --
# "quickshell" and "mako" are both PASS and mean different things here.
notifier=$(
  timeout 5 busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications GetServerInformation 2>/dev/null
)
if [ -n "$notifier" ]; then
  # busctl prints the signature and quotes every field, and the vendor field
  # is empty on quickshell, which leaves a double space if it is not squeezed.
  ok "notifications answered" "$(sed -e 's/^ssss //' -e 's/"//g' -e 's/  */ /g' <<<"$notifier")"
else
  bad "nothing answers org.freedesktop.Notifications" "half the desktop's feedback goes nowhere"
fi

# Not the same question as "is pipewire running", which the screen sharing
# section already asked: pipewire up with no sink is an ordinary state on real
# hardware, and it is silent -- the volume keys still move an OSD.
sink=$( (timeout 5 wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null |
  sed -n 's/.*node\.description = "\(.*\)"/\1/p' | head -1) || true)
if [ -n "$sink" ]; then
  ok "default audio sink" "$sink"
elif pgrep -x pipewire >/dev/null 2>&1; then
  bad "pipewire is running with no default sink" "sound goes nowhere"
else
  bad "no audio at all" "pipewire is not running"
fi

# gio rather than xdg-settings: glib is already a runtime input here, and the
# question is the same one. What breaks is mimeapps.list naming a desktop file
# that no installed package provides -- invisible until someone clicks a link.
handler=$( (timeout 5 gio mime x-scheme-handler/https 2>/dev/null |
  head -1 | sed 's/.*: //') || true)
IFS=: read -r -a datadirs <<<"${XDG_DATA_HOME:-$HOME/.local/share}:${XDG_DATA_DIRS:-/usr/share}"
desktop=""
for d in "${datadirs[@]}"; do
  if [ -f "$d/applications/$handler" ]; then
    desktop="$d/applications/$handler"
    break
  fi
done
if [ -z "$handler" ]; then
  hmm "no default handler for https" "clicking a link does nothing"
elif [ -z "$desktop" ]; then
  bad "the default browser is not installed" "$handler is named and not there"
else
  exe=$( (sed -n 's/^Exec=//p' "$desktop" | head -1 | cut -d' ' -f1) || true)
  if command -v "$exe" >/dev/null 2>&1; then
    ok "links open in" "$handler"
  else
    bad "the default browser names a missing binary" "$handler runs $exe"
  fi
fi

# #204's territory: report the state, do not fix it here.
# omarchy-capture-screenshot shells out to grim, slurp and wl-copy, and hands
# the finished PNG to $OMARCHY_SCREENSHOT_EDITOR, which upstream defaults to
# tensaku-edit. Both halves are asked separately because they fail
# differently: no grim and the key does nothing; no editor and the capture
# still lands on disk, but the "Edit" on the notification is dead.
capture_missing=""
for c in grim slurp wl-copy; do
  command -v "$c" >/dev/null 2>&1 || capture_missing="$capture_missing $c"
done
if [ -n "$capture_missing" ]; then
  bad "screenshot tools missing" "$capture_missing"
else
  ok "screenshot tools" "grim, slurp, wl-copy"
fi

editor=${OMARCHY_SCREENSHOT_EDITOR:-tensaku-edit}
if command -v "$editor" >/dev/null 2>&1; then
  ok "screenshot editor" "$editor"
else
  bad "screenshot editor is not installed" "$editor"
  say_dim "the screenshot saves; the Edit on its notification does nothing: #204"
  if command -v satty >/dev/null 2>&1; then
    say_dim "satty is installed here and no config names it"
  fi
fi

# ---- bluetooth -----------------------------------------------------------
# The checks assert the service is enabled and that the VM has no radio. This
# is the other half.
head_ "Bluetooth"
if [ ! -d /sys/class/bluetooth ] || [ -z "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
  hmm "no adapter on this machine" "nothing to test"
elif ! systemctl is-active bluetooth.service >/dev/null 2>&1; then
  bad "adapter present, bluetoothd not running" "the bar widget will be inert"
else
  adapters=$(timeout 5 bluetoothctl list 2>/dev/null | wc -l)
  if [ "$adapters" -gt 0 ]; then
    ok "bluetoothd sees $adapters adapter(s)" ""
    say_dim "$(timeout 5 bluetoothctl list 2>/dev/null | head -1)"
  else
    bad "bluetoothd running but sees no adapter" ""
  fi
fi

# ---- radios ---------------------------------------------------------------
# #277: rfkill and nmcli are both on a stock machine, but nothing looks at
# rfkill state, so a soft-blocked radio -- a hardware key, a stray `nmcli
# radio wifi off`, a driver quirk during a bad boot -- is a dead end nobody
# notices. systemd-rfkill saves that state at shutdown and restores it at
# boot, so it comes back on every reboot after until something clears it.
#
# Soft and hard blocked are reported separately on purpose: soft is undone by
# `rfkill unblock`, hard is a physical switch or BIOS setting that no command
# here touches, and telling them apart is the point (see the issue).
head_ "Radios"
if ! command -v rfkill >/dev/null 2>&1; then
  hmm "rfkill not on PATH" "nothing to check"
else
  radios=$(rfkill list -n -o TYPE,SOFT,HARD 2>/dev/null)
  if [ -z "$radios" ]; then
    hmm "no radios on this machine" "nothing to test"
  else
    while read -r type soft hard; do
      [ -n "$type" ] || continue
      if [ "$hard" = "blocked" ]; then
        bad "$type is hard blocked" "a physical switch or BIOS setting -- software cannot clear this"
      elif [ "$soft" = "blocked" ]; then
        bad "$type is soft blocked" "will stay blocked across reboots until cleared"
        say_dim "rfkill unblock all"
        say_dim "sudo rm -f /var/lib/systemd/rfkill/*   # or it returns at the next boot"
      else
        ok "$type unblocked" ""
      fi
    done <<<"$radios"
  fi
fi

# ---- microvm readiness -----------------------------------------------------
# #221's whole epic rests on one runner CI cannot boot: `-enable-kvm -cpu
# host` needs nested virtualisation to test under nested virtualisation, and
# GitHub's runners do not have it. `checks.microvm-boot` (#228) is the -tcg
# variant on purpose -- it proves the runner is qemu, shares the store and
# uses SLiRP, none of which needs a real /dev/kvm. Whether the KVM runner
# nearly every user actually runs *boots*, and boots fast, is a fact about
# this machine's firmware, kernel and groups, and #221 says outright: "The
# KVM path is pkgs/verify.sh's job, on real hardware."
#
# Values, not verdicts, same as Graphics above: a laptop running under
# VMware with nested off is not broken, it is a real and common shape, and
# the fix there is a host-side setting this section names rather than a red
# X with no next step.
head_ "MicroVM readiness"

if [ -e /dev/kvm ]; then
  # stat's own answer, not just a boolean -- "not writable right after
  # enabling the feature" (#229) means the kvm group has not applied to this
  # login yet, and the fix is to log out, not to debug anything. Printing
  # the mode is what tells the two cases apart instead of one note doing it.
  kvm_perm=$( (stat -c '%A %U:%G' /dev/kvm) || true)
  if [ -w /dev/kvm ]; then
    ok "/dev/kvm" "present and writable ($kvm_perm)"
  else
    bad "/dev/kvm exists but is not writable" "$kvm_perm"
    say_dim "if you were just added to the kvm group: log out, don't debug"
  fi
else
  bad "/dev/kvm does not exist" "virtualisation is off in firmware, or this machine has none"
fi

# Membership is one input to whether /dev/kvm is writable, not the whole
# answer -- a udev rule can hand the device out by mode alone (0666), which
# makes group membership true or false independently of the check above.
# Both are printed so that gap is visible rather than assumed.
if id -nG 2>/dev/null | tr ' ' '\n' | grep -qx kvm; then
  ok "in the kvm group" ""
else
  hmm "not in the kvm group" "not fatal by itself -- see /dev/kvm's own permissions above"
fi

# nixarchy running inside Proxmox/VMware/VirtualBox, or a cloud instance, is
# a realistic case (#221), and there the KVM runner is not the one that
# boots: this machine's own /dev/kvm, if present at all, is nested
# virtualisation gated by a setting on ITS host, not this one.
if grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
  hmm "this machine is itself a VM" "/dev/kvm above, if present, is nested virtualisation"
  vendor=$( (grep -m1 '^vendor_id' /proc/cpuinfo | cut -d: -f2 | tr -d ' ') || true)
  case "$vendor" in
    GenuineIntel) nested_param=/sys/module/kvm_intel/parameters/nested ;;
    AuthenticAMD) nested_param=/sys/module/kvm_amd/parameters/nested ;;
    *) nested_param="" ;;
  esac
  if [ -n "$nested_param" ] && [ -r "$nested_param" ]; then
    nested=$( (cat "$nested_param") || true)
    case "$nested" in
      1 | Y | y) ok "nested virtualisation" "$nested_param says $nested" ;;
      *)
        bad "nested virtualisation is off" "$nested_param says ${nested:-nothing}"
        say_dim "the setting to change is on THIS machine's host, not here"
        ;;
    esac
  else
    hmm "could not read nested virtualisation state" "${nested_param:-no kvm_intel or kvm_amd module}"
  fi
else
  ok "not itself a VM" "/dev/kvm above, if present, is the real thing"
fi

# ---- microvm guests ---------------------------------------------------------
# Two directory layouts, one check: `nixarchy-vm` (pkgs/microvm.nix) writes
# ~/.local/state/nixarchy/microvm/<name>/current for disposable sandboxes,
# and programs.nixarchy.services.microvm (modules/services/microvm.nix)
# writes /var/lib/microvms/<name>/current for permanent ones. Both are a
# `nix build --out-link` result and nothing else, on purpose (#221): a
# `nix-collect-garbage` while a guest is running must not be able to take the
# store it is 9p-mounted on out from under it. Whether that promise holds is
# not a thing the code that writes the link can assert about itself -- it is
# a fact about the store, read here the same way nix-collect-garbage would.
head_ "MicroVM guests"

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/microvm"
vm_seen=0
running_seen=0
# Deliberately unquoted: a glob over two directory shapes, not a word to
# split. A directory that does not exist expands to its own literal pattern
# with nullglob off, which the `[ -d "$dir" ]` guard below then skips.
for dir in "$state_dir"/*/ /var/lib/microvms/*/; do
  [ -d "$dir" ] || continue
  vm_seen=1
  name=$(basename "$dir")
  cur="$dir/current"

  if [ ! -e "$cur" ] && [ ! -L "$cur" ]; then
    hmm "$name: no current link yet" "created on the first 'nixarchy vm run' or rebuild"
  else
    target=$( (readlink -f "$cur") || true)
    if [ -z "$target" ] || [ ! -e "$target" ]; then
      bad "$name: current is a dangling link" "$cur -> $( (readlink "$cur") || echo '?')"
      say_dim "nothing here is a GC root -- nix-collect-garbage can already have taken it"
    else
      # `--print-roots`, never `--gc`: this must read the store, not collect
      # it. `|| true` because a store query is one more thing that can fail
      # without killing the rest of this report -- the same reasoning as the
      # Graphics grep above, which already did this once for real.
      if timeout 15 nix-store --gc --print-roots 2>/dev/null | grep -qF "$target"; then
        ok "$name: current is a live GC root" "$target"
      else
        bad "$name: current is not a GC root" "$target"
        say_dim "nix-collect-garbage can take this store out from under a running guest"
      fi
    fi
  fi

  # A running guest holds nixarchy-vm's own flock on $dir/.lock for the life
  # of the qemu process (pkgs/microvm.nix) -- the same test 'nixarchy vm
  # list' uses to tell running from stopped, read here rather than
  # reinvented.
  [ -e "$dir/.lock" ] || continue
  locked=0
  exec 8>"$dir/.lock"
  flock -n 8 || locked=1
  exec 8>&-
  [ "$locked" = 1 ] || continue
  running_seen=1

  # kvm-clock means the guest's own kernel is using paravirtualised time
  # under real acceleration; tsc or acpi_pm means it is on -tcg and the user
  # is waiting for software emulation for no reason (#229). Both look
  # identical from outside a shell inside the guest, which is exactly why
  # it is worth reading rather than assumed from which variant was launched.
  #
  # But #221 also made the console the ONLY door for a disposable sandbox on
  # purpose -- no port allocation, no QMP -- and this script must not steal
  # that console from whatever terminal is already attached to it. So the
  # one channel usable without interfering is a forwarded SSH port, findable
  # on the qemu command line itself for machines that have one (only the
  # declarative half, programs.nixarchy.services.microvm, ever sets
  # sshPort).
  qpid=""
  target_cwd=$( (readlink -f "$dir") || true)
  for p in /proc/[0-9]*; do
    [ -n "$target_cwd" ] || break
    [ "$( (readlink -f "$p/cwd" 2>/dev/null) || true)" = "$target_cwd" ] || continue
    qpid=${p#/proc/}
    break
  done
  ssh_port=""
  if [ -n "$qpid" ]; then
    ssh_port=$( ({ tr '\0' ' ' <"/proc/$qpid/cmdline" 2>/dev/null || true; } |
      grep -oE 'hostfwd=tcp::[0-9]+-:22' | head -1 | grep -oE '[0-9]+') || true)
  fi

  if [ -z "$ssh_port" ]; then
    hmm "$name: running, clocksource not checkable from here" "console-only by design (#221) -- attach and run: cat /sys/devices/system/clocksource/clocksource0/current_clocksource"
    continue
  fi

  clocksource=$(timeout 5 ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -p "$ssh_port" dev@127.0.0.1 \
    cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null || true)
  case "$clocksource" in
    kvm-clock) ok "$name: clocksource" "kvm-clock -- hardware acceleration" ;;
    tsc | acpi_pm) bad "$name: clocksource" "$clocksource -- running under software emulation" ;;
    "") hmm "$name: could not read clocksource" "ssh to 127.0.0.1:$ssh_port failed -- dev@ has no key by default in guest.nix" ;;
    *) hmm "$name: clocksource" "$clocksource" ;;
  esac
done

if [ "$vm_seen" = 0 ]; then
  hmm "no MicroVM guests on this machine" "'nixarchy vm create <name>' to make one"
elif [ "$running_seen" = 0 ]; then
  hmm "no MicroVM guests running right now" "'nixarchy vm run <name>' to start one"
fi

# ---- theming -------------------------------------------------------------
head_ "Theme"
scheme=$(
  timeout 5 busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
    org.freedesktop.portal.Settings ReadOne ss org.freedesktop.appearance color-scheme 2>/dev/null
)
case "$scheme" in
  *"u 1"*) ok "portal reports dark" "Chromium and GTK follow this" ;;
  *"u 2"*) ok "portal reports light" "" ;;
  *"u 0"*) bad "portal reports no preference" "browsers will come up light" ;;
  *) hmm "portal did not answer" "${scheme:-nothing}" ;;
esac

cursor=$(timeout 5 gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
case "$cursor" in
  Bibata*) ok "cursor follows the theme" "$cursor" ;;
  "" | Adwaita) bad "cursor is the default" "${cursor:-unset}; Omarchy's theme hook did not run" ;;
  *) hmm "cursor is something else" "$cursor" ;;
esac

policy=/etc/chromium/policies/managed/color.json
if [ -f $policy ]; then
  ok "browser accent written" "$( (grep -o '#[0-9a-fA-F]\{6\}' "$policy" | head -1) || true)"
else
  hmm "browser accent not set" "programs.nixarchy.browserThemeUser is off"
fi

# ---- what nixarchy patched, checked on the machine it matters on ---------
# Every one of these was wrong at some point and none of them is visible in a
# VM: the version comes from a package query, Plymouth only shows at boot, and
# Vulkan needs a real GPU stack. They are the difference between "the build
# succeeded" and "the desktop is right".
head_ "Nixarchy fixes"

# Guarded on the command being here at all. Run on a machine that has a
# Wayland session but not nixarchy -- which is exactly what someone evaluating
# this repo has -- an unguarded check reports "Vulkan present but not detected"
# and blames the wrong thing for a command that is simply absent.
if ! command -v omarchy >/dev/null 2>&1; then
  hmm "Omarchy is not installed here" "nothing in this section to check"
fi

ver=$(timeout 5 omarchy version 2>/dev/null || true)
if ! command -v omarchy >/dev/null 2>&1; then
  : # already reported
else
  case "$ver" in
    dev | dev\ *)
      bad "omarchy version says '$ver'" "should be the packaged version"
      say_dim "upstream falls back to a git-checkout branch when OMARCHY_PATH"
      say_dim "is not /usr/share/omarchy, which on NixOS it never is"
      ;;
    "") bad "omarchy version said nothing" "" ;;
    *) ok "omarchy version" "$ver" ;;
  esac
fi

# The boot splash. Checked through plymouth's own config rather than the Nix
# option, because what matters is what the running system will show.
if ! command -v plymouth >/dev/null 2>&1; then
  hmm "Plymouth not installed" "boot.plymouth.enable is off"
else
  theme=$( (grep -h '^Theme=' /etc/plymouth/plymouthd.conf 2>/dev/null |
    head -1 | cut -d= -f2) || true)
  case "$theme" in
    # The directory is called omarchy and the theme inside it is nixarchy's:
    # boot.plymouth.theme names a directory, and renaming that one means moving
    # boot.plymouth.themePackages with it. Name= in omarchy.plymouth is what
    # the theme calls itself, and it says nixarchy. See #46.
    omarchy) ok "boot splash is nixarchy's" "" ;;
    "") hmm "no Plymouth theme configured" "boot.plymouth.theme is unset" ;;
    *) hmm "boot splash is '$theme'" "not nixarchy's, which is fine if you chose it" ;;
  esac
fi

# Only omarchy-voxtype-install reads this, but it read it wrong on every
# machine: upstream looks in /usr/share/vulkan/icd.d, which NixOS does not use.
if ! command -v omarchy-hw-vulkan >/dev/null 2>&1; then
  : # reported above
elif [ -d /run/opengl-driver/share/vulkan/icd.d ]; then
  if omarchy-hw-vulkan 2>/dev/null; then
    ok "Vulkan detected" "$( (find /run/opengl-driver/share/vulkan/icd.d -maxdepth 1 -name '*.json' 2>/dev/null | wc -l) || echo 0) ICD files"
  else
    bad "Vulkan present but not detected" "omarchy-hw-vulkan is looking in the wrong place"
  fi
else
  hmm "no Vulkan ICDs on this machine" "hardware.graphics may be off"
fi

# The menu, which since #210 is two files with one owner each: the Install-row
# rewrites are in the defaults this session reads, and the extension beside it
# is the user's and their plugins'.
#
# Both halves are worth checking here and neither is checkable in a VM the way
# this is. What matters is the DEFAULTS the running session resolves -- reading
# /etc/nixarchy/omarchy-menu.jsonc instead would test what the system built,
# not what a session started before that rebuild is actually reading.
menu_defaults="${OMARCHY_PATH:-}/default/omarchy/omarchy-menu.jsonc"
if [ -z "${OMARCHY_PATH:-}" ]; then
  maybe_bad "OMARCHY_PATH is unset" "nothing resolves the menu, the bar or the themes"
elif [ ! -r "$menu_defaults" ]; then
  maybe_bad "no menu defaults in \$OMARCHY_PATH" "$menu_defaults"
elif grep -q nixarchy-app-enable "$menu_defaults"; then
  ok "menu defaults" "Install rows reach nixarchy-app-enable"
else
  maybe_bad "menu defaults still run pacman" "no nixarchy-app-enable rows in \$OMARCHY_PATH"
  say_dim "this session predates #210, or its tree is not the generated one"
fi

# And the file that is NOT ours. A symlink here is what nixarchy used to plant,
# and it is the whole bug: upstream's shell/plugins/README.md points plugins at
# this path, and a plugin cannot write a read-only store symlink.
menu_user="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if [ -L "$menu_user" ]; then
  bad "$menu_user is a symlink" "plugins and your own rows cannot be written"
  say_dim "an older nixarchy owned this file; a rebuild no longer does"
  say_dim "rm it and log back in to get Omarchy's writable example"
elif [ -w "$menu_user" ]; then
  ok "your menu extension is yours" "$menu_user"
elif [ -e "$menu_user" ]; then
  bad "$menu_user is not writable" "plugins and your own rows cannot be written"
else
  hmm "no menu extension yet" "seeded on first login; add rows there"
fi

# The two runtime-installable things, both of which clone into ~/.config and
# both of which fail on their first mkdir if that tree is a store symlink.
for d in plugins themes; do
  if [ -d "$HOME/.config/omarchy/$d" ] && [ -w "$HOME/.config/omarchy/$d" ]; then
    ok "$HOME/.config/omarchy/$d writable" \
      "$( (find "$HOME/.config/omarchy/$d" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | wc -l) || echo 0) installed"
  elif [ -e "$HOME/.config/omarchy/$d" ]; then
    bad "$HOME/.config/omarchy/$d not writable" "omarchy $d install cannot work"
  else
    hmm "$HOME/.config/omarchy/$d absent" "created on first use"
  fi
done

# ---- the menu, row by row ------------------------------------------------
# A menu row names a command to run, and until now nothing asked whether that
# command exists. The row renders, somebody picks it, the shell hands the
# string to execDetached, and nothing happens -- no dialog, no error, no
# journal line. That is #202's failure exactly, in another subsystem: the
# config names something, and the something is not there.
#
# It belongs here rather than in CI because of WHICH menu is being read. The
# menu a session shows is the generated defaults with
# ~/.config/omarchy/extensions/omarchy-menu.jsonc merged over the top -- the
# user's file and their plugins', which by design nixarchy never writes and CI
# has therefore never seen. A plugin that adds a row calling a binary it did
# not bring lands only there. build.yml can assert this about the defaults; the
# merged menu exists on one machine and this is the script that runs on it.
head_ "Menu rows"

if [ -z "${OMARCHY_PATH:-}" ] || [ ! -r "$menu_defaults" ]; then
  : # the section above already said why
elif ! command -v python3 >/dev/null 2>&1; then
  hmm "python3 not on PATH" "nothing here can parse the menu"
else
  # Parsed the way MenuModel.js does -- whole-line comments out, then trailing
  # commas, then plain JSON -- because a parser that disagrees with the shell's
  # is reporting on a menu nobody has. The same three lines are in build.yml,
  # tests/session.nix and tests/plugin.nix for that reason.
  menu_rows=$(python3 - "$menu_defaults" "$menu_user" <<'PY'
import json, re, subprocess, sys

def load(path):
    try:
        raw = open(path).read()
    except OSError:
        return {}
    raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
    try:
        return json.loads(re.sub(r",(\s*[}\]])", r"\1", raw))
    except ValueError as e:
        print("PARSE", path, e)
        return {}

rows = load(sys.argv[1])
rows.update(load(sys.argv[2]))   # the extension overrides the defaults by id

# A submenu parent has no action and is not broken. Nothing in a row says
# "I have children" -- the children just carry ids prefixed with the parent's,
# so `install` is legitimately actionless because `install.editor` exists.
# Same test as build.yml's dead-row rule, and for the same reason: without it
# every parent in the merged menu reads as a row that does nothing.
ids = set(rows)
def parent(k):
    return any(o.startswith(k + ".") for o in ids)

# `when:` is evaluated before the row is drawn, so a false one is not a row
# this machine has. Skipping it is not politeness, it is the difference
# between a check and a noise generator: the first run of this section on real
# hardware reported three Touchpad Haptics rows calling
# dell-xps-touchpad-haptics on a laptop that is not a Dell -- and upstream had
# already guarded them with
# `when: omarchy-hw-dell-xps-haptic-touchpad && omarchy-cmd-present ...`.
# Nothing was broken; the check was asking about rows nobody can see.
#
# Run rather than parsed, because they are bash and only bash knows what they
# mean; the same call tests/session.nix makes of the `disabled` expressions.
# Timed out because a hung predicate would hang this whole report, and treated
# as hidden on timeout -- a row the shell cannot decide about in five seconds
# is not one this section should have an opinion on.
def shown(row):
    expr = str(row.get("when", "")).strip()
    if not expr:
        return True
    try:
        return subprocess.run(["bash", "-c", expr], timeout=5,
                              stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False

# The action is a bash string, not a bare command name: `omarchy-theme-set`
# after a `$(...)` and a `&&`, or a whole if/then. So look at the head of every
# command position -- the start, and whatever follows a separator or opens a
# substitution -- and keep only the ones that are a plain word. A fragment
# starting with `[[` or `"$theme"` is a test or an argument, not a command, and
# is dropped rather than guessed at; bash resolves its own builtins and
# keywords when the shell below asks.
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until"}

def commands(action):
    for frag in re.split(r"\$\(|&&|\|\||[;&|()]", action):
        words = frag.split()
        while words and words[0] in KEYWORDS:
            words.pop(0)
        if words and re.fullmatch(r"[A-Za-z0-9_.+/-]+", words[0]):
            yield words[0]

seen = set()
shown_rows = 0
for key, row in rows.items():
    if not shown(row):
        continue
    shown_rows += 1
    action = str(row.get("action", "")).strip()
    if not action:
        # A row with no action, no children and no provider renders and then
        # does nothing when chosen. Upstream's own rows are covered by CI; a
        # hand-written one in the extension is covered by nothing else.
        if not parent(key) and not row.get("provider"):
            print("DEAD", key)
        continue
    for cmd in commands(action):
        if (key, cmd) not in seen:
            seen.add((key, cmd))
            print("CMD", key, cmd)
print("ROWS", shown_rows)
PY
  )

  # `command -v` in this script and not shutil.which in the probe above: the
  # PATH that matters is the one a session has, writeShellApplication's prefix
  # included, and this is the process holding it. Here-string rather than a
  # pipe -- a `while read` on the right of a pipe runs in a subshell and the
  # counters below would be discarded with it.
  menu_checked=0
  menu_total=0
  menu_broken=""
  while read -r kind key cmd; do
    case "$kind" in
      CMD)
        menu_checked=$((menu_checked + 1))
        command -v "$cmd" >/dev/null 2>&1 ||
          menu_broken="$menu_broken $key runs $cmd, which is not installed"$'\n'
        ;;
      DEAD) menu_broken="$menu_broken $key has no action and no submenu"$'\n' ;;
      PARSE) menu_broken="$menu_broken $key is not valid JSONC: $cmd"$'\n' ;;
      ROWS) menu_total=$key ;;
    esac
  done <<<"$menu_rows"

  if [ -n "$menu_broken" ]; then
    bad "menu rows that would do nothing" "$(grep -c . <<<"$menu_broken") of $menu_total visible rows"
    while IFS= read -r line; do
      [ -n "$line" ] && say_dim "$line"
    done <<<"$menu_broken"
    say_dim "each of these renders, and then does nothing when chosen"
  elif [ "$menu_checked" -lt 20 ]; then
    # The count is half the verdict. A parse that returned almost nothing
    # passes this section for the wrong reason, and looks identical to a menu
    # in which everything resolves.
    hmm "only $menu_checked commands checked" "in $menu_total visible rows; the menu did not parse as expected"
  else
    ok "every menu row resolves" "$menu_checked commands in $menu_total visible rows"
  fi
fi

# ---- the shell -----------------------------------------------------------
head_ "Shell"
# Checked by looking at what the system rc sources, not by calling one of the
# functions.
#
# `type tdl` cannot work from here however the shell is spelled: this script
# runs as its own bash process, and a function defined in the user's
# interactive shell is not inherited by a child. So it reported "Omarchy's
# functions are missing" on a laptop where an interactive zsh finds every one
# of them -- the check was structurally incapable of seeing what it asked
# about.
#
# What is actually knowable from a script is whether the chain is wired in at
# all, which is the thing that breaks: /etc/zshrc sourcing Omarchy's rc is what
# puts the functions in every new shell.
case "${SHELL##*/}" in
  bash) rc=/etc/bashrc ;;
  zsh) rc=/etc/zshrc ;;
  fish) rc=/etc/fish/config.fish ;;
  *) rc="" ;;
esac

if [ -z "$rc" ]; then
  hmm "your shell is ${SHELL##*/}" "the chain reaches bash, zsh and fish"
  say_dim "you keep the menus and the desktop, and lose the aliases"
elif [ -f "$rc" ] && grep -q 'share/omarchy' "$rc" 2>/dev/null; then
  ok "Omarchy's functions are wired in" "$rc sources them for ${SHELL##*/}"
else
  maybe_bad "Omarchy's functions are not wired in" "$rc does not source them"
  say_dim "programs.nixarchy.shellIntegration may be off"
fi

compose=$( { sed -n 's/^include "\(.*\)"$/\1/p' "$HOME/.XCompose" 2>/dev/null |
  grep -v '%L' | head -1; } || true)
if [ -n "$compose" ] && [ -e "$compose" ]; then
  ok "compose sequences resolve" "$compose"
elif [ -n "$compose" ]; then
  bad "$HOME/.XCompose points at nothing" "$compose"
else
  hmm "no $HOME/.XCompose" "first login may not have run yet"
fi

# ---- things with big closures the VM never launches ----------------------
head_ "Installed and launchable"
cores=$(timeout 5 omarchy-retroarch-cores 2>/dev/null || true)
if [ -n "$cores" ] && [ -d "$cores" ]; then
  ok "RetroArch cores" "$( (find "$cores" -name '*_libretro.so' | wc -l) || echo 0) cores in $cores"
else
  hmm "RetroArch not installed" "enable apps.retroarch to test this"
fi

for app in nautilus pinta gnome-disks xournalpp; do
  if command -v "$app" >/dev/null 2>&1; then
    ok "$app" "on PATH"
  else
    hmm "$app" "not installed"
  fi
done

# ---- boxes ----------------------------------------------------------------
# What only real hardware and a live network can answer for distrobox (#230).
# CI's checks.box-template (#258) proves the catalogue and nixarchy box's own
# script are well-formed with no network at all; checks.box-boot, once it
# lands, proves creation and entry inside an isolated VM with a preloaded
# image and no real network path out. Neither can answer "does this actually
# work for THIS user, on THIS machine, on the real internet" -- AGENTS.md #2's
# point, the same reason Bluetooth pairing above is answerable nowhere else.
#
# distrobox is deliberately never in this script's runtimeInputs and never
# called any way but by bare name below -- the same wrapper-only rule
# pkgs/box.nix's header explains: distrobox resolves its own support scripts
# relative to the directory it was invoked from, so a /nix/store path here
# would be exactly the mistake this section exists to catch elsewhere.
head_ "Boxes"
if ! command -v distrobox >/dev/null 2>&1; then
  hmm "distrobox not on PATH" "enable services.boxes to test this"
else
  # Rootless podman, actually usable by this user -- not merely installed.
  # NixOS allocates the subuid/subgid ranges automatically; this confirms
  # they landed rather than assuming the allocator ran.
  me=$(id -un)
  if grep -q "^$me:" /etc/subuid 2>/dev/null && grep -q "^$me:" /etc/subgid 2>/dev/null; then
    ok "subuid/subgid ranges" "$(grep "^$me:" /etc/subuid)"
  else
    bad "no subuid/subgid range for $me" "rootless podman cannot start containers"
  fi

  if podman info >/dev/null 2>&1; then
    ok "podman info" "runs with no sudo"
  else
    bad "podman info failed" "rootless podman is not usable by this user right now"
  fi

  # Every box podman actually knows about -- declared or ad hoc, this script
  # cannot and does not try to tell them apart, the same way `nixarchy box
  # list` does not either.
  boxes=$(podman ps -a --format '{{.Names}}' 2>/dev/null || true)
  if [ -z "$boxes" ]; then
    hmm "no boxes exist yet" "nixarchy box create <name> --template <t>"
  else
    while IFS= read -r box; do
      [ -n "$box" ] || continue

      # First-start package-manager update: the one thing #256/#259 could
      # only try once, briefly, offline, on a branch. Read here instead of
      # assumed -- a box whose pacman -Syy / apt-get update never finished
      # is a box that will misbehave the first time a package is needed,
      # quietly.
      #
      # `distrobox enter -- true` rather than `systemctl is-system-running`:
      # distrobox containers do not run systemd as PID 1 by default (no
      # `--init`), so `systemctl is-system-running` inside one answers
      # "offline" on a perfectly healthy box -- verified against a fresh
      # `archlinux` box on this machine, which reported exactly that.
      # `enter -- true` runs the same first-start setup (the "Installing
      # basic packages..." sequence distrobox-init performs) and its own
      # exit status is a direct answer to "did that finish" -- confirmed
      # against both a healthy box (exit 0) and a genuinely corrupted
      # pre-existing one on this machine (exit 1, real error text below).
      #
      # `</dev/null`: a box with storage corruption prompts interactively
      # ("recreate the missing symlinks?") instead of failing outright, and
      # this script has to fail fast rather than hang on that prompt.
      #
      # `|| true`: writeShellApplication forces `set -e`, and an unguarded
      # `var=$(...)` here killed the whole script silently the first time
      # this was run for real against that same corrupted box (it stopped
      # dead right after "podman info" with nothing printed at all) --
      # `podman inspect` on a box that never started and `find` racing a
      # missing ~/.local/share/applications carry the same risk below.
      if out=$(timeout 30 distrobox enter "$box" -- true </dev/null 2>&1); then
        ok "$box: first start" "reached a shell"
      else
        bad "$box: first start" "$(printf '%s' "$out" | tail -1)"
      fi

      # Exported GUI apps actually landing in the launcher --
      # distrobox-export writes .desktop files under
      # ~/.local/share/applications named <box>-<app>.desktop.
      exported=$(find "$HOME/.local/share/applications" -maxdepth 1 -name "${box}-*.desktop" 2>/dev/null | wc -l) || true
      if [ "$exported" -gt 0 ]; then
        ok "$box: exported apps" "$exported .desktop file(s) in the launcher"
      else
        hmm "$box: no exported apps" "fine if this template exports none"
      fi

      # The wrapper-only rule, checked continuously instead of assumed --
      # the live version of the foundation issue's first verify-before-
      # building question. podman records whatever path the container was
      # actually created with; a versioned /nix/store path here is exactly
      # what nixpkgs#478154 says a nix-collect-garbage can delete out from
      # under this box.
      mount_src=$(podman inspect --type container "$box" \
        --format '{{range .Mounts}}{{if eq .Destination "/usr/bin/entrypoint"}}{{.Source}}{{end}}{{end}}' 2>/dev/null) || true
      case "$mount_src" in
        "")
          hmm "$box: entrypoint mount" "not found -- distrobox's own layout may have changed"
          ;;
        /nix/store/*)
          bad "$box: entrypoint mount is a /nix/store path" "$mount_src"
          say_dim "nix-collect-garbage can delete this out from under a running box (nixpkgs#478154)"
          ;;
        *)
          ok "$box: entrypoint mount" "$mount_src"
          ;;
      esac
    done <<<"$boxes"
  fi
fi

# ---- summary -------------------------------------------------------------
printf '\n%s%s passed, %s failed, %s worth a look%s\n' \
  "$bold" "$pass" "$fail" "$note" "$off"
if [ "$fail" -gt 0 ]; then
  printf '%sA failure here is a real one: everything above is something a VM\n' "$dim"
  printf 'cannot check, so nothing in CI would have caught it.%s\n\n' "$off"
  exit 1
fi
printf '\n'
