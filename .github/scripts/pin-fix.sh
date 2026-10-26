#!/usr/bin/env bash
# When a nixpkgs bump breaks a commit-pinned input, propose moving that input
# to its upstream default branch -- as a draft, never merged by this script
# (#1459, plan decisions 3-8, 13, 14). Table: data/pin-fix.nix.
#
#   pin-fix.sh FAILURES_TSV                      the default run (workflow)
#   pin-fix.sh --decide OWNER COMPARE_JSON SHA   print `move <sha> <n>` or `refuse <why>`
#   pin-fix.sh --replace FLAKE_NIX INPUT OLD_FULL_SHA NEW_SHA
#   pin-fix.sh --moved BASE_LOCK NEW_LOCK        root inputs whose lock differs
#   pin-fix.sh --only-nixpkgs MAIN_LOCK PR_LOCK  exit 0 iff only nixpkgs moved
#   pin-fix.sh --sanitize                        stdin to stdout
#   pin-fix.sh --quote-subject                   stdin to stdout, one subject per line
#   pin-fix.sh --owner FIXTURE_JSON              `writable <pr>` or `held <why>`
#
# The default run reads $RUNNER_TEMP/base/{flake.nix,flake.lock} (the tree
# after the nixpkgs bump and before any move), and writes $PIN_FIX_OUT/{status,
# moved,body.md}. Every restore is a copy from base, never `git checkout`: a
# checkout would drop the nixpkgs bump too. Run from the repo root.
# Why: AGENTS.md section 5 (a sed that matches nothing exits 0 -- so count),
# section 13 (a field that may be empty is split by expansion, not `read`).
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() { echo "pin-fix: $*" >&2; exit 2; }

# Resolve a root input (a node name, or a follows path) to its node name.
JQ_RESOLVE='def resolve($lock):
  if type == "string" then .
  else . as $p | reduce $p[] as $k (null;
    if . == null then ($lock.nodes.root.inputs[$k] | resolve($lock))
    else ($lock.nodes[.].inputs[$k] | resolve($lock)) end)
  end;'

decide() {
  local owner=$1 file=$2 sha=$3 status ahead
  jq -e . "$file" >/dev/null 2>&1 || die "unreadable compare JSON: $file"
  [[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "refuse new commit is not a 40-hex sha"; return 0; }
  [ "$owner" != olafkfreund ] || { echo "refuse owner is olafkfreund (our own repo is not moved automatically)"; return 0; }
  status=$(jq -r '.status // ""' "$file")
  ahead=$(jq -r '.ahead_by // 0' "$file")
  [ "$status" = ahead ] || { echo "refuse pin is $status relative to the default branch, not ahead"; return 0; }
  [[ $ahead =~ ^[0-9]+$ ]] || { echo "refuse ahead_by is not a number"; return 0; }
  { [ "$ahead" -ge 1 ] && [ "$ahead" -le 100 ]; } ||
    { echo "refuse ahead_by $ahead is outside 1..100"; return 0; }
  echo "move $sha $ahead"
}

# The line number of INPUT's url line inside its `INPUT = {` block.
url_line() {
  awk -v n="$2" '
    $0 ~ "^[ \t]*" n " = \\{" { b = 1; next }
    b && /^[ \t]*};/ { exit }
    b && /url = "github:/ { print NR; exit }' "$1"
}

# owner/repo/ref from INPUT'"'"'s url in FLAKE_NIX, or non-zero.
url_of() {
  local ln line
  ln=$(url_line "$1" "$2") && [ -n "$ln" ] || return 1
  line=$(sed -n "${ln}p" "$1")
  [[ $line =~ url\ =\ \"github:([^/\"]+)/([^/\"]+)/([^\"?]+)\" ]] || return 1
  printf '%s/%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
}

replace() {
  local f=$1 in=$2 old=$3 new=$4 spec o r ref ln tmp
  [[ $old =~ ^[0-9a-f]{40}$ ]] || { echo "pin-fix: old sha is not 40-hex" >&2; return 1; }
  [[ $new =~ ^[0-9a-f]{40}$ ]] || { echo "pin-fix: new sha is not 40-hex" >&2; return 1; }
  spec=$(url_of "$f" "$in") || { echo "pin-fix: no github url with a ref in the $in block" >&2; return 1; }
  IFS=/ read -r o r ref <<<"$spec"
  [ "${#ref}" -ge 7 ] && [[ $old == "$ref"* ]] ||
    { echo "pin-fix: ref '$ref' is not a prefix of $old" >&2; return 1; }
  [ "$(grep -cF "github:$o/$r/$ref\"" "$f")" = 1 ] ||
    { echo "pin-fix: github:$o/$r/$ref is not in $f exactly once" >&2; return 1; }
  ln=$(url_line "$f" "$in")
  tmp="$f.pin-fix.$$"
  awk -v ln="$ln" -v from="github:$o/$r/$ref\"" -v to="github:$o/$r/$new\"" '
    NR == ln { i = index($0, from); $0 = substr($0, 1, i - 1) to substr($0, i + length(from)) }
    { print }' "$f" >"$tmp" || { rm -f "$tmp"; return 1; }
  if [ "$(grep -cF "github:$o/$r/$new\"" "$tmp")" != 1 ] ||
    [ "$(grep -cF "github:$o/$r/$ref\"" "$tmp")" != 0 ] ||
    [ "$(diff "$f" "$tmp" | grep -c '^<')" != 1 ] ||
    [ "$(diff "$f" "$tmp" | grep -c '^>')" != 1 ]; then
    rm -f "$tmp"
    echo "pin-fix: the edit did not change exactly one line" >&2
    return 1
  fi
  cat "$tmp" >"$f"
  rm -f "$tmp"
}

moved() {
  jq -r --slurpfile a "$1" --slurpfile b "$2" "$JQ_RESOLVE"'
    $a[0] as $A | $b[0] as $B
    | if ($A.nodes.root.inputs | keys) != ($B.nodes.root.inputs | keys)
      then error("root input set differs") else . end
    | ($A.nodes.root.inputs | to_entries[]) as $e
    | ($e.value | resolve($A)) as $na
    | ($B.nodes.root.inputs[$e.key] | resolve($B)) as $nb
    | select($A.nodes[$na].locked != $B.nodes[$nb].locked)
    | $e.key' -n || return 2
}

only_nixpkgs() {
  jq -e -n --slurpfile m "$1" --slurpfile p "$2" "$JQ_RESOLVE"'
    $m[0] as $M | $p[0] as $P
    | ($M.nodes.root.inputs.nixpkgs | resolve($M)) as $nm
    | ($P.nodes.root.inputs.nixpkgs | resolve($P)) as $np
    | $nm == $np and (($P | .nodes[$np].locked = $M.nodes[$nm].locked) == $M)' >/dev/null
}

# The five skip-CI markers are built from parts so the source never holds one.
sanitize() {
  local sp='[[:space:]]+' w1=ski w2=p c=c i=i n=no a=actions re
  local skip="${w1}${w2}" ci="${c}${i}"
  re="\\[[[:space:]]*(${skip}${sp}${ci}|${ci}${sp}${skip}|${n}${sp}${ci}|${skip}${sp}${a}|${a}${sp}${skip})[[:space:]]*\\]"
  sed -E "s/${re}/(skip-ci marker removed)/gI"
}

# Backticks inside a subject are deleted, then it is wrapped, so an @user or
# #123 in an upstream subject cannot link or notify.
quote_subject() {
  local s
  while IFS= read -r s || [ -n "$s" ]; do
    s=${s//\`/}
    printf '`%s`\n' "$s"
  done
}

owner() {
  jq -r '
    . as $f
    | if ($f.branch_exists | not) then "writable "
      elif ($f.pr == null or $f.pr.state != "OPEN") then "writable "
      elif ($f.pr.isDraft | not) then "held PR #\($f.pr.number) is ready for review, not a draft"
      elif $f.pr.author != $f.bot then "held PR #\($f.pr.number) is authored by \($f.pr.author), not \($f.bot)"
      elif ([$f.commits[] | .message | split("\n") | any(. == "Generated by .github/workflows/flake-update.yml.")] | all) then "writable \($f.pr.number)"
      else "held PR #\($f.pr.number) carries a commit this workflow did not write" end' "$1" ||
    die "unreadable owner fixture: $1"
}

past_deadline() {
  [ "${PIN_FIX_DEADLINE:-0}" -gt 0 ] && [ "$(date +%s)" -gt "$PIN_FIX_DEADLINE" ]
}

# ---- the default run -------------------------------------------------------

run() {
  local fails=$1 base out table names name probe
  base=${RUNNER_TEMP:?RUNNER_TEMP unset}/base
  out=${PIN_FIX_OUT:?PIN_FIX_OUT unset}
  [ -s "$base/flake.nix" ] && [ -s "$base/flake.lock" ] || die "no baseline in $base"
  [ -r "$fails" ] || die "cannot read $fails"
  mkdir -p "$out"
  : >"$out/moved"
  echo unfixed >"$out/status"
  : >"$out/body.md"

  table=$(nix eval --json -f data/pin-fix.nix) || die "cannot read data/pin-fix.nix"
  local failing
  failing=$(cut -f1 "$fails" | sed 's/^\.#//')

  local -a movable=()
  declare -A m_old=() m_new=() m_ahead=() m_repo=() m_probe=()
  local -a notes=()

  restore() { cp "$base/flake.nix" flake.nix && cp "$base/flake.lock" flake.lock; }

  names=$(jq -r 'keys[]' <<<"$table") || die "bad table"
  for name in $names; do
    probe=$(jq -r --arg n "$name" '.[$n].probe' <<<"$table")
    grep -qxF "$probe" <<<"$failing" || continue
    if past_deadline; then notes+=("- \`$name\`: not tried: deadline"); continue; fi
    local spec o r ref repo old branch new cmp d
    spec=$(url_of "$base/flake.nix" "$name") || { notes+=("- \`$name\`: refused: no github url with a ref in flake.nix"); continue; }
    IFS=/ read -r o r ref <<<"$spec"
    repo="$o/$r"
    old=$(jq -r --arg n "$name" "$JQ_RESOLVE"'. as $L | ($L.nodes.root.inputs[$n] | resolve($L)) as $x | $L.nodes[$x].locked.rev // ""' "$base/flake.lock") || old=""
    [[ $old =~ ^[0-9a-f]{40}$ ]] || { notes+=("- \`$name\`: refused: no 40-hex locked rev in the baseline lock"); continue; }
    [[ $old == "$ref"* ]] || { notes+=("- \`$name\`: refused: url ref \`$ref\` is not a prefix of the locked rev"); continue; }
    branch=$(gh api "repos/$repo" --jq .default_branch 2>/dev/null) || branch=""
    [ -n "$branch" ] || { notes+=("- \`$name\`: refused: could not read the default branch of $repo"); continue; }
    new=$(gh api "repos/$repo/commits/$branch" --jq .sha 2>/dev/null) || new=""
    [[ $new =~ ^[0-9a-f]{40}$ ]] || { notes+=("- \`$name\`: refused: could not resolve $repo@$branch to a sha"); continue; }
    cmp="$out/compare-$name.json"
    gh api "repos/$repo/compare/$old...$new" >"$cmp" 2>/dev/null || { notes+=("- \`$name\`: refused: could not compare $old...$new"); continue; }
    d=$(decide "$o" "$cmp" "$new") || d="refuse unreadable compare JSON"
    case "$d" in
      move*)
        movable+=("$name")
        m_old[$name]=$old m_new[$name]=$new m_repo[$name]=$repo m_probe[$name]=$probe
        m_ahead[$name]=${d##* }
        ;;
      *) notes+=("- \`$name\`: refused: ${d#refuse }") ;;
    esac
  done

  # Apply NAMES to the baseline; with GATE=1 also require the batch to pass.
  apply() {
    local gate=$1 n; shift
    restore || return 1
    for n in "$@"; do
      replace flake.nix "$n" "${m_old[$n]}" "${m_new[$n]}" || return 1
    done
    nix flake lock >&2 || return 1
    local got want
    got=$(moved "$base/flake.lock" flake.lock | sort) || return 1
    want=$(printf '%s\n' "$@" | sort)
    [ "$got" = "$want" ] || { echo "pin-fix: moved set '$got' != '$want'" >&2; return 1; }
    # 3 = the move applied cleanly and only the gate said no.
    [ "$gate" = 0 ] || "$here/eval-gate.sh" --batch-only || return 3
  }

  local -a final=()
  local m rc
  for m in "${movable[@]}"; do
    if past_deadline; then notes+=("- \`$m\`: not tried: deadline"); continue; fi
    if [ "${#final[@]}" = 0 ]; then
      apply 1 "$m"
      rc=$?
    else
      rc=skip
    fi
    if [ "$rc" = 0 ]; then
      final=("$m")
    elif [ "$rc" = 3 ] &&
      nix path-info --derivation --no-eval-cache ".#${m_probe[$m]}" >/dev/null 2>&1; then
      notes+=("- \`$m\`: moving it fixes \`${m_probe[$m]}\`, but other targets still fail (compare: https://github.com/${m_repo[$m]}/compare/${m_old[$m]}...${m_new[$m]})")
    elif [ "$rc" != skip ]; then
      notes+=("- \`$m\`: moving it alone does not make every target evaluate")
    else
      notes+=("- \`$m\`: not tried: \`${final[0]}\` already fixes the batch")
    fi
  done
  if [ "${#final[@]}" = 0 ] && [ "${#movable[@]}" -gt 1 ] && ! past_deadline; then
    if apply 1 "${movable[@]}"; then
      final=("${movable[@]}")
      local -a cur=("${final[@]}") cand
      for m in "${final[@]}"; do
        past_deadline && break
        cand=()
        local c
        for c in "${cur[@]}"; do [ "$c" = "$m" ] || cand+=("$c"); done
        [ "${#cand[@]}" -gt 0 ] || continue
        if apply 1 "${cand[@]}"; then cur=("${cand[@]}"); fi
      done
      final=("${cur[@]}")
    else
      notes+=("- all candidates together do not make every target evaluate")
    fi
  fi

  if [ "${#final[@]}" -gt 0 ]; then
    apply 0 "${final[@]}" || { restore; die "could not re-apply the passing moves"; }
    printf '%s\n' "${final[@]}" >"$out/moved"
    echo fixed >"$out/status"
  else
    restore || die "could not restore the baseline"
  fi

  {
    if [ "${#final[@]}" -gt 0 ]; then
      echo "### Proposed pin moves"
      echo
      for m in "${final[@]}"; do
        echo "- \`$m\`: \`${m_old[$m]:0:12}\` -> \`${m_new[$m]:0:12}\`, ${m_ahead[$m]} commit(s) ahead"
        echo "  https://github.com/${m_repo[$m]}/compare/${m_old[$m]}...${m_new[$m]}"
      done
      for m in "${final[@]}"; do
        echo
        echo "#### \`$m\`: commits"
        echo
        jq -r '.commits[:100][] | [.sha[0:7], (.commit.author.name // ""), (.commit.message | split("\n")[0])] | join("\u001f")' "$out/compare-$m.json" |
          while IFS=$'\037' read -r sha au subj; do
            printf -- '- %s %s: %s\n' "$sha" "$(printf '%s' "$au" | quote_subject)" "$(printf '%s' "$subj" | quote_subject)"
          done
      done
    else
      echo "### No pin move proposed"
    fi
    if [ "${#notes[@]}" -gt 0 ]; then
      echo
      echo "### Not moved"
      echo
      printf '%s\n' "${notes[@]}"
    fi
  } | sanitize >"$out/body.md"
}

case "${1:-}" in
  --decide) [ $# = 4 ] || die "usage: --decide OWNER COMPARE_JSON NEW_SHA"; decide "$2" "$3" "$4" ;;
  --replace) [ $# = 5 ] || die "usage: --replace FLAKE_NIX INPUT OLD_SHA NEW_SHA"; replace "$2" "$3" "$4" "$5" ;;
  --moved)
    [ $# = 3 ] || die "usage: --moved BASE_LOCK NEW_LOCK"
    moved "$2" "$3"
    ;;
  --only-nixpkgs) [ $# = 3 ] || die "usage: --only-nixpkgs MAIN_LOCK PR_LOCK"; only_nixpkgs "$2" "$3" ;;
  --sanitize) sanitize ;;
  --quote-subject) quote_subject ;;
  --owner) [ $# = 2 ] || die "usage: --owner FIXTURE_JSON"; owner "$2" ;;
  -*) die "unknown mode $1" ;;
  "") die "usage: see the header" ;;
  *) run "$1" ;;
esac
