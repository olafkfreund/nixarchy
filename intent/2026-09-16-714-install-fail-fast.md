---
status: approved
issue: 714
author: olafkfreund
---

# Intent: a failed install check fails in minutes, not at the 90-minute cap

## Problem

When an assertion fails in one of the install-class checks, the job does not
end. It runs on until `install-check.yml`'s `timeout-minutes: 90` and reports
`cancelled`, which reads as an eviction rather than a failure (AGENTS.md §6).

Measured on run 35025579251 (PR #711, a deliberate failure):

- 21:39:16 the assertion fails, with the answer we wanted;
- 21:39–22:01 the target VM is still running — snapper timers, tmpfiles
  cleanup, kernel messages every few minutes;
- 22:58 the job hits its cap and is cancelled.

**79 minutes after the answer was known.**

**Why.** These checks boot the installed disk as a second VM with
`create_machine`. The driver does not add such a machine to `self.machines`, so
neither its cleanup (`Driver.__exit__` → `machine.release()`) nor its own
`globalTimeout` handler (`terminate_test`, which iterates the same list)
touches it. The surviving qemu keeps the builder's process group alive, and Nix
waits.

`tests/install.nix` already half-knows this: at line 1051 it says
"create_machine is not reaped for us the way a declared node is" and calls
`target.shutdown()` — but only on the success path. An assertion that fires
before that line skips it.

Six checks create machines this way: `install`, `free-space`,
`install-encrypted`, `install-iso`, `install-iso-net`, `reinstall-vm`.

## Proposed outcome

- **A failed install-class check ends promptly** — the job reports `failure`
  with a failed step, not `cancelled` at the cap.
- **The slot is returned.** A real failure costs about 25 minutes rather than
  90, on a host with two install slots that every merge queues behind.
- **The failure stays readable:** the assertion text remains the last thing in
  the log.
- **A check proves it**, rather than the next accidental failure being the test.

## Affected users and systems

- Everyone waiting on CI; today this cost about four hours of slot time across
  #711, #712, #715 and #719.
- `tests/install.nix`, `free-space.nix`, `install-encrypted.nix`,
  `install-iso.nix`, `install-iso-net.nix`, `reinstall-vm.nix`.
- No workflow change: `timeout-minutes` stays where it is, and stays a CI gate
  a human owns (AGENTS.md §11).

## Constraints

- **Ours to fix, not upstream's.** The driver's behaviour is documented and
  consistent; what is missing is our cleanup around a machine we created.
- **No change to `globalTimeout` or `timeout-minutes`** as the fix. Both are
  backstops; a backstop firing is not a failure path worth designing around.
- **Seen red first** (§1): the check must fail against today's tests.
- **The evidence must survive.** Whatever runs on failure must not truncate or
  swallow the assertion, which is the thing the run exists to produce.

## Open questions

Resolved at approval:

1. **A `try`/`finally` at the point of use**, not a shared helper: a helper
   would have to own machine creation to own its cleanup.
2. **One local measurement**, recorded in the PR, plus a cheap check that the
   cleanup is on the failure path. No install slot is spent.
