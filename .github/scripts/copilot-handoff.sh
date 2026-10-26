#!/usr/bin/env bash
# Hands a bump PR whose build went red to Copilot, on that PR's own branch.
# Why: .github/workflows/copilot-handoff.yml
set -euo pipefail
: "${RUN_ID:?}" "${REPO:?}" "${BRANCH:?}"
max=2 # ponytail: a fixed cap; if Copilot's second fix is still red, a human reads it

# failure, never cancelled. An evicted job reports cancelled, and so does one
# that hit its timeout (AGENTS.md §6). Neither is Copilot's to fix: an
# eviction needs nothing, and a timeout is a CI gate change for a human.
# The aggregator `system` fails whenever a half does, a half that timed out
# included, so it is not evidence of a failure (#1341).
failed=$(gh run view "$RUN_ID" --repo "$REPO" --json jobs \
  -q '[.jobs[]|select(.conclusion=="failure" and .name!="system")|.name]|join(", ")')
if [ -z "$failed" ]; then
  echo "run $RUN_ID has no failed job -- cancelled only (an eviction or a timeout); not handed off"
  exit 0
fi

pr=$(gh pr list --repo "$REPO" --head "$BRANCH" --state open --json number -q '.[0].number // empty')
[ -n "$pr" ] || { echo "no open pull request for $BRANCH"; exit 0; }

# A draft is held by pin-fix (flake-update.yml); Copilot's commit would take it
# over. Fail safe: if the state cannot be read, do not hand off.
if ! draft=$(gh pr view "$pr" --repo "$REPO" --json isDraft -q .isDraft); then
  msg="#$pr: cannot read whether it is a draft -- not handed off"
  echo "$msg"; echo "$msg" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 0
fi
if [ "$draft" = true ]; then
  msg="#$pr is a draft -- pin-fix owns it; not handed off"
  echo "$msg"; echo "$msg" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 0
fi

# A nixpkgs bump merges itself only while it moves nixpkgs alone, and
# flake-update.yml judged one sha. Copilot's fix is a head nobody judged, so
# auto-merge comes off first and a person merges it (#1459). Fail safe again.
case "$BRANCH" in
  update/nixpkgs-*)
    if ! armed=$(gh pr view "$pr" --repo "$REPO" --json autoMergeRequest -q '.autoMergeRequest != null'); then
      msg="#$pr: cannot read its auto-merge state -- not handed off"
      echo "$msg"; echo "$msg" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
      exit 0
    fi
    if [ "$armed" = true ]; then
      if [ "${DRY_RUN:-}" = 1 ]; then
        echo "would disable auto-merge on #$pr"
      elif ! gh pr merge "$pr" --repo "$REPO" --disable-auto; then
        msg="#$pr: could not disable auto-merge -- not handed off"
        echo "$msg"; echo "$msg" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
        exit 0
      fi
    fi
    ;;
esac

sha=$(gh run view "$RUN_ID" --repo "$REPO" --json headSha -q .headSha)
comments=$(gh pr view "$pr" --repo "$REPO" --json comments -q '[.comments[].body]')
if jq -e --arg s "sha=$sha" 'any(.[]; contains($s))' <<<"$comments" >/dev/null; then
  echo "#$pr: already handed off for $sha -- a re-run of the same commit"
  exit 0
fi
count=$(jq '[.[]|select(contains("<!-- copilot-handoff"))]|length' <<<"$comments")
if [ "$count" -ge "$max" ]; then
  msg="#$pr: $count handoffs already and still red -- left for a human"
  echo "$msg"; echo "$msg" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 0
fi

# The error lines themselves, not a tail (filter: failure-excerpt.sh). Each
# job's post-job cleanup is cut first: the cachix push would fill any tail.
log=$(gh run view "$RUN_ID" --repo "$REPO" --log-failed 2>/dev/null \
  | awk -F'\t' '$1 != job { job = $1; skip = 0 } /Post job cleanup/ { skip = 1 } !skip { print $1 ": " $3 }' \
  | sed 's/: \xEF\xBB\xBF\?[0-9T:.-]*Z /: /' \
  | MAX=100 "$(dirname "$0")/failure-excerpt.sh")

body=$(cat <<EOF
@copilot The dependency bump on this branch broke the build. Fix it here, on this branch.

**Failed:** ${failed}
**Run:** https://github.com/${REPO}/actions/runs/${RUN_ID}

<details><summary>The errors from the failing log</summary>

~~~~
${log}
~~~~

</details>

Constraints, from AGENTS.md:
- Fix the cause in this repository. Do not revert the bump or pin the dependency back -- the bump is the point of the pull request.
- Reproduce first with the command the failing job runs, then show it failing before your change and passing after (§1).
- If the failing job needs KVM or a self-hosted runner, you cannot verify a fix. Say so and stop rather than push an unverified one.

<!-- copilot-handoff sha=${sha} -->
EOF
)

if [ "${DRY_RUN:-}" = 1 ]; then
  echo "would comment on #$pr:"; echo "$body"
else
  gh pr comment "$pr" --repo "$REPO" --body "$body"
fi
