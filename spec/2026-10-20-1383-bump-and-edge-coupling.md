---
status: approved
issue: 1383
intent: intent/2026-10-20-1383-bump-and-edge-coupling.md
---

# Spec: a failed Omarchy bump is visible, and edge carries main without waiting on quattro

Four changes, all workflow edits (§11: you merge the PR). Line numbers are
from `main` at b16561ff.

## 1. `omarchy.yml`: a failed bump opens a draft PR

**Why it is silent today.** Every step after the build (:113) has a plain
`if:`, which means `success()`. So once the build fails, everything up to
"Report what needs a human" (:571) is skipped, and the bump branch is never
pushed. "Open a pull request" (:441, `peter-evans/create-pull-request@v8`,
`branch: update/omarchy-<version>`) is the only push.

**Design:**
- **Ids on the three gates.** The bump step (:70) becomes `id: bump`, the
  build (:113) `id: build`, the session (:386) `id: session`, and counts
  (:410) is already `id: counts`.
- **Capture the gate output.** The build and session gates write their
  output to `$RUNNER_TEMP/gate.log` with `set -o pipefail; … 2>&1 | tee -a
  "$RUNNER_TEMP/gate.log"`. That is pipefail in the step itself, because
  the default `bash -e` has none. It goes to `$RUNNER_TEMP`, never the
  checkout, because create-pull-request commits the whole tree.
- **A new step before :441, "Open a draft pull request for a failed
  bump":**
  - `if: failure() && steps.bump.outcome == 'success'`, so there is a bump
    to show;
  - the same action, token and `branch:` as :441, with `draft: true`;
  - the title is `Omarchy <version>: needs manual work (<failed gate>)`;
  - the body names the failed gate (`steps.build.outcome` / `steps.session.outcome`
    / `steps.counts.outcome`), then `sed -n '1,40p'` of the first `error`
    lines from `gate.log` (no `head`, #1157), then the existing "Most likely
    one of:" checklist from :571;
  - it does not claim, as :472-478 does, that the job proved anything.
- **Updated in place.** The branch is per version, so each night on the
  same release force-pushes the branch and rewrites the draft's body. A
  newer release opens its own draft. The older draft stays open and you
  close it; that matches the per-version branches :459-464 chose on
  purpose.
- **A later green night un-drafts it.** create-pull-request v8's
  `draft: true` applies "only on create" (its README), and auto-merge
  cannot be armed on a draft. So "Arm auto-merge" (:518) runs
  `gh pr ready "$pr" || true` before `gh pr merge --auto`.
- **Tokens.** With `BUMP_TOKEN`, the draft's push runs `build.yml` too,
  so the failure shows in its checks. Without it, the draft still
  appears, just without checks. Nothing new is needed: permissions
  already include `pull-requests: write` (:10-12).

## 2. `omarchy-edge.yml`: `from_candidate` keeps its quattro pin

The `start` step already reads `HAVE`, the start ref's pin, before the
merge (:111). With `from_candidate`, that is the candidate's pin. In the
`pin` step (:165), add `FROM_CANDIDATE: ${{ inputs.from_candidate }}` to
`env`, then:

```bash
if [ "$FROM_CANDIDATE" = true ] && [[ $HAVE =~ ^[0-9a-f]{40}$ ]]; then
  sha=$HAVE   # carry main to the candidate's quattro; a scheduled run moves quattro
else
  <the existing API call>
fi
```

The first publish (`expected=none`) is unchanged.

## 3. `omarchy-edge.yml`: same-run fallback to the last good quattro

- **The last good pin** is the one on `origin/edge`:
  `git show origin/edge:flake.nix`, the same 40-hex grep as :111.
- **`build` (:219) gets `continue-on-error: true`.** Without it the job
  fails, and `wait-idle`/`verify` never see the fallback.
- **New `pin2` + `build2`,** with
  `if: steps.build.outcome == 'failure' && <last good> != steps.pin.outputs.sha`.
  - They repeat the pin script with the fixed SHA, and the same check
    loop.
  - No reset is needed: `pin` only edits `flake.nix`/`flake.lock`, and the
    seds and `nix flake update` overwrite both.
- **`candidate` (:336)'s `if:` becomes**
  `skip != 'true' && (steps.build.outcome == 'success' || steps.build2.outcome == 'success')`.
  - Its commit message names the SHA that passed.
  - A final step fails the job when neither build passed, so nothing
    unverified is ever pushed.
- **A new job output, `fallback`,** set when build2 is what passed.
  `report` then files "new quattro is red" even though edge was promoted,
  so the quattro failure is never hidden by a successful promotion.
- **`timeout-minutes` goes from 45 to 90.** Both passes are cold builds
  of `.#omarchy`, since edge closures are not cached, and with §4's list
  45 minutes cannot hold two passes. Measured in the plan before choosing
  the number.

`verify` and `edge-promote.sh` are unchanged: `verify` still boots the
VM checks on whichever candidate was pushed, and promotion still only
fast-forwards a verified candidate.

## 4. `omarchy-edge.yml`: check list from `generated-checks.sh`

Replace the literal list at :239:

```bash
out=$(.github/scripts/generated-checks.sh) || { echo "::error::generated-checks.sh failed"; exit 1; }
mapfile -t targets <<<"$out"
[ "${#targets[@]}" -ge 5 ] || { echo "::error::only ${#targets[@]} generated checks"; exit 1; }
for c in "${targets[@]}"; do try "${c##*.}" nix build "$c" --print-build-logs; done
```

- **Capture first, then split** (§4: `mapfile < <(cmd)` cannot see `cmd`
  fail), and refuse an empty list.
- **Keep the per-check `try`,** so one evaluation error does not hide its
  siblings (§13).
- The script excludes every claimed (VM/KVM/install) check, so prepare
  stays KVM-less. It includes `etc-overlay` (#1377's workflow half),
  `stable-eval` and the current seven. That is about 26 checks instead of
  7, measured in the plan.

## 5. `report`: the rolling issue closes only itself

:462 picks *any* open `omarchy-edge` issue, which is how promotion closed
#1377. Select it by its own title:

```bash
num=$(gh issue list --label omarchy-edge --state open --json number,title \
  --jq '[.[] | select(.title == "The Omarchy edge channel is not publishing")][0].number // empty')
```

That one line fixes both the close at :471-474 and the failure comment at
:506-511.

## Alternatives rejected

- **An issue instead of a draft PR for a failed bump:** you chose the
  draft PR.
- **Running the fallback as a second run:** you chose the same run.
- **A separate label for the rolling issue:** more change than the
  one-line title match.

## Risks

- **Getting §3 wrong** either promotes nothing, or pushes a candidate
  whose checks failed. The proof below covers both.
- **Runtime:** §3 and §4 together may need the 90-minute limit. If the
  measurement says more, the plan comes back before raising it further.

## Verification (§1)

A throwaway branch with `workflow_dispatch` runs, dropped afterwards:

1. **Draft PR:** a bump that cannot build, made by pinning the Omarchy
   input to a deliberately broken commit on a scratch branch, opens a
   draft PR naming `build`. Without §1 there is no PR, which is today's
   behaviour, recorded from #1374.
2. **`from_candidate`:** a candidate pinned to an older quattro keeps that
   pin. The step summary's `omarchy quattro <sha>` line equals `HAVE`.
   Without §2 it moves.
3. **Fallback:** with a new quattro forced red (via a broken carry patch
   on the scratch candidate), the run promotes `main` on the last good
   quattro and `report` files "new quattro is red". With no good pin, it
   pushes nothing.
4. **Generated list:** the step builds `etc-overlay` and the rest. A
   candidate missing an overlay row fails at `etc-overlay`.
5. **Report:** an unrelated open issue labelled `omarchy-edge` survives a
   promotion.

`actionlint` runs on both workflows.
