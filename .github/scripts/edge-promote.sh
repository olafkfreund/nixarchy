#!/usr/bin/env bash
# Advance the edge branch to a verified candidate, fast-forward only (#1278).
#
# Usage: edge-promote.sh <remote> <candidate-sha> <expected-edge-sha>
# <expected-edge-sha> is edge's head when the candidate was prepared, or the
# word "none" for the first publish.
#
# Two refusals, both exit 1 with the reason on stderr: edge moved since the
# candidate was prepared (stale), or the candidate does not descend from the
# expected head (not a fast-forward). The push is plain, never -f or
# --force-with-lease: edge is followed by users' flakes, so a rewrite of it
# would break their locks. Whether the gates passed is the workflow's `needs:`.
set -euo pipefail

die() {
  echo "edge-promote: $*" >&2
  exit 1
}

remote="$1"
candidate="$2"
expected="$3"

# Capture first: a failed ls-remote must not read as "edge is absent".
listing=$(git ls-remote "$remote" refs/heads/edge) || die "cannot list $remote"
head=${listing%%$'\t'*}
[ -n "$head" ] || head=none

[ "$head" = "$expected" ] ||
  die "stale: edge is $head on $remote, the candidate was prepared against $expected"

if [ "$expected" != none ]; then
  git fetch --quiet "$remote" refs/heads/edge || die "cannot fetch edge from $remote"
  git merge-base --is-ancestor "$expected" "$candidate" ||
    die "not a fast-forward: $expected is not an ancestor of $candidate"
fi

git push "$remote" "$candidate:refs/heads/edge"
