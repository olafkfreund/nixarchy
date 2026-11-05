#!/usr/bin/env bash
# The `report` job of omarchy-edge.yml: say what happened to edge, in issues.
# Two issues, never mixed: "not publishing" means edge did not publish;
# "held back" means upstream quattro is refused and edge kept its last good
# pin (#1602). No continue-on-error here: a failed `gh` must fail the job (§4).
set -euo pipefail

now=${EDGE_REPORT_NOW:-$(date +%s)}
NOT_PUB="The Omarchy edge channel is not publishing"
HELD_T="Omarchy quattro is held back"
LISTED=" bin-ledger etc-overlay etc-sysctl menu-actions menu-conditions menu-verbs omarchy-package-ledger skill-parity stale-scripts "

# Captured first, then parsed: a failing command inside a pipe or a process
# substitution is invisible (§4), and --jq renders null as nothing (§13).
# `|| return`, because callers run this in $(...), where bash clears set -e, and
# a failed listing would read as "no open issue".
find_issue() { # label title
  local out
  out=$(gh issue list --label "$1" --state open --json number,title) || return
  jq -r --arg t "$2" '[.[] | select(.title == $t)][0].number // empty' <<<"$out"
}
close_issue() { # number comment
  [ -z "$1" ] || gh issue close "$1" --comment "$2"
}

# post <label> <colour> <description> <title> <prefix> <sig> <extra> <digest>
# Files the issue, or comments only when the signature line changed: the same
# red every night is one comment, not thirty. Leaves ISSUE_JSON for escalation.
ISSUE_JSON=""
ISSUE_NUM=""
post() {
  local label=$1 colour=$2 desc=$3 title=$4 prefix=$5 sig=$6 extra=$7 digest=$8 body last
  body=$(printf '%s\n\n%s\n' "$prefix: $sig" "Run: $RUN_URL")
  [ -z "$extra" ] || body=$(printf '%s\n\n%s\n' "$body" "$extra")
  [ -z "$digest" ] || body=$(printf '%s\n\n```text\n%s\n```\n' "$body" "$digest")
  gh label create "$label" --force --description "$desc" --color "$colour"
  ISSUE_NUM=$(find_issue "$label" "$title")
  if [ -z "$ISSUE_NUM" ]; then
    gh issue create --label "$label" --milestone "Keeping the lights on" \
      --title "$title" --body "$body"
    return 0
  fi
  ISSUE_JSON=$(gh issue view "$ISSUE_NUM" --json body,comments,createdAt)
  # The newest signature line anywhere, so a person's comment after it does
  # not make the next run post the same failure again.
  last=$(jq -r --arg p "$prefix: " '[.body // "", (.comments[]? | .body // "")]
    | map(split("\n")[] | select(startswith($p))) | last // ""' <<<"$ISSUE_JSON")
  if [ "$last" = "$prefix: $sig" ]; then
    echo "same as the last signature ($sig); not commenting"
  else
    gh issue comment "$ISSUE_NUM" --body "$body"
  fi
}

report_held() {
  local names=${HELD_BY:-} extra n known=true created age
  if [ -z "$names" ]; then known=false; fi
  for n in $names; do
    case "$LISTED" in *" $n "*) ;; *) known=false ;; esac
  done
  if [ "$known" = true ]; then
    extra="Upstream's newest commit needs a classification row or a recorded sysctl decision in data/etc-overlay.nix before edge can adopt it. Edge stays on its last good pin meanwhile."
  else
    extra="upstream candidate failed; investigate. Edge stays on its last good pin meanwhile."
  fi
  post omarchy-edge-held fbca04 "Upstream quattro is refused; edge kept its last good pin" \
    "$HELD_T" held-sig "${HELD_SHA:0:7}: ${names:-unknown}" "$extra" "${HELD_DIGEST:-}"
  # Escalate once, whether or not the signature changed.
  [ -n "$ISSUE_JSON" ] || return 0
  created=$(jq -r '.createdAt' <<<"$ISSUE_JSON")
  age=$((now - $(date -d "$created" +%s)))
  if [ "$age" -gt 72000 ] && ! jq -e '[.comments[]? | .body // "" | startswith("held-escalated:")] | any' <<<"$ISSUE_JSON" >/dev/null; then
    gh issue comment "$ISSUE_NUM" --body "held-escalated: quattro has been held back for more than 20 hours. $RUN_URL"
  fi
}

# "<names>; timed out" for a cancelled job, "<names>" or the result otherwise.
tail_of() { # names result
  if [ "$2" = cancelled ]; then
    if [ -n "$1" ]; then echo "$1; timed out"; else echo "timed out"; fi
  else
    echo "${1:-$2}"
  fi
}

PREPARE=${PREPARE:-} WAIT=${WAIT:-} VERIFY=${VERIFY:-} CANDIDATE=${CANDIDATE:-} SKIP=${SKIP:-}
PROMOTED=${PROMOTED:-} FALLBACK=${FALLBACK:-} NEWEST=${NEWEST:-} BUILD2=${BUILD2:-}
PREPARE_FAILED=${PREPARE_FAILED:-} HELD_BY=${HELD_BY:-} HELD_SHA=${HELD_SHA:-}
VERIFY_FAILED=${VERIFY_FAILED:-} PREPARE_DIGEST=${PREPARE_DIGEST:-} VERIFY_DIGEST=${VERIFY_DIGEST:-}

nopub=$(find_issue omarchy-edge "$NOT_PUB")
held=$(find_issue omarchy-edge-held "$HELD_T")

# A cancel after edge-promote pushed but before it wrote promoted=true
# would report a failure for a promoted edge. Ask the remote.
if [ "$PROMOTED" != true ] && [ -n "$CANDIDATE" ] && [ "$VERIFY" != success ]; then
  current=$(gh api "repos/$GH_REPO/git/ref/heads/edge" --jq .object.sha 2>/dev/null || true)
  [ "$current" != "$CANDIDATE" ] || PROMOTED=true
fi

if [ "$PROMOTED" = true ]; then
  close_issue "$nopub" "edge was promoted by $RUN_URL"
  if [ "$FALLBACK" = true ]; then
    # A promotion on the fallback pin must not hide that new quattro is red.
    report_held
    echo "promoted on the fallback pin; held issue reported"
  else
    if [ "$NEWEST" = true ]; then close_issue "$held" "quattro is adopted as of $RUN_URL"; fi
    echo "promoted; issues ${nopub:-none open} / ${held:-none open}"
  fi
  exit 0
fi
if [ "$PREPARE" = success ] && [ "$SKIP" = true ]; then
  close_issue "$nopub" "edge is current as of $RUN_URL"
  close_issue "$held" "quattro is adopted as of $RUN_URL"
  echo "edge is current; nothing to report"
  exit 0
fi

# A cancelled job result here is a timeout, not a person: a cancelled
# workflow does not reach this job.
digest=""
if [ "$PREPARE" != success ]; then
  x=$(tail_of "$PREPARE_FAILED" "$PREPARE")
  if [ "$BUILD2" = failure ]; then
    sig="prepare: fallback also red: $x"
    [ -z "$HELD_BY" ] || sig="$sig; quattro red: $HELD_BY"
  elif [ -n "$HELD_BY" ] && [ "$HELD_BY" != "$PREPARE_FAILED" ]; then
    sig="prepare: $x; quattro red: $HELD_BY"
  else
    sig="prepare: $x"
  fi
  digest=$PREPARE_DIGEST
elif [ "$WAIT" != success ]; then
  sig="wait-idle: $(tail_of "" "$WAIT")"
elif [ "$VERIFY" != success ]; then
  sig="verify: $(tail_of "$VERIFY_FAILED" "$VERIFY")"
  digest=$VERIFY_DIGEST
else
  sig="promote: not promoted"
fi
post omarchy-edge d93f0b "The nightly edge publish is failing" \
  "$NOT_PUB" edge-sig "$sig" "" "$digest"
