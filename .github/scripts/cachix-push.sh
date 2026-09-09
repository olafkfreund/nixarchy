#!/usr/bin/env bash
# Push the closure of named flake outputs to cachix, explicitly.
#
#   cachix-push.sh .#omarchy .#nixosConfigurations.vm.config.system.build.toplevel
#
# ## Why this exists, and why cachix-action is not enough
#
# cachix-action pushes the STORE DIFF: it snapshots the store when the job
# starts and uploads whatever appeared while the job ran. That is exactly right
# on a GitHub-hosted runner, whose store begins empty.
#
# Ours are self-hosted NixOS machines with WARM stores. A path built by any
# previous run already exists, so it falls outside the diff and is never
# uploaded -- and having been built once it can never become new again, so it
# is skipped forever. Measured on main at 8053b82a: 23684 skipped, 32 pushed,
# and omarchy's own path not even a candidate. nixarchy.cachix.org answered 404
# for it while every step of that job reported success, because pushing nothing
# IS success by the store-diff definition (#439).
#
# The perverse part: the better the local store works, the less reaches the
# cache users pull from.
#
# So this names what to push instead of inferring it. `-r` because the closure
# is the point -- a narinfo hit on omarchy alone still leaves a user building
# every one of its dependencies.
set -uo pipefail

[ $# -gt 0 ] || { echo "usage: $0 <flake-attr>..." >&2; exit 2; }

# A fork PR has no secret, and that is not a failure -- it is a PR that cannot
# push and does not need to. Said out loud rather than failing obscurely deep
# inside cachix.
if [ -z "${CACHIX_AUTH_TOKEN:-}" ]; then
  echo "no CACHIX_AUTH_TOKEN; not pushing (expected on a fork PR)"
  exit 0
fi

fail=0
for attr in "$@"; do
  # Already built by an earlier step in the same job -- this resolves the
  # output path without building, and says so plainly if it is missing rather
  # than silently pushing an empty list.
  if ! out=$(nix path-info "$attr" 2>/dev/null); then
    echo "::error::$attr is not built; push it from the job that builds it" >&2
    fail=1
    continue
  fi

  n=$(nix path-info -r "$attr" 2>/dev/null | wc -l)
  # A closure of zero is the failure this whole script exists to stop being
  # invisible. `nix path-info` above can succeed while `-r` yields nothing, and
  # piping that into cachix pushes an empty list and reports success -- which is
  # exactly how #439 stayed hidden through every green run.
  if [ "$n" -eq 0 ]; then
    echo "::error::$attr resolved to an EMPTY closure; refusing to call that a push" >&2
    fail=1
    continue
  fi
  echo "pushing $attr ($n paths in its closure)"
  if ! nix path-info -r "$attr" 2>/dev/null | cachix push nixarchy; then
    # Not fatal on its own: a cache upload failing must not fail a build that
    # succeeded (#235, and the reason every cachix step here is
    # continue-on-error). But it must be VISIBLE, because "pushed nothing" and
    # "push failed" looked identical for long enough to hide #439 completely.
    echo "::warning::pushing $attr to cachix failed" >&2
    fail=1
  fi
  echo "  $out"
done

exit "$fail"
