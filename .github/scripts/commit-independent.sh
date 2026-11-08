#!/usr/bin/env bash
set -euo pipefail

# The nightly runner provides jq and nix on PATH.
untracked=$(git ls-files --others --exclude-standard) || exit 1
if ! git diff --quiet HEAD || ! git diff --cached --quiet || [ -n "$untracked" ]; then
  echo 'commit-independent: dirty tree' >&2
  exit 2
fi

scratch_root=${RUNNER_TEMP:-/mnt/data/vmtest}
if [ ! -d "$scratch_root" ]; then
  echo "commit-independent: scratch directory missing: $scratch_root" >&2
  exit 2
fi
scratch=$(mktemp -d "$scratch_root/commit-independent.XXXXXX") || exit 1
trap 'git worktree remove --force "$scratch/tree" 2>/dev/null; rm -rf "$scratch"; git worktree prune' EXIT
git worktree add --detach "$scratch/tree" HEAD

bound=$(nix eval --json --file data/commit-bound-checks.nix --apply builtins.attrNames) || exit 1
all=$(nix eval --json "git+file://$scratch/tree#checks.x86_64-linux" --apply builtins.attrNames) || exit 1
missing=$(jq -nr --argjson bound "$bound" --argjson all "$all" '$bound - $all | .[]') || exit 1
if [ -n "$missing" ]; then
  printf 'commit-independent: bound name is not a check: %s\n' "$missing" >&2
  exit 1
fi

requested=("$@")
if [ "$#" -eq 0 ]; then
  names=$(jq -nr --argjson bound "$bound" --argjson all "$all" '$all - $bound | .[]') || exit 1
  if [ -n "$names" ]; then
    mapfile -t requested <<< "$names"
  fi
fi
count=${#requested[@]}

evalall() {
  local tag=$1 c out start end
  : > "$scratch/$tag.tsv"
  for c in "${requested[@]}"; do
    start=$(date +%s) || exit 1
    out=$(nix eval --raw "git+file://$scratch/tree#checks.x86_64-linux.$c.outPath") || {
      echo "$c: does not evaluate" >&2
      exit 1
    }
    end=$(date +%s) || exit 1
    printf '%s\t%s\n' "$c" "$out" >> "$scratch/$tag.tsv"
    printf '%s: %s seconds\n' "$c" "$((end - start))" >&2
  done
}

evalall before
ct=$(git -C "$scratch/tree" log -1 --format=%ct) || exit 1
printf '%s\n' probe > "$scratch/tree/.commit-probe" &&
  git -C "$scratch/tree" add .commit-probe &&
  GIT_COMMITTER_DATE="@$((ct + 172800))" \
    git -C "$scratch/tree" -c user.name=commit-probe -c user.email=probe@invalid commit -q -m probe || exit 1
evalall after

before_count=$(wc -l < "$scratch/before.tsv") || exit 1
after_count=$(wc -l < "$scratch/after.tsv") || exit 1
if [ "$before_count" -ne "$count" ] || [ "$after_count" -ne "$count" ]; then
  echo "commit-independent: compared $before_count of $count before; $after_count of $count after" >&2
  exit 1
fi

awk -F '\t' 'NR == FNR { before[$1] = $2; next }
  $2 != before[$1] { printf "%s  %s  %s\n", $1, before[$1], $2; moved = 1 }
  END { exit moved }' "$scratch/before.tsv" "$scratch/after.tsv" || exit 1
echo "commit-independent: $count checks, none moved"
