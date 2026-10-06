#!/usr/bin/env bash
# The body of the weekly release-candidate issue (#1199).
#
# Usage: release-candidate.sh <candidate-sha> <omarchy-version>
# Run in a full clone with origin/main, origin/release and the tags fetched.
# Prints nothing when release already contains the candidate.
#
# It proposes; it never tags. Moving `release` ships to every installed
# machine, so a human cuts the tag (README "Releasing").
set -euo pipefail

candidate=$(git rev-parse "$1^{commit}")
version="$2"

if git merge-base --is-ancestor "$candidate" origin/release; then
  exit 0
fi

# Highest packaging suffix already used for this Omarchy version, plus one.
# Dots escaped, or v4.0.4 would also match v4x0x4.
pattern="^v${version//./\\.}-[0-9]+\$"
last=$(git tag --list "v$version-*" | grep -E "$pattern" | sed 's/.*-//' | sort -n | tail -1 || true)
tag="v$version-$((${last:-0} + 1))"

short=$(git rev-parse --short "$candidate")
count=$(git rev-list --count "origin/release..$candidate")

if ! git merge-base --is-ancestor origin/release origin/main; then
  echo "**\`release\` is not an ancestor of \`main\`: a hotfix was not merged back.**"
  echo "Until it is, this release cannot move \`release\` (README \"Releasing\")."
  echo
fi

echo "The newest green nightly on \`main\` is \`$short\`, $(git log -1 --format=%s "$candidate")."
echo
echo "Proposed tag: \`$tag\`, $count commits since \`release\`."
echo
echo '```'
git --no-pager log --oneline -n 100 "origin/release..$candidate"
echo '```'
if [ "$count" -gt 100 ]; then
  echo
  echo "and $((count - 100)) more."
fi
echo
echo "This is valid until the next nightly goes green (03:00 UTC daily): the"
echo "release job accepts only the newest one. Re-run \`weekly.yml\` with"
echo "\`job: propose\` first if that has happened."
echo
echo "To release it:"
echo
echo '```sh'
echo "git tag -a $tag $candidate -m $tag"
echo "git push origin $tag"
echo '```'
