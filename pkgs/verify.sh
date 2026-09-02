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

# ---- summary -------------------------------------------------------------
printf '\n%s%s passed, %s failed, %s worth a look%s\n' \
  "$bold" "$pass" "$fail" "$note" "$off"
if [ "$fail" -gt 0 ]; then
  printf '%sA failure here is a real one: everything above is something a VM\n' "$dim"
  printf 'cannot check, so nothing in CI would have caught it.%s\n\n' "$off"
  exit 1
fi
printf '\n'
