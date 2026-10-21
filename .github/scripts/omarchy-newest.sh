#!/usr/bin/env bash
# Prints latest=, current= and changed= for the nightly Omarchy bump (#1403).
# Follows RCs and never goes backwards: sort -V ranks 4.5.0 before 4.5.0-rc1,
# so '-' becomes '~', which sorts before the empty suffix. $GH is stubbable.
set -euo pipefail
current=${1:?usage: omarchy-newest.sh <current-tag>}
tag='^v[0-9]+(\.[0-9]+)*(-[A-Za-z0-9.]+)?$'
# Anchored: these values are pasted into later run: blocks (#1268).
[[ "$current" =~ $tag ]] || { echo "::error::'$current' is not a release tag" >&2; exit 1; }
# Capture first: a process substitution would hide a failed lookup (CLAUDE.md §4).
out=$(${GH:-gh} api repos/basecamp/omarchy/releases --paginate --jq '.[] | select(.draft|not) | .tag_name') ||
  { echo "::error::could not list Omarchy releases" >&2; exit 1; }
latest=$current
while IFS= read -r t; do
  [[ "$t" =~ $tag ]] || continue
  newer=$(printf '%s\n%s\n' "${latest/-/\~}" "${t/-/\~}" | sort -V | tail -n1)
  [ "$newer" = "${t/-/\~}" ] && latest=$t
done <<<"$out"
[ -n "$out" ] || { echo "::error::no Omarchy releases returned" >&2; exit 1; }
echo "latest=$latest"
echo "current=$current"
[ "$latest" = "$current" ] && echo "changed=false" || echo "changed=true"
