#!/usr/bin/env bash
# What an Omarchy release adds to, and drops from, the set it installs.
#
# Omarchy pins no versions -- both package lists are bare Arch names, whatever
# Arch shipped that day -- so there is no version to match. What there is, and
# what nothing here looked at until now, is the SET. When upstream adds a
# package or drops one, that is a decision about how the desktop is put
# together, and this port either mirrors it or knowingly does not.
#
# 4.0.2 is the example that earned this script. It dropped `cups-browsed` and
# added `cups-pk-helper` -- the release notes call it "Harden CUPS printer
# discovery and administration" -- while modules/nixos.nix still justified its
# printing defaults with the comment "cups, cups-browsed, avahi and nss-mdns
# are all in base.packages". Three lines of diff, pointing straight at a
# comment that had stopped being true.
#
# Comparing the whole list against data/apps.nix instead would report 201 of
# 206 packages as unmapped, because `base`, `bluez` and `bat` reach a nixarchy
# machine through the NixOS module rather than the app catalogue. The delta
# between two releases is the part that carries a decision.
#
# Takes files, not tags, so it can be checked without a network. The workflow
# fetches them; tests/package-delta.nix feeds it fixtures.
#
# Usage: omarchy-package-delta.sh <old.packages> <new.packages> [old-tag] [new-tag]
set -euo pipefail

old_file=${1:?usage: omarchy-package-delta.sh <old> <new> [old-tag] [new-tag]}
new_file=${2:?usage: omarchy-package-delta.sh <old> <new> [old-tag] [new-tag]}
old_tag=${3:-old}
new_tag=${4:-new}

# Comments and blank lines are not packages.
clean() { grep -vE '^\s*(#|$)' "$1" | sort -u; }

added=$(comm -13 <(clean "$old_file") <(clean "$new_file"))
removed=$(comm -23 <(clean "$old_file") <(clean "$new_file"))

if [ -z "$added" ] && [ -z "$removed" ]; then
  echo "No change to the package set between $old_tag and $new_tag."
  exit 0
fi

echo "### Packages $new_tag changes"
echo
echo "Upstream's install lists, $old_tag → $new_tag. Each line is a decision"
echo "this port either mirrors or knowingly does not."
echo

[ -n "$added" ] && {
  echo "**Added**"
  echo
  echo "$added" | sed 's/^/- `/;s/$/`/'
  echo
}

[ -n "$removed" ] && {
  echo "**Removed**"
  echo
  echo "$removed" | sed 's/^/- `/;s/$/`/'
  echo
  echo "A removal is the one worth reading twice: upstream dropping a package"
  echo "is often a security decision, and a comment in this repo may still be"
  echo "citing it as a reason for something."
  echo
}

exit 0
