#!/usr/bin/env bash
# Explain a failed nightly from its jobs and the derivations named by its workflow.
set -Eeuo pipefail
export LC_ALL=C

what="initialising the digest"
digest_max=50000
emit() {
  local body=$1 delimiter note limit cut line open=false
  if (( ${#body} > digest_max )); then
    note="(digest cut at $digest_max bytes: this is a bug in nightly-digest.sh)"
    limit=$((digest_max - ${#note} - 6))
    cut=${body:0:limit}
    if [[ $cut == *$'\n'* ]]; then cut=${cut%$'\n'*}; else cut=""; fi
    while IFS= read -r line; do
      if [[ $line == '```'* ]]; then
        if [ "$open" = true ]; then open=false; else open=true; fi
      fi
    done <<<"$cut"
    body=$cut
    if [ "$open" = true ]; then body+=$'\n```'; fi
    body+=$'\n'"$note"
  fi
  # The delimiter is generated for each write, including the ERR path.
  delimiter="NIGHTLY_DIGEST_${RANDOM}_${RANDOM}_${RANDOM}"
  printf '%s\n' "$body"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      printf 'text<<%s\n' "$delimiter"
      printf '%s\n' "$body"
      printf '%s\n' "$delimiter"
    } >>"$GITHUB_OUTPUT"
  fi
}
# Called indirectly by the ERR trap.
# shellcheck disable=SC2329
unavailable() {
  trap - ERR
  emit "digest unavailable: $what" || true
  exit 0
}
trap 'unavailable' ERR

# Redact complete lines, including job names and annotations, before budgeting.
redact() {
  local line upper
  while IFS= read -r line || [ -n "$line" ]; do
    upper=${line^^}
    if [[ $upper =~ (GHP_|GHO_|GHS_|GHU_|GITHUB_PAT_|AGE-SECRET-KEY-|-----BEGIN) ]] ||
       [[ $upper =~ [A-Z_]*(TOKEN|SECRET|PASSWORD|KEY|AUTH)[A-Z_]*= ]]; then
      printf '%s\n' '[line removed: looked like a secret]'
    else
      printf '%s\n' "$line"
    fi
  done
}

# A successful but empty log is not a usable root. A failed log lookup is not
# a digest failure: the job may have stopped before Nix wrote that log.
read_log() {
  nix log --option substituters '' "$1" 2>/dev/null || true
}

in_window() {
  local base path mtime
  base=${1##*/}
  [[ $1 == /nix/store/*.drv && ${#base} -gt 2 ]] || return 1
  path="${NIX_LOG_DIR:-/nix/var/log/nix}/drvs/${base:0:2}/${base:2}"
  if [ ! -f "$path" ]; then path+=.bz2; fi
  [ -f "$path" ] || return 1
  mtime=$(stat -c %Y "$path") || return 1
  (( mtime >= window_start && mtime <= window_end ))
}

outputs_valid() {
  local drv=$1 outputs output
  what="reading outputs of $drv"
  outputs=$(nix-store -q --outputs "$drv") || return 2
  [ -n "$outputs" ] || return 2
  while IFS= read -r output; do
    [ -n "$output" ] || continue
    if ! nix-store --check-validity "$output" >/dev/null 2>&1; then
      return 1
    fi
  done <<<"$outputs"
  return 0
}

what="reading nightly jobs from GitHub"
[ -n "${GH_REPO:-}" ] || { what="GH_REPO is missing"; false; }
[ -n "${RUN_ID:-}" ] || { what="RUN_ID is missing"; false; }
jobs=$(gh api --paginate "repos/$GH_REPO/actions/runs/$RUN_ID/jobs") || unavailable
what="parsing nightly jobs"
failed=$(jq -sc '[.[] | .jobs[] | select(.conclusion == "failure" or .conclusion == "cancelled")] | .[]' <<<"$jobs") || unavailable
what="reading build targets from nightly.yml"
workflow=$(yq -o=json '.jobs | to_entries' .github/workflows/nightly.yml) || unavailable
excluded=$(jq -r '.[] | select(.key == "digest" or .key == "report") | .value.name // .key' <<<"$workflow") || unavailable
what="validating DIGEST_MAX"
digest_max=${DIGEST_MAX:-50000}
if [[ ! $digest_max =~ ^[0-9]+$ ]] || (( 10#$digest_max < 4096 )); then
  digest_max=50000
  what="DIGEST_MAX must be an integer of at least 4096"
  unavailable
fi

headers=()
target_labels=()
root_targets=()
root_labels=()
root_excerpts=()
while IFS= read -r job; do
  [ -n "$job" ] || continue
  name=$(jq -r '.name' <<<"$job") || unavailable
  skip=false
  while IFS= read -r excluded_name; do
    if [ "$name" = "$excluded_name" ]; then skip=true; break; fi
  done <<<"$excluded"
  if [ "$skip" = true ]; then continue; fi
  conclusion=$(jq -r '.conclusion' <<<"$job") || unavailable
  step=$(jq -r '[.steps[]? | select(.conclusion == "failure" or .conclusion == "cancelled") | .name][0] // "unknown"' <<<"$job") || unavailable
  status=failed
  if [ "$conclusion" = cancelled ]; then
    id=$(jq -r '.id' <<<"$job") || unavailable
    what="reading annotations for $name"
    annotations=$(gh api "repos/$GH_REPO/check-runs/$id/annotations") || unavailable
    # Any annotation: a job may warn before it times out.
    timed_out=$(jq -r 'any(.[]; .message // "" | ascii_downcase | contains("exceeded the maximum execution time"))' <<<"$annotations") || unavailable
    message=$(jq -r '.[0].message // ""' <<<"$annotations") || unavailable
    if [ "$timed_out" = true ]; then
      status="timed out"
    elif [ -n "$message" ]; then
      status="cancelled: $message"
    else
      status="cancelled"
    fi
  fi
  header=$(printf '### %s: %s at step "%s"' "$name" "$status" "$step" | redact) || unavailable
  headers+=("${header:0:300}")
  what="reading job window for $name"
  started=$(jq -r '.started_at' <<<"$job") || unavailable
  completed=$(jq -r '.completed_at' <<<"$job") || unavailable
  window_start=$(date -d "$started" +%s) || unavailable
  window_end=$(date -d "$completed" +%s) || unavailable
  window_start=$((window_start - 60))
  window_end=$((window_end + 60))

  what="finding build targets for $name"
  targets=$(jq -r --arg name "$name" '[.[] | select((.value.name // .key) == $name) | .value.steps[]? | .run // empty | scan("nix build[^\\n]*") | scan("\\.#[A-Za-z0-9._+-]+") | ltrimstr(".#")] | unique | .[]' <<<"$workflow") || unavailable
  while IFS= read -r attr; do
    [ -n "$attr" ] || continue
    what="evaluating $attr"
    drv=$(nix eval --raw ".#$attr.drvPath") || unavailable
    if outputs_valid "$drv"; then
      label=$(printf '%s: built' "$attr" | redact) || unavailable
      target_labels+=("$label")
      continue
    else
      rc=$?
      [ "$rc" -eq 1 ] || { what="reading outputs of $drv"; false; }
    fi
    what="reading derivation closure for $attr"
    closure=$(nix-store -qR "$drv") || unavailable
    roots=()
    while IFS= read -r root; do
      [[ $root == *.drv ]] || continue
      in_window "$root" || continue
      if outputs_valid "$root"; then
        continue
      else
        rc=$?
        [ "$rc" -eq 1 ] || { what="reading outputs of $root"; false; }
        # An empty log is not a usable root (read_log's rule).
        log=$(read_log "$root") || unavailable
        if [ -n "$log" ]; then roots+=("$root"); fi
      fi
    done <<<"$closure"
    if [ "${#roots[@]}" -eq 0 ]; then
      log=$(read_log "$drv") || unavailable
      if [ -n "$log" ]; then
        roots+=("$drv")
        if ! in_window "$drv"; then fallback_note=" (log from outside this job's run: may be an earlier build)"; else fallback_note=""; fi
      else
        label=$(printf '%s: no build log (it never started, or it was substituted)' "$attr" | redact) || unavailable
        target_labels+=("$label")
        continue
      fi
    else
      fallback_note=""
    fi
    label=$(printf '%s:' "$attr" | redact) || unavailable
    target_index=${#target_labels[@]}
    target_labels+=("$label")
    for root in "${roots[@]}"; do
      log=$(read_log "$root") || unavailable
      what="extracting the failure from $root"
      excerpt=$(printf '%s\n' "$log" | MAX=100000 "$(dirname "$0")/failure-excerpt.sh" | tail -n 40) || unavailable
      if [ -z "$excerpt" ]; then
        excerpt=$(printf '%s\n' "$log" | tail -n 10) || unavailable
      fi
      excerpt=$(printf '%s\n' "$excerpt" | redact) || unavailable
      short=${root##*/}; short=${short#*-}; short=${short%.drv}
      label=$(printf '**%s**%s' "$short" "$fallback_note" | redact) || unavailable
      root_targets+=("$target_index"); root_labels+=("$label"); root_excerpts+=("$excerpt")
    done
  done <<<"$targets"
done <<<"$failed"

digest=""
for header in "${headers[@]}"; do digest+="$header"$'\n'; done
root_count=${#root_labels[@]}
root_omission="($root_count more derivations not shown)"$'\n'
excerpt_omission="($root_count more excerpts not shown)"$'\n'
reserve=0
if (( root_count > 0 )); then reserve=$((${#root_omission} + ${#excerpt_omission})); fi

# Each append accounts for its framing and the omission lines reserved below.
append() {
  if (( ${#digest} + ${#1} + reserve <= digest_max )); then
    digest+=$1
    return 0
  fi
  return 1
}

for label in "${target_labels[@]}"; do digest+="$label"$'\n'; done

# Return a fenced excerpt within a byte allowance, cutting only at line ends.
excerpt_chunk() {
  local excerpt=$1 budget=$2 line content="" marker=$'(excerpt truncated)\n'
  chunk=""
  (( budget >= 8 )) || return 1
  while IFS= read -r line; do
    if (( ${#content} + ${#line} + 1 + 8 > budget )); then break; fi
    content+="$line"$'\n'
  done <<<"$excerpt"
  if (( ${#content} < ${#excerpt} + 1 )); then
    while (( ${#content} + ${#marker} + 8 > budget )) && [ -n "$content" ]; do
      content=${content%$'\n'}
      # Drop the last line; with no earlier line left, nothing remains.
      if [[ $content == *$'\n'* ]]; then content=${content%$'\n'*}$'\n'; else content=""; fi
    done
    (( ${#marker} + 8 <= budget )) || return 1
    content+=$marker
  fi
  chunk=$'```\n'"$content"$'```\n'
}

# Level 2: one root per target, sharing the available bytes evenly.
first_count=0
for i in "${!root_labels[@]}"; do
  if (( i == 0 )) || (( root_targets[i] != root_targets[i-1] )); then (( first_count += 1 )); fi
done
first_left=$first_count
shown_names=0
shown_excerpts=0
for i in "${!root_labels[@]}"; do
  if (( i > 0 )) && (( root_targets[i] == root_targets[i-1] )); then continue; fi
  share=$(( (digest_max - ${#digest} - reserve) / first_left ))
  first_left=$((first_left - 1))
  label="${root_labels[i]}"$'\n'
  if (( ${#label} <= share )) && append "$label"; then
    (( shown_names += 1 ))
    excerpt_chunk "${root_excerpts[i]}" "$((share - ${#label}))" || continue
    if append "$chunk"; then (( shown_excerpts += 1 )); fi
  fi
done

# Level 3: names of further roots, then the reserved omission line.
shown=()
for i in "${!root_labels[@]}"; do shown[i]=false; done
for i in "${!root_labels[@]}"; do
  if (( i == 0 )) || (( root_targets[i] != root_targets[i-1] )); then
    # The first name was already emitted if its excerpt fits this share.
    continue
  fi
  if append "${root_labels[i]}"$'\n'; then shown[i]=true; (( shown_names += 1 )); fi
done
reserve=$((${#excerpt_omission}))
if (( shown_names < root_count )); then digest+="($((root_count - shown_names)) more derivations not shown)"$'\n'; fi

# Level 4: remaining excerpts, preserving whole lines and closed fences.
for i in "${!root_labels[@]}"; do
  if [ "${shown[i]}" != true ]; then continue; fi
  available=$((digest_max - ${#digest} - reserve))
  excerpt_chunk "${root_excerpts[i]}" "$available" || continue
  if append "$chunk"; then (( shown_excerpts += 1 )); fi
done
if (( shown_excerpts < root_count )); then digest+="($((root_count - shown_excerpts)) more excerpts not shown)"$'\n'; fi
emit "${digest%$'\n'}"
exit 0
