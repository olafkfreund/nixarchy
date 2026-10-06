#!/usr/bin/env bash
# The tag is not behind main, unless it is the newest green nightly (#1199).
#
# Usage: release-guard.sh <tag> <tagged-sha> <main-sha>
# NIGHTLY_SHA: head of the newest successful nightly.yml run on main, or empty.
#
# A tag behind main is how v4.0.2-7 shipped without a fix that was already
# merged (see the comment above the step in release.yml). The newest green
# nightly is the one behind-main commit that is released on purpose: it is
# the commit that was built, installed and booted, and everything after it
# has not been. An empty NIGHTLY_SHA (lookup failed, no green run) leaves only
# the old rule, so a broken lookup can refuse a release but never pass one.
set -euo pipefail

tag="$1"
tagged="$2"
main="$3"
nightly="${NIGHTLY_SHA:-}"

if [ "$tagged" = "$main" ]; then
  echo "$tag is the tip of main"
  exit 0
fi

# Not an ancestor: a hotfix branch or a tag off something else. Not
# what this guard is about, and refusing it would block a real case.
if ! git merge-base --is-ancestor "$tagged" "$main"; then
  echo "::notice::$tag is not on main; not a staleness question, continuing"
  exit 0
fi

if [ -n "$nightly" ] && [ "$tagged" = "$nightly" ]; then
  echo "::warning::$tag is the newest green nightly; these are on main and not in it:"
  git --no-pager log --oneline "$tagged..$main" | sed 's/^/  /'
  exit 0
fi

echo "::error::$tag is BEHIND main and would ship without these:"
git --no-pager log --oneline "$tagged..$main" | sed 's/^/  /'
if [ "${RELEASE_ALLOW_BEHIND_MAIN:-}" = "1" ]; then
  echo "::warning::RELEASE_ALLOW_BEHIND_MAIN=1, publishing anyway"
  exit 0
fi
echo ""
echo "Re-tag at main or at the newest green nightly, or set"
echo "RELEASE_ALLOW_BEHIND_MAIN=1 if this older commit is genuinely the one"
echo "to publish."
exit 1
