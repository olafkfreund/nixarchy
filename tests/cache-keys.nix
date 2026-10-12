{ pkgs, ... }:
# #1248: the Hyprland substituter key was wrong from the first commit and nothing
# noticed, because nixarchy.cachix.org served the same paths. Every
# <cache>.cachix.org-1: key in the tree must be one value per cache, and the
# hyprland and nixarchy keys must verify a real signature from their cache.
# intent/, spec/ and plan/ are left out of the source: they quote the old key.
# Why: tests/AGENTS.md#a-trust-key-is-checked-by-a-signature-not-by-comparing-it-with-itself
let
  inherit (pkgs) lib;
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.difference ../. (
      lib.fileset.unions [
        ../intent
        ../spec
        ../plan
      ]
    );
  };
  python = pkgs.python3.withPackages (p: [ p.pynacl ]);
in
pkgs.runCommand "nixarchy-cache-keys" { nativeBuildInputs = [ python ]; } ''
  set -euo pipefail
  work=$(mktemp -d)
  cd ${src}

  rc=0
  grep -rnoE '[a-z0-9-]+\.cachix\.org-1:[A-Za-z0-9+/]{43}=' . >"$work/hits" || rc=$?
  [ "$rc" -le 1 ] || { echo "grep failed (exit $rc), so nothing was checked" >&2; exit 1; }
  [ -s "$work/hits" ] || { echo "found no cachix keys, so nothing was checked" >&2; exit 1; }

  # A key the strict pattern cannot read (a typo in its length, a split string)
  # would otherwise be invisible rather than red. This file and the fixtures'
  # Sig lines are the only legitimate loose mentions.
  rc=0
  grep -rnF 'cachix.org-1:' . --exclude-dir=cache-keys |
    grep -v '^\./tests/cache-keys\.nix:' |
    grep -vE '\.cachix\.org-1:[A-Za-z0-9+/]{43}=' >"$work/loose" || rc=$?
  [ "$rc" -le 1 ] || { echo "grep failed (exit $rc), so nothing was checked" >&2; exit 1; }
  if [ -s "$work/loose" ]; then
    echo "a cachix key this check cannot read, so cannot compare:" >&2
    cat "$work/loose" >&2
    exit 1
  fi

  # file:line:<cache>.cachix.org-1:<base64>
  for cache in $(cut -d: -f3 "$work/hits" | sed 's/\.cachix\.org-1$//' | sort -u); do
    grep -F ":$cache.cachix.org-1:" "$work/hits" >"$work/$cache.hits"
    if [ "$(cut -d: -f3- "$work/$cache.hits" | sort -u | wc -l)" -ne 1 ]; then
      echo "$cache: the tree disagrees with itself about the key:" >&2
      cat "$work/$cache.hits" >&2
      exit 1
    fi
  done

  for cache in hyprland nixarchy; do
    [ -s "$work/$cache.hits" ] || {
      echo "$cache: no $cache.cachix.org key anywhere in the tree" >&2; exit 1; }
    key=$(cut -d: -f3- "$work/$cache.hits" | sort -u)
    python -I ${./cache-keys.py} ${./fixtures/cache-keys}/$cache.narinfo "$key" || {
      echo "$cache: the key in the tree does not verify a real $cache.cachix.org signature" >&2
      exit 1; }
  done
  touch $out
''
