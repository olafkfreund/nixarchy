---
status: approved
issue: 1058
author: olafkfreund
---

# Intent: A check does not fail because grep found what it was looking for

## Problem

`checks.manifest-has-kind` failed once on #1054 with "manifestHasKind not
found in …/shell/shell.qml". The function was in that file. `main` passed on
the identical source path seconds earlier, and one re-run of the same
derivation passed.

The cause is in how the check asks the question:

```sh
printf '%s\n' "$fn" | grep -q 'function manifestHasKind' || { echo "FAIL: … not found"; exit 1; }
```

It runs under stdenv's `set -o pipefail`. Measured and demonstrated here, not
guessed:

- **bash's `printf` writes line by line.** strace shows four `write()` calls
  for the four-line extract, and the pattern is on line 1.
- **`grep -q` exits at the first match**, so the writes still pending can hit
  a closed pipe. With a delay forced between two writes, the result is
  deterministic: `PIPESTATUS=141 0`. grep succeeded and the writer died of
  SIGPIPE. `pipefail` turns that into a failed pipeline, and the check prints
  "not found".
- **Whether the window opens depends on scheduling.** 8,000 runs here, some
  pinned to one busy CPU, never failed. A 2-vCPU hosted runner in the middle of
  a parallel `nix build` is the environment that preempts a writer between
  lines.

So the check can report a false "not found" when the thing it looks for is
there and sits early in the input. It is the §1 failure read backwards: a
check that goes red for a reason unrelated to the property. A flaky red costs
a re-run and teaches people to re-run reds (§10).

The same shape, `… | grep -q` with more than one write after the match,
appears about 99 times across this repository. Only some run under `pipefail`
with a multi-write producer.

## Proposed outcome

`checks.manifest-has-kind` can no longer fail because grep matched early. It
still fails, with the same message, when the function is really missing.

The mechanism is written down where somebody writing a check will read it
(`tests/AGENTS.md`), so the next check does not reintroduce it.

## Affected users and systems

- `tests/manifest-has-kind.nix`, and every PR's `omarchy` job that builds it.
- `tests/AGENTS.md`.
- Possibly other checks with the same shape (open question 1).

## Constraints

- The negative control stays. The check must still fail on a shell.qml
  without the function (§1: prove it).
- No change to what the check asserts, only to how it reads its input.
- Do not retry the check to make it pass.

## Open questions

1. **Scope of the sweep.** Fix only this check, which is the one that failed,
   or also the other places where `pipefail` and a multi-write producer meet
   `grep -q`? Default proposal: this check plus the tests/AGENTS.md lesson now,
   and a follow-up issue listing the other occurrences, each checked for
   whether `pipefail` actually applies. Many are `machine.succeed` in VM
   tests, where it may not.
