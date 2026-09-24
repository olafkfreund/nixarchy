---
status: draft
issue: 979
author: olafkfreund
---

# Intent: a detached rebuild a caller can watch, and only build what it checked

## Problem

`nixarchy-apply --detach` starts the rebuild in a user unit and returns. The
unit outlives a shell restart, which is the point -- and the caller is then
given nothing to hold onto.

**No status, no log.** A caller wanting to show progress or a result has to
know the unit's name and its SubState protocol, and read `systemctl --user
show` and `journalctl` itself. `modules/apps.nix:3376` already encodes that
protocol, with the reasoning at the line:

```
# SubState, not ActiveState: RemainAfterExit keeps a finished
# rebuild "active" (SubState exited) so its result stays readable.
...
# No --collect: it unloads a FAILED unit at once, which then reads
# Result=success -- the one result that matters.
```

So the interface exists; it is just not offered. Every caller re-derives it, and
the trap is in the comment: **a unit that never ran reads `Result=success
ExecMainStatus=0`**, so reading `Result` alone answers "succeeded" for a rebuild
that never happened.

**No pinned input.** Under `--detach` the unit copies
`~/.config/nixarchy/{apps,services,advanced,flatsnap}.nix` into the flake
**after the caller has returned**. A caller that checked a file before starting
cannot hold that check across the copy.

nixarchy-flatsnap#23 (PR #34, merged) works around both on its own side: it
starts the same unit itself, hard-codes the unit name with a comment pointing
here, and reads `SubState,Result,ExecMainStatus,InvocationID` and
`journalctl --invocation=<id>`. That is a downstream repository reimplementing
our internals because we published none.

## Why this matters more than it looks: it supersedes #967

#967 is the same ground -- these files are imported as full NixOS modules, so
whatever writes them as the user writes root configuration -- and the fix I
built for it **shipped tonight and was reverted within the hour** (c7b9aad,
reverted in d9fc8b0).

It refused any changed source file without `--yes`. `checks.options` drives
`nixarchy-apply` non-interactively, changes the selection and runs it again --
the ordinary `omarchy-pkg-add` -> `nixarchy-apply` flow -- and it refused.
`main` went red. The fault was not the boundary; it was **who decides**. A gate
that protects everyone protects nobody usefully, because the callers who cannot
answer are exactly the ones it stops.

**`--expect-sha256 <part>=<sha256>` inverts that, and that is why it works.**
The caller that checked a file passes the hash it saw; the unit refuses if the
file moved under it. A caller that did not ask for the guarantee is not given
one and is not blocked. #979's own text says this *"gives `advanced.nix` and
`apps.nix` the 'build only what was checked' guarantee that #967 asks for"*, and
having built the other shape and watched it fail, I think that is right.

So this issue is the better answer to #967, and #967 should probably close into
it rather than be attempted again on its own.

## Proposed outcome

- A caller can ask for the state of the current or last detached run, and get a
  machine-readable answer that distinguishes **never ran** from **succeeded** --
  which `Result` alone cannot.
- A caller can read that run's log without knowing the unit's name.
- A caller can say "build this only if it is still what I checked", and have the
  unit refuse otherwise.
- The unit name and its SubState protocol become a stated interface, so
  nixarchy-flatsnap can delete its copy and the next panel does not write a
  third.

## Affected users and systems

- `modules/apps.nix` -- the generated `nixarchy-apply`, and nothing else in this
  repository today.
- nixarchy-flatsnap, which is carrying the workaround; nixarchy-pkg and any
  future panel that runs a rebuild.
- Not the interactive user: `--detach` needs `--yes` already and is what the
  menu uses.

## Constraints

- **`--status` must never answer from `Result` alone.** The comment at
  `:3376` records why, and #979 restates it. Any implementation that reads
  `Result` first is wrong in the one case that matters.
- **Do not repeat #967's mistake.** Nothing here may refuse a caller that did
  not opt in. `--expect-sha256` is opt-in by construction; anything added beside
  it must be too.
- **The unit's shape is load-bearing**: `RemainAfterExit`, no `--collect`, no
  `NoNewPrivileges`. Each has a reason written at the line, and a change to the
  interface must not quietly change the unit.
- **Publishing an interface is a promise.** Once flatsnap calls `--status`,
  its output shape cannot drift without breaking another repository.

## Open questions

1. **One issue or three?** `--status`, `--log` and `--expect-sha256` are
   independent, and the third is the one with a user-visible safety story.
   I lean to **splitting `--expect-sha256` out** and doing it first, because it
   is what closes #967, and because the other two are conveniences that can
   follow without anyone waiting on them.

2. **What is the `--status` output?** `--json` is named in the issue. A stable
   JSON object is a promise to a downstream repository; a human-readable default
   is not. I lean to **JSON being the contract and the plain output explicitly
   not one**, said in the help text.

3. **Should #967 be closed into this?** I think yes, and it is your call --
   #967's intent and spec stand, its plan is marked superseded with the fault,
   and this issue's third bullet is the shape that avoids it.

## Not in scope

- Changing what `--detach` does, or the unit's own options.
- nixarchy-flatsnap dropping its workaround, which is its repository's to do
  once this exists (section 11).
