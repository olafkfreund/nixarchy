---
status: draft
issue: 1524
intent: intent/2026-10-30-1524-vm-host-mutual-wait.md
---

# Spec: an install and edge's verify stop waiting on each other

## Evidence the design rests on

- **Both long `verify` runs were the standoff, not slow work.**

  | Run | Total | Waiting on an install | Real work |
  |---|---|---|---|
  | 41037548734 (10-30) | 84 min | 30 min | — |
  | 40905691663 (10-29) | 51 min | 31 min | ≈20 min |

  The other eight `verify` runs since 10-28 took 19–21 min each. In both cases, the install `verify` was waiting on later disappeared from the API (404).
- **The jobs API reports each step's name and status** (`.jobs[].steps[] | {number, name, status}`), and the install's wait is a step of its own: step 7, "Wait for edge's VM checks to leave this host". The status values are `queued`, `in_progress` and `completed`. I read a completed job, run 41054785082; a live `in_progress` step is verified in plan step 4.

## Design

Break the cycle on one side only: **edge does not count an install that is still in its wait step.** The install keeps yielding to the whole `verify` job, as today.

`.github/scripts/vm-host-free.sh`:

- The `case` gains a third variable, `wait`.
  - `edge` sets `wait="Wait for edge's VM checks to leave this host"`.
  - `install` sets `wait=""`, so nothing is exempt and the install's view is unchanged.
- The job filter becomes:

  ```jq
  .jobs[] | select(.name == $j and .status == "in_progress"
    and ([.steps[]? | select(.name == $w and .status == "in_progress")] | length) == 0) | .name
  ```

  So an install job is busy **unless** its wait step is the one running. The job is still busy:
  - before the wait (gate, checkout);
  - after the wait (booting);
  - in the moment between, when the wait step is `completed` and the next step is not yet `in_progress`;
  - and with no `steps` at all.

  Every unknown state stays busy, which is #1365's safe direction.
- The comment above the install's wait in `install-check.yml` currently says the install only waits out the check already running. It is corrected to say the install waits out the whole `verify` (≈20 min), and that edge does not wait for a waiting install (#1524). The 30-minute bound and the job's 90-minute timeout are **not** changed: 20 min of real `verify` fits 30 with ten minutes to spare.

`omarchy-edge.yml` is not changed.

### Why one side and not both

If both sides ignored a waiting peer, two jobs could each see the other "waiting" in the same minute and both boot. That is exactly #1365's collision. One side has to yield even while its peer only waits.

The install side is chosen to yield (unchanged), because:

- its wait is already a separate step, so the exemption is a filter change and no edit to edge's workflow;
- edge's waits sit inside its single VM step. Making them visible would mean unrolling `verify`'s loop into per-check steps, with its failure accounting.

### The remaining race, and why it is closed

The install proceeds only when no `verify` job is `in_progress`. A `verify` that starts after that moment first checks out the tree and evaluates the `options-*` shards. That takes minutes, and only then does it call `host_free` before `session`. By then the install's wait step has long been `completed`, so edge sees the install as busy and waits.

The only gap is between the install's last check and its wait step being reported `completed`. That is seconds, against minutes of `verify` start-up.

### Coupling to a step name

If the step is renamed, the exemption never matches. Every install is then busy to edge again, so the standoff returns, but #1365 is not broken. `checks.vm-host-free` asserts that the `wait` string appears as a `- name:` in `install-check.yml`, so a rename turns the check red and does not quietly bring the standoff back.

## Alternatives rejected

- **A host lock (`flock`).** The runners are separate `DynamicUser`s with `ProtectSystem=strict` and `PrivateTmp`, and no path is shared. It needs a nixos_config change and a p620 switch, which kills installs in flight (§6). Revisit if a second runner host is added.
- **Raising the install's bound to 60 min.** It lengthens the standoff and does not end it. Together with about 25 min of install, it would also crowd the 90-minute job timeout.
- **Making both sides step-aware.** This is the both-boot race above.
- **Moving the install's wait into its own job.** The gap between that job ending and `install` being picked up by a runner can be long when all four runners are busy, and edge would see no install during it.
- **Making edge's side step-aware instead.** This needs `verify`'s loop unrolled into per-check steps, so it is a bigger change for the same effect.

## Risks

- **GitHub reports a step's status late.** That would widen the seconds-long gap above. The minutes of `verify` start-up still cover it. If a live run ever shows overlap, the fix is a 60 s delay before the install's wait step exits, plus a re-check.
- **Installs queue on a long `verify`.** An install can still wait longer than 30 min when `verify` itself waits for an install from the other slot that really is booting. Edge runs about 3–4 times a day, so that is rare. If it shows up, it is a separate issue with its own numbers.
- **No host is touched and nothing is deployed.** The change takes effect when edge's next run reads `main` (`edge-candidate` merges `main`). The install side is unchanged.

## Verification

- **`checks.vm-host-free`** keeps its six cases and its two break proofs, and adds:

  | Case | Fixture | Expect |
  |---|---|---|
  | edge-vs-waiting-install | install job, wait step `in_progress` | `free`, exit 0 |
  | edge-vs-booting-install | wait `completed`, the next step `in_progress` | busy, exit 1 |
  | edge-vs-install-before-wait | wait `queued` | busy |
  | edge-vs-install-between-steps | wait `completed`, the next step `queued` | busy |
  | install-vs-waiting-verify | verify `in_progress` | busy (the install side is unchanged) |
  | standoff | both waiting | the install side is busy and the edge side is `free`; the old script says busy for both, which shows the standoff and its fix in one fixture pair |
  | step-name guard | — | the `wait` string is a `- name:` in `install-check.yml` |

- **Break proofs (§1):**
  - Remove the exemption: edge-vs-waiting-install must go red.
  - Exempt any step that is not booting (`.status != "completed"`): edge-vs-install-before-wait must go red.
  - Rename the step in a copy of the workflow: the step-name guard must go red.
- **Cheap tier only:** `nix fmt -- --ci`, shellcheck on the script, actionlint, `checks.grep-q-pipefail` and `checks.vm-host-free`, under `flock` (§6).
- **Live:** the next time an install and an edge `verify` overlap, edge's log shows no `waiting … job install` while that install is in its wait step, and the install does not give up. The jobs API's step status is read once from a running install while it waits.
