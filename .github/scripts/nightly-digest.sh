#!/usr/bin/env bash
# Explain a failed nightly from its jobs and the derivations named by its workflow.
set -Eeuo pipefail

what="initialising the digest"
emit() {
  local body=$1 delimiter
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
  nix log "$1" 2>/dev/null || true
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
[[ $digest_max =~ ^[0-9]+$ ]]

headers=()
kinds=()
labels=()
excerpts=()
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
  headers+=("$header")

  what="finding build targets for $name"
  targets=$(jq -r --arg name "$name" '[.[] | select((.value.name // .key) == $name) | .value.steps[]? | .run // empty | scan("nix build[^\\n]*") | scan("\\.#[A-Za-z0-9._+-]+") | ltrimstr(".#")] | unique | .[]' <<<"$workflow") || unavailable
  while IFS= read -r attr; do
    [ -n "$attr" ] || continue
    what="evaluating $attr"
    drv=$(nix eval --raw ".#$attr.drvPath") || unavailable
    if outputs_valid "$drv"; then
      label=$(printf '%s: built' "$attr" | redact) || unavailable
      kinds+=(line); labels+=("$label"); excerpts+=("")
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
      if outputs_valid "$root"; then
        continue
      else
        rc=$?
        [ "$rc" -eq 1 ] || { what="reading outputs of $root"; false; }
        log=$(read_log "$root") || unavailable
        if [ -n "$log" ]; then roots+=("$root"); fi
      fi
    done <<<"$closure"
    if [ "${#roots[@]}" -eq 0 ]; then
      log=$(read_log "$drv") || unavailable
      if [ -n "$log" ]; then
        roots+=("$drv")
      else
        label=$(printf '%s: no build log (it never started, or it was substituted)' "$attr" | redact) || unavailable
        kinds+=(line); labels+=("$label"); excerpts+=("")
        continue
      fi
    fi
    label=$(printf '%s:' "$attr" | redact) || unavailable
    kinds+=(line); labels+=("$label"); excerpts+=("")
    for root in "${roots[@]}"; do
      log=$(read_log "$root") || unavailable
      what="extracting the failure from $root"
      excerpt=$(printf '%s\n' "$log" | MAX=100000 "$(dirname "$0")/failure-excerpt.sh" | tail -n 40) || unavailable
      if [ -z "$excerpt" ]; then
        excerpt=$(printf '%s\n' "$log" | tail -n 10) || unavailable
      fi
      excerpt=$(printf '%s\n' "$excerpt" | redact) || unavailable
      short=${root##*/}; short=${short#*-}; short=${short%.drv}
      label=$(printf '**%s**' "$short" | redact) || unavailable
      kinds+=(excerpt); labels+=("$label"); excerpts+=("$excerpt")
    done
  done <<<"$targets"
done <<<"$failed"

# Count all fixed text first. Only excerpts consume the remaining allowance;
# each one is cut at a complete line, preserving every job and target heading.
fixed=""
for header in "${headers[@]}"; do fixed+="$header"$'\n'; done
for i in "${!kinds[@]}"; do
  fixed+="${labels[i]}"$'\n'
  if [ "${kinds[i]}" = excerpt ]; then fixed+=$'```\n(excerpt truncated)\n```\n'; fi
done
remaining=$((digest_max - ${#fixed}))
(( remaining > 0 )) || remaining=0
digest=""
for header in "${headers[@]}"; do digest+="$header"$'\n'; done
for i in "${!kinds[@]}"; do
  digest+="${labels[i]}"$'\n'
  if [ "${kinds[i]}" = excerpt ]; then
    digest+=$'```\n'
    excerpt=${excerpts[i]}
    if (( ${#excerpt} + 1 <= remaining )); then
      digest+="$excerpt"$'\n'
      remaining=$((remaining - ${#excerpt} - 1))
    else
      if (( remaining > 0 )); then
        while IFS= read -r line; do
          if (( ${#line} + 1 > remaining )); then break; fi
          digest+="$line"$'\n'
          remaining=$((remaining - ${#line} - 1))
        done <<<"$excerpt"
      fi
      digest+=$'(excerpt truncated)\n'
      remaining=0
    fi
    digest+=$'```\n'
  fi
done
emit "${digest%$'\n'}"
exit 0
