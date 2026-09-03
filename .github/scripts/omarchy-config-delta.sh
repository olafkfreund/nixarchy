#!/usr/bin/env bash
# What an Omarchy release changes in the tree that lands in ~/.config.
#
# modules/home.nix seeds the whole of upstream's config/ into the user's
# ~/.config -- 41 files today. Those files are not packaged and not patched:
# they arrive verbatim, and every command they name is expected to be on the
# session PATH by some other route entirely. That split is where #202 lived.
# config/hypr/xdph.conf sets
# `custom_picker_binary = hyprland-preview-share-picker`; upstream declares
# that binary in install/omarchy-base.packages, which pacman honours and
# nothing on NixOS reads. xdg-desktop-portal-hyprland execed a command that
# did not exist and screen sharing failed in every application, with no
# dialog, no error, and the one line saying why in the portal's journal.
#
# So a file list is not enough. For every file this release adds or changes,
# this also reports the executables it NEWLY names -- the names that were not
# already there in the old version -- because that is the set a reviewer has
# to place somewhere before the bump merges.
#
# The reference forms are the ones that tree actually uses, taken from the
# probe in tests/session.nix rather than invented here: hyprland's
# `key = binary`, imv's `= exec binary`, yaml `command:`, .desktop Exec=, and
# lua launch_on_start(). Comment lines go first, because autostart.lua and
# hyprsunset.conf both ship a commented sample naming nothing.
#
# Takes directories, not tags, so it can be checked without a network. The
# workflow unpacks them; tests/config-delta.nix feeds it fixtures.
#
# Usage: omarchy-config-delta.sh <old-config-dir> <new-config-dir> [old-tag] [new-tag]
set -euo pipefail

old_dir=${1:?usage: omarchy-config-delta.sh <old-dir> <new-dir> [old-tag] [new-tag]}
new_dir=${2:?usage: omarchy-config-delta.sh <old-dir> <new-dir> [old-tag] [new-tag]}
old_tag=${3:-old}
new_tag=${4:-new}

[ -d "$new_dir" ] || {
  echo "config delta: $new_dir is not a directory -- the seeded tree moved," >&2
  echo "config delta: or it was never unpacked. Refusing to report calm." >&2
  exit 1
}

files() { (cd "$1" && find . \( -type f -o -type l \) | sed 's|^\./||' | sort); }

# The executables a config file names. Every pattern here is a grep against
# upstream's file layout, so the whole set is checked below for having matched
# anything at all -- a scanner that has stopped matching prints exactly what a
# release that changed nothing prints.
refs() {
  [ -f "$1" ] || return 0
  grep -hIvE '^[[:space:]]*(#|--|//)' "$1" 2>/dev/null |
    sed -nE \
      -e 's/^[[:space:]]*custom_picker_binary[[:space:]]*=[[:space:]]*//p' \
      -e 's/^[[:space:]]*(exec|exec-once)[[:space:]]*=[[:space:]]*//p' \
      -e 's/^[[:space:]]*command:[[:space:]]*//p' \
      -e 's/.*=[[:space:]]*exec[[:space:]]+//p' \
      -e 's/^(Try)?Exec=//p' \
      -e 's/.*launch_on_start\((.*)\).*/\1/p' |
    sed -E 's|^[^A-Za-z0-9_./-]+||' |
    awk '{print $1}' |
    sed -E 's|[^A-Za-z0-9_./-]+$||' |
    grep -vE '^$' | sort -u || true
}

old_files=$(files "$old_dir" 2>/dev/null || true)
new_files=$(files "$new_dir")

added=$(comm -13 <(echo "$old_files") <(echo "$new_files") | grep -vE '^$' || true)
removed=$(comm -23 <(echo "$old_files") <(echo "$new_files") | grep -vE '^$' || true)

changed=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  cmp -s "$old_dir/$f" "$new_dir/$f" || changed="$changed$f"$'\n'
done < <(comm -12 <(echo "$old_files") <(echo "$new_files"))
changed=${changed%$'\n'}

# The guard that keeps this from being a green light. If not one file in the
# whole new tree names an executable, the patterns above have stopped matching
# upstream's layout -- and the report they produce is indistinguishable from a
# quiet release. See AGENTS.md section 1.
any_ref=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ -n "$(refs "$new_dir/$f")" ]; then
    any_ref=yes
    break
  fi
done <<<"$new_files"
[ -n "$any_ref" ] || {
  echo "config delta: nothing in $new_dir names an executable, which cannot" >&2
  echo "config delta: be true -- the reference patterns have stopped matching." >&2
  echo "config delta: See the refs() forms here against tests/session.nix." >&2
  exit 1
}

if [ -z "$added" ] && [ -z "$removed" ] && [ -z "$changed" ]; then
  echo "No change to the seeded config tree between $old_tag and $new_tag."
  exit 0
fi

echo "### Config $new_tag seeds into \`~/.config\`"
echo
echo "\`config/\`, $old_tag → $new_tag. modules/home.nix copies this tree into"
echo "the user's \`~/.config\` verbatim, so every line of it reaches a machine"
echo "without passing through the package."
echo

[ -n "$added" ] && {
  echo "**Added**"
  echo
  echo "$added" | sed 's|^|- `config/|;s|$|`|'
  echo
}

[ -n "$removed" ] && {
  echo "**Removed**"
  echo
  echo "$removed" | sed 's|^|- `config/|;s|$|`|'
  echo
}

[ -n "$changed" ] && {
  echo "**Changed**"
  echo
  echo "$changed" | sed 's|^|- `config/|;s|$|`|'
  echo
}

# The half #202 would have been caught by.
new_names=""
for f in $added $changed; do
  before=$(refs "$old_dir/$f")
  after=$(refs "$new_dir/$f")
  fresh=$(comm -13 <(echo "$before") <(echo "$after") | grep -vE '^$' || true)
  [ -n "$fresh" ] || continue
  new_names="$new_names$(echo "$fresh" | sed "s|^|- \`|;s|\$|\` — named by \`config/$f\`|")"$'\n'
done

if [ -n "$new_names" ]; then
  echo "**Executables these files newly name**"
  echo
  printf '%s' "$new_names"
  echo
  echo "Each of these has to reach the session PATH by some other route: the"
  echo "seeded file names it, and upstream satisfies it from an Arch package"
  echo "list nothing on NixOS reads. That is #202 exactly -- screen sharing"
  echo "failed in every application because \`config/hypr/xdph.conf\` named a"
  echo "picker binary nothing here provided. Place each one, or decide out"
  echo "loud that it stays absent."
  echo
else
  echo "No file this release adds or changes names an executable it did not"
  echo "already name."
  echo
fi

exit 0
