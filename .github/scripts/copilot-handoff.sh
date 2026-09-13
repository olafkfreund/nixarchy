#!/usr/bin/env bash
# Hands a bump PR whose build went red to Copilot, on that PR's own branch.
# Why: .github/workflows/copilot-handoff.yml
set -euo pipefail
: "${RUN_ID:?}" "${REPO:?}" "${BRANCH:?}"
max=2 # ponytail: a fixed cap; if Copilot's second fix is still red, a human reads it

# failure, never cancelled. An evicted job reports cancelled, and so does one
# that hit its timeout (AGENTS.md §6). Neither is Copilot's to fix: an
# eviction needs nothing, and a timeout is a CI gate change for a human.
failed=$(gh run view "$RUN_ID" --repo "$REPO" --json jobs \
  -q '[.jobs[]|select(.conclusion=="failure")|.name]|join(", ")')
if [ -z "$failed" ]; then
  echo "run $RUN_ID has no failed job -- cancelled only (an eviction or a timeout); not handed off"
  exit 0
fi

pr=$(gh pr list --repo "$REPO" --head "$BRANCH" --state open --json number -q '.[0].number // empty')
[ -n "$pr" ] || { echo "no open pull request for $BRANCH"; exit 0; }

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

# The error lines themselves, not a tail. Each job's post-job cleanup is cut
# first (the cachix push would fill any tail), and nix's `… while calling`
# frames are dropped: the line that names the cause is the `error:` at the
# bottom of a trace two hundred lines deep, and a tail lands past it.
# Colour is stripped in both spellings: GitHub's log API returns the literal
# text ^[[31m rather than ESC, and filtering \x1b alone lets every trace
# frame through the filter below.
log=$(gh run view "$RUN_ID" --repo "$REPO" --log-failed 2>/dev/null \
  | awk -F'\t' '$1 != job { job = $1; skip = 0 } /Post job cleanup/ { skip = 1 } !skip { print $1 ": " $3 }' \
  | sed 's/\x1b\[[0-9;]*m//g; s/\^\[\[[0-9;]*m//g; s/: \xEF\xBB\xBF\?[0-9T:.-]*Z /: /' \
  | grep -vE '^[^:]*: +(… |[0-9]+ *\||\|)' \
  | grep -E -A6 'error|Error|does not evaluate|unexpected changes|Failed to|FAIL' | head -100)

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
