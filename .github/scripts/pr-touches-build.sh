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
# TWO questions, one denylist, plus a narrower second list.
#
# build.yml asks "can this change anything Nix builds?" -- a new tests/foo.nix
# is a new derivation, so yes. install-check.yml asks the narrower "can this
# change an INSTALL?", and for that a new check that the install job does not
# build is a 30-minute VM for nothing. Measured: 26 to 46 minutes per run,
# serialised behind one slot.
#
# `--install` adds the second list. It stays a denylist for the reason the
# header gives, and every entry names why that path cannot reach the install
# closure -- an entry without one is a guess, and a wrong guess here merges a
# broken installer.
#
# Usage:  pr-touches-build.sh            # reads $EVENT_NAME/$GH_REPO/$PR_NUMBER
#         pr-touches-build.sh --install  # the narrower question
#         echo "$files" | pr-touches-build.sh -   # a file list on stdin
#
# Prints `true` or `false` on stdout. Nothing else goes to stdout.
set -euo pipefail

install_only=false
if [ "${1:-}" = "--install" ]; then
  install_only=true
  shift
fi

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
    # `AGENTS.md` matched only at the root, so installer/AGENTS.md and
    # modules/AGENTS.md fell through to `*` and ran the whole build -- and,
    # once install-check grew its own narrower list, a 26-46 minute VM install
    # for a markdown file. Every AGENTS.md in this repository is documentation
    # for agents; verified that nothing reads one into a derivation, and the
    # only mentions in .nix files and scripts are comments citing it.
    #
    # `*/AGENTS.md` covers any depth, because `case` globs are not path-aware
    # and `*` crosses `/` -- the same property the `docs/*` arm relies on.
    docs/*|AGENTS.md|*/AGENTS.md|CONTRIBUTING.md|.envrc|.gitignore|.github/*)
      continue ;;

    # Only for the install question, and only files the install job cannot
    # reach. install-check.yml builds exactly three checks -- install,
    # free-space and installer-refusal -- and those three import only
    # ./hardware-configuration.nix and ./test-instrumentation.nix from this
    # directory. Verified by reading them, not assumed; the five names below
    # are re-included above this arm so they keep triggering it.
    #
    # Everything else under tests/ is a SEPARATE derivation that build.yml
    # builds and this job never touches. tests/substitutable.nix cost a
    # 37-minute VM install on the day it was added, and could not have
    # changed one byte of an install.
    tests/install.nix|tests/free-space.nix|tests/installer-refusal.nix)
      relevant=true; break ;;
    tests/hardware-configuration.nix|tests/test-instrumentation.nix)
      relevant=true; break ;;
    tests/*)
      if [ "$install_only" = true ]; then continue; fi
      relevant=true; break ;;

    *) relevant=true; break ;;
  esac
done <<EOF2
$files
EOF2

echo "$relevant"
