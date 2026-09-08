#!/usr/bin/env bash
# Can this change affect anything Nix builds?
#
# One copy, called by two workflows. install-check.yml has asked this question
# since #183; build.yml now asks the same one, and the reason this is a file
# rather than a second copy of the `case` is setup-nix's reason: eleven
# byte-identical blocks that were identical "by luck rather than by design".
# A denylist that is right in one workflow and stale in the other is worse
# than no denylist, because the stale one is still trusted.
#
# The list is a DENYLIST of paths that provably cannot change a derivation,
# never an allowlist of paths that can. install-check.yml's header records
# why, and it is worth restating because it is the whole safety argument:
# #123 changed hosts/<name>/ layout, which changed module ORDER, which
# changed the system path hash, and the installer then tried to build 517
# derivations offline. No file anyone would have listed as "installer" was
# touched. Nix closures are computed by evaluation, not by directory, so an
# allowlist silently stops covering the next directory somebody adds. A
# denylist can only be wrong about the few paths it names.
#
# Usage:  pr-touches-build.sh            # reads $EVENT_NAME/$GH_REPO/$PR_NUMBER
#         echo "$files" | pr-touches-build.sh -   # a file list on stdin
#
# Prints `true` or `false` on stdout. Nothing else goes to stdout.
set -euo pipefail

if [ "${1:-}" = "-" ]; then
  files=$(cat)
elif [ "${EVENT_NAME:-}" != "pull_request" ]; then
  # Not a pull request, so not filtered. main and workflow_dispatch always
  # ran the real thing and still do.
  echo true
  exit 0
else
  # The API, not `git diff`: actions/checkout gives a job a single commit by
  # default, so a diff against the base needs a deepened fetch whose depth is
  # a guess. The PR's file list is the same answer without one.
  files=$(gh api "repos/$GH_REPO/pulls/$PR_NUMBER/files" \
    --paginate --jq '.[].filename')
fi

# A pull request that changed no files is not a pull request. An empty list
# here means the question could not be answered -- a paginated API call that
# returned nothing, a permissions change, a renamed field -- and the cheap
# answer to an unanswerable question is `false`, which skips every build. So
# it fails SAFE instead: unknown means run everything. The cost of being
# wrong in this direction is a wasted job; in the other it is a merged
# regression nothing looked at.
if [ -z "$(printf '%s' "$files" | tr -d '[:space:]')" ]; then
  echo true
  exit 0
fi

# Order matters and this loop is where it is expressed: the re-includes are
# tested before the exclusions, so a change to the gate itself, or to this
# script, is relevant even though both live under .github/.
#
# `case` globs are not path-aware -- `*` crosses `/` -- which is what makes
# `docs/*` and `.github/*` cover nested files.
relevant=false
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    .github/workflows/install-check.yml) relevant=true; break ;;
    .github/workflows/build.yml) relevant=true; break ;;
    .github/scripts/pr-touches-build.sh) relevant=true; break ;;

    # README.md is NOT in this list, and that is deliberate rather than an
    # oversight. build.yml derives the app and command counts from data/ and
    # greps README.md for them, so a README-only edit can legitimately fail
    # the omarchy job -- it did on #424. Excluding it would turn a working
    # guard into one that only runs when something else changed too.
    docs/*|AGENTS.md|CONTRIBUTING.md|.envrc|.gitignore|.github/*)
      continue ;;

    *) relevant=true; break ;;
  esac
done <<EOF2
$files
EOF2

echo "$relevant"
