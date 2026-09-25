---
status: draft
issue: 935
author: olafkfreund
---

# Intent: the LUKS wait should not get slower the longer it waits

## Problem

`checks.install-encrypted` never finishes. It is killed at the 90-minute CI cap
having made no progress, and it has failed this way every night it has run.

The guest is innocent. From the 2026-09-25 nightly's serial log, guest uptime
against host wall clock, all inside the initrd:

| wall clock | guest uptime | wall seconds for ~1.5 ms of guest |
|---|---|---|
| 03:20:21 | 1.885565 | - |
| 03:24:26 | 1.888307 | 159 |
| 03:44:30 | 1.891364 | 879 |
| 04:16:56 | 1.892967 | 1946 |

**7 milliseconds of guest time in 56 minutes**, with the cost doubling each
line.

## The mechanism, verified rather than inferred

`wait_for_console_text`, in nixpkgs'
`nixos/lib/test-driver/src/test_driver/machine/__init__.py`:

```python
while True:
    console.write(self.last_lines.get(block=block))   # append ONE line
    console.seek(0)
    matches = re.search(regex, console.read())        # rescan the WHOLE buffer
```

Every arriving line re-reads and re-matches everything received since the wait
began. That is O(n^2) in console output on its own, and the pattern makes each
scan expensive: `tests/install-encrypted.nix:654` builds `assphrase for` with a
kernel-line group between **every character** -- thirteen nested quantifiers.

Then it feeds back. Driver CPU grows with the buffer, starving the qemu on the
same host, so the guest advances more slowly, so the wait continues, so the
buffer grows. That loop is why the slowdown is super-linear; nothing constant
-- TCG, contention, a slow disk -- produces doubling.

**Why only this check**, measured:

| | `console=ttyS0` | `wait_for_console_text` |
|---|---|---|
| `tests/install.nix` | 0 | 0 |
| `tests/install-encrypted.nix` | 5 | 3 |

`install-encrypted` routes all kernel and systemd output to the serial line
(`:113`, and again for the installed target at `:297`) **and** sits in the
rescan loop over it. `install.nix` does neither, and finishes in 2m34s on the
same runner in the same minute. The two qemu invocations are byte-identical,
so the asymmetry is entirely host-side.

## What the fix must not do, and this nearly went wrong

The obvious cheapening -- replace the thirteen nested groups with one loose
quantifier -- is **the design `spec/2026-09-21-834-luks-prompt-race.md` measured
and rejected**:

| pattern | the real split | a clean prompt | decoy, no prompt |
|---|---|---|---|
| `[Pp]assphrase for` | no match | match | safe |
| `.{0,2048}?` joined | match | match | **MATCHES** |
| kernel-line bounded | match | match | safe |

> A false positive here is not a flaky test. It sends the passphrase to
> whatever is listening, with nothing having asked for it.

The pattern's boundedness **is** the safety property, and `install-encrypted`
already carries a `DECOY` assertion whose whole job is to fail if someone
"simplifies" it. I proposed exactly that simplification an hour ago, before
reading #834's spec. It would have passed every test in the file except the one
written to catch it.

So: **the regex is not the thing to change.** The buffer is.

## Proposed outcome

- The wait's cost per arriving line is constant rather than growing, so the
  guest runs at normal speed and the check finishes.
- The split-prompt tolerance #834 established is unchanged, and its `DECOY`
  and `SPLIT` assertions still hold.
- `console=ttyS0` stays: #834's spec says dropping it "throws away the stage-1
  output this test most needs on the day it genuinely fails".

## Affected users and systems

- `checks.install-encrypted`, which has never passed in this configuration.
- The nightly, whose `report` job depends on it.
- Nothing a user runs. This is test-harness cost, not shipped behaviour.

## Constraints

- **Do not touch the pattern.** See above.
- **Any bound must be far larger than a split prompt.** The `SPLIT` fixture in
  the file is roughly 200 characters; a bound in the tens of kilobytes has
  three orders of magnitude of margin, and the bound must be justified against
  that fixture rather than picked.
- **`wait_for_console_text` is nixpkgs', not ours.** A fix here cannot patch
  the driver; it has to work with it -- or the test stops using that helper.
- Section 1: whatever is written must be seen failing. A performance fix is
  the easy thing to declare done without evidence.

## Open questions

1. **Where does the bound live?** Three shapes:
   - **Stop using `wait_for_console_text`** and poll `get_console_log()`'s tail
     ourselves, matching a bounded window. Most control, most code, and it
     leaves the helper's semantics behind.
   - **Wait in stages** -- a cheap `wait_for_console_text` on something that
     appears just before the prompt, then the expensive pattern over the short
     window after it. Keeps the helper; the buffer resets between calls.
   - **Send it upstream.** The quadratic is nixpkgs' and everyone waiting on a
     chatty console pays it. Not ours to file unprompted (section 11), and too
     slow to unblock this check.

   I lean to **staged waits**: it uses the helper as designed, the second wait's
   buffer holds only what arrived after the first matched, and it needs no
   understanding of the driver's internals to stay correct.

2. **Is there a cheap pre-prompt marker?** The staged shape needs one. Stage 1
   emits plenty before the passphrase, but it has to be something that cannot
   appear on a successful boot *after* the prompt, or the second wait starts
   too late. To establish before the spec.

## Not in scope

- The nightly's job structure (#937 already split the chains; it is not this).
- `checks.install`, which does not use the console matcher at all.
- Any change to what the installer does with encryption.
