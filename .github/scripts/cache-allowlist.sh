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
# An entry belongs here only if someone downloads it AND would otherwise build
# it. Both halves matter: cache-budget.sh already subtracts everything
# cache.nixos.org and hyprland.cachix.org serve, so anything reaching the budget
# is something upstream will not serve -- but "unfree, so Hydra will not build
# it" and "expensive to build" are different claims, and only the second is a
# reason to pay for it here. A prebuilt binary is a download either way, so
# caching it makes this a slower second mirror (#725). Add the reason beside it.
#
# One exception, for availability rather than build cost (#788, #800): the box
# checks' pinned base images. They are a download either way, but Docker Hub is
# not ours, and a 502 from it turned main red on a cold runner. They are cached
# so the checks never depend on it -- every pinned template image, not only the
# default one, through the single .#box-test-image entry in `system`.
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
      # checks.options compiles hypr-rdp otherwise -- 447 Rust crates, 5.5 to
      # 8.5 minutes, every run, for a check that asserts in three seconds
      # (#738). Nothing else serves it: it is a flake input, MIT, off by
      # default so no toplevel carries it, and absent from cache.nixos.org.
      # It was in this cache by accident until #699 stopped the store-diff
      # pushes, and `system` started timing out the next day.
      echo ".#hypr-rdp"
      # #788, #800: every pinned box template image (archlinux, debian), which
      # the box checks pull -- the availability exception in the header. One
      # entry, so a new template brings its image with no second edit here or
      # in build.yml's producer step. Keep the pinned images unmodified.
      echo ".#box-test-image"
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
    # An app marked `prebuilt` is left out too, for the reason in the header:
    # there is no build to save.
    apps)
      # shellcheck disable=SC2016 # a Nix expression, not shell
      nix eval --raw --impure --expr '
        let
          cat = import ./data/apps.nix;
          ours = builtins.filter (
            n:
            (cat.${n}.ours or false) && !(cat.${n}.unfree or false) && !(cat.${n}.prebuilt or false)
          ) (builtins.attrNames cat);
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
