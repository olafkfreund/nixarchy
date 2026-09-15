#!/usr/bin/env bash
# What nixarchy.cachix.org is for: the flake installables whose closures are
# pushed from main, one per line.
#
#   cache-allowlist.sh [omarchy|system|runners|apps]    no argument: all of them
#
# The free tier is 5 GB, evicted by last DOWNLOAD (a push is not a use). Every
# job used to push whatever it built, pull requests included, and that evicted
# the MicroVM runners and 31 of 34 check proofs on 2026-09-15 (#697). So the
# cache holds this list and the check proofs -- nothing else -- and
# cache-budget.sh fails when this list outgrows its share.
#
# An entry belongs here only if someone downloads it. Add the reason beside it.
set -uo pipefail

group() {
  case "$1" in
    # Every user: the desktop itself. A new 124 MiB path on every commit,
    # because it depends on the flake's rev (#212).
    omarchy)
      echo ".#omarchy"
      ;;
    # vm-toplevel is what CI boots; reference-toplevel is the installed
    # system's closure, which an offline install copies. They share nearly
    # every path, so the second costs little.
    system)
      echo ".#checks.x86_64-linux.vm-toplevel"
      echo ".#checks.x86_64-linux.reference-toplevel"
      ;;
    # `nixarchy vm run` downloads the KVM runner instead of building QEMU;
    # checks.microvm-boot downloads -tcg every night. From the data file, so a
    # new template brings its runners.
    runners)
      local t
      for t in $(nix eval --impure --raw --expr \
        'toString (builtins.attrNames (import ./data/microvm-templates.nix))'); do
        echo ".#microvm-$t"
        echo ".#microvm-$t-tcg"
      done
      ;;
    # Apps packaged here, which nixpkgs does not have: a user who enables one
    # downloads it from nowhere else. Read the way build.yml's apps job reads
    # them, so the two cannot disagree -- except that an app data/apps.nix marks
    # `unfree` is left out: this cache is public, and pushing a proprietary
    # binary to it is redistributing it. Its users build it, as nixpkgs' do.
    apps)
      # shellcheck disable=SC2016 # a Nix expression, not shell
      nix eval --raw --impure --expr '
        let
          cat = import ./data/apps.nix;
          ours = builtins.filter (n: (cat.${n}.ours or false) && !(cat.${n}.unfree or false)) (builtins.attrNames cat);
        in builtins.concatStringsSep "\n" (map (n: ".#" + (cat.${n}.attr or n)) ours)
      '
      echo
      ;;
    *)
      echo "cache-allowlist.sh: unknown group '$1' (omarchy, system, runners, apps)" >&2
      return 2
      ;;
  esac
}

groups=${1:-omarchy system runners apps}
out=""
for g in $groups; do
  lines=$(group "$g") || exit 2
  # A group that evaluates to nothing is a data file that moved, not a group
  # with nothing in it -- and an empty list pushes nothing while reporting calm.
  [ -n "$(printf '%s' "$lines" | tr -d '[:space:]')" ] || {
    echo "cache-allowlist.sh: group '$g' evaluated empty" >&2
    exit 2
  }
  out="$out$lines"$'\n'
done
printf '%s' "$out" | grep -v '^$'
