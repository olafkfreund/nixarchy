---
status: draft
issue: 1426
intent: intent/2026-10-22-1426-edge-wait-vm-host.md
---

# Spec: edge waits only for what collides with its VMs

Both open questions in the intent were approved as recommended:
edge's VMs may run alongside package builds, and the `wait-idle` job stays,
changing only what it waits for.

## Design

One job changes: `wait-idle` in `.github/workflows/omarchy-edge.yml`
(about lines 393–426). It stays on the hosted `ubuntu-26.04` runner.

- **Add a checkout.** The job has none today, and it now needs
  `.github/scripts/vm-host-free.sh`. Use `actions/checkout` (`@v5`, as the
  file's other two checkouts), sparse to `.github/scripts`.
- **Replace the run count with the existing script.** The loop runs
  `.github/scripts/vm-host-free.sh edge` directly. The hosted image ships
  `gh` and `jq`, so `verify`'s `nix shell` wrapper is not needed. The script
  reads `GITHUB_REPOSITORY` and `GITHUB_RUN_ID`, which Actions sets, and
  `GH_TOKEN`, which the step already passes.
  - Exit 0 (`free`): print it and leave the loop.
  - Exit 1 (busy) or exit 2 (API unreadable): wait. Exit 2 counts as busy,
    as in `verify` and `install`.
- **Poll every 60 s instead of 300 s**, matching `verify` and `install`.
  The question is now cheap and narrow, so a shorter poll costs nothing and
  starts edge sooner.
- **Keep the 3-hour bound**, the job's 200-minute timeout and the error on
  giving up, with the message naming what it waited on.
- **Rewrite the comment above the step.** It cites §6's "nothing in flight"
  rule, which this deliberately no longer applies. The new comment points at
  #1365/#1426: what edge must not share p620 with is an install's VMs.

Nothing else changes. `verify`'s per-check `host_free` stays, because an
install can start between `wait-idle` ending and each VM check starting.
`install-check.yml` and `vm-host-free.sh` are untouched.

## Alternatives rejected

- **Delete `wait-idle`, and rely on `verify`'s per-check gate.** That moves
  the wait onto a VM runner, which it holds for up to 2 hours per check.
  Rejected in the intent.
- **Count only runs on self-hosted runners.** A run's runner labels are
  per job and not in the run list, so this needs a job query per run: the
  same cost as the script, with a weaker answer. A package build is also
  not the collision #1365 measured.
- **Narrow the existing count with a workflow-name list.** It is a second
  hand-kept list beside the one in `vm-host-free.sh`, which §4 says fails
  open.

## Risks

- **Edge VMs now run beside `system-build` or `omarchy` on p620.** These are
  package builds, not VMs; #1365's stall was VMs on VMs. If an edge check
  ever times out next to a package build, the digest names it, and the rule
  can be widened then.
- **A hosted runner without `gh` or `jq`.** The script would fail and exit
  non-zero, which reads as busy until the 3-hour bound, so this fails
  closed, not open. The Ubuntu image ships both, and the first edge run
  shows it.
- **The `wait-idle` → `verify` race.** An install that starts after
  `wait-idle` passes is caught by `verify`'s per-check gate, as today.

## Verification

- **`actionlint`** on the workflow (build.yml's lint job runs the same).
- **The script is already covered** by `checks.vm-host-free`, including its
  fail-open break. This change adds a call site, not logic.
- **§1, red then green, for the step itself:** extract the new `run:` block
  as written into a scratch script, and run it under bash with `GH` stubbed
  by a `gh` stub on `PATH` that serves `tests/vm-host-free.nix`'s fixtures
  for both `gh api` and the old block's `gh run list`:
  - an install `install` job in progress → it waits (`busy: …`);
  - only a `build` run in progress → it exits at once with `free`.
  The red is the old block run against the same "only `build`" fixture: it
  waits, which is the bug.
- **After merge:** the next edge run that starts while only `build` or
  `pages` is in flight goes from `prepare` to `verify` within a minute.
  Reported on #1426.
