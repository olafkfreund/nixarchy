#!/usr/bin/env bash
set -euo pipefail

# shortcut: trusts the author; a hand-made commit with the bot's identity reads
# as disposable. Upgrade to a recorded last-pushed SHA if that ever happens.
for ref in edge edge-candidate; do
  if git show-ref --verify --quiet "refs/remotes/origin/$ref"; then
    continue
  else
    status=$?
    [ "$status" -eq 1 ] || exit "$status"
    echo none
    exit 0
  fi
done

authors=$(git log origin/edge..origin/edge-candidate --not origin/main --format=%ae)
if [ -n "$authors" ]; then
  while IFS= read -r author; do
    if [ "$author" != '41898282+github-actions[bot]@users.noreply.github.com' ]; then
      if git merge-base --is-ancestor origin/edge origin/edge-candidate; then
        echo carry
        exit 0
      else
        status=$?
        [ "$status" -eq 1 ] || exit "$status"
        echo diverged
        exit 0
      fi
    fi
  done <<< "$authors"
fi

echo none
