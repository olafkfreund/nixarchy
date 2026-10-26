---
status: draft
issue: 1463
author: x
---

# Intent: checks.options runs as parallel shards, well inside the runner's memory

## Problem

On a nixpkgs bump (#1457, job 121519966539), `checks.options` took 26:44
and peaked at 14,574 MiB of the hosted runner's 16,384. The job warned that
this is within 2 GB of its limit, and past that limit the job ends as
`cancelled` with no failed step (#747). The time went like this:

- **5.5 minutes** evaluating all 174 cases;
- **21 minutes** realising the inputs that the 2,800-line runCommand's
  assertions read. Mostly that is the `vm` toplevel, which `system-build`
  already builds on another runner.

Memory is held by the fixtures that live for the whole evaluation (the
microvm group, and about forty shallow shared fixtures), not by individual
cases.

## Proposed outcome

`checks.options` becomes four checks that run as legs of one parallel job
under the existing `system` aggregator:

- **`options-system`, `options-home`, `options-microvm`:** the cases, cut
  along fixture families;
- **`options-files`:** the file assertions.

Every option is still asserted both ways, with the same report lines. A
cheap guard, `options-shards`, fails if any case is unassigned or assigned
twice.

## Affected users and systems

CI only:

- `tests/options.nix`, `flake.nix`, `generated-checks.sh`;
- `build.yml` (a new job, and the aggregator), `omarchy-edge.yml`;
- the docs that name `checks.options`.

## Constraints

- **Mode A:** every case's off state is still asserted.
- **One list, checked:** a case that falls between shards fails a check, not
  a reviewer's eye (§4).
- **Each shard is shown to fail (§1).** The guard fails three ways locally;
  each leg fails on a throwaway draft PR.
- **Memory is measured per shard while CI is idle (§6),** as cgroup
  anonymous memory (AGENTS.md §6, #1460).
- **This lands after #1466,** which edits `tests/options.nix`.

## Open questions

None. The owner approved it on 2026-10-26: "yes do that".
