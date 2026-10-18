---
status: approved
issue: 1341
intent: intent/2026-10-18-1341-system-bump-timeout.md
---

# Spec: a nixpkgs bump finishes inside the system job's limit

## Design

**Split `system` into two parallel jobs, divided by what needs `hypr-rdp`
built, and keep a job named `system` that passes only when both did.** The answer to the intent's first question is "split", and to
the second "PRs still build `hypr-rdp`": see the alternatives.

### Revision (2026-10-18), after the plan review

The first version split "builds" from "VM boots". The plan review found that
`session` enables `services.hypr-rdp` (`tests/session.nix:171`), so a
`session` away from the tools step would compile `hypr-rdp`'s 447 crates a
second time on a bump. Pull requests push no closures, so nothing shares it,
and that half came to ~39 of 45, not ~29. Of `system`'s checks, only
`session` and `options` pull in `hypr-rdp` (grep of `tests/*.nix`), so the
split now follows that dependency.

It also claimed, wrongly (see revision 2), that **`system`'s VM checks run without KVM.** No step in it
grants `/dev/kvm`, and `box`'s own comment (`build.yml:1738-1742`) says that
without the udev rule the test driver falls back to TCG and the job "would
quietly get slower until it started flapping against its timeout". That is
`system`'s history. Both halves gain `box`'s udev step.

### Revision 2 (2026-10-18), after the second plan review

**`system` already has KVM.** `setup-nix` uses `nix-installer-action`, which
enables it: main's job 117701579179 logs `kvm: true` and "Accelerated KVM is
enabled", and so do both #1332 timeouts. Revision 1's "the lever is KVM" was
wrong, and its KVM step is dropped: it would be a no-op.

**`options` does not build `hypr-rdp`.** It evaluates whether the unit exists
(`tests/options.nix:1945-1953`, `? hypr-rdp`), so it moves to
`system-checks`. That is the lever that replaces KVM.

The verification's merge-state test could not fail: a draft PR reads `DRAFT`,
and a cancelled `install`, a required check, blocks on its own. It now uses a
ready PR whose other required checks are green.

### Jobs

`.github/workflows/build.yml`:

- **`system-build`**: today's `system` job (`:1306`) minus the checks that do
  not need `hypr-rdp` or publish. It keeps the toplevels, `coexistence`, the
  allowlisted tools and box image, the system-closure push, **`session`**
  and the cache budget. Everything that builds `hypr-rdp` is here, once.
- **`system-checks`**: the MicroVM template and its push, the box template,
  `integration`, `coexist`, `install-teardown`, `installer-ui`,
  `try-nixarchy`, `dashboard-clock`, `installer-wizard` and `plugin`. Several
  of these are `runCommand`s, not VMs; what they share is that none needs
  `hypr-rdp`. It has the same setup steps, `Free disk space`, and its own copy
  of the gate's "cannot pass" first step.
- **`system`** (the required context, unchanged in branch protection:
  `["lint","omarchy","system","devenv-presets","box","install"]`):
  `needs: [gate, system-build, system-checks]`, `if: ${{ !cancelled() }}`,
  one step that fails unless all three concluded `success`. This is the shape
  #1134 gave the gate, for the reason #1144 measured: a `skipped` required
  check passes the merge gate, so the aggregator must run and fail, never
  skip.
- **`copilot-handoff.sh:11-12`** excludes the aggregator `system` from its
  `failure` filter. It hands off only `failure`, so that a timeout (reported as
  `cancelled`) reaches a human (`:8-10`). The aggregator would turn a
  timed-out half into `failure` and summon Copilot onto exactly the bump PRs
  this issue is about. The halves carry the real verdict.

Each half keeps `timeout-minutes: 45` and the per-commit concurrency group
`system` has today (`:1347-1350`), named by job.

### Time

Measured on the two #1332 timeouts (jobs 117666616240 and 117687897155), both
already under KVM, worst of two:

| job | steps (minutes) | total incl. setup |
|---|---|---|
| `system-build` | disk 2.0, VM closure 3.3, installed 0.9, coexistence 0.7, tools 10.3, push 1.7, session 9.8, budget 2.3 + 2 | ~36 |
| `system-checks` | disk 2.0, MicroVM 2.0 + push 2.2, options 4.5, plugin 5.5, coexist 2.5, wizard 1.4, integration 1.1, the four small ones ~2, nixarchy's own packages again ~2 | ~28 |

The budget's "+ 2" is the MicroVM runners: `cache-budget.sh` realises every
allowlist entry (`:34-40`), and after the split they are built in the other
job. "Nixarchy's own packages again" is because pull requests push no
closures, so both halves build them.

~36 of 45 leaves ~9 minutes, against ~50 in one job today. It is an estimate
from step times: only a real nixpkgs bump measures it, because a normal PR
substitutes `hypr-rdp` from the cache. A normal PR (proofs present) stays at
today's ~20 minutes or less, and a timeout now names the half that ran out.

### Coverage guard

`generated-checks.sh claimed` matches a check's name anywhere in `build.yml`
(`:27-40`), not per job, so moving a step between jobs changes nothing there.

## Alternatives rejected

- **Raise `timeout-minutes`** (to 60 or 90). The cap exists to fail a hung job
  in under an hour while surviving a 20-minute substituter stall (`:1310-1317`,
  411c6a4). A bump is when the most changes, so it is the worst time to
  weaken the hang guard. It also leaves one job that names nothing when it
  stops.
- **Raise it only for bump PRs** (an expression on `timeout-minutes`). Same
  objection, and a second behaviour to remember.
- **Split "builds" from "VM boots"** (this spec's first version). `session`
  needs `hypr-rdp`, so the VM half would compile it again: ~39 of 45.
- **Move only "Build the allowlisted tools" (10 min) out.** It is the
  `hypr-rdp` compile, 447 crates (`:1414-1421`), and `options` and `session`
  need `hypr-rdp` too. Pull requests never push closures, so it would be
  compiled again. That would save nothing on a PR.
- **KVM** (revision 1's lever). `system` already has it.
- **A third job for `session`.** It needs `hypr-rdp` built, so it would
  compile the 447 crates a second time: no saving.
- **Skip `hypr-rdp`/box image on PRs.** `options` still builds `hypr-rdp`, and
  the box image is what the box checks test. No saving, and less coverage.
- **Self-hosted runners.** All four are on p620 and share the two install
  slots with a desktop (§6); a bump's whole suite is exactly the load §6 keeps
  off them.

## Risks

- **Branch protection.** Unchanged: the aggregator keeps the name `system`.
  If the aggregator could be skipped, a red half would merge; `!cancelled()`
  plus the explicit check closes that, and verification measures it (below).
- **Cancelled half.** A half cancelled by concurrency makes the aggregator
  fail with that half named, which disables auto-merge as today (§6). No new
  failure mode.
- **Runner minutes.** Two setups instead of one, about 5 more hosted minutes
  per run. Public repository, so free.
- **~9 minutes of headroom on a bump** is less than the 25 a normal run
  has. A substituter stall on a bump day would still time `system-build` out;
  it would then name `system-build` rather than everything.
- **Disk.** Each half frees disk and downloads its own closures. The VM half
  substitutes the test VMs' closures from cache.nixos.org, about 3 minutes, as
  `system` does today.
- **Docs and references.** `docs/internals/workflows.md:103-107` and
  `AGENTS.md:583` (CLAUDE.md is a symlink to it) name the job; the stale
  comment at `build.yml:1695-1697` is corrected in passing, and so are the
  pointers to "`system`'s timeout comment" in `already-proven.sh:20` and
  `build-unless-proven.sh:11`, which name `system-build`.

## Verification

- `actionlint` on `build.yml`; the workflow guards in `build.yml` itself
  (skipPush, coverage) green on the PR.
- **The aggregator blocks on a red half**, measured, not inferred (§4), on a
  throwaway PR from a `test/` branch (outside Copilot's `update/` filter),
  **marked ready for review, with `install` left to finish**, so that every
  required check but `system` is green when the merge state is read
  (`gh pr checks --required`). Two runs:
  - `system-checks` times out (a `sleep` past a 1-minute `timeout-minutes`),
    `system-build` green: `mergeStateStatus` reads `BLOCKED`, the half is
    `cancelled` with the timeout annotation, and `copilot-handoff.sh` run
    against that run hands off nothing.
  - `system-build` fails (an `exit 1`), `system-checks` green: `BLOCKED`.
  The green control is the real PR's own run, which must read `CLEAN` or
  `UNSTABLE` with `system` green.
- `checks.copilot-handoff` gains a case for the aggregator's exclusion, with a
  control that fails when the exclusion is removed.
- **Timing:** the PR's own run shows both halves' durations. The next nightly
  nixpkgs bump finishes both halves without a re-run; the PR records it, and
  #1341 closes on that evidence rather than on merge.
- A maintainer merges (§11).
