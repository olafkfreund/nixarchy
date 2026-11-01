---
status: approved
issue: 1524
author: x
---

# Intent: an install and edge's verify stop waiting on each other

## Problem

An install job and edge's `verify` job must not boot VMs on p620 at the same time (#1365). Each asks `.github/scripts/vm-host-free.sh` whether the other is running, and waits while it is.

That script counts a **job** as busy for as long as it is `in_progress`, and both waits happen inside their own jobs:

- the install waits in a step of its `install` job;
- edge waits between checks inside its `verify` job.

So when both start waiting together, each sees the other as busy, and neither boots anything. The install gives up after 30 minutes and reports **failure** with no code under test.

On 2026-10-30, from 10:38 to 11:08, `main`'s install for #1522 (run 41041818120) and edge `verify` (run 41037548734) each logged `waiting … busy: … job <the other>`. The install then failed, and only then did `verify` go on.

What this costs:

- false reds on `main` and on pull requests;
- the nightly review (#1519) reporting failing installs;
- about 30 minutes of idle CI each time;
- people and agents chasing a bug that does not exist.

The comment beside the install's wait assumes "an install only waits out the one already running (~15-20 min)". That is not true while the two can block each other.

## Proposed outcome

- At any moment, at most one of {an install's VM build, one edge VM check} runs on a host. This is #1365's guarantee, unchanged.
- A job that is only **waiting** never blocks the other, so the two cannot both wait at once. One proceeds at once, and the other waits only as long as the first's VM work lasts.
- An install fails at its wait only when the host really is occupied beyond its bound, not because of this cycle.
- A break proof (§1) shows the current code deadlocking two stand-in jobs, and the fix letting one proceed straight away.

## Affected users and systems

- `.github/scripts/vm-host-free.sh`, and its check (`checks.vm-host-free`).
- `install-check.yml`: the "Wait for edge's VM checks to leave this host" step.
- `omarchy-edge.yml`: `wait-idle` and `verify`'s `host_free`.
- The four self-hosted runners on p620.
- Anyone merging to `main`, and the nightly review.

## Constraints

- **CI-gate change (§11):** a human approves it and merges it.
- #1365's guarantee must hold: never an install VM and an edge VM together on one host.
- **A shared lock file is not possible without a host change.** The runners run as separate `DynamicUser`s with `ProtectSystem=strict` and `PrivateTmp=yes`, and no `ReadWritePaths`. No path is writable by all four today. A lock needs a change in nixos_config, and a p620 switch, which kills every install in flight (§6).
- Nothing may treat an unknown API answer as free. Exit 2 stays busy.
- Proving the fix must not use the VM tier locally: stubbed `$GH` and stand-in scripts only.

## Open questions

1. **Which mechanism?**
   - (a) **A host lock**: per host and per check, no API calls. It needs a shared writable directory on p620, set up in nixos_config, and a deploy.
   - (b) **Step-aware check**, all in this repo. A job counts as busy only once it is past its wait. Edge's per-check wait sits inside its VM step, so edge needs a marker the API can see: for example, its wait moves into a step of its own per check, or the check reads the step's name or log.

   I lean to **(b)** for this issue, because it needs no host change and no deploy. (a) can follow if a second runner host is added.
2. With (b), an install still waits out a whole `verify` run (20–51 min) when `verify` really is booting, which is longer than the 30-minute bound. Should the bound rise to about 60 minutes as part of this change?
