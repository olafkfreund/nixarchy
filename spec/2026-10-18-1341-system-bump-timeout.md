---
status: draft
issue: 1341
intent: intent/2026-10-18-1341-system-bump-timeout.md
---

# Spec: a nixpkgs bump finishes inside the system job's limit

## Design

**Split `system` in two parallel jobs, and keep a job named `system` that
passes only when both did.** The answer to the intent's first question is
"split", and to the second "PRs still build `hypr-rdp`": see the
alternatives.

`.github/workflows/build.yml`:

- **`system-build`**: today's `system` job (`:1306`) with the VM boots taken
  out. It keeps the toplevels, `coexistence`, the allowlisted tools and box
  image, the cachix pushes, the MicroVM and box templates, `options`, and the
  cache budget. Everything that publishes stays here, so the cache rules (§6)
  are untouched.
- **`system-vm`**: the steps that boot a VM. That covers `session`,
  `integration`, `coexist`, `install-teardown`, `installer-ui`,
  `try-nixarchy`, `dashboard-clock`, `installer-wizard` and `plugin`. It has
  the same setup steps, `Free disk space`, and its own copy of the gate's
  "cannot pass" first step. It pushes nothing but proofs, which
  `build-unless-proven.sh` already does per step.
- **`system`** (the required context, unchanged in branch protection:
  `["lint","omarchy","system","devenv-presets","box","install"]`):
  `needs: [gate, system-build, system-vm]`, `if: ${{ !cancelled() }}`, one
  step that fails unless both needs concluded `success`. This is the shape
  #1134 gave the gate, for the reason #1144 measured: a `skipped` required
  check passes the merge gate, so the aggregator must run and fail, never
  skip.

Each half keeps `timeout-minutes: 45` and the per-commit concurrency group
`system` has today (`:1347-1350`), named by job. Measured on the two #1332
timeouts (jobs 117666616240, 117687897155), each half is about 30 minutes on a
bump with no proofs:

| job | steps (minutes, worst of two) | total incl. setup |
|---|---|---|
| `system-build` | disk 2.0, VM closure 3.3, installed 0.9, coexistence 0.7, tools 10.3, pushes 3.9, MicroVM 2.0, options 4.5, budget 2.3 | ~32 |
| `system-vm` | disk 2.0, session 9.8, plugin 5.5, coexist 2.5, wizard 1.4, integration 1.1, the four small ones ~2, closure substitution ~3 | ~29 |

A normal PR (proofs present) stays at today's ~20 minutes wall clock or less,
since the halves run side by side. A timeout now names the half that ran out.

The comments that carry measurements move with their steps. The `timeout-minutes`
comment at `:1310-1317` gains one paragraph: the split exists because a bump
has no proofs (#1341).

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
- **Move only "Build the allowlisted tools" (10 min) out.** It is the
  `hypr-rdp` compile, 447 crates (`:1414-1421`), and `checks.options` needs
  `hypr-rdp` too. Pull requests never push closures, so `options` would compile
  it again in `system-build`. That would save nothing on a PR.
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
- **Disk.** Each half frees disk and downloads its own closures. The VM half
  substitutes the test VMs' closures from cache.nixos.org, about 3 minutes, as
  `system` does today.
- **Docs and references.** `docs/internals/workflows.md`, CLAUDE.md §6 and
  comments name "the `system` job"; the plan greps for them.

## Verification

- `actionlint` on `build.yml`; the workflow guards in `build.yml` itself
  (skipPush, coverage) green on the PR.
- **The aggregator blocks on a red half**, measured, not inferred (§4): on a
  throwaway draft PR with a deliberately failing step in `system-vm`,
  `gh pr view --json mergeStateStatus` reads `BLOCKED`, and `system` reads
  `failure` naming `system-vm`. Then the same with `system-build`.
- **Timing:** the PR's own run shows both halves' durations. The next nightly
  nixpkgs bump finishes both halves without a re-run; the PR records it, and
  #1341 closes on that evidence rather than on merge.
- A maintainer merges (§11).
