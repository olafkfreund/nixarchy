#!/usr/bin/env bash
# What nixarchy.cachix.org should be serving and is not, and putting it back.
#
#   cache-entries.sh probe             missing allowlist entries, one per line
#   cache-entries.sh repush <entry>...  build, push, and probe again
#
# The entries are cache-allowlist.sh's: omarchy, the system closures, the
# MicroVM runners and the apps built here (#697). Everything on that list is
# there because somebody downloads it, and the cache evicts by last download --
# so anything nobody fetched for a while goes, and a user's next `nixarchy vm
# run` or install builds what it should have downloaded.
#
# Why repush exists at all: the runners DROP OUT of the cache. On 2026-09-15
# the nightly found every KVM runner 404 while main's system job had
# downloaded the very same path (srdblflsg...-microvm-qemu-nixos) from
# nixarchy.cachix.org the afternoon before. Nothing had changed; the cache had
# let go of paths nobody fetched. The -tcg runners survived because
# checks.microvm-boot fetches one every night. build.yml cannot notice --
# it pushes an entry once per commit, and an entry evicted a week later is not
# pushed again until something changes it. So the nightly puts back what it
# finds missing, and only fails when an entry is STILL missing after that --
# which is the token, or cachix.
#
# Evaluated, then built only when missing. Entries whose paths depend on the
# flake's rev (omarchy, the toplevels) are evaluated from the checkout this
# runs on, which is main -- the same tree build.yml pushed from.
set -uo pipefail

here=$(dirname "$0")
cache=${NARINFO_URL:-https://nixarchy.cachix.org}
push=${PUSH:-$here/cachix-push.sh}
retry_sleep=${RETRY_SLEEP:-20}

# The self-hosted runners have no curl on a step's PATH (AGENTS.md section 4),
# and GitHub's images do. Either way the question is only an HTTP status.
http_code() {
  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null -w '%{http_code}' "$1"
  else
    nix run --inputs-from . nixpkgs#curl -- -s -o /dev/null -w '%{http_code}' "$1"
  fi
}

served() { # served <installable> -> 0 when the cache has its output
  local path hash
  path=$(nix eval --raw "$1.outPath") || return 2
  hash=$(basename "$path" | cut -d- -f1)
  [ "$(http_code "$cache/$hash.narinfo")" = 200 ]
}

entries() {
  "$here/cache-allowlist.sh"
}

case "${1:-}" in
  probe)
    attrs=$(entries)
    [ -n "$attrs" ] || { echo "::error::the allowlist came back empty; refusing to report nothing missing" >&2; exit 2; }
    for attr in $attrs; do
      if served "$attr"; then
        echo "$attr: in the cache" >&2
      else
        echo "$attr: MISSING" >&2
        echo "$attr"
      fi
    done
    ;;

  repush)
    shift
    [ $# -gt 0 ] || { echo "usage: $0 repush <entry>..." >&2; exit 2; }
    fail=0
    for attr in "$@"; do
      echo "building $attr"
      nix build --no-link --print-build-logs "$attr" || {
        echo "::error::$attr did not build, so it cannot be put back in the cache" >&2
        fail=1
        continue
      }
      # Its own failure is not the verdict: cachix exits 0 on a rejected
      # token, so only the probe below says whether the path arrived.
      "$push" "$attr" || true

      # Three tries, as the omarchy probe does: a push that landed seconds
      # ago may not be served yet, and one 404 is not evidence of anything.
      ok=0
      for _ in 1 2 3; do
        if served "$attr"; then ok=1; break; fi
        sleep "$retry_sleep"
      done
      if [ "$ok" = 1 ]; then
        echo "$attr: pushed, and the cache serves it"
      else
        echo "::error::$attr was built and pushed and nixarchy.cachix.org still does not serve it." >&2
        echo "  cachix exits 0 when a token is rejected, so check CACHIX_AUTH_TOKEN first." >&2
        fail=1
      fi
    done
    exit "$fail"
    ;;

  *)
    echo "usage: $0 probe | repush <entry>..." >&2
    exit 2
    ;;
esac
