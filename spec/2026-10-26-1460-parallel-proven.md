---
status: approved
issue: 1460
intent: intent/2026-10-26-1460-parallel-proven.md
---

# Spec: the omarchy job finishes a nixpkgs bump inside its budget

## Design

**`already-proven.sh` evaluates the checks in parallel.** It used to run one
`nix eval` per check, one after another. Each check is now a worker,
`check_one`, that leaves its verdict in a temporary directory. The main loop
then reads the verdicts back in argument order, so the rows on stdout, the
messages on stderr and the counts are exactly what the serial script gave.
The floor (asked about N, accounted for N) and the fallback for a check that
does not evaluate are unchanged.

**Scheduling is by measured memory.** Each of the 157 generated checks was
measured cold on p620:

| check | peak RSS |
|---|---|
| `generate-config-surface` | 11.6 GB |
| `config-warnings` | 5.0 GB |
| median of the rest | 0.16 GB |
| worst four of the rest, together | 12.8 GB |

- **The two heavy checks run first, alone, one after another.** Running
  anything beside them pushed anonymous memory to 15 GB, whether one light
  check was allowed or three.
- **The rest run `PROVEN_JOBS` (4) at a time.**
- **A worker starts only with `PROVEN_MIN_FREE_KB` (4 GB) available,** or
  when nothing is running, so the loop can never stall. A heavy check added
  later then slows the step rather than exhausting the runner.

**`omarchy`'s timeout goes from 45 to 60 minutes,** as margin for the build
half (owner decision 1).

## Measured

Cold, on the same tree, peaks read from the run's cgroup:

| | time | anonymous peak | rows and messages |
|---|---|---|---|
| serial (`main`) | 905 s | 11.6 GB | |
| **this** | **406 s** | **11.6 GB** | identical, same order |
| four-way, no heavy rule | 247 s | 14.9 GB | rejected: too little headroom on a 16 GB runner |
| heavy slot plus one light | 348 s | 15.6 GB | rejected |

## Alternatives rejected

- **One `nix eval` for every check:** `tryEval` does not catch every error
  (§5), so one bad check aborts the batch. Its memory is also the sum, not
  the maximum.
- **Bigger build batches:** no measurement shows a gain (owner decision 2).
- **Split the job:** that needs new required contexts.

## Risks

- **The heavy list is hand-kept.** A new heavy check is caught by the
  memory floor, which slows the step without failing it.
- **Hosted-runner timing is not yet measured.** The first bump run will
  show it.

## Verification

- `checks.proof-push` gains a case with 12 checks, where earlier checks
  finish later. It asserts the rows and messages come back in argument order,
  and that an unmeetable memory floor does not stall the loop. It goes red
  when the read-back is reversed.
- `checks.cache-budget` and `checks.proof-push` stay green.
- actionlint is clean.
