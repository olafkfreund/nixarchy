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
#
# ## What may be pushed, and from where (#697)
#
# The cache is the free tier: 5 GB, evicted by last download. So closures --
# cache-allowlist.sh's entries -- are pushed from main only, and a check's
# result is pushed from any ref with --proof:
#
#   cachix-push.sh --proof <check>...
#
# A proof is the result path ALONE. `cachix push` has no way to omit
# dependencies, so a result that references anything would upload a closure;
# that is refused (a warning, not a failure) rather than filling the cache.
set -uo pipefail

usage() {
  echo "usage: $0 <flake-attr>...   (closures; main only)" >&2
  echo "       $0 --proof <check>...  (one check result each; any ref)" >&2
  exit 2
}

proof=false
if [ "${1:-}" = --proof ]; then
  proof=true
  shift
fi
[ $# -gt 0 ] || usage

# The largest result a proof may be. Measured results are 96 bytes to 12 KB.
proof_max_bytes=${PROOF_MAX_BYTES:-1048576}
system=${NIXARCHY_SYSTEM:-x86_64-linux}

# A fork PR has no secret, and that is not a failure -- it is a PR that cannot
# push and does not need to. Said out loud rather than failing obscurely deep
# inside cachix.
#
# A job that ran cachix-action has the token in cachix's own config instead of
# the environment, and build-unless-proven.sh is called from those jobs.
if [ -z "${CACHIX_AUTH_TOKEN:-}" ] &&
  [ ! -s "${XDG_CONFIG_HOME:-$HOME/.config}/cachix/cachix.dhall" ]; then
  echo "no cachix token; not pushing (expected on a fork PR)"
  exit 0
fi

if [ "$proof" = true ]; then
  # Three outcomes, not two. Counting a refusal as a failure made this script
  # exit 1 on EVERY run -- checks.nixi is the nixi package (flake.nix), so its
  # result is 92 paths and 567 MB and can never be a proof -- and
  # build-unless-proven.sh discards that with `|| true`. Measured on
  # 2026-09-16: exit 1 with 39 of 40 pushed, which is indistinguishable from
  # exit 1 with 0 of 40. A step whose failure is guaranteed and discarded
  # reports nothing (#729).
  #
  # So: a result that cannot be a proof is a CATEGORY, not an error. Only
  # `cachix push` itself failing is a failure, and only that sets the exit
  # status.
  pushed=0
  skipped=0
  failed=0
  for c in "$@"; do
    c=${c#".#checks.$system."}
    if ! out=$(nix eval --raw ".#checks.$system.$c" 2>/dev/null) ||
      ! nix path-info "$out" >/dev/null 2>&1; then
      # Under --keep-going a failed check produces no output. The build's own
      # exit status already reports that; saying it twice, as a push failure,
      # points the reader at the cache instead of at the check.
      echo "::warning::$c has no built result here; no proof pushed" >&2
      skipped=$((skipped + 1))
      continue
    fi
    n=$(nix path-info -r "$out" 2>/dev/null | wc -l)
    size=$(nix path-info -r --json "$out" 2>/dev/null | jq '[.[] | .narSize] | add // 0')
    if [ "$n" -ne 1 ] || [ "$size" -gt "$proof_max_bytes" ]; then
      echo "::warning::$c's result is $n paths and $size bytes; a proof is one path under $proof_max_bytes bytes, so it is not pushed" >&2
      skipped=$((skipped + 1))
      continue
    fi
    echo "pushing the proof of $c ($size bytes)"
    if cachix push nixarchy "$out"; then
      pushed=$((pushed + 1))
    else
      echo "::warning::pushing the proof of $c failed" >&2
      failed=$((failed + 1))
    fi
  done
  # One line, so the log states the outcome rather than leaving it to be
  # inferred from an exit status that used to mean nothing.
  echo "proofs: $pushed pushed, $skipped skipped (unproofable), $failed failed"
  [ "$failed" -eq 0 ] || exit 1
  exit 0
fi

# Closures come from main. A pull request, a bump branch or a tag pushing its
# builds is what filled the cache with paths nobody would ever download.
if [ "${GITHUB_REF:-}" != refs/heads/main ]; then
  echo "not main; closures are pushed from main only (${GITHUB_REF:-no GITHUB_REF})"
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
