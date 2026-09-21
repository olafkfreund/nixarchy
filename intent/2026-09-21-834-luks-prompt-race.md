---
status: draft
issue: 834
author: olafkfreund
---

# Intent: the LUKS check reads a prompt the kernel is talking over

Closes #834.

## Problem

`checks.install-encrypted` installs onto an encrypted disk, boots the target,
and answers the LUKS passphrase on the serial console:

```python
target.wait_for_console_text(r"[Pp]assphrase for", timeout=600)
target.send_console("${luksPassphrase}\n")
```

On 2026-09-21 it spent the full 600 seconds beside a prompt that was on screen
the whole time. From the run's own log:

```
target # [ 2.728291] systemd-tty-ask-password-agent[161]: Starting password query on /dev/ttyS0.
target # Please enter pas[    2.948528] scsi 1:0:0:0: CD-ROM  QEMU  QEMU DVD-ROM  2.5+ PQ: 0 ANSI: 5
target # sphrase for disk disk-main-root (cryptroot): (press TAB for no echo)
```

A kernel message landed **inside the word "passphrase"**. The bytes
`passphrase for` never occur contiguously, so the pattern cannot match. The
prompt appeared at 2.9 s; everything after that was the test waiting beside it.

The `clocksource: Watchdog remote CPU 1 read timed out` at 203 s is the guest
idling at an unanswered prompt, not starvation — worth saying, because it is
the line that invites a wrong diagnosis.

### Why it is intermittent, and why that makes it worse

It is a race between one `printk` and one write to the same tty. The nightly
passed on 09-19 and failed on 09-21 with no change to the test. `loglevel=7` —
the loudest setting — is on the target's kernel command line, so every kernel
message competes with the prompt for `ttyS0`.

An intermittent failure in a nightly VM check is expensive out of proportion to
its rarity: it costs a 600-second timeout, it looks like a real encryption
regression, and the next person re-runs it and sees green, which teaches
everyone that the check is flaky rather than that the matcher is wrong.

### The shape of the mistake

`tests/install-encrypted.nix:640` already tolerates *two* spellings, because
stage 1 has two implementations:

```
# implementations: scripted prints "Passphrase for <device>", systemd
# prints "Please enter passphrase for disk ...".
```

What it does not tolerate is one of them being **split**, and no pattern over a
fixed string can: an interleaving `printk` can land between any two characters.
Widening the alternation moves which collisions survive rather than removing
them. This is AGENTS.md §1's green light — a pattern that happens to dodge
today's split reads as coverage.

## Outcome

- The check answers the prompt when the prompt appears, whatever the kernel
  writes through the middle of it.
- It still **only types after seeing the prompt**. A passphrase sent blind, on
  a timer or a retry loop, would be typed into whatever is listening — and the
  guard that makes that safe is prompt detection again, so it is not an escape
  from the problem.
- The failure stays **loud**: if the prompt never appears, the check fails
  saying so. It must not become a hang, and it must not become a pass.
- The fix is provable **without a VM**. The captured transcript above is the
  fixture: the new matcher must match it, and the old one must not. That pair
  runs in milliseconds, where reproducing the race in a VM cannot be done on
  demand at all.

## Affected

- `tests/install-encrypted.nix` — the matcher, and a fixture asserting both
  directions
- possibly `tests/AGENTS.md`, if the lesson generalises beyond this check

Nothing outside the test changes. The installed system, the kernel command
line and the password agent stay as they are.

## Constraints

- **No new check, no new workflow entry.** This is one assertion inside a check
  that already runs nightly.
- **`loglevel` stays.** Lowering it would reduce the probability of a collision
  without removing it, and would throw away the stage-1 output this test most
  needs on the day it genuinely fails. A quieter console is not a fix, it is a
  smaller target.
- **The end-to-end proof stays.** Reaching `multi-user.target` and mounting `/`
  from the mapped LUKS device is what makes the prompt real; the matcher change
  must not weaken that.
- AGENTS.md §1: the break must be made deliberately and its output captured. A
  race satisfies this only if the fixture is the transcript, not the VM.

## Open questions

1. **How much interleaving should the pattern tolerate?** An independent review
   (Codex, consulted on this issue at the maintainer's request) proposed
   joining the escaped characters with `.{0,2048}?`. That matches the phrase
   spread across two kilobytes of unrelated output, which is far more tolerance
   than the observed failure needs and starts to risk matching something that
   is not the prompt. The bound is a decision for the spec, with the observed
   split — about 90 characters of kernel message — as the evidence.
2. **Tolerate a split anywhere, or only where one is plausible?** A `printk`
   interleaves at a write boundary, not uniformly between every character.
3. **Does this belong only to this check?** `wait_for_console_text` is used
   elsewhere in the suite against strings printed while the kernel is loud. If
   the answer is a helper rather than one pattern, that is a different change
   and possibly a different issue.
4. **Should the fixture assert the old pattern fails?** It documents the bug in
   the file that fixes it, and makes the regression test self-explaining — but
   it also pins a pattern nobody will use again.

## Rejected before writing this

- **Send the passphrase on a retry loop.** It escapes the matcher only by
  giving up the guarantee that we typed at a prompt.
- **Quiet the console.** See Constraints.
- **A second serial device**, so the prompt and `printk` do not share a
  console. Attractive, and rejected: making it honest means separating kernel
  console routing from the stage-1 password agent's tty, which is initrd
  plumbing for a bug that is simply "console bytes are not atomic".
